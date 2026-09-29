# MiVibe · Agent 协作规范

本文件是仓库内所有 AI 编程助手共享的工程入口。面向用户的介绍与安装流程见 [README.md](README.md)；Claude Code 通过 [CLAUDE.md](CLAUDE.md) 引用本文件，通用规则只维护一份。

## 项目定位

MiVibe 是 macOS 菜单栏原生应用：小米蓝牙遥控器提供音频与按键，豆包或本地 whisper.cpp 完成识别，结果经过关键词纠正及可选改写后写入目标输入框。实体按键支持快捷键与应用内动作映射。

核心语义：**输入不等于发送；失败必须可恢复；焦点改变后不能强行注入。**

- 代码注释与工程文档使用中文；README 保持中文优先、中英文内容一致。
- 标识符沿用现有 Swift 风格；提交信息采用英文 Conventional Commits。
- 保持原生 SwiftUI / AppKit 方向，沿用现有层次与依赖。产品或架构变更先说明对现有合同的影响。

## 开始工作

1. 查看 `git status --short`，保留现有修改；未跟踪文件也可能是用户的工作。
2. 阅读 [CONTEXT.md](CONTEXT.md) 的相关术语、[SPEC.md](SPEC.md) 的对应章节及后续增补，再查看目标类型的头部注释、调用方和测试。
3. 按任务范围修改，用相应检查验证；交付时说明改变了什么、验证结果及尚未验证的部分。

**区分当前实现、产品约定与历史证据。** `SPEC.md` 包含早期基线和后续迭代，不能只读首段「明确不做」就否定已实现的本地识别。凭据存储等冲突应结合后续增补及 `Config.swift` 核对，不能据旧描述宣称已使用 Keychain。发现冲突时明确指出；不要以源码现状为由静默更改产品约定。

`.scratch/mivibe/` 是已入库的票据、协议研究、探针和验收证据，不是可清理的构建缓存。架构选型记录在 [docs/adr](docs/adr)。

## 构建与验证

在仓库根目录执行。Swift 6.0、Apple Silicon 是当前构建路径；SwiftPM 与手工组装 `.app` 支持仅安装 Command Line Tools 的环境，不要求完整 Xcode。

```sh
Scripts/fetch-whisper.sh              # 首次准备依赖：固定版本 + SHA256
swift build                          # 构建所有目标
swift run MiVibeTests                 # 执行全部测试，失败返回非零
Scripts/build-app.sh debug            # 组装 build/MiVibe.app 并签名
```

- `Vendor/whisper.cpp` 不入库；缺少它时直接 `swift build` 会失败。`build-app.sh` 会在目录不存在时自动拉取。
- 测试是自带 `Harness` 的 executable target，不是 XCTest；**用 `swift run MiVibeTests`，不用 `swift test` 作为验证入口**。
- 新增测试套件时，在 `Tests/MiVibeTests/main.swift` 注册 `XxxTests.run()`，复用 `Harness`。当前没有测试过滤参数；不要通过注释其他套件缩减最终验证。
- 纯文档变更检查事实、路径、链接、命令和语言一致性即可，不必下载模型或构建本地引擎。
- 核心逻辑变更运行构建与完整测试；界面变更还需打开应用验证真实交互；打包变更验证 bundle、资源与签名。
- 硬件、焦点注入与云服务行为不能仅靠单元测试宣称通过。先阅读 `Sources/MiVibeProbes/main.swift`，按任务选择探针、准备设备与目标输入框，记录环境和结果；无条件实测时明确标记未验证。

CI 顺序见 `.github/workflows/ci.yml`：拉取依赖 → 构建 → 测试 → ad-hoc 签名打包。`v*` 标签触发 `.github/workflows/release.yml` 的测试、打包和发布；不要把推送标签当作普通验证步骤。

安装与签名命令的副作用：

| 命令 | 行为 |
| --- | --- |
| `Scripts/setup-signing.sh` | 创建固定本地签名身份及相关钥匙串配置，通常只需首次运行。 |
| `Scripts/build-app.sh [debug\|release]` | 重建仓库内 `build/MiVibe.app`，默认 release；可能下载依赖。 |
| `Scripts/deploy.sh [debug\|release]` | 关闭 MiVibe、构建、替换 `/Applications/MiVibe.app` 并启动，默认 release。 |
| `MIVIBE_SIGN_IDENTITY=- Scripts/build-app.sh release` | 显式使用 ad-hoc 签名，适合 CI 组装验证。 |

只在任务需要安装、权限或发布验证时执行相应操作；普通文档编辑不触碰用户的已安装应用与系统授权。

## 代码导航与职责

| 位置 | 职责与边界 |
| --- | --- |
| `Sources/MiVibe/Core/Coordinator.swift` | `@MainActor` 主编排者，串联遥控器、识别、纠正、改写、队列和注入。 |
| `Sources/MiVibe/UI/` | SwiftUI 设置、菜单栏界面，以及 AppKit 浮条；不承载协议与队列规则。 |
| `Sources/MiVibeCore/Core/` | 配置、队列、按键路由与映射、权限、待处理存储。 |
| `Sources/MiVibeCore/Audio/` | ADPCM 解码与音量计算。 |
| `Sources/MiVibeCore/ASR/` | 识别接口、豆包协议、本地引擎、模型下载与关键词纠正。 |
| `Sources/MiVibeCore/Rewrite/` | 模式、服务商配置、LLM 请求与原文回退。 |
| `Sources/MiVibeCore/Remote/` | CoreBluetooth 音频与 IOHIDManager 按键接管。 |
| `Sources/MiVibeCore/Input/` | 焦点快照、AX 注入、剪贴板降级与快捷键合成。 |
| `Sources/MiVibeProbes/` | 独立诊断入口，与应用共享 Core。 |
| `Tests/MiVibeTests/` | 可脱离硬件运行的断言测试。 |
| `Package.swift` / `Scripts/` | whisper.cpp 编译清单、依赖获取、资源装配、签名与部署。 |

