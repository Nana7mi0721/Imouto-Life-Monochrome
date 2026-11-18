# 《妹！生活 ～単色～》`46de4eb` 完整代码审查与新增 Bug / 定制改造报告

> **归档说明（2026-11-18）**：本文为`46de4eb` 的完整代码审查与新增 Bug / 定制改造报告，内容已被 [`docs/reviews/CODE_REVIEW_4ROUND.md`](../../reviews/CODE_REVIEW_4ROUND.md) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


**审查目标**：`nana7mi0721/imouto-life` 最新提交 `46de4ebc9ee660212a8f3a8bb0d5e0dacead8b65`（`46de4eb`）
**重要标注约定**：本报告明确区分 **【移植 Bug】**（代码实现缺陷）与 **【原版设计，用户要求更改】**（零售原版即如此，但本次按用户需求主动偏离原版以提升体验），方便本地开发代理准确执行。

---

## 一、`46de4eb` 新增与改动代码总览审查

| 模块 | 主要改动 | 审查结论 |
| :--- | :--- | :--- |
| `crates/wolf-game/src/pointer.rs` | 新增引擎侧手型指针槽 `POINTER_SLOT = 2998`（`CharaChip/hand3.png` cell 0，hotspot `(4,1)`），按 `Sys74` 与 `2999` 互斥 | 思路正确，但 Z 轴层级与隐藏策略受制于原版 `Sys74`，需按【需求 6】调整 |
| `crates/wolf-game/src/game.rs` | 新增 `request_load`、`set_auto_save_slot`、`ce258_running` 晚饭后自动存档钩子、`trigger_return_to_title`、`sister_body_action_event_at` 补全 `pose 5` | `request_load` 与 `ce258` 钩子结构合理；需排查读档后相册残留（Bug 1）与卧室妹妹判定偏移（Bug 5） |
| `crates/wolf-game/src/savegame.rs` & `wolf-vm/src/rng.rs` | 支持 `WOLF_LIVE_RNG=1` 实机游标扰动，默认保持确定性 | 符合预期，`cargo test --workspace` 确定性不受破坏 |
| `crates/wolf-gdext/src/lib.rs` | 暴露 `save_slot_at`、`request_load`、`return_to_title`、`at_title`、`set_auto_save_slot` | 桥接安全；需补充「是否在二级界面」查询接口供 `Esc` 过滤，并调高指针 `sprite_z` |
| `godot/scripts/GameView.gd` | 新增 `_ModalLayer`（返回标题确认、存档槽保存/读取弹窗、自动存档提示）、`_input` 顶部拦截左键 | `_input` 顶部防误覆盖设计正确；漏了回车键触发弹窗（Bug 2）与二级界面 `Esc` 屏蔽（Bug 3） |

---

## 二、新增 Bug 排查与【用户要求更改】清单

### Bug 1：读取存档后会进入相册界面且无法左/右键关闭 【移植 Bug】

- **现象**：读取存档后画面直接进入相册界面，左键/右键均无法关闭，必须点击「数据」图标强制替换后才能正常退出。
- **代码定位**：`crates/wolf-game/src/game.rs:3318-3335`（`retire_load_ui_chain`）与 `game.rs:4297-4345`（`SaveRequest::Load` 处理流程）。
- **根因排查方向**：
  1. `retire_load_ui_chain()` 当前仅清理 `BOOT_EVENT | TITLE_EVENT | 14 | 95 | 131 | 132`，**未清理在读档前可能残留、或由存档内状态/事件栈带出的相册事件（`CE 301` / `CE 303` `アルバム画面呼び出し`）及普通地图动作事件**；
  2. 若所读存档是在曾开启过相册、或 `SavePart5` 画面残存相关图片/变量的状态下保存的，`load_into` 恢复画面后，`resume_loaded_map()` 安装了新地图运行时，但旧事件实例或未清空的 `pending_mouse` / `mouse_consumed` 可能误触发了右下角相册图标（`slot -7` `icon06.png` -> `Event 35`），且相册内部轮询被残留状态锁死。
- **修复建议**：
  - 在 `SaveRequest::Load` 成功后：
    1. 强制清空 `pending_mouse`、`mouse_buttons` 边沿状态与 `reserved_events`；
    2. 扩大 `retire_load_ui_chain()` 的清理范围（或直接重置除系统常驻后台外的所有前台 UI 协程，包括 `CE 301 / 303` 等二级界面事件），确保读档后纯净回到存档时的地图与日常状态。

---

### Bug 2：选中存档槽按回车键无法弹出保存/读取选项框 【移植 Bug】

