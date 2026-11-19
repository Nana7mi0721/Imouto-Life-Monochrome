# 《妹！生活 ～単色～》只读静态代码审查报告（`1c76dcc..9a817e4`）

> **归档说明（2026-11-18）**：本文为`1c76dcc..9a817e4` 区间的只读静态代码审查报告，内容已被 [`docs/reviews/REVIEW_9a817e4_FIX_REPORT.md`](../../reviews/REVIEW_9a817e4_FIX_REPORT.md) 与 [`docs/reviews/CODE_REVIEW_4ROUND.md`](../../reviews/CODE_REVIEW_4ROUND.md) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


- **审查范围**：`HEAD 9a817e4` + `CHANGES_since_1c76dcc.patch`（含 `05_new_changes.zip` 未跟踪文件，排除第三方插件 `godot/addons/`）
- **参考数据**：`work/out/_ce_full.json`、`work/out/map_full.json`、`ptr_sc/` 原版实机截图
- **审查方式**：纯只读静态代码与字节码对照审查（未构建、未运行原版游戏、未修改源码）

---

## 1. 总评：**Block**（存在 1 项本轮新引入的 P0 级 VM 指令解码回归）

本轮围绕实机视觉与交互缺陷完成了多项有效修复（`Opcode 150` 范围批处理 `span`、气球加高与 `36002` 锚定、`2999` 鼠标哨兵、行动力栏右对齐定锚与黑幕遮挡保护、`\img` 改走图集贴图）。但本轮修改 `Opcode 122` 掩码导致了 `CE 268` 与 `CE 270` 的首行切分逻辑失效，建议优先修复后再合入或进入下一轮实机测试。

---

## 2. 本轮改动新引入的回归（Regressions）

### [P0] `Opcode 122` 掩码改为 `mode & 0xFF00` 并把 `上1行切り取り` 移至 `0x0200`，破坏 `CE 268` 名牌首行截取与 `CE 270` 逐行流式切分

- **文件与行号**：`crates/wolf-vm/src/exec.rs:2654, 2715, 3998`
- **现象与推理路径**：
  1. 统计全量 `CommonEvent` 字节码（`work/out/_ce_full.json`）确认：全作 **0 处**使用 `0x0200`，而 `mode = 17 (0x0011)` 与 `mode = 18 (0x0012)` 分别真实出现在：
     - **`CE 268 pc=14`**：`122 [1600010, 17, 1600005]`（将多行参数 `CSelf5` 的首行切入 `CE 269 CSelf5` 名牌槽）；
     - **`CE 270 pc=2000`**：`122 [1600096, 18, 1600095]`（从 `[self95]` 中逐行切出首行正文至 `CSelf96` 并从源串移除）。
  2. 在 WOLF RPG 引擎中，`0x0010` 正是 `上1行切り取り`。本轮补丁将 `operation` 掩码由 `0xFFF0` 改为 `0xFF00`、并将分支由 `0x0010` 移至 `0x0200`（同时改写了 `exec.rs:3998` 单测掩盖了失败），导致 `mode = 17 / 18` 全部落入 `0x0000`（普通赋值 `=`），不再切分首行也不会从源串消费已显示行。
- **最小修复建议**：恢复 `let operation = mode & 0xFFF0;` 与 `0x0010 =>` 分支，并将 `exec.rs:3998` 单测还原为 `0x0011`。
- **证据等级**：`Confirmed`

---

### [P2] `\img` 内联贴图迁入 `atlas.rs` 后：混排文本整条被吞、忽略 `anchor/scale`、且未过滤 `alpha == 0`

- **文件与行号**：`crates/wolf-game/src/atlas.rs:9-54`、`crates/wolf-game/src/game.rs:2398-2400`、`crates/wolf-game/src/message.rs:888`、`crates/wolf-game/src/textpic.rs:1105`
- **现象与推理路径**：
  1. `game.rs:2398` 只要检测到 `picture.text.contains(r"\img")` 即整条跳过 `text_quads()`，而 `atlas.rs:20-52` 只处理 `Newline` 与 `Image/ImageNearest`、完全忽略 `TextToken::Text` 与变量转义（`\v` / `\cself`）。若文本图片同时包含文字与 `\img`，文字内容会完全丢失。
  2. `atlas.rs:38` 直接构造 `[pen_x, pen_y, size.0, size.1]`，未应用 `picture.anchor`（如 `0x1000` 居中锚点）与 `picture.scale / scale_y`；且 `atlas.rs:10` 未过滤 `picture.alpha() <= 0.0`，透明图仍会向图集打包贴图。
  3. 遗留不一致：`message.rs:888` 残留孤立注释 `/// Map the two shipped alertness-meter tiles...` 挂在 `push_plain` 上；`textpic.rs:1105` 单测仍断言返回 `"□■"`，与新路径脱节。
- **最小修复建议**：在 `atlas.rs:10` 增加 `picture.alpha() <= 0.0` 过滤；按 `picture.anchor` / `scale` 计算基准偏移；若需支持图文混排，应按 token 顺序协同推进光标而不是整条跳过 `text_quads()`。
- **证据等级**：`Confirmed`

