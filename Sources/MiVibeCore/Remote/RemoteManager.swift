import CoreBluetooth
import Foundation

/// 遥控器 BLE 语音会话（SPEC §2，ATVV 1.0）。
///
/// 关键约束，全部来自真机实测：
/// - **音频受物理门控**：只有语音键被按住时音频才流出。应用发 MIC_OPEN 能开会话
///   但拿不到帧，所以录音会话一律以设备自发的 `AUDIO_START` 为准。
/// - **以 `AUDIO_STOP` 收口**，不以 HID 松开截断——松手后仍有尾帧在途。
/// - 固件 2671 首连可能返回非标准 GET_CAPS 响应，须由 `AUDIO_START` 的 codec=2 二次确认。
/// - 应用主动断开后重连可靠，进程被杀后立即重连即可恢复，**不需要退避**。
/// - 已绑定且已连上系统的遥控器**扫描不到**（不再发可发现广播），只能靠
///   `retrieveConnectedPeripherals` 拿到；休眠断开后被按键唤醒时系统会自动重连，
///   所以搜索期间必须持续轮询它，不能只在进入搜索那一刻查一次。
public final class RemoteManager: NSObject {
    // MARK: - 协议常量

    // CBUUID 不是 Sendable，用计算属性避开全局可变状态检查。
    public static var serviceUUID: CBUUID { CBUUID(string: "AB5E0001-5A21-4F05-BC7D-AF01F617B664") }
    private static let txPrefix = "AB5E0002"
    private static let audioPrefix = "AB5E0003"
    private static let controlPrefix = "AB5E0004"

    private static let getCaps: [UInt8] = [0x0A, 0x01, 0x00, 0x00, 0x03, 0x03]
    private static let expectedCodec: UInt8 = 2   // 16 kHz ADPCM
    private static let expectedFrameBytes = 120
    /// 搜索期间轮询系统已连接设备的间隔。
    private static let reacquireInterval: TimeInterval = 2

    public enum State: Equatable {
        case bluetoothUnavailable
        case searching
        case connecting
        case negotiating
        case ready
        case recording
    }

    /// 一次完整录音的产物。PCM 已解码为 16 kHz 单声道 pcm_s16le。
    public struct Recording {
        public let pcm: Data
        public let frameCount: Int
        public let duration: TimeInterval
    }

    // MARK: - 回调

    public var onStateChange: ((State) -> Void)?
    /// 设备自发开始录音（用户按住了语音键）。
    public var onRecordingStart: (() -> Void)?
    /// 录音结束（收到 AUDIO_STOP），交付解码后的 PCM。
    public var onRecordingFinish: ((Recording) -> Void)?
    /// 边收边给的增量 PCM，供流式上传。
    public var onAudioChunk: ((Data) -> Void)?

