# MiVibe · Claude Code

@AGENTS.md

## 使用方式

[AGENTS.md](AGENTS.md) 是本仓库共享的协作规范，包含构建命令、代码导航、行为约束与数据边界；上方导入让 Claude Code 直接加载它。其他阅读器若不支持导入语法，请先打开该文件。

- 开始前查看工作区状态，阅读共享规范及任务涉及的源码、测试。
- 中文沟通与文档优先；代码注释使用中文，提交信息使用英文 Conventional Commits。
- 通用规则只修改 `AGENTS.md`；本文件仅保留 Claude Code 入口说明，避免两份规范漂移。
- 按任务运行适当验证，报告具体结果。不要把构建通过当作遥控器、权限或跨应用输入已经实测。

## 按需阅读

| 要了解什么 | 入口 |
| --- | --- |
| 产品介绍、安装与使用 | [README.md](README.md) |
| 领域术语与输入 / 发送语义 | [CONTEXT.md](CONTEXT.md) |
| 产品与协议合同、后续迭代 | [SPEC.md](SPEC.md) |
| 架构决策与本地识别选型 | [docs/adr](docs/adr) |
| 历史研究、票据与真机证据 | [.scratch/mivibe](.scratch/mivibe) |

优先阅读相关章节与类型，遇到证据冲突时再追溯对应记录，无需每次加载全部历史材料。
