# 新发现缺陷与已证实开放风险清单 (`02_FINDINGS.md`)

> 说明：所有结论均基于对源码 `24119960904011cbf5c0d0d4a7246a9d11fcf22b` 的静态审计。受云端无 Rust/Godot/Data 限制，代码路径可证明的静态缺陷统一标为 `E1`，不虚构 `E2/E3/E4` 运行证据。

---

### F-01: Opcode 122 掩码仍为 `0xFF00` / `0x0200`，破坏 CE268/CE270 首行截取
- **Severity**: P0
- **Category**: VM 语义 / 回归
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `crates/wolf-vm/src/exec.rs:2661,2715` (`execute` Opcode 122 分支)
- **Status**: confirmed (OPEN / REVERTED)
- **Affected flow**: 对白气泡名称/正文首行截取（CE268 `pc=14`、CE270 `pc=2000`）
- **Observed behavior**: `let operation = mode & 0xFF00;` 且首行截取分支匹配 `0x0200 =>`；`b23a1e1` 回退 `f52db44` 后未重新恢复。
- **Expected behavior**: 按 WOLF 手册，操作码掩码应为 `mode & 0xFFF0`，首行截取（「上1行切り取り」）分支应为 `0x0010 =>`；`0x0011`/`0x0012` 均属该操作。
- **Reproduction**: 在 `crates/wolf-vm/src/exec.rs` 执行 `cmd(122, &[1600010, 17, 1600005], &[])`（mode=17=0x0011），`17 & 0xFF00 == 0` 落入普通赋值 `0x0000`。
- **Root cause**: `f52db44` 修复被 `b23a1e1` 整批回退，单测也被留在 `0x0201`。
- **Impact**: 全作仅有的两条首行截取指令被折叠为普通赋值，源字符串首行既不被切走也不被消费，导致剧情文本解析错乱。
- **Minimal fix**: 将 `exec.rs:2661` 改为 `let operation = mode & 0xFFF0;`、`:2715` 改为 `0x0010 =>`，同步更新错误注释与单元测试。
- **Regression test**: 恢复 `op122_first_line_cut_moves_the_head_out_of_a_numbered_source` 并断言 `mode=0x0011/0x0012` 正确消费源行。
- **Packaging/performance impact**: 无性能损耗。
- **Related requirement**: `REQ-011` (`REVIEW_9a817e4_FIX_REPORT` §2.1)

---

### F-02: 缺失 Godot 正式导出配置 (`export_presets.cfg`) 与跨平台库配置
- **Severity**: P0
- **Category**: 发布 / 导出阻断
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `godot/project.godot`, `godot/bin/wolf_gdext.gdextension`
- **Status**: confirmed (OPEN)
- **Affected flow**: Godot 正式发行打包与独立客户端运行
- **Observed behavior**: `godot/` 目录不存在 `export_presets.cfg`；`wolf_gdext.gdextension` 仅配置 `windows.debug.x86_64` 与 `windows.release.x86_64` 指向 `res://bin/wolf_gdext.dll`；`tools/package-playable.sh` 打包的是 CLI 启动器而非 Godot 工程。
- **Expected behavior**: 正式 Godot 发布需具备 `export_presets.cfg`、release 导出脚本、数据根定位与非开发依赖打包清单。
- **Reproduction**: 检查 `ls -la godot/` 与 `cat godot/bin/wolf_gdext.gdextension`。
- **Root cause**: Godot 迁移仍停留在开发期直接 `--path godot` 运行阶段，尚未建立导出管线。
- **Impact**: 无法交付独立的 Godot 发行版客户端；若误以为 `package-playable.sh` 即 Godot 发行包，实则交付的是旧 `wolf-cli` 窗口路径。
- **Minimal fix**: 添加 `godot/export_presets.cfg`（排除测试脚本与开发插件）及对应 Godot release 导出脚本，明确 `wolf-cli` 包与 Godot 包的发布边界。
- **Regression test**: 导出后独立目录启动冒烟测试（`--headless` 或窗口启动到达标题）。
- **Packaging/performance impact**: 决定正式发布产物形态。
- **Related requirement**: `REQ-039`

---

