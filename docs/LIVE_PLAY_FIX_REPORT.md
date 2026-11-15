# 实机报告 `live_play_issues_and_fixes_report.md` 剩余项修复报告（2026-11-15）

> 输入：`live_play_issues_and_fixes_report.md`（仓库根目录，外部只读产物，11 项断言）。
> 上一轮已完成核实与三条裁定落地（见 `HANDOFF_PROGRESS.md` 2026-11-15 同日条目、
> 提交 `2bd0463`）。本轮收掉报告里剩下的 9 项，并给三条裁定补上回归。
> 本作语汇与说明保持中性技术描述。

---

## 0. 结论摘要

| 编号 | 报告断言 | 核实结论 | 处置 |
| :--- | :--- | :--- | :--- |
| **#1** | 对话右下角闪现巨大头像 | **成立** | 已修：气泡模式全程屏蔽原生 `19500..=19503` |
| **#2** | 对话框过高、头像顶部留空 | **成立** | 已修：气泡高 `136 → 107`、头像底 `563 → 558` |
| **#3** | 格子进度条被打断后残留 | **成立** | 已修：夜袭场景收尾时擦 `500..=503` 并关掉三个闸门变量 |
| **#4** | 恶作剧光标移出身体热区不回落 | **零售原样**（报告误判） | 不改引擎语义，补 4 条回归锁住零售行为 |
| **#5a** | BAD/GOOD 粗细不一致 | **按用户裁定统一为 8** | 已落地（上一轮 `2bd0463`），本轮补集成回归 |
| **#5b** | 睡眠圆形图标无呼吸动效 | **成立** | 已修：同图重绘不再清空 `breath/zoom/pattern` |
| **#6** | 残留中文乱码 | **成立** | 已修（上一轮 `2bd0463`：否决 U+FF61..FF64）；本轮订正文档口径 |
| **#7** | 黑屏转场时顶栏行动力条消失 | **成立** | 已修：改成几何判定（顶栏带 36 px） |
| **#8** | 黑屏转场无渐变 | **成立** | 已修：`150 Move` 的 fade 变成真正的 alpha 插值 |
| **#9** | 侧拉栏收起瞬移 | **零售是补间**（按用户实机裁定） | 已修（上一轮 `2bd0463`），本轮补双向动画回归 |
| **E** | 本地时钟语义 + 基线漂移 | **成立** | 已修：宿主读 `GetLocalTime`，`--clock` 可钉住 |
| **F** | 读档后背景图匹配失败 | **成立** | 已修：路径补 `.mps` 后缀 |

---

## 1. 逐项处置

### 1.1 #1 气泡模式漏出原生头像

* **根因**：`picture_quads()` 只在 `balloon_owns_message()` 为真时屏蔽原生
  `19500..=19503`。而 `balloon_visuals_active()` 是**瞬态**的：气泡淡出到
  `opacity == 0` 的那一帧它就变成 `false`，而原生槽位要到一两帧后才被 CE63 擦掉，
  中间这个空档里 `19502` 就漏了出来（右下角 170 % 的大头像）。
* **修复**：屏蔽条件改成 `balloon_picture_mode_enabled() || balloon_picture_text_is_visible()`
  —— 气泡模式一旦启用就整轮不画原生槽位，与瞬态无关。
* **回归**：`m19_balloon_ui.rs::picture_mode_never_leaks_the_native_face`。

### 1.2 #2 对话框过高

* **根因**：`BALLOON_FACE_FRAME_MIN_HEIGHT = 136`（`9a817e4` 自增）与
  `BALLOON_FACE_BOTTOM_Y = 563.0` 是估的。
* **测量**：零售截图 `ptr_sc/卧室_点击妹妹_首句话.png` 是 1536x907 的 1.5 倍放大图，
  内容起点在物理 y = 43。气泡洗色从物理 y = 732 到 y = 892，即逻辑
  **459.3 .. 566.0**（高 106.7）。框底是脚本自有的（CE270 锚定 580x60 的窗口），
  宿主只能改高度 → `566 - 459.3 = 106.7 ≈ 107`。
  头像 `Picture/face02.png`（180x180 @50 %）对齐后左上角在逻辑 (228, 469)、底边 559。
