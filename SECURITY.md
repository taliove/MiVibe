# 安全策略 · Security policy

MiVibe 需要辅助功能与输入监控权限，并会把文字写入其他应用的输入框。我们认真对待任何可能让这些能力被滥用的问题。
MiVibe holds Accessibility and Input Monitoring permissions and types into other apps, so we take anything that could let those capabilities be abused seriously.

## 支持的版本 · Supported versions

只有[最新发布版本](https://github.com/taliove/MiVibe/releases/latest)会收到安全修复。
Only the [latest release](https://github.com/taliove/MiVibe/releases/latest) receives security fixes.

## 报告漏洞 · Reporting a vulnerability

请**不要**在公开 issue 里报告安全问题。请通过 GitHub 的 [私密漏洞报告](https://github.com/taliove/MiVibe/security/advisories/new) 提交，附上版本号、macOS 版本、复现步骤和影响。报告里不要附带你的 API Key、录音或口述内容。
Please do **not** open a public issue. Use GitHub [private vulnerability reporting](https://github.com/taliove/MiVibe/security/advisories/new) and include the version, macOS version, reproduction steps and impact. Do not include API keys, recordings or dictated text.

我们会在 7 天内确认收到，修复发布后在更新记录中致谢（如你愿意）。
We aim to acknowledge reports within 7 days and will credit you in the changelog once a fix ships, if you wish.

## 范围 · Scope

- 在范围内 In scope：注入到非预期的窗口或安全输入框、按键接管残留或绕过、配置与待处理文件的权限、日志泄露正文、发布包完整性。Injection into an unintended window or secure field, key takeover leaks or bypasses, permissions on config and pending files, dictated text leaking into logs, release package integrity.
- 不在范围内 Out of scope：未公证 / 临时签名本身（已在 README 说明）、豆包或 LLM 服务商自身的安全问题。The unnotarized, ad-hoc signed builds themselves (documented in the README), and security issues in Doubao or LLM providers.
