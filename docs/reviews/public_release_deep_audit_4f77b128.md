# Imouto! Life ~Monochrome~ 公开发布版深度静态代码审查报告（`4f77b128`）

- **审阅对象**：`nana7mi0721/imouto-life-monochrome`（v0.1.0 公开发布版）
- **源码快照**：`4f77b1283effcbea8b32452f99d2dd9e01c7b9f1`
- **审阅边界**：纯静态只读代码审查（云端沙箱无 `rustc` / `cargo` / Godot / `work/Data`，所有编译与运行结论均基于源码与配置静态推理，需本地复核项标 `UNVERIFIED_ENV`）
- **去重基线**：已逐项核对 `docs/reviews/TASKS_REMAINING_BUGS.md`、`docs/reviews/AUDIT_2411996_FIX_REPORT.md`、`docs/reviews/cloud_audit_2026-11-18_e716f08/00_EXECUTIVE_SUMMARY.md` 与 `docs/HANDOFF_PROGRESS.md`，确保不与任何历史已修复缺陷冲突。

> **处理状态（2026-11-20）**：PUB-01..06 已全部修复，并随 0.1.1 六个发行包
> 发布；Windows/Android 真机与无头验证结果见
> [PUBLIC_RELEASE_FIX_REPORT.md](PUBLIC_RELEASE_FIX_REPORT.md) 与
> [PACKAGING.md](../release/PACKAGING.md) §8.8。§5.1 的方向 1/2/4/5
> 已落地，方向 3 以 Android APK 内直读实现，标准与 slim 共用同一读取路径。

---

## 一、执行摘要

当前公开发布版在核心玩法、Android 适配、存档兼容与文档结构上整体成熟度很高，但在**公开发布前的最后一次仓库清理**与**底层稳健性**上，发现 **1 项 P0 级构建阻断缺陷**、**1 项 P1 级存档损毁隐患** 与 **4 项 P2 级交互/移动端/发布卫生问题**：

- **必须立即修复（P0）**：根 `Cargo.toml` 为响应“不设开源协议”删除了 `[workspace.package].license`，但**全部 9 个子 crate 的 `Cargo.toml` 仍写着 `license.workspace = true`**，导致任何克隆本仓库或触发 `.github/workflows/ci.yml` 的环境都会在 Cargo 解析阶段直接报错失败。
- **高优先级修复（P1）**：`crates/wolf-game/src/savegame.rs:65` 的 `write_save()` 仍直接调用 `std::fs::write()`（非原子写入），在 Android 后台被杀或断电瞬间写盘会直接截断损毁玩家存档或 `System.sav`。
- **注释与代码结构**：剔除码表 `gbk.rs` 后，Rust 生产代码注释占比高达 **21.7%**（`game.rs` 26.1%、`picture.rs` 26.9%、`WolfText.gd` 47.3%），且包含 **214 行** 引用已过时编号（`BUG-08`、`report section`、`ptr_sc`、`used to`）的历史过程注释，极易污染未来 Agent 上下文。
- **包体精简潜力巨大**：当前发行包（Windows Setup 148 MB / ZIP 159 MB / Android APK 145 MB）中，仅靠 **WebP/无损重压 `media.pak` + 精简 Godot 2D 导出模板 + Rust release 瘦身**，理论上可将双端包体压缩 **40%–55%**（降至 **~65–85 MB** 区间），且 Android 端可进一步消除 ~113 MB 的双份存储占用。

---

## 二、新发现漏洞与修复方案（不与历史已修项冲突）

