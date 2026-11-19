# 文档索引（docs/README.md）

本文件是《妹！生活 ～単色～》Rust 重写的**唯一文档地图**。按用途分组：
交接 → 基线 → 里程碑 → M3 专题审计 → 引擎行为与逆向 → 审查与修复 → 调研资料 →
翻译 → 参考实现 → 工具与工作区 → 归档。

## 0. 状态约定

| 标签 | 含义 |
|---|---|
| **现行** | 内容代表当前工程事实，可以直接引用 |
| **现行 · 先读** | 现行且应当优先阅读的入口文档 |
| **现行 · 证据** | 现行的事实来源（实测 / 反编译），数字可直接引用 |
| **历史 · 非事实源** | 只作背景与证据链，**不得**从中抄数字或行号 |
| **已归档** | 已被取代，移入 `docs/archive/`，登记表见 [archive/README.md](archive/README.md) |

标「历史」「已归档」的文档只作证据链保留，**当前事实以「现行」条目为准**。

## 1. 交接与工程约定（先读）

| 文件 | 状态 | 内容 |
|---|---|---|
| [HANDOFF_M0.md](HANDOFF_M0.md) | **现行 · 先读** | 新会话交接：§0 提示词、§1 现状、§3 已实测硬事实、§4 世代差异、§5 M0 清单、§6 代码地图、§7 调研采信/推翻、§8 陷阱、§9 不要做、**§11 当前状态摘要** |
| [HANDOFF_PROGRESS.md](HANDOFF_PROGRESS.md) | 现行 · 查史 | 完整进度日志（M0–M7 与 C 任务逐步的改动、验证数字、坑），由 HANDOFF §11 拆出 |
| [../AGENTS.md](../AGENTS.md) | **现行 · 必读** | 协作约定：并行/写作用域、bash 开头、数据与测试、提交、清理、内容安全 |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | 现行 · 协作 | 开发者贡献指引、开发工作流、测试与规范约束 |
| [plans/README.md](plans/README.md) | 现行 · 规划 | 架构演进与交互优化方案目录（含 Android 触控交互优化方案） |
| [../tools/README.md](../tools/README.md) | 现行 · 工具 | 构建、测试、打包及逆向审计工具说明索引 |
| [../README.md](../README.md) | 现行 | 仓库总览、当前状态、快速开始、目录结构 |
| [../README_EN.md](../README_EN.md) | 现行 | 英文仓库总览与快速入门 |
| [../CHANGELOG.md](../CHANGELOG.md) | 现行 | 版本演进与变更日志 |
| [../DISCLAIMER.md](../DISCLAIMER.md) | 现行 | 版权免责声明与资产隔离原则 |
| [PROJECT_ASSETS.md](PROJECT_ASSETS.md) | 现行 · 资产盘点 | 停止重构后的清理记录与可复用资产清单（源码/数据/文档/逆向/证据） |

### 1.1 审查报告与归档

