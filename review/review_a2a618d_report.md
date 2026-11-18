# 《妹！生活 ～単色～》最新提交 `a2a618d` 完整代码审查报告

**审查目标**：`nana7mi0721/imouto-life` 提交 `a2a618d1fc0a479ea47269b6616be37b76ffcd44`（`a2a618d`）

**基线对比**：相对上一提交 `81853d1`

**改动文件**：`crates/wolf-game/src/game.rs`、`godot/scripts/GameView.gd`，以及新增/更新测试 `m25_sister_body_rects.rs`、`m25_sister_pose5.rs`、`m25_save_slot.rs`、`m17_ui_regressions.rs`、`save_slot_modal.gd`。

## 一、已确认修复并验证通过的改动

| 对应问题 | 代码定位 | 实现评估 |
| ----- | ----- | ----- |
| **1. `in_submenu()` 在卧室恒为 `true` 导致 `Esc` 失效** | `game.rs:1978-1980` | **通过**。已从检查所有 `ActionKey` 激活页改为 `slot.trigger == Trigger::ActionKey && slot.instance().is_some()`，仅在动作键事件正在运行时视为二级界面，卧室自由探索按 `Esc` 可正常弹出返回标题确认框。 |
| **2. 卧室妹妹全身点击判定 & 枕头优先权** | `game.rs:559-581, 3970-4007` | **通过**。已用 6 个姿势的实测 `1024×576` 全身矩形 `SISTER_BODY_RECTS` 替代原版小格子，并把 `Ev 13` 枕头（`[56, 340, 134, 88]`）排在 `pose == 5` 睡觉妹妹之前，且在 `900..=903` 立绘出现时正确退让。 |
| **3. 恶作剧「道具」下方空框误触换姿势** | `game.rs:148-156, 7880-7901` | **通过**。已从 `PICTURE_ACTION_CONTROLS` 移除整块底框 `1109`（`Picture/pose_iconarea.png`），保留 `1110` 与 `1117` 按钮，并附带回归测试锁定。 |
| **4. 点击「相册」图标偶发无反应** | `game.rs:3727-3734` | **通过**。在 `handle_action_key_input` 对 `event == 35` 提前 `return` 且不置 `mouse_consumed = true`，避免吞掉并行事件 `Ev 35` 自身的 `124` + `123` 点击轮询边沿。 |
| **5. 对话框先出文字后出头像导致高度跳变** | `game.rs:3159-3163` | **通过**。`balloon_has_face()` 去掉了 `face.opacity > 0` 门槛，改为只要 `36002` 未隐藏且文件名非空，第 1 帧即按含头像高度排版，消除文字上跳瞬移。 |
| **6. 存单页面姊妹作左栏右说明框改造** | `game.rs:589-602, 1889-2110`；`GameView.gd:14, 114-142` | **通过**。槽位已收窄至左侧 `48..684`（`save_grid_row_rect` 与渲染同源对齐），翻页箭头挪至 `x=8 / x=691`，隐藏多余头像只保留完整哥哥属性 + 时长/天数/周几/时间；右侧 `SAVE_NOTICE_RECT` 已移至 `(716, 96, 276, 216)` 分 6 行清晰展示。 |

## 二、遗留未修复问题（需补充修复）

### 1. 存档界面预选高亮仍未随鼠标移动实时更新 【移植 Bug】

* **代码定位**：`crates/wolf-game/src/game.rs:4270-4302`（`sync_save_grid_cursor`）。

* **现状分析**：`a2a618d` 中 `sync_save_grid_cursor` 的末尾逻辑没有改动，鼠标移动时依然**只更新了 `CE 131` 的内部变量 `self[610]`**，而没有驱动画面上的光标/高亮槽位（`12051 + 20 * row`）同步重绘。

* **影响**：鼠标滑过 1\~4 号存档槽时，底层选中的槽号已经变了，但画面上的蓝色/高亮框仍停留在上一次翻页或键盘方向键停留的位置，造成「视觉高亮与实际点击槽位不一致」的错觉。

* **修复建议**：在 `apply_save_grid_layout()`（每帧渲染前都会执行）中读取 `grid.row`（即 `self[610]`），直接同步每行光标框 `12051 + 20 * row` 的可见性/透明度：

  ```
  if let Some(cursor_pic) = self.screen.get_mut(base + 1) {
      if row == grid.row {
          cursor_pic.hidden = false;
          cursor_pic.opacity = 255;
      } else {
          cursor_pic.opacity = 0;
      }
  }

  ```

  *(注：需核对 `CE 94` 中 `base + 1` 即 `12051 + 20 * row` 是否为槽位选中框/光标；若当前使用 `base + 1` 做高亮，`apply_save_grid_layout` 直接按 `grid.row` 控制显隐即可立即实现零延迟跟随。)*

