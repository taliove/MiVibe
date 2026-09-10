# 豆包账号与实际协议帧如何通过小样验证

Type: task
Label: wayfinder:task
Status: resolved
Assignee: taliove (with Claude)
Parent: ../map.md
Blocked by: 05

## Question

取得官方 Python/Go 协议附件或可核验的真实帧，明确最后响应 flags/sequence、result 形态及 is_last_package 包装来源。之后用用户已配置在本地的语音凭据和明确授权的短测试音频验证2.0资源、握手、PCM、最终结果、取消和二遍尾延迟；事先明确测试费用上限，不要求用户在聊天提交密钥，不自动购买或开通服务。对失败/取消/重试账单无法确认的项向官方资料或控制台求证。

## Context

[公开协议核验](../research/doubao-contract.md) 列出已确认字段及文档差异。账号未配置时先完成可离线阅读的部分；这是一项验证任务，不实现正式应用。

## Comments

2026-09-09（Claude）：协议帧三问已通过官方 SDK 源码核验解决，详见 [research/doubao-wire.md](../research/doubao-wire.md)：`is_last_package` 是官方示例包装层按帧头 flags 0x02 位计算，非服务器 JSON 字段；结束判定只看 flags 位、不查 sequence 符号；`result` 三方实现一致按 object 消费。残留分歧（flags 0x04 含义、result 最终形态、认证头行为）只能由真实帧裁决，列入实测验收取证清单。本机未发现任何已配置的语音凭据（环境变量与 Keychain 均无），实测部分需用户先完成账号配置与费用授权。

2026-09-09（Claude）：用户授权费用上限 5 元并提供凭据（已转存 Keychain）。实测全部通过，详见 [research/doubao-wire.md](../research/doubao-wire.md)「实测裁决」：握手、端到端识别、取消、二遍尾延迟（单遍 0.209s / 二遍 0.767s）均确认；真实帧裁决下行最终帧 seq 为正、flags 0x04 未出现、result 为 object、下行不压缩。实际费用约 0.004 元。探针 [diagnostics/asr-probe.py](../diagnostics/asr-probe.py) 与证据帧 `diagnostics/asr-evidence-*.jsonl` 已归档。

## Answer

**协议合同成立，可执行。** 接入候选确认为：2.0 小时版（`volc.seedasr.sauc.duration`）+ `bigmodel_async` + 当前三头认证 + 16 kHz mono pcm_s16le 200ms 分包 + 官方末包惯例（flags=3、负 seq、gzip 空包）+ 按帧头 flags 0x02 判结束（不查 seq 符号）+ `result` 按 object 解析 + 逐帧按头解压。二遍识别可开：尾延迟 0.767s 换更准标点分句；单遍 0.209s。

**唯一遗留**（不阻塞合同，属人工核对）：取消/失败调用的账单归因需用户在火山控制台核对四次测试调用（约 14.25s 音频、约 0.004 元）的实际扣费，归入地图"费用展示体验"雾区，核对结果补记于 [doubao-wire.md](../research/doubao-wire.md)。建议用户在全部测试结束后到控制台轮换 API Key。