| 文件 | 状态 | 内容 |
|---|---|---|
| [reviews/CODE_REVIEW_4ROUND.md](reviews/CODE_REVIEW_4ROUND.md) | **现行 · 唯一审查事实源** | 第一至四轮完整审查（2026-11）：报告 §六基线 BUG-20..24（与 `HANDOFF_PROGRESS.md` 旧台账同号不同义）、第一轮 BUG-25..35、第二轮 BUG-36..40、第三轮 BUG-41..46、第四轮 BUG-47..48 + 架构建议 |
| [HANDOFF_DEEP_REVIEW_FIX.md](HANDOFF_DEEP_REVIEW_FIX.md) | **现行 · 完成交接** | BUG-25..48 的 T0–T11 完成状态、实施细节、官方手册/反编译语义证据、最终验证结果；历史中断快照保留 |
| [TASKS_REMAINING_BUGS.md](TASKS_REMAINING_BUGS.md) | **现行 · 执行完成** | 原 T0–T12 任务卡与写作用域；§0 为 2026-11-12 完成状态（含 T12 性能/旧编号复核），§1 起为历史编排快照 |
| [archive/HANDOFF_T12_PATCH_AND_LEDGER.md](archive/HANDOFF_T12_PATCH_AND_LEDGER.md) | 已归档 · 2026-11-13 会话 | T12 性能路径审查结论、`alpha_bounds` 记忆化与 `install_map` 清扫补丁、`m16` 双台账收口、`m14` 两场景既有红（含 A/B 归因与基线对照表） |
| [AUDIT_REBUILD_FIX_REPORT.md](AUDIT_REBUILD_FIX_REPORT.md) | 现行 · 两轮汇总 | T12 收口 + 审计轮：截图 6 项、RNG/缓存/键位/文本塑形落地、验证数字、未处理项与环境坑 |
| [GEMINI_REVIEW_1c76dcc_FIX_REPORT.md](GEMINI_REVIEW_1c76dcc_FIX_REPORT.md) | 现行 · 第三轮 | Gemini `1c76dcc` 全量审查处理：人名牌缓存 P1、行动力三位数右对齐、`1a9fafe` 两条闭环核对、测试与遗留项 |
| [reviews/README.md](reviews/README.md) | 现行 · 导读 | 审查轮次/缺陷编号对照、阅读注意、报告命名规则 |
| [GEMINI_FULL_AUDIT_GUIDE.md](GEMINI_FULL_AUDIT_GUIDE.md) | 现行 · 云端审查任务书 | Gemini 只读全量审查：云端数据边界、需求闭环矩阵、正确性/性能/死代码/素材封包检查、证据等级与交付格式 |
| [AUDIT_2411996_FIX_REPORT.md](AUDIT_2411996_FIX_REPORT.md) | 现行 · 全量审查修复 | `2411996` 审查处置：F-01 误报、Godot 导出、checksum 警告、发行包纯档、动作键门控/移动区间/资源缓存 |
| [reviews/T13_UI_REGRESSION_AUDIT.md](reviews/T13_UI_REGRESSION_AUDIT.md) | 现行 · UI 专项 | 2026-11-12 用户 15 项截图缺陷逐项复核；91 passed / 2 ignored，中央对话双源仍开放 |
| [REVIEW_9a817e4_FIX_REPORT.md](REVIEW_9a817e4_FIX_REPORT.md) | 现行 · 复审修复 | `code_review_9a817e4.md`（`1c76dcc..9a817e4`）核实与修复：名牌缓存、格子条对齐、夜间点击热区 |
| [LIVE_PLAY_FIX_REPORT.md](LIVE_PLAY_FIX_REPORT.md) | 现行 · 实机修复 | 实机 11 项断言（`live_play_issues_and_fixes_report.md`）剩余项修复：开场取消穿透、窗口图标、音频 cell |
| [M25_LIVE_UX.md](M25_LIVE_UX.md) | 现行 · 实机 UX | M25 四项收口：live RNG / 光标 / 睡姿热区 / 存读档 |
| [archive/README.md](archive/README.md) | 归档 · 索引 | 归档规则与全部归档项（旧交接、旧审查报告） |
| [archive/HANDOFF_NEXT_AGENT.md](archive/HANDOFF_NEXT_AGENT.md) | 已归档 · 已完成 | 2026-11-11 POST_DEEPSEEK 19 项修复交接（BUG-02 闭环），仅作追溯 |
| [archive/reviews/CODE_REVIEW_1_2ROUND_superseded.md](archive/reviews/CODE_REVIEW_1_2ROUND_superseded.md) | 已归档 · 被取代 | 第一、二轮审查单行本（BUG-25..40）；内容已并入现行四轮总报告 |

### 1.2 云端只读审查轮次

云端复审按轮次出报告，**同一时间只保留最新一轮为现行**，更早的轮次进 `docs/archive/reviews/`。

| 轮次 | 位置 | 状态 | 基线与内容 |
|---|---|---|---|
| 2026-11-18 | [reviews/cloud_audit_2026-11-18_e716f08/](reviews/cloud_audit_2026-11-18_e716f08/) | **现行 · 最新** | 基线 `e716f08`；目前只交付了执行摘要（分册说明见 [reviews/README.md](reviews/README.md)） |
| 2026-11-17 | [archive/reviews/cloud_audit_2026-11-17_2411996/](archive/reviews/cloud_audit_2026-11-17_2411996/) | 已归档 · 被取代 | 基线 `2411996`；10 份完整分册，处置结果见 [AUDIT_2411996_FIX_REPORT.md](AUDIT_2411996_FIX_REPORT.md) |

> **编号体系警告**：云端轮次报告用 `F-xx` 编号，与
> [reviews/CODE_REVIEW_4ROUND.md](reviews/CODE_REVIEW_4ROUND.md) 的 `BUG-20..48` 台账
> **不是同一套**。引用时必须写明出处（轮次 + 编号），不要把 `F-07` 当成 `BUG-07`。

### 1.3 归档区

归档件**统一登记在 [archive/README.md](archive/README.md)**（文件 / 归档原因 / 现行替代 三列），
本索引不重复列举。两类来源：

| 归档族 | 内容 |
|---|---|
| `docs/archive/*.md` | 已被取代的会话存档与诊断报告（交接类、T12 轮报告、UI 诊断） |
| `docs/archive/reviews/*` | 已被取代的审查报告与**成组的云端审查产物**（按轮次建目录） |

