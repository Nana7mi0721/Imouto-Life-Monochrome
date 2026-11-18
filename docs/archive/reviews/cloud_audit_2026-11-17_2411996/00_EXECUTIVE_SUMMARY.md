# Imouto Life 只读全量审查执行摘要 (`00_EXECUTIVE_SUMMARY.md`)

> **归档说明（2026-11-18）**：本文为2026-11-17 云端只读全量审查（基线 `2411996`）的组成部分，内容已被 [`docs/reviews/cloud_audit_2026-11-18_e716f08/`](../../../reviews/cloud_audit_2026-11-18_e716f08/) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。
>
> **同轮次说明**：本文件与现行轮的 `docs/reviews/cloud_audit_2026-11-18_e716f08/00_EXECUTIVE_SUMMARY.md`
> **同名不同轮**（基线分别是 `2411996` 与 `e716f08`，结论也不同），按文件名检索时容易误取，
> 请以所在目录名为准。
>
> **证据等级提醒**：云端容器**没有** Rust 工具链、Godot 与 `work/Data`，
> 因此本轮的测试类结论都是**转引历史文档**（例如 `06_TEST_COVERAGE_AND_SKIPS.md`
> 里"ce238 仍失败"引自 11-14 的 `GEMINI_REVIEW_1c76dcc_FIX_REPORT.md`），
> 而 ce238 已于 11-15 转绿。**测试状态一律以 `docs/HANDOFF_M0.md` §11.1 为准。**


> 审查日期：2026-11-17
> 审查范围：`nana7mi0721/imouto-life` 源码快照（只读审计，未修改源码、未提交、未创建 PR）
> 依据指南：`docs/GEMINI_FULL_AUDIT_GUIDE.md`

---

## 1. 审查基线与环境约束

| 维度 | 实测记录 |
|---|---|
| 源码快照 / Exact SHA | `24119960904011cbf5c0d0d4a7246a9d11fcf22b`（来自上传压缩包 `imouto-life-24119960904011cbf5c0d0d4a7246a9d11fcf22b`；压缩包不含 `.git` 目录，无法运行 `git log` / `git status`） |
| 操作系统 / CPU / 内存 | `Linux ace 6.12.105+ #1 SMP Sat Sep 19 19:37:41 UTC 2026 x86_64 GNU/Linux` / 2 vCPU / 7.8 GiB RAM |
| Rust / Cargo 工具链 | **未安装**（`rustc` / `cargo` 均不存在于容器环境中） |
| Godot / Windows 运行时 | **未安装**（无 Godot 4.7.2，无 Windows DLL 构建与执行环境） |
| 游戏数据 (`work/Data`) | **不存在**（干净 `master` 快照不含 `work/Data`、`work/out`、`prt sc/` 与 `Data.wolf`） |
| 代码规模 | Cargo workspace 含 **9 个 crate**（206 个 `.rs` 文件，125,883 行）+ `godot/` GDScript 前端 |
| 测试规模（静态统计） | 165 个含测试 Rust 文件，**1,215 个 `#[test]`**，2 个 `#[ignore]`，**116 个文件含 `skipping`/`skip:` 路径（363 处）** |

> **证据等级说明**：受云端容器缺少 `rustc`/`cargo`、Godot 4.7.2 与 `work/Data` 限制，本次审计结论主要为 **E1（静态代码路径可证明，未运行）** 与历史文档核对；所有编译、测试执行、性能实测、资产引用扫描与实机画面核对均在 `08_UNVERIFIED_CLOUD.md` 中诚实标为 `UNVERIFIED_ENV`。

---

## 2. 总体风险与发布结论（回答 §12.3）

### 2.1 是否存在阻断发布的问题？
**是。当前仓库不具备可信的 Godot 正式发布路径，且存在已证实的 VM 语义回归与打包/安全阻断项：**

1. **Godot 正式导出路径缺失（P0 级发布阻断）**：`godot/` 目录下不存在 `export_presets.cfg`，且 `godot/bin/wolf_gdext.gdextension` 仅配置了 `windows.debug.x86_64` / `windows.release.x86_64` 指向 `res://bin/wolf_gdext.dll`。`tools/package-playable.sh` 打包的是 CLI 启动器（`wolf-cli.exe` + `imouto-life`），并非 Godot 正式发行包。
2. **第三方开发插件 `godot_ai` 已启用并注入全局 Autoload（P1 级发布风险）**：`godot/project.godot:20,32` 启用了 `res://addons/godot_ai/plugin.cfg` 并注册了 `_mcp_game_helper` Autoload（`godot/addons/godot_ai/runtime/game_helper.gd`），若直接导出将把调试/截图/MCP 辅助脚本带入玩家发行包。
3. **`Opcode 122` 掩码回归仍在当前代码库中（P0 级语义缺陷，E1）**：`crates/wolf-vm/src/exec.rs:2661,2715` 仍使用 `mode & 0xFF00` 与 `0x0200 =>` 分支（`b23a1e1` 回退 `f52db44` 后未重新落地），导致 CE268 `pc=14` 与 CE270 `pc=2000` 的「上1行切り取り」（`0x0010`）被折叠为普通赋值。
4. **存档读取不校验校验和（P1 级数据完整性风险，E1）**：`crates/wolf-save/src/lib.rs:342-363` 计算并暴露了 `checksum_ok()`，但 `SaveFile::parse` 与游戏层 `savegame::load_into` 均未在读档时强制校验 `checksum_ok()`，损坏或篡改的 `.sav` 可静默加载。