    public private(set) var state: State = .bluetoothUnavailable {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    // MARK: - 内部状态

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var tx: CBCharacteristic?
    private var audio: CBCharacteristic?
    private var control: CBCharacteristic?
    private var capsRequested = false
    private var reacquireTimer: Timer?

    private var adpcmState = ADPCM.State()
    private var pcmBuffer = Data()
    private var frameCount = 0
    private var recordingStart: TimeInterval = 0
    private var streamID: UInt8 = 0

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - 连接

    public func connect() {
        guard central.state == .poweredOn else { return }
        // 已连接的设备走 retrieve，未连接才扫描；扫描同时轮询 retrieve，
        // 接住之后才被系统重连上的设备。
        if let match = connectedRemote() {
            attach(match)
        } else {
            state = .searching
            central.scanForPeripherals(withServices: [Self.serviceUUID])
            startReacquire()
        }
    }

    public func disconnect() {
        stopReacquire()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        reset()
    }

    private func connectedRemote() -> CBPeripheral? {
        central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
            .first(where: { ($0.name ?? "").contains("小米") })
    }

    private func startReacquire() {
        guard reacquireTimer == nil else { return }
        // target/selector 形式避开 @Sendable 闭包捕获；.common 模式保证菜单展开时照常触发。
        let timer = Timer(
            timeInterval: Self.reacquireInterval,
            target: self,
            selector: #selector(reacquireTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        reacquireTimer = timer
    }

    private func stopReacquire() {
        reacquireTimer?.invalidate()
        reacquireTimer = nil
    }

    @objc private func reacquireTick() {
        guard state == .searching, peripheral == nil, central.state == .poweredOn else {
            stopReacquire()
            return
        }
        guard let match = connectedRemote() else { return }
        Log.chain.notice("remote reacquired from system-connected peripherals")
        attach(match)
    }

    private func attach(_ device: CBPeripheral) {
        guard peripheral == nil else { return }
        central.stopScan()
        stopReacquire()
        peripheral = device
        device.delegate = self
        state = .connecting
        central.connect(device)
    }

    private func reset() {
        peripheral = nil
        tx = nil
        audio = nil
        control = nil
        capsRequested = false
        pcmBuffer.removeAll()
        frameCount = 0
        adpcmState = ADPCM.State()
    }

    private func write(_ bytes: [UInt8]) {
        guard let peripheral, let tx else { return }
        let type: CBCharacteristicWriteType = tx.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(bytes), for: tx, type: type)
    }
}

// MARK: - CBCentralManagerDelegate

extension RemoteManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connect()
        } else {
            stopReacquire()
            state = .bluetoothUnavailable
            reset()
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard (peripheral.name ?? "").contains("小米") else { return }
        attach(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .negotiating
        peripheral.discoverServices([Self.serviceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        reset()
        state = .searching
        connect()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        reset()
        // 无退避：实测立即重连即可恢复。
        state = .searching
        connect()
    }
}

// MARK: - CBPeripheralDelegate

extension RemoteManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return }
        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid.uuidString
            if uuid.hasPrefix(Self.txPrefix) {
                tx = characteristic
            } else if uuid.hasPrefix(Self.audioPrefix) {
                audio = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if uuid.hasPrefix(Self.controlPrefix) {
                control = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        // 两路通知都就绪后才协商能力。
        guard audio?.isNotifying == true, control?.isNotifying == true, !capsRequested else { return }
        capsRequested = true
        write(Self.getCaps)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }

        if characteristic.uuid.uuidString.hasPrefix(Self.audioPrefix) {
            handleAudio(data)
        } else {
            handleControl([UInt8](data))
        }
    }

    // MARK: - 控制帧

    private func handleControl(_ bytes: [UInt8]) {
        switch bytes[0] {
        case 0x0B:  // GET_CAPS 响应
            // 固件 2671 存在非标准布局，此处不据此判定 codec，
            // 一律等 AUDIO_START 的 codec 字段二次确认。
            state = .ready

        case 0x04:  // AUDIO_START：设备自发，意味着用户按住了语音键
            guard bytes.count >= 4, bytes[2] == Self.expectedCodec else { return }
            streamID = bytes[3]
            beginRecording()

        case 0x0A where state == .recording:  // SYNC：重置解码器状态
            guard bytes.count >= 7, bytes[6] <= 88 else { return }
            let predictor = Int32(Int16(bitPattern: UInt16(bytes[4]) << 8 | UInt16(bytes[5])))
            adpcmState = ADPCM.State(predictor: predictor, index: Int32(bytes[6]))

        case 0x00 where state == .recording:  // AUDIO_STOP：录音的唯一收口标志
            finishRecording()

        default:
            break
        }
    }

    private func beginRecording() {
        pcmBuffer.removeAll()
        frameCount = 0
        adpcmState = ADPCM.State()
        recordingStart = ProcessInfo.processInfo.systemUptime
        state = .recording
        onRecordingStart?()
    }

    private func handleAudio(_ data: Data) {
        guard state == .recording else { return }  // AUDIO_START 之前的帧不要
        let (pcm, next) = ADPCM.decode(data, state: adpcmState)
        adpcmState = next
        pcmBuffer.append(pcm)
        frameCount += 1
        onAudioChunk?(pcm)
    }

    private func finishRecording() {
        let recording = Recording(
            pcm: pcmBuffer,
            frameCount: frameCount,
            duration: ProcessInfo.processInfo.systemUptime - recordingStart
        )
        state = .ready
        pcmBuffer.removeAll()
        frameCount = 0
        onRecordingFinish?(recording)
    }
}
