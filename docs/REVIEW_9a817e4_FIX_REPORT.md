# `code_review_9a817e4.md` 核实与修复报告（2026-11-15）

> 评审原文：`code_review_9a817e4.md`（仓库根目录，未跟踪，外部只读审查产物）。
> 本报告记录**逐条核实结论**、**处置方式**、**改动文件**与**验证数字**。
> 本作语汇与说明保持中性技术描述。

> **2026-11-18 更新**：`F-11`（`\img` 纯图片条/图文混排、
> anchor/scale/alpha）已在本轮重新落地，并有 `textpic` 单测与 Godot smoke
> 覆盖。本文件下方“当前没有”的逐条状态是 2026-11-15 的回退快照，不再是
> 当前源码状态；以 `00_executive_summary.md` §2.2/§2.5 与
> `docs/HANDOFF_M0.md` §11.1 为准。

> **状态说明（2026-11-15 晚）**：本报告对应的实现提交 `f52db44` 已按用户要求在 `b23a1e1`
> 被整体回退，因此下表「已修」一栏里**除下列两项外均未落地**：
> * 「读档后 `current_map_path` 缺 `.mps` 后缀」——已在 live-play 轮以 `map_data_path()`
>   重新落地（见 `docs/LIVE_PLAY_FIX_REPORT.md` 的 F 项与 `crates/wolf-game/tests/m23_map_path.rs`）。
> * 「`Sys77..Sys82` 逐帧写 UTC」——已以另一实现重新落地：宿主读 Win32 `GetLocalTime`
>   并通过 `install_local_clock` 注入，`wolf-cli --clock` 可钉住（见 live-play 轮的 E 项）。
>
> 其余各项**当前代码里没有**，请勿把本报告当作它们的现状说明。逐条说明：
> * **Opcode 122 掩码**——`crates/wolf-vm/src/exec.rs` 仍用 `mode & 0xFF00`，
>   分支仍是 `0x0200`；`f52db44` 改成的 `0xFFF0` / `0x0010` 没有留下。
>   `docs/OPCODE_122.md` 已按当前代码订正，并在开头记了这个仍开放的差异。
> * **`\img` 内联贴图**——**内联贴图支持一直存在**（分词在
>   `crates/wolf-format/src/messagetext.rs`，文字 pass 早就跳过图片，见
>   `crates/wolf-game/src/message.rs` 的 `inline_images_are_omitted_from_the_text_pass`）。
>   被回退的是 `f52db44` 新增的那部分：
>   纯图片走 sprite pass、文字与图片分层、锚点/缩放/alpha 处理
>   （`is_inline_image_only` 全仓 0 命中，`crates/wolf-game/src/atlas.rs` 仍是旧写法）。
>   评审指控的旧 bug（整条吞文字 / 忽略 anchor·scale / 不过滤 alpha）仍然成立。
> * **动作键绕过范围**——`crates/wolf-game/src/game.rs` 仍是
>   `matches!(event, 5 | 21 | 22 | 28 | 30 | 35)`，没有收窄。
> * **`150 Move` 活跃槽位遍历**——`crates/wolf-game/src/picture.rs` 仍按 `lo..=hi`
>   逐整数遍历，没有改成活跃槽位区间查询。
> * **Godot 回归脚本**——`godot/tests/verify_p0_fixes.gd` 与
>   `godot/tests/verify_ui_and_interaction_fixes.gd` 两个文件都还在，只是
>   `f52db44` 新增的回归内容被回退了。
>
> 本报告的**核实结论**仍然有效，尤其是「`武器スキルセット` / `防具スキルセット` 在本作不存在」
> 这一条误报判定。

---

## 0. 结论摘要

> 下表的「处置」列写的是 `f52db44` 当时的做法。**该提交已被整体回退**，
> 逐条现状见本文开头的「状态说明」横幅；标了「已回退」的行在当前代码里并未落地。

