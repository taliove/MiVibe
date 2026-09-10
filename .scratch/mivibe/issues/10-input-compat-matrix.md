# 跨应用文本注入的兼容矩阵如何实测确定

Type: task
Label: wayfinder:task
Status: resolved
Assignee: taliove (with Claude)
Parent: ../map.md
Blocked by: 03

## Question

按 [03 票候选路径](03-macos-input.md)（辅助功能定位 + 文本写入/粘贴回退）做最小注入探针，在用户日常应用矩阵（终端、VS Code/Cursor、浏览器输入框、微信等）实测：写入是否成功、焦点是否被抢、失败时降级到粘贴的行为。确定第一版的兼容策略与降级范围：哪些应用走直写、哪些走粘贴、哪些明确不支持。探针不实现正式产品逻辑，不做自动发送。

## Context

03 票已定候选路径但未实测；08 票已确认识别链路可用，注入成为最后一里路。用户日常应用场景由其指定；每应用的成功/失败/降级现象需用户目视确认。

## Comments

2026-09-09（Claude）：注入探针 [diagnostics/inject-probe.swift](../diagnostics/inject-probe.swift) 建成（check/ax/paste 三模式，唯一标记串读回验证，剪贴板快照+恢复）。本机辅助功能与事件投递权限均已具备，无需用户授权步骤。用户指定矩阵只测 TextEdit。证据在 /tmp/mivibe-inject-evidence.jsonl。

## Answer

**注入策略实测成立（基线），探针即兼容测试工具。** 实测结果：

- **TextEdit（原生 AXTextArea）**：AX 直写 ✅（AXSelectedText 可写，中文+emoji 读回验证通过）；粘贴降级 ✅（读回验证通过，剪贴板 changeCount 干净、快照恢复成功）。
- **iTerm2（意外数据点）**：AXSelectedText **不可写** → AX 路径不适用，必须走粘贴降级——验证了"运行时探测+按应用降级"策略的必要性。

**第一版兼容策略定型**：运行时探测焦点元素 → AXSelectedText 可写走直写，否则经验证目标走粘贴（快照/恢复），安全输入框（subrole 含 Secure）拒绝注入，结果不明则暂存不盲重试。兼容承诺仅限实测应用；新应用接入 = 跑一次探针。终端的粘贴执行行为（bracketed paste）未实测（用户本轮不测终端），第一版对终端场景标注"待验证"，不作为兼容承诺。