### F-03: 第三方开发插件 `godot_ai` 已启用且注册全局 Autoload `_mcp_game_helper`
- **Severity**: P1
- **Category**: 安全 / 发布隔离
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `godot/project.godot:20,32`, `godot/addons/godot_ai/runtime/game_helper.gd`
- **Status**: confirmed (OPEN)
- **Affected flow**: Godot 启动、每帧运行时与未来导出包
- **Observed behavior**: `[autoload]` 启用 `_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"`，`[editor_plugins]` 启用 `res://addons/godot_ai/plugin.cfg`。该插件（MIT 许可，Godot AI MCP server）在游戏进程注册 `"mcp"` 调试消息捕获。
- **Expected behavior**: 仅用于开发期调试/MCP 的插件与 Autoload 不应默认打包进正式玩家发行版。
- **Reproduction**: 查看 `godot/project.godot:18-33`。
- **Root cause**: 开发期直接将插件启用状态写入共享的 `project.godot`。
- **Impact**: 增加启动开销与包体体积（`addons/godot_ai` 约 500+ KB），且在正式导出未做排除过滤时会将 MCP 调试逻辑带入发行包。
- **Minimal fix**: 在 `export_presets.cfg` 中配置导出过滤排除 `addons/godot_ai/*`，或在发行导出前移除/条件化 `_mcp_game_helper` Autoload。
- **Regression test**: 导出 PCK/EXE 后检查资源列表不含 `addons/godot_ai`。
- **Packaging/performance impact**: 减小发行包体积并消除非必要运行时节点。
- **Related requirement**: `REQ-039`

---

### F-04: `GameView.gd` 启动或加载失败时静默黑屏，无可见错误提示与退出路径
- **Severity**: P1
- **Category**: 鲁棒性 / 用户体验
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `godot/scripts/GameView.gd:428-439,461-464,476-483` (`_ready`)
- **Status**: confirmed (OPEN)
- **Affected flow**: 玩家双击启动 Godot 客户端但缺 `Data/`、损坏 `Game.dat` 或指定无效存档时
- **Observed behavior**: 当 `root.is_empty()`、`!wolf.open(root)`、`!wolf.load_save(...)`、`!wolf.start_title()` 或 `!wolf.boot()` 时，脚本仅调用 `push_error(...)` 和 `set_physics_process(false)` 后 `return`。GUI 窗口保持黑屏且不退出。
- **Expected behavior**: 在窗口内绘制清晰的中文错误提示（含缺失路径/原因）并提供 Esc/点击退出或 `OS.alert` + `get_tree().quit(1)`。
- **Reproduction**: 在无有效 `Data/` 目录时直接运行 Godot 工程。
- **Root cause**: 启动错误处理仅面向带控制台的开发者调试（`push_error`），未考虑无控制台窗口的普通玩家。
- **Impact**: 玩家遇到路径配置错误或数据损坏时看到永久黑屏假死，无法得知原因。
- **Minimal fix**: 复用 `_ModalLayer` 显示致命错误说明与「退出」按钮（或在 headless/非交互下 `get_tree().quit(1)`）。
- **Regression test**: 新增 headless 启动缺数据测试，验证返回非零退出码或错误状态标志。
- **Packaging/performance impact**: 无性能影响，显著提升交付健壮性。
- **Related requirement**: `REQ-042`

---

### F-05: `SaveFile::parse` 与游戏读档流程不校验存档校验和 (`checksum_ok`)
- **Severity**: P1
- **Category**: 存档安全 / 数据完整性
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `crates/wolf-save/src/lib.rs:342-363,393-395`, `crates/wolf-game/src/savegame.rs`
- **Status**: confirmed (OPEN)
- **Affected flow**: 标题读档 / 游戏内读档 / 启动 `--load-save`
- **Observed behavior**: `SaveFile::parse` 计算 `computed_checksum` 并保存 `stored_checksum`，提供 `checksum_ok()` 方法，但全仓生产代码（除 `wolf-cli` 统计外）无一处调用 `checksum_ok()` 来拒绝或告警损坏的 `.sav` 文件（`m3_save_robustness.rs:7,255` 亦明确记录了此缺口）。
- **Expected behavior**: 读档前应校验 `checksum_ok()`（至少对损坏文件返回明确错误或标记不可读，避免将半截损坏变量状态加载进 VM）。
- **Reproduction**: 篡改 `.sav` 加密体任意字节或 header 校验字节后调用 `SaveFile::parse` 与 `load_save`。
- **Root cause**: 解析器刻意保留了只读宽容边界以便诊断，但游戏宿主层未在 `load_into` 前执行校验拦截。
- **Impact**: 磁盘坏块或被截断/篡改的存档可能绕过校验进入游戏，引发不可预测的脚本状态错乱或后续覆盖写坏。
- **Minimal fix**: 在 `Game::load_save` / `savegame::load_into` 增加校验和检查（可提供诊断开关绕过，默认拒绝不匹配的存档）。
- **Regression test**: 在 `m3_save_robustness.rs` 补充游戏层拒绝 `checksum_ok() == false` 存档的断言。
- **Packaging/performance impact**: 仅在读档时多一次 O(1) 布尔判断。
- **Related requirement**: `REQ-040`