| 评审条目 | 核实结论 | 处置 |
|---|---|---|
| [P0] `Opcode 122` 掩码 `0xFF00` 破坏 CE268/CE270 首行截取 | **成立** | 已修（掩码回 `0xFFF0`，分支回 `0x0010`）——**已回退** |
| [P2] `\img` 内联贴图：整条吞文字 / 忽略 anchor·scale / 不过滤 alpha | **成立（写法层面）** | 已修（贴图/文字分层 + 锚点缩放 + alpha 过滤）——**已回退** |
| [P2] 读档后 `current_map_path` 缺 `.mps` 后缀 | **成立** | 已修——已由 live-play 轮以 `map_data_path()` 重新落地 |
| [P1] `Sys77..Sys82` 逐帧写 UTC，且破坏运行确定性 | **成立** | 已修（本地时间 + 可注入时钟）——已由 live-play 轮以 `install_local_clock()` 重新落地 |
| [P2] 动作键绕过范围扩到 `5\|21\|22\|28\|30\|35` | **成立** | 已修（收窄 + 只忽略交互模式变量）——**已回退** |
| [P2] `PictureAction::Move` 按 `lo..=hi` 逐整数遍历 | **成立** | 已修（改为活跃槽位区间查询）——**已回退** |
| [P3] Godot 回归脚本断言过空 + 硬编码绝对路径 | **路径问题成立；两处坐标前提被证伪** | 已修（路径链 + 可证伪断言 + 接入 smoke）——**已回退** |
| （评审原文之外的）`武器スキルセット` / `防具スキルセット` | **误报：本作不存在** | **不实现**，仅在本文留证 |

评审结论「Block」的前提（Opcode 122 回归）在 `f52db44` 里已消除，**但该修复随
`b23a1e1` 一起回退，当前代码里这个前提重新成立**；其余 5 条缺陷的处理方式见上表。

---

## 1. 核实方法

1. **字节码全量统计**：`work/out/_ce_full.json`（350 个公共事件）与
   `work/out/map_full.json`（8 张注册地图、102 个页面、33,970 条脚本字符串）。
2. **Opcode 122 操作码直方图**：全作 448 条 `122` 指令，
   `mode` 分布为 `0x0000×220 / 0x0001×29 / 0x0002×9 / 0x0011×1 / 0x0012×1 /
   0x0100×107 / 0x0101×5 / 0x0301×10 / 0x0401×10 / 0x0501×1 / 0x0800×6 /
   0x0900×4 / 0x0A00×9 / 0x0B00×36`；`0x0200` 全作 **0 处**。
   按手册把掩码取 `0xFFF0` 时，448 条全部落在手册列出的操作上。
3. **变量语义**：以 `work/out/变量对照表.csv` 与 `SysDatabase` 类型 14 为准
   （`v69` 射精、`v100` 深夜1、`v101` 深夜1ポーズ、`v125` 例外処理、
   `v176` スタッツ表示中、`v238` アルバム表示中、`v247` アルバム回想実行中、
   `v260` 为未启用项）。
4. **地图页条件实测**：`SampleMapA` 的 `ev5` 保存（`v176==0 && v238==0`）、
   `ev21` 終了仮（`v100==1 && v125!=1`）、`ev22` ポーズ変更1（`v100>=1 && v69==0`）、
   `ev28` ポーズ変更2（`v100>=1 && v101<=1 && v69==0 && v18<=5`）、
   `ev30` スタッツ（`v100==0 && v238==0`）、
   `ev35` アルバム起動判定（page0 = Parallel，`v100==0 && v176==0`；
   page1 = ActionKey，`v247==1`，程序仅一条空指令）。
5. **零售存档采样**：`work/Data/Save/*.sav` 共 8 个，全部处于白天 `SampleMapA`，
   `v18/v69/v100/v101/v120/v125/v176/v238/v247/v260` 均为 0。

---

## 2. 逐条处置

> **注意**：本节按 `f52db44` 当时的做法书写。该提交已被 `b23a1e1` 整体回退，
> 因此下面的「修复」「新增回归」「单测」大多**不在当前代码里**；每节末尾标注了
> 当前现状。只有 2.3（`.mps` 后缀）与 2.4（本地时钟）已在 live-play 轮以另一实现
> 重新落地。

### 2.1 [P0] `Opcode 122` 掩码回归（`crates/wolf-vm/src/exec.rs`）

