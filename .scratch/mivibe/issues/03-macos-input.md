# 跨应用直接输入的能力与边界是什么

Type: research
Label: wayfinder:research
Status: resolved
Assignee: macos
Parent: ../map.md
Blocked by: none

## Question

依据 Apple 官方资料调查 macOS 原生跨应用文本输入、权限、焦点保持、剪贴板竞争、受保护输入框与沙盒/分发限制。推荐松手后直接输入方案；明确如何避免错误目标及误发送，不承诺所有软件兼容。

## Answer

Apple 官方资料支持以辅助功能定位目标、经验证的 AX 选区写入或剪贴板粘贴实现跨应用直接输入，但无法承诺所有软件。建议非沙盒原生应用；正常路径松手后直接插入，不附提交键；焦点改变/结果不明时暂存，不盲目重试。剪贴板恢复存在竞争与延迟消费限制，终端多行粘贴需独立验证。

研究资产：[macOS 跨应用直接输入研究](../research/macos.md)。此票解决文档能力边界，不代表真机兼容性通过。
