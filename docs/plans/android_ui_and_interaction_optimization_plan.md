# Imouto! Life ~Monochrome~（Rust + Godot 4.7.2）安卓端交互优化与缺陷修复方案

- **基线快照**：`e716f08f273f8aedced65e1b95502b90678ffd7b`
- **分析方式**：只读静态源码定位（未修改仓库源码）
- **涉及模块**：`crates/wolf-game/src/game.rs`、`crates/wolf-game/src/choice.rs`、`crates/wolf-game/src/savegame.rs`、`godot/scripts/GameView.gd`

---

## 问题与优化清单总览

| 编号 | 模块 | 问题/需求摘要 | 核心涉及文件 |
| :--- | :--- | :--- | :--- |
| OPT-01 | 存档界面 (`CE131`) | 点击非存档槽空白区域改为退出存档页面 | `crates/wolf-game/src/game.rs` |
| OPT-02 | 相册界面 (`CE303`) | 点击可交互查看 CG 区域外改为退出相册界面 | `crates/wolf-game/src/game.rs` |
| OPT-03 | 存档界面 UI | 自动保存提醒框右下角新增“回到标题界面”按钮（复用恶作剧退出图标） | `godot/scripts/GameView.gd`、`crates/wolf-game/src/game.rs` |
| OPT-04 | 存档翻页与默认页 | 打开默认定位第 1 页或最新存档所在页；支持点击紫色左右箭头翻页 | `crates/wolf-game/src/game.rs` |
| OPT-05 | 选项框尺寸与对齐 | 加长“是/否”等短选项框；所有选项框横向中轴线与游戏窗口中轴线对齐 | `crates/wolf-game/src/choice.rs` |
| BUG-06 | 事件期快捷按钮门控 | 早起后/傍晚自动存档前屏蔽保存/相册/数据与侧拉栏；修复对话中读档卡死 | `crates/wolf-game/src/game.rs`、`crates/wolf-game/src/savegame.rs` |

---

## 1. OPT-01：点击存档界面非存档槽区域改为退出存档页面

### 现状与根因
- `crates/wolf-game/src/game.rs` 中的 `sync_save_grid_cursor()`（第 4399–4444 行）在左键按下时遍历 `0..slots` 调用 `save_grid_row_rect(index)`。
- 若点击位置不在 4 个存档槽矩形内，`slot` 为 `None`，函数直接返回，既未消费左键，也未注入取消信号。
- 未被消费的左键仍会通过 `pending_mouse` 向 `CE131` 的 `opcode 123` 轮询输送确认信号，导致页面出现重载感或误触发当前选中槽。

### 改动方案
1. 在 `sync_save_grid_cursor()` 处理左键按下边沿（`clicked == true`）时，按优先级做命中判定：
   - 优先判定左右翻页箭头（见 OPT-04）及“回到标题”按钮区域（见 OPT-03）；
   - 其次判定 4 个存档槽矩形 `save_grid_row_rect(index)`；
   - 若以上区域均未命中（即点击空白背景），设置 `self.mouse_consumed = true`，并向 `self.key_bits` 注入 `crate::key::CANCEL`，使 `CE131` 退出存档界面。
2. 同步确保 `godot/scripts/GameView.gd` 的 `_open_save_slot_modal()` 仅在 `wolf.save_slot_at(...)` 命中有效槽位时拦截弹窗，空白处点击放行至上述逻辑。

### 验收要点
- 在存档/读档界面点击上方标题栏、四周背景或右侧说明框以外的空白区域时，直接退出存档界面，不再重载页面。

---

## 2. OPT-02：点击回忆相册可交互 CG 区域外改为退出相册界面

### 现状与根因
- `CE303`（回忆相册）在 `in_submenu()`（`crates/wolf-game/src/game.rs:2052`）中目前仅依赖右键或 `Esc` 触发 `CANCEL` 退出，缩略图以外区域左键无响应。

### 改动方案
1. 在 `CE303` 运行期间（`vm.instances().iter().any(|i| i.event == 303)`）监听左键按下边沿：
   - **区分状态**：仅在缩略图网格浏览态生效（需排除已点开全屏 CG 鉴赏的状态，避免看大图时点击屏幕误退整个相册）；
   - 获取当前 `CE303` 绘制的可见缩略图 `Picture` 矩形集合；
   - 若左键坐标未落入任何可交互缩略图矩形内，设置 `self.mouse_consumed = true` 并注入 `crate::key::CANCEL` 退出相册。

### 验收要点
- 相册网格页点击缩略图外空白处直接退出回房间；点开大图 CG 时仍按原逻辑关闭大图/翻页，不会直接退出整个相册。

---

## 3. OPT-03：存档页面自动保存提醒框右下角增加“回到标题界面”按钮

