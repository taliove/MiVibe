# 小米遥控器 2 Pro：独立接入研究

研究日期：2026-09-08。仅阅读资料和源码，未复制实现、安装或运行 mi-ao，也未连接用户硬件。网页抓取来自不同缓存时间，未取得统一 commit 快照；这里的源码结论是调查线索，实施前应固定所读版本。

## 结论

独立实现的技术路线可行：用 CoreBluetooth 接入 ATVV 语音服务，独立解码 ADPCM 为 PCM，向豆包 API 提供音频；按键另用 macOS HID 接入。mi-ao 对小米 2 Pro 固件 2671 报告了实际闭环，但不能推定用户设备、固件和 macOS 组合已兼容。[mi-ao 兼容说明](https://github.com/fanxeon/mi-ao/blob/main/docs/COMPATIBILITY.md)

建议第一版只承诺小米 2 Pro，协议优先 ATVV v1.0；8 kHz、v0.4、多型号作为可扩展边界，先不承诺。研究已经足够确定验证路线，尚不足以跳过真机探测。

## 已有证据及其等级

| 项目 | 事实与边界 | 一手来源 |
| --- | --- | --- |
| 小米音频 | 仓库作者报告固件 2671：ATVV v1.0、ADPCM 16 kHz、Hold-to-Talk、120 字节音频通知；松手有 AUDIO_STOP。属于作者真机报告，非小米官方规格或本机验收。 | [PROTOCOL.md](https://github.com/fanxeon/mi-ao/blob/main/docs/PROTOCOL.md) |
| ATVV 行为 | Google 托管的 Telink 参考遥控器固件有 v0.4/v1.0、8/16 kHz ADPCM、HTT 松手停止、SYNC 带预测值和步进索引等实现。参考固件证明协议存在这些机制，不证明小米完整实现所有机制。 | [Google 托管参考固件 gl_audio.c](https://android.googlesource.com/platform/hardware/telink/atv/refDesignRcu/+/86f501098fb4ba60954cb046201ffe43ca360c3e/application/audio/gl_audio.c) |
| 主机解析 | 已读取 mi-ao 的 ATVVProtocol.swift：分版本解析能力、开始/停止/同步事件，v1.0 连续解码状态由同步消息重置，支持 stream ID 和 keep-alive。 | [ATVVProtocol.swift](https://raw.githubusercontent.com/fanxeon/mi-ao/main/Sources/MiAo/ATVVProtocol.swift) |
| 蓝牙生命周期 | 已读取 BLEVoiceBridge.swift：检索已知/系统已连接设备，应用仍主动 connect，然后发现服务、协商；区分 disconnected/discovering/negotiating/ready/opening/streaming，断连安排重试。 | [BLEVoiceBridge.swift](https://raw.githubusercontent.com/fanxeon/mi-ao/main/Sources/MiAo/BLEVoiceBridge.swift) |
| 系统已连接设备 | Apple 明确 retrieveConnectedPeripherals 可返回其他应用已连接的设备，但本应用仍须 connect 才能使用。这不代表两个 ATVV 控制端同时操作不会冲突。 | [Apple API](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:)) |
| HID | 仓库文档描述独立 HID Usage→设备档案→预设→执行链路；固件 2671 按键已有作者验收。HIDButtonController 与 ADPCMDecoder 文件抓取失败，不能声称审阅过其内部实现。 | [README](https://github.com/fanxeon/mi-ao), [架构说明](https://github.com/fanxeon/mi-ao/blob/main/docs/ARCHITECTURE.md) |

公开检索出现标记 Google Confidential 的第三方镜像规范 PDF，本研究没有以它作为官方发布依据；优先采用 Google 托管参考固件。未找到小米公开 ATVV 开发规格。

## 独立实现需要保留的协议知识

ATVV 服务 UUID 为 AB5E0001-5A21-4F05-BC7D-AF01F617B664；同后缀 0002 为主机命令 TX、0003 为音频 RX 通知、0004 为控制通知。先发现并确认服务及特征属性、订阅控制和音频，再协商版本、编码和帧大小。不要只凭设备名称或硬编码 120 字节就宣布就绪。[协议说明](https://github.com/fanxeon/mi-ao/blob/main/docs/PROTOCOL.md)

能力响应存在小米特定字段错位的作者观察。独立实现应先保存用户设备脱敏原始响应，标准解析优先；仅在证据充分且歧义可排除时启用型号/固件限定兼容规则，不做通用“交换字节直到成功”。[主机解析源码](https://raw.githubusercontent.com/fanxeon/mi-ao/main/Sources/MiAo/ATVVProtocol.swift)

v1.0 数据帧可无逐帧头，不能当作每包独立 WAV 或 PCM；ADPCM 预测状态跨包延续，SYNC 才提供恢复点。建议解码器输出单声道 Int16 PCM 帧，附采样率和会话标识。云端分包与蓝牙通知分包分离，具体豆包输入格式由 API 研究确定。对丢包、损坏帧和同步缺失设明确失败状态。[主机解析源码](https://raw.githubusercontent.com/fanxeon/mi-ao/main/Sources/MiAo/ATVVProtocol.swift), [参考固件](https://android.googlesource.com/platform/hardware/telink/atv/refDesignRcu/+/86f501098fb4ba60954cb046201ffe43ca360c3e/application/audio/gl_audio.c)

参考固件在 HTT 松手后允许排空音频缓存再发送停止。因此不能在看到 HID release 时立刻丢弃后续通知；最终收口优先协议 AUDIO_STOP，加有界兜底超时，避免截掉尾字。该策略是基于参考固件的设计推论，实际时间窗待用户遥控器验证。[参考固件](https://android.googlesource.com/platform/hardware/telink/atv/refDesignRcu/+/86f501098fb4ba60954cb046201ffe43ca360c3e/application/audio/gl_audio.c)

## 配对、权限、共存与恢复

- 配对由 macOS 蓝牙设置完成。仓库针对该型号建议同时长按菜单和 HOME；原电视自动重连可能干扰。应在首次真机验证中对照用户设备说明书，不能将此组合键推广所有型号。系统配对、应用蓝牙授权、ATVV 就绪是三个不同状态。[配对指南](https://github.com/fanxeon/mi-ao/blob/main/docs/PAIRING.md)
- CoreBluetooth 需要正确用途声明，并处理 unauthorized/poweredOff/unsupported。HID 监听的授权要用 IOHIDRequestAccess 等 API 和实际返回值验证；不要因参考项目只列“蓝牙+辅助功能”，就预先承诺本实现无需输入监控。只处理所选遥控器，避免监听全局键盘。[Apple 蓝牙声明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription), [IOHIDRequestAccess](https://developer.apple.com/documentation/iokit/3181574-iohidrequestaccess)
- 从 BLE 特征读取音频，不等于通过 AVAudioEngine 读取 Mac 麦克风；本方案不必把遥控器注册为系统麦克风。是否需要额外 TCC 权限应在独立签名 App 上实测，不用“麦克风已授权”替代 BLE 就绪验证。
- 系统 HID 与应用 BLE 音频可构成双链路；mi-ao 的作者结果支持此路线。但与 mi-ao、其他遥控器工具或电视同时控制同一音频服务没有兼容保证。首次验收应只有一个 ATVV 控制程序，随后专门测冲突状态。[README](https://github.com/fanxeon/mi-ao), [Apple 已连接设备语义](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:))
- 普通按键原生动作和自定义动作可能重复触发。先测原始 usage、按下/松开、原生效果，再决定拦截办法；不要在协议研究阶段照搬系统 No Event 映射或修改系统键盘配置。[仓库按键说明](https://github.com/fanxeon/mi-ao#%E4%B8%80%E6%94%AF%E9%81%A5%E6%8E%A7%E5%99%A8%E5%A4%9A%E5%A5%97%E6%98%A0%E5%B0%84)
- 断连恢复设计建议：停止当前收音并清除解码状态；本次记录标记中断，不自动把不完整语句输入目标；退避重连，按键活动可唤醒重试。重新连接必须重新确认订阅与协商，不能仅凭 BLE connected 恢复 ready。这里是不复制源码的独立产品策略；重试参数与耗电需真机决定。

## 接下来应创建的验证任务

建立一个仅用于协议证据的真机验证任务：确认型号、固件、macOS 版本及目标设备身份；系统配对；读取 GATT 与能力；连续完成至少 20 次短按住说话及长句，检查首尾音、松手结束、SYNC 和正确 PCM；同时记录每个按键的按下/松开与原生效果；覆盖蓝牙关闭、休眠唤醒、移出范围、进程退出、快速重复录音与重复控制端冲突。产物为脱敏事件轨迹、用户同意的测试音频和验收表。

此任务只验证接入可行性，不负责开发完整应用。通过前保留“用户这支遥控器兼容性”未决；通过后才锁定最低 macOS 版本、按键拦截办法、异常收口和重连参数。
