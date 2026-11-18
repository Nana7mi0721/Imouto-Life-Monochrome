# Gemini 云端全量审查指南

> 项目：《妹！生活 ～単色～》Rust + Godot 重写
>
> 审查方式：**只读代码审计**。默认不修改源码、不提交、不创建 PR、不删除文件。
>
> 本文是给云端 Gemini 的任务书。请先完整阅读，再开始审查。

---

## 0. 直接使用的任务提示

可以把下面这段作为 Gemini 的首条任务：

```text
请对云端拉取的 Imouto Life 仓库做只读全量审查。
严格遵循仓库里的 docs/GEMINI_FULL_AUDIT_GUIDE.md。
先记录 git rev-parse HEAD、分支、Rust 版本和运行环境，再按指南分阶段审查。
不要修改源码，不要提交，不要覆盖或删除任何存档，不要用推测代替证据。
最终必须交付需求闭环矩阵、缺陷清单、性能报告、素材/封包报告、死代码可达性报告、
测试有效性报告，以及“云端无法验证”的明确清单。
每条 P0/P1 结论都必须有文件/行号、代码路径、复现命令或测试证据；
没有运行证据的内容只能标为候选或待验证。
```

---

## 1. 审查目标与完成定义

本次审查不只找“代码写得对不对”，还要回答以下问题：

1. `docs/HANDOFF_M0.md`、`docs/HANDOFF_PROGRESS.md` 和各专题报告提到的缺陷、
   用户裁定与优化项，是否真的在当前代码中落地。
2. 已声称修复的项目是否仍存在回归、边界条件或未被测试覆盖的分支。
3. 是否存在尚未发现的功能、状态机、输入、存档、渲染、音频或资源生命周期缺陷。
4. 是否存在可感知的性能问题、内存增长、重复分配、重复 I/O 或 GPU/CPU 浪费。
5. 是否存在游戏运行中永远不可达的代码、测试残留、模板代码、旧版重复实现。
6. 是否存在被封包但游戏中永远不会使用的素材、字体、地图、战斗模板或其他资源。
7. 代码边界是否清晰，是否容易理解和维护，注释与实现是否一致。
8. 测试是否真的执行了断言，还是在缺数据、缺夹具时静默 `return` 后显示“通过”。
9. 当前是否具备可信的发布路径，尤其是 Godot 正式导出、存档安全和第三方插件隔离。
10. 对发现的问题给出按风险排序、可验证、不过度重构的修复建议。

完成定义：

- 所有 tracked handoff 中可识别的缺陷/要求均进入需求矩阵，不允许“看过但没记录”。
- 所有 P0/P1 结论都有独立证据，不只引用旧报告。
- 明确区分“已证实缺陷”“高可信风险”“待实机验证假设”“误报/设计取舍”。
- 明确列出云端环境无法验证的项目，不用“未发现问题”替代“无法验证”。
- 给出可执行的后续验证顺序，而不是只给泛泛建议。

---

## 2. 云端仓库边界

### 2.1 master 分支中有什么

云端拉取 `master` 后，主要可见内容为：

- `crates/`：Rust workspace。
- `godot/`：Godot 工程、GDScript、测试和第三方开发插件。
- `docs/`：交接、里程碑、审查、逆向证据、打包说明。
- `tools/`：构建、冒烟、打包、审计脚本。
- `AGENTS.md`、`README.md`、`Cargo.toml`、`Cargo.lock`、`rust-toolchain.toml`。

截至本指南编写，workspace 实际包含 **9 个 crate**：
`wolf-format`、`wolf-save`、`wolf-vm`、`wolf-render`、`wolf-audio`、
`wolf-game`、`wolf-cli`、`wolf-launcher`、`wolf-gdext`。
`AGENTS.md` 里的“8 个 crate”是历史口径，以 `Cargo.toml` 为准。

开始时必须执行并记录：

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git log -5 --oneline
rustc --version
cargo --version
uname -a
```

后续所有 finding 都应以本次 `HEAD` 为准。若拉取新提交，必须重新核对受影响结论。

### 2.2 master 中没有、不能假设存在的内容

以下路径被 `.gitignore` 或当前工作流排除，云端干净克隆通常没有：

- `work/Data/`：解包后的游戏数据，约 176 MB。
- `work/out/`：本地构建、截图、性能日志、探针和审查产物。
- `prt sc/`、`ptr_sc/`、`重构游戏问题截图/`：实机截图。
- `原版游戏截图.zip`、`重构游戏问题截图.zip`。
- `godot/bin/wolf_gdext.dll`、`target/`、Godot `.godot/` 导入缓存。
- 根目录部分 `review_*.md`、`code_review_*.md` 和用户方案文件未必已跟踪；
  是否可见以 `git ls-files` 为准。

因此：

- 不能因为云端没有 `work/Data` 就判定项目缺数据或测试失败。
- 不能把“数据测试跳过”写成“数据测试通过”。
- 不能引用本地截图路径作为已复核证据，除非用户另行提供素材包。
- 不能凭旧报告中的图片描述臆造视觉结论。

### 2.3 可选：`assets` 分支或用户提供的素材包

仓库说明曾记录远端存在独立 `assets` 分支，包含解包数据、逆向材料、截图和证据。
只有用户明确授权且云端有权限时才使用。建议单独克隆，不要切坏 master 工作树：

```bash
git clone --single-branch --branch assets --depth 1 \
  <REPOSITORY_URL> ../imouto-life-assets
