# 豆包流式 ASR 线上协议帧合同核验

核验日期：2026-09-09。未调用识别 API、未消耗任何费用。结论来自官方 SDK 源码与多份独立实现交叉比对，回应 [08 票](../issues/08-asr-wire-validation.md) 前半（flags/sequence、result 形态、is_last_package 包装来源）。本文档补充 [doubao-contract.md](doubao-contract.md)，不重复其公开文档部分。

## 证据来源（按可信度排序）

1. **官方 SDK**：`volcengine/veadk-python`（火山引擎官方 org，Apache 2.0，版权声明 Beijing Volcano Engine）`veadk/toolkits/audio/asr/asr_client.py`。其 `ResponseParser`/`RequestBuilder` 即官方 `sauc_python` 示例的 `protocol.py` 同族实现。
2. **官方示例转引副本**：`HorizonRobotics/HoloAgent` 的 `audio/volcengine_doubao_asr.py`、`LXXK91/HuoHuoAI` 的 `serve/sauc_websocket_demo.py` 等，解析逻辑与官方逐行一致（同一 flags 位逻辑）。
3. **独立实现**（非示例血统，交叉验证）：
   - `joewongjc/type4me`：macOS Swift 生产应用，`Type4Me/Protocol/VolcHeader.swift`、`VolcProtocol.swift`、`VolcASRClient.swift` 及配套测试——**本项目未来实现的直接同平台参考**。
   - `xinnan-tech/xiaozhi-esp32-server` 的 `doubao_stream.py`：Python 生产项目，独立解析路径。

## 三个存疑点的结论

### 1. `is_last_package` 的包装来源：官方示例封装层，非服务器 JSON 字段

官方解析器（veadk `ResponseParser.parse_response`）：

```python
if message_type_specific_flags & 0x01:
    response.payload_sequence = struct.unpack(">i", payload[:4])[0]  # 大端有符号
if message_type_specific_flags & 0x02:
    response.is_last_package = True
if message_type_specific_flags & 0x04:
    response.event = struct.unpack(">i", payload[:4])[0]
```

`is_last_package` 是官方 `AsrResponse` 包装对象根据**帧头 flags 第 0x02 位**计算的布尔值，服务器 JSON 正文里没有这个字段。文档页面示例输出的 `response.to_dict()` 即该包装。自研解析器应直接判 flags 位，不要在 JSON 里找 `is_last_package`。

### 2. 最后响应的 flags/sequence

- **判结束只看 flags 位**：`flags & 0x02` 即最后一包；sequence 是否存在只看 `flags & 0x01`。官方解析器**不检查 sequence 符号**——doubao-contract.md 记录的"历史文档要求负 sequence、示例却展示正 3"差异因此无害：符号不参与结束判定。
- **上行末包存在两种可用惯例**（线上均有生产使用）：
  - 官方示例/veadk：末包 flags=`0b0011`（NEG_WITH_SEQUENCE），seq 取负，payload 为 gzip 压缩的空字节。
  - xiaozhi/Type4Me：末包 flags=`0b0010`（末包无 sequence），空 payload（Type4Me 甚至不压缩）。
  - 结论：服务端对两种末包都接受；本项目实现可任选，建议跟随官方示例（`0b0011`+负 seq+空 gzip）。
- **分歧残留**：flags 第 `0x04` 位，veadk 解析为 4 字节 `event` 整数，Type4Me 标注为 bigmodel_async 最终响应标志（`asyncFinal`）。两者对同一端的描述不同，**只有真实帧能裁决**——列入实测验收取证项。

### 3. `result` 形态：对象，不是 list

官方包装不约束形态（`payload_msg = json.loads(...)` 原样透传）；三个独立消费方（HoloAgent、xiaozhi、Type4Me）全部按 `payload_msg["result"]["text"]` + `result["utterances"][]`（`utterances[i].definite`）读取——即 `result` 为 **object**。当前文档表格称 `result` 为 list 与实际实现不符，解析器按 object 建模；真机首帧时打印原始 JSON 归档，作为最终证据。

## 上行/下行帧摘要（实现用速查）