* **核实**：CE268 `pc=14` 的 `122 [1600010, 17, 1600005]` 与 CE270 `pc=2000` 的
  `122 [1600096, 18, 1600095]` 是全作仅有的两条首行截取指令；
  手册中「上1行切り取り」的操作码是 `0x0010`，而评审指出的 `0x0200` 全作 0 处。
  旧掩码 `mode & 0xFF00` 会把 17/18 折叠成普通赋值 `0x0000`，首行既不切走也不消费。
* **修复**：`operation = mode & 0xFFF0`；分支 `0x0200 =>` 改回 `0x0010 =>`；
  删除评审指出的错误注释（「代入先を変数で指定」不是模式位，间接目标由目标操作数编码，
  由 `resolve_string_target` 解析）；把被改成 `0x0201` 的单测还原为 `0x0011`。
* **新增回归**：`op122_first_line_cut_moves_the_head_out_of_a_numbered_source`
  （镜像 CE270 `pc2000` 的跨事件 bank 形态，断言整行搬运 + 源行被消费）。
* **文档**：`docs/OPCODE_122.md` 末尾追加回归说明，正文未动。
* **当前现状（2026-11-15）**：**已回退**。`crates/wolf-vm/src/exec.rs` 仍是
  `mode & 0xFF00` 与分支 `0x0200`，`op122_first_line_cut_moves_the_head_out_of_a_numbered_source`
  不存在；`docs/OPCODE_122.md` 已按当前代码订正，并在开头记了这条仍开放的差异。

### 2.2 [P2] `\img` 内联贴图分层（`crates/wolf-game/src/{textpic,atlas,game,message}.rs`）

* **核实**：全作 771 条 `\img` 字符串**全部为纯图片**，图文混排 **0 条**；
  因此「混排整条被吞」在本作数据下不会发生，但「整条跳过 `text_quads()`」的写法
  本身不安全，评审给出的最小修复仍照做（防御性修复，不改变现有像素）。
* **修复**：
  - `textpic::has_inline_image()` / `textpic::is_inline_image_only()`：
    只有纯图片（含空行、颜色码）才算「图片条」；出现文字/变量/图标即算图文混排。
  - `game.rs`：`text_quads()` 的跳过条件由 `text.contains(r"\img")` 改为
    `textpic::is_inline_image_only(&picture.text)` —— 混排图保留文字，不再吞词。
  - `atlas.rs`：贴图条跳过 `alpha <= 0`；按 `picture.anchor`（复用
    `textpic::anchor_origin`）与 `scale`/`scale_y` 定位；按行分组测量块尺寸，
    多行图片条逐行排布。
  - `message.rs`：删除挂在 `push_plain` 上的孤立注释。
* **单测**：原 `inline_box_images_survive_as_box_glyphs_in_text_picture` 已失效，
  重写为 `an_image_only_text_picture_produces_no_glyphs`，
  并新增 `a_picture_that_mixes_text_and_images_keeps_its_words`。
* **当前现状（2026-11-15）**：**已回退**。`is_inline_image_only` 全仓 0 命中，
  `crates/wolf-game/src/atlas.rs:780` 仍是 `picture.text.contains(r"\img")`，
  `crates/wolf-game/src/game.rs` 的 `text_quads()` 跳过条件也仍是旧写法；
  上面两个单测都不存在，`inline_box_images_survive_as_box_glyphs_in_text_picture`
  仍是原名（它属于长期基线红灯之一）。

### 2.3 [P2] 读档后 `.mps` 后缀（`crates/wolf-game/src/game.rs`）

* **核实**：`SysDatabase` 类型 0 列 0 存的是**带后缀**的相对路径
  （字节核对为 `MapData/SampleMapA.mps`），`boot()`/`install_map()` 也都带后缀，
  只有 `resume_loaded_map()` 丢了它，导致 `map_scenery_by_path()` 精确匹配落空。
* **修复**：`self.current_map_path = Some(format!("MapData/{name}.mps"));`
* **新增回归**：`crates/wolf-game/tests/m4_load_resume.rs::the_resumed_map_keeps_its_mps_path_and_its_scenery`。
* **当前现状（2026-11-15）**：**已由 live-play 轮以另一实现落地**。
  `crates/wolf-game/src/game.rs` 新增 `map_data_path()`，
  `resume_loaded_map()` 与 `boot()` 都改用它（`boot()` 原来还有一次双前缀 bug，
  一并修掉）；回归在 `crates/wolf-game/tests/m23_map_path.rs`。

