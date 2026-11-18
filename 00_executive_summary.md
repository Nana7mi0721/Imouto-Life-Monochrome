# Imouto Life 最新代码只读全量复审执行摘要 (`00_EXECUTIVE_SUMMARY.md`)

> 审查日期：2026-11-18  
> 审查基线：`e716f08f273f8aedced65e1b95502b90678ffd7b`（相对上一轮 `2411996` 复审，只读审计，未修改源码）  
> 依据指南：`docs/GEMINI_FULL_AUDIT_GUIDE.md`

---

## 1. 审查基线与环境约束

| 维度 | 实测记录 |
|---|---|
| 源码快照 / Exact SHA | `e716f08f273f8aedced65e1b95502b90678ffd7b`（压缩包不含 `.git` 目录） |
| 操作系统 / CPU / 内存 | `Linux ace 6.12.105+ x86_64` / 2 vCPU / 7.8 GiB RAM |
| Rust / Godot / `work/Data` | **云端容器均未安装/未附带**（所有编译、测试运行、性能采样与素材扫描均标为 `UNVERIFIED_ENV`） |
| 代码规模 | 9 个 crate（209 个 `.rs` 文件，127,581 行）+ `godot/` 前端 |
| 测试规模（静态统计） | 168 个含测试 Rust 文件，**1,234 个 `#[test]`**（较 `2411996` 新增 +19 条），1 个 `#[ignore]`，118 个文件含 `skipping`/`skip:`（372 处） |

---

## 2. 总体风险与发布结论（回答 §12.3）

### 2.1 是否存在阻断发布的问题？
**无 P0/P1 阻断发布问题。** 上一轮（`2411996`）识别的全部 P0/P1 阻断项与近期三项实机问题均已在 `e716f08f` 源码中落地修复或完成裁决：

1. **原 `F-01`（Opcode 122 掩码）已撤回为 `NOT_A_BUG`**：根据 `docs/AUDIT_2411996_FIX_REPORT.md` §2 与 `docs/OPCODE_122.md` 订正，实机证据中 `0x0010` 为间接目标标志，改为 `0xFFF0` 会清空 CE270 名牌，保留 `0xFF00` / `0x0200` 正确。
2. **Godot 正式导出与插件隔离（`F-02`/`F-03`）已闭环**：已新增 `godot/export_presets.cfg` 与 `tools/package-godot.sh`，导出过滤显式排除 `addons/godot_ai/*`、`tests/*`、`bin/~*`、`icon_windows.png`。
3. **发行数据包白名单裁剪（`F-06`）已闭环**：已新增 `tools/package/release-data.manifest` 与 `release_data.py`，仅打包 746 个白名单文件 + 干净 `System.sav`（合计 747 个文件），剔除 `SaveData*.sav` 与当前 dry-run 的 619 个未用模板资源（审计快照为 618；manifest 仍为 746）。
4. **其余已闭环项**：启动失败错误面板与退出路径（`F-04`）、损坏存档校验和警告（`F-05`）、动作键绕过收窄（`F-08`）、`150 Move` 区间查询（`F-09`）、`reset_to_title()` 清缓存（`F-10`）、模态下 F11 全屏（`F-12`），以及**新游戏标题闪回**、**存档翻页旧文本残留**、**`Esc`/右键穿透无 `421` 分支的 `102 Choice`** 与 **窗口模式默认开启 `live_rng`** 均已落地且附带回归测试。

### 2.2 当前剩余开放项（无 P0/P1，仅 P2/P3）

| 排名 | ID | 严重度 | 证据 | 状态 | 标题与位置 |
|---:|---|---|---|---|---|
| 1 | `F-07` | **P2** | E1 | 暂缓（用户决定） | 模态弹窗打开期间 `GameView.gd:692` 仍推进 `wolf.frame()` |
| 2 | `F-11` | **P2** | E1 | 暂缓（用户决定） | `\img` 跳过仍用 `contains(r"\img")`（`atlas.rs:780`、`game.rs`），仅影响未来可能的图文混排 Mod |
| 3 | `R-01` | **P2** | E1 | OPEN | `Assets.cache` 已在回标题时清理，但单次长会话内仍无 LRU/字节上限 |
| 4 | `R-02` | **P3** | E1 | OPEN | `godot/tests/verify_p0_fixes.gd:6` 与 `verify_ui_and_interaction_fixes.gd:6` 仍硬编码本地路径且未接入 `smoke-godot.sh` |
| 5 | `R-03` | **P3** | E1 | OPEN | `godot/export_presets.cfg:28` 设置 `debug/export_console_wrapper=1`；`AGENTS.md:49` 仍写“8 个 crate” |

### 2.3 下一步最小验证集（本地带数据环境）
1. `cargo fmt --all -- --check && cargo check -q --workspace`
2. `WOLF_DATA_ROOT="<ABS>/work/Data" cargo test -q --workspace --no-fail-fast`
3. `bash tools/smoke-godot.sh` 与 `godot/tests/startup_error_and_f11.gd`
4. `bash tools/package-godot.sh --dry-run`（或正式导出验证打包产物）

### 2.4 复核补充（2026-11-18 修复）

- **新发现并修复的 P2**：用户数据库 SE 行是
  `SystemFile/[SE]Cancel.ogg\r\n80\r\n100` 这类多行 cell；opcode 140 之前把
  整段 cell 当作文件名传给宿主，Godot 的 `get_extension()` 得到
  `ogg\r\n80\r\n100`，`[SE]Cancel`/`[SE]Cursor` 等 16 个 SE 条目报
  `unsupported extension`/`cannot load`。`crates/wolf-vm/src/exec.rs` 新增
  `split_sound_cell()`（首行文件名、后两行音量/音高），并修正
  `split_first_line()` 的 CRLF 行尾；新增 3 条回归。
- 修复后 `bash tools/smoke-godot.sh` exit 0，且 `[SE]Cancel`/`[SE]Cursor`
  的 audio warning 消失。
- **发布前置**：当前机器仍无 `ISCC.exe`；便携 ZIP 可生成，`Setup.exe` 需
  Inno Setup 6。`tools/package-godot.sh --dry-run` 当前显示：
  manifest 746 文件 / 127,928,202 B，排除 619 文件 / 55,910,216 B。
