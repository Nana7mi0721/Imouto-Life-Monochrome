# 《妹！生活 ～単色～》全量静态代码审查与优化建议报告（基线 + `1c76dcc` 修复包）

> **归档说明（2026-11-18）**：本文为Gemini 全量静态代码审查 `1c76dcc` 的原始报告，内容已被 [`docs/GEMINI_REVIEW_1c76dcc_FIX_REPORT.md`](../../GEMINI_REVIEW_1c76dcc_FIX_REPORT.md) 与 [`docs/reviews/CODE_REVIEW_4ROUND.md`](../../reviews/CODE_REVIEW_4ROUND.md) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


- **审查范围**：`HEAD 141c524` 既有未修改源码 + `ImoutoLife_fix_bundle_1c76dcc_final.zip`（代码 `b2b6998` / 文档 `1c76dcc` 的 22 个改动文件）合并快照
- **审查方式**：全量静态代码审查（未构建、未运行游戏、未修改源码）
- **已知边界**：`1c76dcc` 交付包为相对 `1a9fafe` 的增量快照，因此 `crates/wolf-vm/src/exec.rs` 与 `crates/wolf-game/src/picture.rs` 等未在 22 文件清单内的文件以基线版本参与全量核对，涉及 `1a9fafe` 是否已同步改动的条目均单独标注“待核对 `1a9fafe`”。

---

## 1. 总评：**Approve with changes**（高优核心问题已基本收口，新发现 1 项气球人名牌缓存错位缺陷）

本批 `b2b6998 / 1c76dcc` 修复包高质量地闭环了此前第一、二轮审查中的多项核心问题（`CE 223` 滚轮吞噬、`expand_balloon_frame` 渲染期状态污染、`sync_save_grid_cursor` 同步写穿、`GameView.gd` 混合批次引用释放与 `161` 冻结帧刷新/复用）以及全部实机截图反馈的 UI 缺陷。

但在对**合并后的全量代码**进行交叉审查时，新发现 **1 项由 `text_cache` 与气球动态扩高交互引起的 P1/P2 级人名牌错位缺陷**，同时整理了**行动力数值定长/右对齐优化方案**及未在本次增量包内的遗留核对项。

---

## 2. 本轮全量审查新发现与遗留缺陷列表

### [P1-新] `TextQuadKey` 未计入 `balloon_frame_growth()`，导致多行气泡流式换行时人名牌文字（`36014`）命中旧缓存并与上移的灰底框错位

- **文件与行号**：
  - `crates/wolf-game/src/game.rs:2308-2315, 2396-2405`
  - 交互路径：`crates/wolf-game/src/game.rs:1673-1683`（`picture_quads`）
- **触发的具体代码路径**：
  1. 当 `CE 270` 流式输出一条 2~3 行对话时，第 1 帧正文 `36013` 只有前几个字（1 行高度，`balloon_frame_growth() == 0.0`）。
  2. `text_quads()` 为人名牌文字 `36014`（例如 `"妹妹"`）计算缓存键 `TextQuadKey`（`game.rs:2308-2315`）：
     ```rust
     let key = TextQuadKey {
         fingerprint: crate::textpic::fingerprint(&picture.text, &ctx),
         x_bits: x.to_bits(),
         y_bits: y.to_bits(),
         anchor: picture.anchor,
         alpha_bits: alpha.to_bits(),
         font_gen,
     };
     ```
     并将 `balloon_lift = 0.0` 的结果写入 `self.text_cache`。
  3. 几帧后，随着 `36013` 字符流式追加并自动换行至 2~3 行，`balloon_frame_growth()` 变为正值（如 `20.0`）：
     - `picture_quads()`（`game.rs:1678`）会实时将人名牌底框精灵 `36008..=36012` 向上平移 `-growth`；
     - 但 `text_quads()` 处理 `36014` 时，由于 `"妹妹"` 文本内容、`x`、`y`、`anchor`、`alpha`、`font_gen` 均未变化，`TextQuadKey` **发生缓存命中**，直接返回 `balloon_lift = 0.0` 的旧图元！
- **玩家可见或系统级影响**：
  - 在多行对话打字机换行瞬间（或从多行切换为同一说话人的单行对话时），人名牌灰底框 `36008..=36012` 会上下移动，而 `"妹妹"` 文字却停留在旧 Y 坐标，导致人名掉进正文气泡内部或悬空在框外。