归档不等于删除：内容保留作证据链，但其中的数字、行号、结论**不再代表当前工程事实**。

## 2. 基线

| 文件 | 状态 | 内容 |
|---|---|---|
| [BASELINE.json](BASELINE.json) | 现行 | 本作自己的 `wolf-cli verify` 期望值：`game_dat` **9 个分组**（strings / u8 / u16 设置 / 字体 / 两张随机表 / 页脚 / 版本头）、`common_events` 350 个公共事件、地图事件与 tileset、14 项文件版本、1,361 条 archive |
| [REFERENCE.md](REFERENCE.md) | 现行 | 日文原版路径、攻略链接、10 张实机截图目录、存档样本 |

## 3. 里程碑说明

| 文件 | 状态 | 内容 |
|---|---|---|
| [M2_SLICE.md](M2_SLICE.md) | 完成 | M2 日常循环切片：CE245/CE251/CE242/CE243/CE244/CE256 实测、鼠标→键码契约、验收 |
| [M3_RUNTIME.md](M3_RUNTIME.md) | 完成 | M3 完整运行时：测试基架、引擎修复、存档/字符串/音频、遗留缺口 |
| [M4_PARITY.md](M4_PARITY.md) | 完成 | M4 对等打磨分解（UI、音频、存档互通、性能） |
| [M4_HUD.md](M4_HUD.md) | 完成 | M4 HUD/读档数值与负号图片保真修复 |
| [M4_SETTINGS_UI.md](M4_SETTINGS_UI.md) | 完成/历史口径 | CE132/CE95 设置界面排版修复；tenths/1/10 字符格部分已在当前工作区撤销，见文首说明 |
| [M4_PERF.md](M4_PERF.md) | 完成/基线 | M4 headless 性能基线与优化候选（tile quad 缓存已落地） |
| [M4_V8_AUDIT.md](M4_V8_AUDIT.md) | 完成 | 普通变量 v8 语义专项（夜间可活动上限 23..26） |
| [M5_BEYOND.md](M5_BEYOND.md) | 完成 | M5 超越原版 A–F 切片（高分辨率/调试 overlay/统计/翻译目录/mod 覆盖/消息回顾） |
| [M6_INPUT.md](M6_INPUT.md) | 完成 | M6 输入层对等（123 选项字解码、键码闭环、125/126、121 min-max） |
| [M7_I18N.md](M7_I18N.md) | 完成 | M7 英语语言包（TSV 双列转义、模板静态句、en.full.tsv 100%） |
| [M7_PATCH.md](M7_PATCH.md) | 完成 | M7 mod 记录级二进制补丁（Database 字节序列化 + set_cell + 两阶段补丁） |
| [M7_HOTKEYS.md](M7_HOTKEYS.md) | 完成 | M7 模拟器热键重绑定（--hotkeys） |
| [ASSETS.md](ASSETS.md) | 完成 | 素材目录导出：`wolf-cli assets`（另见 `--db-defaults` 数据库层导出） |
| [PACKAGING.md](PACKAGING.md) | 完成 | 发布打包：`work/out/dist/<version>/` |

## 4. M3 专题审计

| 文件 | 主题 | 对应测试 |
|---|---|---|
| [M3_EVENT_MAP.md](M3_EVENT_MAP.md) | 自有公共事件 CE212..303 冒烟与事件地图 | `m3_event_smoke` |
| [M3_EVENT_GRAPH.md](M3_EVENT_GRAPH.md) | 公共事件调用图与可达性静态审计 | `m3_event_graph` |
| [M3_EVENT_INPUTS.md](M3_EVENT_INPUTS.md) | 自有事件在真实按键注入下的可达性 | `m3_event_inputs` |
| [M3_MAP_EVENTS.md](M3_MAP_EVENTS.md) | 5 张注册地图属性 + SampleMapA 35 事件冒烟 | `m3_map_events` |
| [M3_MANUAL_ALIGNMENT.md](M3_MANUAL_ALIGNMENT.md) | 官方说明书 manual01..06 逐条核对 | — |
| [M3_ASSET_REFS.md](M3_ASSET_REFS.md) | 事件脚本图片/音频引用完整性扫描 | `m3_asset_refs` |
| [M3_STRING_DECODE.md](M3_STRING_DECODE.md) | CP932/GBK 混排解码审计与回归 | `m3_string_decode` |
| [M3_VARDB_BUG.md](M3_VARDB_BUG.md) | 新游戏存档丢失 CDataBase 可变数据库（已修复） | `m3_vardb_cdata_roundtrip` |
| [M3_TITLE_UX.md](M3_TITLE_UX.md) | 标题菜单可见性与“取消读档返回标题”链 | 标题/读档测试 |
| [M3_ENDINGS.md](M3_ENDINGS.md) | 结局条件、变量写入者与事件链 | `m3_endings` |

