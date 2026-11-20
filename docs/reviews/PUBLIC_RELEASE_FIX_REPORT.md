# 公开发布审计修复报告（`4f77b128`）

对应报告：[public_release_deep_audit_4f77b128.md](public_release_deep_audit_4f77b128.md)。
代码、脚本与本地验证完成后，已继续生成 0.1.1 的六个 Windows / Android
发行包，并完成 Android 真机启动验证；发布记录见
`docs/release/PACKAGING.md` §8.8。

## 审计缺陷

| 编号 | 状态 | 落点 |
| :--- | :--- | :--- |
| PUB-01 构建阻断 | 已修复 | 9 个 crate 移除失效的 `license.workspace = true`；`cargo metadata` / `cargo check --workspace` 通过。 |
| PUB-02 存档原子写 | 已修复 | `savegame.rs` 先编码到同目录 `.<name>.tmp`，`sync_all()` 后 `rename`；失败清理临时文件。`public_release_save_atomic` 通过。 |
| PUB-03 并发输入 | 已修复 | `mouse_key_bits()` 入口检查 consumed；恶作剧态跳过通用动作热区；`STORY_COMMON_EVENTS` 纳入 `219/220/283/284/290`。`m16_parallel_input` 5/5。 |
| PUB-04 Android 启动 | 已修复 | 资源释放移入后台 `Thread`，主线程显示不可取消的进度面板；升级仅在版本变化时清理旧文件，并严格保护 `Save/` 与 `.sav`。`android_staging_async.gd` 0 failures。 |
| PUB-05 发布隐私 | 已修复 | `AGENTS.md`、docs、`tools/env.*` 与审计脚本移除个人邮箱、用户名和本机绝对路径；Godot 通过 `GODOT_BIN` / `PATH` 探测。 |
| PUB-06 Android 测宽 | 已修复 | 字体候选优先 `NotoSansCJK-Bold.ttc`，再 Regular 与厂商回退。 |

## 包体优化

1. **媒体重编码 + 帧级 zstd**
   - `media.pak` 升级为 v2：逐条记录 raw/stored size、CRC-32、codec；能缩小才 zstd，读取端仍兼容 v1。
   - 标准媒体：733 文件 / 113,002,637 B → pack 100,773,072 B。
   - slim 媒体树：73,751,358 B（较标准源 −34.7%，671 个文件重编码）；
     slim pack 72,714,784 B。
   - 新 `tools/package/slim_media.py`：PNG → 无损 WebP，JPEG → Q90 WebP，
     逻辑路径不变，不修改 `work/Data`。

2. **Android 消除重复 `media.pak`**
   - APK 内媒体包改为 `android_data/media.pak.blob.cfb`；`.cfb` 命中 Godot
     APK 写入器的“不压缩”扩展名，保证 ZIP `STORED`，可随机 seek。
   - `wolf-format::MediaPack` 新增 `PackSource` / `open_source()`；
     `wolf-gdext::open_with_media_file()` 用 Godot `FileAccess` 直接读取包内媒体。
   - Android 清单新增 `media_pak_in_apk` / `media_pak_blob`；首次启动不再复制
     约 100 MB 媒体包到 `user://data`。
   - `android_data.py verify-apk` 会拒绝被压缩的媒体包。

3. **Rust 发布档**
   - 新增 `[profile.release-dist]`：fat LTO、`codegen-units=1`、
     `strip="symbols"`、`panic="abort"`。
   - `tools/build-godot.sh --dist` 与 `tools/build-android.sh --dist` 使用该档；
     打包脚本与 `media-pack` 同步切到 `target/release-dist/`。
   - 启用 `lazy-function-tables` 后本机 `wolf_gdext.dll` 为 2,401,280 B；
     Android arm64 `.so` 为 2,231,160 B。

4. **定制 Godot 模板**
   - 新 `tools/build-godot-template.sh` 固定 Godot 4.7.2 源码与 SCons 构建，
     提供 safe 与 aggressive 两档。
   - aggressive 档删除 3D/XR/Navigation/Physics3D 类，前提是
     `wolf-gdext` 启用 `lazy-function-tables`（已启用）；GDExtension 方法
     改为首次调用时解析，运行时不使用这些类。
   - aggressive Windows 模板 52,120,576 B（官方约 105 MB），真实导出 +
     无头 180 帧通过。
   - aggressive Android arm64 模板 APK 21,775,866 B；其中
     `libgodot_android.so` 56,326,888 B，官方 arm64 为 71,114,944 B，
     实际引擎本体约 −14.8 MB。
   - `deprecated=no` 仍禁止：它删除 `get_godot_version` 等接口函数，
     lazy 方法表也无法补救。
   - 打包脚本新增 `--template` 与 `GODOT_TEMPLATE_WINDOWS` /
     `GODOT_TEMPLATE_ANDROID`，导出前临时改写 preset，退出时恢复。

## 验证

- `cargo fmt --all -- --check`：通过。
- `cargo check -q --workspace`：通过。
- `cargo test -q -p wolf-format`：35 passed。
- `cargo test -q -p wolf-gdext -j 1`：3 passed。
- `public_release_*` / `m16_parallel_input`：16 passed。
- `WOLF_DATA_ROOT="$PWD/work/Data" ./target/debug/wolf-cli.exe verify`：
  PASS 64 / 1 SKIP。
- `cargo test -q --workspace --exclude wolf-gdext --no-fail-fast`：
  仅剩历史数据夹具缺失与既有差异（`SaveData01/02` 已在发布清理时删除，
  `m3_save_load` / `m3_title_mouse` / `m3_week_loop` 因此报“无存档”；
  另有既有 `m18 hidden_and_transparent...` 与 `late_night_bedtime...`）。
- Godot `--check-only`、`smoke-godot.sh`、`android_staging_async.gd` 通过。
- 定制 Windows aggressive 模板真实导出后无头启动 `work/Data` 成功，
  GDExtension 正常加载；Android 模板在后续 0.1.1 阶段已用 OnePlus PJZ110
  完成标准/slim 两个正式 APK 的覆盖安装与真机冷启动验证。

## 0.1.1 发布与真机验证

- 六个正式产物已汇总到 `work/out/dist/release-assets/0.1.1/`：
  Windows 标准/slim 的 setup 与 zip、Android 标准/slim 的 arm64 APK，
  以及覆盖六个文件的聚合 `SHA256SUMS.txt`。
- Android 版本为 `versionName=0.1.1`、`versionCode=2`，沿用 0.1.0 的
  release 证书（SHA-256 `ea94042a…4dd653`），覆盖安装未卸载、未清理数据。
- 真机日志确认 `Godot Engine v4.7.2.stable.custom_build`、
  `wolf-gdext ... [build v0.1.1]`、后台 staging 完成、首帧音效/画面正常；
  标准包与 slim 包均通过标题画面/剧情渲染检查，无接口函数缺失、类加载失败、
  panic、媒体包读取或 CRC 错误。
- Android 资源释放日志确认媒体包不再复制到 `user://data`；标准包稳定启动为
  `copied=0 removed=0 skipped=true`，切换媒体清单时仅复制约 3.5 MB 明文负载，
  `media.pak` 始终从 APK 内 `STORED` blob 直读。

## 未做

- 六个 0.1.1 发行产物已生成；本轮仍未提交 commit。
- 审计 §5.2 的 FFI 扁平数组、图集增量上传、大图/音频异步解码仍属后续性能项。
- 大型文件模块拆分（`game.rs` / `GameView.gd` / `picture.rs`）未在本轮执行。