- **现象**：在存单界面鼠标点击非空存档槽会弹出「保存到此槽 / 读取此存档 / 取消」弹窗，但用键盘选中存档槽后按回车键（`Enter`）不会弹窗，直接走原版逻辑。
- **代码定位**：`godot/scripts/GameView.gd:560-599`（`_input`）与 `719-748`（`_open_save_slot_modal`）。
- **根因分析**：`_open_save_slot_modal` 目前仅在 `event is InputEventMouseButton`（左键按下）时调用；键盘按下 `KEY_ENTER` / `KEY_KP_ENTER` / `KEY_SPACE` 时直接进入 `held_keys` 并送入 `wolf`，完全绕过了弹窗拦截。
- **修复建议**：
  - 在 `wolf-gdext` 暴露当前选中的存档槽信息（`selected_save_slot()`：当 `save_grid_active()` 为真时，读取 `CE 131` 的 `self[610]` / `self[611]` / `self[627]` 计算槽号与是否非空）；
  - 在 `GameView.gd` 的 `_input` 中，若当前无弹窗且 `wolf.save_grid_active()` 为真，按下 `KEY_ENTER` / `KEY_KP_ENTER` / 决定键时同样拦截并调用 `_open_save_slot_modal_for_slot(hit)`，选择「保存」后再向 VM 补发一次决定键边沿。

---

### Bug 3：`Esc` 触发返回标题范围太大，二级界面按 `Esc` 也会弹窗 【移植 Bug】

- **现象**：在保存、相册、数据、设置等二级界面按 `Esc` 本应取消/返回上一级，但当前版本直接弹出「返回标题画面？」确认框。
- **代码定位**：`godot/scripts/GameView.gd:582-589` 及 `691-697`（`_open_return_modal`）。
- **根因分析**：`_input` 中无条件截获 `KEY_ESCAPE` 调用 `_open_return_modal()`，而 `_open_return_modal()` 只检查了 `if wolf.at_title(): return`，没有判断当前是否处于保存/读取（`CE 131`）、相册（`CE 301/303`）、数据（`Event 30` / `Picture 500..650`）、设置（`CE 95/132`）或选项框等二级界面。
- **修复建议**：
  - 在 `Game` / `wolf-gdext` 新增 `in_submenu() -> bool`（检查 `save_grid_active()`、`CE 95 / 132 / 301 / 303` 是否运行，或 `choices.is_some()`）；
  - 当 `wolf.in_submenu()` 为 `true` 时，按 `Esc` 不触发返回标题确认框，而是放行作为 WOLF 的取消键（等价 `Backspace / X`）关闭当前二级界面；仅在主地图自由探索/日常主界面按 `Esc` 时才弹出返回标题确认框。

---

### Bug 4：侧拉栏拉出时数字/文字直接跳到最终位置，收回时正常 【移植 Bug】

- **现象**：晚上卧室界面展开左侧状态栏/物品栏时，文字与数字直接闪现在完全拉出后的最终坐标（`+305`），没有跟随侧拉栏底图一起平滑滑出；收回时则表现正常。
- **字节码与代码定位**：
  - `CE 238`（`ステータス`）：
    - **隐藏分支（`pc=4..7`）**：`320` 底图与 `321..325` 文字全部使用 `150 Draw`（`fade=10`）放在 `x = -305` 附近；
    - **拉出分支（`pc=69..74`）**：`pc=69` 对 `320` 底图执行 `150 Draw`（`head=0x10000`，`relative`，`fade=20`）；而 `pc=70..74` 对 `321..325` 文字执行 `150 Move`（`head=0x10001`，`dx=+305`，但**指令尾部没有帧数参数 `animate=[]`**！）。
  - `crates/wolf-game/src/picture.rs:732-736`：`Transition::from_command` 因 `animate` 为空返回 `None`，导致 `321..325` 立即瞬移至最终位置且 `opacity=255`；而 `320` 底图因 `Draw` 带有 `fade=20` 处于透明渐显中，视觉上就变成了「数字先出现在最终位置、底板后出来」。
- **修复建议**：
  - 在 `Game::start_panel_event`（或引擎对 `CE 238/239` 侧拉栏的统一平滑补间）中，为侧拉栏容器（`320` 及 `321..=325`，以及 `2300` 及 `2301..=2317`）在展开/收起时统一注入同步的水平位移动画（如 `8~10` 帧从 `x - 305` 平滑插值到 `x`），确保文字与底板保持相对静止同步滑出、同步收回。

---

### Bug 5：卧室界面与妹妹交互判定范围向右下偏移，未按全身显示范围生效 【移植 Bug】