- 握手认证头（当前文档，API Key 方式）：`X-Api-Key` + `X-Api-Resource-Id`（2.0 小时版 `volc.seedasr.sauc.duration`）+ `X-Api-Request-Id`（UUID）。旧版 App Key/Access Key 头仍被官方 SDK 使用（`X-Api-App-Key`/`X-Api-Access-Key`/`X-Api-Connect-Id`）。Type4Me 两套都支持。
- 首包：type `0b0001`，flags `0b0001`（带正 sequence，seq=1），JSON+gzip。
- 音频包：type `0b0010`；官方惯例每包带递增正 seq；gzip 压缩 PCM；官方示例按 200ms 分段。
- 下行：type `0b1001` 全量响应 / `0b1111` 错误（错误 payload 前 4 字节为大端 code）。sequence/事件字段按上述 flags 位读取，payload 长度为其后 4 字节大端。
- 下行 payload 的 gzip/JSON 由帧头声明，**以帧头为准，不做全局假设**。

## 二遍识别配置观察

- veadk 默认 `enable_nonstream: False`；Type4Me 生产配置 `enable_nonstream: true` + `end_window_size: 3000`。项目候选建议评估二遍（[doubao-contract.md](doubao-contract.md)）；尾字延迟必须实测，列入实测验收取证项。

## 实测待取证清单（08 票后半，需账号与费用授权）

1. 握手：当前文档三头（`X-Api-Key`/`X-Api-Resource-Id`/`X-Api-Request-Id`）对 2.0 小时版资源是否一次通过。
2. 真实下行帧：打印首个与最终响应的**原始字节+解压 JSON**，裁决 flags `0x04` 含义与 `result` 形态。
3. 16 kHz mono pcm_s16le 200ms 分包端到端识别一段授权短音频，拿到最终全量文本。
4. 中途取消（直接关连接/发末包前中断）的服务端行为与迟到结果形态。
5. 开启 `enable_nonstream` 的二遍识别：最终确定文本到达的尾延迟实测值。
6. 账单核对：上述调用（含失败/取消/二遍）在控制台的实际计费归因。

## 实测裁决（2026-09-09，真凭据+真服务）

探针 [`../diagnostics/asr-probe.py`](../diagnostics/asr-probe.py) 按上清单逐项执行，证据帧存 `diagnostics/asr-evidence-*.jsonl`。实际费用合计约 0.004 元（台账 `asr-usage.jsonl`），远低于 5 元授权上限。

1. **握手通过**：当前文档三头 + `volc.seedasr.sauc.duration` 一次成功，账号 2.0 小时版已开通。
2. **真实帧裁决**（run 模式 17 帧）：
   - 服务端响应（type 9）中间帧 flags=1 带正递增 seq（1..15）；最终帧 flags=3、**seq=+15 为正**——历史文档"负 sequence"之说对下行不成立，判结束只看 flags 0x02 位，与官方 SDK 一致。
   - **flags 0x04 全程未出现**：veadk 的 event 字段与 Type4Me 的 asyncFinal 解读在本流程均未观测到；本项目只依赖 0x02 位即可，0x04 按"保留未知位，忽略"处理。
   - `result` 全帧为 **object**（keys: text/utterances/additions/prefetch），文档表格"list"之说不实。
   - **服务端响应不压缩**（comp=0），即使上行全 gzip——解析必须以每帧头为准，不可全局假设。
3. **端到端识别通过**：16 kHz mono pcm_s16le、200ms 分包、官方末包惯例（flags=3+负 seq+gzip 空包），6.12s `say` 合成语音识别为"你好，这是小米遥控器语音输入的识别测试，今天9月9号。"（ITN 生效）。
4. **取消**：发送 1s 后 `transport.abort()`  abrupt 断开，客户端无异常后果；该次调用的计费归因需控制台账单核对（见下）。
5. **尾延迟实测**（同一段 6.12s 音频）：单遍 0.209s；二遍（enable_nonstream=true）0.767s，二遍文本标点更准（句号分句）。按住说话场景两者均可接受；以准确率为先则选二遍，+0.56s 尾延迟换更准分句。
6. **账单核对（未决，留人工）**：控制台账单的失败/取消/二遍归因无法在客户端验证，需用户在控制台核对四次调用（约 14.25s 音频）的实际扣费。此项不阻塞协议合同成立，归入地图"费用展示体验"雾区。

## 边界声明

- 协议合同已可执行：握手、分包、末包、结束判定、解析容错均经真实服务确认；残留唯账单一项（人工核对）。
- 凭据由用户主动贴出一次后立即转存本机 Keychain（`mivibe-volc-apikey`），未进仓库；建议实测期结束后用户在控制台轮换该 Key。
- 探针是验证工具，不是正式应用代码；正式实现应参考 Type4Me 的 Swift 协议层结构重写。
