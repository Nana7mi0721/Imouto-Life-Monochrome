# 《妹！生活 ～単色～》GitHub 仓库（`1a1741cc`）代码审核：随机机制核验与交互/存档增强方案

> **归档说明（2026-11-18）**：本文为`1a1741cc` 的 GitHub 仓库随机机制核验与交互/存档增强方案，内容已被 [`docs/reviews/CODE_REVIEW_4ROUND.md`](../../reviews/CODE_REVIEW_4ROUND.md) 与 [`docs/reviews/LIVE_PLAY_FIX_REPORT.md`](../../reviews/LIVE_PLAY_FIX_REPORT.md) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


**审核目标**：`nana7mi0721/imouto-life` 远程仓库快照（`commit 1a1741ccc90b7fca110932c87d82ec117056d4a1`）
**审核内容**：
1. 游戏内各类事件随机结果产生机制的有效性核验；
2. 非恶作剧界面的跟随鼠标手指图标缺失排查与方案；
3. 画面内交互要素（卧室妹妹、相册、数据、保存、半夜恶作剧各姿势图标）点击判定范围核查；
4. 游戏内便利读档（回标题 / 存单槽弹出保存或读取）与每日傍晚饭后（槽 1）自动存档方案。

---

## 一、核心核验：游戏内事件随机结果产生机制是否有效

### 结论：**底层随机运算与数据表有效，但「新开局」与「反复读档 S/L」存在游标固定导致的伪随机（结果重复）问题**

#### 1. 已验证有效的部分
- **指令路由完整**：`crates/wolf-vm/src/exec.rs:2159, 2245, 2591, 2624` 中，凡 `Opcode 121` 的二元运算符高半字节为 `0x6`（即 WOLF 编辑器的 `min ~ max` 范围随机，全作共 1,101 处调用点），无论是普通变量、间接寻址还是 `CData` 数据库写入，均统一路由至 `rng.range(v1, v2)`。
- **零售随机表与区间映射正确**：`crates/wolf-vm/src/rng.rs:157-238` 的 `WolfRng::from_game` 直接读取 `Game.dat` 末尾 28,942 字节的 `static_randoms` 7-bit 预生成表，每次抽取推进 `cursor`（到末尾取模回绕），并按 `(entry * (span + 1)) >> 7 + low` 映射至 `[low, high]` 闭区间（且自动兼容上下界反写，如 `ev119 pc128`），数学分布与上下界均无误。
- **读档游标迁移存在**：`crates/wolf-game/src/savegame.rs:166` 在读档时会执行 `game.vm.rng.set_cursor(loaded.playtime_frames as usize)`，因此不同游戏时长（`playtime_frames`）的存档会从不同的表偏移开始抽取。

#### 2. 发现的真实隐患（会导致玩家体感「随机失效」）
1. **每次开新游戏 `cursor` 恒从 `0` 开始**（`crates/wolf-game/src/game.rs:1141-1142, 1801-1802`）：
   - `WolfRng::from_game` 固定将 `cursor` 初始化为 `0`，未结合系统时间做初始扰动。
   - **后果**：玩家每次点击「New Game」后，只要前期操作路径相同，所有随机事件都会按 `table[0], table[1], ...` 得出完全相同的固定结果。
2. **同一存档反复读档（S/L）会得出完全相同的随机序列**（`crates/wolf-game/src/savegame.rs:166`）：
   - `savegame.rs:166` 仅使用存档文件内静态记录的 `playtime_frames` 作为游标位置。
   - **后果**：玩家在某次随机判定前存档并反复读取同一个存档时，`playtime_frames` 每次都完全一样，导致 `cursor` 每次都被重置到同一个位置，读档后的随机事件（例如当天突发事件、好感度/判定波动）**永远出同一个结果**，无法通过 S/L 刷出不同分支。