## 5. 引擎行为与逆向（C 任务）

> 这一组是**引擎行为的事实源**。`ENGINE_BEHAVIOR.md` 是面向实现的规范；
> `RE_GAME_EXE.md` 与 `re/*.md` 是原版 Game.exe 的反编译证据（方法、函数地址、伪码行号）。

| 文件 | 状态 | 内容 |
|---|---|---|
| [ENGINE_BEHAVIOR.md](ENGINE_BEHAVIOR.md) | **现行 · 引擎规范** | 六类核心行为（九宫格/文本度量与换行/选择面板/1-10 UI 缩放/过渡/叠色）+ §3 十二项常量与落地状态 + **§3.5 开放项清单（OPEN-01..11）** |
| [RE_GAME_EXE.md](RE_GAME_EXE.md) | 现行 · 逆向方法 | 工具链（Ghidra 12.2 + JDK 25）、二进制身份、函数地图、可复现步骤与坑 |
| [re/RUNTIME_CONSTANTS.md](re/RUNTIME_CONSTANTS.md) | 现行 · 证据 | 帧率/窗口/present 后端/皮肤/过渡掩膜几何 |
| [re/TEXT_METRICS.md](re/TEXT_METRICS.md) | 现行 · 证据 | 行距公式、禁则（原版无）、打字机累加水位 |
| [re/LAYOUT_METRICS.md](re/LAYOUT_METRICS.md) | 现行 · 证据 | 坐标取整、默认原点、九宫格、极小盒、102 面板全链、超宽选项；§9 落地记录 |
| [re/TRANSITION.md](re/TRANSITION.md) | 现行 · 证据 | 过渡掩膜几何、溶解语义、tint×fade 顺序；§5 落地前后对照 |
| [re/SCREENSHOT_METRICS.md](re/SCREENSHOT_METRICS.md) | 现行 · 实机 | 实机截图标定：消息行距 23、选择支行距 27、面板 156×114 / 162×141、内缩 8 |
| [re/EVENT_REACHABILITY.md](re/EVENT_REACHABILITY.md) | 现行 · 证据 | 事件可达性静态分析：入口条件 → 触发点 → 实际可达集合 |
| [re/README.md](re/README.md) | 现行 · 证据层导读 | 逆向与实机证据层索引：6 篇的取证方法（只读 Ghidra dump / 数据解析 / 实机度量）、与 `ENGINE_BEHAVIOR.md` §3 条目的对应、置信度口径与阅读注意 |

### 5.1 opcode 契约（逐指令语义）

> 这一组是**单个字节码指令的语义契约**，写实现前先查这里，不要凭反编译片段猜。

| 文件 | 状态 | 内容 |
|---|---|---|
| [OPCODE_122.md](OPCODE_122.md) | 现行 · 契约 | Opcode 122 SetString 变量字符串操作：第二操作数语义、模式位掩码（`0xFF00` vs `0xFFF0`）、与「代入先を変数で指定」标志的区分 |
| [OPCODE_220_SAVE.md](OPCODE_220_SAVE.md) | 现行 · 契约 | Opcodes 220 / 221 / 222 存档访问：三者线格式相同但语义不同，存档编号与路径解析 |

## 6. 调研与实证（历史背景，不是当前事实源）

| 文件 | 说明 |
|---|---|
| [research/README.md](research/README.md) | 调研目录说明 |
| [research/M7_PRNG.md](research/M7_PRNG.md) | PRNG 实证（M3 已落地） |
| [research/gpt-reports/](research/gpt-reports/) | 历史 · 非事实源 | M0 之前的 6 份 GPT 深度调研报告 + 前置问题组 `GPT_RESEARCH_GROUPS.md`；**采信/推翻清单以 HANDOFF §7 为准**。逐篇对照见下表 |
| [攻略文档/](攻略文档/) | 第三方攻略与资料（gitignore，不提交；仅本地参考，非事实源） |
| 相关链接.txt | 外部链接汇总（gitignore，不提交） |

**gpt-reports 逐篇对照**（**文件名里的 `(1)`…`(5)` 是下载批次序号，不代表问题组编号**）

