# 全量审查 `2411996` 修复报告

> 日期：2026-11-17
> 审查来源：`docs/archive/reviews/cloud_audit_2026-11-17_2411996/`（云端只读审计，基线 `2411996`）
> 用户拍板：`F-02/03` 做 Godot 正式导出；`F-05` 只警告不拒载；
> `F-06` 发行包不含本地编号存档；同时修 `F-04/F-08/F-09/F-10/F-12`。

## 1. 结论

- `F-01` 是误报，不回滚 Opcode 122 语义；只订正 `docs/engine/OPCODE_122.md`。
- `F-02/F-03` 已补齐 Godot Windows Desktop 导出预设与发布脚本，导出时排除
  `addons/godot_ai/*`、`tests/*` 和 `bin/~*`。
- `F-04` 启动失败现在有可读中文错误面板与退出路径；headless 直接 `quit(1)`。
- `F-05` 坏 checksum 仍可读档，但会在 `Game::diagnostics`、Godot 控制台和 CLI
  输出警告；`LoadedSave::checksum_valid` 暴露结果。
- `F-06` 两个发行脚本在复制 Data 时剔除整个 `Save/` 与所有 `SaveData*.sav`，
  只注入一个干净 `System.sav`；打包后再次校验 `Data/Save/` 只能有该文件。
- `F-08` 图片按钮回退收窄为 `5 | 21 | 22 | 28`，且只跳过交互模式变量
  `v100`（magic `2000100`）；`v69/v125/v176/v238` 等脚本门控保留。
- `F-09` `150 Move` 改用 `BTreeMap::range`，不再按整数跨度逐个探测。
- `F-10` `Game::reset_to_title()` 现在调用 `assets.clear()`。
- `F-12` F11 在 `_input` 顶部优先处理，模态弹窗不再吞掉全屏切换。
- `F-07`（模态期间冻结 VM）与 `F-11`（`\img` 混排）按用户决定暂不修改。

## 2. 逐项处置

| ID | 核实 | 处置 |
|---|---|---|
| `F-01` | **误报**：本地 WOLF 3.39 手册有“上1行切り取り”，但 `0x0010` 在实机证据中是“代入先を変数で指定”标志；改成 `0xFFF0` 会清空 CE270 名牌 | 不改引擎；订正 `docs/engine/OPCODE_122.md` |
| `F-02` | 属实 | 新增 `godot/export_presets.cfg` 与 `tools/package-godot.sh` |
| `F-03` | 属实 | 导出预设排除 `godot_ai` 插件与测试脚本；子代理实跑 `--export-pack` 验证 `project.binary` 无 `_mcp_game_helper` |
| `F-04` | 属实 | `GameView.gd` 统一 `_fail_startup()`：GUI 显示错误面板，headless `quit(1)` |
| `F-05` | 属实 | 解析保持宽容；`load_into` 记录诊断，GDExt/CLI 打印警告，不拒载 |
| `F-06` | 属实 | `package-playable.sh` / `package-godot.sh` 过滤所有本地编号存档 |
| `F-07` | 属实但暂缓 | 模态期间仍推进 `wolf.frame()`，按用户决定不改 |
| `F-08` | 属实 | 恢复窄回退，只跳过 `2000100` |
| `F-09` | 属实 | 区间查询活跃槽位，保留 `i32::MAX` 跨度护栏测试 |
| `F-10` | 属实 | 返回标题清理解码图像缓存 |
| `F-11` | 属实但暂缓 | 按用户决定不改 |
| `F-12` | 属实 | F11 提前到 `_input`，标记 handled，仅触发一次 |

## 3. 主要文件

- `crates/wolf-game/src/map_runtime.rs`：`action_key_event_ignoring_interaction_mode`、
  `conditions_met_except`、门控回归测试。