- **最小修复建议**：
  - 在 `crates/wolf-game/src/game.rs:2288-2315` 计算 `TextQuadKey` 之前，先将 `balloon_lift`（针对 `BALLOON_BODY_TEXT_PICTURE` 与 `BALLOON_NAME_TEXT_PICTURE`）计入 `y`（即 `y -= balloon_lift` 后再写入 `y_bits`），或直接在 `TextQuadKey` 中增加 `balloon_lift_bits: u32`。
- **证据等级**：`Confirmed`

---

### [P1-待核对 `1a9fafe`] `exec.rs` 中 `Opcode 121` 的 `self_range` 全局短路是否已移除

- **文件与行号**：`crates/wolf-vm/src/exec.rs:2510, 2565-2569`（基线 `141c524` 位置）
- **说明**：
  - `1c76dcc` 的 `game.rs:2288` 已彻底移除了 `ui_scale_for` 坐标除以 10 的补偿逻辑，且 `game.rs:5078-5079` 修复了 `picture_state` 的 `290` 位移返回。
  - 由于 `exec.rs` 不在 `1c76dcc` 的 22 个增量文件中，若前置提交 `1a9fafe` 已同步移除 `exec.rs` 中“所有 `SelfVar` 批量 `121` 强制 `batch_count = 0`”的短路规则，则该问题已完全闭环；若 `1a9fafe` 尚未移除，则 `CE 64` 万能窗口（`pc=671` `self53..=55` RGB 色调重置）等非坐标批量 `SelfVar` 赋值仍会漏写后续槽位。
- **证据等级**：`Confirmed`（基线存在，待对照 `1a9fafe` 确认）

---

### [P2-待核对 `1a9fafe`] `picture.rs` 瞬时 `Move` 取消 `Erase` 渐隐时未清空残留 `transition`

- **文件与行号**：`crates/wolf-game/src/picture.rs:1326, 1954-1968`（基线 `141c524` 位置）
- **说明**：
  - 同上，`picture.rs` 未在 `1c76dcc` 增量包中。基线代码在瞬时 `Move`（`duration == 0`）取消 `picture.erase_after_slide = false` 时未同步清空 `picture.transition = None`，会导致图片在原 `Erase` 倒计时结束时透明度被覆写为 `0`。若 `1a9fafe` 未修此行，建议补充 `picture.transition = None;` 并强化 `move_cancels_an_erase_fade` 测试断言 `opacity == 255`。
- **证据等级**：`Confirmed`（基线存在，待对照 `1a9fafe` 确认）

---

### [P3-优化项] 顶栏行动力数值未采用定长/右对齐预留，三位数时右边界贴近 `精力` 槽位

- **文件与行号**：`crates/wolf-game/src/game.rs:186-188, 2408-2425`
- **现状分析**：
  - 当前常量为 `HUD_ACTION_LABEL_X = 560.0`、`HUD_ACTION_BAR = [608.0, 18.0, 100.0, 12.0]`、`HUD_ACTION_VALUE_X = 716.0`，而右侧 `精力` 文本位于 `x = 760.0`。
  - 两位数行动力（如 `70/75`，5 个半角字符 ≈ `35 px`）落在 `716..751`，尚有 `9 px` 间隙；但若后续数值达到三位数（如 `100/120`，7 个半角字符 ≈ `49 px`），则右端会延伸至 `765`，与 `x = 760` 的 `精力` 发生贴靠或重叠。
- **优化建议（二选一）**：
  1. **左对齐预留固定全长（改动最小）**：按三位数最宽 `100/120`（`49 px`）预留定长槽位，整体左移约 `15 px`：
     - `HUD_ACTION_LABEL_X = 545.0`（`行动力` 占 `545..587`）
     - `HUD_ACTION_BAR = [593.0, 18.0, 100.0, 12.0]`（占 `593..693`）
     - `HUD_ACTION_VALUE_X = 701.0`（即使 `100/120` 也只占到 `750`，稳留 `10 px` 间隙）
  2. **右对齐定锚（视觉最稳，推荐）**：保持条体在 `[593.0, 18.0, 100.0, 12.0]`，在 `build_text_picture` 中将 `value` 的 `layout_with` 锚点设为右对齐（`anchor = 3`，`x = 750.0`）。无论显示 `8/40`、`70/75` 还是 `100/120`，右边界始终锁死在 `750.0`，位数变化时不会抖动也不会碰撞 `精力`。

