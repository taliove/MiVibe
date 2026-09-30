import Foundation
import IOKit.hid

/// 遥控器实体按键读取（SPEC §2）。
///
/// 始终以**非独占**方式打开 IOHIDManager 读取原始 usage；两种模式的差别在系统那一侧：
/// - **仅监听**（默认）：系统照常处理这些标准 HID 键盘事件，这里只是旁听，
///   用于返回键取消等动作。
/// - **接管**（`takeover: true`）：对遥控器的事件服务写入按设备重映射
///   （`RemoteKeyRemapper`），把它的键映射成死键，系统不再响应；所有按键经
///   `KeyRouter` 裁决后由 `KeySynth` 重新发出。
///
/// 为什么不用 `kIOHIDOptionsTypeSeizeDevice`：遥控器是键盘类设备，IOHIDFamily 只许
/// root 或带 Apple 私有授权的进程独占键盘，普通进程恒得 0xE00002C1（与输入监控无关）。
///
/// 重映射是**持续维护**的：BLE 遥控器连接晚于 App 启动是常态，事件服务随重连重建，
/// 所以设备每次出现（匹配回调）都重新写入；服务比设备回调晚到时短暂重试。
/// 监听打不开时绝不写重映射——否则系统不响应、MiVibe 又收不到，遥控器彻底失灵。
public final class KeyReader {
    public static let vendorID = 0x2717
    public static let productID = 0x32B8

    /// 设备出现而事件服务尚未就绪时的重试节奏。
    private static let remapRetryDelay: TimeInterval = 0.5
    private static let remapRetryLimit = 10

    /// 实测确认的按键。身份定义在 `RemoteButton`（纯逻辑，可脱离硬件测试）——
    /// 这里只做别名，`KeyReader.Key.up` 这样的写法继续可用。
    public typealias Key = RemoteButton

    /// 按下/抬起回调。主线程投递。第三参是 isRepeat：同一个键没抬起就再次按下。
    /// 实测本机遥控器不自动重复（按住语音键 1.95 秒只有一对 down/up），
    /// 这个标记是防御性的——路由层靠它保证 ⌘Z 不会连发。
    public var onKey: (@MainActor (Key, Bool, Bool) -> Void)?

    /// 接管状态变化回调（生效/失效时触发，参数为是否已接管）。
    public var onExclusiveChanged: (@MainActor (Bool) -> Void)?

    /// 接管失败回调：监听打不开或重映射被拒时触发，
    /// 同一次 `start` 内相同原因只报一次（设备反复出现不刷屏）。
    public var onTakeoverFailed: (@MainActor (TakeoverFailure) -> Void)?

    /// 最近一次接管失败的原因；接管生效或 `stop` 后清空。
    /// 调用方据此判断重试有没有意义（见 `TakeoverFailure.isRetryable`）。
    public private(set) var lastFailure: TakeoverFailure?

    /// 接管是否生效：系统已不再处理遥控器的原生按键（重映射在位）。false 时系统
    /// 仍在处理，调用方绝不能自行合成/转发，否则每个键都会发生两次。
    /// 名字沿用独占时代，语义不变。
    public private(set) var isExclusive = false

    private var manager: IOHIDManager?
    private let remapper = RemoteKeyRemapper(vendorID: KeyReader.vendorID, productID: KeyReader.productID)
    /// 用户意图：要不要接管。与实际是否生效（`isExclusive`）分开——
    /// 设备迟到、服务未就绪都是暂时的，意图不变，持续维护。
    private var wantExclusive = false
    /// 监听是否打开成功。失败时不写重映射（见类型注释）。
    private var listening = false
    /// 每次 `start` / `stop` 递增，让过期的延迟重试自行作废。
    private var generation = 0
    /// 当前按住的键：同一个键未抬起又收到按下 → isRepeat。
    private var held: Set<RemoteButton> = []

    public init() {}

