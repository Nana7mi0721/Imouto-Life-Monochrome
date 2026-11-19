# 前端与混合交互架构（docs/frontend）

本目录包含基于 Godot 4 的混合前端架构设计、GDExtension 绑定桥接及运行时调试指南。

## 文档清单

| 文档 | 状态 | 核心内容 |
|---|---|---|
| [GODOT_MIGRATION.md](GODOT_MIGRATION.md) | **现行 · 架构** | Godot 4.7.2 迁移全景：GDExtension 桥接设计、视口渲染、混合输入分发与像素对齐方案 |
| [GODOT_DEBUGGING.md](GODOT_DEBUGGING.md) | 现行 · 调试 | Godot 端运行问题排查、日志开关、断点捕获与实机异常复现技巧 |
| [MCP_AUDIT_PROBE.md](MCP_AUDIT_PROBE.md) | 现行 · 测试 | MCP 运行时自动化探针架构：只读事件枚举、状态监控与 Headless 驱动 |

## 快速构建与验证

- 编译动态链接库：`bash tools/build-godot.sh`（产出 `godot/bin/wolf_gdext.dll`）
- 执行 Headless 冒烟：`bash tools/smoke-godot.sh`
- 像素与长程对齐：`bash tools/parity-godot.sh`
