# 更新记录 · Changelog

每个版本一节，中文在前、英文在后。发布流程按标签版本号取出对应一节放在发布说明最上方；缺少该节时发布会失败。

Each release has one section, Chinese first, English second. The release workflow copies the section matching the tag to the top of the release notes and fails if it is missing.

## [Unreleased]

### 本版更新

- 以 MIT 许可证开源，安装包内附带本项目与 whisper.cpp 的许可声明。
- 新增安全漏洞私下报告渠道（SECURITY.md）。
- 修复：几乎同时按下菜单键和返回键后，模式选单再也打不开（按菜单键无反应，按返回键时一闪而过）。
- 新增按键提示：按下遥控器按键时在屏幕中央短暂显示键名与这一次的实际结果（如「确认 → ⌘↩」「菜单 → 模式选单」），可在「设置 → 遥控器」关闭。
- 浮条跟随每条录音：连续说话时每句一条、上下叠放（新句在下），各自显示进度，已输入的那条单独收起；模式切换等提示单独一条；第三条录音被拒绝时已有浮条轻晃一下。

### What's New

- Open-sourced under the MIT License; the app bundle now includes the license notices for MiVibe and whisper.cpp.
- A private channel for reporting security issues (SECURITY.md).
- Fix: after pressing the menu and back keys almost together, the mode picker no longer opened (the menu key did nothing and the back key only flashed it).
- Key hints: pressing a remote key briefly shows the key and what it actually did in the center of the screen (e.g. "Confirm → ⌘↩", "Menu → Mode picker"); turn it off in Settings → Remote.
- One float bar per recording: when you speak several sentences in a row, each gets its own bar, stacked with the newest at the bottom and showing its own progress; an inserted bar collapses on its own; notices such as mode switches get a separate bar; a rejected third recording shakes the existing bars once.

## [0.4.0] - 2026-09-30

### 本版更新

**全新品牌与主题**
- 新的品牌标志：三根声波组成的「M」，应用图标、菜单栏图标、浮条和设置窗口统一使用。
- 默认主题换成潮汐青，替代原来的系统蓝；「设置 → 外观」可在六套主题（潮汐青、靛蓝、珊瑚、兰紫、玫瑰、石墨）之间切换，立即生效。
- 外观可选跟随系统、浅色或深色，同时作用于设置窗口、菜单弹层和浮条。
- 应用图标按 macOS 26 的圆角规格重做，在程序坞里与系统应用大小一致，并随主题换色。

**动效**
- 浮条出现、切换状态、收起都有过渡；录音时显示随音量跳动的三根声波，转写中显示进度圈，需要处理时轻轻晃动提醒。
- 说话时菜单栏图标随音量跳动。
- 模式选单高亮、设置侧栏选中项平滑移动。
- 开启「减弱动态效果」后，所有动效改为淡入淡出或静止。

**修复**
- 关闭模式选单时不再闪出上一次的浮条状态。
- 菜单弹层和设置窗口里的按钮、分段控件文字在浅色、深色下都清晰可读。
- 设置侧栏不再出现蓝色焦点边框。

**发布**
- 发布页提供 DMG 安装包，并附中英文安装说明，包括首次打开被拦截时的处理方式。
- README 分为中文与英文两份。

### What's New

**New brand and themes**
- A new brand mark, an "M" made of three sound bars, used across the app icon, menu bar icon, float bar and settings window.
- The default theme is now Tide, replacing the system blue. Settings → Appearance switches between six themes (Tide, Indigo, Coral, Orchid, Rose, Graphite) instantly.
- Appearance can follow the system or stay light or dark, applied to the settings window, menu popover and float bar together.
- The app icon is redrawn to the macOS 26 squircle, so it matches system apps in the Dock, and follows the theme color.

**Motion**
- The float bar animates in, between states and out. Recording shows three bars that follow your voice, transcribing shows a progress ring, and items that need attention give a short shake.
- The menu bar icon moves with your voice while you speak.
- The mode picker highlight and the settings sidebar selection slide smoothly.
- With Reduce Motion on, animations fall back to fades or stay still.

**Fixes**
- Closing the mode picker no longer flashes the previous float bar state.
- Buttons and segmented controls in the menu popover and settings are readable in both light and dark.
- The settings sidebar no longer shows a blue focus ring.

**Releases**
- Releases now ship a DMG with bilingual install notes, including what to do when macOS blocks the first launch.
- The README is split into Chinese and English.

## [0.3.0] - 2026-09-30

### 本版更新

**按键接管**
- 改用按设备的按键重映射接管遥控器，不再需要独占设备，普通权限下即可生效；设备重连时自动重新接管，关闭接管、退出应用时自动撤销。
- 接管失败时显示可读的原因，只在确实缺少「输入监控」权限时才请求授权。

**语音队列**
- 过短（不足 0.3 秒）或过轻的录音不再送去识别；空白或只有标点的结果直接丢弃，不会卡住队列。
- 识别整体超时保护；失败的录音可以从菜单一键重试；遥控器断开时丢弃正在进行的录音。
- 焦点变化后晚到的识别结果会补进占位项。

**设置窗口**
- 重新设计：侧栏延伸到标题栏，支持前进后退（⌘[ / ⌘]）和 ⌘1–⌘5 切换页面。
- 按键映射合并为一页：默认映射加按应用覆盖，可从运行中的应用添加，支持预设、预览和撤销。
- 矢量绘制的遥控器示意图，标出继承与覆盖的按键。

**遥控器与浮条**
- 睡眠唤醒后系统自动回连的遥控器也能被重新识别。
- 浮条改为毛玻璃背景，宽度随内容变化，边框随状态变色。

### What's New

**Key takeover**
- The remote is now taken over with a per-device key remap instead of exclusive access, so it works without root. It is reapplied when the remote reconnects and removed when takeover is turned off or the app quits.
- Takeover failures show a readable reason, and Input Monitoring is requested only when that permission is actually missing.

**Voice queue**
- Recordings shorter than 0.3 s or too quiet are no longer sent for recognition, and empty or punctuation-only results are dropped instead of blocking the queue.
- An overall transcription timeout, one-click retry of failed recordings from the menu, and in-progress recordings are dropped when the remote disconnects.
- Late results fill in their placeholder after the focus changed.

**Settings window**
- Redesigned: the sidebar runs under the title bar, with back and forward (⌘[ / ⌘]) and ⌘1–⌘5 page shortcuts.
- Key mapping is one page: a default mapping plus per-app overrides, added from running apps, with presets, preview and undo.
- A vector remote diagram marks inherited and overridden keys.

**Remote and float bar**
- A remote that the system reconnects after sleep is picked up again.
- The float bar uses a glass background, sizes to its content and tints its border by state.

## 更早版本 · Earlier releases

0.1.0 与 0.2.0 的改动见提交历史。Changes in 0.1.0 and 0.2.0 are in the commit history.

[0.4.0]: https://github.com/taliove/MiVibe/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/taliove/MiVibe/compare/v0.2.0...v0.3.0
