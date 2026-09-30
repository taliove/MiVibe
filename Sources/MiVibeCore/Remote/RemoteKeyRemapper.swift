import Foundation
import IOKit.hid
import IOKit.hidsystem

/// 遥控器按设备重映射的系统边界：读写其 HID 事件服务的 `UserKeyMapping`。
///
/// 条目怎么算在 `RemoteKeyRemap`（纯逻辑）；这里只做 IOHIDEventSystemClient 的读、写、
/// 读回校验。非 root 可写（`--probe-remap` 实测）。映射挂在事件服务上，服务随 BLE
/// 重连重建，所以调用方要在设备每次出现时重新 `apply`。
public final class RemoteKeyRemapper {
    private let vendorID: Int
    private let productID: Int
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

    private var mappingKey: CFString { kIOHIDUserKeyUsageMapKey as CFString }
    private let srcKey = kIOHIDKeyboardModifierMappingSrcKey
    private let dstKey = kIOHIDKeyboardModifierMappingDstKey

    public init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }

    public struct Result: Equatable, Sendable {
        /// 匹配到的事件服务数。0 表示服务还没出现（设备刚连上时常见），稍后重试。
        public let services: Int
        /// 写入且读回一致的服务数。
        public let succeeded: Int
    }

    /// 写入接管条目。
    @discardableResult
    public func apply() -> Result {
        update { RemoteKeyRemap.applying(to: $0) } verify: { RemoteKeyRemap.isApplied($0) }
    }

    /// 撤销接管条目（无状态，也用于清理上次崩溃的残留）。
    @discardableResult
    public func remove() -> Result {
        update { RemoteKeyRemap.removing(from: $0) } verify: { !RemoteKeyRemap.isApplied($0) }
    }

    // MARK: - 实现

    private func update(_ transform: ([KeyUsageMapping]) -> [KeyUsageMapping],
                        verify: ([KeyUsageMapping]) -> Bool) -> Result {
        let services = matchingServices()
        var succeeded = 0
        for service in services {
            let current = read(service)
            let next = transform(current)
            if next != current {
                guard IOHIDServiceClientSetProperty(service, mappingKey, encode(next)) else { continue }
            }
            if verify(read(service)) { succeeded += 1 }
        }
        return Result(services: services.count, succeeded: succeeded)
    }

    private func matchingServices() -> [IOHIDServiceClient] {
        guard let all = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return all.filter { service in
            intProperty(service, kIOHIDVendorIDKey) == vendorID
                && intProperty(service, kIOHIDProductIDKey) == productID
        }
    }

    private func intProperty(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue
    }

    /// 属性不存在时是 nil，清空后是空数组，两者都视为无条目。
    private func read(_ service: IOHIDServiceClient) -> [KeyUsageMapping] {
        guard let raw = IOHIDServiceClientCopyProperty(service, mappingKey) as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let src = (entry[srcKey] as? NSNumber)?.uint64Value,
                  let dst = (entry[dstKey] as? NSNumber)?.uint64Value else { return nil }
            return KeyUsageMapping(src: src, dst: dst)
        }
    }

    private func encode(_ mappings: [KeyUsageMapping]) -> CFArray {
        mappings.map { [srcKey: NSNumber(value: $0.src), dstKey: NSNumber(value: $0.dst)] } as CFArray
    }
}