### 现状定位
- 自动保存提醒框位于 `godot/scripts/GameView.gd`：
  - `SAVE_NOTICE_Z := 99990`（第 17 行）
  - `SAVE_NOTICE_RECT := Rect2(716.0, 96.0, 276.0, 216.0)`（第 18、51 行）
  - 当 `wolf.save_ui_active()` 为真时，在渲染管线中添加 `{"save_notice": true, "z": SAVE_NOTICE_Z}` 并调用 `_draw_save_notice()`（第 118–144、1324–1326 行）。
- 恶作剧界面的“退出”图标已在 `crates/wolf-game/src/game.rs:153` 确认为 `Picture/endbutton.png`（picture `1108`）。

### 改动方案
1. **图标资源与绘制**：
   - 在 `GameView.gd` 中通过游戏数据目录纹理加载并缓存 `Picture/endbutton.png`。
   - 仅当 `wolf != null and wolf.save_ui_active()` 时，在 `_draw_save_notice()`（或同一 `SAVE_NOTICE_Z = 99990` 批次）中将按钮绘制在 `SAVE_NOTICE_RECT` 右下角附近（位于右下角相册图标 `-7` 的上方，留出安全间距防止触控重叠）。
   - 确保该按钮与存档页面其他 UI 处于同一渲染层（`SAVE_NOTICE_Z`，位于游戏画面之上、鼠标指针之下），且关闭存档界面后自动消失。
2. **点击交互与确认流**：
   - 在 `GameView.gd::_input()` 鼠标左键分支中，若 `wolf.save_ui_active()` 且点击命中该“回到标题”按钮矩形，消费事件并调用 `_open_return_modal()`。
   - **关键调整**：当前 `_open_return_modal()`（第 943 行）有 `if wolf.at_title() or wolf.in_submenu(): return`，需允许从 `save_ui_active()` 入口打开返回标题确认弹窗；在用户点击确认回到标题时，确保先清理/退出 `CE131` 再重置到标题界面。

### 验收要点
- 仅在打开存档/读档界面时显示该图标，位置在提醒框右下角（相册图标上方）；点击后弹出确认并可正常回到标题界面，关闭存档界面后图标消失。

---

## 4. OPT-04：打开存档界面默认页码修正 + 紫色左右翻页箭头可点击

### 4.1 默认打开页码（第 1 页或最新存档所在页）

#### 现状与根因
- `CE131` 的当前页码存储在实例自变量 `self[611]` 中（`crates/wolf-game/src/game.rs:2079`）。打开存档界面时未根据本地存档重置该值，导致默认落在了第 2 页（`page == 1`）。

#### 改动方案
- 在检测 `save_grid_active()` 从 `false` 变为 `true` 的边沿帧：
  1. 扫描 `Save/SaveData01.sav` ~ `SaveData*.sav`（覆盖有效槽位范围）；
  2. 若存在至少一个存档文件，取 `metadata.modified()` **最新**的槽位编号 `latest_slot`，计算 `target_page = (latest_slot - 1) / per_page`、`target_row = (latest_slot - 1) % per_page`；
  3. 若没有任何存档文件，则 `target_page = 0`（第 1 页）、`target_row = 0`；
  4. 将 `target_page` 写入 `CE131` 实例的 `self[611]`，同步更新 `self[610] = target_row`，并触发 `apply_save_grid_layout()` 刷新槽位文本与高亮。

### 4.2 紫色左右翻页箭头可点击

#### 现状定位
- 两个紫色翻页箭头已在 `crates/wolf-game/src/game.rs:1985-1996` 定位：
  - 左箭头：`picture 12004`（逻辑坐标 `x = 8, y = 280`）
  - 右箭头：`picture 12005`（逻辑坐标 `x = 691, y = 280`）
- 当前 `sync_save_grid_cursor()` 未检测这两张图的点击。

#### 改动方案
- 在 `sync_save_grid_cursor()` 左键按下边沿检测 `12004` 与 `12005` 的命中区域（考虑到安卓手指触控，建议将逻辑点击热区适当扩大，例如以箭头中心向外扩展至至少 `44 × 64` 逻辑像素）：
  - 命中 `12004`（左箭头）：设置 `self.mouse_consumed = true`，注入 `crate::key::LEFT`（或直接翻至上一页）；
  - 命中 `12005`（右箭头）：设置 `self.mouse_consumed = true`，注入 `crate::key::RIGHT`（或直接翻至下一页）。
- 必须消费本次左键，防止翻页点击同时被 `CE131` 当作 `OK` 确认当前槽位。

### 验收要点
- 无存档时打开固定在第 1 页（槽位 1–4）；有存档时自动定位到最新存档那一页；点击左/右紫色箭头可正常翻页且不误触读/存档。

---

## 5. OPT-05：“是/否”选项框加长 & 所有选项框横向中轴线与窗口中轴线对齐

