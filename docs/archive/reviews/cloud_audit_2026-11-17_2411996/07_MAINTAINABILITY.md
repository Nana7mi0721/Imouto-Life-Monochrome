# 可维护性与架构清晰度审查报告 (`07_MAINTAINABILITY.md`)

> **归档说明（2026-11-18）**：本文为2026-11-17 云端只读全量审查（基线 `2411996`）的组成部分，内容已被 [`docs/reviews/cloud_audit_2026-11-18_e716f08/`](../../../reviews/cloud_audit_2026-11-18_e716f08) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


---

## 1. 模块边界与巨型模块评估

整体 Workspace 分层清晰：`wolf-format`（二进制解包与格式）→ `wolf-save`（存档读写与重建）→ `wolf-vm`（字节码虚拟机）→ `wolf-game`（游戏宿主、状态机、渲染图元合成）→ `wolf-gdext` / `wolf-cli`（双前端桥接）。

需关注的巨型文件与耦合点：
1. **`crates/wolf-game/src/game.rs`**：单文件承载了游戏状态机、地图切换、输入路由、图片按钮命中、HUD 布局、TextQuad 生成、Host trait 实现与大量内嵌单测，建议后续按「Host 实现 / HUD 与文本布局 / 输入命中」拆分为子模块（纯维护性改进，非缺陷）。
2. **`crates/wolf-vm/src/exec.rs`**：单文件超 6,000 行（含单测），建议将 Opcode 分发按类别拆分。
3. **跨语言契约 (`wolf-gdext` ↔ `GameView.gd`)**：两者通过无 schema 约束的 `VarDictionary` 键名（`"sprites"`, `"texts"`, `"overlays"`, `"sounds"`, `"ap"`, `"auto_saved"` 等）通信，虽有文档注释，但缺乏集中化的契约测试以防字段拼写漂移。

---

## 2. 错误处理与 `unwrap`/`expect` 审计

统计各 crate 生产代码（`#[cfg(test)]` 之前）中 `.unwrap(` / `.expect(` 出现次数：

| Crate | 生产代码 `unwrap`/`expect` 次数 | 评估 |
|---|---:|---|
| `wolf-vm` | 0 | 优秀，无未受保护的 panic 点 |
| `wolf-save` | 0 | 优秀，外部 `.sav` 输入均走 `Result` |
| `wolf-launcher` | 0 | 优秀 |
| `wolf-cli` | 1 | 低风险 |
| `wolf-gdext` | 1 | `lib.rs:320` 有前置 `if let Some(...) = choice_data` 守卫，安全 |
| `wolf-render` | 2 | 低风险 |
| `wolf-audio` | 3 | 低风险 |
| `wolf-game` | 3 | 低风险 |
| `wolf-format` | 14 | 建议后续逐步核查是否全为内部不变量，防止畸形外部数据触发 panic |

**前端启动错误处理（P1 缺陷，见 `F-04`）**：`GameView.gd:428-483` 对致命启动失败仅输出 `push_error` 并停用 `_physics_process`，缺乏用户可见的错误提示与退出机制。

---

## 3. 文档与代码一致性差异

1. **`AGENTS.md:49` Crate 数量过期**：文档写“8 个 crate”，`Cargo.toml` 实际包含 **9 个 crate**（多出 `crates/wolf-launcher`，包名 `imouto-launcher`）。
2. **`REVIEW_9a817e4_FIX_REPORT.md` 回退标记**：报告顶部横幅已正确注明 `b23a1e1` 回退了 5 项修改，但下方的正文表格仍写“已修”，阅读时极易误导，建议仅以本审计矩阵为准。
3. **`Assets::clear()` 注释与实现脱节**：`assets.rs:323` 注释声称返回标题时调用，实际生产路径无任何调用（见 `F-10`）。
4. **双前端并行维护成本**：`wolf-render` + `wolf-cli play`（wgpu 原生窗口）与 `wolf-gdext` + `godot/`（Godot 4.7.2 前端）两套渲染、文本、音频缓存与打包脚本并存，建议在 Godot 正式导出就绪后明确旧窗口前端的退场边界。
