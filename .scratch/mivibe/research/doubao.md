# 豆包语音 API 首轮研究

日期：2026-09-08。仅查阅公开官方资料；未登录、开通服务或调用收费 API。

## 决策建议

采用火山引擎豆包语音的**大模型流式语音识别 WebSocket**作为首选方向。按住期间上传音频，松手结束本次音频，收到最终结果后一次性写入目标应用。结果流用于状态展示，不能当作多次文本插入。优先验证官方 `bigmodel_async` 双向流式优化接口；官方产品动态确认该接口支持非流式二遍识别，适合在松手后取得修正结果。这个适用性判断是本项目推断，不是官方对遥控器场景的保证。[官方产品动态](https://www.volcengine.com/docs/6561/162929?lang=en)

此票解决的是接入方向调查，不代表完整协议和真机效果已经验证。**API v3 的音频字段、结束帧和最终结果判定仍是实施前验证门槛**，不能依据本报告直接编码协议。

## 已核实的事实

| 项目 | 事实与来源 |
| --- | --- |
| 产品类别 | 官方将大模型流式识别用于实时音频流转文字，与录音文件识别区分。[产品页](https://www.volcengine.com/product/asr) |
| 接口候选 | 官方产品动态明确给出 `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`，并说明支持非流式二遍识别；同时提及 `bigmodel_nostream` 流式输入模式。[产品动态](https://www.volcengine.com/docs/6561/162929?lang=en) |
| SDK现状 | 已读取的官方 SDK 文档提供 Android 和 iOS 接入，配置 `/api/v3/sauc/bigmodel`、APP ID、Access Token、ResourceId 和 Seed 协议；不能由此宣称存在可直接使用的 macOS SDK。[SDK 文档](https://www.volcengine.com/docs/6561/1395846?lang=zh) |
| 资源与计费维度 | 官方并发查询文档列出小时版 `volc.bigasr.sauc.duration` 和并发版 `volc.bigasr.sauc.concurrent`。个人单人使用优先考察小时版，是项目建议。[官方资源表](https://www.volcengine.com/docs/6561/1476626?lang=en) |
| 新旧认证差异 | 官方录音文件极速版文档明确：旧版控制台使用 `X-Api-App-Key` + `X-Api-Access-Key`；新版用 `X-Api-Key`。**这是录音文件接口的证据，尚不能替代流式接口对新认证的逐项确认**。不要误用普通文本模型 Key 或云账号 AK/SK。[极速版 API](https://www.volcengine.com/docs/6561/1631584?lang=zh) |
| 文件接口备选 | 极速版支持 WAV/MP3/OGG OPUS，单次请求返回，需开通 `volc.bigasr.auc_turbo`；但它需要松手后提交文件，不作为首选交互路径。[极速版 API](https://www.volcengine.com/docs/6561/1631584?lang=zh) |
| 官方网关备选 | 边缘网关 Realtime 文档提供 `input_audio_buffer.commit` 与 `conversation.item.input_audio_transcription.completed` 事件。这是另一种网关协议，**不可套用到原生 ASR 二进制 WebSocket**。[网关文档](https://www.volcengine.com/docs/6893/1527759?lang=en) |

## 实施前必须补核的协议细节

首要参考：[大模型流式语音识别 API](https://www.volcengine.com/docs/6561/1354869)。本次抓取该页面被官方新域名跳转后的工具访问限制阻断，搜索也未返回其正文，因此下列内容明确未确认，不使用第三方转载冒充官方证据：

- 当前账号对应模型版本、资源 ID 和认证 Header；新版 API Key 是否适用于选定原生流式端点。
- PCM 支持的采样率、位深、声道、字节序；建议把遥控器解码结果规范为单声道 PCM，但参数必须按官方协议及真实音频确认。
- 推荐分包间隔；是否要求序号；最后一包的 message flags / 负序号精确定义；最终响应标志；连接关闭时机。
- 全文结果是累计替换还是增量；二遍返回如何覆盖首遍；超时、并发限制及错误码。
- 不宣称具备断点续传或请求幂等性。

建议有限时状态机：录音 → 等最终结果 → 插入一次 → 完成。网络故障保留本次临时音频供用户重试，不自动把不完整识别当成功；认证/额度问题指向设置；取消或旧会话迟到结果不写入。这些是工程建议，具体超时和重试策略留待可用官方正文与小样实测确定。

## 开通、费用与密钥

在用户自己的火山引擎语音控制台核对所开通的流式识别服务、资源及认证；不要求把密钥贴到聊天。账号资格、试用额度、现有充值和计费套餐未知。官方产品页当前显示流式识别新客套餐 30 小时 66 元，但促销不可作为正式单价或用户资格承诺。[产品页](https://www.volcengine.com/product/asr)

费用权威入口：[豆包语音计费说明](https://www.volcengine.com/docs/6561/1359370)。本轮正文访问失败，未确认后付费单价、计费取整及重试计费规则，不引用第三方报价估预算。

个人版建议用户自带语音 API 凭证，保存在 macOS Keychain generic-password 项；设置中可更新和删除，日志排除认证头，不写入源码、UserDefaults 或仓库。Apple 明确提供加密 Keychain 存储、SecItemAdd/CopyMatching/Update/Delete 生命周期。这是基于 Apple 能力作出的工程建议。[Apple Keychain](https://developer.apple.com/documentation/security/keychain-services/)、[凭据生命周期](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets?language=objc)

Keychain 保护静态存储，不使共享开发者密钥在客户端不可提取。未来若由开发者统一承担 API 费用，需要另行决策服务端凭证代理；不属于本轮个人真机闭环。