#### 3. 修复建议
- 在 `crates/wolf-game/src/game.rs` 区分**确定性测试模式**与**实机游玩模式**：
  - 确定性回归测试（CLI / `m14` 等）保持 `cursor = 0` 或固定 `playtime_frames` 以保证可复现；
  - 实机游玩模式下，在 `new_game`（开新档）与 `load_into`（读档）时，将当前系统时间戳（如纳秒/毫秒低位）混入 `rng.set_cursor(...)`（或在每帧空闲时做一次微扰），即可彻底解决新开局固定序列与 S/L 结果锁死的问题。

---

## 二、非恶作剧界面的跟随鼠标手指图标

### 1. 现状与缺失原因
- **当前机制**：`godot/scripts/GameView.gd:487-498` 的 `_update_mouse_cursor(sprites)` 仅在检测到 `sprite 2999`（即 `SampleMapA Ev 14` 在半夜恶作剧场景中绘制的自定义光标）存在且 `alpha > 0` 时，才隐藏系统鼠标（`Input.MOUSE_MODE_HIDDEN`）；在其余所有非恶作剧界面（标题、卧室日常、菜单、商店等），前端都切回 `Input.MOUSE_MODE_VISIBLE`，直接显示 **Windows 系统默认箭头**。
- **补充说明**：仓库新增的 `crates/wolf-game/src/cursor_fallback.rs` 仅用于修正恶作剧场景内部鼠标离开热区时将 `var 121` 复位为 `0`（`CharaChip/hand3.png`），不负责日常界面。

### 2. 实现方案（推荐 Godot 硬件自定义光标）
- **做法**：在 `GameView.gd` 初始化时，从游戏素材 `Data/CharaChip/hand3.png`（或 `hand1.png`，与零售一致的手指帧）裁剪出单帧图像并按当前窗口缩放比例生成 `ImageTexture`，调用 `Input.set_custom_mouse_cursor(finger_tex, Input.CURSOR_ARROW, hotspot)` 设为全局默认光标。
- **协同逻辑**：
  - 非恶作剧界面：`Input.mouse_mode = Input.MOUSE_MODE_VISIBLE`，系统硬件光标直接渲染为零售同款手指图标，**零帧延迟且不消耗画面精灵槽位**；
  - 恶作剧界面（`sprite 2999` 激活时）：保持 `Input.MOUSE_MODE_HIDDEN`，由 `SampleMapA Ev 14` 的 `2999` 自由切换手指 / 眼睛 / 对话 / 蘑菇图标。

---

## 三、画面内交互要素的点击判定范围核查与完善

### 1. 当前 `1a1741cc` 已完成部分
- **卧室站姿/坐姿妹妹**（`crates/wolf-game/src/game.rs:3388-3429` `sister_body_action_event_at`）：已针对 `pose 0, 1, 2, 3, 6` 读取 `CE 240` 绘制的 `900..=903` 立绘槽位，使用 `picture_alpha_hit(slot, x, y, SISTER_HIT_RADIUS)` 按非透明像素轮廓判定，**已经摆脱了原版仅限头部 16×16 格子的限制**。
- **主要图标按钮**（`crates/wolf-game/src/game.rs:148-156` `PICTURE_ACTION_CONTROLS` + `picture_ink_rect`）：已对以下槽位按实际非透明墨迹矩形判定：
  - `-7`（`Picture/icon06.png`，相册，对应事件 `35`）
  - `-5`（`Picture/icon01.png`，保存，对应事件 `5`）
  - `-4`（`Picture/icon05.png`，数据，对应事件 `30`）
  - `1108`（`Picture/endbutton.png`，夜结束，对应事件 `21`）
  - `1109 / 1110`（`Picture/pose_iconarea.png` / `Picture/pose_icon`，姿势按钮，对应事件 `22`）
  - `1117`（`Picture/pose_icon02.png`，姿势按钮 2，对应事件 `28`）