---

### F-06: `tools/package-playable.sh` 全量递归复制 `Data/`，夹带测试存档与模板资源
- **Severity**: P1
- **Category**: 封包与供应链
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `tools/package-playable.sh:131`
- **Status**: confirmed (OPEN)
- **Affected flow**: 生成可双击游玩的发布包 (`Imouto Life-*-playable.zip`)
- **Observed behavior**: `cp -a "$DATA_ROOT/." "$OUT_DIR/Data/"` 无过滤地复制整个 `work/Data/`。同时第 91/95 行构造 `imouto-life.exe`（包名 `imouto-launcher`）并依赖 MSYS `cygpath`，纯 Linux 下不可执行。
- **Expected behavior**: 发布包应仅复制白名单游戏运行资源，排除测试残留存档（如 `SaveData03+`）、未注册模板地图或确认无用的 `BattleEffect/` 模板资源（若经运行时验证可裁）。
- **Reproduction**: 检查 `tools/package-playable.sh:130-132`。
- **Root cause**: 缺少基于资源审计 manifest 的裁剪拷贝逻辑。
- **Impact**: 玩家下载包体积膨胀（含约 15+ MiB 模板残留候选）且可能把本地测试存档状态带给玩家。
- **Minimal fix**: 在打包脚本中显式重置/过滤 `Data/Save/` 仅保留出货存档（或空 `Save/` + `System.sav`），并引入可选资源白名单过滤。
- **Regression test**: 打包后脚本校验输出目录 `Save/` 文件列表与哈希。
- **Packaging/performance impact**: 可减少发行包体积并避免玩家初始存档污染。
- **Related requirement**: `REQ-039`

---

### F-07: Godot 前端模态弹窗打开期间，底层 `wolf.frame()` 仍每帧推进
- **Severity**: P2
- **Category**: 状态机 / 模态隔离
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `godot/scripts/GameView.gd:513,548` (`_physics_process`)
- **Status**: confirmed (OPEN)
- **Affected flow**: 游戏内按 `Esc` 打开「返回标题画面？」弹窗，或点击非空存档槽打开确认弹窗期间
- **Observed behavior**: 当 `modal_open` 为 `true` 时，`_physics_process` 仅把输入清零（`raw_keys` 空、`buttons = 0`、`wheel = 0`），但第 548 行依然调用 `packet = wolf.frame()`。
- **Expected behavior**: 打开前端模态确认框时，通常应暂停游戏世界推进（或至少文档明确这是有意设计），防止夜间计时事件、并行协程、BGM 淡入淡出或 `playtime_frames` 在玩家思考确认期间继续演进。
- **Reproduction**: 夜间交互有倒计时/并行事件时按 `Esc` 弹窗停留数秒，观察底层画面/事件是否继续变化。
- **Root cause**: `GameView.gd` 将模态实现为输入拦截层，而非运行时暂停门控。
- **Impact**: 玩家停在「返回标题？」或「覆盖存档？」弹窗时，底层并行计时器仍继续消耗并可能触发剧情跳转或动画结束。
- **Minimal fix**: 当 `modal_open` 为真时跳过 `wolf.frame()` 推进（复用最后一帧 `packet` 重绘，或为 `WolfGame` 提供仅重绘不步进 VM 的接口）。
- **Regression test**: 在 `save_slot_modal.gd` 断言弹窗打开期间 `game_frames` / `playtime` 不增长。
- **Packaging/performance impact**: 模态期间省去每帧 VM 步进 CPU 开销。
- **Related requirement**: `REQ-035`