- `crates/wolf-game/src/game.rs`：图片按钮回退范围；`reset_to_title()` 清资源缓存。
- `crates/wolf-game/src/picture.rs`：`Screen::move_targets()` 与宽跨度回归。
- `crates/wolf-game/src/savegame.rs`：`LoadedSave::checksum_valid` 与警告诊断。
- `crates/wolf-game/tests/m3_save_robustness.rs`：坏 checksum 可加载且有警告。
- `crates/wolf-game/tests/m16_runtime_state.rs`：返回标题后资源缓存为空。
- `crates/wolf-gdext/src/lib.rs`、`crates/wolf-cli/src/{main,play}.rs`：警告输出。
- `godot/scripts/GameView.gd`、`godot/tests/startup_error_and_f11.gd`：错误面板与 F11。
- `godot/export_presets.cfg`、`tools/package-godot.sh`：Godot 正式导出。
- `tools/package-playable.sh`、`tools/package/PLAYABLE_README.txt`、
  `docs/release/PACKAGING.md`：F-06 与发行说明。

### 3.1 追加修复：开始新游戏时标题闪回

**现象**：标题选「はじめから」后，画面先黑一下，又闪出标题背景，再变黑进入游戏；
原版应保持标题并逐渐被黑幕覆盖。

**实机数据结论**：

- `CE42` 在选单确认后等待 12 帧，随后 `130 Teleport` 到 `Map003`；标题背景一直在
  负号槽 `-2`。
- `Map003` 事件 1 先在正号槽 `9000` 画 `cg/blackscreen.jpg`，`fade=30` 慢慢变黑；
  随后把同一标题画到 `-1`，等黑幕完全不透明后再 `Erase -1..-2`，最后传送
  `SampleMapA`。进入卧室后由 `SampleMapA` 事件 0 擦除 `9000`。
- 旧 `switch_map()` 在 `130` 当帧无条件 `clear_screen_layers()`，提前删掉了
  `-2`。于是出现两帧纯黑；Map003 再把标题画到 `-1` 并淡入，造成“标题闪回”。

**修复**：`crates/wolf-game/src/game.rs` 的 `switch_map()` 不再清负号图片层。
WOLF 的 `130 Teleport` 只换地图，图片存储由目标地图脚本负责淡出/擦除；旧注释
“新地图会重建覆盖层”与实机字节码不符。

**回归**：新增 `crates/wolf-game/tests/m3_title_transition.rs`，断言：

1. 进入 Map003 的第一帧，`-2` 标题背景仍在；
2. `9000` 黑幕尚未完全不透明时，画面始终有标题层，不能出现纯黑空档；
3. 进入 `SampleMapA` 前，Map003 已擦掉 `-1/-2`。

把旧的 `clear_screen_layers()` 临时放回去，该测试会在第一帧断言失败；恢复修复后
通过。`m1_title_load` 4/4、`opening` 4/4、`m3_newgame_persistence` 2/2、
`m3_title_mouse` 8/8、`m3_title_visibility` 4/4、`m6_title_wheel` 4/4、
`m3_endings` 6/6、`m16_runtime_state` 9/9 均通过。

### 3.2 追加修复：存档翻页时漏出 CE94 原始文本

**现象**：存档/读档栏翻页后的前一至两帧，会闪出上一页脚本写入的旧槽位编号、
游玩时长或哥哥称号（截图中的 `1`、`熊头` 等）；这些不是当前页数据。

**逐帧结论**：`CE131` 先更新页码变量，`CE94` 随后才重建四行文字图片。页码变化
后的前两帧里，`12052/12053/12055 + 20*row` 仍是上一页的图片；此时
`save_slot_text_override()` 已按新页码查槽，空槽返回 `None` 后 `text_quads()`
回退绘制 `picture.text` 的原始 CE94 字符串，于是旧文本漏出。

**修复**：覆盖函数先检查该行标签图片末端的槽位编号是否已经等于当前页码的槽位。
标签尚未重建时，同时隐藏该行的标签、游玩时长和状态文字；标签重建后恢复正常
覆盖，空槽继续显示脚本自己的“没有数据”。这样不会把上一页的文字带进新页，
也不会误删当前页刚绘制的文字。

**回归**：`m25_save_slot::a_page_turn_never_shows_the_previous_pages_raw_text`
覆盖向右翻到第 2 页、再向左返回第 1 页，逐帧断言过期行三组文字同时为空，
且重建后的第 1/2 页标签正确。

## 4. 验证

