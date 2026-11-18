# docs/research — 调研与实证资料

这里放**一手/二手调研资料**，不是当前实现的事实源。

- [M7_PRNG.md](M7_PRNG.md) — PRNG 实证：Game.dat 的 static-random 块是预生成表，`random_a/b` 是生成器输出 K1/K2 而非种子；姊妹作 28,936/28,936 字节全等，本作前 1,055 字节全等、之后为汉化补丁改写/损坏，按原字节消费。结论已在 M3 落地。
- 6 份 GPT 深度调研报告与前置问题组在 [gpt-reports/](gpt-reports/)，其中若干条已被本作数据实测推翻，**采信/推翻清单见 [../HANDOFF_M0.md](../HANDOFF_M0.md) §7**。

### gpt-reports 文件对照表

> **文件名里的 `(1)`…`(5)` 只是下载批次序号，不代表问题组编号**，按下表对号入座。

| 文件 | 问题组 | 主题 |
|---|---|---|
| [GPT_RESEARCH_GROUPS.md](gpt-reports/GPT_RESEARCH_GROUPS.md) | 前置 | 6 个问题组的提问原文；每组规定固定 7 段报告格式与「事实 / 推测」分界规则 |
| [deep-research-report (4).md](<gpt-reports/deep-research-report (4).md>) | 第 1 组 | 日常循环与时间/日程/行动力：主角四种身份、行动力上限与消耗、时间段划分 |
| [deep-research-report (5).md](<gpt-reports/deep-research-report (5).md>) | 第 2 组 | 妹妹状态与人际数值：状态面板字段、警戒度与性興味、阈值事件、状态图标 |
| [deep-research-report (2).md](<gpt-reports/deep-research-report (2).md>) | 第 3 组 | H 场景系统、相册与结局：场景分类与进入条件、操作方式、结局数量 |
| [deep-research-report (3).md](<gpt-reports/deep-research-report (3).md>) | 第 4 组 | UI、操作、设置与存档：按键与引擎行为，以及公开资料查不到的项清单 |
| [deep-research-report (1).md](<gpt-reports/deep-research-report (1).md>) | 第 5 组 | WOLF RPG Editor 2.00 世代引擎事实：版本发布时间线、「基本システム Ver2.20」模板、2.00 命令语义变更、官方手册术语 |
| [deep-research-report.md](gpt-reports/deep-research-report.md) | 第 6 组 | 版本谱系与中文化：正式名与发售、1.0→2.03 履历、汉化来源、Steam 版、与续作沿革 |

> 无后缀的那份是**第 6 组**，不是第 1 组。