- **现象**：当前卧室界面点击妹妹时，有效判定区域明显向原判定范围的右下方偏移，仍无法按妹妹全身实际显示轮廓准确交互。
- **代码定位**：`crates/wolf-game/src/game.rs:3633-3687`（`sister_body_action_event_at`）与 `3756-3822`（`picture_alpha_hit`）。
- **根因排查方向**：
  1. 当 `CE 240` 在卧室绘制 `900..=903` 时，需核查 `900` 实际使用的文件名是否确实以 `"Picture/stand_"` 开头、以及 `screen.picture_rect(900)` 计算出的 `destination` 锚点/缩放与 `SampleMapA` 地图事件格子是否一致；
  2. 若 `pose == 5`（睡姿）或 `has_standing_art` 未命中而走入地图事件矩形，当前 `game.rs:3680` 的 fallback 仅对原地图 16×16 格子向外扩 `16 px`，而原地图格子在卧室中若偏右下或未覆盖全身，就会导致判定区域整体偏右下；
  3. 需在实机卧室状态下打印 `screen_picture_info(900..=903)` 的 `rect` 与 `file`，确认是 `has_standing_art` 守卫条件漏判、还是 `picture_rect` 的 `anchor` 偏移导致。

---

### 需求 6：光标图标图层优先级与全界面显示 【原版设计，用户明确要求更改】

- **原版行为说明**：零售原版中，`2998/2999` 光标层级按图片编号排序，低于 `12xxx` 存档页与 `36000` 对话气泡/选项框；且 `CE 224` 会在选项、对话、过场期间将 `Sys74` 置 `0` 隐藏手指图标。
- **用户明确更改要求**：**即使这是原版设计，也必须更改**——让手指/交互光标图标在**一切可以使用鼠标操作的页面**（包括选项框、对话气泡、存档页面及其他选项事件）都显示在最顶层，不被遮挡或隐藏。
- **修改方案**：
  1. **图层置顶**（`crates/wolf-gdext/src/lib.rs:832-838`）：在 `sprite_z(number)` 中，将 `POINTER_SLOT (2998)` 与 `GAME_POINTER_SLOT (2999)` 的 Z 值设为高于 `UI_Z`（例如 `UI_Z + 100`），并确保高于所有气泡、选项框、文本与存档网格；
  2. **取消菜单/选项隐藏**（`crates/wolf-game/src/pointer.rs:80`）：不要在 `choices.is_some()`、气泡对话、`save_grid_active()`、相册/数据等可鼠标交互状态下因为 `Sys74 == 0` 而擦除 `2998` 指针（仅在前端模态弹窗 `_ModalLayer` 打开时交由系统光标或同步渲染置顶）。

---

### 需求 7：存档页面样式改造为姊妹作风格 【原版设计，用户明确要求更改】

- **原版行为说明**：当前存档页（对应附图 `{63611B06}`）沿用 WOLF 默认简洁模板，仅显示 `数据 N`、游玩时长和简略角色名/数字。
- **用户明确更改要求**：参考姊妹作存档页截图（`{D9506FC0}`），在保留本作已有元素的前提下进行以下改造（**不加妹妹 SD 立绘和 `NORMAL` 难度字样**，因为本作无对应素材）：
  1. **右上角注意事项框**：在存档列表右侧增加说明框，提示玩家「第一栏为自动存档所使用；第一栏已有存档数据时，请先读取该存档，再保存至合适位置」；
  2. **第一栏自动存档标注**：第 1 槽标题显式标注为 `数据 1 自动存档`（区分于 `数据 2`、`数据 3`、`数据 4`）；
  3. **每栏详细信息扩展**：从 `.sav` 解析或随存档快照读取并展示：**天数、周几、游戏内时间、以及哥哥的属性/称号**（例如 `128天 周二 22時  温柔的哥哥`）。
- **实现路径建议**：在 `savegame.rs` 扩展读取存档摘要结构（从 `SavePart3` 的正常变量中提取天数、星期、时间与哥哥属性字符串），并通过 `wolf-gdext` 传递给 Godot 前端或由引擎覆盖绘制 `12050+` 槽位文本与右上角说明面板。

---

### 需求 8：行动力条样式复刻姊妹作 【原版设计，用户明确要求更改】

- **原版行为说明 / 当前实现**：当前 `godot/scripts/GameView.gd:82-101`（`_draw_action_points_dict`）绘制的是深灰底槽（`Color(0.16,0.16,0.16,0.92)`）+ 浅灰细边框 + 1px 内缩浅灰填充（见 `{0E9DE4B2}`）。
- **用户明确更改要求**：复刻姊妹作顶栏样式（见 `{82DD6742}`）：
  - 去掉深灰底槽与外边框（背景直接融入黑色顶栏，或仅在消耗后留黑底），改为**纯白实心长条**（`Color(1.0, 1.0, 1.0, 1.0)`），并紧凑对齐「行动力」文字右侧与 `current/max` 数值左侧。
- **修改位置**：直接修改 `godot/scripts/GameView.gd:87-101` 的 `_draw_action_points_dict`，去掉边框 `draw_rect(..., false, 1.0)` 与灰底，改用纯白实心矩形并微调 `box` 坐标与宽度对齐顶栏文本。