## 三、潜在边界与后续建议

1. **头像首帧透明度延迟的视觉微调**：`balloon_has_face()` 已消除了对话框高度跳变，但如果 `CE 270` 自身给 `36002` 带了数帧淡入（`fade > 0`），头像仍会有「对话框先撑大、头像淡入出现」的轻微延迟。若希望文字与头像完全同帧实显，可在 `balloon_owns_message()` 渲染路径为 `36002` 强制跳过淡入或保持实显。

2. **存档栏周六/周日颜色区分（可选美化）**：当前 `SaveSummary::status_line()` 统一使用白字；如需进一步贴近姊妹作截图，可在格式化 `weekday` 时为 `周六`、`周日` 加上 `\c[...]` 颜色标签。

---

### 2. 对话文本太靠近对话框边缘，需向右下微调 【原版设计，用户明确要求更改】

- **原版行为说明**：`CE 270` 排版后的气泡正文 `36013`（`BALLOON_BODY_TEXT_PICTURE`）紧贴圆角渐变底框 `36000` 的左上内边缘（如「又是新的一天…」「喘口气吧。」紧挨着半透明阴影边缘）。
- **用户明确更改要求**：**即使原版游戏如此，也需向右下稍微移动一点**，留出更舒适的内边距。
- **代码定位**：`crates/wolf-game/src/game.rs:163-174`、`3383-3389`（`let balloon = picture.number == BALLOON_BODY_TEXT_PICTURE;`）。
- **修复建议**：
  1. 在 `game.rs` 新增偏移常量（建议先试 `x + 12.0, y + 6.0`）：
     ```rust
     const BALLOON_BODY_TEXT_X_OFFSET: f32 = 12.0;
     const BALLOON_BODY_TEXT_Y_OFFSET: f32 = 6.0;
     ```
  2. 在 `game.rs:3383-3389` 对 `balloon` 分支应用偏移：
     ```rust
     let x = x + if balloon { BALLOON_BODY_TEXT_X_OFFSET } else { 0.0 };
     let y = y + if nameplate {
         BALLOON_NAME_TEXT_Y_OFFSET
     } else if balloon {
         BALLOON_BODY_TEXT_Y_OFFSET
     } else {
         0.0
     };
     ```
  3. 同步在 `balloon_frame_target_height()` 中将底部余量同步加上 `BALLOON_BODY_TEXT_Y_OFFSET`（约 `+6 px`），防止多行长文本下移后贴近或裁切底边。

