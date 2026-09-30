# 参与贡献 · Contributing

欢迎提 issue 和 PR。动手前请先读 [AGENTS.md](AGENTS.md)：构建命令、代码职责边界、必须保持的行为（输入不等于发送、失败可恢复、焦点改变后不强行注入）都在那里。
Issues and PRs are welcome. Please read [AGENTS.md](AGENTS.md) first: it covers build commands, module boundaries and the behaviors that must hold (typing never sends, failures are recoverable, no injection after the focus changes). It is written in Chinese.

## 开发 · Development

```sh
Scripts/fetch-whisper.sh     # 首次拉取固定版本的 whisper.cpp / fetch pinned whisper.cpp
swift build
swift run MiVibeTests        # 不用 swift test / not `swift test`
Scripts/build-app.sh debug   # 组装 build/MiVibe.app
```

需要 Apple Silicon 与 Swift 6，仅装 Command Line Tools 即可。Requires Apple Silicon and Swift 6; Command Line Tools are enough.

## 提交 PR · Pull requests

- 一个 PR 做一件事；提交信息用英文 Conventional Commits（`feat:`、`fix:`、`docs:` …）。One change per PR; English Conventional Commits.
- 改动核心逻辑时补测试，并在 `Tests/MiVibeTests/main.swift` 注册新套件。Add tests for core logic and register new suites in `Tests/MiVibeTests/main.swift`.
- 界面改动附截图；涉及遥控器、焦点注入或云服务的改动，写明实测环境与结果，未实测就明确说未验证。Attach screenshots for UI changes; for remote, injection or cloud changes, state what you actually tested.
- 修改 `README.md` 时同步 `README.en.md`；面向用户的改动在 `CHANGELOG.md` 的「Unreleased」一节中英文各记一条。Keep both READMEs in sync and add a bilingual entry under "Unreleased" in `CHANGELOG.md`.

## 隐私 · Privacy

不要在 issue、PR、测试样本或日志里附带 API Key、录音、口述内容或未脱敏的系统日志。安全问题按 [SECURITY.md](SECURITY.md) 私下报告。
Never include API keys, recordings, dictated text or unredacted system logs in issues, PRs, fixtures or logs. Report security issues privately per [SECURITY.md](SECURITY.md).

参与本项目即表示同意遵守 [行为准则](CODE_OF_CONDUCT.md)。By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