* **修复**：`BALLOON_FACE_FRAME_MIN_HEIGHT = 107`、`BALLOON_FACE_BOTTOM_Y = 558.0`。
* **回归**：`m19_balloon_ui.rs::the_sister_balloon_matches_the_retail_screenshot`，
  `m17_ui_regressions.rs` 的旧断言（136/563）同步更新。

### 1.3 #3 夜袭格子进度条残留

* **根因**：`CE 279`（実行バー表記）、`CE 281`（右计时）、`CE 282`（左计时）都是
  并行事件，闸门变量是 `2000090/2000091/2000092`。其中 `2000091` 与 `2000092`
  **全作 350 个公共事件里没有任何一条会清零**；`CE 281` 只在自己的计时走完时才擦
  `500..=501`。中途打断夜袭，格子条就留在屏幕上。
* **修复**：新增 `crates/wolf-game/src/raid_cleanup.rs`——夜袭场景
  （`CE 249/256/259`）**结束的那一帧**清掉 `2000090/2000091/2000092/2000154`
  并擦掉 `500..=503` 这段 HUD 带。触发条件是场景的**沿**而不是电平，因为这些
  计时事件本来就活得比场景久。
* **回归**：`m22_raid_cleanup.rs`（5 条）。

### 1.4 #4 恶作剧光标回落（零售原样，报告误判）

* **零售引擎实证**（`work/out/re_all/all/`）：
  * `004874c0_FUN_004874c0.c`：图片不存在时，field ≠ 9 一律返回 `0xffffffff`（-1）。
    所以零售对缺失图的 hover 命中就是 -1，本仓 `Game::hover()` 同款。
  * `00452de0` / `00467a90`：`111` 记下命中的 case id，`401` 跳过不匹配的分支体
    ⇒ 条件全假时任何分支体都不执行，与本仓 `enter_block` 一致。
* **数据链路**：`SampleMapA.mps` Ev18 的链是 `124 hover(1100..1108,1111)` →
  每级 `111 [2, flag==0→case1, flag==1→case2]`，链尾 `121` 把 `var121` 复位为 0；
  结束键 `1108` 的 case2 在 pc79 同样写 `var121 = 0`。
  Ev19 里 `1111` 只有在 `2000106 <= 1` 时才画，而正式夜袭流程（CE227 → CE230）
  一开始就把 `2000106` 设成 4 ⇒ **正式流程里 1111 根本不存在**，链在最后一节断掉，
  `var121` 保留上次的身体图标。
* **零售截图**：`ptr_sc/恶作剧_凝视胸部_穿衣.png` 鼠标停在左侧相册画面（不在任何热区），
  光标仍是**眼睛**（`var121 = 1`）；`ptr_sc/恶作剧_首次系统提示.png` 同一位置、
  尚未悬停过任何身体部位时是普通手掌 `hand3`（`var121 = 0`）。
  ⇒ 零售默认回落是 **hand3（`var121 = 0`）**，且**只有悬停结束键才回落**；
  报告写的「回落 hand1 / `var121 = 2`」与零售不符。
* **处置**：不改引擎语义。补 `m21_cursor_hover.rs`（4 条）把零售行为钉住：
  悬停胸口 → `var121 = 1`；悬停结束键 → `var121 = 0`；移出热区保持（零售同款）；
  缺失图 → -1。

### 1.5 #5a BAD/GOOD 粗细统一为 8（用户裁定）

* 零售截图 `ptr_sc/恶作剧_BAD&GOOD条特写.png` 实测两条外沿同高（12 图像像素 @1.5x
  = **8 逻辑像素**），而 `CE 237` 给的是 6 vs 8。全作 `<SQUARE><FRAME>` 只有这两条
  Draw，所以宿主把 BAD 外框（1998）钉到 GOOD 外框（1994）的盒子：窗口高 8、顶边 56。
  填充条（1992/1996，本就是 215x6）不动。
* 上一轮已落地（`2bd0463`），本轮补集成回归
  `m24_live_play_rulings.rs::the_bad_and_good_frames_have_the_same_weight`
  （另有 `picture.rs` 的单元测试）。

### 1.6 #5b 睡眠图标无呼吸动效

