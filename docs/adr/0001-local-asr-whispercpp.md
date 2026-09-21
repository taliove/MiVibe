# 0001. 本地语音识别引擎选用 whisper.cpp

日期：2026-09-17
状态：已接受

## 背景

MiVibe 的语音识别此前只有豆包云端一种引擎。需要新增本地（端侧、离线）识别能力，让用户可以下载开源模型在 Mac 上运行。约束条件：

- 用户以中文场景为主；
- 构建环境只有 Command Line Tools，没有 Xcode；
- 项目保持零外部依赖，.app 由 shell 脚本手工组装签名；
- 现有交互形态是"按住录音、松手后一次性转写注入"，没有边说边出字的流式 UI。

## 候选方案

**sherpa-onnx（k2-fsa）**：中文识别社区流行，支持 SenseVoice / Paraformer / Zipformer，中文效果优于同尺寸 Whisper，原生流式。但官方分发为预编译 XCFramework 与 onnxruntime 二进制，在无 Xcode、手工打包的现状下接入改造成本高，且打破零外部依赖的结构；模型为多文件结构，下载校验管理更复杂。

**WhisperKit / FluidAudio（Apple CoreML）**：纯 Swift、ANE 加速、功耗低。但模型生态锁定 Whisper 系，中文识别质量一般，且引入 CoreML 模型转换/编译链路。

**whisper.cpp**：GitHub 上最流行的本地 Whisper 实现。纯 C/C++ 源码，可直接作为 SwiftPM target 用 CLT 编译，Metal 加速可用；模型是单个 ggml 文件，下载、SHA256 校验、目录管理都简单。缺点：本质是批处理模型，无原生流式；中文效果弱于 SenseVoice，需要 small 以上档位补足。

## 决定

选用 **whisper.cpp** 作为本地识别引擎，置于 `ASRProvider` 协议之后（协议签名沿用现有 `transcribe(pcm: Data) async throws -> String`），豆包客户端同样适配该协议，引擎在设置中可切换。

流式能力不作为目标：现有交互本来就是松手后一次性出稿，本地批处理与体验天然对齐。

中文质量通过模型目录补足：提供 tiny / base / small / medium / large-v3-turbo 五档多语言模型（不提供 large-v3，turbo 全面占优；不提供 .en 英文专用版），按设备内存与 CPU 给出推荐档。

## 后果

- 构建链路保持"CLT + 手工打包"可用，只新增 SwiftPM 内源码 target，无预编译二进制依赖。
- 中文识别质量上限弱于 sherpa-onnx 方案；若未来中文准确率成为主要抱怨，可凭 `ASRProvider` 协议增加第二后端，本决策不锁死。
- 用户模型文件为单一 ggml 文件，存储于 `~/Library/Application Support/MiVibe/models/`，App 内置目录（含 ModelScope 主源、HuggingFace 备用源与 SHA256）。