### 现状与根因
- 位于 `crates/wolf-game/src/choice.rs`：
  1. `size()`（第 146–159 行）直接按最长选项文本宽度计算：`let width = widest + TEXT_INSET * 2.0 + 4.0;`（无最小宽度下限），导致“是 / 否”等两字选项框极窄，安卓端难以点击。
  2. `layout_at_sized()`（第 230–277 行）当脚本传入的 `(x, y)` 满足 `on_screen` 时，直接采用脚本坐标 `(x, y)` 作为面板左上角，未做居中对齐，导致部分选项框在画面中明显偏上；仅当 `(x, y)` 越界或为 `(0, 0)` 时才回退居中 `((SCREEN_W - width) / 2.0, (SCREEN_H - height) / 2.0)`。

### 改动方案
1. **增加最小宽度下限**（`choice.rs::size`）：
   - 为非标题图片菜单（`!is_title_image_menu(options)`）的 `width` 设置最小宽度下限，例如 `.max(240.0)`（在 `1024 × 576` 逻辑画布下足够容纳“是/否”并留出舒适触控宽度）。
   - 同步更新 `choice.rs` 中原本断言“无最小宽度”的单元测试（第 536–538 行附近）。
2. **统一居中对齐**（`choice.rs::layout_at_sized`）：
   - 对非标题图片菜单的所有 `102` 选项框，统一使用逻辑屏幕居中坐标：
     - 水平方向：`cx = ((SCREEN_W as f32) - width) / 2.0`
     - 垂直方向：`cy = ((SCREEN_H as f32) - height) / 2.0`
   - 使所有选项框的横向中轴线与游戏窗口横向中轴线完全重合，避免选项偏上影响安卓单手/双手点击。

### 验收要点
- 二次确认“是/否”弹窗长度明显加长、易于点击；全游戏所有普通选项框均以屏幕中心为基准水平与垂直居中，不再出现偏上情况。

---

## 6. BUG-06：早起后 / 傍晚自动存档前屏蔽快捷 UI，并修复对话中读档对话框残留卡死

### 现状与双层根因
1. **前置门控不足（为什么剧情期还能点到按钮）**：
   - `crates/wolf-game/src/game.rs:3824-3905` 的 `handle_action_key_input()` 仅检查 `!self.messages.is_empty() || self.choices.is_some()` 以及 `matches!(instance.event, 14 | 95 | 131 | 132)`。
   - 早上起床后与妹妹对话的事件链中，两句对话切换的 1 帧间隙、或事件处于 `Wait` / 移动路线 / 自动演出（`Autorun`）期间，以及傍晚自动存档前的过场阶段，`self.messages` 会短暂为空，导致 `handle_action_key_input()` 放行了 `picture_action_event_at`（`-5` 保存 / `-7` 相册 / `-4` 数据）和 `try_side_panel_handle`（`320` 状态栏 / `2300` 物品栏）。
   - 此外 `event 35`（相册图标）走独立的 Parallel 轮询，也未在剧情阻塞期间统一屏蔽。
2. **读档未清理消息队列（为什么读档后对话框残留且操作卡死）**：
   - `crates/wolf-game/src/savegame.rs:82-235` 的 `load_into()` 只调用了 `game.clear_message_history()` 和 `game.screen.clear()`，**没有清空 `game.messages` 和 `game.choices`**（`self.messages.clear()` 目前仅在 `reset_to_title()` 中调用，见 `game.rs:2417`）。
   - 对话中途读档后，旧的 `game.messages` 仍残留在屏幕上渲染，而原对话事件协程已被 `load_into()` / `retire_load_ui_chain()` 清除，导致旧对话框无法推进也无法关闭，整局操作彻底锁死。

### 改动方案
1. **必改兜底（彻底根除残留卡死）**：
   - 在 `savegame::load_into()`（`crates/wolf-game/src/savegame.rs:89` 附近）或 `SaveRequest::Load` 成功分支（`crates/wolf-game/src/game.rs:4676`）中显式清理：
     ```rust
     game.messages.clear();
     game.choices = None;
     game.choice_cursor = 0;
     ```
2. **前置屏蔽（剧情/过场期间禁用快捷按钮与侧拉栏）**：
   - 在 `handle_action_key_input()` 中新增“阻塞性剧情/演出进行中”判定（例如存在运行中的 `Autorun` 地图事件、正在推进的非空闲前台地图交互事件，或处于早起后/傍晚自动存档前过渡变量区间）：
     - 阻塞期间直接返回，禁止触发 `PICTURE_ACTION_CONTROLS` 中的保存（`-5`）、相册（`-7`）、数据（`-4`）以及 `try_side_panel_handle()`（`320` / `2300` 侧拉栏）；
     - 同步抑制 `event 35` 相册按钮在阻塞期间的响应，并可在视觉上将快捷图标在阻塞期保持半透明或隐藏（与原版交互锁一致）。

### 验收要点
- 早上起床后对话结束前、傍晚自动存档完成前，点击“保存 / 相册 / 数据”或左右侧拉栏均无响应。
- 任意时机执行读档后，不会残留读档前的对话框或选项框，画面与操作立即恢复正常。