| 文件 | 问题组 | 主题 |
|---|---|---|
| [GPT_RESEARCH_GROUPS.md](research/gpt-reports/GPT_RESEARCH_GROUPS.md) | 前置 | 6 个问题组的提问原文；每组规定固定 7 段报告格式与「事实 / 推测」分界规则 |
| [deep-research-report (4).md](research/gpt-reports/deep-research-report%20%284%29.md) | 第 1 组 | 日常循环与时间/日程/行动力：主角四种身份、行动力上限与消耗、时间段划分 |
| [deep-research-report (5).md](research/gpt-reports/deep-research-report%20%285%29.md) | 第 2 组 | 妹妹状态与人际数值：状态面板字段、警戒度与性興味、阈值事件、状态图标 |
| [deep-research-report (2).md](research/gpt-reports/deep-research-report%20%282%29.md) | 第 3 组 | H 场景系统、相册与结局：场景分类与进入条件、操作方式、结局数量 |
| [deep-research-report (3).md](research/gpt-reports/deep-research-report%20%283%29.md) | 第 4 组 | UI、操作、设置与存档：按键与引擎行为，以及公开资料查不到的项清单 |
| [deep-research-report (1).md](research/gpt-reports/deep-research-report%20%281%29.md) | 第 5 组 | WOLF RPG Editor 2.00 世代引擎事实：版本发布时间线、「基本システム Ver2.20」模板、2.00 命令语义变更、官方手册术语 |
| [deep-research-report.md](research/gpt-reports/deep-research-report.md) | 第 6 组 | 版本谱系与中文化：正式名与发售、1.0→2.03 履历、汉化来源、Steam 版、与续作沿革 |

## 6.1 攻略与事件逻辑检查（用户资料向，未入库）

> 本组是「写《妹！生活 ～単色～》超详细攻略」的资料层；`docs/guide/` 当前未入库（用户资料），
> 数字以本组大纲与 `work/out/*_audit.md` 明细为准，不进规范文档。姊妹作 `imoto life` 的定稿/正文属另一仓库，不互通（AGENTS.md:29）。

| 文档 | 状态 | 内容 |
|---|---|---|
| [guide/00_说明与口径.md](guide/00_说明与口径.md) | **现行 · 先读** | 本作版口径文档（对齐姊妹作 00 层）：版本三口径（引擎 ver2.22 / 数据世代 2.00 / 副标题 Ver2.03）、S/T/G/U 证据分级、`CE<编号>@<pc>` 与 `map@…` 坐标、四命名空间、7 种判定图例 + 统一 8 列表、**opcode 契约**（op111 首真分档 / op121 compound 真实表 / op210 `param_status` / 页条件 AND）、异作剔除清单、写正文三条铁律；附本轮订正记录。写正文前先读 |
| [guide/00_outline.md](guide/00_outline.md) | 现行 · 大纲 | 14 章超详细攻略骨架，用 [有]/[核]/[缺] 标记每类资料可靠度；写作顺序见文末；已按 §3 订正 12 处实质错误 + 定级批量修正 |
| [guide/01_事件逻辑清晰度检查.md](guide/01_事件逻辑清晰度检查.md) | **现行 · 先读** | 6 路并行只读审计（A–F）汇总：**回答「各类事件逻辑是否说明清楚」——否**。183 子项 清楚 49 / 部分 85 / 缺 49；列出 **14 处**会写错正文的实质错误、3 个根因、写正文前最小工具链。**§9–§12 四波补链**、**§13 定稿与正文收口**、**§14 两篇前作攻略条件组并入**：§6 补链清单已全部交付，一手数据根齐备、三个根因解除、92 CE 进入条件 0/92→71/92、21「缺」收口为 0（5 升级 + 16 定案非玩法事件）、条件矩阵 30,870 行、日常命令流 21,863 行、rand 682 站点、消息表 3,357 条、3 个隐藏参数 v 号定位；**数据定稿 01–12 与 14 章正文已完成并独立验收**。剩 P2 实机复核（静态脚本无法解决）。明细在 `work/out/*_audit.md` 与各 `P0_*/P1_*_REPORT.md`（gitignored） |

**数据定稿层（唯一数字来源，12 文件 / 367 KB，统一 8 列表）**

