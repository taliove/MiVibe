# 按键接管与异常断连应采用什么安全策略

Type: prototype
Label: wayfinder:prototype
Status: resolved
Assignee: taliove (with Claude)
Parent: ../map.md
Blocked by: 06

## Question

在不影响用户日常工作的可撤销测试中，确认电源键及普通按键的系统原生副作用，并验证蓝牙关闭、休眠唤醒、移出范围、快速连续录音和进程异常退出。基于结果决定按键接管、启动前检查、重连退避和退出恢复策略。先设计可见的测试与恢复步骤，再进行系统映射变更；未经明确步骤不得修改系统按键映射。

## Context

[真机验证记录](../research/hardware-check.md) 已证明核心语音链路与十二个非电源按钮可用，也记录了未覆盖的压力边界。

## Comments

2026-09-09（Claude）：自动化压力阶段完成，新工具 [diagnostics/stress-probe.swift](../diagnostics/stress-probe.swift)（cycles/hold/button 三模式）。结果：①程序驱动快速开关麦 5/5 成功（AUDIO_START 延迟约 20-33ms，MIC_CLOSE→AUDIO_STOP 约 30ms），固件无卡死；②**程序 MIC_OPEN 收不到音频帧**（5 轮全 0 帧），真实音频仅在按住语音键时流出（设备自发 AUDIO_START 04 03 02 xx）——麦克风由物理按键门控，应用无法绕过，快速连录实测必须用真实按键；③hold 模式会话建立后 kill -9，立即重跑 cycles 恢复完整（连接 74ms、就绪 166ms、5/5 周期成功），进程异常退出无需退避延迟。证据在 /tmp/mivibe-stress-*.jsonl。剩余物理项：电源键副作用、普通按键前台副作用、蓝牙关闭/休眠/移出范围恢复、真实按键快速连录——已备好 hid-wide-probe 与 stress-probe button 模式。

2026-09-09（Claude）：真实按键快速连录 5/5 通过（会话时长 0.98-2.63s、46-165 帧不等，stream 计数跨连接单调递增 08→0C，固件无卡死）。宽域 HID 探针（[diagnostics/hid-wide-probe.swift](../diagnostics/hid-wide-probe.swift)）捕获电源键 4 次按下：usage 0x66（HID Power），**无任何 SYSTEM_WILL_SLEEP 事件**——本机 macOS 26.5.2 对该设备的 Power 键无系统副作用。随后用户基于日常使用经验裁决：蓝牙关闭/休眠/移出范围的恢复「基本上都没有问题」，不再专项实测，剩余风险由 04 票「失败手动重试」交互兜底。

## Answer

**安全策略确定**（实测证据 + 用户裁决）：

1. **按键接管**：电源键发送 HID Power(0x66) 但本机系统无响应——应用**不接管也不依赖电源键**，无需任何系统按键映射变更。普通按键是标准 HID 键盘事件（天然到达前台应用），语音键 HID 面（0x3E）未见副作用，语音通道由 BLE 独占保证。
2. **麦克风门控**：程序 MIC_OPEN 无音频，音频仅在物理按住语音键时流出——应用无法绕过物理按键，隐私边界由硬件保证；同时意味着所有录音会话必须以设备自发 AUDIO_START 为准。
3. **进程异常退出**：kill -9 后立即重连即恢复（166ms 就绪），**无需重连退避**；实现用 CoreBluetooth 状态回调驱动重连即可。
4. **断连恢复**：蓝牙关闭/休眠/移出范围按用户日常经验视为可恢复，不专项实测；失败场景由交互合同的「失败手动重试」兜底。
5. **启动前检查**：CB 状态 poweredOn + 设备可连接（retrieveConnectedPeripherals/扫描），不满足时引导用户检查系统蓝牙与配对。
