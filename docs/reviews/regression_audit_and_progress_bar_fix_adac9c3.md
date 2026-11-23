# Imouto-Life-Monochrome (`adac9c3`) 历史问题全量防复发梳理与“进度条残留”复发根因报告

- **审查基线**：最新提交 `adac9c34646e868c5fc9ef64a9201d495487e707`（`v0.1.2`）
- **梳理来源**：`docs/HANDOFF_M0.md`、`docs/HANDOFF_PROGRESS.md` 及 `docs/reviews/` 全部现行审查/修复报告（按约定排除已归档的 `docs/archive/ui_and_interaction_diagnosis_report.md`）
- **核心目标**：
  1. 彻底查明**“有进度条的事件被打断时，格子进度条残留在画面上不消失”**这一老 Bug 复发的精确根因，并给出与旧修复零冲突的根治方案；
  2. 全量梳理历次 review 与 handoff 中已查明并解决的问题，在 `adac9c3` 源码中逐项核验是否存在复发或回退；
  3. 建立**新老修复冲突雷区矩阵**与**回归护栏清单**，防止后续改动引发“修新崩旧”。

---

## 一、老 Bug 复发深挖：有进度条的事件被打断后，格子进度条残留

### 1.1 历史修复回顾（`LIVE_PLAY #3`）
在 2026-11-15 的 `docs/reviews/LIVE_PLAY_FIX_REPORT.md` §1.3 中，项目新增了 `crates/wolf-game/src/raid_cleanup.rs` 与回归测试 `crates/wolf-game/tests/m22_raid_cleanup.rs`（5 条），在 `Game::frame()`（`crates/wolf-game/src/game.rs:5170`）调度器之前调用 `sync_raid_hud(self)`，试图在夜袭场景结束的下降沿清掉闸门变量并擦除进度条图片槽位。

### 1.2 为什么会重新出现？（4 处代码级 + 字节码级实锤缺口）

经全量扫描原版 550 个公共事件（`_ce_full.json`）与 `SampleMapA.mps`（`map_full.json`），全作共有 **8 个并行进度条绘制事件**（使用 `\img[Picture\box01.png]` / `box02.png`），分布在 **6 类场景** 与 **3 组图片槽位** 中。对比 `crates/wolf-game/src/raid_cleanup.rs`，该模块存在 **4 处直接导致复发的硬伤**：

| 维度 | 原版字节码实际行为 | `raid_cleanup.rs` 当前实现 | 导致的复发现象 |
| --- | --- | --- | --- |
| **1. 场景监听名单不全** | 除 `CE 249 (┣お風呂)`、`CE 256 (日中メニュー)`、`CE 259 (休日メニュー)` 外，还有：<br>• **夜间恶作剧**：`SampleMapA Ev 17/18/19` → `CE 283`（`v100 >= 1`，全程不启动 `249/256/259`）<br>• **厕所**：`CE 295 (トイレ処理)` → `CE 293`<br>• **素股**：`CE 298 (素股処理)` → `CE 300` | `RAID_SCENE_EVENTS = &[249, 256, 259]`（`raid_cleanup.rs:41`） | 在**夜间恶作剧、厕所、素股**中途被打断或点“结束”时，`raid_scene_running()` 从未变为 `true`，`sync_raid_hud()` **一次都不会触发** |
| **2. 闸门变量漏清 4 个** | 8 个并行计时器的启动变量为：<br>`v90`（`CE 279`）、`v91`（`CE 281`）、`v92`（`CE 282`）、`v154`（`CE 277`）、<br>**`v155`（`CE 274 お風呂タイマー1`）**、<br>**`v160`（`CE 273 お風呂タイマー2`）**、<br>**`v170`（`CE 294 トイレタイマー1`）**、<br>**`v178`（`CE 299 素股タイマー`）** | `RAID_GATE_VARS = &[90, 91, 92, 154]`（`raid_cleanup.rs:56`） | 哪怕在已被监听的 `CE 249 (┣お風呂)` 里，由 `CE 275` 拉起的 `CE 273/274`（`v160/v155`）也不会被关掉，退出后继续把格子条画回屏幕 |
| **3. 图片擦除槽位不全** | • `CE 279 / 281` 画 `500..=501`<br>• `CE 282` 画 `502..=503`<br>• **`CE 273 / 274 / 294 / 299` 画 `510..=511`**<br>• **`CE 277 (警戒度)` 画 `500..=502` 与 `520..=521`**（`CE 249` 正常收尾也会擦 `500..=521` / `510..=511` / `520..=521`） | `RAID_BAND_START = 500`、`RAID_BAND_END = 503`（`raid_cleanup.rs:44-47`） | `510..=511`（浴室/厕所/素股进度条）和 `520..=521`（警戒度条）完全在擦除范围之外，永远残留 |
| **4. 单槽守卫判断 Bug** | 左侧计时器 `CE 282` 只画 `502..=503`，不画 `500`；浴室/厕所/素股只画 `510..=511`，不画 `500` | `if game.screen.get(RAID_BAND_START).is_some()`（`raid_cleanup.rs:98`） | 只要 `Picture 500` 恰好不在屏幕上，**哪怕 `501/502/503` 都在，`erase_band()` 也直接被跳过** |