```

使用前记录：

```bash
git -C ../imouto-life-assets rev-parse HEAD
head -n 20 ../imouto-life-assets/MANIFEST.tsv 2>/dev/null || true
```

如果无法访问 `assets` 分支：

- 不执行任何“需要真实数据”的结论性验证。
- 在最终报告的“云端未验证”章节中明确记录。
- 可以请求用户提供只读数据包，但不要从不明来源下载或重新分发游戏素材。

### 2.4 平台限制

当前 Godot 构建/冒烟脚本和 `.gdextension` 配置主要面向 Windows：

- `tools/build-godot.sh` 复制 `wolf_gdext.dll`。
- `tools/parity-godot.sh` 使用 `cygpath` 和 `.exe`。
- `tools/env.sh` 写死本地 Windows/MSYS 路径。

如果云端是 Linux：

- **不要 `source tools/env.sh`**，否则会注入无效路径和本地镜像设置。
- 可以正常审查 Rust，但 Godot DLL、Windows 启动器和部分打包脚本只能静态审查。
- 不要为了“让脚本在 Linux 跑起来”而改源码；除非用户明确要求。
- 无法执行 Windows/Godot 运行时，必须在报告中标注 `UNVERIFIED_ENV`。

### 2.5 非破坏性红线

- 不修改源码，不提交，不创建分支或 PR。
- 不执行会删除、移动、重打包或覆盖用户文件的命令。
- 不运行针对真实 `Save/` 的保存测试。
- 不把 `work/Data` 或 `assets` 分支内容复制到公开输出。
- 不在报告中暴露私人路径、账号信息或与原作无关的敏感字符串。
- 如需实验性补丁，使用独立 scratch clone；报告中明确“未应用”。

---

## 3. 事实源与阅读顺序

### 3.1 事实优先级

发生冲突时按以下顺序裁决：

1. **当前源码和实际运行结果**。
2. **当前测试与基线数据**。
3. `docs/HANDOFF_M0.md` §11.1 的当前状态摘要。
4. `docs/HANDOFF_PROGRESS.md` 的最新记录。
5. 各专题 fix report。
6. 原始审查报告和历史里程碑。

文档是线索，不是事实。代码注释也可能过期；测试名称也可能沿用旧语义。

### 3.2 最低阅读清单

按以下顺序阅读，避免一开始陷入全部历史日志：

1. `AGENTS.md`
2. `README.md`
3. `docs/README.md`
4. `docs/HANDOFF_M0.md`，重点是 §3、§4、§8、§9、§11
5. `docs/HANDOFF_PROGRESS.md`，先读 2026-11-12 以后部分，再向前追溯
6. `docs/TASKS_REMAINING_BUGS.md` 的 §0 和 §1 历史状态
7. `docs/reviews/CODE_REVIEW_4ROUND.md`
8. `docs/HANDOFF_DEEP_REVIEW_FIX.md`
9. `docs/archive/HANDOFF_T12_PATCH_AND_LEDGER.md`
10. `docs/LIVE_PLAY_FIX_REPORT.md`
11. `docs/M25_LIVE_UX.md`
12. `docs/REVIEW_9a817e4_FIX_REPORT.md`
13. `docs/GEMINI_REVIEW_1c76dcc_FIX_REPORT.md`
14. `docs/AUDIT_REBUILD_FIX_REPORT.md`
15. `docs/M4_PERF.md`
16. `docs/GODOT_MIGRATION.md`
17. `docs/GODOT_DEBUGGING.md`
18. `docs/ENGINE_BEHAVIOR.md` 与 `docs/re/*.md`
19. `docs/ASSETS.md`、`docs/PACKAGING.md`、`docs/PROJECT_ASSETS.md`
20. 相关 `docs/M3_*`、`docs/M4_*`、`docs/M6_*`、`docs/M7_*`

### 3.3 已知过期或容易误读的文档

以下内容不要直接当现状：

- `docs/HANDOFF_M0.md` 开头仍保留“只有 docs/、没有代码”的初始背景；
  当前状态以 §11.1 为准。
- `README.md` 对测试全绿的描述可能落后于当前基线；以实际运行和
  `HANDOFF_M0.md` §11.1 为准。
- `docs/M4_PERF.md` 中旧机器的毫秒数据只作方法示例，不能跨机器比较。
- `docs/M4_SETTINGS_UI.md` 的 tenths/1/10 UI 缩放段落属于历史；
  当前实现已撤销相关补偿。
- `docs/GODOT_MIGRATION.md` 的“已知缺口”和 P3 导出状态是阶段快照。
- `docs/TASKS_REMAINING_BUGS.md` §1 之后是历史任务快照，§0 才是完成记录。
- `docs/M25_LIVE_UX.md` 的测试计数是当时快照，后续继续增加了回归。
- `docs/PROJECT_ASSETS.md` 的“停止重构”是历史决策，不代表当前项目目标。
- `docs/M3_TITLE_UX.md` 的读档取消软锁等旧缺口可能已经修复。
- `docs/REFERENCE.md` 的截图数量和路径可能已变化。
- `docs/GODOT_DEBUGGING.md` 对 `Esc` 的描述是简化版；应结合
  `GameView.gd` 与 `game.rs` 的当前分支。
- 代码注释里引用的 `FORMAT_SPEC.md`、`TEXT_SPEC.md`、`HSCENE.md` 等文档
  可能并不存在，见 `docs/README.md` 的“缺失文档”章节。
- 历史审查报告中的行号会漂移，应以函数名、符号名和当前 `rg` 结果定位。
- `docs/M4_PERF.md` 示例使用相对 `work/Data`；当前数据测试应使用绝对路径。
- `m14_visual_regression` 的像素/图集数字在历史报告里可能已重录，
  以当前测试源码中的基线为准。

### 3.4 缺陷编号冲突

项目存在两套同号不同义的 `BUG-20..24`：

- `docs/HANDOFF_PROGRESS.md` 的 2026-11-11 历史台账。
- `docs/reviews/CODE_REVIEW_4ROUND.md` §六。

引用时必须写明来源，例如“历史台账 BUG-21”或“四轮审查 §六 BUG-21”。
不得把两套编号合并统计。

---

## 4. 基线、测试与证据等级

### 4.1 记录环境

报告中必须记录：

- exact commit SHA
- 分支
- OS / CPU / 内存
- Rust / Cargo 版本
- 是否使用 `assets` 分支
- 数据根绝对路径及其哈希/来源
- Godot 版本（如使用）
- 是否运行 release/debug

### 4.2 云端最小验证

不依赖游戏数据也应执行：

```bash
cargo fmt --all -- --check
git diff --check
cargo check -q --workspace
cargo test -q --workspace --no-fail-fast
cargo test -q --workspace --no-run
```

如果存在既有失败，先建立“基线失败集合”，再判断是否有新增问题。
不要把当前环境无法编译、缺系统依赖或 Windows-only 问题直接归咎于业务代码。

### 4.3 数据驱动验证

只有数据根存在且为可写副本时才执行：

```bash
export AUDIT_DATA=/absolute/path/to/writable/Data

WOLF_DATA_ROOT="$AUDIT_DATA" cargo test -q --workspace --no-fail-fast
WOLF_DATA_ROOT="$AUDIT_DATA" cargo test -q -p wolf-format --test m3_asset_refs
WOLF_DATA_ROOT="$AUDIT_DATA" cargo test -q -p wolf-game --test m3_perf_baseline -- --nocapture
WOLF_DATA_ROOT="$AUDIT_DATA" cargo run -q -p wolf-cli -- verify
```

注意：

- `WOLF_DATA_ROOT` 必须是绝对路径。相对路径会被各 crate 当成 crate 目录相对路径，
  结果可能是静默 skip 的假绿。
- 先复制数据到可写目录，再运行测试。不要让测试直接修改 `assets` 分支或用户原始
  `Save/`。
- 未设置 `WOLF_LIVE_RNG`；它是 opt-in 行为，会破坏确定性基线。
- 未设置 `WOLF_CURSOR_FALLBACK_OFF`，除非专门测试该逃生口。
- 部分测试还读取 `WOLF_GAME_DIR` 或 `WOLF_DATA_WOLF`；素材包通常没有原始
  `Data.wolf`，缺失时只能记录为 `UNVERIFIED_ENV`，不能宣称 `verify --wolf` 已验证。

存档隔离建议：

```bash
cp -a /path/to/Data /workspace/audit-data
find /workspace/audit-data/Save -type f -print0 \
  | sort -z | xargs -0 sha256sum > /workspace/save-before.sha256
# 运行测试
find /workspace/audit-data/Save -type f -print0 \
  | sort -z | xargs -0 sha256sum > /workspace/save-after.sha256
diff -u /workspace/save-before.sha256 /workspace/save-after.sha256 || true
```

已知会涉及存档的测试包括但不限于：

- `m25_save_slot` 的自动存档用例
- `m3_save_ui_roundtrip`
- `m3_settings_persist`
- `m3_system_settings_bridge`
- `m3_save_byte_fidelity` 的临时写出

必须在报告中说明哪些测试实际改写了临时存档，哪些只是读取。

### 4.4 测试“假绿”审计

大量数据测试在缺数据时打印 `skipping` 后直接 `return`。必须检查：

```bash
cargo test -q --workspace -- --nocapture > /workspace/tests.log 2>&1 || true
rg -n "skipping|skip:" /workspace/tests.log
rg -c "skipping" /workspace/tests.log
```

要求：

- 统计“测试函数总数”和“实际断言执行数”。
- 对关键需求，不能只引用“test passed”，必须确认测试在该环境下没有提前返回。
- 检查 `#[ignore]`、空断言、只打印不 panic 的测试、恒定 true 的断言。
- 检查测试是否依赖玩家可变存档或本地截图，导致不同环境结果漂移。

编写本指南时的静态快照：约 114 个测试文件、1,215 个 `#[test]`，
其中 91 个测试文件包含 `skipping` 路径，另有多处构造器返回 `None` 后静默跳过。
这是提醒而不是结论；Gemini 必须在自己的环境中重新统计。

### 4.5 证据等级

每条 finding 建议标注：

- `E0`：仅推测，无代码路径或数据证据。
- `E1`：静态代码路径可证明，未运行。
- `E2`：本环境编译/单测验证。
- `E3`：使用真实数据或 headless 运行时复现。
- `E4`：真实窗口、视觉或交互复现。

没有 `E2` 以上证据的内容，不应标为 P0。

---

## 5. 阶段一：需求闭环追溯

### 5.1 建立需求账本

从 tracked 文档中提取所有 bug、用户裁定、优化项、已知边界和“不要做”事项。
至少覆盖：

- `CODE_REVIEW_4ROUND` BUG-01..48 及历史 §六 BUG-20..24。
- `TASKS_REMAINING_BUGS` T0..T13。
- `HANDOFF_DEEP_REVIEW_FIX` 的 T0..T11 和关键语义。
- `HANDOFF_T12_PATCH_AND_LEDGER` 的 T12 收口。
- `LIVE_PLAY_FIX_REPORT` 的 11 项。
- `M25_LIVE_UX` 的 RNG、光标、睡姿热区、存读档、返回标题、自动存档。
- `REVIEW_9a817e4_FIX_REPORT` 的 P0/P1/P2 和“重新开放项”。
- `GEMINI_REVIEW_1c76dcc_FIX_REPORT` 的人名牌缓存、HUD、已知边界。
- `AUDIT_REBUILD_FIX_REPORT` 的截图轮、RNG、缓存、键位、字体。
- `HANDOFF_M0.md` §11.1 和 §11.3 的当前开放项。
- 各 M3/M4/M6/M7 专题文档中的验收条件和“不实现”裁定。

如果用户另行提供根目录审查报告，可补入：

- `code_review_9a817e4.md`
- `review_46de4eb_and_ux_bugs_report.md`
- `review_a2a618d_report.md`
- `live_play_issues_and_fixes_report.md`
- `github_audit_rng_and_ux_report.md`
- `ux方案.md`

这些文件在云端可能不存在，缺失不代表要求丢失；应优先查对应 fix report 和 handoff。

### 5.2 需求矩阵格式

必须输出 CSV/Markdown 表，列建议为：

| 字段 | 含义 |
|---|---|
| `req_id` | 自行分配的稳定编号 |
| `source` | 文档路径 + 章节/ID |
| `requirement` | 原始要求或缺陷描述 |
| `claimed_status` | 文档声称的状态 |
| `code_evidence` | 当前代码符号/文件/行号 |
| `test_evidence` | 测试名、命令、是否真正执行 |
| `independent_result` | 已修复 / 部分 / 未修复 / 已回退 / 非缺陷 / 无法验证 |
| `residual_risk` | 未覆盖分支、环境限制、夹具漂移 |
| `notes` | 与其他文档冲突或历史背景 |

状态定义：

- `FIXED_VERIFIED`：代码 + 测试/运行证据均成立。
- `FIXED_STATIC_ONLY`：代码存在，但缺真实数据/运行时验证。
- `PARTIAL`：主路径修复，边界或相关入口仍缺失。
- `OPEN`：当前代码仍存在该问题。
- `REVERTED`：曾修复但当前代码已回退。
- `NOT_A_BUG`：原报告误判或用户裁定为设计行为。
- `UNVERIFIED_ENV`：云端环境无法判断。

### 5.3 按主题检查，而不是只按编号检查

至少建立以下需求族：

1. **格式与数据**：VER6、Game.dat、CommonEvent、Database、CP932/GBK、mps、tileset、
   `.project`、verify 基线。
2. **VM 语义**：变量地址、字符串槽、条件、循环、调用、图片、音效、存档操作码、
   自动输入、等待、随机、过渡。
3. **调度与状态机**：AutoEvents、并行页、地图换页、公共 Self、跨事件调用、
   返回标题、预约事件、预算与死循环。
4. **地图和输入**：5 张注册地图、ActionKey、鼠标边沿、滚轮、按键重复、失焦、
   改键、PlayerTouch 不建模。
5. **文本/对话**：行距、折行、名牌、头像、气泡高度、`\img`、翻译、编码。
6. **HUD/菜单/UI**：标题、行动力条、侧栏、选项、相册、数据页、设置、存档栏。
7. **存读档**：字节保真、Part1、vardb、CSelf 路径、BGM 恢复、槽号、弹窗、
   自动存档、返回标题后的状态清空。
8. **Godot 桥**：绘制包字段、atlas、blend、输入、音频缓存、模态、退出落盘。
9. **性能/资源**：VM 预算、Assets 缓存、tile/text 缓存、atlas 上传、音频解码、
   存档摘要、内存生命周期。
10. **发布/素材**：Godot 导出、CLI 打包、Data 全量复制、第三方插件、未用资源。

每个族都必须有结论，不能只挑容易的部分。

### 5.4 必须逐项裁决的开放/争议项

以下项目不能因为旧文档写了“已完成”就跳过：

- Opcode 122 掩码与首行截取语义。
- `\img` 的独立分层、anchor/scale/alpha 过滤。
- ActionKey 图片按钮绕过脚本条件的范围。
- `150 Move` 范围指令是否逐整数扫描，跨度是否可控。
- 同协程同帧多次 `123` 的 auto-key 消费粒度。
- Godot 两个 verify 脚本是否接入自动 smoke。
- 打字机速度是否仍约 2 倍偏差。
- 选择面板宽度约 5.3 px 的未解释差异。
- `kind >= 0` 过渡、极小窗口盒等“明确不实现”项是否真的不可达。
- Godot 正式导出包是否存在。
- Godot 模态期间 runtime 是否继续推进，是否符合设计。
- F11/全屏在模态下是否被输入拦截。
- 启动失败时是否有可观察错误和可靠退出路径。
- `Assets::clear()` 的注释与 production 生命周期是否一致。
- 未使用 API 是否真是死代码，还是诊断/未来前端接口。
- 资产封包是否包含游戏永远不会使用的模板资源。
- `m3_status_panel::ce238_relative_panel_lands_at_the_left_edge` 等历史失败项
  是否仍存在，或已变成夹具/环境问题。

---

## 6. 阶段二：正确性与新缺陷

### 6.1 先审入口和数据流

至少建立以下调用链图：

1. `Game::new` → `prime_engine` / `boot` / `start_title`
2. 标题 → Map003 → SampleMapA
3. 标题 → CE14 → CE131 → load → resume map
4. 游戏内保存图标 → CE14 → CE131 → 写槽
5. 自由地图 `Esc` → 返回标题确认 → 帧末切换
6. 地图事件 → VM → Picture/Message/Choice/Sound → Game host → Godot packet
7. 存档恢复 → vardb/Part1 → picture layer → BGM → map runtime
8. 设置 → CE132/CE95 → Sys 变量 → 音频/键位 → Godot 退出落盘

对每条链路检查：

- 状态清空是否完整。
- 请求是否在安全阶段结算，而不是在遍历中修改集合。
- 失败路径是否可观察。
- 是否能重复进入/退出而不泄漏或残留。
- 输入沿是否可能被多个消费者重复消费。
- 存档写入是否可能因视觉或前端逻辑误触发。

### 6.2 VM 和事件语义

重点检查：

- `Opcode 121/122/123/124/125/126/130/140/150/151/160/161/162/170/171/172/
  174/176/179/180/201/210/211/212/213/220/221/222/250/270/281/290/300/401/420/`
  `421/498/499` 的参数求值、边界和错误分支。
- `eval_num`、`eval_string`、`store_num`、`store_string` 对 StrVar、CSelf、
  CommonSelf、DB、间接指针的寻址是否一致。
- `op111`、`op121` 的位域、运算符、溢出、负数、除零、钳制。
- `op124` 的字段和复合赋值。
- `op176` 的循环语义，不能重新当作循环头。
- `op210/211/300` 的间接调用和事件身份。
- 等待、非阻塞轮询、并行实例和 foreground event 的语义。
- 预算耗尽时是继续、报错还是静默跳过。

不要只看 `match` 是否有分支；要核对参数索引、副作用和测试数据。

### 6.3 存档与状态完整性

存档是本项目最高风险区域之一。必须检查：

- `SaveFile::parse` / `write` / rebuild 的边界和校验和。
- 官方存档 load→save 的字节差异。
- vardb 的数字/字符串/缺失单元格。
- Part1 地图快照、事件对象、tile 数据。
- CSelf 字符串与自引用路径。
- BGM/音频命令恢复。
- CE131 的 12 槽/3 页寻址。
- 非空槽确认、空槽直接保存、标题读档模式。
- 读档后旧 UI 链、旧输入沿、旧音频和旧地图实例是否清理。
- 自动存档是否默认关闭、何时启用、是否覆盖玩家槽位。
- 退出时写设置与写存档是否分离，是否可能连带写入编号存档。

`SaveFile` 当前存在“不验证存储 checksum”的已知 API 边界时，必须评估其安全/完整性
影响，不要只把它当作测试忽略项。

### 6.4 输入与模态

至少检查：

- 快速点击（按下/松开跨渲染帧）。
- 左键、右键、滚轮、Enter、Backspace、Esc。
- 失焦/恢复、Alt-Tab、最小化、全屏切换。
- 模态打开时键盘/鼠标/滚轮是否完全隔离。
- 关闭模态时 release guard 是否防止同一按住状态穿透。
- 弹窗按钮悬停与键盘焦点是否一致。
- 二级界面与自由地图的 Esc 语义是否分层。
- 模态期间 runtime 是否继续推进；如果是，是否会改变底层状态。
- 标题菜单、读档格、存档格、相册、设置、相册详情的坐标转换。
- 窗口缩放、`canvas_items` stretch、全屏下逻辑坐标是否正确。

必须把“点击取消/否后底层仍执行读档或覆盖保存”作为 P0 级检查项。

### 6.5 UI、对话和视觉

静态审查时至少覆盖：

- 标题三选项及选中图。
- 新游戏开场背景不能黑屏。
- HUD 行动力条及其边框、比例、文字对齐。
- 侧栏开合、文字与底板同步、关闭态 alpha。
- 对话正文、名牌、头像、原生 101 层抑制。
- 三行以上气泡是否越界或被裁切。
- 选项面板游标、高亮、外部点击。
- 存档栏左列布局、右侧注意事项、翻页箭头、鼠标高亮。
- 相册图标命中、已收集缩略图、详情关闭链。
- 夜间菜单、恶作剧按钮、GOOD/BAD 条、脚本光标与系统手型互斥。
- 记录/数据/保存/结束按钮的可见墨迹命中，不使用旧整屏矩形。

没有截图或运行时像素证据时，只能写“代码审查支持/不支持”，不能写“视觉通过”。

### 6.6 鲁棒性与安全

建议检查：

- 恶意/损坏 `.sav`、`.dat`、`.mps` 的长度、索引、整数溢出、除零。
- 解包路径是否有目录穿越、大小爆炸、无限循环。
- 资源缺失、字体缺失、数据根为空、Godot atlas 字节不匹配。
- panic 是否可能由玩家数据触发。
- 是否存在 `unwrap`/`expect` 在外部输入路径上无保护。
- mod overlay 的路径、大小写、符号链接与优先级。
- 翻译表重复键、缺失键、超大行。
- 第三方脚本或插件的权限、网络、文件写入行为。

如果使用 fuzz/property test，必须说明工具、种子、运行时长和未覆盖范围。

### 6.7 测试质量审查

- 每个 P0/P1 修复是否有回归测试。
- 测试是否依赖真实存档、固定日期、字体、窗口或本地路径。
- 是否有 `skipping` 后直接返回。
- 是否有 `#[ignore]` 及原因是否成立。
- 是否只测实现细节而没有用户可见断言。
- 是否存在同一输入多次运行结果不稳定。
- 测试是否会在失败时恢复存档、设置和临时文件。
- 是否覆盖错误路径、重复进入、取消、返回标题、长会话。
- 是否存在“改基线求绿”的历史风险。

---

## 7. 阶段三：性能与内存

### 7.1 性能审查规则

- 必须先测量，再优化；没有当前机器数据的“优化”只能写候选。
- 不设跨机器墙钟阈值。
- 同一时段交替运行基线和候选，报告中位数、p95、max。
- 区分冷启动、首帧解码、稳态帧、场景切换、存档 UI 和退出。
- 区分 Rust CLI/wgpu 路径与 Godot 路径，不能混用数据。
- 不把 60 fps 当成“CPU 每帧可用 16.6ms”的理论许可；记录实际帧预算。

### 7.2 必须回答的热点

#### VM 调度

- `step_frame` / `run_instances` / `execute` 的每帧成本。
- 每帧 clone `WaitState`、`Arc<Program>`、foreground event 扫描的成本。
- 并行事件增多时是否出现 O(n²) 行为。
- 200,000 指令预算是否被忙等、死循环或大型脚本耗尽。
- `--hot` 的 event/pc 分布和预算耗尽次数。

#### Assets 缓存

- `Assets.cache` 是否有容量上限或字节预算。
- 返回标题、读档、浏览相册、长会话后 RSS 和缓存数量是否持续上升。
- `Assets::clear()` 是否被 production 调用；文档声称的清理是否实际存在。
- 图片解码、alpha bounds、缺失名字负缓存是否有效。
- 全量解码的理论内存上限和常见场景实际占用。

历史只读估算曾给出“若全部图片解码约为 949 MiB”的上限（cg 约 748 MiB、
BattleEffect 约 104 MiB、Picture 约 79 MiB）；这不是当前 RSS，也不是已复现缺陷。
请用实际缓存字节数、RSS 时间序列和场景可达性重新验证。

#### Atlas/渲染

- `Atlas` 的 backing 分配、content crop 上传和 UV 计算是否一致。
- `atlas_pixels()` 是否每帧复制大块内存。
- window panel、普通 sprite、`\img` sprite 的多遍扫描和排序成本。
- Godot `_draw` 每帧构造 `items`、`sort_custom`、blend batch 的成本。
- `TileMap::quads()` 命中缓存后是否仍 clone 大 Vec。
- tile bridge 已从前端移除后，相关缓存是否仅用于诊断。

#### 文本

- `text_quads` 缓存命中后是否仍 clone 大量 quad。
- 字体 shaping、行距、fallback、描边的每帧成本。
- Godot `WolfText` paragraph 缓存的命中率和上限。

#### 音频

- 首次解码、重复播放、场景切换和读档时的卡顿。
- Godot 64 项缓存是否按文件大小而非数量限制。
- Rust 音频解码与 Godot 音频缓存策略是否造成行为差异。

#### 存档 UI

- 打开、翻页、悬停、自动存档、读档恢复的耗时。
- 全量 clone `base_save`/part2、重建 `.sav`、摘要缓存和文本 clone 的成本。
- 是否需要后台线程，或是否应避免在帧内做文件 I/O。

### 7.3 性能报告格式

至少包含：

| 场景 | 入口 | 数据/存档 | 帧数 | p50 | p95 | max | 内存峰值/增量 | 备注 |
|---|---|---|---:|---:|---:|---:|---:|---|

并附：

- 命令和日志路径。
- 是否 warm-up。
- 是否 debug/release。
- 是否含资源首帧解码。
- 与历史基线是否可比。

---

## 8. 阶段四：死代码与不可达路径

### 8.1 分类

不要把所有“未调用”都叫死代码。至少分为：

- `RUNTIME`：正式游戏流程会执行。
- `TOOLING`：`wolf-cli verify/capture/assets`、打包、逆向工具使用。
- `TEST_ONLY`：测试夹具、探针、基线。
- `DEV_ONLY`：MCP/Godot 编辑器插件、开发辅助。
- `DATA_TEMPLATE`：WOLF 模板或未注册地图数据，保留但可裁包。
- `OBSOLETE_CANDIDATE`：有证据表明被新实现完全取代。
- `TRULY_DEAD_CANDIDATE`：静态和动态均无入口，仍待产品决定。

### 8.2 “四证”规则

删除建议必须同时具备：

1. **静态引用证据**：production、tests、docs 分开统计。
2. **动态可达性证据**：事件、opcode、地图、读档状态、变量目标、间接调用。
3. **运行时证据**：trace、测试或长会话观察。
4. **产品决定**：确认不是未来前端、诊断工具、兼容 API 或模板保留。

只有 `rg` 搜不到调用，最多是 `TRULY_DEAD_CANDIDATE`，不能直接建议删除。

### 8.3 当前重点候选

以下只能作为调查起点：

- `Assets::clear()`
- `TileMap::animation_phase()`
- `save_common_self()`
- `eval_arith_operand()`
- 未被 Godot 使用的 `tile_quads` 路径（但要保留 CLI 取证）
- `wolf-launcher` 与 `wolf-render`/`wolf-cli play` 的定位
- `godot/tests/verify_*.gd` 是否仍被任何流程调用
- CE212/213/221/222 等模板/间接事件
- CE301 是否为旧版重复实现
- `godot/addons/godot_ai`
- 未注册地图、PlayerTouch、161/162 过渡
- 战斗表、`BattleEffect/`、未引用的 `cg`/`MapChip`

### 8.4 明确不要误删/误报

- `Game::tile_quads()` 仍用于 CLI capture、视觉取证和诊断，不等于前端死代码。
- `wolf-render`/`wolf-cli` 是工具链和基线的一部分。
- `Picture/word_effect*` 可能有运行时路径 fallback。
- `MapChip` 未出现在图片绘制扫描中，不代表未被 tile 层使用。
- `BattleEffect` 是模板残留候选，但必须与数据引用、打包策略一起判断。
- `character_state` 已在 `wolf-game` 实现；不要只看到 VM trait 的默认空实现
  就判定缺失。
- 不要因为一次 `m14_event_reachability` 未命中就断言某个 CE 永不可达。

---

## 9. 阶段五：素材、封包与第三方代码

### 9.1 可用的静态资源审计

有数据根时：

```bash
WOLF_DATA_ROOT="$AUDIT_DATA" cargo test -q -p wolf-format --test m3_asset_refs

cargo run -q -p wolf-cli -- assets \
  --root "$AUDIT_DATA" --include-maps --format json > /workspace/assets.json

cargo run -q -p wolf-cli -- assets \
  --root "$AUDIT_DATA" --coords --format json > /workspace/assets-coords.json

cargo run -q -p wolf-cli -- assets \
  --root "$AUDIT_DATA" --db-defaults --format json > /workspace/db-defaults.json
```

注意：

- `assets` 主要枚举 op150 图片绘制和部分数据库引用。
- 不能覆盖 kind 1/4 动态字符串、运行时拼接路径、tile layer、字体内部 fallback。
- 文件存在 != 画面正确；必须结合尺寸、alpha、锚点、层级和运行时 trace。

### 9.2 未使用素材分析

至少输出：

- 总文件数、总字节数。
- 被静态引用/未被静态引用的数量与大小。
- 按目录分类：BGM、SE、cg、Picture、MapChip、CharaChip、SystemFile、
  BattleEffect、字体、未注册地图、存档夹具。
- 每个“未引用大项”的人工裁决：可裁、不可裁、需运行时证据。
- 发布包是否实际复制该资源。

重点风险：

- `tools/package-playable.sh` 当前看起来会递归复制整个 Data 根。
- 如果没有 manifest/白名单，封包会包含测试存档、模板资源和游戏不会用到的素材。
- 字体、BGM、CG、相册、SE 可能被数据库或动态字符串引用，不能只看 op150。
- 存档样本是测试夹具，不是玩家发布内容；是否应进入发布包必须单独判断。
- 未注册地图和战斗模板可能是“数据保留”而非“运行资源”。

历史一次仅按 op150 字面量扫描的结果为：1,069 个图片文件中 652 个被引用、
417 个未引用，未引用约 23.4 MiB，其中 `BattleEffect` 47 个约 15.35 MiB。
该扫描不覆盖动态路径、tile layer、数据库和别名，不能直接当最终结论；
必须在当前数据版本上重跑并人工裁决。

### 9.3 Godot 导出与第三方插件

必须回答：

- 是否存在正式 Godot `export_presets.cfg` 和导出步骤。
- `godot/project.godot` 是否启用 `res://addons/godot_ai/`。
- `_mcp_game_helper` autoload 是否会在正式发行时执行。
- 开发插件是否会被导出、暴露 MCP/调试能力、增加启动成本或写入文件。
- `godot/addons/godot_ai` 的许可证、来源和维护方式。
- `godot/bin/wolf_gdext.gdextension` 是否只配置 Windows；Linux/macOS 是否无库。
- CLI 发布包是否被误当成 Godot 正式发布包。

截至本指南编写，仓库中没有发现 `export_presets.cfg`，而
`tools/package-playable.sh` 打包的是 CLI 启动器 + Data，不是 Godot 导出包。
这需要作为发布阻断候选重新确认，不能把 CLI 包的 `verify` 通过当作 Godot 发行验证。
同样，`godot/addons/godot_ai/` 当前已入库、插件已启用且配置了 autoload；
必须判断它是否仅为开发工具，以及正式导出时是否会被包含。

### 9.4 封包与供应链

- 检查 `tools/package*.sh/.ps1` 的构建、复制、校验和、错误处理。
- 是否存在静默覆盖、未校验 hash、把源码/测试/存档打进包。
- `Cargo.lock`、`rust-toolchain.toml`、Godot 版本是否锁定。
- 第三方 crate 和插件是否有可接受许可证。
- 是否有 CI、release gate、checksum、可重复构建说明。
- 不新增依赖；任何依赖建议都必须有充分理由和体积/安全评估。

截至本指南编写，仓库没有 `.github/` CI 配置；如果 Gemini 看到其他 CI 文件，
以其实际内容为准。

---

## 10. 阶段六：清晰度与可维护性

评估以下方面：

1. **模块边界**：`wolf-format`、`wolf-save`、`wolf-vm`、`wolf-game`、
   `wolf-gdext`、Godot 前端职责是否清晰。
2. **单一事实源**：变量地址、图片槽、UI 常量、事件 ID、操作码语义是否集中。
3. **巨型模块**：`game.rs`、`exec.rs`、`gbk.rs` 等大文件是否可按职责拆分；
   但不要把体量本身当缺陷，先看耦合和重复。
4. **跨语言契约**：Rust packet 字典与 GDScript 读取是否有 schema/测试保护。
5. **错误处理**：字符串错误、日志、静默失败、启动失败是否可观察。
6. **注释与文档**：代码注释是否引用不存在的文档、过期行号或已撤销实现。
7. **重复逻辑**：坐标转换、命中测试、缓存、槽位映射是否存在多份实现。
8. **测试可维护性**：硬编码玩家存档、字体、Windows 路径、截图尺寸。
9. **魔法数字**：1024×576、slots、self 变量、事件 id 是否命名清晰。
10. **发布可维护性**：两套前端、两套打包、两套资源缓存是否定位明确。

输出时区分：

- 正确性缺陷
- 性能问题
- 可维护性改进
- 风格偏好

不要把“我希望这样写”作为缺陷。

---

## 11. 已知误报、设计取舍与不要重复立项

以下项目已被历史审查或用户裁定处理。若没有新证据，不要重复当成新 bug：

1. 日常卧室没有独立体力图形条；HUD 文字/数值是原版行为。
2. `Picture 2999` 不是白天系统光标的唯一来源；白天是引擎系统指针。
3. 卧室站立立绘 `900..903` 是显示层，不是额外点击热区。
4. Godot 前端不再绘制 `tile_quads` 是 T13 后的有意架构，不是地图层缺失。
5. 161/162 冻结过渡只在未注册示例地图出现，不应要求正式流程强制触发。
6. PlayerTouch（trigger 3）不在本作注册地图使用，不要求实现完整玩家行走系统。
7. Sys104/105 不应建立 player/camera/scroll 模型；本作是定屏地图。
8. `.wolf` VER6 解密不是未解难题；不要在报告中重新当研究空白。
9. `message` 名牌字面量在原版实机中也出现，不要擅自按占位符隐藏。
10. 两套 `BUG-20..24` 同号不同义，不能合并。
11. 旧报告中的 `武器スキルセット`、`防具スキルセット`、大量日文模板文本，
    不能脱离数据上下文当成本作实际内容。
12. 不要把“文件不存在”直接等同于“游戏运行时会缺图”；先检查动态路径、
    fallback、别名和未注册地图。
13. 不要把“公共图片数量相同”当成画面正确；层级、z、blend、UV、裁剪都需检查。
14. 不要把“测试 passed”当成“真实数据断言执行”；很多测试缺数据会 skip。
15. 不要把旧性能数字当当前 HEAD 结果；机器和实现均可能变化。

如果 Gemini 认为上述裁定有误，必须提供新的代码/数据/实机证据，并单列“推翻既有裁定”。

---

## 12. 必须交付的报告

建议输出以下文件，全部写入审查报告目录，不写源代码目录：

1. `00_EXECUTIVE_SUMMARY.md`
   - 审查基线、总体风险、最严重 10 项、是否可发布。
2. `01_REQUIREMENT_TRACEABILITY.csv`
   - 全部需求/缺陷/裁定逐条闭环。
3. `02_FINDINGS.md`
   - 新发现缺陷和风险详情。
4. `03_PERFORMANCE.md`
   - 场景、命令、p50/p95/max、内存、热点归因。
5. `04_ASSETS_AND_PACKAGING.md`
   - 已用/未用素材、封包裁剪、Godot 导出、第三方插件。
6. `05_DEAD_CODE_REACHABILITY.md`
   - 候选、证据等级、建议保留/删除/观察。
7. `06_TEST_COVERAGE_AND_SKIPS.md`
   - 测试数、断言数、skip/ignore、夹具漂移、缺口。
8. `07_MAINTAINABILITY.md`
   - 架构、重复、文档/代码一致性、建议重构顺序。
9. `08_UNVERIFIED_CLOUD.md`
   - 云端缺数据/缺 Godot/缺 Windows/缺截图导致的未验证项。
10. `09_REPRODUCTION_LOGS/`
    - 命令、输出、截图、性能日志、哈希。

### 12.1 Finding 格式

每条 finding 至少包含：

```text
ID:
Severity: P0/P1/P2/P3
Category:
Confidence:
Evidence level: E0/E1/E2/E3/E4
Title:
Location: path:symbol:line
Status: confirmed / high-risk hypothesis / unverified / not-a-bug
Affected flow:
Observed behavior:
Expected behavior:
Reproduction:
Root cause:
Impact:
Minimal fix:
Regression test:
Packaging/performance impact:
Related requirement:
```

P0/P1 不能只有“建议重构”或“可能”；必须说明真实玩家影响和复现方式。

### 12.2 需求矩阵状态

不要在矩阵中使用模糊的“基本完成”。只允许：

`FIXED_VERIFIED`、`FIXED_STATIC_ONLY`、`PARTIAL`、`OPEN`、`REVERTED`、
`NOT_A_BUG`、`UNVERIFIED_ENV`。

### 12.3 最终结论

必须明确回答：

- 项目是否存在阻断发布的问题？
- 哪些问题必须立即修，哪些可以在后续版本修？
- 哪些结论是证据充分，哪些只是风险假设？
- 哪些旧报告结论应撤回或更新？
- 下一步最小验证集是什么？

---

## 13. 严重度与置信度

建议定义：

- `P0`：存档破坏、必现崩溃、无法启动、核心流程完全不可用、严重安全问题。
- `P1`：高频可见功能错误、状态机死锁、数据损坏风险、关键输入/UI 失效。
- `P2`：低频可见错误、边界差异、明显性能/资源问题、维护风险。
- `P3`：代码质量、文档、可选优化、轻微性能。

置信度：

- `High`：代码路径和运行/测试均证实。
- `Medium`：代码路径明确，但缺少目标环境验证。
- `Low`：只有静态线索或推测。

严重度描述影响，置信度描述证据，两者不能混为一谈。

---

## 14. 可选：完整数据与 Godot 运行手册

只有在用户提供 `assets` 分支或数据包时使用。

### 14.1 准备可写数据根

```bash
mkdir -p /workspace/imouto-audit
cp -a /path/to/assets/Data /workspace/imouto-audit/Data
export WOLF_DATA_ROOT=/workspace/imouto-audit/Data
```

不要直接在原始数据根上运行会写存档的测试。

### 14.2 Rust 数据测试

```bash
WOLF_DATA_ROOT="$WOLF_DATA_ROOT" cargo test -q --workspace --no-fail-fast
WOLF_DATA_ROOT="$WOLF_DATA_ROOT" cargo test -q -p wolf-game --test m3_perf_baseline -- --nocapture
```

### 14.3 verify / precompile / translations

根据 `wolf-cli --help` 当前实际子命令执行，至少检查：

```bash
./target/debug/wolf-cli --root "$WOLF_DATA_ROOT" verify
./target/debug/wolf-cli --root "$WOLF_DATA_ROOT" precompile
./target/debug/wolf-cli --root "$WOLF_DATA_ROOT" translations --help
```

不要照抄旧命令参数；以当前 CLI help 和 `docs/BASELINE.json` 为准。

### 14.4 Godot

如果使用 Windows runner：

```bash
GODOT_BIN="/path/to/Godot_v4.7.2-stable_win64.exe" \
WOLF_DATA_ROOT="C:/absolute/path/to/audit-data" \
bash tools/smoke-godot.sh
```

Linux/无 Godot：

- 只做静态审查。
- 不执行 DLL 复制脚本。
- 不把 Godot 相关失败归咎于游戏逻辑。
- 在 `08_UNVERIFIED_CLOUD.md` 中明确列出。

### 14.5 视觉/交互验证

- 先使用临时存档副本。
- 记录窗口分辨率、缩放模式、截图时间和帧号。
- 对窗口截图先换算回 1024×576 逻辑坐标。
- 不用 PS/手动模拟按键干扰用户桌面。
- 每次保存测试前后校验 `Save/` 哈希。
- 至少覆盖标题、新游戏、读档、存单弹窗、返回标题、设置、相册、
  夜间菜单、恶作剧、侧栏、对话气泡。

---

## 15. 提交前自检

在结束前逐项确认：

- [ ] 已记录 exact HEAD 和环境。
- [ ] 已阅读最低文档清单。
- [ ] 已建立需求矩阵，状态不是模糊值。
- [ ] 已区分修复、回退、非缺陷、无法验证。
- [ ] 已统计测试 skip/ignore 和夹具依赖。
- [ ] 已检查存档隔离，未改写真实存档。
- [ ] 已检查性能热点，但没有用旧数字冒充当前结果。
- [ ] 已检查 Assets、Atlas、TileMap、音频、存档 UI 的内存/CPU。
- [ ] 已检查死代码候选的静态和动态可达性。
- [ ] 已检查素材使用、封包复制和 Godot 导出。
- [ ] 已检查 `godot/addons/godot_ai` 的运行时/打包风险。
- [ ] 已单列云端无法验证项。
- [ ] 每条 P0/P1 都有复现或代码证据。
- [ ] 没有把设计取舍或个人风格当缺陷。
- [ ] 没有修改源码、提交或删除用户文件。

---

## 附录 A：已知历史验收值（仅作起点，必须重测）

这些数字来自 handoff 记录，不是当前机器实测：

- `wolf-cli verify`：历史记录 PASS 64 / 1 SKIP。
- `precompile`：历史记录 PASS 19 / 0。
- `smoke-godot.sh`：历史 P0 基线 `pictures=4 sprites=4`。
- `parity-godot.sh 600 --pixel-check=0`：历史记录 PASS。
- `m14_visual_regression`：历史记录 5/5，但依赖存档夹具。
- `m25_save_slot`：14 条相关用例通过，另有两条自动存档测试在“不得写玩家存档”
  策略下被排除。
- 默认 workspace 仍可能有既有字体度量失败（choice/textpic 等），
  真实数据套件也可能有既有姊妹作/事件语义差异。
- 个别测试的 `data_root()` 曾指向不存在的 `work/full`，会静默跳过；
  必须逐个检查测试查找路径，不能只看 exit code。

先运行、再比较、最后下结论。

## 附录 B：推荐的首轮命令顺序

```bash
git status --short
git rev-parse HEAD
rustc --version
cargo --version

cargo fmt --all -- --check
git diff --check
cargo check -q --workspace
cargo test -q --workspace --no-fail-fast

# 只在有可写数据副本时
export WOLF_DATA_ROOT=/workspace/imouto-audit/Data
WOLF_DATA_ROOT="$WOLF_DATA_ROOT" cargo test -q --workspace --no-fail-fast
WOLF_DATA_ROOT="$WOLF_DATA_ROOT" cargo run -q -p wolf-cli -- verify
```

任何命令失败时，先区分：

- 环境缺失
- 既有基线失败
- 夹具漂移
- 新引入回归
- 真正业务缺陷

不要把后两类与前两类混在同一张表里。
