# 《妹！生活 ～単色～》（`Imouto-Life-Monochrome`）全量静态代码审查报告

**审查目标**：`nana7mi0721/imouto-life-monochrome` 提交 `bedd7a19cc0a8a3f946979f1f7cca41c005a259a`（`bedd7a1`，`v0.1.1+`）  
**审查范围**：全仓 9 个 Rust crate（`wolf-format`、`wolf-save`、`wolf-vm`、`wolf-render`、`wolf-audio`、`wolf-game`、`wolf-cli`、`wolf-launcher`、`wolf-gdext`）、iOS Objective-C++ 桥接（`ios_file_picker.mm`）、Godot 4.7.2 前端脚本（`GameView.gd`、`WolfKeys.gd`、`WolfText.gd`）及发布/CI 配置（`Cargo.toml`、`export_presets.cfg`、`.github/workflows/*`），合计约 90,295 行核心源码。  
**审查方式**：纯静态代码审查（未构建、未修改任何仓库文件）。

---

## 一、总体评价与历史审查项收口确认

### 1. 整体架构质量
- **安全边界清晰**：核心运行时（`wolf-game`、`wolf-vm`、`wolf-format`、`wolf-save`）保持零 `unsafe`；全仓仅在宿主边界存在少量 `unsafe`（Windows `GetLocalTime` / `MessageBoxW` / `SendMessageW` / `CreateIconFromResourceEx` 与 iOS `ios_file_picker` FFI），且大部分边界检查严谨。
- **测试体系扎实**：覆盖 `m1` 至 `m27` 回归测试、`public_release_*` 发布门禁测试及 20+ 个 Godot 自动化测试脚本，CI 启用了 `cargo fmt --check` 与 `clippy -D warnings`。
- **上一轮（`a2a618d`）遗留项已全部闭环**：
  - 存档界面预选高亮实时跟随已通过 `sync_save_grid_highlight()`（`crates/wolf-game/src/game.rs:2273-2305`）修复，按鼠标悬停实时切换 `12051 + 20 * row` 的 `EFFECT_BLINK`；
  - 对话框正文内边距偏移已落地 `BALLOON_BODY_TEXT_X_OFFSET = 12.0` / `BALLOON_BODY_TEXT_Y_OFFSET = 6.0`（`game.rs:198-199, 3795-3802`）；
  - `wolf-vm/src/exec.rs:1468-1490` 修正了无 `421` 分支的 `102` 选项框误响应 `CANCEL` 的问题，并补充了 `split_sound_cell` 处理 CRLF 音效配置单元。

### 2. 风险总览

| 编号 | 级别 | 模块与位置 | 问题摘要 |
| :--- | :--- | :--- | :--- |
| **H1** | 高 | `crates/wolf-gdext/src/ios_file_picker.rs:12-60` | iOS 文件选择器使用 `thread_local!` 存储回调，若调用线程与 UIKit 主线程不同将静默丢回调并永久锁死后续导入/导出 |
| **H2** | 高 | `godot/scripts/GameView.gd:2569-2618` | ZIP 存档导入未调用 `validate_save_bytes` 校验包内 `.sav` 合法性，且先全量解压再校验总大小存在 ZIP 炸弹 OOM 风险 |
| **H3** | 高 | `crates/wolf-format/src/media_pack.rs:550-562` | `media.pak` v2 的 zstd 解压在检查 `raw_size` 之前全量解码至内存，损坏或恶意构造流可触发 OOM |
| **M1** | 中 | `crates/wolf-gdext/src/ios_file_picker.mm:107-112, 155-158, 220-223` | `presentViewController` 失败时 `g_activePicker` 永久非空锁死；`fileExistsAtPath` 早于 `startAccessingSecurityScopedResource` |
| **M2** | 中 | `crates/wolf-audio/src/engine.rs:186, 212, 256` | 3 处绕过 `self.lock()` 直接调用 `self.mixer.lock().unwrap()`，在 `release-dist`（`panic = "abort"`）下遇锁毒化会直接终止进程 |
| **M3** | 中 | `godot/scripts/GameView.gd:4334-4343` | `_replace_file_atomic` 在 Windows 目标存在时回退为「先删再改名」，非严格原子替换，崩溃窗口内可能丢失目标文件 |
| **M4** | 中 | `crates/wolf-gdext/src/lib.rs:1270-1285` | Windows 标题栏图标缓存键仅按 `width` 索引，且 `width * height * 2` 转 `u32` 未用 `try_from` |
| **L1** | 低 | `godot/scripts/GameView.gd`（4,577 行） | 单文件承担渲染、输入、音频、模态框、移动端适配、Android 异步释放、存档导入导出全部职责，维护与回归成本高 |
| **L2** | 低 | `godot/project.godot:22` & `export_presets.cfg` | `_mcp_game_helper` 注册为 Autoload，但导出预设排除了 `addons/godot_ai/*`，需确认无编辑器 CLI 导出时不会产生启动报错 |
| **L3** | 低 | `.github/workflows/ci.yml` & `ios-unsigned.yml` | CI 仅跑 `windows-latest`；`ios-unsigned.yml` 硬编码 `0.1.1` 产物路径，发版升级易漏改 |