### 1.3 零冲突修复方案（完全兼容现有 `m22_raid_cleanup` 5 条回归）

改造范围收敛在 `crates/wolf-game/src/raid_cleanup.rs` 与 `crates/wolf-game/src/game.rs`（读档/回标题状态复位），不触碰任何渲染锚点、输入消费或 VM 核心语义：

1. **补齐全部场景与夜间恶作剧态下降沿监听**：
   - 扩展 `RAID_SCENE_EVENTS`：`&[249, 256, 259, 295, 298]`；
   - 在 `raid_scene_running(vm)`（或新建 `meter_owner_active(vm)`）中同时纳入夜间恶作剧状态 `vm.vars.get(100) != 0`：
     ```rust
     pub const RAID_SCENE_EVENTS: &[u32] = &[249, 256, 259, 295, 298];

     pub fn raid_scene_running(vm: &Vm) -> bool {
         vm.vars.get(100) != 0
             || vm.instances().iter().any(|instance| {
                 instance.program.self_base == COMMON_SELF_BASE
                     && RAID_SCENE_EVENTS.contains(&instance.event)
             })
     }
     ```
   - 保持原有的**下降沿触发**（`was_running && !running`），因此事件正常进行期间绝不误擦任何进度条，也不会影响现有 `m22_raid_cleanup::the_teardown_only_fires_when_the_scene_ends`。
2. **补齐全部 8 个进度条闸门变量**：
   ```rust
   pub const RAID_GATE_VARS: &[usize] = &[90, 91, 92, 154, 155, 160, 170, 178];
   ```
   因为 `sync_raid_hud(self)` 运行在 `self.auto_events.sync(&mut self.vm)` 之前（`game.rs:5170-5171`），清零这些变量后，同帧 `auto_events.sync()` 会立刻 `stop_instance` 终止仍在 `Wait` 中的 `CE 273/274/277/279/281/282/294/299`，杜绝“刚擦掉下一帧又被并行协程画回来”。
3. **补齐 3 组槽位擦除并修复 `get(500)` 单槽守卫 Bug**：
   ```rust
   pub const RAID_BANDS: &[(i32, i32)] = &[
       (500, 503), // CE 277 / 279 / 281 / 282
       (510, 511), // CE 273 / 274 / 294 / 299
       (520, 521), // CE 277 警戒度扩展槽
   ];

   pub fn clear_raid_hud(game: &mut Game) -> bool {
       let mut changed = false;
       for index in RAID_GATE_VARS {
           if game.vm.vars.get(*index) != 0 {
               game.vm.vars.set(*index, 0);
               changed = true;
           }
       }
       for &(start, end) in RAID_BANDS {
           if (start..=end).any(|slot| game.screen.get(slot).is_some()) {
               game.screen.apply(&erase_range(start, end));
               changed = true;
           }
       }
       changed
   }
   ```
   - 精确分段只擦 `500..=503`、`510..=511`、`520..=521`，不波及 `600` 等其他 HUD 槽位，完全兼容 `the_teardown_leaves_the_rest_of_the_picture_layer_alone`。
4. **跨会话状态复位**：在 `Game::reset_to_title()` 与 `220 SaveLoad` 读档成功分支中调用 `self.auto_events.set_raid_scene_active(crate::raid_cleanup::raid_scene_running(&self.vm))`，防止“在夜袭中读档/回标题”后旧的 `was_running` 残留触发误擦或漏擦。
5. **建议新增回归测试（追加至 `m22_raid_cleanup.rs`）**：
   - 仅存在 `502/503`（无 `500`）时，场景结束必须擦除 `502/503`；
   - 夜间恶作剧（`v100 = 1 -> 0`）中断时，必须清 `v91/v92` 并擦 `500..=503`；
   - 浴室/厕所/素股（`CE 249/295/298`）中断时，必须清 `v155/v160/v170/v178` 并擦 `510..=511`、`520..=521`。

