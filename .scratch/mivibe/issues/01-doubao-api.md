# 豆包语音 API 应选择哪种接入方式

Type: research
Label: wayfinder:research
Status: resolved
Assignee: doubao
Parent: ../map.md
Blocked by: none

## Question

豆包/火山引擎目前适合按住说话、松手输入的官方语音识别 API 是哪种？核实认证、开通、音频格式、流式与结束语义、错误恢复、费用来源及 macOS 客户端密钥保存约束。给出推荐与仍需用户/真机确认的事实，不调用收费 API。

## Answer

首选豆包大模型流式 WebSocket，优先验证官方 bigmodel_async 优化模式，松手后等待最终结果、只插入一次。官方已确认接口存在及二遍能力；原生流式 API 正文受抓取限制，音频参数、结束帧、最终标志和新版认证仍须实施前核验，不能宣称已完成协议验证。个人凭证建议存 Keychain，小时版资源优先考察；价格与试用按用户控制台确认。

研究资产：[豆包语音 API 首轮研究](../research/doubao.md)。