| 文档 | 内容 |
|---|---|
| [guide/数据定稿/01_变量总表.md](guide/数据定稿/01_变量总表.md) | 302 var + 135 sys + 328 dbN 分组速查、别名、magic/offset、尺度与别名陷阱（v10-13 职业标志、v8 上限、3 隐藏参数、状态链变量、49 未命名保留槽） |
| [guide/数据定稿/02_时间与日程.md](guide/数据定稿/02_时间与日程.md) | 时钟 v4/5/6/8/99、一晚时序链、v99 三点、节日状态机（非固定公历）、行动耗时、v8 上限 |
| [guide/数据定稿/03_结局与相册.md](guide/数据定稿/03_结局与相册.md) | CE258 结局分支全表、4 职业 HAPPYEND、4 条 BADEND、结局标记写入点、**订正 #13**（v12 职业标志）、相册 16 格、title2/ending02 订正 |
| [guide/数据定稿/04_系统数值.md](guide/数据定稿/04_系统数值.md) | 职业参数 ev0 pc32-92、开局 5 问与 17 称号、3 隐藏参数阈值、AP/精力/金钱/状态链变量 |
| [guide/数据定稿/05_冲突与待验证.md](guide/数据定稿/05_冲突与待验证.md) | **14 处订正汇总**（含 #14 两篇前作攻略条件组）、**34 项 U 清单**、正文检查清单（唯一订正/U 状态源） |
| [guide/数据定稿/06_事件系统.md](guide/数据定稿/06_事件系统.md) | 350 CE 分区、92 自有 CE 进入条件（清楚37/部分39/⊘16/缺0）、16 非玩法事件、4,860 调用点、CE258 13 处调用方 |
| [guide/数据定稿/07_日常行动全表.md](guide/数据定稿/07_日常行动全表.md) | 27 日常 CE 槽数、一晚时序、行动数值、互斥/冷却、17 项 U、大纲 10 处漏收对照 |
| [guide/数据定稿/08_条件矩阵与阈值.md](guide/数据定稿/08_条件矩阵与阈值.md) | 30,870 条件实例分源统计、阈值速查、3 隐藏参数定位、op111 分档 vs op102 选项 vs 页条件 AND |
| [guide/数据定稿/09_商店与物品.md](guide/数据定稿/09_商店与物品.md) | 19 件商品、CE259/258/250 三段链、CE250 网购 4 档、物品栏变量与延迟链、**订正 #3/#5** |
| [guide/数据定稿/10_收集与CG.md](guide/数据定稿/10_收集与CG.md) | 收集品 20 格（写入 S 20/20、逐格条件 0/20 U）、相册 16 格、CG 29 条、状态链、结局后继承、**订正 #1/#8/#12** |
| [guide/数据定稿/11_随机与概率.md](guide/数据定稿/11_随机与概率.md) | 682 rand 站点、31 条 G 级绑定、两套概率矛盾、**「不 pin」铁律**、PRNG 4(+1) 项 inferred-not-proven |
| [guide/数据定稿/12_前作攻略条件组.md](guide/数据定稿/12_前作攻略条件组.md) | **两篇前作攻略条件组收录核实**：姊妹作判「⊘ 属前作剔除」→ 本作 S 级核实应 ✅收录；《早安骑》6 条 ↔ `CE251@430-442`（6 条单条件 op111 层叠=AND）、《浴室隐藏逆推 CG》3 条 ↔ `CE249@121/176/180`（`>200`→`>=200` ◐以脚本为准、媚药首真分档非 AND）；归属对照表（两边 `文件:行号`）+ 6 项 U；对应**订正 #14** |

**正文**

| 文档 | 内容 |
|---|---|
| [guide/妹生活超详细攻略_正文.md](guide/妹生活超详细攻略_正文.md) | **14 章叙述正文（已完成）**：第 0–13 章 / 67 小节 / 1189 行 / 98 KB；以定稿 01–12 为唯一数字来源；692+ 处 `CE@pc` 坐标、122 个不同 `varN`、132+ 处「资料不足/待核」；**14 处订正**全部落地（含 #13 `v12` 职业标志、#14 两篇前作条件组）；坐标可回指定稿；U/◐/— 项一律不编数字；成人内容中性技术表述 |

**资料集（百科层，`docs/攻略/妹生活_资料集/`）**