---

## 二、全量 Review 与 Handoff 已解决问题防复发核验总账（基线 `adac9c3`）

经逐项对照 `docs/HANDOFF_M0.md`、`docs/HANDOFF_PROGRESS.md` 及 `docs/reviews/` 全部现行修复报告，**除上述 `LIVE_PLAY #3` 进度条残留为局部漏覆盖复发外，其余全部历史已修项在 `adac9c3` 中均保持完好，未出现代码回退**。完整台账如下：

### 2.1 核心引擎与虚拟机（`CODE_REVIEW_4ROUND.md` / `HANDOFF_DEEP_REVIEW_FIX.md`）

| 批次 / 编号 | 已解决的核心问题 | `adac9c3` 核验状态 | 关键代码落点与锁死测试 |
| --- | --- | --- | --- |
| **BUG-01..19** | 对话人名框、相对 `210/211` 寻址、存档开关锁死 HUD 图标、选项框外左键取消（`BUG-18`）、音频同曲重触发（`BUG-17`）等 | **完好** | `wolf-vm/src/exec.rs`、`wolf-audio/src/engine.rs`、`m3_hud_buttons`、`m3_mouse_menu` |
| **BUG-25 / 26** | `AutoEvents::sync` 改为电平触发（`CE 43` 例外走上升沿 + 光标重放）；`ENGINE_RESTART` 补齐常时并行事件 | **完好** | `crates/wolf-game/src/auto_events.rs`、`game.rs`、`m16_vm_scheduler` |
| **BUG-27..29** | `Op121` 二阶指针与 `SelfVar` 批量赋值、`Op124 Field 18` 前台事件 ID、跨事件 `15_000_000+` 实时读写同步 | **完好** | `crates/wolf-vm/src/exec.rs`、`m16_runtime_state` |
| **BUG-30 / 36 / 37** | 同帧输入竞争（后演进为 `PUB-03` + `mouse_consumed_bits`）、`Op176 ContinueLoop` 纠偏、`Op140` 音频参数 `eval_num` 与 CRLF 音效 cell 拆分 | **完好** | `game.rs`、`exec.rs`、`m16_parallel_input` |
| **BUG-41..48** | 读档 BGM 队列同帧 flush、`Op250` 字符串槽写入、滚轮 `Field 10`、`blend` 混合、`character_state`、`picture_state` 像素宽高、`Op150 Erase` 淡出与 `Move` 取消 `Erase` 过渡 | **完好** | `savegame.rs`、`picture.rs`、`atlas.rs`、`game.rs`、`m19_picture_motion` |
| **F-01（误报裁定）** | `Opcode 122` 掩码保持 `0xFF00`（`0x0010` 为变量目标标志，不可改为 `0xFFF0`） | **完好** | `crates/wolf-vm/src/exec.rs`、`docs/engine/OPCODE_122.md` |

### 2.2 UI、文本、视觉与实机交互（`T13` / `AUDIT_REBUILD` / `1c76dcc` / `LIVE_PLAY` / `a2a618d`）