| 编号 | 严重度 | 位置 | 问题描述 | 推荐修正方法 |
| :--- | :--- | :--- | :--- | :--- |
| **`PUB-01`** | **P0（构建阻断）** | `Cargo.toml:16-20`；`crates/*/Cargo.toml:6`（全部 9 个 crate） | **Workspace `license` 继承断裂**：根 `Cargo.toml` 删除了 `[workspace.package]` 下的 `license` 字段，但 `wolf-audio`、`wolf-cli`、`wolf-format`、`wolf-game`、`wolf-gdext`、`wolf-launcher`、`wolf-render`、`wolf-save`、`wolf-vm` 共 9 个子 crate 仍保留 `license.workspace = true`。Cargo 会直接报 manifest 继承错误，导致全新克隆与 GitHub Actions CI 全部无法编译（`UNVERIFIED_ENV` 静态必现）。 | 批量删除 9 个子 crate `Cargo.toml` 中的 `license.workspace = true` 行（若希望明确声明版权保留，也可在根 `Cargo.toml` 不设 `license` 且子 crate 不继承）。修复后在本地跑一次 `cargo check --workspace` 验证。 |
| **`PUB-02`** | **P1（数据安全）** | `crates/wolf-game/src/savegame.rs:57-66` | **存档写入非原子，存在截断损毁风险**：`write_save()` 直接调用 `std::fs::write(path, bytes)`。`GameView.gd:2695` 对 `.staged_version` 已实现了原子替换，但真正承载玩家进度的 `SaveDataNN.sav` 与 `System.sav` 没有临时文件保护；在 Android 杀后台、低电量断电或磁盘满时极易留下 0 字节/半截坏档。 | 改为先写入同目录 `.<name>.tmp`（调用 `file.sync_all()`），再通过 `std::fs::rename(tmp, path)` 原子替换（Windows 若目标存在且 `rename` 受限，可先备份 `.bak` 或使用原子替换策略）。 |
| **`PUB-03`** | **P2（并发输入）** | `crates/wolf-game/src/game.rs:167-169, 4185, 5938` | **恶作剧/并行轮询的并发输入与热区穿透**：① `mouse_key_bits()` 写入 `*self.mouse_consumed = true` 却未在入口检查 `*self.mouse_consumed`，同帧重叠热区可被 `ActionKey` 与 `op123` 双重触发；② `v100 != 0`（恶作剧模式）时 `handle_action_key_input()` 末尾仍执行 `action_key_at_excluding()`，可能穿透触发白天妹妹事件（`ev1..ev4`）；③ `STORY_COMMON_EVENTS` 仅含 `245..=259`，未覆盖 `CE284 / CE283 / CE290 / CE219 / CE220`。 | ① `mouse_key_bits()` 开头加 `if *self.mouse_consumed { return 0; }`；② `v100 != 0` 时跳过末尾的 `action_key_at_excluding`；③ 将 H 演出及事后处理事件纳入输入锁。 |
| **`PUB-04`** | **P2（Android 启动）** | `godot/scripts/GameView.gd:530, 2580-2715` | **Android 冷启动主线程同步拷贝 ~113 MB 存在 ANR 风险，且升级不清理旧孤儿文件**：`_prepare_android_storage()` 在 `_ready()` 主线程里同步分块拷贝全部 `android_data`（含 113 MB `media.pak`），低端安卓机首次启动或覆盖升级时易触发超过 5 秒的 ANR；同时升级时不清理旧版本已移除的文件（例如旧版释放的日文 `.ttf` 字体会永久残留在 `user://data/`）。 | ① 将首次释放改为后台 `Thread` 执行，主线程展示简易进度条/提示，完成后再 `wolf.open_with_save_dir`；② 释放完成后比对 `user://data/` 文件列表与新 manifest，清理不在新清单中的旧资源文件（严格避开 `user://Save/`）。 |
| **`PUB-05`** | **P2（发布隐私与可移植性）** | `AGENTS.md:15,19,51,68`；`docs/HANDOFF_M0.md:218,226`；`docs/HANDOFF_PROGRESS.md:123,1067`；`tools/audit-godot.sh:11`；`tools/audit-explore.sh:11`；`tools/env.sh:9-10`；`tools/env.ps1:6` | **公开发布仓残留个人邮箱、本机用户名与绝对路径**：公开发布仓内仍暴露作者个人邮箱、本机用户名与 `<local-path>` 等本地绝对路径；`audit-godot.sh` / `audit-explore.sh` 默认写死 `<godot-install>/...`。 | 在公开仓的 `AGENTS.md` 与工具脚本中移除个人邮箱和本机用户名，将 `audit-godot.sh` / `audit-explore.sh` 改为从 `PATH` 或 `GODOT_BIN` 环境变量探测；如不希望历史日志在公开仓暴露个人信息，可对 `docs/` 做脱敏替换。 |
| **`PUB-06`** | **P3（Android 测宽微差）** | `crates/wolf-gdext/src/lib.rs:1286-1293` | **Android 测宽字重与绘制字重略有偏差**：`install_font_metrics()` 优先加载 `NotoSansCJK-Regular.ttc`（Regular），而 Godot 普通文本多以 `weight = 700`（Bold）绘制。因 `WolfText.gd` 已关闭单行折行，不会再叠字，但右对齐文本可能出现 1–2 px 偏移。 | 可将 Android 候选列表优先尝试 `NotoSansCJK-Bold.ttc`（若存在），其次再回退 Regular 与默认 em 估算。 |