---

## 二、高危问题详解（建议优先修复）

### H1：iOS 文件选择器 `thread_local!` 跨线程回调丢失与永久锁死
- **位置**：`crates/wolf-gdext/src/ios_file_picker.rs:12-60`、`crates/wolf-gdext/src/ios_file_picker.mm:129-225`
- **根因分析**：
  - `ios_file_picker.rs` 使用 `thread_local! { static PENDING_CALLBACK: RefCell<Option<Callable>> ... }` 保存 GDScript 传入的回调；
  - `ios_file_picker.mm` 通过 `dispatch_async(dispatch_get_main_queue(), ...)` 在 **UIKit 主线程** 弹出面板并最终回调 `wolf_gdext_ios_picker_result`；
  - 在 Godot 4 iOS 运行时中，GDScript 脚本线程未必与 UIKit 主线程为同一操作系统线程。一旦跨线程调用：
    1. `wolf_gdext_ios_picker_result` 在 UIKit 主线程访问 `PENDING_CALLBACK` 时读到的是 `None`，用户选择的导入/导出结果被**静默丢弃**；
    2. 原调用线程的 `PENDING_CALLBACK` 永远保持 `Some(callback)`，导致后续所有 `pick_import` / `export_file` 在第 17/28 行直接返回 `false`，整个会话内文件选择器**永久卡死**。
- **修复建议**：
  - 不要在跨线程 FFI 中使用 `thread_local!` 存放回调，也不要在非 Godot 线程直接操作 `Callable`；
  - 改为使用全局 `static PENDING_RESULT: Mutex<Option<(String, i32)>>`：Objective-C++ 回调仅将 `(path, status)` 写入 `Mutex`，由 Godot 主循环每帧轮询 `wolf.poll_ios_picker_result()` 消费结果并触发 GDScript 回调（彻底线程安全，且无 `Callable` 跨线程 `Send` 风险）。

---

### H2：ZIP 存档导入缺少 `.sav` 格式校验且存在未限流解压风险
- **位置**：`godot/scripts/GameView.gd:2569-2618`（`_validate_save_archive`）
- **根因分析**：
  1. **缺少内容校验**：单个 `.sav` 导入路径（`_inspect_save_import_source:2089-2091`）会调用 `wolf.validate_save_bytes(bytes)` 验证 WOLF 存档头与结构；但 ZIP 导入路径 `_validate_save_archive` 仅检查了文件名后缀与非空，**从未调用 `wolf.validate_save_bytes(bytes)`**。如果用户误选包含伪造或损坏 `.sav` 的 ZIP，导入会直接覆盖并删除原有 `Save/` 内的正常存档（虽有备份目录，但会导致重启后读档失败）。
  2. **先全量解压再判上限**：第 2600 行 `var bytes := reader.read_file(raw_name)` 在检查 `SAVE_ARCHIVE_MAX_BYTES` 之前就会把单个条目完整解压进内存，面对高压缩比畸形 ZIP（ZIP 炸弹）在移动设备上容易直接触发 OOM 闪退。
