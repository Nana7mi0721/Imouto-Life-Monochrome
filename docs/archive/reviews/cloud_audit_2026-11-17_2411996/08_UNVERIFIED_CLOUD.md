# 云端环境无法验证项目清单 (`08_UNVERIFIED_CLOUD.md`)

> **归档说明（2026-11-18）**：本文为2026-11-17 云端只读全量审查（基线 `2411996`）的组成部分，内容已被 [`docs/reviews/cloud_audit_2026-11-18_e716f08/`](../../../reviews/cloud_audit_2026-11-18_e716f08) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


> 严格遵循《指南》§1、§2.2–2.4、§4.3 与 §12 原则：**凡云端缺少工具链、数据根、Godot 或 Windows 运行时导致无法实测的项目，一律明确列为 `UNVERIFIED_ENV`，绝不用“未发现问题”替代“无法验证”。**

---

## 1. 环境缺失清单

1. **Rust 工具链缺失**：容器内无 `rustc` 与 `cargo`（`rust-toolchain.toml` 无法生效）。
2. **游戏数据包缺失**：`work/Data/`（约 176 MB 解包数据）与 `Data.wolf`（VER6 原包）均不在 `master` 压缩包中。
3. **Godot 与 Windows 运行时缺失**：无 `Godot_v4.7.2-stable_win64.exe`，无 MSVC/MinGW 链接环境，无法编译 `wolf_gdext.dll`。
4. **实机截图与 Git 历史缺失**：压缩包不含 `.git` 目录（无法执行 `git log`/`git diff --check`），不含 `prt sc/` / `ptr_sc/` 实机对照截图。

---

## 2. 受影响而无法验证的审计项 (`UNVERIFIED_ENV`)

### 2.1 编译、格式化与静态检查
- `cargo fmt --all -- --check`
- `cargo check -q --workspace`
- `cargo clippy --workspace`
- `git diff --check`

### 2.2 单元测试与真实数据集成测试
- `cargo test -q --workspace --no-fail-fast`（无数据模式）的实际通过/失败数与 `skipping` 日志实测。
- `WOLF_DATA_ROOT="$AUDIT_DATA" cargo test -q --workspace --no-fail-fast`（有数据模式）的真实断言执行数、8 项长期基线红灯及 `m3_status_panel::ce238_relative_panel_lands_at_the_left_edge` 当前状态。
- `wolf-cli verify`（目标基线 PASS 64 / 1 SKIP）、`wolf-cli verify --wolf Data.wolf`、`wolf-cli precompile`。
- 存档隔离哈希前后比对（`Save/` SHA-256 diff）。

### 2.3 性能与内存实测
- `m3_perf_baseline` 在当前 `HEAD`（`24119960904011cbf5c0d0d4a7246a9d11fcf22b`）下的实际耗时。
- Godot 窗口实测的 p50 / p95 / max 帧耗时（标题冷启动、读档卧室、相册翻页、存档 UI、返回标题循环）与长会话 RSS 增长曲线。

### 2.4 素材引用与裁剪核验
- `wolf-cli assets --root "$AUDIT_DATA" --include-maps --format json`
- `wolf-cli assets --coords` 与 `--db-defaults`
- `m3_asset_refs` 测试及各目录（尤其是 `BattleEffect/`、未注册地图、字体）实际磁盘字节数与动态路径可达性裁决。

### 2.5 Godot 运行时、视觉与交互实测
- `tools/build-godot.sh` 编译生成 `wolf_gdext.dll`。
- `tools/smoke-godot.sh` 全部 9+1 个 headless 脚本与 `parity-godot.sh 600 --pixel-check=600`。
- 窗口视觉核对：标题、开场黑屏、行动力条 `165x14` 对齐、气泡 `107px` 高度与头像底边 `558`、恶作剧光标互斥、存单弹窗拦截与 `Esc` 返回标题实机交互。