> **安全专项复核（通过）**：
> - `unsafe` 审计：全仓仅 4 处外部 FFI（`wolf-gdext` Win32 HICON、`wolf-launcher` `MessageBoxW`、`wolf-cli`/`wolf-gdext` `GetLocalTime`），边界检查完备（`checked_mul`、`try_from`、空句柄守卫），无越界或悬垂指针；核心 `wolf-game` 保持纯安全 Rust。
> - 路径穿越审计：`media_pack.rs:196`、`assets.rs:692`、`GameView.gd:2652` 均正确拦截了 `..`、绝对路径与驱动器冒号。

---

## 三、已有文档中“已忽略 / 延后 / 裁定非缺陷”项单独台账

以下条目均已在仓库历史文档中明确记录、裁定或主动搁置，**不计入上述新缺陷**，集中列示以便版本维护者追溯：

| 类别 | 位置 / 来源文档 | 具体内容 | 当前处置状态 |
| :--- | :--- | :--- | :--- |
| **源数据固有缺陷** | `crates/wolf-format/tests/m3_string_decode.rs:402` | `CE250` 第一项含奇数长度 `0xA1` 序列，属原版游戏数据本身缺陷，非解码器 Bug。 | 保留 `#[ignore]` 测试。 |
| **合成差异复现** | `docs/reviews/TASKS_REMAINING_BUGS.md` §0（四轮审查 §六 BUG-21） | 独立 map-self 协程未被 `install_map` 清理；仅在合成探针复现，真实零售数据影响未证实。 | 保留为 `#[ignore]` 回归。 |
| **已裁定非缺陷** | `docs/reviews/AUDIT_2411996_FIX_REPORT.md` §2（原 `F-01`） | Opcode 122 掩码 `0xFF00` / `0x0200`（`0x0010` 为间接目标位，改为 `0xFFF0` 会清空 `CE270` 名牌）。 | 正式裁定 `NOT_A_BUG`，禁止改动。 |
| **已裁定非缺陷** | `docs/reviews/TASKS_REMAINING_BUGS.md` §0（历史台账 BUG-22/23/24） | 字段 11/12 为帧间鼠标位移；空 Picture 范围 `Screen::effect` 返回 `false` 为无害 no-op；Sys15/16 默认档 14/8 为原版行为。 | 正式裁定非缺陷。 |
| **缺乏原版证据（暂不伪造）** | `docs/reviews/TASKS_REMAINING_BUGS.md` §0 / §0.1 | ① 侧栏仅支持点击三角把手开合，不实现按住拖拽；② 保存按钮不伪造 hover 高亮；③ `36014` 首框名牌字面量 `"message"` 与原版截图一致，不擅自隐藏；④ 哥哥体力条无独立图形槽位；⑤ 人物 alpha 轮廓命中与 `36002` 底边锚定规则。 | 按“无实机反证不臆造”原则保持现状。 |
| **跨作测试噪声** | `AGENTS.md` §2；`TASKS_REMAINING_BUGS.md` §0 | 全套 `wolf-game` 在本作数据下存在少量源自姊妹作（`imoto life`）的期望值差异（2 项 `db` 用例 + `late_night_bedtime_skips_to_next_evening`）。 | 长期已知，不视作本作运行时缺陷。 |

---

## 四、代码规范性、注释污染与精简策略审计

### 4.1 量化现状（生产源码，不含 `tests/` 与 `examples/`）