- **修复建议**：
  1. 在 `_validate_save_archive` 中对每个 `.sav` 条目补充 `wolf.validate_save_bytes(bytes)` 校验（至少在 `wolf != null && wolf.has_method("validate_save_bytes")` 时强校验）；
  2. 在读取条目之前（或结合 Rust 侧流式校验接口）先检查 ZIP 压缩文件头/未压缩大小与总条目数上限（如最多 128 个条目），拒绝超限条目后再解压。

---

### H3：`media_pack.rs` 的 zstd 解压未做输出上限保护
- **位置**：`crates/wolf-format/src/media_pack.rs:550-562`
- **根因分析**：
  - `read_entry()` 先调用 `rusty_zstd::decompress(&bytes)` 将整块数据无上限解压到 `Vec<u8>`，完成后才比对 `if bytes.len() != capacity`；
  - 若 `media.pak` 损坏或被篡改，一个几十 KB 的 zstd 帧可能解压出数 GB 数据，在校验长度前就耗尽内存（尤其是 3 GB 内存的 iOS 设备）。
  - 同理，`open_source()` 第 465 行 `vec![0u8; index_size]` 仅检查了 `index_offset + index_size == file_len`，没有为索引区设置合理上限（例如 `MAX_INDEX_BYTES = 32 * 1024 * 1024`）。
- **修复建议**：
  - 使用带上限的流式解压（`std::io::Read::take(entry.raw_size + 1)` 配合 zstd `StreamingDecoder`），一旦输出超过 `entry.raw_size` 立即中止并返回 `Corrupt` 错误；
  - 在 `Header::decode` / `open_source` 中为 `index_size` 和单条目 `raw_size` 增加合理上限校验。

---

## 三、中危问题详解（建议近期修复）

### M1：`ios_file_picker.mm` 呈现失败锁死与权限作用域顺序
- **位置**：`crates/wolf-gdext/src/ios_file_picker.mm:107-112, 155-158, 220-223`
- **问题**：
  1. `picker.presentationController.delegate = delegate` 写在 `presentViewController:animated:completion:` 的回调块里；若 `root` 正在执行其他转场导致呈现被 UIKit 忽略，`completion` 不会按预期回调且用户无法触发取消，`g_activePicker` 将永久非空；
  2. 第 108 行 `[[NSFileManager defaultManager] fileExistsAtPath:source.path isDirectory:&isDirectory]` 位于 `WolfCopyIntoAppTemp` 的 `startAccessingSecurityScopedResource` 之前；应将目录判定移入安全作用域之内（并优先使用 `NSURLIsDirectoryKey`）。
- **修复建议**：将 `picker.presentationController.delegate = delegate` 提前至 `presentViewController` 调用之前，并在呈现前检查 `root.presentedViewController == nil`；同时把目录判定放入 `startAccessingSecurityScopedResource` 作用域内。

### M2：`wolf-audio` 3 处裸 `.lock().unwrap()` 在 `panic = "abort"` 下存在崩溃风险
- **位置**：`crates/wolf-audio/src/engine.rs:186, 212, 256`
- **问题**：`engine.rs` 已经专门封装了可从锁毒化恢复的 `self.lock()`（第 385-389 行），但 `play_bgm`、`play_bgm_with_fade`、`play_bgs_with_fade` 开头 3 处误写了 `self.mixer.lock().unwrap()`。由于 `Cargo.toml:50` 的 `[profile.release-dist]` 开启了 `panic = "abort"`，任何异常导致的锁毒化都会直接让发行版闪退。
- **修复建议**：将这 3 处统一替换为 `self.lock()`。