- `cargo fmt --all --check`、`cargo check -q --workspace`：通过。
- 定向回归：map_runtime 门控 2/2、picture 移动 5/5、
  `m3_save_robustness` 4/4、资源缓存清理 1/1。
- 使用 `work/out/retail_saves` 的出厂存档复制 `work/out/audit-Data` 后跑全量：
  `wolf-game` 库 363 passed / 6 failed；失败为既有 choice×3、db×2、textpic×1。
  另有已知夹具/旧 UI 期望失败：`m18_t18_regressions` 1、`m3_manual_rules` 1、
  `m3_hud_buttons` 1、`m3_menu_screens` 1。它们均不在本轮改动路径内；本轮新增
  回归全部通过。直接对玩家当前 `work/Data/Save` 跑测试会有更多夹具漂移，属于已知
  实机存档覆盖，不是回归。
- `bash -n` 两个打包脚本通过；两个 `--dry-run` 均 exit 0，列出并过滤当前所有
  本地编号存档，只计划注入 `System.sav`。
- Godot 子代理验证：启动失败退出码 1、错误面板与 F11 单次切换测试通过；
  `--export-pack` 实际成功，包内无 `addons/godot_ai`、`tests`、`bin/~*`；
  现有 headless smoke 与 UI 脚本通过。
- 标题过渡修复后重建 DLL：
  `godot/bin/wolf_gdext.dll` 与 `target/godot/wolf_gdext.dll` 均为
  `9c9e32812cfe5ea371b560d571ab8de0d6bbef6c76561d7b965a901e87cde635`；
  `smoke-godot.sh` exit 0（`pictures=4 sprites=4`）。

## 5. 正式发行包（已生成）

- Godot 4.7.2 导出模板已安装到
  `%APPDATA%\Godot\export_templates\4.7.2.stable`；正式
  `Imouto Life.exe` 已导出，PCK 内嵌。
- 发行 Data 改为 `tools/package/release-data.manifest` 精确白名单：
  746 个素材 + 干净 `Data/Save/System.sav`，共 747 个文件 / 128,083,817 B。
  完整 `work/Data` 中另有 618 个文件 / 55,684,128 B 不进入包，包括
  `MapChip/`、`FIcon/`、`BattleEffect/`、`Fog_BackGround/`、`SystemGraphic/`、
  未注册地图和未引用图片/音频。
- exe 图标来自 `work/Data/icon_windows.png`（2048×2048 PNG）：
  `godot/icon_windows.png` + `application/icon="res://icon_windows.png"`；
  图标源本身从 PCK 排除。
- 导出器把 DLL 放在 exe 根目录，但运行时清单按 `res://bin/wolf_gdext.dll`
  查找；脚本已重排为 `bin\wolf_gdext.dll` 并校验 SHA-256。PCK 不再重复嵌入
  DLL，当前 PCK 只有 13 个运行文件，无 `addons/`、`tests/` 或图标源。
- 最终包：
  `work/out/dist/godot/0.1.0/Imouto Life.exe`（109,299,944 B）、
  `bin/wolf_gdext.dll`（6,517,248 B，SHA-256 `348aa5d3...`）、
  `Data/`（747 文件，约 124 MiB）、
  `checksums.txt`；zip 约 141 MiB，并生成外部 `.sha256`。
- 精简 Data 验证：`smoke.gd` 输出 `pictures=4 sprites=4`；
  `save_roundtrip.gd` 新游戏自动走到卧室、保存并重载均为 38 张图片，
  `System.sav` 前后 SHA-256 不变。
- `bash tools/smoke-godot.sh` exit 0；`startup_error_and_f11.gd` 输出
  `error_ui=ok modal_f11=ok missing_data_exit=1`。

## 6. 发行存档基线

- 干净模板：`work/out/retail_saves/System.sav`，155,615 B，SHA-256
  `aaf62fc54c1df1ee63f3e5338b05ec349476346ec1a42b532c8cba0e3b3d888d`。
- 不得使用当前 `work/Data/Save/System.sav` 作为首选模板；它可能含本地设置，
  脚本仅在找不到干净模板时回退并打印警告。