| 语言 / 代表文件 | 总行数 | 代码行 | 注释行 | 注释占比 | 历史/过程污染注释行 |
| :--- | ---: | ---: | ---: | ---: | ---: |
| **Rust 生产总计（86 文件，含 `gbk.rs`）** | 87,622 | 70,288 | 13,424 | 16.0% | **205** |
| **Rust 生产（剔除自动生成 `gbk.rs`）** | 65,760 | 48,437 | 13,416 | **21.7%** | **205** |
| └─ `crates/wolf-game/src/game.rs` | **8,718** | 6,141 | 2,165 | **26.1%** | **60** |
| └─ `crates/wolf-game/src/picture.rs` | **4,075** | 2,826 | 1,041 | **26.9%** | 5 |
| └─ `crates/wolf-game/src/textpic.rs` | 1,589 | 1,086 | 396 | **26.7%** | 2 |
| └─ `crates/wolf-vm/src/exec.rs` | **6,463** | 4,997 | 1,168 | 18.9% | 12 |
| └─ `crates/wolf-cli/src/main.rs` | **5,324** | 4,566 | 556 | 10.9% | 22 |
| **GDScript 生产总计（3 文件）** | 3,553 | 2,769 | 481 | 14.8% | **9** |
| └─ `godot/scripts/GameView.gd` | **2,978** | 2,384 | 319 | 11.8% | 5 |
| └─ `godot/scripts/WolfText.gd` | 279 | 138 | 124 | **47.3%** | 3 |

### 4.2 注释污染三大重灾区（最容易误导未来 Agent）

1. **“过去式叙事 / 考古日志”注释**（全仓 214+ 行）
   - 典型样本：`game.rs:101, 985, 2753, 4553, 6081`（`"It used to be left out..."`、`"`resume_loaded_map` used to swap..."`、`"A click outside the panel used to be swallowed..."`）、`GameView.gd:346`（`"The cache used to grow forever..."`）。
   - **危害**：未来 Agent 读到旧实现描述时，容易把“曾经的 Bug”误判为当前仍存在的行为或过度防御，同时白白消耗大量上下文 Token。
2. **临时会话编号与本地私密证据路径**
   - 典型样本：`game.rs:2756, 2763, 2779, 5240, 5439`（`BUG-08`、`BUG-02`、`report section 6 BUG-21`、`report section 1.3`）、`game.rs:215, 2911`（`ptr_sc/卧室_点击妹妹_首句话.png`）、`GameView.gd:342`（`report BUG-17`）。
   - **危害**：`BUG-XX` 存在两套冲突编号体系，且 `ptr_sc/` 不在公开仓中，未来 Agent 无法验证这些外部引用，甚至可能按错误编号重复修改。
3. **长篇数学/推导论文式头部注释**
   - 典型样本：`WolfText.gd:1-85`（单文件注释占 47.3%，顶部连续 80+ 行推导公式与旧实验对比）、`picture.rs` 与 `textpic.rs` 大量 15–30 行的段落式注释。
   - **危害**：代码与长注释一旦脱节，注释就变成高置信度的错误规格。

### 4.3 注释精简与结构自表达建议（直接可写入 `AGENTS.md`）

1. **确立“三不写、两保留”注释红线**：
   - **不写**“以前是什么样（`used to` / `previously`）”——变更历史属于 Git commit，不属于源码。
   - **不写**内部审查编号（`BUG-XX`、`T12/T13`、`report section X.Y`）和未入库本地路径（`ptr_sc/`、`work/out/`）。
   - **不写**复述代码字面逻辑的注释（如 `// Clear the list`）。
   - **仅保留①** WOLF RPG 引擎/零售数据的**非显然硬约束**（例如 `// Sys100 != 0: 深夜恶作剧态；CE284 以 action=0 停止 pattern 动画`），一句话说清 **Why**。
   - **仅保留②** `unsafe` 安全不变量（`// SAFETY: ...`）与公共 API 的简短 1 行摘要。