《妹！生活 ～単色～》最新提交 a2a618d 完整代码审查报告审查目标：nana7mi0721/imouto-life 提交 a2a618d1fc0a479ea47269b6616be37b76ffcd44（a2a618d）基线对比：相对上一提交 81853d1改动文件：crates/wolf-game/src/game.rs、godot/scripts/GameView.gd，以及新增/更新测试 m25_sister_body_rects.rs、m25_sister_pose5.rs、m25_save_slot.rs、m17_ui_regressions.rs、save_slot_modal.gd。一、已确认修复并验证通过的改动对应问题代码定位实现评估1. in_submenu() 在卧室恒为 true 导致 Esc 失效game.rs:1978-1980通过。已从检查所有 ActionKey 激活页改为 slot.trigger == Trigger::ActionKey && slot.instance().is_some()，仅在动作键事件正在运行时视为二级界面，卧室自由探索按 Esc 可正常弹出返回标题确认框。2. 卧室妹妹全身点击判定 & 枕头优先权game.rs:559-581, 3970-4007通过。已用 6 个姿势的实测 1024×576 全身矩形 SISTER_BODY_RECTS 替代原版小格子，并把 Ev 13 枕头（[56, 340, 134, 88]）排在 pose == 5 睡觉妹妹之前，且在 900..=903 立绘出现时正确退让。3. 恶作剧「道具」下方空框误触换姿势game.rs:148-156, 7880-7901通过。已从 PICTURE_ACTION_CONTROLS 移除整块底框 1109（Picture/pose_iconarea.png），保留 1110 与 1117 按钮，并附带回归测试锁定。4. 点击「相册」图标偶发无反应game.rs:3727-3734通过。在 handle_action_key_input 对 event == 35 提前 return 且不置 mouse_consumed = true，避免吞掉并行事件 Ev 35 自身的 124 + 123 点击轮询边沿。5. 对话框先出文字后出头像导致高度跳变game.rs:3159-3163通过。balloon_has_face() 去掉了 face.opacity > 0 门槛，改为只要 36002 未隐藏且文件名非空，第 1 帧即按含头像高度排版，消除文字上跳瞬移。6. 存单页面姊妹作左栏右说明框改造game.rs:589-602, 1889-2110；GameView.gd:14, 114-142通过。槽位已收窄至左侧 48..684（save_grid_row_rect 与渲染同源对齐），翻页箭头挪至 x=8 / x=691，隐藏多余头像只保留完整哥哥属性 + 时长/天数/周几/时间；右侧 SAVE_NOTICE_RECT 已移至 (716, 96, 276, 216) 分 6 行清晰展示。二、遗留未修复问题（需补充修复）1. 存档界面预选高亮仍未随鼠标移动实时更新 【移植 Bug】代码定位：crates/wolf-game/src/game.rs:4270-4302（sync_save_grid_cursor）。现状分析：a2a618d 中 sync_save_grid_cursor 的末尾逻辑没有改动，鼠标移动时依然只更新了 CE 131 的内部变量 self[610]，而没有驱动画面上的光标/高亮槽位（12051 + 20 * row）同步重绘。影响：鼠标滑过 1~4 号存档槽时，底层选中的槽号已经变了，但画面上的蓝色/高亮框仍停留在上一次翻页或键盘方向键停留的位置，造成「视觉高亮与实际点击槽位不一致」的错觉。修复建议：在 apply_save_grid_layout()（每帧渲染前都会执行）中读取 grid.row（即 self[610]），直接同步每行光标框 12051 + 20 * row 的可见性/透明度：if let Some(cursor_pic) = self.screen.get_mut(base + 1) {
    if row == grid.row {
        cursor_pic.hidden = false;
        cursor_pic.opacity = 255;
    } else {
        cursor_pic.opacity = 0;
    }
}

(注：需核对 CE 94 中 base + 1 即 12051 + 20 * row 是否为槽位选中框/光标；若当前使用 base + 1 做高亮，apply_save_grid_layout 直接按 grid.row 控制显隐即可立即实现零延迟跟随。)三、潜在边界与后续建议头像首帧透明度延迟的视觉微调：balloon_has_face() 已消除了对话框高度跳变，但如果 CE 270 自身给 36002 带了数帧淡入（fade > 0），头像仍会有「对话框先撑大、头像淡入出现」的轻微延迟。若希望文字与头像完全同帧实显，可在 balloon_owns_message() 渲染路径为 36002 强制跳过淡入或保持实显。存档栏周六/周日颜色区分（可选美化）：当前 SaveSummary::status_line() 统一使用白字；如需进一步贴近姊妹作截图，可在格式化 weekday 时为 周六、周日 加上 \c[...] 颜色标签。2. 对话文本太靠近对话框边缘，需向右下微调 【原版设计，用户明确要求更改】原版行为说明：CE 270 排版后的气泡正文 36013（BALLOON_BODY_TEXT_PICTURE）紧贴圆角渐变底框 36000 的左上内边缘（如「又是新的一天…」「喘口气吧。」紧挨着半透明阴影边缘）。用户明确更改要求：即使原版游戏如此，也需向右下稍微移动一点，留出更舒适的内边距。代码定位：crates/wolf-game/src/game.rs:163-174、3383-3389（let balloon = picture.number == BALLOON_BODY_TEXT_PICTURE;）。修复建议：在 game.rs 新增偏移常量（建议先试 x + 12.0, y + 6.0）：const BALLOON_BODY_TEXT_X_OFFSET: f32 = 12.0;
const BALLOON_BODY_TEXT_Y_OFFSET: f32 = 6.0;
在 game.rs:3383-3389 对 balloon 分支应用偏移：let x = x + if balloon { BALLOON_BODY_TEXT_X_OFFSET } else { 0.0 };
let y = y + if nameplate {
    BALLOON_NAME_TEXT_Y_OFFSET
} else if balloon {
    BALLOON_BODY_TEXT_Y_OFFSET
} else {
    0.0
};
同步在 balloon_frame_target_height() 中将底部余量同步加上 BALLOON_BODY_TEXT_Y_OFFSET（约 +6 px），防止多行长文本下移后贴近或裁切底边。