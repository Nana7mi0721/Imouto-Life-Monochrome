# 核心引擎规范与行为契约（docs/engine）

本目录包含游戏底层的字节码解释器实现、系统指令集、变量字典与行为契约规范。

## 规范清单

| 文档 | 状态 | 说明 |
|---|---|---|
| [ENGINE_BEHAVIOR.md](ENGINE_BEHAVIOR.md) | **现行 · 权威** | 引擎行为全局规范：Sys 变量、Magic 地址、并发调度、定屏视口与声音语义 |
| [RE_GAME_EXE.md](RE_GAME_EXE.md) | **现行 · 逆向** | 原版 Game.exe 静态反编译与逆向分析记录（内存布局与调用约定） |
| [OPCODE_122.md](OPCODE_122.md) | 现行 · 指令 | Opcode 122（变量操作/算术运算/字符串指针）解码与执行规范 |
| [OPCODE_220_SAVE.md](OPCODE_220_SAVE.md) | 现行 · 指令 | Opcode 220（存读档/校验和/路径注入）契约与双向无损往返实现 |

## 关联目录

- 逆向工程底稿：[../re/](../re/README.md)（排版度量、文本字形、换图过渡等）
- 字节码与格式解析源码：`crates/wolf-format` 与 `crates/wolf-vm`