---

### [P3-既有未改代码] VM 调度与输入边界项（来自基线 `exec.rs`）

1. **`Opcode 125`（`auto_keys`）单协程同帧多次 `123` 消费**：`exec.rs:2777-2786` 在协程首次执行 `123` 时即标为已投递，若同一协程同帧分两次 `123` 查不同键位，第二次会读到 `0`。
2. **`Vm::spawn_child()` 未继承 `is_parallel`**：`exec.rs:1606` 由并行背景协程通过 `210/300` 派生的子协程默认 `is_parallel = false`，子协程运行期间会短暂影响 `Sys110`（`foreground_event`）判定。

---

## 3. `1c76dcc` 修复包已确认闭环清单

经静态核对，以下此前审查缺陷与实机 UI 问题在 `1c76dcc` 中已完整修复且实现规范：

1. **P1 级逻辑修复**：
   - **新游戏 `v[1] == 1` 滚轮失效**：`ce223_window_active()`（`game.rs:3299-3309`）仅在 `Picture(100_000)` 实际可见时才让 `CE 223` 接管滚轮，并已新增单元测试覆盖。
   - **气球框渲染期原地突变**：`expand_balloon_frame()` 已替换为只读计算的 `balloon_frame_render_rect()`（`game.rs:2197-2221`），不再修改 `Screen` 中的 `Picture 36000`。
2. **P2 级与跨层状态同步**：
   - `sync_save_grid_cursor()`（`game.rs:3373`）已改用 `self.vm.set_instance_self_var(id, 610, slot)` 同步写穿 `common_self`。
   - `GameView.gd` 快路径（`560-563`）已清空 `_batch_pool` 节点残留引用；`_update_frozen_frame()`（`933, 949-952`）已允许连续 `161` 刷新截屏并复用尺寸相同的 `ImageTexture`。
3. **实机截图 UI & 性能项**：
   - 选项 `(0,0)` 锚点回退居中（`choice.rs:244`）、选项控制码剥离（`game.rs:4407`）、等待者消失/切图时回收残留 `choices`（`game.rs:1599, 3690`）、`101+102` 共存时点空白仅推进对话（`game.rs:3177`）。
   - 末句滞留修复（`Sys28` 推进 + `SysStr25` 清空：`game.rs:3528, 3794`）、气球期间屏蔽原生 `19500..=19503`（`game.rs:1650, 1706, 2124`）、`36002` 头像底边钳位至 `576`（`game.rs:1689`）、空人名牌整组隐藏与 `7.0 px` 垂直居中补偿（`game.rs:155, 1708, 2160, 2401`）。
   - 侧栏 `0.2` 停靠透明度、稳定 `hover` 与 8 帧防抖自动缩回（`game.rs:288, 2806, 2887-2934`）。
   - 行动力条改读 `CData 0:12:8/9`、校验 `split_action_readout` 防止黑屏误显，并对齐顶栏居中暗灰槽样式（`game.rs:1961-1974`、`GameView.gd:81-101`）。
   - `audio_cache` 64 条上限淘汰、`WolfText.gd` 256 条 `TextParagraph` 缓存、`key_config_revision()` 指纹缓存、读档 RNG 游标按 `playtime_frames` 派生（`savegame.rs:166`、`rng.rs:175`）。

---

## 4. 建议新增的回归测试

1. **`balloon_nameplate_text_moves_up_when_body_wraps_during_streaming`**（针对 **[P1-新]**）：
   - 先在 1 行 `36013` 状态下调用 `game.text_quads()` 使 `36014`（`"妹妹"`）写入 `text_cache`；随后仅将 `36013` 扩展为 3 行文本并再次调用 `game.text_quads()` 与 `game.picture_quads()`，断言 `36014` 的 Y 坐标随 `36008..=36012` 同步上移 `balloon_frame_growth()`，不会命中旧缓存留在原地。
2. **`hud_action_points_three_digit_value_clears_stamina_column`**（针对 **[P3-优化项]**）：
   - 构造 `slot 230` 文本为 `\f[14]行动力100/120`，调用 `game.text_quads()` 断言所有字符图元的右边界（`rect[0] + rect[2]`）严格小于 `760.0`（`精力` 起始 X 坐标）。