| 文档 | 内容 |
|---|---|
| [攻略/README.md](攻略/README.md) | 资料集（百科层）目录导读：九册制清单、S/T/G/U 证据分级定义、与 `docs/guide/` 的分工对照、版本口径与「社区攻略仅作 G 级交叉验证」约定 |
| [攻略/妹生活_资料集/00_总索引.md](攻略/妹生活_资料集/00_总索引.md) | 九册制百科总索引（按《资料集通用编写要求》编写）：01 系统与数值 / 02 物品 / 03 事件 / 04 角色 / 05 日程与结局 / 06 收集与CG / 99 内部ID与校验附录；全量剧透、S/T/G/U 证据分级、成人内容中性技术表述；本作无战斗/迷宫/DLC 故不设战斗册。数字来源同定稿 01–12，与 guide 正文互补（百科查表 vs 叙述攻略） |
| [攻略/妹生活_资料集/01_系统与数值.md](攻略/妹生活_资料集/01_系统与数值.md) | 系统数值百科：时间轴、行动力/精力/金钱、妹妹与哥哥五维数值模型、心情/睡眠/兴奋/敏感档位、开局问答、4 职业与 17 称号 |
| [攻略/妹生活_资料集/02_物品.md](攻略/妹生活_资料集/02_物品.md) | 物品百科：全部商品（茶饮/食品/药品/避孕/健身/安眠/游戏/情趣用品）的价格、效果、获取方式、上限；价格取 `CE250`/`CE245` 字面量 |
| [攻略/妹生活_资料集/03_事件.md](攻略/妹生活_资料集/03_事件.md) | 事件百科：平日/周末/晚餐/夜间/浴室/厕所/就寝/早晨的日常行动逐条，含进入条件、结果增量与随机分支；优先标 `CE212..303` / `ev N` |
| [攻略/妹生活_资料集/04_角色.md](攻略/妹生活_资料集/04_角色.md) | 角色数值模型：本作只有妹妹与哥哥（玩家）两名可交互角色 + 商店街 NPC 群像（无数值）；状态机与面板/统计含义；系列通用的「角色与队友」养成体系在本作不存在 |
| [攻略/妹生活_资料集/05_日程与结局.md](攻略/妹生活_资料集/05_日程与结局.md) | 一日循环结构、周循环、节日日程（非固定公历）与全部结局判定链 |
| [攻略/妹生活_资料集/06_收集与CG.md](攻略/妹生活_资料集/06_收集与CG.md) | 内裤收集 20 格、相册 16 个 `album_000..015` 资产（15 解锁格 + 背景框）、CG 29 条一览与结局演出 |
| [攻略/妹生活_资料集/99_内部ID与校验附录.md](攻略/妹生活_资料集/99_内部ID与校验附录.md) | 回查锚点：变量总表、CE/地图事件索引、脚本坐标、证据分级定义、U 项汇总与数据源；全册数值可回指到本册 |

> 口径与数字来源：`00_说明与口径.md` 为现行写作口径；**正文出现的每个数值都应能回指到 `数据定稿/01–12` 某表某行**；
> 当前订正/U 状态源 = `05_冲突与待验证.md`（14 处订正 / 34 项 U）；一手 S 级中间数据在 `work/out/`（gitignored，51 份产物）。
> 姊妹作 `imoto life` 的定稿/正文属**另一仓库**，不互通（AGENTS.md:29）；《早安骑》《浴室隐藏逆推 CG》经判定属**本作**、已由定稿 12 收录核实（S 级坐标 `CE251@430-442` / `CE249@121,176,180`），见 `00` §6、正文 §0.4、检查报告 §14。

## 6.2 Godot 迁移（进行中）

| 文件 | 状态 | 内容 |
|---|---|---|
| [GODOT_MIGRATION.md](GODOT_MIGRATION.md) | **现行 · P0/P1/P2 完成** | GDExtension 混合架构：Godot 负责窗口/渲染/音频/UI，Rust 保留 `wolf-format`/`wolf-vm`/`wolf-save`/`wolf-game`。含工程布局、`build/smoke/parity-godot.sh`、标题像素对照、输入/读档/文字校准与长程 parity 结果、剩余缺口 |
| [../godot/](../godot/) | 现行 | Godot 4.7 工程（`project.godot`、`main.tscn`、`GameView.gd`、`WolfKeys/WolfText`、headless smoke/parity） |
| [../crates/wolf-gdext/](../crates/wolf-gdext/) | 现行 | `WolfGame` GDExtension 类：每帧返回动态 sprites/texts/overlays/sounds；T13 后玩法前端不再请求或绘制地图瓦片，核心 `Game::tile_quads()` 与 CLI `capture --map` 仅保留取证/诊断用途 |
| [GODOT_DEBUGGING.md](GODOT_DEBUGGING.md) | 现行 | 操作/显示/对话缺失的排查手册：输入契约、`--log-input/--log-events/--log-messages`、截图 diff、字形覆盖、存档 fixture 坑 |

## 7. 翻译目录

| 文件 | 内容 |
|---|---|
| [translations/README.md](translations/README.md) | TSV 目录格式、`[msg]`/`[choice]` 作用域键、生成工具 |
| [translations/en.tsv](translations/en.tsv) / [en.full.tsv](translations/en.full.tsv) / [ja.tsv](translations/ja.tsv) | 演示/完整语言目录与日文回填表 |

## 8. 参考实现

| 目录 | 内容 |
|---|---|
| [vendor/uberwolf-ref/](vendor/uberwolf-ref/) | 第三方 WOLF 数据解码参考（DXLib / UberWolfLib / dw2_header.py / dw8_verify.py）。**只读参考，不参与构建** |

## 9. 工具与工作区产物

