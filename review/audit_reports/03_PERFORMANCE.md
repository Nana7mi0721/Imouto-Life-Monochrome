# 性能与内存审查报告 (`03_PERFORMANCE.md`)

> **云端环境声明**：本云端容器无 `rustc`/`cargo`、无 `work/Data`、无 Godot 4.7.2 与 Windows 运行时，因此**无法在当前机器实测 p50/p95/max 帧耗时与 RSS 曲线**。本文严格遵守《指南》§7.1 规则：**不把旧报告数字冒充当前 HEAD 实测**，仅列明静态代码热点归因、内存生命周期审计与待实机测量的场景表。

---

## 1. 实测场景表（云端状态：`UNVERIFIED_ENV`）

| 场景 | 入口 | 数据/存档 | 帧数 | p50 | p95 | max | 内存峰值/增量 | 备注 |
|---|---|---|---:|---:|---:|---:|---:|---|
| 标题冷启动 | `Game::new` → `prime_engine` → `start_title` | 缺 `work/Data` | - | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | 历史 T14 记录 `ready=110.1ms`（不可跨机器直接引用） |
| 读档卧室稳态 | `load_save` (`SaveData01.sav`) | 缺 `work/Data` | 600 | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | 历史 T14 记录 `wolf_avg=0.536ms / draw_avg=0.315ms` |
| 相册连续翻页 | `CE303` / 缩略图与 CG 浏览 | 缺 `work/Data` | - | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | **重点高风险内存场景**（`Assets.cache` 无上限） |
| 存档 UI 打开与翻页 | `CE14` → `CE131` 3 页切换 | 缺 `work/Data` | - | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | 含 `m3_perf_baseline` 基准待跑 |
| 返回标题重复进出 | 自由地图 `Esc` → 标题 → 读档循环 | 缺 `work/Data` | - | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | `UNVERIFIED_ENV` | 验证 `Assets::clear()` 缺失导致的 RSS 变化 |

---

## 2. §7.2 核心热点静态审计

### 2.1 VM 调度 (`crates/wolf-vm/src/exec.rs`)
- **帧预算机制**：`DEFAULT_BUDGET = 200_000`（`exec.rs:54`），`MAX_INSTANCES = 4_096`（`exec.rs:59`）。预算耗尽时 `execute()` 返回 `Signal::Continue`（`exec.rs:2351-2355`）并在下一帧从当前 `pc` 继续，不会挂死进程。
- **静态风险**：
  - `run_instances()`（`exec.rs:1507`）对每个可运行实例在循环内反查 `foreground_event`，在实例数量不多（通常 < 20）时开销极微；但若未来出现大量并行协程，属于 O(N²) 扫描。
  - `hot_trace` 开启时使用 `Vec<(usize, u64)>` 线性查找（`exec.rs:2360`），仅影响 `--hot` 诊断模式，不影响正常游玩。

### 2.2 Assets 缓存与内存生命周期 (`crates/wolf-game/src/assets.rs`)
- **已证实问题 (`F-10`, E1)**：`Assets::cache`（`HashMap<String, ImageData>`）与 `alpha_bounds_cache` **没有任何容量上限或字节预算淘汰策略**。
- **`Assets::clear()` 孤立**：`assets.rs:323-327` 的文档注释写明 `"Called when returning to the title."`，但全仓检索显示生产代码（包括 `Game::reset_to_title()` 与 `savegame::load_into()`）**从未调用 `assets.clear()`**。
- **负缓存与二级键**：`missing: HashSet<String>` 有效避免缺失资源每帧重复 I/O；`alpha_bounds_in` 的两级 `HashMap` 避免了热区命中测试时的字符串分配与每帧 19 万像素全图扫描（T12 已落地）。
- **结论**：长会话浏览相册（`cg/`）或多次往返标题后，已解码的 RGBA 图像将持续驻留内存；需在实机上通过长会话 RSS 采样验证具体峰值。

### 2.3 Atlas 与 Godot 渲染 (`crates/wolf-game/src/atlas.rs`, `crates/wolf-gdext/src/lib.rs`, `godot/scripts/GameView.gd`)
- **内容包围盒上传（已落地）**：`Atlas` 内部保持 4096×4096 页以稳定 UV，但通过 `content_bounds()` 仅向 Godot 上传实际打包的最小矩形区域（T13 修复，消除了整页 64 MiB 重复上传）。
- **TileMap 桥接**：玩法前端（`wolf-gdext` 与 `GameView.gd`）已完全移除 `tile_quads` / `tile_pixels` 调用，`TileMap::quads()` 仅保留给 `wolf-cli` 离线取证/截图工具使用。
- **跨语言字典构造开销（P3 持续存在）**：`crates/wolf-gdext/src/lib.rs:300-410` 每帧仍为每个可见 sprite/text/sound 重新创建 `VarDictionary` 并推入 GDScript `Array`，`GameView.gd` 侧每帧按 batch 分组与排序。在当前 50 个左右 sprite/text 规模下（历史实测约 0.3~0.5ms）可接受，但若后续特效增多需注意 FFI 分配成本。

### 2.4 文本渲染 (`godot/scripts/WolfText.gd`, `crates/wolf-game/src/game.rs`)
- **Rust 侧**：`text_quads()` 使用 `TextQuadKey` 缓存；`rendered_message_layout()` 在 `wolf-gdext::frame()` 中已合并为每帧计算一次（T13 已修）。
- **Godot 侧**：`WolfText.gd` 实现了 256 项 `TextParagraph` 缓存，避免每帧重新塑形文本。
- **冷启动字体双读**：Rust (`cosmic-text`) 与 Godot (`FontFile`) 各自加载字体（约 16.9 MB），属一次性启动百毫秒级成本（`AUDIT_REBUILD_FIX_REPORT.md` 已裁定不合并生命周期）。

### 2.5 音频缓存 (`godot/scripts/GameView.gd:267-272`)
- `GameView.gd` 已增加 `AUDIO_CACHE_LIMIT := 64` 并在淘汰时跳过 `bgm_player`/`bgs_player`/`se_players` 正在引用的流。
- **边界风险**：按**条目数（64 个）**而非**解码后 PCM/流字节大小**限制；若存在多个超长无压缩 WAV 或大体积 BGM，按数量淘汰的上限仍偏宽松（P3）。

### 2.6 存档 UI (`crates/wolf-game/src/savegame.rs`, `godot/scripts/GameView.gd`)
- 161/162 冻结帧仅在进入冻结时回读一次并复用 `frozen_texture`。
- `PictureAction::Move` 仍存在 `for n in lo..=hi` 逐整数遍历（`picture.rs:1433`，见 `F-09`），在正常小区间（如 `36008..=36012`）无感，但在极端/错误 `span` 参数下会产生 O(span) 尖刺。
- `savegame::build_save_bytes`（保存写盘）在当前架构下于玩家点击保存或晚饭后槽 1 自动存档瞬间同步执行，可能造成单帧几十毫秒级 I/O 毛刺（建议实机采样确认是否需要异步写盘）。