| 批次 / 编号 | 已解决的核心问题 | `adac9c3` 核验状态 | 关键代码落点与锁死测试 |
| --- | --- | --- | --- |
| **T13 / T14 / Rebuild** | 移除玩法前端瓦片桥接、停靠侧栏 `0.2` alpha 与双三角把手命中、原生/气泡对话去重、开场 `230` 孤立空槽消除、三位数行动力右对齐 | **完好** | `game.rs`、`m14_visual_regression`、`m17_ui_regressions` |
| **1c76dcc P1** | `TextQuadKey` 计入 `balloon_frame_growth()`，流式多行正文时人名牌 `36014` 同步上移 | **完好** | `crates/wolf-game/src/game.rs`、`m4_load_resume` |
| **LIVE_PLAY #1 / #2** | 气泡模式全程屏蔽原生 `19500..=19503` 防闪大头像；气泡高 `107`、头像底 `558` | **完好** | `game.rs`、`m19_balloon_ui` |
| **LIVE_PLAY #3** | **有进度条的事件被打断后格子进度条残留** | **存在局部复发** | `raid_cleanup.rs` 漏夜间恶作剧/厕所/素股、漏 `v155/160/170/178`、漏 `510..=511`/`520..=521` 及 `get(500)` 单槽守卫 Bug（见 §一） |
| **LIVE_PLAY #4 / #5a / #5b** | 恶作剧光标移出热区回落 `hand3`（`cursor_fallback.rs`）；BAD/GOOD 粗细统一 8；同图同位重绘保留呼吸/缩放/图案动画 | **完好** | `cursor_fallback.rs`、`picture.rs`、`m21_cursor_hover`、`m24_live_play_rulings` |
| **LIVE_PLAY #6 / #7 / #8 / #9** | CP932 否决 `U+FF61..FF64` 防 GBK 乱码；顶栏 `y < 36` 几何遮挡判定；黑幕 `Move` 渐变 `fade_from`；侧拉栏双向补间；本地时钟 `GetLocalTime`；读档 `.mps` 路径 | **完好** | `game.rs`、`picture.rs`、`m19_balloon_ui`、`m19_picture_motion`、`m23_map_path` |
| **M27 / a2a618d** | 无 `421` 选项框禁止 `CANCEL` 穿透；枕头 `Ev 13` 优先于睡姿；恶作剧空道具框不触发换姿势；存档预选高亮 `12051 + 20*row` 实时跟随；正文右下偏移 `12/6` | **完好** | `exec.rs`、`game.rs`、`m27_choice_cancel`、`m27_opening_choice_cancel` |

### 2.3 云端审计、跨平台与发布安全（`2411996` / `e716f08` / `PUB-01..06` / `bedd7a1` / `3a89a8a`）

| 批次 / 编号 | 已解决的核心问题 | `adac9c3` 核验状态 | 关键代码落点与锁死测试 |
| --- | --- | --- | --- |
| **2411996 F-02..F-12** | Godot 导出预设与插件隔离、启动错误面板、坏 checksum 仅警告、发行包纯净 `System.sav`、动作键窄回退（仅 `5\|21\|22\|28` 跳过 `v100`）、`150 Move` 改 `BTreeMap::range`、回标题 `assets.clear()`、F11 优先响应 | **完好** | `game.rs`、`picture.rs`、`map_runtime.rs`、`GameView.gd`、`export_presets.cfg` |
| **e716f08 F-07 / F-11 / R-01..03** | 模态弹窗暂停 `wolf.frame()`；`\img` 纯图片条与图文混排分层及 anchor/scale/alpha；`Assets` 256 MiB 近似 LRU 上限；媒体包补齐内联格子素材 | **完好** | `GameView.gd`、`textpic.rs`、`atlas.rs`、`assets.rs` |
| **PUB-01..06 + Android/iOS** | 存档原子写（`.tmp` + `sync_all` + `rename`）；并发输入单消费者 + `STORY_COMMON_EVENTS`；Android 后台线程释放 + APK 内直读 `media.pak.blob.cfb`；iOS 隐藏 `menu3` 退出项；NSIS Low 完整性修复 | **完好** | `savegame.rs`、`game.rs`、`GameView.gd`、`wolf-gdext`、`normalize_windows_integrity.sh` |
| **bedd7a1 H1..H3 / M1..M4** | iOS 文件选择器改主线程队列轮询 + 安全作用域内目录判定；ZIP 中央目录限额 + `validate_save_bytes`；`media.pak` zstd 解压上限 `decompress_with_limit`；`wolf-audio` 去掉 3 处裸 `unwrap`；Windows 原子覆盖 `MoveFileExW`；整仓 Clippy `-D warnings` 清零 | **完好** | `ios_file_picker.rs/.mm`、`GameView.gd`、`media_pack.rs`、`wolf-audio/src/engine.rs`、`wolf-gdext/src/lib.rs` |
| **3a89a8a 输入与读档修复** | `mouse_consumed` 改为按位 `mouse_consumed_bits`（解决右键取消连带抹除同帧左键）；`220 SaveLoad` 新增 `resume_loaded_map_with_fallback()` 防止缺图软锁 | **完好** | `game.rs:1143, 4073, 5120, 6048`、`m4_load_resume`、`m16_parallel_input` |

---

## 三、新老修复冲突雷区矩阵（防“修新崩旧”守则）

为确保后续修复（包括本次进度条清理扩展及未来迭代）不再和历史修复打架，以下 **8 个高耦合雷区** 在修改前必须逐条核对：

