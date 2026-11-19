以下是针对 `1a1741cc` 仓库四个待改项的具体代码实现方案，均已对齐当前 `wolf-game`、`wolf-gdext` 和 `GameView.gd` 的现有结构与接口。

---

### 一、修复 RNG 新开局与同档反复 S/L 游标固定问题

> **归档说明（2026-11-18）**：本文为`1a1741cc` 四项待改项的代码实现方案，内容已被 [`docs/reviews/CODE_REVIEW_4ROUND.md`](../../reviews/CODE_REVIEW_4ROUND.md) 与 [`docs/reviews/LIVE_PLAY_FIX_REPORT.md`](../../reviews/LIVE_PLAY_FIX_REPORT.md) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


**目标**：保留测试/CLI 的确定性（可复现），但在实机游玩开新档或读档时引入系统时间扰动，避免每次新局或 S/L 得出完全相同的随机序列。

#### 1. `crates/wolf-game/src/game.rs`

新增一个仅在非确定性环境变量开启（或默认实机）时使用的随机游标扰动辅助函数，并在 `Game::new` 与 `reset_to_title` 中调用：

```rust
// crates/wolf-game/src/game.rs
fn live_rng_jitter() -> usize {
    if std::env::var_os("WOLF_DETERMINISTIC_RNG").is_some() {
        return 0;
    }
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| (d.subsec_nanos() as usize) ^ (d.as_secs() as usize))
}

```

在 `Game::new`（约 `1140` 行）和 `Game::reset_to_title`（约 `1801` 行）中：

```rust
if let Some(dat) = &game_dat {
    game.vm.rng = WolfRng::from_game(dat.random_a, dat.random_b, dat.static_randoms.clone());
    game.vm.rng.set_cursor(live_rng_jitter());
}

```

> 回归测试（如 `m14` / `wolf-cli`）中若需锁定序列，设置环境变量 `WOLF_DETERMINISTIC_RNG=1` 即可保持从 `0` 起步。

#### 2. `crates/wolf-game/src/savegame.rs`

修改第 `166` 行，读档时在 `playtime_frames` 基础上叠加实时时间戳扰动（同样受 `WOLF_DETERMINISTIC_RNG` 控制）：

```rust
// crates/wolf-game/src/savegame.rs (替换第 166 行)
let jitter = if std::env::var_os("WOLF_DETERMINISTIC_RNG").is_some() {
    0
} else {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| (d.subsec_nanos() as usize) ^ (d.as_secs() as usize))
};
game.vm.rng.set_cursor((loaded.playtime_frames as usize).wrapping_add(jitter));

```

---

### 二、非恶作剧界面的跟随鼠标手指图标

**目标**：非恶作剧界面使用 Godot 硬件自定义光标渲染零售手指图标；进入恶作剧场景（`sprite 2999` 激活）时继续隐藏硬件光标，交由 `Picture 2999` 接管。

#### `godot/scripts/GameView.gd`

在 `GameView.gd` 中新增手指光标加载函数，并在 `open()` 成功后调用一次：

```gdscript
# godot/scripts/GameView.gd
var _finger_cursor_loaded := false

func _install_default_finger_cursor(root_dir: String) -> void:
	if _finger_cursor_loaded:
		return
	var path := root_dir.path_join("Data/CharaChip/hand3.png")
	if not FileAccess.file_exists(path):
		return
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return
	# hand3.png 是 4x1 帧表，取第 0 帧左上角单帧作为手指光标
	var frame_w := img.get_width() / 4
	var frame_h := img.get_height()
	if frame_w <= 0 or frame_h <= 0:
		return
	var icon := Image.create(frame_w, frame_h, false, Image.FORMAT_RGBA8)
	icon.blit_rect(img, Rect2i(0, 0, frame_w, frame_h), Vector2i.ZERO)
	var tex := ImageTexture.create_from_image(icon)
	# hotspot 设为指尖位置（按原图比例微调，通常在左上指尖附近）
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(6, 2))
	_finger_cursor_loaded = true

```

在 `_ready()` 中 `wolf.open(data_root)` 成功之后调用：

```gdscript
_install_default_finger_cursor(data_root)

```

现有 `_update_mouse_cursor(sprites)`（第 `487-498` 行）无需改动：`sprite 2999` 出现时自动 `MOUSE_MODE_HIDDEN`，消失后自动切回 `MOUSE_MODE_VISIBLE` 并显示上述自定义手指光标。

---

### 三、补全画面内交互要素的点击判定范围

#### 1. 卧室睡姿妹妹（`pose == 5`）放大点击热区

在 `crates/wolf-game/src/game.rs:3402-3411`，目前 `pose == 5` 仅依赖地图格子 `action_key_rect`：

```rust
// crates/wolf-game/src/game.rs (替换 3402-3411 行)
if pose == 5 {
    // 睡姿没有 CE240 立绘槽位，优先使用扩展后的睡姿身体视觉热区，
    // 若当前地图不在标准卧室尺寸则回退到原 action_key_rect。
    if let Some((left, top, width, height)) = self.runtime.action_key_rect(&self.vm, event) {
        let radius = SISTER_HIT_RADIUS;
        // 向下/向右扩展覆盖被褥中的妹妹身体范围（约 120x96 像素）
        let body_w = width.max(120);
        let body_h = height.max(96);
        let inside = (left - radius..left + body_w + radius).contains(&x)
            && (top - radius..top + body_h + radius).contains(&y);
        return inside.then_some(event);
    }
    return None;
}

```

