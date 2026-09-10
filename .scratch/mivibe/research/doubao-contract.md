# 豆包流式 API 协议核验

核验日期：2026-09-08。通过浏览器读取官方渲染正文，未登录账号、读取凭据、购买服务或调用识别 API。此文件补充并更新首轮研究的未知项。

## 官方来源与版本

- [当前双向流式 WebSocket](https://docs.volcengine.com/docs/6561/2630027?lang=zh)：页面更新时间 2026-09-01 15:27:25，当前 API 导航内。
- [历史流式协议](https://docs.volcengine.com/docs/6561/1354869?lang=zh)：页面更新时间 2026-08-06 17:40:25，现归入“历史文档”。包含底层二进制协议，不能将其所有参数限制覆盖到新版。
- [计费说明](https://docs.volcengine.com/docs/6561/1359370?lang=zh)：页面更新时间 2026-08-20 21:22:12。

## 已核验的接入事实

当前双向流式端点为 `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`。新版请求头列出必选 `X-Api-Key`、`X-Api-Resource-Id`、`X-Api-Request-Id`（建议 UUID）。支持旧版 App Key/Access Key 认证，但个人新接入优先 API Key。当前文档推荐模型 2.0，小时版资源 `volc.seedasr.sauc.duration`；1.0 小时版为 `volc.bigasr.sauc.duration`。端点不因资源版本而改变。[当前接口](https://docs.volcengine.com/docs/6561/2630027?lang=zh)

音频选择 `format=pcm`、`codec=raw`、`rate=16000`、`bits=16`、`channel=1`；当前文档及示例支持该参数组合的组成字段，历史协议明确 PCM/WAV 内部为 pcm_s16le。因此独立解码目标采用 16 kHz、单声道、16 位有符号小端 PCM，仍需端到端试样验收。不得把蓝牙 ADPCM 原始数据直接当 PCM 上传。当前示例默认每包 200ms，换算上述 PCM 为每包 6400 字节（压缩前）；最后不足一包的音频必须保留。[当前接口](https://docs.volcengine.com/docs/6561/2630027?lang=zh)、[底层协议](https://docs.volcengine.com/docs/6561/1354869?lang=zh)

请求模型名仍是 `bigmodel`。`result_type=full` 返回累计全量结果，`single` 为增量。`enable_nonstream=true` 开启二遍识别，VAD 分句后重新识别；`definite=true` 标识确定分句，不代表整个按住说话会话结束。当前响应描述与示例包含 `is_last_package`，为真表示结果已全部返回。页面示例由 `protocol.AsrWsClient` 解码并输出 `response.to_dict()`，不能据此假定 WebSocket 直接返回这份 JSON。[当前接口](https://docs.volcengine.com/docs/6561/2630027?lang=zh)

## 结束流程与二进制边界

历史协议规定：四字节基本头包含协议版本、头大小、消息类型、flags、序列化、压缩。协议整数字段是大端，与 PCM 小端不同。首包是 full client request（类型1），后续 audio only（类型2）；结果类型9、错误类型15。JSON 和 gzip 均通过头字段声明，长度计算针对压缩后 payload。

flags 0 表示无 sequence；1 表示携带正 sequence；2 表示最后一包且不携带 sequence；3 表示最后一包并携带负 sequence。官方示例用类型2/flags2发送最后音频，用类型9/flags3表示最终响应。[底层协议](https://docs.volcengine.com/docs/6561/1354869?lang=zh)

工程建议：按住时分包上传；HID 松手后收完遥控器协议尾音，再给云端标记最后音频包；等待解码后的最终响应，且未取消、目标仍有效、队列顺序允许时，仅输入一次最终全量文字。VAD 判停不触发跨应用输入。网络关闭或超时不能冒充成功，取消后忽略迟到结果。此流程是项目推论及既定产品行为的结合。

## 文档内部差异，不能盲抄

- 当前页面将 WebSocket 端点标为 POST，历史协议及 WebSocket 常规握手描述为 GET Upgrade。使用标准 WebSocket 客户端，不按页面标签做普通 HTTP POST。
- 历史头表的 flags3 要求负 sequence，但最终响应示例却展示正3。应解析 flags 和有无 sequence，并以官方示例库与真实抓包核对其符号；不能只凭 sequence<0 判结束。
- 当前响应表称 result 为 list，而输出示例为 object。解析器需要实际样例确定支持形态；不能直接照表建单一固定数组类型。
- 历史音频格式/采样率限制比当前文档更窄；本项目选两者均可解释的 16 kHz PCM，不据旧文档宣称新版仅支持这一格式。
- 历史头表与示例混用 Request-Id/Connect-Id；新请求遵循当前必选 Request-Id 表，并在握手实测中确认。
- 已点击当前页面的 `sauc_python.zip` 附件，但未获得可读取的本地包，因此尚未审阅 `protocol.py`。当前页面暴露的包装层字段与底层帧映射仍需官方附件或真实响应补证。

## 费用与账号边界

当前官方计费表：2.0 流式识别按调用后付费 1 元/小时；30小时资源包28元，有效期1年。按时长累计每次调用，精确至毫秒，再折算小时；双声道也按音频时长计费。个人版优先考察小时版，无需预先购买纯并发套餐。账户是否已开通、适用优惠、可用额度及实际账单仍未知。[计费说明](https://docs.volcengine.com/docs/6561/1359370?lang=zh)

不要将页面中“按次数计费的失败调用不计次”泛化成 ASR 时长计费失败免费；失败、中断、取消、二遍及重试的实际账单归因需控制台/官方补证。本次不承诺这些调用免费。

账号准备入口已由当前接口页面核实：[语音 API Key 管理](https://console.volcengine.com/speech/new/setting/apikeys?projectName=default)。后续在本地应用设置中配置 Key，不在聊天/仓库记录密钥。Keychain 是首轮研究提出的存储建议。尚未配置用户账户或运行收费测试。

## 当前接入候选

2.0 小时版 + bigmodel_async + 16 kHz mono pcm_s16le + 200ms 分包 + full 全量结果。建议评估二遍识别，以最终准确率为先，实际尾字延迟需实测。标点和 ITN 使用默认开启，语义顺滑暂保持默认关闭；这些文本处理选项是建议，不冒充用户新确认的偏好。

公开文档缺口已显著收敛；接下来进行官方示例库/真实帧核验与用户账号的小样验证，完成后才能把候选变为可执行协议合同。
