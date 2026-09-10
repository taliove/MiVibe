import Cocoa
import CoreBluetooth
import Darwin

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var manager: CBCentralManager!
    var peripheral: CBPeripheral?
    let service = CBUUID(string: "AB5E0001-5A21-4F05-BC7D-AF01F617B664")
    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("BLUETOOTH_STATE=\(central.state.rawValue)")
        guard central.state == .poweredOn else { return }
        let known = central.retrieveConnectedPeripherals(withServices: [service])
        let matches = known.filter { ($0.name ?? "").contains("小米") }
        print("ATVV_CONNECTED_XIAOMI=\(matches.count)")
        if matches.count == 1 { connect(matches[0]) }
        else if matches.isEmpty { central.scanForPeripherals(withServices: [service]) }
        else { print("AMBIGUOUS_DEVICE; no connection attempted") }
    }
    func connect(_ p: CBPeripheral) {
        guard peripheral == nil else { return }
        peripheral = p
        manager.stopScan()
        p.delegate = self
        print("CONNECTING_XIAOMI")
        manager.connect(p)
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard (p.name ?? "").contains("小米") else { return }
        connect(p)
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        print("CONNECTED; discovering ATVV only")
        p.discoverServices([service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { print("CONNECT_FAILED=\(String(describing:error))") }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { print("SERVICE_ERROR=\(error)"); return }
        for s in p.services ?? [] {
            print("SERVICE=\(s.uuid)")
            p.discoverCharacteristics(nil, for: s)
        }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        if let error { print("CHARACTERISTIC_ERROR=\(error)"); return }
        for c in s.characteristics ?? [] { print("CHARACTERISTIC=\(c.uuid) PROPERTIES=\(c.properties.rawValue)") }
        print("DISCOVERY_COMPLETE; no notifications, writes or audio capture")
        finish()
    }
    func finish() {
        manager.stopScan()
        if let peripheral { manager.cancelPeripheralConnection(peripheral) }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { NSApplication.shared.terminate(nil) }
    }
}
setbuf(stdout,nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let probe = Probe()
DispatchQueue.main.asyncAfter(deadline:.now()+60) { print("DISCOVERY_TIMEOUT"); probe.finish() }
app.run()
