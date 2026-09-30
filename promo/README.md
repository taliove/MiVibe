# MiVibe 宣传片

约 46 秒的 MiVibe 产品宣传片工程：画面用 [Motion Canvas](https://motioncanvas.io)（MIT）以 TypeScript 矢量绘制，配乐由本目录的 Node 脚本逐采样合成，没有任何第三方素材，零版权风险。

| 产物 | 规格 |
| --- | --- |
| `output/mivibe-promo.mp4` | 1920×1080 · 60 fps · H.264（yuv420p，faststart）+ AAC 192k · 46.0 s |
| `output/mivibe-loop.webp` | 1280×720 · 24 fps · 8 s 循环动图，取自「流程 + 浮条」段，给 README 顶部用 |
| `output/stills/*.png` | 自检时抽出的 8 张代表帧 |

`output/` 与 `music/out/` 都是生成物，已在 `.gitignore` 中忽略。

## 环境

- Node ≥ 22.18（脚本直接以 `.ts` 运行，依赖 Node 内置的类型擦除；开发时用 Node 26）
- pnpm（锁文件为 `pnpm-lock.yaml`）
- 本机 Google Chrome（无头渲染用；其他 Chromium 内核浏览器可用 `CHROME_PATH=/path/to/chrome` 指定）
- 系统 `ffmpeg`（封装音轨、自检）
- 生成 WebP：`ffmpeg` 带 `libwebp` 时直接用；Homebrew 默认的 ffmpeg 不带，会自动改用 `img2webp`（`brew install webp`）

逐帧编码 H.264 用的是 `@motion-canvas/ffmpeg` 自带的 ffmpeg 二进制，安装依赖时会下载（`pnpm-workspace.yaml` 已允许其安装脚本）。

## 安装

```sh
pnpm install
```

## 预览

```sh
pnpm music   # 先生成配乐：编辑器预览与渲染都会载入 music/out/soundtrack.wav
pnpm dev     # 打开 Motion Canvas 编辑器（默认 http://localhost:9000），可拖时间轴、同步听配乐
```

## 渲染成片

```sh
pnpm build   # = pnpm music && pnpm frames && pnpm encode
pnpm check   # 切点与节拍对齐表、抽帧、响度与文件信息
```

分步说明：

| 命令 | 作用 |
| --- | --- |
| `pnpm music` | 合成配乐 → `music/out/soundtrack.wav`（约 3 秒） |
| `pnpm frames` | 启动 Vite 开发服务器，用无头 Chrome 打开 `render.html`，由 Motion Canvas 核心 `Renderer` 逐帧导出，经官方 ffmpeg 导出器编码 → `output/frames/video.mp4`（无声，约 1–2 分钟） |
| `pnpm encode` | 合成音轨与 faststart → `output/mivibe-promo.mp4`；截取循环片段 → `output/mivibe-loop.webp` |
| `pnpm check` | 在每个预期切点附近做场景检测，列出实测帧与节拍网格的偏差；抽帧到 `output/stills/`；报告积分响度与真峰值 |

只渲染一段（调试用，单位秒）：`node scripts/render.ts --from 14 --to 30`。

### 为什么这样渲染

Motion Canvas 的官方导出流程在编辑器界面里点「Render」。这里保留官方组件，只把界面换成无头：`render.html` 直接创建核心库的 `Renderer` 并调用 `render()`，帧仍交给 `@motion-canvas/ffmpeg` 导出器，经 Vite HMR 通道送到服务端 ffmpeg。好处是可复现、可放进脚本，也不必自己实现逐帧截图。

## 重新生成配乐

```sh
pnpm music
```

- 120 BPM、48 kHz、16-bit 立体声；鼓、贝斯、supersaw 铺底、琶音、上升音效、冲击与转场声全部在 `music/instruments.ts` 里用振荡器、滤波器和噪声合成。
- 编曲在 `music/arrangement.ts`，母带（K 加权响度测量、归一、前视限幅、淡出、WAV 写出）在 `music/master.ts`。目标 −14 LUFS，采样峰值不超过 −1 dBFS。
- 随机数带固定种子，重复运行得到逐字节相同的文件。

### 卡点：画面与配乐共用一张节拍表

`src/timing.ts` 是唯一的时间来源：BPM、每个段落的起止拍、功能卡片每张几拍、主题切换在哪几拍、冲击前上升段从哪拍开始。场景用 `at(拍, 动作)` 排期，配乐用同一组常量摆放鼓点与音效。60 fps 下一拍正好 30 帧，所有切点都落在整数帧上，`pnpm check` 会逐个核对（当前全部 0 帧偏差）。

改节奏或段落长度时只改 `src/timing.ts`，再运行 `pnpm build`。

## 分镜

| 时间 | 段落 | 内容 |
| --- | --- | --- |
| 0–4 s | intro | 黑场，遥控器浮现，第 2 拍语音键亮起潮汐青并泛起涟漪；「按住，说话。」 |
| 4–14 s | pipeline | 声音 → 识别 → 关键词纠正（mi vibe → MiVibe）→ 改写（可选）→ 写入输入框；浮条从「正在听」经签名动作到 ✓ 已输入 |
| 14–30 s | features | 六张功能卡（每张 4 拍）+ 六宫格总览 |
| 30–40 s | themes | 设置窗口按拍轮换六套主题；最后 4 拍上升段，图标飞到中央 |
| 40–46 s | outro | 冲击，标志声波跳动，MiVibe / 开源 · macOS / 仓库地址，淡出 |

## 目录

```text
src/
  timing.ts            节拍与段落表（画面、配乐共用）
  copy.ts              全部上屏文案
  project.ts           Motion Canvas 项目入口
  brand/               色板（取自 Theme.swift）、标记几何（取自 BrandMark.swift）、字体
  components/          背景、品牌标记与图标、浮条、遥控器、窗口、设置窗口、阶段芯片、声波
  components/features/ 功能卡片外壳与六个插画
  scenes/              五个场景
  render/main.ts       无头渲染入口（render.html 载入）
music/                 配乐合成：dsp / instruments / arrangement / master / generate
scripts/               render（逐帧）、encode（封装与 WebP）、check（自检）
```

## 与 MiVibe 设计系统的对应

- 品牌标记六个圆角矩形与圆角半径逐字移植自 `Sources/MiVibeCore/Core/BrandMark.swift`；应用图标按 `Scripts/make-icon.swift` 的比例（标记占 64%）重绘。
- 六套主题色板逐字取自 `Sources/MiVibeCore/Core/Theme.swift`，深色画面使用各主题的深色侧。
- 浮条动效依据 `.scratch/mivibe/design/motion-v1.html`：签名动作 420 ms、三根声波、转写圆弧 1.2 s/圈、改写四角星、成功绿对勾、需处理轻晃、换主题 250 ms 渐变。
- 遥控器几何取自 `Sources/MiVibe/UI/RemoteControlView.swift`。
- 画面全部为矢量重绘，不含真实桌面截图或个人内容。

## 字体与许可

| 字体 | 用途 | 许可 |
| --- | --- | --- |
| [Inter](https://github.com/rsms/inter) | 拉丁文字 | SIL Open Font License 1.1 |
| [Noto Sans SC](https://github.com/notofonts/noto-cjk) | 中文 | SIL Open Font License 1.1 |
| [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) | 等宽标签 | SIL Open Font License 1.1 |

字体通过 `@fontsource/*` npm 包引入，不在仓库内保存字体文件。OFL 允许在视频等作品中嵌入使用。

Motion Canvas 与本工程代码均为 MIT 许可；配乐为程序生成，无第三方采样。