### M3：`GameView.gd` 的 `_replace_file_atomic` 在 Windows 下并非严格原子
- **位置**：`godot/scripts/GameView.gd:4334-4343`
- **问题**：当 `DirAccess.rename_absolute(tmp_path, dst_path)` 失败且目标文件存在时（Windows 上覆写已有目标常见），代码先执行 `DirAccess.remove_absolute(dst_path)` 再执行 `rename_absolute`。若进程在删除与改名之间意外终止，原目标文件将丢失。
- **修复建议**：Rust 侧 `savegame.rs:58-88` 已有原子写入路径；GDScript 侧的存档导入覆盖或导出替换，可直接复用 `wolf-gdext` 暴露的 Rust 原子替换辅助接口（在 Windows 上使用 `MoveFileExW(MOVEFILE_REPLACE_EXISTING)` 或 `std::fs::rename` 语义），彻底消除删旧留空窗口。

### M4：Windows 标题栏图标缓存键与 `u32` 转换细节
- **位置**：`crates/wolf-gdext/src/lib.rs:1270-1285, 1325-1330`
- **问题**：`TITLEBAR_ICONS` 以 `image.get_width()` 作为唯一缓存键（若传入非正方形图标会碰撞）；`width as u32`、`height.checked_mul(2)? as u32`、`pixel_bytes as u32` 建议统一使用 `u32::try_from(...)` 保持与第 1365 行一致的防截断风格。

---

## 四、低危与架构可维护性建议

1. **拆分 `godot/scripts/GameView.gd`（4,577 行）**：
   - 该文件目前同时承担核心帧循环、Canvas 绘制、桌面热键、窗口图标、音频缓存、模态对话框、Android 资源异步释放、iOS/Android 存档导入导出与 ZIP 校验，已超过 156 KB。
   - **建议拆分**：至少拆出 `SaveTransfer.gd`（导入/导出/ZIP 校验/备份回滚）、`AndroidStaging.gd`（异步释放与清理）、`ModalLayer.gd`（弹窗与 Toast 绘制）、`AudioBridge.gd`（BGM/BGS/SE 缓存与淡入淡出），可显著降低改动耦合与回归风险。
2. **核查 `project.godot:22` 的 `_mcp_game_helper` Autoload**：
   - `godot/project.godot:22` 启用了 `_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"`，而 `godot/export_presets.cfg` 在所有平台排除了 `addons/godot_ai/*`。请核实无编辑器 CLI 打包（`godot --headless --export-release`）时是否会在导出产物启动日志中打印 `Can't open file ... game_helper.gd`，若有则建议在导出插件或打包脚本中剔除该开发期 Autoload。
3. **CI 与发版工作流加固**：
   - `.github/workflows/ci.yml` 目前仅在 `windows-latest` 运行，无法提前发现 Linux/macOS/Android/iOS 条件编译（`#[cfg(target_os = "...")]`）的语法或类型回归；建议至少补充 `ubuntu-latest` 的 `cargo check --workspace` 与 `ios_file_picker.rs` 的交叉类型检查。
   - `.github/workflows/ios-unsigned.yml:72-75` 硬编码了 `0.1.1` 路径，建议改为从 `Cargo.toml` 动态读取版本号，避免发版到 `0.1.2+` 时上传步骤报 `file not found`。

---

## 五、推荐修复优先级

1. **立即修复（发布前必改）**：**H1**（iOS 文件选择器去 `thread_local!` 改轮询）、**H2**（ZIP 内 `.sav` 补 `validate_save_bytes` 与解压前大小限制）、**H3**（`media_pack.rs` zstd 限流解压）。
2. **短期修复**：**M1**（`ios_file_picker.mm` 呈现防锁死与安全作用域顺序）、**M2**（`wolf-audio` 3 处 `.unwrap()` 改 `self.lock()`）、**M3**（Windows 原子替换防删旧窗口）。
3. **迭代重构**：**L1**（拆分 `GameView.gd`）、**L2**（清理导出包 `_mcp_game_helper` 启动噪音）、**L3**（补齐多平台 CI 与动态版本号）。
