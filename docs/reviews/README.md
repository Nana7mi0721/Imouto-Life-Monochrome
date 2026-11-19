# 代码审查与修复报告（docs/reviews）

本目录存放项目历次系统性代码审查（Code Review）、深度审计任务书、修复落地交接与专项问题处置报告。

## 1. 核心审查事实源与修复交接

| 文件 | 状态 | 范围与内容 |
|---|---|---|
| [CODE_REVIEW_4ROUND.md](CODE_REVIEW_4ROUND.md) | **现行 · 主审查源** | 第一至四轮完整审查（BUG-20..24 基线，第一轮 BUG-25..35，第二轮 BUG-36..40，第三轮 BUG-41..46，第四轮 BUG-47..48 与架构建议） |
| [HANDOFF_DEEP_REVIEW_FIX.md](HANDOFF_DEEP_REVIEW_FIX.md) | **现行 · 完成交接** | 深度审查 BUG-25..48 的 T0–T11 落地细节、反编译证据与最终验证结果 |
| [TASKS_REMAINING_BUGS.md](TASKS_REMAINING_BUGS.md) | 现行 · 执行记录 | 缺陷修复任务卡分工、写作用域与执行状态台账 |
| [GEMINI_FULL_AUDIT_GUIDE.md](GEMINI_FULL_AUDIT_GUIDE.md) | 现行 · 审查指南 | 全量只读审计任务书（需求闭环、正确性、性能、素材封包检查标准） |

## 2. 轮次修复报告（Fix Reports）

| 文件 | 状态 | 核心处置内容 |
|---|---|---|
| [AUDIT_2411996_FIX_REPORT.md](AUDIT_2411996_FIX_REPORT.md) | 现行 · 修复 | 基线 `2411996` 审查处置：动作键门控、移动区间、资源缓存与纯档重置 |
| [AUDIT_REBUILD_FIX_REPORT.md](AUDIT_REBUILD_FIX_REPORT.md) | 现行 · 修复 | 重建审计轮：截图缺陷修复、RNG/缓存/键位与文本塑形落地 |
| [GEMINI_REVIEW_1c76dcc_FIX_REPORT.md](GEMINI_REVIEW_1c76dcc_FIX_REPORT.md) | 现行 · 修复 | 基线 `1c76dcc` 审查处置：人名牌缓存 P1、行动力数字对齐与事件闭环 |
| [REVIEW_9a817e4_FIX_REPORT.md](REVIEW_9a817e4_FIX_REPORT.md) | 现行 · 修复 | 基线 `9a817e4` 审查处置：名牌缓存、格子条对齐、夜间点击热区 |
| [LIVE_PLAY_FIX_REPORT.md](LIVE_PLAY_FIX_REPORT.md) | 现行 · 实机 | 实机测试断言修复：开场穿透取消、窗口图标、音频通道管理 |
| [T13_UI_REGRESSION_AUDIT.md](T13_UI_REGRESSION_AUDIT.md) | 现行 · UI专项 | 用户 15 项截图缺陷逐项复核与命中判定测试 |

## 3. 云端只读审查轮次

- 最新现行轮次：[cloud_audit_2026-11-18_e716f08/](cloud_audit_2026-11-18_e716f08/)（基线 `e716f08`）
- 历史已归档轮次：[../archive/reviews/](../archive/reviews/README.md)（含 `cloud_audit_2026-11-17_2411996/`）
