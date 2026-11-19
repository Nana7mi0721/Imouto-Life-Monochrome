# 测试覆盖率与假绿风险审查报告 (`06_TEST_COVERAGE_AND_SKIPS.md`)

> **归档说明（2026-11-18）**：本文为2026-11-17 云端只读全量审查（基线 `2411996`）的组成部分，内容已被 [`docs/reviews/cloud_audit_2026-11-18_e716f08/`](../../../reviews/cloud_audit_2026-11-18_e716f08) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


> **云端执行说明**：由于容器未安装 `rustc`/`cargo` 且无 `work/Data`，**无法实际运行 `cargo test`**。下表数据来自对仓库全部 206 个 `.rs` 文件与 `godot/tests/` 的静态 AST/正则审计。

---

## 1. 全仓测试规模与“假绿 (`skipping`)”分布

| Crate | 含测试文件数 | `#[test]` 总数 | `#[ignore]` 数量 | 含 `skipping`/`skip:` 文件数 | `skipping`/`skip:` 出现次数 |
|---|---:|---:|---:|---:|---:|
| `wolf-audio` | 5 | 41 | 0 | 3 | 8 |
| `wolf-cli` | 5 | 41 | 0 | 2 | 5 |
| `wolf-format` | 25 | 113 | 1 | 14 | 43 |
| `wolf-game` | 109 | 781 | 1 | 88 | 291 |
| `wolf-gdext` | 1 | 2 | 0 | 0 | 0 |
| `wolf-launcher` | 0 | 0 | 0 | 0 | 0 |
| `wolf-render` | 7 | 58 | 0 | 3 | 7 |
| `wolf-save` | 5 | 31 | 0 | 5 | 8 |
| `wolf-vm` | 8 | 148 | 0 | 1 | 1 |
| **合计** | **165** | **1,215** | **2** | **116** | **363** |

### 核心发现
1. **高比例静默跳过（假绿风险）**：165 个含测试文件中高达 **116 个（70.3%）** 包含 `skipping` / `skip:` 提前返回路径（363 处）。在未设置 `WOLF_DATA_ROOT` 绝对路径时，绝大多数集成测试会打印 `skipping` 后直接 `return` 并以 exit 0 通过。
2. **相对路径陷阱**：如 `AGENTS.md:27` 所述，`cargo test` 以各 crate 根目录为 CWD，传入相对路径 `WOLF_DATA_ROOT=work/Data` 会导致找不到目录而静默 skip，造成“数据测试全绿”的假象。
3. **`wolf-launcher` 零测试**：`crates/wolf-launcher` 拥有 0 个单元测试。
4. **`#[ignore]` 用例（2 处）**：均位于已知历史边界（`wolf-format` 1 处、`wolf-game/tests/m16_old_bug_review.rs` 1 处或 2 处，需以本机 `cargo test -- --list` 复核）。

---

## 2. 夹具漂移与历史已知失败项

1. **玩家存档夹具漂移**：
   - `m14_visual_regression` 的 `saveui` 场景与 `m3_menu_screens` / `m17_ui_regressions` 依赖出厂 `SaveData01.sav` / `SaveData02.sav`。当 `Save/` 目录混入额外测试存档（如 `SaveData03.sav`）或被玩家实机覆盖时，`depends_on_save_grid` 守卫会触发跳过或产生差异。
2. **历史既有失败基线（云端 `UNVERIFIED_ENV`，待本机复跑）**：
   - `m3_status_panel::ce238_relative_panel_lands_at_the_left_edge`（`GEMINI_REVIEW_1c76dcc_FIX_REPORT.md` §6.2 记录仍失败：面板停在 `x=-305` 而期望 `(0,0)`）。
   - `m3_manual_rules::late_night_bedtime_skips_to_next_evening`（长期口径差：实得 17:00 vs 期望 19:00）。
   - `wolf-game --lib` 若干姊妹作期望差异（`choice` / `db` / `textpic`，见 `LIVE_PLAY_FIX_REPORT.md` §3 记录的 8 项长期基线红灯）。

---

## 3. Godot 测试缺口

- `godot/tests/verify_p0_fixes.gd:6` 与 `godot/tests/verify_ui_and_interaction_fixes.gd:6` **硬编码了作者本地绝对路径** `"E:/Study/github program/Imouto Life/work/Data"`，在任意其他机器或 CI 环境无法直接运行。
- `tools/smoke-godot.sh` 目前仅运行 9+1 个脚本，**未调用上述两份 `verify_*.gd` 脚本**（因 `b23a1e1` 回退了 `f52db44` 的接入改动）。
- 缺乏针对 `GameView.gd` 启动失败 UI（`F-04`）、模态期间 VM 暂停（`F-07`）与模态下 `F11` 全屏（`F-12`）的自动化测试。
