# 死代码与不可达路径审查报告 (`05_DEAD_CODE_REACHABILITY.md`)

> **归档说明（2026-11-18）**：本文为2026-11-17 云端只读全量审查（基线 `2411996`）的组成部分，内容已被 [`docs/reviews/cloud_audit_2026-11-18_e716f08/`](../../../reviews/cloud_audit_2026-11-18_e716f08/) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


> 严格遵循《指南》§8.1 分类与 §8.2 “四证”规则（静态引用、动态可达性、运行时证据、产品决定）。无运行时证据者仅列为候选，不直接建议删除。

---

## 1. §8.3 重点候选逐项核查表

| 候选符号 / 文件 | 位置 | 静态引用证据 | 分类 | 建议与原因 |
|---|---|---|---|---|
| `Assets::clear()` | `crates/wolf-game/src/assets.rs:324` | 仅定义与 `assets.rs:259` 注释，**生产/测试均 0 调用** | `OBSOLETE_CANDIDATE` / 待接入 | **不应删除，应接入 `reset_to_title()`**（见 `F-10`），其注释本意就是返回标题时释放缓存 |
| `TileMap::animation_phase()` | `crates/wolf-game/src/tilemap.rs:259` | 定义于 `tilemap.rs`，供 `TileMap::quads` / 诊断取证使用 | `TOOLING` / `RUNTIME`（诊断） | **保留**。虽然 Godot 玩法前端已移除瓦片桥接，但 `wolf-cli capture` 与地图验证仍依赖完整瓦片管线 |
| `Game::tile_quads()` | `crates/wolf-game/src/game.rs` | 被 `wolf-cli` capture/visual 取证及测试调用，Godot 已不再调用 | `TOOLING` / `TEST_ONLY` | **保留**（§8.4 明确警示勿误删） |
| `Vm::save_common_self()` | `crates/wolf-vm/src/exec.rs:1175` | `exec.rs` 内部私有辅助方法，协程退出时回写 `CommonSelf` | `RUNTIME` | **保留**，属 VM 协程生命周期关键逻辑 |
| `eval_arith_operand()` | `crates/wolf-vm/src/exec.rs:1820` | `exec.rs` 内部算术操作数求值，与 `eval_arith_operand_host` 并存 | `RUNTIME` / `OBSOLETE_CANDIDATE` | **观察**：需核对是否所有调用点已迁移至 `eval_arith_operand_host`（`exec.rs:2561,2572`），若确无剩余调用可由单测覆盖后精简 |
| `wolf-launcher` (`imouto-launcher`) | `crates/wolf-launcher/src/main.rs` | 被 `tools/package-playable.sh` 打包为 `Imouto Life.exe`，拉起 `wolf-cli.exe` | `TOOLING` | **保留**（CLI 发行包入口），但需在文档中与 Godot 正式客户端定位区分 |
| `godot/tests/verify_p0_fixes.gd` & `verify_ui_and_interaction_fixes.gd` | `godot/tests/` | 独立 GDScript 测试脚本，**未接入 `tools/smoke-godot.sh`**，且第 6 行硬编码作者本地路径 | `TEST_ONLY` | **保留并修复路径**后接入 `smoke-godot.sh`（见 `REQ-017`） |
| `godot/addons/godot_ai` | `godot/addons/godot_ai/` | 在 `project.godot:20,32` 启用并挂入 `_mcp_game_helper` Autoload | `DEV_ONLY` | **仅限开发期保留，导出时必须排除**（见 `F-03`） |
| `161/162` 冻结过渡 / `PlayerTouch` | `crates/wolf-game/src/picture.rs`, `map_runtime.rs` | 仅在未注册示例地图 `SampleMapB.mps` 出现，正式 5 张注册图不触发 | `DATA_TEMPLATE` | **保留引擎实现与单测**，不作为玩家路径故障 |
| `BattleEffect/` / 战斗表 | `work/Data/BattleEffect/` | 游戏数据模板残留（动态可达性 `UNVERIFIED_ENV`） | `DATA_TEMPLATE` | 需在有 `work/Data` 时跑完 `wolf-cli assets` + 动态 trace 后再由产品决定是否从发行包裁剪 |

---

## 2. 明确不建议删除的误报警示（对照 §8.4）
- `Game::tile_quads()` 与 `wolf-render` / `wolf-cli`：属于视觉回归（`m14_visual_regression`）与离线验证工具链基石。
- `Picture/word_effect*`：存在运行时路径 fallback（`assets.rs:250`）。
- `GameHost::character_state`：`wolf-game` 已实现所需字段，部分未用子字段保留默认返回属既有设计。