2. **用模块拆分和类型/命名替代注释**（优先治理 4 个超大“上帝文件”）：
   - **`crates/wolf-game/src/game.rs`（8,718 行）**：按职责拆分为子模块目录 `crates/wolf-game/src/game/`：
     - `mod.rs`（核心结构与 `frame()` 编排）
     - `save_grid.rs`（`CE131/CE94` 存档页布局、跳页、箭头点击、文字覆写）
     - `input.rs`（点击/选项/侧栏/相册/剧情锁门控）
     - `hud.rs`（顶栏行动力、气球抬升、`text_quads` 组装）
     - `host.rs`（`GameHost` trait 实现）
   - **`godot/scripts/GameView.gd`（2,978 行）**：拆出独立脚本 `AndroidStorage.gd`（资源释放）、`ModalLayer.gd`（弹窗层）、`TouchInput.gd`（触控手势与边沿映射）、`AudioBridge.gd`（音频缓存与播放），主脚本瘦身至 ~800 行以内。
   - **`crates/wolf-game/src/picture.rs`（4,075 行）**：拆分 `picture/effects.rs`（`290` 特效状态机）与 `picture/transition.rs`（补间与淡出）。
   - **消除裸魔数变量**：将散落的 `vars.get(100)`、`vars.get(66)`、`self_vars.get(611)`、`matches!(event, 14 | 95 | 131 | 132)` 收敛为带语义的常量模块（如 `mod wolf_var { pub const NIGHT_MODE: usize = 100; ... }`、`mod ce { pub const SAVE_GRID: u32 = 131; ... }`），代码本身即可自解释，天然省掉一半注释。

---

## 五、游戏包体体积精简与性能优化探索方向

当前 0.1.0 发行包基线：Windows Setup **147.8 MB** / Portable ZIP **159.4 MB** / Android APK **144.9 MB**（其中 `media.pak` 占 **113.0 MB**，包含 476 张 PNG + 195 张 JPG + 31 个 OGG + 20 个 MP3 + 11 个 WAV）。

### 5.1 包体体积精简方向（按投入产出比排序）

| 优先级 | 方向 | 预计减重 | 实现思路与风险评估 |
| :---: | :--- | :--- | :--- |
| **1** | **媒体资源重编码（PNG → 无损/近无损 WebP，WAV → OGG）** | **−40 ~ −60 MB** | `media.pak` 当前仅做 XOR 混淆、**完全未压缩**。476 张 PNG 与 195 张 JPG 占了绝大部分体积：① 零画质损失方案：对 PNG 跑 `oxipng -o 4 --strip safe` 可稳降 15–25%；② 高收益方案：将大图/CG（`cg/` 338 张、`Picture/` 309 张）转为 **WebP（无损或 Q90 近无损）**，11 个 `.wav` 转为 `.ogg`，`image` crate（启用 `webp` feature）与 Godot 均原生支持，仅需在 `media-pack` 构建期离线转码并在 `assets.rs` 探测 `.webp` 后缀，**不改原始 `work/Data`**。 |
| **2** | **定制裁剪 Godot 4.7.2 导出模板（仅留 2D + GLES3）** | **−20 ~ −30 MB** | 官方预编译模板包含 3D 渲染、Vulkan/D3D12、Jolt/GodotPhysics 3D、XR、Navigation、Text-to-Speech 等本项目完全不用的模块。用 SCons 编译一份 `disable_3d=yes disable_physics_3d=yes vulkan=no module_openxr_enabled=no ...` 的 2D-only 模板，Windows `.exe` 与 Android APK 引擎本体均可直接瘦身 20–30 MB。 |
| **3** | **Android 消除 `media.pak` 双份存储占用** | **手机端省 ~113 MB 空间** | 当前 APK 内含 113 MB `media.pak.blob`，首次启动又完整拷贝到 `user://data/media.pak`，实际占用手机 **~260 MB**。若打包时让 APK 内 `media.pak` 以 `STORED`（不压缩）存放，Rust 侧直接按 ZIP 偏移读取 APK 内的 `media.pak`（或利用 Godot `FileAccess` 随机 seek），可省去 113 MB 拷贝与冷启动等待。 |
| **4** | **Rust Release 编译体积优化** | **−2 ~ −4 MB** | 在根 `Cargo.toml` 新增 `[profile.release-dist]`（或调整 `[profile.release]`）：开启 `strip = "symbols"`、`lto = "fat"`、`panic = "abort"`（仅用于 `wolf-gdext` / `wolf-launcher` 发布，测试仍用默认 unwind）；对 Android 可额外测试 `opt-level = "s"`。 |
| **5** | **`media.pak` 内部支持帧级 zstd 压缩（备选）** | **−5 ~ −15 MB** | 若不转 WebP，可对 `media.pak` 中的 BMP/WAV/未压缩 PNG 启用按条目可选的 zstd 压缩（已压缩的 JPG/OGG/MP3 保持直存，避免无意义 CPU 解压开销）。 |