| 位置 | 说明 |
|---|---|
| `tools/env.sh` / `env.ps1` / `setpath.ps1` | 环境（含 `GHIDRA_INSTALL_DIR`/`GHIDRA_JAVA_HOME`） |
| `tools/package.sh` / `package.ps1` / `package/` | 打包脚本与模板（NSIS 安装器：`package/ImoutoLife.nsi.in` + `package/render_nsis.py`） |
| [../tools/pack_gemini_review.py](../tools/pack_gemini_review.py) | 云端 Gemini 只读审查打包器：切 ≤16 MB 单包 + 附审查说明与 sha256 清单 |
| [../tools/pack_review_bundle.py](../tools/pack_review_bundle.py) | 云端沙箱**可构建**包打包器：额外带 `work/Data` 与离线依赖树 |
| [../tools/split_review_bundle.py](../tools/split_review_bundle.py) | 沙箱包按 9 MB 分片并生成还原脚本 |
| [../tools/re/wolfpe.py](../tools/re/wolfpe.py) | 只读 PE 探针（facts/strings/xref/disasm） |
| [../tools/re/ghidra/README.md](../tools/re/ghidra/README.md) | Ghidra headless 反编译脚本（DumpAll/DumpByAnchor） |
| `work/Data` | 解包后的本作数据，176 MB，**gitignore**，测试必需 |
| `work/out/re_all/` | 4,375 个 ≥64B 函数的 Ghidra C 伪码 + index.tsv（27 MB，未入库，复核用） |
| `work/out/ghidra/` | 已于 2026-11-04 清理（166 MB）；需要时用 `tools/re/ghidra` 从原版 `Game.exe` 重新 import（约 4 分钟） |
| `work/out/_archive/` | 历史提交信息（`commit_messages/`）与一次性探针脚本（`scripts/`）归档，未入库 |
| `work/out/shot_metrics/` | 截图度量脚本与标注图（未入库，SCREENSHOT_METRICS 的复现材料） |

## 10. 被引用但本仓库缺失的文档

以下路径在**代码注释**里被引用，但本仓库没有对应文件（沿用上一作仓库的文档名，未随仓库复制过来）。
新会话不要以为它们存在；需要时从上一作仓库取，或按 [ENGINE_BEHAVIOR.md](ENGINE_BEHAVIOR.md) 重写：

`ARCHITECTURE.md`、`OPCODE_SPEC.md`、`OPCODE_101/102/112/124/210_RETURN/250/290.md`、
`FORMAT_SPEC.md`、`SAVE_SPEC.md`、`TEXT_SPEC.md`、`BATTLE.md`、`HSCENE.md`、`ENGINE_EVENTS.md`、
`MAP_AUDIT.md`、`ASSET_AUDIT.md`、`AUDIO.md`、`M1_CLOSURE.md`、`HANDOFF_M3.md`、`HANDOFF_M4.md`、`PLAN.md`、`UNVERIFIED.md`。

> 已有对应实现说明的：`OPCODE_220_SAVE.md` → 见 §5.1；`OPCODE_122.md` → 见 §5.1。

## 11. 文档维护规则

- 新里程碑说明命名 `M<N>_<主题>.md`，新专题审计放 `docs/` 根，并**在本索引登记**。
- 完成且被取代的文档不删除：移入 `docs/archive/`（审查报告放 `docs/archive/reviews/`），
  在 [archive/README.md](archive/README.md) 登记原因与替代文档，并更新本索引。
- 现行代码审查报告统一放 `docs/reviews/`，同一时间只保留一份现行总报告；
  新报告须在 [reviews/README.md](reviews/README.md) 标注轮次与缺陷编号范围。
- 云端只读复审按轮次成目录 `docs/reviews/cloud_audit_<日期>_<基线>/`；
  **最新一轮留在 `docs/reviews/`，更早的整轮移入 `docs/archive/reviews/`**，
  归档时在文件顶部加「归档说明」块，不改写原始记录。
- 会改变玩家可见行为或 verify 数值的改动：同时更新 [HANDOFF_M0.md](HANDOFF_M0.md) §11.1、
  [HANDOFF_PROGRESS.md](HANDOFF_PROGRESS.md) 末尾新增一条，以及本索引对应条目状态。
- 反编译/实测证据进 `docs/re/`；调研背景进 `docs/research/`；两者都不与规范文档混放。
- 攻略正文与资料层（`docs/guide/`、`docs/攻略/`）自成一格，内部互链，**不与工程规范混放**；
  `docs/攻略文档/` 是本地私有目录（gitignore），不得作为事实源引用。
- **本索引必须覆盖仓库里每一份 `.md`**（零孤儿）：新增文档要在此登记，
  移走的要更新链接；改完跑一次链接体检，确认无断链。
- **审查产物不进仓库根**：云端审查报告、只读复审产物一律落到 `docs/reviews/` 或
  `docs/archive/reviews/`；仓库根只保留 `README.md`、`AGENTS.md` 等入口文件。
