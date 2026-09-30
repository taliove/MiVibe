import MiVibeCore
import SwiftUI

/// 「套用预设」sheet：左列选择预设，右侧预览它将写入的改动，底部选择
/// 「仅填空位 / 覆盖已有绑定」后套用。
///
/// 预览沿用按键映射页原有的对比与冲突标黄规则：当前已有绑定（含动作）且与
/// 预设不一致的行标黄——覆盖模式下它会被替换，填空位模式下它会保留。
struct PresetSheet: View {
    @ObservedObject var coordinator: Coordinator
    /// 套用目标作用范围：nil = 默认映射。
    let scope: String?
    let onDismiss: () -> Void

    @State private var selectedPresetID: String? = KeyMapPreset.all.first?.id
    @State private var onlyFillEmpty = true

    private var selectedPreset: KeyMapPreset? {
        KeyMapPreset.all.first { $0.id == selectedPresetID }
    }

    /// 当前作用范围实际生效的映射表（预览对比用）。
    private var effectiveMapping: AppMapping {
        coordinator.keyMap.mapping(forBundleID: scope)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("套用预设")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], Spacing.page)
                .padding(.bottom, Spacing.section)

            HStack(alignment: .top, spacing: 0) {
                presetList
                    .frame(width: 180)
                Divider()
                previewPane
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 220)

            Divider()
            footer
        }
        .frame(width: 560)
    }

    // MARK: - 左列：预设列表

    private var presetList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(KeyMapPreset.all) { preset in
                Button {
                    selectedPresetID = preset.id
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Color.brandAccent)
                        Text(preset.name)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.rowH)
                    .padding(.vertical, Spacing.rowV)
                    .background(selectedPresetID == preset.id
                                ? Color.brandAccentSoft : Color.clear,
                                in: RoundedRectangle(cornerRadius: Radius.small))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.rowH)
    }

    // MARK: - 右侧：改动预览

    @ViewBuilder
    private var previewPane: some View {
        if let preset = selectedPreset {
            VStack(alignment: .leading, spacing: Spacing.intra) {
                Text(preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    ForEach(preset.shortcuts.keys.sorted(), id: \.self) { key in
                        previewRow(preset: preset, key: key)
                    }
                }
            }
            .padding(Spacing.page)
        } else {
            Text("选择左侧预设查看改动。")
                .foregroundStyle(.secondary)
                .padding(Spacing.page)
        }
    }

    /// 单键改动行：键 / 当前绑定 → 预设将改成；已有绑定且不一致时标黄（冲突）。
    private func previewRow(preset: KeyMapPreset, key: String) -> some View {
        let button = RemoteButton.from(id: key)
        let newValue = preset.shortcuts[key]!
        let currentShortcut = button.flatMap { effectiveMapping[$0] }
        let currentAction = button.flatMap { effectiveMapping[action: $0] }
        let conflict = currentAction != nil || (currentShortcut != nil && currentShortcut != newValue)
        return HStack(spacing: 6) {
            Text(button?.displayName ?? key)
                .frame(width: 50, alignment: .leading)
            Text(currentAction.map { "动作：\($0.displayName)" }
                 ?? currentShortcut?.display ?? "—")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(newValue.display)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(conflict ? Color.brandAttention.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Radius.small))
    }

    // MARK: - 底部：模式与操作

    private var footer: some View {
        HStack(spacing: Spacing.section) {
            Picker("", selection: $onlyFillEmpty) {
                Text("仅填空位（推荐）").tag(true)
                Text("覆盖已有绑定").tag(false)
            }
            .labelsHidden()
            .fixedSize()
            .help("仅填空位不动已有绑定（继承来的也算占用）；覆盖已有绑定整键替换")

            Spacer()

            Button("取消", action: onDismiss)
                .keyboardShortcut(.cancelAction)
            Button("套用") {
                guard let preset = selectedPreset else { return }
                coordinator.applyPreset(preset, to: scope, onlyFillEmpty: onlyFillEmpty)
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandControlFill)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedPreset == nil)
        }
        .padding(.horizontal, Spacing.page)
        .padding(.vertical, Spacing.rowH)
    }
}
