# 0002. 按键接管改用按设备重映射，不用 HID 独占

日期：2026-09-30
状态：已接受

## 背景

按键接管要求系统不再响应遥控器按键，由 MiVibe 统一路由与合成。原实现用 `kIOHIDOptionsTypeSeizeDevice` 独占设备，但真机上从未成功：每次返回 `0xE00002C1`（`kIOReturnNotPrivileged`），设置页一直显示「未生效」，授予输入监控也无效。

原因在 IOHIDFamily 的 `IOHIDLibUserClient::open`：设备主用途为 GenericDesktop/Keyboard 时，非特权客户端（非 root、无 Apple 私有 HID entitlement）请求 seize 一律返回 `kIOReturnNotPrivileged`。该检查不经过 TCC。小米遥控器 `PrimaryUsagePage=1, PrimaryUsage=6`，正落在此规则内。

## 候选方案

**A. 按设备 `UserKeyMapping` 重映射**：用 IOHIDEventSystemClient 只对遥控器的事件服务写映射，把键映射成死键；IOHIDManager 非独占读取原始 usage。

**B. root 辅助进程**（Karabiner 的做法）：特权守护进程负责 seize，需要正式开发者签名与额外安装流程。

**C. 放弃接管**：只保留仅监听。

## 决定

采用 **A**。`--probe-remap`（`Sources/MiVibeProbes/RemapProbe.swift`）于 2026-09-30 真机实测：

1. 非 root 写入成功，读回一致；
2. 重映射到键盘页 usage 0（`0x700000000`）后，12 个参与重映射的键系统零事件（仅未重映射的电源键仍有事件）；
3. 非独占 IOHIDManager 读到的仍是映射前的原始 usage；
4. 撤销后系统恢复响应。

条目规则放在纯逻辑 `RemoteKeyRemap`：写入只替换同源条目，撤销只剥离“我们的源 + 死键目标”，无需保存原值。系统边界是 `RemoteKeyRemapper`，维护逻辑在 `KeyReader`。

## 后果

- 不需要 root、开发者签名或额外安装；输入监控仍然需要（用于读取 HID）。
- 映射挂在事件服务上：设备每次出现都重写，服务晚到时短暂重试。重连后映射是否保留未专项实测，实现不依赖它。
- 监听打不开时绝不写映射，否则遥控器彻底失灵。
- 进程崩溃或被 `kill -9` 会留下映射，遥控器按键失灵，直到下次启动清理或断开重连遥控器。正常退出与 SIGTERM/SIGHUP/SIGINT 会撤销。
- 语音键一并映射为死键（F5 不再漏给前台应用）；按住说话走 BLE `AUDIO_START`，与 HID 无关。