---

### [P2] 读档恢复地图后 `current_map_path` 缺少 `.mps` 后缀，导致 `scenery_quad` 背景在读档后失效

- **文件与行号**：`crates/wolf-game/src/game.rs:2798`（`resume_loaded_map`）vs `crates/wolf-game/src/db.rs:252-265`
- **现象与推理路径**：
  1. `boot()`（`game.rs:1548`）与 `install_map()`（`game.rs:1914`）写入 `current_map_path` 时均包含 `.mps` 后缀（如 `"MapData/SampleMapA.mps"`），与 `SysDatabase` 表 0 列 0 格式一致。
  2. `resume_loaded_map()`（`game.rs:2798`）使用 `file_stem()` 提取的 `name` 拼接为 `"MapData/{name}"`（缺少 `.mps`），导致 `databases.map_scenery_by_path(map_path)` 精确匹配返回 `None`，读档后无法生成 `-20_000` 背景图元。
- **最小修复建议**：将 `game.rs:2798` 改为 `self.current_map_path = Some(format!("MapData/{name}.mps"));`。
- **证据等级**：`Confirmed`

---

## 3. 真缺陷（Defects）

### [P1] `Game::frame()` 逐帧写入的 `Sys77..Sys82` 为 UTC 时间且破坏运行确定性与离线 Parity

- **文件与行号**：`crates/wolf-game/src/game.rs:353-394, 3682-3688`
- **现象与推理路径**：
  1. `current_datetime()` 直接对 `SystemTime::now().duration_since(UNIX_EPOCH)` 取模，未计算本地时区偏移，产出的是 **UTC 时间**而非原版 `GetLocalTime()` 的本地时间（东亚时区 00:00~08:00 日期与小时会整体偏差）。
  2. 每帧读取墙钟会破坏同存档回放、`parity-godot.sh` 与离线回归测试的跨时段确定性。
- **最小修复建议**：改用本地时间（或由宿主注入可固定/可覆写的时钟源，在无头测试与 parity 模式下使用确定性时间）。
- **证据等级**：`Confirmed`

---

### [P2] `action_key_event_ignoring_conditions` 扩宽至 `5 | 21 | 22 | 28 | 30 | 35`，绕过脚本的合法禁用门禁

- **文件与行号**：`crates/wolf-game/src/game.rs:2898`
- **现象与推理路径**：
  - 核对 `work/out/map_full.json` 中 `SampleMapA` 的对应事件页条件：
    - `Ev 5`（保存）：`var176 == 0 && var238 == 0`（剧情/相册期间禁止保存）；
    - `Ev 22 / 28`（姿势 1/2）：`var69 == 0`（动作锁）、`var18 <= 5`、`var101 <= 1`；
    - `Ev 30`（数据）：`var100 == 0 && var238 == 0`；
    - `Ev 35`（相册）：`var247 == 1`（由并行页 `var100 == 0 && var176 == 0` 驱动）。
  - 此前仅 `Ev 21` 因 `v100 == 10` 子菜单需要绕过页条件；扩宽到 `5 | 22 | 28 | 30 | 35` 后，玩家在剧本明确禁止的阶段（`var176 == 1`、`var69 == 1`、`var238 == 1`）仍可强行触发保存、切换姿势或打开数据/相册。
- **最小修复建议**：仅保留有明确子菜单冲突的 `Ev 21`（或针对具体子菜单状态做白名单放行），不要无条件绕过全部图标的剧本条件。
- **证据等级**：`Confirmed`

---

### [P2] `PictureAction::Move` 在范围模式下按 `lo..=hi` 逐整数遍历，存在无界大跨度循环风险

- **文件与行号**：`crates/wolf-game/src/picture.rs:1013-1025`
- **现象与推理路径**：
  - `for n in lo..=hi` 对区间内每个整数调用 `self.pictures.contains_key(&n)`。若某段脚本的 `span` 变量未初始化或传入大跨度范围，会执行数万至上百万次哈希查询。
- **最小修复建议**：改为通过 `self.pictures.range(lo..=hi).map(|(&n, _)| n)` 直接枚举活跃槽位（再按需补入 `cmd.number`），将复杂度降为 `O(活跃槽位数)`。
- **证据等级**：`Confirmed`

---

### [P3] 新增 Godot 回归脚本断言过空且硬编码本地绝对路径

- **文件与行号**：`godot/tests/verify_p0_fixes.gd:2204`、`godot/tests/verify_ui_and_interaction_fixes.gd:2280, 2308-2346`
- **现象与推理路径**：
  1. 两份脚本均硬编码 `"E:/Study/github program/Imouto Life/work/Data"`，且未接入 `tools/smoke-godot.sh`。
  2. `verify_ui_and_interaction_fixes.gd` 传入 `(450, 300)` 后未断言 `Picture 2999` 实际存在及坐标跟随；传入 `(935, 505)` 点击后未检查 `clicked_frame` 状态，即使未命中也会打印 `PASS` 并退出 `0`。
