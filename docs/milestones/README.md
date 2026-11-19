# 里程碑研发记录（docs/milestones）

本目录归档项目从 M0 数据勘察至 M7 模块扩展历次里程碑的专题研发记录、设计草稿与阶段性验证报告。

> **阅读说明**：本目录文档记录各里程碑攻坚时的一手推导过程与设计决策。如需查询当前实现的最新事实标准，请优先查阅根目录 [HANDOFF_M0.md](../HANDOFF_M0.md) 与 [engine/](../engine/README.md)。

## 里程碑阶段索引

### M2 ~ M2.5：日常循环与交互打磨
- [M2_SLICE.md](M2_SLICE.md) — 日常循环切片验证：CE245/251/242/243/244/256 实测与键码契约
- [M25_LIVE_UX.md](M25_LIVE_UX.md) — 实机 UX 四项收口：实时 RNG、光标平滑、睡姿热区与存读档

### M3：完整运行时研发专题
- [M3_RUNTIME.md](M3_RUNTIME.md) — 完整运行时骨架：测试基架、引擎修复与音频调度
- [M3_EVENT_GRAPH.md](M3_EVENT_GRAPH.md) — 地图事件调度图谱与执行队列
- [M3_EVENT_MAP.md](M3_EVENT_MAP.md) — 地图事件监听与触发条件
- [M3_MAP_EVENTS.md](M3_MAP_EVENTS.md) — 5 张注册地图事件执行逻辑
- [M3_EVENT_INPUTS.md](M3_EVENT_INPUTS.md) — 事件期输入门控与按键注入
- [M3_ENDINGS.md](M3_ENDINGS.md) — 全部结局判定链与演出逻辑
- [M3_TITLE_UX.md](M3_TITLE_UX.md) — 标题界面交互与开场选择
- [M3_STRING_DECODE.md](M3_STRING_DECODE.md) — 文本编码识别与 GBK/Shift-JIS 统一解码
- [M3_ASSET_REFS.md](M3_ASSET_REFS.md) — 资源引用拓扑与依赖提取
- [M3_VARDB_BUG.md](M3_VARDB_BUG.md) — 变量持久化缺陷与字典修复
- [M3_MANUAL_ALIGNMENT.md](M3_MANUAL_ALIGNMENT.md) — 与原版差异手工校准清单

### M4：对等打磨与性能提升
- [M4_PARITY.md](M4_PARITY.md) — 对等打磨总体计划（UI、音频、存档互通）
- [M4_HUD.md](M4_HUD.md) — HUD 数值排版、相对坐标与负号切片
- [M4_SETTINGS_UI.md](M4_SETTINGS_UI.md) — CE132/CE95 设置面板与排版
- [M4_PERF.md](M4_PERF.md) — 离屏渲染基线与 Quad 贴图缓存优化
- [M4_V8_AUDIT.md](M4_V8_AUDIT.md) — 变量 v8 语义与夜间活动上限专项

### M5 ~ M7：超越原版与增强特性
- [M5_BEYOND.md](M5_BEYOND.md) — 超越原版特性 A~F（高分缩放、F2/F3 Overlay、F4 历史文本、TSV 翻译、Mod 覆盖层）
- [M6_INPUT.md](M6_INPUT.md) — 123 选项字解码、输入掩码过滤与按键闭环
- [M7_I18N.md](M7_I18N.md) — 英语语言包构建（TSV 机制与双列转义）
- [M7_PATCH.md](M7_PATCH.md) — 数据库记录级二进制补丁系统
- [M7_HOTKEYS.md](M7_HOTKEYS.md) — 启动参数热键重绑定（`--hotkeys`）
