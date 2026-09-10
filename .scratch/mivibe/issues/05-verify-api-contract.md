# 豆包流式协议与账号接入合同如何核验

Type: task
Label: wayfinder:task
Status: resolved
Assignee: taliove (with Codex)
Parent: ../map.md
Blocked by: 01

## Question

取得可读取的官方流式 API 正文或官方示例，逐项核对端点、账号认证方式、音频参数、最后帧、最终结果标志、二遍修正及计费规则。公开访问不足时，再向用户提供准确的控制台资料获取步骤；密钥不通过聊天传递。此任务只补足接入决策的证据，不实现正式应用、不自动开通付费服务。

## Context

[豆包语音首轮研究](../research/doubao.md) 明确记录了已核实的方向与未核实的协议字段。

## Answer

2026-09-08：已通过浏览器取得当前官方接口、历史二进制协议和计费正文，完成公开资料核验。[核验报告](../research/doubao-contract.md) 记录 API Key、2.0 资源、PCM 参数、尾包 flags、最终响应与分句区别、二遍行为和时长计费。

旧来源现属历史文档，已改以当前双向流式接口为主要依据。文档包含 sequence 符号、result 类型和包装层/线协议差异；未获得官方附件内容、未验证用户账号、未调用收费 API。上述剩余证据转入「豆包账号与实际协议帧如何通过小样验证」，不宣称接入已经可用。