### 2.4 [P1] `Sys77..Sys82` 本地时间与可注入时钟（`crates/wolf-game/src/game.rs`）

* **核实**：`current_datetime()` 直接对 `SystemTime::now()` 取模，产出 UTC；
  零售引擎用的是 `GetLocalTime()`，东亚时区 00:00~08:00 会整体偏一天/一小时。
  每帧读墙钟也会破坏回放与离线 parity 的确定性。
* **修复**：新增 `pub enum Clock { System, Fixed(LocalDateTime) }` 与
  `pub struct LocalDateTime`（字段全部 pub），`Game::clock` 默认 `Clock::System`；
  Windows 走 `GetLocalTime` 的 `extern "system"` FFI，非 Windows 回退 UTC；
  `frame()` 改为读 `self.clock.now()`。`wolf-game` 的 `#![forbid(unsafe_code)]`
  放宽为 `#![deny(unsafe_code)]`，仅该 FFI 函数点开 `#[allow(unsafe_code)]`。
* **单测**：`a_pinned_clock_reports_exactly_the_pinned_time`、
  `the_system_clock_reports_a_plausible_civil_time`、
  `the_frame_publishes_the_clock_into_sys77_to_sys82`。
* **当前现状（2026-11-15）**：**已由 live-play 轮以另一实现落地**。
  实现路线不同：`wolf-game` 保持 `#![forbid(unsafe_code)]`，本地时钟由**宿主**
  （`crates/wolf-cli/src/localclock.rs` 与 `crates/wolf-gdext/src/localclock.rs`）
  调 Win32 `GetLocalTime` 后经 `install_local_clock()` 注入；
  `wolf-cli --clock YYYY-MM-DD[THH:MM:SS]` 可钉住；回归在
  `crates/wolf-game/tests/m20_clock.rs`。

### 2.5 [P2] 动作键绕过范围（`crates/wolf-game/src/{game,map_runtime}.rs`）

* **核实**：旧名单 `5|21|22|28|30|35` 无条件忽略**全部**页条件，
  于是剧本明确禁止的阶段（`v176==1` 统计中、`v238==1` 相册中、
  `v69==1` 禁止阶段、`v125==1` 例外处理中）仍能强行触发保存/姿势/数据/相册。
* **修复**：
  - 名单收紧为 `5|21|22|28`。
  - `action_key_event_ignoring_conditions` 改名为
    `action_key_event_ignoring_interaction_mode`，**只跳过交互模式变量**
    （`INTERACTION_MODE_MAGIC = 2_000_100`，即 `深夜1`），其余条件逐条照旧；
    新增内部 `conditions_met_except(conditions, self_vars, vars, skip)`，
    普通 `conditions_met` 委托给它（`skip = None`）。
  - 理由：`v100` 是姿势子菜单（CE227）自己改写的全局量——菜单开着时它被置 0，
    于是它所属的页面从选择器里消失，但图标还画着，玩家仍要点它收尾；
    这是唯一一条「可见图标比页面活得久」的条件。
* **单测**：`the_bridge_ignores_only_the_interaction_mode_variable`、
  `the_bridge_still_honours_the_other_page_gates`、
  `the_strict_path_still_refuses_a_page_the_interaction_mode_hides`；
  端到端回归 `crates/wolf-game/tests/m3_night_interaction_e2e.rs::the_pose_icon_bridge_keeps_the_scripts_own_stage_gate`
  （`v69=1` 时姿势事件不得启动，`v69=0` 时必须启动）。
* **相册为什么不需要绕过**：`ev35` 的真正相册逻辑在**并行页**（page0）里——
  `op 124` 读 `picture_state(-7, 8)`（= `hover(-7)`）、`op 123` 轮询鼠标左键、
  命中后 `op 210` 调用 `CE303`（アルバム画面呼び出し，905 条指令）。
  图片桥指向的是 page1（ActionKey，条件 `v247==1`，程序为空），
  且 `ev35` 的并行页运行期间该事件已有实例，`action_key_event` 本来就会返回 `None`。
  因此把 35 移出绕过名单**不影响相册开启**；数据（30）同理（它的页条件就是
  `v100==0`，属于白天地图）。