    public func start(takeover: Bool = false) {
        guard manager == nil else { return }
        wantExclusive = takeover
        generation += 1
        held.removeAll()
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(hid, [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(hid, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let reader = Unmanaged<KeyReader>.fromOpaque(context).takeUnretainedValue()
            reader.handle(value)
        }, context)

        // BLE 遥控器的断开重连是日常（SPEC §3）：设备每次出现都重写重映射。
        IOHIDManagerRegisterDeviceMatchingCallback(hid, { context, _, _, _ in
            guard let context else { return }
            let reader = Unmanaged<KeyReader>.fromOpaque(context).takeUnretainedValue()
            reader.deviceAppeared()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hid, { context, _, _, _ in
            guard let context else { return }
            let reader = Unmanaged<KeyReader>.fromOpaque(context).takeUnretainedValue()
            reader.deviceRemoved()
        }, context)

        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        manager = hid

        let status = IOHIDManagerOpen(hid, 0)
        listening = status == kIOReturnSuccess
        if !listening {
            Log.chain.error("HID listen open failed")
            if takeover { reportFailure(TakeoverFailure(status: status)) }
        }

        if takeover && listening {
            applyRemap(attempt: 0)
        } else {
            // 不接管（或监听不可用）：清掉上次崩溃可能遗留的重映射，把按键还给系统。
            let result = remapper.remove()
            if result.services > 0 && result.succeeded < result.services {
                Log.chain.error("stale remap cleanup incomplete (\(result.succeeded)/\(result.services))")
            }
        }
    }

    public func stop() {
        guard let manager else { return }
        generation += 1
        if wantExclusive {
            let result = remapper.remove()
            Log.chain.notice("remap removed (\(result.succeeded)/\(result.services))")
        }
        IOHIDManagerClose(manager, 0)
        self.manager = nil
        wantExclusive = false
        listening = false
        held.removeAll()
        lastFailure = nil
        setExclusive(false)
    }

    // MARK: - 重映射维护

    private func deviceAppeared() {
        guard wantExclusive, listening else { return }
        applyRemap(attempt: 0)
    }

    private func deviceRemoved() {
        let remaining = (manager.flatMap { IOHIDManagerCopyDevices($0) } as? Set<IOHIDDevice>)?.count ?? 0
        if remaining == 0 { setExclusive(false) }
    }

    /// 写入重映射。事件服务可能比设备匹配回调晚到，找不到服务时短暂重试。
    private func applyRemap(attempt: Int) {
        guard wantExclusive, listening else { return }
        let result = remapper.apply()
        if result.succeeded > 0 {
            if result.succeeded < result.services {
                Log.chain.error("remap applied partially (\(result.succeeded)/\(result.services))")
            }
            Log.chain.notice("remap applied (\(result.succeeded)/\(result.services))")
            setExclusive(true)
        } else if result.services > 0 {
            reportFailure(.remapRejected)
        } else if attempt < Self.remapRetryLimit {
            let token = generation
            // KeyReader 只在主线程使用（HID 回调挂在主 run loop），延迟块也投递回主队列。
            nonisolated(unsafe) weak var reader = self
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.remapRetryDelay) {
                guard let reader, reader.generation == token else { return }
                reader.applyRemap(attempt: attempt + 1)
            }
        }
    }

    private func reportFailure(_ failure: TakeoverFailure) {
        Log.chain.error("takeover failed: \(failure.reason, privacy: .public)")
        guard failure != lastFailure else { return }
        lastFailure = failure
        Task { @MainActor [onTakeoverFailed] in onTakeoverFailed?(failure) }
    }

    private func setExclusive(_ now: Bool) {
        guard now != isExclusive else { return }
        isExclusive = now
        if now { lastFailure = nil }
        // 抬起没到就切换模式时，残留的按住状态会让下一次按下被误判为重复。
        held.removeAll()
        Log.chain.notice("takeover now \(now ? "active" : "inactive", privacy: .public)")
        let value = now
        Task { @MainActor [onExclusiveChanged] in onExclusiveChanged?(value) }
    }

    // MARK: - 按键事件

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == 0x07 else { return }
        let usage = IOHIDElementGetUsage(element)
        // 0xFFFFFFFF 是数组占位元素，不是实体按键（实测）。
        guard usage != 0xFFFF_FFFF, let key = Key(rawValue: usage) else { return }

        let isDown = IOHIDValueGetIntegerValue(value) != 0
        let isRepeat: Bool
        if isDown {
            isRepeat = held.contains(key)
            held.insert(key)
        } else {
            isRepeat = false
            held.remove(key)
        }
        // 回调已标注 @MainActor：HID 回调虽在主 run loop 上触发，
        // 仍显式跳一次以满足并发检查。
        Task { @MainActor [onKey] in onKey?(key, isDown, isRepeat) }
    }
}