### 2. 仍存在的遗漏与建议补全项
1. **卧室睡姿妹妹（`pose == 5`，`Event 12 就寝妹`）**：
   - `game.rs:3402-3411` 中，因为 `pose == 5` 没有 `CE 240` 的 `900..=903` 立绘槽位，代码仍回退到 `self.runtime.action_key_rect(&self.vm, 12)`（即地图事件矩形 + `SISTER_HIT_RADIUS`）。若卧室背景图中妹妹躺在床上的实际视觉范围大于地图事件格子，仍会出现点身体没反应的情况。
   - **建议**：核对睡姿背景图上妹妹身体像素区域，为 `pose == 5` 配置与睡姿视觉轮廓一致的点击矩形。
2. **半夜恶作剧不同姿势的图标**：
   - 目前 `PICTURE_ACTION_CONTROLS` 仅覆盖了 `1109 / 1110 / 1117` 三个姿势相关槽位。需核查 `CE 230`（`深夜1`）及 `SampleMapA` 中全部姿势切换图标/按钮所占用的图片槽位（含子菜单展开后的姿势图标），确保所有同类按钮全部通过 `picture_ink_rect`（非透明墨迹包围盒）判定，而不是落回原版地图事件格。

---

## 四、游戏内便利读档与每日傍晚槽 1 自动存档方案

### 1. 游戏内便利读档（二选一或双支持）
- **原版限制**：游戏内打开 `CE 131`（`セーブ欄実行`）默认仅允许保存（`pc=28` 注释写明仅特定辅助键或从标题进入时才走读档），因此游戏内无法直接读档。
- **方案 A（推荐）：存单界面点击非空槽弹出「保存 / 读取」选项**
  - **实现路径**：当 `save_grid_active()` 为真且玩家点击某个存档槽位时，若目标槽位对应的 `SaveDataXX.sav` 文件已存在（非空槽）：
    1. 宿主拦截本次点击，不立即放行给 `CE 131`；
    2. 在画面/Godot 浮层弹出轻量选项菜单：**「保存到此存档」 / 「读取此存档」 / 「取消」**；
    3. 选「保存」则将原点击放行给 `CE 131` 完成覆盖保存；选「读取」则直接入队 `SaveRequest::Load(path)`，由 `Game::frame` 现有 `load_into` + `retire_load_ui_chain` + `resume_loaded_map` 流程无缝切换过去。
- **方案 B（可并行提供）：不关闭游戏返回标题界面**
  - **实现路径**：`crates/wolf-game/src/game.rs:4184-4186` 已经完整实现了 `pending_return_to_title -> self.reset_to_title()`。只需在 Godot 前端（例如 `Esc` 快捷菜单或顶部/设置面板增加「返回标题」按钮）暴露一个触发 `reset_to_title()` 的入口（带二次确认防止误触），即可随时不重启游戏回到标题界面读档。

### 2. 每日傍晚吃完饭后在「存档槽 1」自动存档
- **触发时机定位**：字节码检索显示，每天傍晚吃饭均由 `CE 256`（`日中メニュー`）、`CE 257`（`帰宅メニュー`）、`CE 259`（`休日メニュー`）统一调用 `CE 258`（`晩ごはん処理`）。
- **实现方案**：
  1. 在 `Game::frame` 中追踪 `CE 258` 实例的生命周期：当 `CE 258` 正常执行结束并从 `vm.instances()` 退栈，且**未触发** `pending_return_to_title`（即未进入 `pc=1718` BadEnd），画面回到日常卧室自由行动状态时，自动执行 `self.save_to(&save_dir.join("SaveData01.sav"))`；
  2. 同步刷新系统存档记录的最近存档信息（若需要），并在 Godot 顶栏或角落显示 2 秒轻量提示（如 `「已自动存档至槽位 1」`）；
  3. **注意事项**：自动存档会固定覆盖 `SaveData01.sav`（槽 1），建议在存单界面槽 1 旁或提示中标明「自动存档槽（每日晚饭后覆盖）」，避免玩家将手动关键存档误存在槽 1。