---

### F-08: ActionKey 图片按钮绕过范围仍为 `5|21|22|28|30|35` 且无条件跳过全部页条件
- **Severity**: P2
- **Category**: 输入 / 状态机逻辑
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `crates/wolf-game/src/game.rs:3792`
- **Status**: confirmed (OPEN / REVERTED)
- **Affected flow**: 点击 HUD 保存(`5`)、结束(`21`)、姿势(`22/28`)、数据(`30`)、相册(`35`)图标
- **Observed behavior**: `if started.is_none() && matches!(event, 5 | 21 | 22 | 28 | 30 | 35)` 调用 `action_key_event_ignoring_conditions`，无条件忽略对应事件的**所有**页条件。
- **Expected behavior**: 仅应对因交互模式变量 `v100` 临时改写而隐藏页面的事件（`5|21|22|28`）跳过 `v100` 检查，保留 `v176`/`v238`/`v69`/`v125` 等脚本阶段门控。
- **Reproduction**: 在 `v69 == 1` 或 `v176 == 1`（统计页打开）时点击相关图片槽位，`action_key_event_ignoring_conditions` 仍会强行启动事件。
- **Root cause**: `f52db44` 的收窄修复随 `b23a1e1` 回退。
- **Impact**: 在脚本明确禁止操作的阶段可能误触发保存/姿势菜单。
- **Minimal fix**: 恢复 `action_key_event_ignoring_interaction_mode`（仅跳过 `2_000_100`）并收窄为 `5 | 21 | 22 | 28`。
- **Regression test**: `the_pose_icon_bridge_keeps_the_scripts_own_stage_gate` (`v69=1` 时禁止启动姿势事件)。
- **Packaging/performance impact**: 无。
- **Related requirement**: `REQ-015`

---

### F-09: `PictureAction::Move` 仍按 `lo..=hi` 逐整数遍历区间
- **Severity**: P2
- **Category**: 性能 / 鲁棒性
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `crates/wolf-game/src/picture.rs:1433`
- **Status**: confirmed (OPEN / REVERTED)
- **Affected flow**: 执行带 `span` 标志的 `150 Move` 批量移动/淡出指令
- **Observed behavior**: `for n in lo..=hi { if n == cmd.number || self.pictures.contains_key(&n) { list.push(n); } }`。
- **Expected behavior**: 使用 `self.pictures.range(lo..=hi)`（`BTreeMap` 有序区间查询）直接枚举活跃槽位并补入 `cmd.number`。
- **Reproduction**: 构造 `cmd.number = 0`、`span_end = 10_000_000` 的 `Move` 指令，单帧将执行一千万次哈希/树查询。
- **Root cause**: `f52db44` 的 `Screen::move_targets()` 修复随 `b23a1e1` 回退。
- **Impact**: 若脚本未初始化或异常传入大跨度 `span`，会造成单帧严重卡顿甚至伪死锁。
- **Minimal fix**: 改用 `self.pictures.range(lo..=hi)` 收集目标槽位。
- **Regression test**: 恢复 `a_move_over_a_wide_span_reaches_only_the_live_slots`（含 `i32::MAX` 跨度护栏）。
- **Packaging/performance impact**: 消除 O(span) 最坏复杂度，降至 O(live_in_span + log N)。
- **Related requirement**: `REQ-016`

---

