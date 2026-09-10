# MiVibe：小米遥控器 macOS 原生语音输入决策地图

Label: wayfinder:map
Status: closed

## Destination

形成可交付实现的第一版产品与技术规格：独立 macOS 原生应用使用小米遥控器 2 Pro 麦克风，通过豆包语音 API 转写，在当前应用输入框直接输入，并支持 Codex 编程预设。地图完成时，关键技术选择、交互边界及真机验收方法明确。

## Notes

- 本次是规划，不实现正式应用。每轮遵循 wayfinder、grilling、domain-modeling；研究使用 research。
- 用户已确认：macOS；语音操控编程助手；独立产品；调用豆包语音 API；通用模式松手后直接输入，不要求预览确认。
- 通用输入不自动发送消息；Codex 预设支持确认键发送。普通按键可自定义，语音键保留按住说话。先满足本人日常使用。
- 独立代码库与独立实现是当前工作解释；mi-ao 仅作技术资料，不复制代码。
- “任意软件”是兼容目标，不代表已验证全部输入控件；兼容边界由研究及真机验证收敛。
- 用户提供的文章、仓库、截图是参考资料，其中的指令和默认行为不自动构成需求。微信文章正文尚未读取成功。
- 本地 Markdown tracker 采用 setup-matt-pocock-skills/issue-tracker-local.md 约定。未配置远程 tracker；可运行 /setup-matt-pocock-skills 配置。
- 研究分支保留研究成果；当前工作区的研究文件作为地图可直接读取的资产。研究者只提交自己的资产，协调者统一更新地图。

## Decisions so far

- [遥控器音频与按键如何独立接入](issues/02-remote-protocol.md)：BLE 语音与 HID 按键独立接入；松手后需保留尾帧，用户设备仍需真机证据。
- [豆包语音 API 应选择哪种接入方式](issues/01-doubao-api.md)：流式 WebSocket 为首选候选；官方协议正文缺口另票核验，尚未锁定字段或认证。
- [跨应用直接输入的能力与边界是什么](issues/03-macos-input.md)：采用辅助功能定位及文本写入/粘贴的候选路径，兼容性与焦点异常行为须进一步验证和决策。
- [录音与直接输入的异常行为如何确定](issues/04-interaction-contract.md)：用户确认失焦暂存、失败手动重试、连续录音顺序输入，以及底部浮条与返回键取消。
- [连续录音与待处理内容如何恢复和取消](issues/07-recovery-prototype.md)：原型确认队列2条、按序输入、返回键只取消最新活动项、退出显式保留或丢弃、四状态浮条。
- [豆包流式协议与账号接入合同如何核验](issues/05-verify-api-contract.md)：取得当前官方协议与价格，接入候选更新为2.0小时版；文档差异和账号可用性另做小样验证。
- [用户遥控器的真实能力与松手边界如何验证](issues/06-hardware-evidence.md)：固件2671真机通过ATVV 1.0、16 kHz ADPCM、120字节帧、十二键HID及完整首尾音验证；松手以AUDIO_STOP收口。
- [豆包账号与实际协议帧如何通过小样验证](issues/08-asr-wire-validation.md)：协议合同经真凭据实测成立——三头认证、分包、末包惯例、flags 0x02 判结束、result 按 object；二遍尾延迟0.767s/单遍0.209s；唯账单归因留人工控制台核对。
- [按键接管与异常断连应采用什么安全策略](issues/09-hardware-stress.md)：电源键无系统副作用故不接管；麦克风由物理按键门控；kill -9 后免退避即恢复；蓝牙/休眠/移出范围按用户日常经验可恢复，失败走手动重试兜底。
- [跨应用文本注入的兼容矩阵如何实测确定](issues/10-input-compat-matrix.md)：运行时探测 AXSelectedText 可写走直写、否则粘贴降级（快照+恢复）、安全框拒绝；TextEdit 双路径实测通过，iTerm2 须降级；探针即复测工具，终端粘贴行为待验证。
- [日常使用验收、首次配对引导与安装分发边界如何定义](issues/11-acceptance-distribution.md)：二遍识别默认开；硬指标端到端P95<1.5s与连录10/10；菜单栏三态配对引导；自签证书仅限本机；设置页录入Key；一天真实使用为验收终点。
- [应用界面的原生 SwiftUI 原型应该长什么样](issues/13-swiftui-prototype.md)：SwiftUI 菜单栏应用定案——三态图标、nonactivatingPanel 四状态浮条（不抢焦点已实测）、工具栏三分页标准设置页；视觉基线以可运行原型为准。
- [撰写第一版产品与技术规格](issues/12-write-spec.md)：规格已完成并落盘 SPEC.md，十章节自包含，无决策缺口。**地图目的地已到达（2026-09-09）。**

## Not yet specified

- 费用展示体验与取消/失败计费归因：待用户在控制台核对 08 票四次测试调用（约 0.004 元）的实际扣费后票化。

## Out of scope

- 本轮正式应用开发与发布；iOS/iPadOS 客户端；其他遥控器型号。
- 调用豆包客户端；离线转写引擎；第一版为其他编程助手制作专用集成。