0.1.1 实施结果：方向 1（slim WebP）、方向 2（aggressive 2D/GLES3 模板）、
方向 3（APK 内 `STORED` 媒体包 + Godot `FileAccess` 直读）、方向 4
（`release-dist` fat LTO/strip/panic=abort）与方向 5（media.pak v2 逐条 zstd）
均已落地。相对 0.1.0，标准 Windows setup / zip / Android APK 为
122,256,849 / 128,605,811 / 125,675,650 B（约 −17.3% / −19.3% / −13.3%）；
slim 为 93,822,449 / 100,538,746 / 97,618,050 B（约 −36.5% / −36.9% / −32.6%）。
未达到原估的“双端 80 MB 以内”，剩余体积主要来自 Godot 引擎、CJK 字体与
已高压缩的音频/图像；继续压缩需要牺牲兼容性或画质，留待后续评估。

### 5.2 运行时性能优化方向

| 优先级 | 方向 | 瓶颈定位 | 优化方案 |
| :---: | :--- | :--- | :--- |
| **1** | **减少 `wolf-gdext::frame()` 每帧 FFI 字典分配** | `crates/wolf-gdext/src/lib.rs:515-715` 每帧为每个 sprite、text、sound 新建 `VarDictionary` 并通过 FFI 拷贝到 GDScript。 | ① 画面静止帧（VM 无视觉变更且 `atlas_revision` / 文本 fingerprint 未变）直接返回 `unchanged: true`，Godot 跳过字典遍历与 `queue_redraw()`；② 热路径 `sprites` 可改为扁平 `PackedFloat32Array`（每 quad 固定 stride）传递，大幅减少 GC 与 FFI 跨边界开销。 |
| **2** | **图集（Atlas）增量脏矩形上传** | 当前 `atlas_revision` 变化时通过 `atlas_pixels()` 将整个打包包围盒（数 MB RGBA）一次性回传 Godot 重建纹理。 | 维护每帧新增图块的脏矩形列表，Godot 侧仅在首次或扩容时重建 `ImageTexture`，新增小图时用 `Image.blit_rect()` + 局部更新，显著降低切图/立绘切换时的峰值卡顿（`wolf_max_ms`）。 |
| **3** | **Android 首次资源释放异步化** | `GameView.gd:530` 在 `_ready()` 主线程同步拷贝 113 MB，存在 ANR 与黑屏体验问题。 | 改用后台线程释放 + 主线程轻量加载提示画面（或按 §5.1 方向 3 实现 APK 直读 `media.pak` 彻底省去拷贝）。 |
| **4** | **大 CG 解码与音频预加载异步化** | `assets.rs` 与 `GameView.gd` 音频桥在首次命中大 CG/BGM 时于主线程同步读盘+解码，可能造成单帧掉帧。 | 对 `media.pak` 的大 PNG/JPG 解码增加轻量后台预取（如相册页预解当前可见缩略图，或利用 WebP 更快的解码速度降低单帧抖动）。 |

---

## 六、建议的下一步行动优先级

1. **已完成（0.1.1）**：`PUB-01`（9 个子 crate 移除 `license.workspace = true`）与 `PUB-02`（`savegame.rs::write_save` 原子写盘）已合入并通过本地 `cargo check` / 原子写测试。
2. **已完成（0.1.1）**：`PUB-03`（并发输入与热区穿透）、`PUB-04`（Android 异步释放 + 清理旧孤儿文件）以及 `PUB-05`（公开仓个人隐私与路径脱敏）已合入；Android 标准/slim 包已在真机验证。
3. **后续（v0.2.0）**：按第四章继续拆分 `game.rs` / `GameView.gd`；§5.2 的 FFI 扁平数组、图集增量上传、大图/音频异步解码仍待评估。WebP 与定制模板已在 0.1.1 落地，但包体未达到 80 MB 以内。
