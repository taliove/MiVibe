import MiVibeCore
import SwiftUI

/// 「全部按键」列表：11 个可映射键各一行——图标、键名、当前绑定文本，
/// 应用作用范围下加来源胶囊（继承 / 覆盖）。点行即选中到右侧编辑卡。
struct KeyMappingAllKeysList: View {
    @ObservedObject var coordinator: Coordinator
    let scope: String?
    @Binding var selectedButton: RemoteButton?

    /// 当前作用范围实际生效的映射表（显示绑定文本用）。
    private var effectiveMapping: AppMapping {
        coordinator.keyMap.mapping(forBundleID: scope)
    }

    var body: some View {
        SettingsGroup(title: "全部按键",
                      footer: scope == nil
                      ? "未映射的键保持系统原生行为。"
                      : "「继承」跟随默认映射，「覆盖」是该应用自己的绑定；清除覆盖即回到继承。") {
            ForEach(Array(RemoteButton.mappable.enumerated()), id: \.element) { index, button in
                if index != 0 { RowDivider() }
                row(button)
            }
        }
    }

    private func row(_ button: RemoteButton) -> some View {
        let source = coordinator.keyMap.bindingSource(of: button, forBundleID: scope)
        let isSelected = selectedButton == button
        return Button {
            selectedButton = button
        } label: {
            HStack(spacing: Spacing.intra) {
                Image(systemName: KeyMappingSelectedCard.icon(for: button))
                    .foregroundStyle(Color.brandAccent)
                    .frame(width: 20)
                Text(button.displayName).font(.body)
                Spacer(minLength: 8)
                if scope != nil, let tag = sourceTag(source) {
                    tag
                }
                Text(bindingText(button))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.rowH)
            .padding(.vertical, Spacing.rowV)
            .frame(minHeight: Spacing.rowMinHeight)
            .background(isSelected ? Color.brandAccentSoft : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 绑定文本：无绑定显示「—」，动作显示「动作：xxx」。
    private func bindingText(_ button: RemoteButton) -> String {
        effectiveMapping[action: button].map { "动作：\($0.displayName)" }
            ?? effectiveMapping[button]?.display
            ?? "—"
    }

    /// 应用作用范围下的来源标签胶囊；默认作用范围与未绑定不显示。
    private func sourceTag(_ source: KeyBindingSource) -> Text? {
        switch source {
        case .inherited:
            return Text("继承")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .overridden:
            return Text("覆盖")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.brandAccent)
        case .own, .unbound:
            return nil
        }
    }
}