* **根因**：`CE 237` 是并行事件（`run = 2`），每帧都 `150 Show` 重画
  `Picture 2000`（`sleeping_staus.png`），而 `PictureAction::Show` 每次都新建
  `Picture`，把上一帧累积的 `breath.elapsed` 清零；紧跟着的 `290`（呼吸）又从
  phase 0 重新开始 ⇒ 图标永远停在原始大小。
* **修复**：`picture.rs` 的 Draw 分支在**同一张图、同一位置**的重绘时保留
  `breath/zoom/pattern/shake`；换图或换位仍是替换语义。图案动画会把基准格改成
  本次 Draw 要求的格号。
* **回归**：`m19_picture_motion.rs::a_redraw_of_the_same_graphic_in_the_same_place_keeps_the_running_animation`
  与 `::the_sleep_status_event_pulses_its_icon`。

### 1.7 #6 中文乱码（上一轮已修）+ 本轮订正文档口径

* 修法见提交 `2bd0463`：保留 CP932 启发式，但对读法里出现 U+FF61..U+FF64
  （`｡ ｢ ｣ ､`）的串**否决**启发式——那正是 GBK 的 `…`（`A1 AD`）、`？`（`A3 BF`）
  被 CP932 误读成半角标点的指纹。上界必须停在 U+FF64：再宽一个码位会命中
  U+FF65（半角中点），而 `顔画像 [ﾊﾞﾄﾙ･ｽﾃｰﾀｽ用]` 确实含它、且有 4 处 op250 寻址会翻转。
* **本轮订正**：这条启发式决定的 98 个 unique 串里那批日文**不是本作画面上的日文正文**，
  而是 **wolf 引擎自带的数据库列名**（op250 的 label），只承担寻址、不上屏。
  `docs/M3_STRING_DECODE.md` 已按这个口径改写。

### 1.8 #7 黑屏转场时顶栏行动力条消失

* **根因**：`hud_action_points()` 只要看到 `slot -1` 或 `slot 9000` 活着就整条返回
  `None`，把宿主自绘的顶栏条一起吞掉。而零售黑幕是 `cg/blackscreen.jpg`
  （1024x540）画在 `(0, 36)`——**在顶栏下方**，顶栏本来就不该被遮。
* **修复**：改成几何判定 `hud_top_band_covered()`：只有当遮挡物的目标矩形真的
  伸进 `y < 36` 的顶栏带时才隐藏。`slot 9000` 不是死代码（`Map003.mps` 整屏遮挡用），
  按同一条几何规则处理。
* **回归**：`m19_balloon_ui.rs::a_black_screen_below_the_top_bar_keeps_the_gauge`。

### 1.9 #8 黑屏转场无渐变

* **根因**：`PictureAction::Move` 在槽位不存在时用 `Picture::new()` 建槽，
  而新图的 `opacity` 默认 255 ⇒ 脚本的 `150 Move (-1, opacity=255, fade=30)`
  变成 `255 → 255`，第 0 帧直接全黑。
* **修复**：`Picture` 新增 `fade_from` / `fade_start`——fade 是**从命令到达时屏幕上的
  alpha 走到目标 alpha** 的斜坡：Draw 从透明起步（原来的淡入），Move 从当前 alpha
  起步（同一条斜坡既负责淡入也负责淡出）。`alpha()` 改成走这条斜坡而不是把
  `opacity` 乘一个进度。
* **回归**：`m19_picture_motion.rs`（14 条，含
  `::the_black_screen_fades_to_black_and_back_in_thirty_frames_each`、
  `::a_move_without_a_fade_is_still_a_teleport`、
  `::the_move_fade_does_not_stack_on_top_of_the_draw_fade`）。

### 1.10 #9 侧拉栏拉出与收回都有位移动画（用户实机裁定）

* 零售引擎 Ghidra 实证：`0049c7a0_FUN_0049c7a0.c` 证明零售 `150 表示` 作用在
  **已有图像**的槽位上是**位置补间**（时长 = ウェイト時間 = raw arg 2），不是瞬移；
  `1600020` 也不是常量坐标而是 `self[20]`（运行期 -305）。
* 宿主现在按同一语义实现：同图重定位 → 保留旧 alpha、按 `args[0]` 建 Transition；
  空槽仍走淡入。全作只有 **39 条**「同图重定位」Draw（CE234/238/239/283/293）。
