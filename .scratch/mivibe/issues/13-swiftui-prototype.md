# 应用界面的原生 SwiftUI 原型应该长什么样

Type: prototype
Label: wayfinder:prototype
Status: resolved
Assignee: taliove (with Claude)
Parent: ../map.md
Blocked by: none

## Question

用户指定第一版为原生 SwiftUI 应用。制作可运行的界面原型供用户确认观感，覆盖：菜单栏三态图标与菜单（未配对/已配对未连接/已连接）、底部不抢焦点浮条的四状态呈现（正在听/正在转写/已输入/需处理，含指引文案）、设置页（API Key 录入 + 二遍识别开关 + 打开控制台/蓝牙设置按钮）、首次配对引导。顺带实测 `.nonactivatingPanel` 是否真的不抢焦点（03 票的关键假设）。原型不连蓝牙/ASR/注入，状态用模拟数据驱动。

## Context

交互逻辑已由 [07 票原型](../prototypes/recovery-flow-prototype.html) 确认，本票只解决原生观感与布局。界面原型是 [12 票规格](12-write-spec.md) 界面章节的事实来源。

## Answer

2026-09-09：用户验收通过可运行的 SwiftUI 原型 [prototypes/MiVibeProto.swift](../prototypes/MiVibeProto.swift)（`swiftc -O -parse-as-library` 单文件编译即跑）。确认的界面决策：

1. **实现栈**：原生 SwiftUI，菜单栏应用（MenuBarExtra + `.window` 弹窗样式）。
2. **菜单栏三态**：图标随 未配对(mic.badge.plus，橙)/已配对未连接(mic.slash，灰)/已连接(mic.fill，绿) 切换；未配对时弹窗内嵌配对引导（步骤+打开蓝牙设置按钮）。
3. **底部浮条四状态**：黑底圆角横条（色点+状态词+指引文案），`.nonactivatingPanel` + `canBecomeKey/Main = false` 双重保险；演示模式轮播期间 TextEdit 打字无打断，**不抢焦点假设实锤**。
4. **设置页**：标准 macOS 惯例——工具栏三分页（豆包语音/遥控器/关于）、分组表单、左列右对齐短标签、说明文字入 Section 脚注、窗口中文标题、内容定高无滚动条。API Key 录入走 SecureField（真实版存 Keychain），附控制台直达按钮；二遍识别开关默认开。

视觉基线以此原型为准；07 票的四状态逻辑与队列行为不变。