- **最小修复建议**：改用相对路径 / `WOLF_DATA_ROOT` 环境变量解析数据目录，并为 `2999` 坐标与 `(935, 505)` 点击后 `last_action_event` / `choices` 补充硬断言。
- **证据等级**：`Confirmed`

---

## 4. 设计取舍（Design Trade-offs，非缺陷）

1. **选项面板宽度与光标框高**（`crates/wolf-game/src/choice.rs:111, 129-132`）：
   - 面板宽度 `+4.0 px`（`widest + TEXT_INSET * 2.0 + 4.0`），光标高度 `(pitch + 1.0).max(font_px + 4.0) = 28.0` 并上移 `2.0 px`。经计算，末行光标底边位于 `5 + rows * 27`，仍在面板底边 `6 + rows * 27` 之内（留 `1 px`），不会越界；以 `+4 px` 宽度偏差换取不裁切文字属于合理取舍。
2. **`BALLOON_FACE_BOTTOM_Y = 563.0` 与 `BALLOON_FACE_FRAME_MIN_HEIGHT = 136` 硬编码**（`crates/wolf-game/src/game.rs:295-302, 1797-1803`）：
   - 与 `ptr_sc/卧室_点击妹妹_首句话.png` 一致；但对其他尺寸头像贴图缺乏自适应。
3. **透明热区放行 `hover` 门禁**（`crates/wolf-game/src/game.rs:4408`）：
   - 去除 `picture.opacity <= 0` 限制，使夜间隐藏鼠标热区可被 `hover` 轮询到；因 `picture_ink_rect_in` 仍拦截 `opacity <= 0`，不会重新打开 HUD 按钮热区。
4. **`GameView.gd` `_update_mouse_cursor` 与 `ap` 图层合批**（`godot/scripts/GameView.gd:2105-2116, 2155-2158`）：
   - `2999` 存在且 `alpha > 0` 时隐藏原生光标、失焦/退出时恢复 `VISIBLE`；`ap` 以 `z = 230` 参与排序，避免压在 `12000+` 存档网格上方（注：`_append_action_bar_and_overlays` 传入的 `ap` 及 `_BlendBatch.ap` 已不再被 `_draw_action_points_dict` 使用，属无害冗余）。

---

## 5. 需要补充原版证据确认的事项

1. **其他含头像对话场景的原版截图**：确认除妹妹外若存在其他角色或不同高度头像使用 `36002` 槽位时，底边 `563` 与最小框高 `136` 是否全角色通用。
2. **夜间姿势按钮（`Ev 22 / 28`）与相册（`Ev 35`）在子菜单中的可用性**：确认原版在 `var69 != 0` 或特定动作阶段时，姿势按钮是“脚本故意禁用”还是“可见即可点击”，以决定 `game.rs:2898` 的条件绕过范围。

---

## 6. 核实与勘误（2026-11-15，端口侧回执）

本文件为外部只读审查产物，正文一字未改。端口侧已逐条核实并闭环，详见
**[docs/reviews/REVIEW_9a817e4_FIX_REPORT.md](../../reviews/REVIEW_9a817e4_FIX_REPORT.md)**。要点：

* **P0（Opcode 122）成立并已修**：掩码回 `mode & 0xFFF0`、分支回 `0x0010`，
  全作 `0x0200` 0 处；新增镜像 CE270 `pc2000` 的回归单测。
* **[P2] `\img` 三项成立并已修**：贴图条与文字分层、锚点/缩放定位、`alpha <= 0` 过滤。
  补充证据：全作 771 条 `\img` 字符串**图文混排 0 条**。
* **[P2] `.mps` 后缀成立并已修**；**[P1] UTC 时钟成立并已修**（本地时间 + 可注入时钟）。
* **[P2] 动作键绕过成立并已修**：名单收紧为 `5|21|22|28`，且只忽略交互模式变量
  `v100`（`深夜1`），其余页条件逐条保留。相册（35）与数据（30）不再绕过。
* **[P2] `PictureAction::Move` 无界遍历成立并已修**：改为活跃槽位区间查询。
* **[P3] 两处坐标前提被证伪**：`Picture 2999` 由 Map Event 14 创建（页条件 `v120==1`），
  `(935,505)` 命中的 `ev21` 页条件为 `v100==1`；零售存档全在白天，这两处白天不绘制。
  脚本已改为按当前状态分支的硬断言；硬编码绝对路径改为
  `--data-root=` → `WOLF_DATA_ROOT` → `res://../work/Data` 解析链，并接入 `tools/smoke-godot.sh`。
* **另需澄清**：本文件不含 `武器スキルセット` / `防具スキルセット`。
  经全量核实，本作 33,970 条脚本字符串中 `スキルセット` **0 命中**
  （库存 CE 的 `武器増加処理`/`防具増加処理` 是 WOLF 通用库模板，本作无对应内容），
  该项为误报，端口侧不实现。