* **当前现状（2026-11-15）**：**已回退**。`crates/wolf-game/src/game.rs:3165` 仍是
  `matches!(event, 5 | 21 | 22 | 28 | 30 | 35)`，没有收窄；
  `action_key_event_ignoring_interaction_mode` 与 `conditions_met_except` 都不存在。

### 2.6 [P2] `PictureAction::Move` 无界遍历（`crates/wolf-game/src/picture.rs`）

* **核实**：`for n in lo..=hi` 会对区间内每个整数做一次哈希查询；
  `span` 未初始化或跨度极大时，单条指令可能触发上百万次查询。
* **修复**：新增 `Screen::move_targets()`，用 `self.pictures.range(lo..=hi)`
  枚举活跃槽位，并补入 `cmd.number`（必在区间内，行为与旧实现等价，仍按升序）。
* **单测**：`a_move_over_a_span_reaches_the_slots_the_per_number_walk_reached`
  （与旧逐整数参照实现逐例比对）、`a_move_over_a_wide_span_reaches_only_the_live_slots`
  （`span = i32::MAX` 护栏 + 耗时上界）、`a_move_stays_inside_the_two_ends_of_its_span`。
* **当前现状（2026-11-15）**：**已回退**。`crates/wolf-game/src/picture.rs:1421` 仍是
  `for n in lo..=hi` 逐整数遍历，`Screen::move_targets()` 不存在，上面三条单测也不存在。

### 2.7 [P3] Godot 回归脚本（`godot/tests/*.gd`、`tools/smoke-godot.sh`）

* **路径部分（成立）**：两份脚本硬编码 `E:/Study/github program/Imouto Life/work/Data`，
  且未接入 smoke。
* **坐标前提部分（被证伪）**：
  - `Picture 2999`（鼠标哨兵）由 **Map Event 14** 创建，其页条件是 `v120==1`；
    零售 8 个存档全在白天（`v120==0`），该图白天根本不绘制，
    所以「传入 (450,300) 后断言 2999 存在」在零售数据上不可断言。
  - `(935, 505)` 命中的 `ev21` 页条件是 `v100==1`（夜间命令层），
    零售存档同样在白天，白天该点不画结束按钮。
* **修复**：数据根解析链 `--data-root=` → `WOLF_DATA_ROOT` →
  `res://../work/Data`；目录不存在 → 打印 skip 并 `exit 0`；
  目录在但打不开 → `push_error` + `exit 1`（绝不「没加载却 PASS」）。
  断言改为**状态推导式两分支硬断言**：白天可断言存档图标 `-5` → 事件 5、
  数据图标 `-4` → 事件 30（点击点由 sprite 实际矩形反推，每次点击前重新
  `load_save`，避免上一次点击的 `last_action_event` 粘连）；夜间分支断言
  `(935,505)` 不产生幽灵事件 21。两份脚本已接入 `tools/smoke-godot.sh` 末尾。
* **当前现状（2026-11-15）**：**已回退**。两个脚本文件都还在，但
  `godot/tests/verify_p0_fixes.gd:6` 与 `godot/tests/verify_ui_and_interaction_fixes.gd:6`
  仍硬编码 `E:/Study/github program/Imouto Life/work/Data`，
  `tools/smoke-godot.sh` 也没有调用它们（脚本里的断言还是旧版）。

---

## 3. 误报留证

### 3.1 `武器スキルセット` / `防具スキルセット`

* 全作 **33,970** 条脚本字符串（350 个公共事件 + 8 张地图的全部指令串）
  中，`スキルセット` **0 命中**，`武器スキルセット` / `防具スキルセット` 同样 0 命中。
* 库存公共事件里确有 `武器増加処理`（CE1）、`防具増加処理`（CE2）、
  `装備コードを取得する`（CE21）等字样，那是 WOLF 通用库的**标准模板**，
  本作既没有武器/防具的技能集合，也没有对应的技能系统事件。