### F-10: `Assets::cache` 无容量上限且 `Assets::clear()` 在生产路径中未被调用
- **Severity**: P2
- **Category**: 内存生命周期 / 性能
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `crates/wolf-game/src/assets.rs:291,323-327`
- **Status**: confirmed (OPEN)
- **Affected flow**: 长会话游玩、频繁翻阅 CG 相册、多次返回标题并重新读档
- **Observed behavior**: `Assets::clear()` 注释声称 `"Called when returning to the title."`，但全仓 `rg` 显示生产代码（`game.rs` `reset_to_title()` / `load_into()`）从未调用 `self.assets.clear()`；且 `Assets.cache`（`HashMap<String, ImageData>`）无条目数或字节预算上限。
- **Expected behavior**: 返回标题时清理（或基于 LRU/字节预算淘汰）非常驻解码图像，防止 RSS 单调增长。
- **Reproduction**: 全局搜索 `clear(`，确认 `assets.rs:324` 无任何生产调用点。
- **Root cause**: 实现了 `clear()` 方法与注释，但未接入 `Game::reset_to_title()`。
- **Impact**: 长时间游玩并浏览相册大 CG 后，所有解码 RGBA 图像永久驻留内存（历史静态估算全量上限约 949 MiB，实际视可达图像而定）。
- **Minimal fix**: 在 `Game::reset_to_title()` 调用 `self.assets.clear()`，或为 `Assets.cache` 增加字节上限 LRU 淘汰。
- **Regression test**: 单元测试验证 `reset_to_title()` 后 `assets.len() == 0`（或缓存不超过预算）。
- **Packaging/performance impact**: 降低长会话峰值内存占用；返回标题后首次进游戏会重新解码常用 UI 图（毫秒级）。
- **Related requirement**: `REQ-041`

---

### F-11: `\img` 内联贴图跳过逻辑仍使用 `contains(r"\img")` 整条吞文字
- **Severity**: P2
- **Category**: 文本 / 渲染防御性缺陷
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `crates/wolf-game/src/atlas.rs:780`, `crates/wolf-game/src/game.rs:3275`
- **Status**: confirmed (OPEN / REVERTED)
- **Affected flow**: 绘制包含 `\img[...]` 的文本图片槽位
- **Observed behavior**: `if picture.text.contains(r"\img") { continue; }` 在 `text_quads()` 中整条跳过文字生成，且 `atlas.rs:780` 未按 `picture.anchor` / `scale` / `alpha <= 0` 完整处理。
- **Expected behavior**: 仅当文本 picture 为纯图片条时跳过 `text_quads()`，图文混排应保留普通文字 run；贴图渲染应过滤 `alpha <= 0`。
- **Reproduction**: 构造 `"HP \img[icon.png]"` 文本图片，文字部分完全消失。
- **Root cause**: `f52db44` 修复随 `b23a1e1` 回退（当前本作数据 771 条 `\img` 均为纯图片，故暂未触发用户可见故障）。
- **Impact**: 对原版数据当前无可见故障，但对 Mod/翻译补丁中的图文混排构成隐性破坏。
- **Minimal fix**: 恢复 `is_inline_image_only()` 判定并在 `atlas.rs` 过滤 `alpha <= 0`。
- **Regression test**: `a_picture_that_mixes_text_and_images_keeps_its_words`。
- **Packaging/performance impact**: 无。
- **Related requirement**: `REQ-012`

---

### F-12: Godot 模态弹窗期间 `F11` 全屏切换热键被 `_input` 吞噬
- **Severity**: P3
- **Category**: 输入 / 热键
- **Confidence**: High
- **Evidence level**: E1
- **Location**: `godot/scripts/GameView.gd:625-629,1009-1014`
- **Status**: confirmed (OPEN)
- **Affected flow**: 打开「返回标题」或「存档槽」模态框时按 `F11` 切换全屏
- **Observed behavior**: `_input` 在 `_modal_kind` 非空时直接调用 `_handle_modal_event(event)` 并执行 `get_viewport().set_input_as_handled(); return`，而 `F11` 处理位于 `_unhandled_input`，导致事件无法到达。
- **Expected behavior**: 窗口级全屏热键 `F11` 在模态打开时仍应可响应（或不吞掉 `KEY_F11`）。
- **Reproduction**: 在游戏内按 `Esc` 打开确认框后按 `F11`。
- **Root cause**: 模态分支在 `_input` 顶部无差别拦截全部输入事件。
- **Impact**: 轻微体验瑕疵（关闭模态后可恢复使用 `F11`）。
- **Minimal fix**: 在 `_handle_modal_event` 或 `_input` 模态分支放行 `KEY_F11`。
- **Regression test**: GDScript 输入单测验证模态打开时按 `F11` 触发窗口模式切换。
- **Packaging/performance impact**: 无。
- **Related requirement**: `GUIDE §5.4`
