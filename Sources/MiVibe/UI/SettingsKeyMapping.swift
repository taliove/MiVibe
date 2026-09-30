import AppKit
import MiVibeCore
import SwiftUI
import UniformTypeIdentifiers

/// 「按键映射」页：作用范围栏 + 接管提示 + 预设撤销横幅 + 遥控器图 + 选中按键卡 + 全部按键列表。
///
/// 术语（与 CONTEXT.md 一致）：nil 的作用范围 = 默认映射；应用作用范围只记录
/// **覆盖**，未覆盖的键**继承**默认映射。页面状态（sheet、确认框、录制令牌）
/// 都收在 `KeyMappingPage` 内，`keyMappingTab` 只是入口。
extension SettingsView {

    var keyMappingTab: some View {
        KeyMappingPage(
            coordinator: coordinator,
            paneModel: paneModel,
            scope: $mappingScope,
            selectedButton: $selectedButton
        )
    }
}

/// 按键映射页主体。所有本页临时状态（预设 sheet、移除确认、录制令牌）都在这里。
struct KeyMappingPage: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject var paneModel: SettingsPaneModel
    @Binding var scope: String?
    @Binding var selectedButton: RemoteButton?

    /// 非 nil 时显示预设套用 sheet。
    @State private var presetSheetShown = false
    /// 非 nil 时先弹确认再移除该应用的覆盖（记录覆盖数供确认文案使用）。
    @State private var removalTarget: RemovalTarget?

    struct RemovalTarget: Identifiable {
        let bundleID: String
        let name: String
        let overrideCount: Int
        var id: String { bundleID }
    }

    /// 当前作用范围里每个可映射键的绑定来源（遥控器标记与列表胶囊共用）。
    private var bindingSources: [RemoteButton: KeyBindingSource] {
        Dictionary(uniqueKeysWithValues: RemoteButton.mappable.map {
            ($0, coordinator.keyMap.bindingSource(of: $0, forBundleID: scope))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PageHeader(subtitle: "点按遥控器上的按键进行配置，改动即时保存并生效。")

            KeyMappingScopeBar(
                coordinator: coordinator,
                scope: $scope,
                onShowPresets: { presetSheetShown = true },
                onRequestRemoval: { target in
                    // 覆盖数为 0 直接移除；有覆盖先确认。
                    if target.overrideCount == 0 {
                        removeScope(target.bundleID)
                    } else {
                        removalTarget = target
                    }
                }
            )

            takeoverBanner

            if let undo = coordinator.presetUndo {
                presetUndoBanner(undo)
            }

            HStack(alignment: .top, spacing: Spacing.page) {
                RemoteControlView(
                    selected: $selectedButton,
                    sources: bindingSources,
                    flashing: coordinator.pressedButton,
                    onClear: { button in
                        coordinator.setShortcut(nil, for: button, in: scope)
                        coordinator.setAction(nil, for: button, in: scope)
                    },
                    onSetAction: { button, action in
                        coordinator.setAction(action, for: button, in: scope)
                        selectedButton = button
                    }
                )
                .frame(width: RemoteControlView.preferredWidth)

                VStack(alignment: .leading, spacing: Spacing.section) {
                    KeyMappingSelectedCard(coordinator: coordinator, scope: scope,
                                           selectedButton: $selectedButton)
                    KeyMappingAllKeysList(coordinator: coordinator, scope: scope,
                                          selectedButton: $selectedButton)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Spacing.page)
        .onAppear(perform: reconcileScope)
        .onChange(of: coordinator.keyMap) { reconcileScope() }
        .sheet(isPresented: $presetSheetShown) {
            PresetSheet(coordinator: coordinator, scope: scope,
                        onDismiss: { presetSheetShown = false })
        }
        .alert(item: $removalTarget) { target in
            Alert(
                title: Text("移除 \(target.name) 的 \(target.overrideCount) 项覆盖？"),
                message: Text("该应用将完全跟随默认映射。"),
                primaryButton: .destructive(Text("移除覆盖")) {
                    removeScope(target.bundleID)
                },
                secondaryButton: .cancel()
            )
        }
    }

    /// 移除某应用的全部覆盖，并把作用范围收回到默认映射。
    private func removeScope(_ bundleID: String) {
        coordinator.removeAppMapping(bundleID)
        if scope == bundleID { scope = nil }
    }

    /// 作用范围兜底：正在编辑的应用覆盖被别处移除时回到默认映射。
    /// 注意 `ensureAppMapping` 建的是空覆盖表，`hasMapping` 同样为 true，不算失效。
    private func reconcileScope() {
        if let scope, !coordinator.keyMap.hasMapping(forBundleID: scope) {
            self.scope = nil
        }
    }

    // MARK: - 接管提示条

    /// 仅当映射不会生效时显示；「去处理」跳到遥控器页开接管 / 处理权限。
    @ViewBuilder
    private var takeoverBanner: some View {
        if !coordinator.keyTakeover {
            banner(text: "按键接管未开启，映射不会生效")
        } else if !coordinator.keyTakeoverActive {
            banner(text: "按键接管未生效，映射暂不起作用")
        }
    }

    private func banner(text: String) -> some View {
        NoticeBanner(icon: "exclamationmark.triangle.fill", text: text,
                     actionTitle: "去处理") { paneModel.pane = .remote }
    }

    /// 预设撤销横幅：显示最近一次套用的预设与作用范围，一键撤销。
    private func presetUndoBanner(_ undo: Coordinator.PresetUndo) -> some View {
        let scopeName = undo.scope.map { AppIdentity.name(for: $0) } ?? "默认（所有应用）"
        return NoticeBanner(icon: "arrow.uturn.backward.circle.fill",
                            text: "已套用「\(undo.presetName)」 · 作用范围：\(scopeName)",
                            actionTitle: "撤销", style: .brand) { coordinator.undoPresetApply() }
    }
}

// MARK: - 作用范围栏

/// 「编辑对象」弹出菜单 + 添加应用（＋）+ 更多操作（⋯）+ 套用预设。
struct KeyMappingScopeBar: View {
    @ObservedObject var coordinator: Coordinator
    @Binding var scope: String?
    let onShowPresets: () -> Void
    let onRequestRemoval: (KeyMappingPage.RemovalTarget) -> Void

    var body: some View {
        HStack(spacing: Spacing.intra) {
            Text("编辑对象：")
                .foregroundStyle(.secondary)
            Picker("", selection: $scope) {
                Text("默认（所有应用）").tag(String?.none)
                ForEach(AppIdentity.sortedByName(coordinator.keyMap.perApp.keys), id: \.self) { bundleID in
                    scopeItem(bundleID)
                        .tag(String?.some(bundleID))
                }
            }
            .labelsHidden()
            .fixedSize()

            Spacer()

            // ＋：把新应用加入覆盖列表。正在运行的直接列；其余走 NSOpenPanel 选 .app。
            Menu {
                ForEach(AppIdentity.runningCandidates.compactMap(\.bundleIdentifier), id: \.self) { bundleID in
                    Button {
                        coordinator.ensureAppMapping(bundleID)
                        scope = bundleID
                    } label: {
                        Label {
                            Text(AppIdentity.name(for: bundleID))
                        } icon: {
                            if let icon = AppIdentity.menuIcon(for: bundleID) {
                                Image(nsImage: icon)
                            }
                        }
                    }
                }
                Divider()
                Button("从应用程序文件夹选择…") { pickApplication() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("添加应用覆盖")

            // ⋯：当前作用范围的维护操作。
            Menu {
                Button("移除「\(scope.map { AppIdentity.name(for: $0) } ?? "")」的应用覆盖") {
                    guard let scope else { return }
                    onRequestRemoval(KeyMappingPage.RemovalTarget(
                        bundleID: scope,
                        name: AppIdentity.name(for: scope),
                        overrideCount: coordinator.keyMap.overrideCount(forBundleID: scope)
                    ))
                }
                .disabled(scope == nil)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")

            Button("套用预设…", action: onShowPresets)
                .controlSize(.small)
        }
    }

    /// 作用范围菜单项：应用图标 + 名称 + 覆盖键数。
    private func scopeItem(_ bundleID: String) -> some View {
        Label {
            Text("\(AppIdentity.name(for: bundleID))（覆盖 \(coordinator.keyMap.overrideCount(forBundleID: bundleID)) 键）")
        } icon: {
            if let icon = AppIdentity.menuIcon(for: bundleID) {
                Image(nsImage: icon)
            }
        }
    }

    /// 从 /Applications 选一个 .app，读出 bundle id 后建覆盖并切过去。
    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else { return }
        coordinator.ensureAppMapping(bundleID)
        scope = bundleID
    }


}