| 雷区编号 | 耦合子系统 | 绝对不可破坏的历史契约 | 容易引发冲突的错误改法 | 必跑回归测试 |
| --- | --- | --- | --- | --- |
| **C-01** | **输入消费 (`mouse_consumed_bits`)** | `PUB-03` + `3a89a8a` + `adac9c3`：**按位独立消费**（`OK`/`CANCEL` 互不连坐）且维持 `123` 同位单消费者契约 | 将非等待 `123` 改为无约束广播（会打崩 `m16_parallel_input`），或回退成单 `bool`（会复发 `Ev 15` 吞 `Ev 16`） | `m16_parallel_input`、`m3_mouse_menu`、`m3_title_mouse` |
| **C-02** | **动作键回退 (`picture_action_event_at`)** | `F-08`：仅对 `5\|21\|22\|28` 放宽且**只跳过 `v100`**，保留 `v69/v125/v176/v238` 门控；恶作剧态跳过通用动作热区 | 扩大忽略条件的事件名单或跳过所有变量条件（会复发剧情/相册期间点穿） | `m3_hud_buttons`、`m3_map_click` |
| **C-03** | **进度条清理 (`raid_cleanup.rs`)** | `LIVE_PLAY #3`：必须在 `auto_events.sync()` **之前**执行，且仅在活跃场景/恶作剧态**下降沿**清理指定进度条槽位 | 改为电平持续清零（会导致正常游玩时进度条画不出来），或整段盲擦 `500..=650`（会误杀 `Picture 600`） | `m22_raid_cleanup` |
| **C-04** | **气泡对话与原生槽位** | `T13` + `1c76dcc` + `LIVE_PLAY #1/#2` + `a2a618d`：气泡模式全程屏蔽 `19500..=19503`；高 `107`/底 `558`/正文偏 `12,6`；`TextQuadKey` 含 `balloon_frame_growth` | 改回瞬态 `balloon_visuals_active()` 屏蔽（会复发右下角闪大头像），或改动 `TextQuadKey` 漏掉 lift（会复发人名牌错位） | `m19_balloon_ui`、`m17_ui_regressions`、`m17_text_layer` |
| **C-05** | **图片动画与淡出 (`picture.rs`)** | `BUG-48` + `LIVE_PLAY #5b/#8` + `F-09`：同图同位重绘保留 `breath/zoom/pattern`；瞬时 `Move` 清 `transition`；淡出走 `fade_from`；区间移动用 `BTreeMap::range` | 重绘时直接 `Picture::new()` 覆盖（会复发睡眠图标不呼吸），或 `Move` 漏清 `transition`（会复发淡出后隐身） | `m19_picture_motion`、`m14_visual_regression` |
| **C-06** | **内联格子条 (`\img`) 与文本编码** | `F-11` + `LIVE_PLAY #6`：`box01/02` 仅走 `atlas` 贴图 pass（绝不恢复 `inline_box_glyph` 字符映射）；CP932 否决上界严格止于 `U+FF64`（不含 `U+FF65`） | 放宽编码否决到 `U+FF65`（会打崩 4 处 `op250` 数据库寻址），或在文本层画 Unicode 方块（会复发格子双重叠影） | `m3_string_decode`、`m3_visual_text` |
| **C-07** | **Opcode 122 与 102 取消** | `F-01`（`0xFF00` 不可动）+ `M27`（无 `421` 禁止 `CANCEL` 穿透，且 `handle_choice_input` 消费不可取消按键边沿） | 把 `122` 掩码改成 `0xFFF0`（会清空 `CE 270` 名牌），或让无 `421` 的 `102` 回落块尾（会复发开场取消跳过问答） | `m27_choice_cancel`、`m27_opening_choice_cancel` |
| **C-08** | **移动端媒体包与存档安全** | `PUB-02/04` + `bedd7a1 H1..H3`：APK 内 `media.pak.blob.cfb` 必须 `STORED`；覆盖安装不删 `Save/`；ZIP 导入必过限额与 `validate_save_bytes`；iOS 选择器走主线程轮询队列 | 在 `GameView.gd` 中恢复同步释放或去掉 `.blob` 后缀（会复发字体丢失与媒体包二次拷贝），或恢复 `thread_local!` 回调（会复发 iOS 锁死） | `save_transfer.gd`、`android_staging_async.gd`、`m8_android_touch` |

---

## 四、建议落地顺序

