# Imouto Life 最新代码只读全量复审执行摘要 (`00_EXECUTIVE_SUMMARY.md`)

> 审查日期：2026-11-18  
> 审查基线：`e716f08f273f8aedced65e1b95502b90678ffd7b`（相对上一轮 `2411996` 复审，只读审计，未修改源码）  
> 依据指南：`docs/reviews/GEMINI_FULL_AUDIT_GUIDE.md`

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

1. **原 `F-01`（Opcode 122 掩码）已撤回为 `NOT_A_BUG`**：根据 `docs/reviews/AUDIT_2411996_FIX_REPORT.md` §2 与 `docs/engine/OPCODE_122.md` 订正，实机证据中 `0x0010` 为间接目标标志，改为 `0xFFF0` 会清空 CE270 名牌，保留 `0xFF00` / `0x0200` 正确。
2. **Godot 正式导出与插件隔离（`F-02`/`F-03`）已闭环**：已新增 `godot/export_presets.cfg` 与 `tools/package-godot.sh`，导出过滤显式排除 `addons/godot_ai/*`、`tests/*`、`bin/~*`、`icon_windows.png`。
3. **发行数据包白名单裁剪（`F-06`）已闭环**：已新增 `tools/package/release-data.manifest` 与 `release_data.py`，仅打包 746 个白名单文件 + 干净 `System.sav`（合计 747 个文件），剔除 `SaveData*.sav` 与当前 dry-run 的 619 个未用模板资源（审计快照为 618；manifest 仍为 746）。
4. **其余已闭环项**：启动失败错误面板与退出路径（`F-04`）、损坏存档校验和警告（`F-05`）、动作键绕过收窄（`F-08`）、`150 Move` 区间查询（`F-09`）、`reset_to_title()` 清缓存（`F-10`）、模态下 F11 全屏（`F-12`），以及**新游戏标题闪回**、**存档翻页旧文本残留**、**`Esc`/右键穿透无 `421` 分支的 `102 Choice`** 与 **窗口模式默认开启 `live_rng`** 均已落地且附带回归测试。

### 2.2 复审开放项处理状态（2026-11-18 已全部闭环）

| 排名 | ID | 严重度 | 证据 | 状态 | 标题与位置 |
|---:|---|---|---|---|---|
| 1 | `F-07` | **P2** | E1 | FIXED | 模态弹窗打开期间暂停 `wolf.frame()`，保留最后一帧并隐藏运行时指针 |
| 2 | `F-11` | **P2** | E1 | FIXED | `textpic::is_inline_image_only()` 区分纯图片条与图文混排；贴图条按 anchor/scale/alpha 绘制 |
| 3 | `R-01` | **P2** | E1 | FIXED | `Assets` 增加 256 MiB 字节上限与近似 LRU，超限淘汰并清理对应 alpha 缓存 |
| 4 | `R-02` | **P3** | E1 | FIXED | 两份 Godot 回归改为 `--data-root`，已接入 `tools/smoke-godot.sh` |
| 5 | `R-03` | **P3** | E1 | FIXED | `debug/export_console_wrapper=0`；`AGENTS.md` 已改为 9 个 crate |

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
- **发布前置已解除**：安装器已改用 NSIS 3.11（`makensis.exe`），中文界面与
  自定义安装路径均可用；便携 ZIP 与 `Setup.exe` 均已生成。

### 2.5 最终发包与验证（2026-11-18）

- `F-07`：`GameView.gd` 在模态期间不再推进运行时；`save_slot_modal.gd` 新增
  `runtime paused behind the dialog` 断言。
- `F-11`：`wolf_format::messagetext::contains_inline_image()` 按转义规则识别，
  不再把 `\\img` 文本误判为图片；`textpic::is_inline_image_only()` 保证混排保留
  文字；Atlas 贴图条补齐 `anchor`、`scale`、`scale_y`、`alpha <= 0` 处理。
- `R-01`：`DEFAULT_CACHE_BYTES = 256 MiB`；新增 LRU 淘汰回归。
- `R-02`：`verify_p0_fixes.gd` / `verify_ui_and_interaction_fixes.gd` 已改用
  `--data-root` 并接入 smoke。
- `R-03`：发布预设关闭 console wrapper，`AGENTS.md` 修正为 9 个 crate。
- 验证：`cargo fmt --all -- --check`、`cargo check -q --workspace`、
  `wolf-game --lib` 373/373、`wolf-format` 全绿、`m14_visual_regression` 5/5、
  `wolf-cli verify` PASS 64 / 1 SKIP、`bash tools/smoke-godot.sh` exit 0。
  `cargo test -q --workspace` 仅余已记录的玩家存档夹具漂移
  `m17_ui_regressions::night_message_click_is_not_eaten_by_parallel_pollers`，
  与本次改动无关且未修改 `work/Data/Save`。
- 发行产物：
  `work/out/dist/godot/0.1.0/Data` 为 747 文件 / 128,083,817 B，`Data/Save`
  仅含 `System.sav`；便携 ZIP 为 764 entries / 751 files，顶层目录为
  `妹！生活 ～单色～ Godot/`，所有非 ASCII 条目带 UTF-8 标志；
  `Imouto Life setup.zip` SHA-256 `bb7b65284fd31e43af1d1016d54e7ffe9af36ffed62dd72e404330479b165f4d`；
  `Imouto Life setup.exe` 为 114 MiB，SHA-256
  `23318bbd67238d6e39b9db455f7651ef71c04f8d69006b940aea6a8486a8b689`，
  版本资源语言为简体中文。