* 结论：**本作不存在对应内容，不实现、不改动任何代码**。

### 3.2 P3 的两处坐标前提

见 §2.7：2999 与 `(935,505)` 在零售存档下都不绘制，
原断言等于「断言一个不会出现的东西」，已改为按当前状态分支的可证伪断言。

---

## 4. 验证数字（2026-11-15）

> 下面是 `f52db44` 那一轮的实测记录，随该提交一起回退，**不再代表当前树**。
> 当前树（`ad7f4b6` 之后）的实测：`cargo test -q --workspace --no-fail-fast`
> **8 红 0 新增**（choice×3 / db×2 / textpic×1 / m18 `hidden_and_transparent...` /
> m3_manual_rules `late_night_bedtime...`，全是长期基线），
> `m14_visual_regression` 5/5 全绿，`wolf-cli verify` PASS 64 / 1 SKIP，
> `tools/smoke-godot.sh` exit 0。详见 `docs/LIVE_PLAY_FIX_REPORT.md`。

* `cargo fmt --all -- --check`：0 差异。
* **HEAD（`9a817e4`）基线对照**（`git stash` 取出原树实测）：
  `cargo test -q -p wolf-game --lib` 在 HEAD 上已有 **4 项红灯**——
  `choice::tests::the_panel_geometry_is_the_measured_102_panel`、
  `choice::tests::a_long_option_widens_the_panel`、
  `choice::tests::the_known_ce257_replacement_character_never_reaches_the_glyph_pass`、
  `textpic::tests::inline_box_images_survive_as_box_glyphs_in_text_picture`。
  前三条是实现早已改成「面板宽 +4 px 防折行」「U+FFFD 剥离」而断言没跟上，
  第四条是 `\img` 改走贴图后旧断言失效；本轮已全部对齐/重写，**HEAD 的 4 项红灯归零**。
* `cargo test -q --workspace --no-fail-fast`：仅剩 **3 项既有失败**
  （均在 `docs/HANDOFF_PROGRESS.md` 长期记录，非本轮引入）：
  `m3_manual_rules::late_night_bedtime_skips_to_next_evening`、
  `m3_save_load::save_data_01_and_02_differ_in_hud_time_and_money`、
  `m3_status_panel::ce238_relative_panel_lands_at_the_left_edge`。
* `WOLF_DATA_ROOT=<绝对路径> cargo test -q -p wolf-game --lib`：
  **369 passed / 2 failed**，两项均为既有 `db::tests::*` 姊妹作期望差异。
* `wolf-cli verify`：**PASS 64 / 1 SKIP**（`dxarchive.header` loader pending）。
* `bash tools/build-godot.sh`：重建 `godot/bin/wolf_gdext.dll` 成功。
* `bash tools/smoke-godot.sh`：**exit 0**，`verify_p0_fixes.gd` 与
  `verify_ui_and_interaction_fixes.gd` 均 `ALL VERIFICATION TESTS PASSED`。
* 临时探针（已删）：反复打开状态界面（地图事件 30）8 轮，
  Godot 侧 `OS.get_static_memory_usage()` 在 25,452,589 / 25,497,253 字节之间
  随面板开合波动、**无单调增长**，Rust 侧 picture 数 91、实例数 8 恒定。
  即「反复打开状态界面会吃爆内存」在当前代码上**未复现**，不予立项。

---

## 5. 仍开放（与本轮无关）

* 上述 3 + 2 项既有姊妹作/陈旧期望差异。
* `m3_status_panel::ce238_relative_panel_lands_at_the_left_edge`（面板停在 -305，
  属 `picture.rs` 相对绘制路径，待单独排查）。
* 评审 §5 的两条原版证据缺口（其他角色头像底边、夜间姿势/相册可用性）仍需实机比对。
* **因回退重新开放**：Opcode 122 的首行截取（`0xFFF0` 掩码）、`\img` 贴图分层、
  动作键绕过范围收窄、`150 Move` 活跃槽位遍历、Godot 回归脚本接入 smoke。
  这五项在当前代码里**都没落地**，需要时可以重新做。