1. **优先修复本次复发 Bug**：按 §1.3 修改 `crates/wolf-game/src/raid_cleanup.rs`（扩场景 + 扩夜间 `v100` + 扩 8 个闸门变量 + 分段擦 `500..=503 / 510..=511 / 520..=521` + 修 `get(500)` 单槽守卫），并在 `game.rs` 的读档与回标题路径复位 `raid_scene_active`。
2. **补齐防复发单测**：在 `crates/wolf-game/tests/m22_raid_cleanup.rs` 追加 3 条回归（单左侧条 `502/503` 无 `500`、夜间恶作剧 `v100` 中断、浴室/厕所/素股 `510..=511` 中断）。
3. **发版前全量门禁**：执行 `cargo fmt --check`、`cargo clippy --workspace --all-targets -- -D warnings`、关键回归集（`m14/m16/m17/m19/m21/m22/m23/m24/m27`）及 `tools/smoke-godot.sh`，确认 8 大雷区零冲突后再推进 `v0.1.2` 发布。

## 五、修复落地状态（2026-11-23）

报告 §1.2 的 4 处缺口已逐项用 `work/Data` 的真实事件头核实并修复：

- `RAID_SCENE_EVENTS` 扩为 `249/256/259/295/298`；
- `raid_scene_running()` 增加 `v100 != 0` 的 deep-night 生命周期；
- `RAID_GATE_VARS` 扩为 `90/91/92/154/155/160/170/178`；
- 擦除改为精确分段 `500..=503`、`510..=511`、`520..=521`，并移除
  “必须存在 slot 500”的单槽守卫；
- `220 SaveLoad` 成功分支与 `reset_to_title()` 重新同步
  `auto_events.raid_scene_active`，避免跨会话残留旧沿。

`crates/wolf-game/tests/m22_raid_cleanup.rs` 从 5 条增至 9 条，新增：
无 slot 500 的左半条、夜间 `v100` 退出、厕所/素股 extra bands、
以及 8 个真实 `CommonEvent.dat` 头字段锁死。

验证：

- `cargo fmt --all -- --check`；
- `cargo clippy --workspace --all-targets -- -D warnings`；
- `m22_raid_cleanup` 9/9；
- `m16_runtime_state` 9/9、`m4_load_resume` 10/10、
  `m25_cursor_follow` 10/10、`public_release_input_guards` 5/5；
- 其余相关集 `m19_balloon_ui` 3/3、`m19_picture_motion` 14/14、
  `m21_cursor_hover` 7/7、`m23_map_path` 1/1、`m24_live_play_rulings`
  2/2、`m27_opening_choice_cancel` 5/5、`wolf-vm m27_choice_cancel`
  3/3；
- `wolf-game --lib` 377 passed / 6 failed，`m3_night_interaction` 4/6、
  `m3_night_interaction_e2e` 5/7、`m17_ui_regressions` 22/23；
  这些失败已在未修改的 `adac9c3` 基线复跑并原样出现，属于既有
  数据库/事件夹具漂移，不是本次回归。

注意：现有 `work/out/dist` 下的 0.1.2 包由提交 `3ff1fe9` 构建，
**不包含本次修复**；正式发布前必须从当前源码重打。

## 六、追加修复：开局随机称号 `³ç` 乱码（2026-11-23）

实机顶栏出现 `池面 ³ç 哥哥（学生）`。核查后确认这不是 CP932/GBK
解码误判：

- `work/Data/BasicData/DataBase.dat` 的 type 25「ランダム肩書」row 1
  （肩書2）column 9 原始内容就是 UTF-8 字符 `³ç `（字节
  `C2 B3 C3 A7 20 00`），`decode_wolf_str` 会把它当作合法 UTF-8 正常返回。
- 开局 `ev0` 通过 `250 Data.25[1,self[101]]` 把它读入字符串变量 `s[0]`，
  再写入 `CData 0:12:1` 供顶栏显示，因此 `³ç` 会原样上屏。

修复落在 `crates/wolf-game/src/db.rs`：

- 数据库加载时仅修复这一已知损坏格，`³ç` → `帅哥`（保留尾随空格）；
  所有索引有存在性保护，Mod 或已修正数据不受影响；
- `apply_saved_database()` 同步修复旧存档 `CData 0:12:0/1` 中已保存的
  同一乱码，保证读档后顶栏也正常；
- 新增 `crates/wolf-game/tests/m28_database_text_repair.rs` 与两条
  `db.rs` 单元回归。