* 实测：拉出 x 从 -305 逐帧滑到 0（**20 帧**），收回从 0 滑到 -305（**10 帧**）。
* **回归**：`m24_live_play_rulings.rs::the_status_drawer_slides_out_and_back_instead_of_teleporting`
  逐帧采样两侧的中间位置，任一侧没有中间位置就红。

### 1.11 E 本地时钟

* `wolf-game` 不用 unsafe，所以宿主（`wolf-cli` / `wolf-gdext`）负责调
  `GetLocalTime`，再通过 `install_local_clock` 交给游戏层；`wolf-game` 默认退回 UTC。
* 新增 `Clock::System / Clock::Fixed`，`--clock YYYY-MM-DD[THH:MM:SS]` 可把时钟钉死；
  `m14_visual_regression` 的每个场景都跑在 `PINNED_CLOCK` 上，基线不再随日期漂移。
* **回归**：`m20_clock.rs`（3 条）。

### 1.12 F 读档后背景图匹配失败

* `SysDatabase` 类型 0 把背景按**带后缀**的路径索引（`MapData/SampleMapA.mps`），
  而 `resume_loaded_map()` 写的是 `MapData/SampleMapA`，永远匹配不上。
* 修复：新增 `map_data_path()` 统一补后缀（已有后缀则原样使用）。
* **回归**：`m23_map_path.rs`。

---

## 2. 附带改动

* **`m14` 基线**：`saveui` 的 non-black 从 `576_221` 记到 `576_228`。这个场景长期被跳过
  （`Save/` 里多出玩家的 `SaveData03/04`，存档格多一格），旧数字早就陈旧了。
  **三个像素是真实渲染变化，不是夹具漂移**：把夹具固定成出厂存档后实测，
  `ee808fe` 渲染出 576_225，而从 `1a9fafe`（"fix: close T18 UI and runtime
  regressions"，重写了 `picture.rs`/`atlas.rs`/`game.rs` 并挪了存档格面板的锚点）
  起一律是 576_228。
  现在出厂存档归位，并用 FNV-1a 指纹（`0x752b_4235_063a_4721`）守住夹具，指纹不符就跳过
  而不是报回归。画面结构数字（25 pictures / 27728 quads / 13 text pics / 54 glyphs /
  21 atlas / 9 peak coroutines）一个没动。
* **`.gitignore`**：补 `/nul`（Windows 保留名，删不掉）、`/ptr_sc/`（用户实机截图）、
  `/tools/debug/`、`/tools/.rustc_info.json` 与根目录的录制截图压缩包，避免误提交。

---

## 3. 验证

* `cargo test -q --workspace --no-fail-fast`（`WOLF_DATA_ROOT` 绝对路径）：
  **8 红，0 新增**。8 条全是长期基线：
  `wolf-game --lib` 的 choice×3 / db×2 / textpic×1，
  `m18_t18_regressions::hidden_and_transparent_pictures_do_not_report_hover`，
  `m3_manual_rules::late_night_bedtime_skips_to_next_evening`。
* 本轮新增回归 **32 条**：`m19_balloon_ui` 3、`m19_picture_motion` 14、`m20_clock` 3、
  `m21_cursor_hover` 4、`m22_raid_cleanup` 5、`m23_map_path` 1、`m24_live_play_rulings` 2。
* `WOLF_DATA_ROOT=... ./target/debug/wolf-cli.exe verify` → **PASS 64 / 1 SKIP**（M0 基线）。

---

## 4. 遗留与下一步

* 8 条基线红里，`choice`/`db`/`textpic` 6 条是姊妹作期望值差异（长期记录于
  `HANDOFF_PROGRESS.md`），`m18` 与 `m3_manual_rules` 各 1 条是事件语义差异，
  都不是本轮引入。
* #3 的收尾是宿主补的（零售数据不可改）：若将来能改脚本，正确的做法是在夜袭的
  每个出口补 `150 Erase [16777218, 500, 0, 0, 0, 503]`。
* #4 按零售保持「粘住」，若要做成「移出热区就回落手形」，那是**行为改动**而非
  bug 修复，需要先确认目标形态（回落 hand3 还是 hand1）。