让 `InputQueue`、`KeyRouter`、映射解析等规则保持可独立测试。网络、文件、硬件及系统事件副作用留在相应边界实现中；`MiVibeCore` 不依赖 SwiftUI。不要把模型下载、LLM 请求等新增边界遗漏在架构描述之外。

## 主链路

```text
RemoteManager：AUDIO_START → 音频解码 → AUDIO_STOP
  → Coordinator → ASRProvider（DoubaoClient / LocalWhisperProvider）
  → KeywordCorrections → InputQueue
  → drain：可选 RewriteEngine → 重新校验焦点 → TextInjector

KeyReader：取得 HID 独占 → KeyRouter
  → KeySynth（快捷键 / 原生键转发）或 MiVibe 应用内动作
```

`Coordinator.drain()` 负责自动按序注入；显式恢复入口为 `resumeHere`。队列保存**关键词纠正后的识别文本**，改写在注入前进行，重试使用当时的模式，不把改写结果覆盖成队列原文。

## 必须保持的行为

### 配置与标识符

- `Config.Data` 新增持久化字段保持 `Optional`，或在明确迁移方案中提供兼容解码。嵌套结构同样需容忍旧配置缺字段，并验证旧数据可读。
- `Config.load()` 解码失败会返回空配置，后续保存可能覆盖原有 API Key；不能让一次字段扩展使整个配置失效。
- `RemoteButton.id` 是持久化键，不得随意改名。语音键与电源键的 `isMappable` 为 false，不进入可配置映射。

### 录音、队列与按键

- 录音由设备自发的 `AUDIO_START` 开始，以 `AUDIO_STOP` 收口。HID 松开之后仍可能有尾帧，不能用它截断录音，也不能用 HID 语音键事件主动开启录音。
- 固件 2671 的 `GET_CAPS` 可能非标准，codec 必须由 `AUDIO_START` 字段再次确认。云端识别接收解码后的 PCM，不能上传原始 ADPCM。
- `InputQueue.capacity` 当前为 2。保持录制顺序，阻塞项不能被后续结果越过；重试、恢复与丢弃是显式操作。
- `KeyReader.isExclusive == false` 时，不合成或转发按键，避免与系统原生事件重复。设备重新出现时继续尝试独占；未映射键的按下 / 抬起须成对转发。
- 模式选单打开时临时捕获方向、确认、返回键，不能同时执行这些键的普通映射。

### 识别、改写与注入

- 本地识别失败或缺模型时不能静默切换云端；原文直出不调用 LLM。使用本地识别但启用云端改写时，文字仍会外发，界面和文档必须准确表达。
- `RewriteEngine.apply` 保持不抛错；LLM 超时（当前 5 秒）、失败、空返回时回落原文。改写不能导致用户文字丢失。
- 异步改写后重新比对录音时的焦点快照，目标改变则暂存；只有用户显式恢复时才改用新目标。
- 输入不附加 Return，不把口述「发送」解释成提交指令；发送来自独立按键动作。
- 注入先探测 `AXSelectedText`，并读回验证；不要盲目 AX 写入后再粘贴。结果不明确时保留待处理状态。安全输入框拒绝注入。
- 在抓取焦点前启用 `AXEnhancedUserInterface`，避免 Chromium 首次重建 AX 树造成焦点 identity 变化。剪贴板降级须保护原内容，并尊重第三方对剪贴板的修改。

### 界面与签名

- 浮条不抢焦点，由 `AppDelegate` 持有；不能依赖只有菜单弹层打开时才存在的内容视图。主链路挂接应随应用启动发生。
- 保持固定签名身份；不要为普通构建重建证书或重置 TCC。ad-hoc 签名随二进制改变，可能导致重新授权。
- 打包本地引擎时保留 Metal 内核及相关头文件资源；修改 vendored 版本需同时核对下载脚本、SHA256、`Package.swift` 清单和资源装配。

## 数据与排障

| 数据 | 位置 / 约束 |
| --- | --- |
| 配置与明文 API Key | `~/.config/mivibe/config.json`，`0600`；目录 `0700`。不使用 Keychain 存 API Key。 |
| 待处理内容 | 同目录 `pending.json`，明文、`0600`；启动读取后删除，音频留存上限 4 MiB，超限仅留文字。 |
| 本地模型 | `~/Library/Application Support/MiVibe/models/`；下载到临时文件，SHA256 通过后落位。 |

调试与测试使用临时目录和合成数据，不读取或覆盖用户真实 API Key、待处理录音与签名文件。不要把密钥、录音、用户口述内容写入提交、测试样本或交付输出。

链路日志应只记录状态、标识与长度，避免记录正文。注意当前 `Coordinator.transcribe` 的关键词纠正分支仍将文本插值到日志中，不能宣称现有实现已完全不记录正文；涉及该路径时核对系统隐私标记，按任务范围处理。

```sh
log show --predicate 'subsystem == "io.github.taliove.mivibe"' --last 10m --info
```

真实日志可能含用户数据；仅提取排障所需信息，并在共享前脱敏。最终报告区分本次验证、仓库历史实测和未验证推断。
