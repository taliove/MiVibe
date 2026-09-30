import MiVibeCore

/// 按键提示的外推（issue #2）：文案由 `KeyHint.make`（纯逻辑）按该次路由判定推出，
/// 这里只负责开关与转交。显示由 AppDelegate 持有的 `KeyHintPanelController` 完成，
/// 解耦方向与 `onAudioLevel` / `onPickerConfirmFlash` 一致。
extension Coordinator {
    /// 在执行判定**之前**调用：`picker` 反映按键发生前的状态，所以打开选单的那次
    /// 菜单键照常出提示，选单打开期间的按键不出提示。
    func emitKeyHint(_ key: RemoteButton, isDown: Bool, isRepeat: Bool, route: KeyHint.Route) {
        guard keyHints else { return }
        if let hint = KeyHint.make(button: key, isDown: isDown, isRepeat: isRepeat,
                                   route: route, pickerOpen: picker != nil) {
            onKeyHint?(hint)
        } else if isDown, isRepeat, picker == nil {
            // 映射键按住连发被吞掉：提示不换字，只续命（代码审查：按住途中不该淡出）。
            onKeyHintKeepAlive?()
        }
    }
}
