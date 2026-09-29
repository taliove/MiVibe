/// 前进 / 后退导航历史（设置窗口工具栏导航的数据源）。
///
/// 纯值类型，与 UI 无关：当前项之外各持一个后退栈与前进栈。`visit` 访问新项
/// （与当前项相同则无操作）会压栈并清空前进栈；`goBack` / `goForward` 在两栈
/// 之间移动当前项。历史长度有上限（`capacity`），超出时丢弃最旧的回退项。
public struct NavigationHistory<Item: Equatable & Sendable>: Equatable, Sendable {
    /// 历史总容量（含当前项）。超出时丢弃最旧的回退项。
    /// 泛型类型不能有静态存储属性，故用计算属性。
    public static var capacity: Int { 50 }

    public private(set) var current: Item
    private var backStack: [Item]
    private var forwardStack: [Item]

    public init(initial: Item) {
        current = initial
        backStack = []
        forwardStack = []
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// 访问新项：与 current 相同则什么都不做；否则压栈并清空前进栈。
    public mutating func visit(_ item: Item) {
        guard item != current else { return }
        backStack.append(current)
        if backStack.count >= Self.capacity {
            backStack.removeFirst(backStack.count - Self.capacity + 1)
        }
        forwardStack.removeAll()
        current = item
    }

    /// 返回新的 current；无可回退时返回 nil 且状态不变。
    @discardableResult
    public mutating func goBack() -> Item? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return current
    }

    /// 返回新的 current；无可前进时返回 nil 且状态不变。
    @discardableResult
    public mutating func goForward() -> Item? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return current
    }
}