### 2.2 最严重的 10 项问题（按风险排序）

| 排名 | ID | 严重度 | 证据 | 标题与核心位置 |
|---:|---|---|---|---|
| 1 | `F-01` | **P0** | E1 | `Opcode 122` 掩码仍为 `0xFF00` / `0x0200`，破坏 CE268/CE270 首行截取 (`crates/wolf-vm/src/exec.rs:2661,2715`) |
| 2 | `F-02` | **P0** | E1 | 缺失 Godot `export_presets.cfg` 与正式导出管线，仅支持 Windows 局部库 (`godot/project.godot`, `godot/bin/wolf_gdext.gdextension`) |
| 3 | `F-03` | **P1** | E1 | `godot/project.godot:20,32` 启用 `godot_ai` 插件及 `_mcp_game_helper` 全局 Autoload，存在随导出带入风险 |
| 4 | `F-04` | **P1** | E1 | `GameView.gd:428-483` 启动/读档/打开数据失败仅 `push_error` 并停用物理帧，GUI 窗口无可见错误提示与退出路径 |
| 5 | `F-05` | **P1** | E1 | `SaveFile::parse` (`crates/wolf-save/src/lib.rs:342-363`) 与读档流程不拒绝 `checksum_ok() == false` 的损坏存档 |
| 6 | `F-06` | **P1** | E1 | `tools/package-playable.sh:131` 递归复制整个 `Data/`，会把测试存档、未注册地图与模板资源（如 `BattleEffect/`）打入发行包 |
| 7 | `F-07` | **P2** | E1 | `GameView.gd:548` 在前端模态弹窗打开期间仍每帧调用 `wolf.frame()` 推进底层 VM 与计时 |
| 8 | `F-08` | **P2** | E1 | `crates/wolf-game/src/game.rs:3792` 动作键绕过范围仍为 `5\|21\|22\|28\|30\|35` 全条件跳过，未收窄且未保留阶段门控 |
| 9 | `F-09` | **P2** | E1 | `crates/wolf-game/src/picture.rs:1433` `PictureAction::Move` 仍为 `for n in lo..=hi` 逐整数遍历，大跨度存在卡顿风险 |
| 10 | `F-10` | **P2** | E1 | `Assets::cache` (`crates/wolf-game/src/assets.rs:291`) 无容量上限且 `Assets::clear()` 在生产代码中无调用者 |

### 2.3 立即修 vs 后续修 vs 证据充分性
- **必须立即修（发版前）**：`F-01`（恢复 `0xFFF0` / `0x0010`）、`F-02`（补齐 `export_presets.cfg` 与正式 Godot 导出验证）、`F-03`（导出时剥离或禁用 `godot_ai` / `_mcp_game_helper`）、`F-04`（启动失败可见弹窗 + 安全退出）、`F-06`（`package-playable.sh` 资源白名单/排除测试存档与模板）。
- **可在后续版本修**：`F-05`（损坏存档提示而非静默解析）、`F-07`（模态期间冻结/暂停 VM 帧推进）、`F-08`（收窄动作键绕过并保留非交互模式门控）、`F-09`（`Move` 改用 `BTreeMap::range`）、`F-10`（`Assets::clear()` 接入 `reset_to_title` / `load_save` 或加 LRU 预算）、`F-11`（`\img` 混排保护）、`F-12`（模态下 `F11` 全屏不被 `_input` 拦截）。
- **旧报告应撤回或更新的结论**：
  - `docs/REVIEW_9a817e4_FIX_REPORT.md` 表格正文记录的 5 项“已修”在 `b23a1e1` 已回退，当前源码仅落地 `.mps` 后缀与本地时钟两项（报告顶部横幅已声明，但引用时不可再将表格误当现状）。
  - `AGENTS.md:49` 仍写“8 个 crate”，实际 `Cargo.toml` 为 **9 个 crate**（含 `wolf-launcher` / `imouto-launcher`）。

### 2.4 下一步最小验证集（需在有 Rust + Godot + `work/Data` 的 Windows/本机环境执行）
1. `cargo fmt --all -- --check && cargo check -q --workspace`
2. `WOLF_DATA_ROOT="<ABS>/work/Data" cargo test -q --workspace --no-fail-fast`（重点核查 `m3_status_panel::ce238_relative_panel_lands_at_the_left_edge` 与 8 项长期基线红灯）
3. `WOLF_DATA_ROOT="<ABS>/work/Data" cargo run -q -p wolf-cli -- verify`（核对 PASS 64 / 1 SKIP 基线）
4. `WOLF_DATA_ROOT="<ABS>/work/Data" cargo run -q -p wolf-cli -- assets --root "<ABS>/work/Data" --include-maps --format json`
5. `bash tools/smoke-godot.sh` + 补跑修复路径后的 `godot/tests/verify_p0_fixes.gd` 与 `verify_ui_and_interaction_fixes.gd`