> 建议实机截取一张夜间睡觉卧室画面，核对床铺上妹妹身体像素左上/右下坐标后，将 `body_w` / `body_h`（或固定 `Rect`）对齐到实际显示区域。

#### 2. 补全半夜恶作剧各姿势图标到 `PICTURE_ACTION_CONTROLS`

在 `crates/wolf-game/src/game.rs:148-156` 补充可能用到的姿势/菜单图标槽位，确保全部走 `picture_ink_rect` 非透明包围盒判定：

```rust
const PICTURE_ACTION_CONTROLS: &[(i32, u32, &str)] = &[
    (-7, 35, "Picture/icon06.png"),      // 相册
    (-5, 5, "Picture/icon01.png"),       // 保存
    (-4, 30, "Picture/icon05.png"),      // 数据
    (1108, 21, "Picture/endbutton.png"), // 夜结束
    (1109, 22, "Picture/pose_iconarea.png"),
    (1110, 22, "Picture/pose_icon"),
    (1117, 28, "Picture/pose_icon02.png"),
    // 若 CE230/SampleMapA 子菜单还使用其他姿势按钮槽位（如 1111~1120 的 pose_icon*），按实测槽号追加在此处
];

```

---

### 四、游戏内便利读档 & 每日傍晚饭后自动存档（槽 1）

#### 1. `crates/wolf-game/src/game.rs`：暴露「回标题」、槽 1 自动存档及存单槽状态查询

**（A）添加状态字段与 `CE 258` 晚饭后自动存档钩子**
在 `Game` 结构体增加：

```rust
ce258_was_running: bool,
auto_saved_banner_frames: u32,

```

在 `Game::frame()`（约 `4184` 行 `pending_return_to_title` 处理之后）加入：

```rust
let ce258_running = self.vm.instances().iter().any(|inst| inst.event == 258);
if self.ce258_was_running && !ce258_running && !self.boot_map_active {
    // CE 258 刚正常结束（未回标题/未进 BadEnd），自动保存到槽 1
    let auto_path = self.root.join("Save").join("SaveData01.sav");
    if self.save_to(&auto_path).is_ok() {
        self.auto_saved_banner_frames = 120; // 供前端显示 2 秒提示
    }
}
self.ce258_was_running = ce258_running;
if self.auto_saved_banner_frames > 0 {
    self.auto_saved_banner_frames -= 1;
}

```

同时在 `Game` 上暴露两个公开方法给 `wolf-gdext`：

```rust
pub fn trigger_return_to_title(&mut self) {
    self.pending_return_to_title = true;
}

/// 若当前处于存单界面且点击了非空存档槽，返回 (1-based 槽号, 存档文件路径)
pub fn clicked_non_empty_save_slot(&self) -> Option<(i32, std::path::PathBuf)> {
    if !self.save_grid_active() || self.boot_map_active {
        return None;
    }
    let inst = self.vm.instances().iter().find(|i| i.event == 131)?;
    let page = inst.self_vars.get(611).max(0);
    let per_page = inst.self_vars.get(627).clamp(1, 10);
    let idx = inst.self_vars.get(610).max(0);
    let slot_num = page * per_page + idx + 1; // SaveData01.sav ..
    let path = self.root.join("Save").join(format!("SaveData{slot_num:02}.sav"));
    path.is_file().then_some((slot_num, path))
}

```

#### 2. `crates/wolf-gdext/src/lib.rs`：暴露给 Godot 的桥接方法

```rust
#[func]
fn return_to_title(&mut self) {
    if let Some(game) = self.game.as_mut() {
        game.trigger_return_to_title();
    }
}

#[func]
fn save_grid_active(&self) -> bool {
    self.game.as_ref().is_some_and(|g| g.save_grid_active())
}

#[func]
fn selected_non_empty_save_path(&self) -> GString {
    self.game
        .as_ref()
        .and_then(|g| g.clicked_non_empty_save_slot())
        .map_or_else(GString::new, |(_, p)| GString::from(p.to_string_lossy().as_ref()))
}

#[func]
fn load_save_in_game(&mut self, path: GString) -> bool {
    let Some(game) = self.game.as_mut() else {
        return false;
    };
    let p = Path::new(path.to_string().as_str());
    if game.load_save(p).is_err() {
        return false;
    }
    game.retire_load_ui_chain();
    game.resume_loaded_map().is_ok()
}

```

*(注：若 `retire_load_ui_chain` / `resume_loaded_map` / `save_grid_active` 当前为私有方法，将其可见性改为 `pub` 即可；同时可以在 `frame()` 返回的 `packet` 中加一个 `auto_saved: game.auto_saved_banner_frames > 0` 字段用于前端显示轻量角标。)*

#### 3. `godot/scripts/GameView.gd`：弹出「保存 / 读取」浮层与回标题入口

* **存单界面非空槽点击弹窗**：在 `_unhandled_input`（或 `_input`）捕获左键点击时，如果 `wolf.save_grid_active()` 且 `var p := wolf.selected_non_empty_save_path()` 非空，先拦截本次点击并显示一个 Godot `PopupMenu`（或 `ConfirmationDialog`）：
* **「保存到此槽」**：放行左键点击事件给 `wolf`（执行原版 `CE 131` 覆盖保存）；
* **「读取此存档」**：调用 `wolf.load_save_in_game(p)`，直接无缝切换至该存档；
* **「取消」**：关闭弹窗，不做任何操作。


* **不关闭游戏返回标题**：在 `Esc` 键或顶栏按钮触发一个确认弹窗，点击确认后调用 `wolf.return_to_title()` 即可直接回到标题界面。