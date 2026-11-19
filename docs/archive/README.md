# 归档区（docs/archive/）

本目录存放**已完成、已被取代或仅供追溯**的文档。归档不等于删除：保留证据链，
但其中的数字、行号、结论都**不再代表当前工程事实**。

## 归档清单

| 文件 | 归档原因 | 现行替代 |
|---|---|---|
| [HANDOFF_NEXT_AGENT.md](HANDOFF_NEXT_AGENT.md) | 2026-11-11 的 POST_DEEPSEEK 19 项修复交接，任务已完成并闭环 | [../HANDOFF_M0.md](../HANDOFF_M0.md)（项目现状）、[../HANDOFF_PROGRESS.md](../HANDOFF_PROGRESS.md)（历史日志）、[../HANDOFF_DEEP_REVIEW_FIX.md](../reviews/HANDOFF_DEEP_REVIEW_FIX.md)（当前修复交接） |
| [reviews/CODE_REVIEW_1_2ROUND_superseded.md](reviews/CODE_REVIEW_1_2ROUND_superseded.md) | 第一、二轮审查单行本（BUG-25..40），已被第一至四轮总报告完整收录 | [../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md) |

### 2026-11-18 归位与归档（文档整理轮）

| 文件 | 归档原因 | 现行替代 |
|---|---|---|
| [reviews/cloud_audit_2026-11-17_2411996/](reviews/cloud_audit_2026-11-17_2411996) | 2026-11-17 云端只读全量审查（基线 `2411996`）的 10 份产物，已被次日同系列审查取代 | [../reviews/cloud_audit_2026-11-18_e716f08/](../reviews/cloud_audit_2026-11-18_e716f08)（同系列下一轮）、[../AUDIT_2411996_FIX_REPORT.md](../reviews/AUDIT_2411996_FIX_REPORT.md)（该轮处置） |
| [reviews/CODE_REVIEW_1c76dcc_superseded.md](reviews/CODE_REVIEW_1c76dcc_superseded.md) | Gemini 全量静态代码审查 `1c76dcc` 的原始报告，缺陷已全部处置 | [../GEMINI_REVIEW_1c76dcc_FIX_REPORT.md](../reviews/GEMINI_REVIEW_1c76dcc_FIX_REPORT.md)（处置报告）、[../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md)（现行唯一审查事实源） |
| [reviews/CODE_REVIEW_cb5ecb4_141c524_superseded.md](reviews/CODE_REVIEW_cb5ecb4_141c524_superseded.md) | 第一、二轮静态代码审查汇总报告，已被第一至四轮总报告收录 | [../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md) |
| [reviews/code_review_9a817e4.md](reviews/code_review_9a817e4.md) | `1c76dcc..9a817e4` 区间的只读静态审查报告，处置已完成 | [../REVIEW_9a817e4_FIX_REPORT.md](../reviews/REVIEW_9a817e4_FIX_REPORT.md)（处置报告）、[../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md) |
| [reviews/code_review_1a1741cc_rng_ux.md](reviews/code_review_1a1741cc_rng_ux.md) | `1a1741cc` 的随机机制核验与交互/存档增强方案，方案已落地 | [../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md)、[../LIVE_PLAY_FIX_REPORT.md](../reviews/LIVE_PLAY_FIX_REPORT.md) |
| [reviews/code_review_46de4eb_ux_bugs.md](reviews/code_review_46de4eb_ux_bugs.md) | `46de4eb` 的完整代码审查与新增 Bug / 定制改造报告，已被后续轮次覆盖 | [../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md) |
| [reviews/code_review_a2a618d.md](reviews/code_review_a2a618d.md) | `a2a618d` 的完整代码审查报告，已被后续轮次覆盖 | [../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md) |
| [reviews/ux_plan_1a1741cc.md](reviews/ux_plan_1a1741cc.md) | `1a1741cc` 四项待改项的代码实现方案，对应改动已全部落地 | [../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md)、[../LIVE_PLAY_FIX_REPORT.md](../reviews/LIVE_PLAY_FIX_REPORT.md) |
| [reviews/live_play_issues_2026-11-15.md](reviews/live_play_issues_2026-11-15.md) | 实机测试问题排查与 E/F 项修复报告，剩余项已由后续报告闭环 | [../LIVE_PLAY_FIX_REPORT.md](../reviews/LIVE_PLAY_FIX_REPORT.md) |
| [reviews/imouto_life_code_review_and_patch_report.md](reviews/imouto_life_code_review_and_patch_report.md) | 早期只读代码审查与补丁方案报告，缺陷台账已被总报告取代 | [../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md) |
| [reviews/imouto_life_rebuild_fixes_and_full_audit.md](reviews/imouto_life_rebuild_fixes_and_full_audit.md) | 重构问题截图纠因与全量代码审查报告，已被审计轮汇总取代 | [../AUDIT_REBUILD_FIX_REPORT.md](../reviews/AUDIT_REBUILD_FIX_REPORT.md) |
| [HANDOFF_T12_PATCH_AND_LEDGER.md](HANDOFF_T12_PATCH_AND_LEDGER.md) | 2026-11-13 的 T12 性能补丁与双台账收口会话存档，任务已闭环 | [../HANDOFF_M0.md](../HANDOFF_M0.md)、[../AUDIT_REBUILD_FIX_REPORT.md](../reviews/AUDIT_REBUILD_FIX_REPORT.md) |
| [ROUND_T12_AND_SCREENSHOT_FIX_REPORT.md](ROUND_T12_AND_SCREENSHOT_FIX_REPORT.md) | T12 收口与实机截图复核报告，已被后续轮次取代 | [../AUDIT_REBUILD_FIX_REPORT.md](../reviews/AUDIT_REBUILD_FIX_REPORT.md)、[../LIVE_PLAY_FIX_REPORT.md](../reviews/LIVE_PLAY_FIX_REPORT.md) |
| [ui_and_interaction_diagnosis_report.md](ui_and_interaction_diagnosis_report.md) | Godot 复刻版 UI 与交互问题排查方案，历史诊断材料 | [../reviews/CODE_REVIEW_4ROUND.md](../reviews/CODE_REVIEW_4ROUND.md)、[../TASKS_REMAINING_BUGS.md](../reviews/TASKS_REMAINING_BUGS.md) |

## 使用规则

- 需要引用历史结论时，先确认现行文档是否已覆盖；**不要从归档文档直接抄数字或行号**。
- 归档文档不删除；如需更正归档内容，只在文件顶部加“归档说明”，不改写原始记录。
- 新归档项的命名：交接类 `HANDOFF_<主题>.md`；审查类放 `reviews/`，文件名带 `_superseded` 或轮次。
- 云端审查这类**成组产物**按轮次建目录（`reviews/<主题>_<日期>_<基线>/`），
  整组进归档时同样只保留一份现行轮次在 `docs/reviews/` 下。
