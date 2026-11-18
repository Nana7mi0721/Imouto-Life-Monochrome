# 代码审查报告目录（docs/reviews/）

本目录存放**面向当前工程的代码审查报告**。审查报告是缺陷台账与修复依据，不是引擎规范；
引擎行为以 `docs/ENGINE_BEHAVIOR.md` 与 `docs/re/` 的实测证据为准。

## 现行报告

| 文件 | 状态 | 范围 |
|---|---|---|
| [CODE_REVIEW_4ROUND.md](CODE_REVIEW_4ROUND.md) | **现行 · 唯一审查事实源** | 第一至四轮完整版（2026-11）：报告 §六基线 BUG-20..24；第一轮 BUG-25..35；第二轮 BUG-36..40；第三轮 BUG-41..46；第四轮 BUG-47..48；含系统性架构建议 |

## 专项审计

| 文件 | 状态 | 范围 |
|---|---|---|
| [T13_UI_REGRESSION_AUDIT.md](T13_UI_REGRESSION_AUDIT.md) | 现行 · UI/命中盒专项 | 2026-11-12 用户 15 项截图缺陷逐项复核；91 passed / 2 ignored，中央对话双源仍开放 |

## 云端只读审查轮次

云端复审按轮次成目录。**同一时间只保留最新一轮在 `docs/reviews/`**，
更早的整轮移入 `docs/archive/reviews/` 并在文件顶部加「归档说明」。

| 轮次 | 位置 | 状态 | 基线 |
|---|---|---|---|
| 2026-11-18 | [cloud_audit_2026-11-18_e716f08/](cloud_audit_2026-11-18_e716f08/) | **现行 · 最新** | 基线 `e716f08`；目前只交付了执行摘要，其余分册待补 |
| 2026-11-17 | [../archive/reviews/cloud_audit_2026-11-17_2411996/](../archive/reviews/cloud_audit_2026-11-17_2411996/) | 已归档 · 被取代 | `2411996` |

一轮**完整**的云端审查包含：`00_EXECUTIVE_SUMMARY.md`（执行摘要与发布结论）、
`01_REQUIREMENT_TRACEABILITY.csv`（需求→实现追溯矩阵）、
`02_FINDINGS.md`（缺陷与开放风险）、`03_PERFORMANCE.md`（性能与内存）、
`04_ASSETS_AND_PACKAGING.md`（素材与封包）、`05_DEAD_CODE_REACHABILITY.md`（死代码）、
`06_TEST_COVERAGE_AND_SKIPS.md`（覆盖率与假绿风险）、`07_MAINTAINABILITY.md`（可维护性）、
`08_UNVERIFIED_CLOUD.md`（云端环境无法验证项）、`09_REPRODUCTION_LOGS/`（复现日志）。

> 11-17 与 11-18 两轮的 `01_REQUIREMENT_TRACEABILITY.csv` **内容完全相同**
> （`md5 007ea804…`，`git show HEAD` 可复核），因此只随 11-17 轮归档一次。

云端容器**没有** Rust 工具链、Godot 与 `work/Data`，因此这些轮次的结论多为
`E1（静态代码路径可证明，未运行）`；凡标 `UNVERIFIED_ENV` 的项必须在本机复验，
不要直接当成已修或已坏。

## 轮次与缺陷编号

| 轮次 | 缺陷编号 | 主题 |
|---|---|---|
| 报告 §六基线 | BUG-20..24 | ActionKey/Parallel 分离、`install_map` 直接自协程、选项框外点击、`CSelf5..9`、Op300（**与下行的旧台账同号不同义**） |
| 旧台账（2026-11-11） | BUG-20..24 | `docs/HANDOFF_PROGRESS.md` 深水区审计遗留项（滚轮、鼠标出界、character_state、全屏特效、按键连发） |
| 第一轮 | BUG-25..35 | 核心架构与调度器、变量寻址、输入、存档、文本层 |
| 第二轮 | BUG-36..40 | 全量字节码指令语义（176 / 140 / 220..222 / 130 / 151）与前端开销 |
| 第三轮 | BUG-41..46 | 真实二进制资产 + `wolf-gdext` / `GameView.gd` 跨语言管线 |
| 第四轮 | BUG-47..48 | 图层几何、`Opcode 124` 复合算子、`PictureAction::Erase` 淡出 |

## 阅读注意

- 报告中的行号对应其写作时的快照；修复后行号会漂移，**以符号名和报告描述的行为为准**。
- 报告的部分结论已被实测修正（例如 `ENGINE_RESTART` 取值、`Opcode 121` flags、
  `Opcode 151` 首参、blend 编码）。差异清单与证据见
  [../HANDOFF_DEEP_REVIEW_FIX.md](../HANDOFF_DEEP_REVIEW_FIX.md) §5。
- 第一、二轮单行本已被现行报告收录，归档在
  [../archive/reviews/CODE_REVIEW_1_2ROUND_superseded.md](../archive/reviews/CODE_REVIEW_1_2ROUND_superseded.md)，
  仅作证据链保留，不要再作为现行依据。
- 新审查报告命名建议 `CODE_REVIEW_<轮次或日期>.md`，并在 `docs/README.md` 登记；
  被取代的旧报告移入 `docs/archive/reviews/`。
- 云端复审目录命名 `cloud_audit_<YYYY-MM-DD>_<基线短哈希>/`；
  归档目录命名保持原样，便于按轮次回溯。
- 云端轮次报告里的缺陷编号（`F-01` 形式）与本目录的 `BUG-xx` 台账**不是同一套编号**，
  引用时务必写明出处（轮次 + 编号），不要把 `F-xx` 当成 `BUG-xx`。
