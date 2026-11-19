# MCP / Godot 运行时审计探针

`godot/tests/mcp_audit_probe.gd` 是只用于编辑器、无头测试和 MCP 驱动的
GameView 审计节点。它不自动加载，不进入发行 PCK（`tests/` 已被导出排除），
也不会调用 WolfGame 的存档写入接口。

## 先决条件

探针读取现有 `GameView` 的公开状态：

- `packet`：`sprites`、`texts`、`choices`、`stats`、`last_action_event` 等；
- `wolf`：`save_ui_active()`、`running_events()`、`transcript()`；
- `wolf.debug_event_snapshot()`：每个存活实例的 `event/instance/parallel/pc/wait/self_base/page`；
- `wolf.message_active()` / `wolf.message_text()`：当前可见对话。

`debug_event_snapshot()` 的 `wait` 是稳定字符串：

```text
none / timer / message / message_choice / choice / child / key
```

`page == -1` 表示该实例不是当前地图活动页，或来自公共事件/子事件。

## MCP 挂载

通过 Godot AI 的 `game_eval` 在运行中的游戏里执行：

```gdscript
var scene = get_tree().current_scene
var probe = scene.get_node_or_null("McpAuditProbe")
if probe == null:
    probe = load("res://tests/mcp_audit_probe.gd").new()
    probe.name = "McpAuditProbe"
    scene.add_child(probe)
    probe.attach(scene)
    probe.start()
return probe.snapshot()
```

之后每次由 Harness 发送点击、按键或滚轮后调用：

```gdscript
var probe = get_tree().current_scene.get_node("McpAuditProbe")
probe.mark_input("click", {"x": 366, "y": 140})
return probe.snapshot()
```

探针还提供：

- `targets()`：当前可见的 `sprite/control/choice/save_slot/map_event` 目标及
  `rect/center`，供覆盖式点击。标题菜单的 `menu1..menu3` 没有独立文本
  run，探针会按原脚本实际绘制它们的图片槽位 3..5 暴露为 `choice`；
  `map_event` 来自只读 `wolf.debug_action_targets()`，列出当前条件下会选中的
  ActionKey 事件矩形、事件名、页码以及 `running/starts` 状态；
- `audit_text_items(items)`：对任意 `packet.texts` 风格数组做文本检查；
- `take_violations()` / `reset()` / `write_report(path)`：抽取、清空和落盘。

取走告警并落盘：

```gdscript
var probe = get_tree().current_scene.get_node("McpAuditProbe")
var found = probe.take_violations()
probe.write_report("user://audit/last_report.json")
return found
```

`write_report()` 会递归创建父目录；报告只包含探针快照，不写玩家存档。

## 当前检查项

- `stall_after_input`：`mark_input()` 后连续 `stall_limit_frames` 个非冻结帧，
  transcript 长度、choices、save UI、submenu、last action event、
  message active/text，以及非并行 VM 实例的 `page/pc/wait` 均无变化。
- `sprite_state_flap`：30 帧内同一图片槽位只在两个离散
  `(src, rect, blend)` 状态间切换至少 6 次。指针 2998/2999 默认忽略，
  可用 `exempt_slots` 增加已知呼吸/眨眼槽位。
- `implicit_text_wrap`：非 `wrap` 文本实际 shaped 出多于一行。
- `text_overflow`：`TextParagraph.get_size().x` 超过布局矩形 4 px 以上。
- `text_overlap`：同 `z`、不同槽位、alpha > 0.5 的文本真实包围盒重叠超过
  较小面积的 15%，保留 2 px 容差。
- `text_artifact`：可见文本残留 `\f[`、`\c[`、`\img[`、U+FFFD 或控制字符。

文本检查默认每 6 帧一次，并复用 `WolfText._shape()` 的段落缓存；不要改为
每帧对所有文本重新 shaping。

## 无头回归

```bash
bash tools/audit-godot.sh
```

脚本会构建 `wolf_gdext.dll`，启动真实 GameView，并验证：

- 探针可以挂载和读取 VM 快照；
- 标题菜单可从图片槽位暴露为至少 3 个 `choice` 目标；
- 人为构造的显式换行、窄框溢出和残留格式码会分别触发文本告警；
- 输入后无状态推进会触发 `stall_after_input`；
- JSON 报告可写。

## 覆盖探索驱动

`godot/tests/mcp_audit_driver.gd` 在探针之上提供确定性的目标规划与覆盖记录。
它不会自动启动后台循环；外部 Harness 可以只读调用 `plan_next()`，也可以让
驱动执行安全点击：

```gdscript
var scene = get_tree().current_scene
var driver = scene.get_node_or_null("McpAuditDriver")
if driver == null:
    driver = load("res://tests/mcp_audit_driver.gd").new()
    driver.name = "McpAuditDriver"
    scene.add_child(driver)
    driver.attach(scene)
    driver.start()
return driver.plan_next()
```

- `plan_next(false)`（默认）只返回默认安全计划：标题界面只允许进入
  「继续/读取」，标题存档页允许读档；一旦进入地图事件流程，默认拒绝执行，
  避免自动探索触发存档写入。
- `plan_next(true)` 仍可只读地取出全部未访问目标（包括新游戏/退出等），但
  `execute_plan()` 会拒绝不安全计划。
- 只有在对 `work/out/audit_fixtures/` 之类的**一次性存档目录**运行时，才设置
  `driver.allow_mutating_actions = true`。绝不能直接对玩家 `work/Data/Save`
  打开此开关。
- `step()` / `tick(wait_frames)` 执行下一步并记录覆盖；`record_action()` 用于
  Harness 自己点击后补登记；`capture(path)` 从当前 viewport 存 PNG；
  `write_report(path)` 输出覆盖、最近动作、探针快照和告警，`save_writes` 恒为 0
  表示驱动自身未调用任何存档写接口。

```bash
bash tools/audit-explore.sh
```

该 smoke 会规划标题菜单、只点击安全的「继续/读取」入口，并在点击前后逐字节
比较 `Save/`，证明该路径没有写入。

## 场景夹具

测试存档应放在 `work/out/audit_fixtures/`，并按需要复制一份独立
`Save/` 目录后通过 `open_with_save_dir()` 打开。不要直接修改
`work/Data/Save`，也不要用测试覆盖玩家的真实存档。

一个场景脚本的基本顺序是：

1. MCP 启动游戏并挂载探针；
2. `mark_input()`；
3. 等待 2–60 帧，让目标界面稳定；
4. 调 `snapshot()` 和 `take_violations()`；
5. 有告警时截图并保存 JSON；
6. 将稳定复现路径固化为 `godot/tests/` 或 Rust 集成测试。

## 已知边界

- `stall_after_input` 只适用于 Harness 明确调用 `mark_input()` 之后；普通长动画
  和读档转场可能合理地保持状态不变，探针会跳过 `freeze/transition_active` 帧。
- `text_overlap` 是启发式检查，标题菜单、描边和故意叠加的 HUD 可能需要加入
  场景白名单；不要因为告警直接修改游戏排版，先看截图和双方槽位。
- 探针构造 `TextParagraph` 使用当前平台实际加载的字体，因此 Windows 和
  Android 的结论可能不同；安卓实机应单独跑一次。
- `debug_action_targets()` 只枚举“当前变量条件下已选中”的 ActionKey 页；
  尚未枚举失败条件页或所有历史页。普通 `sprite` 目标仍可能包含仅用于绘制、
  点击无逻辑效果的图片，探索时应结合 `map_event/control/choice` 优先级判断。
