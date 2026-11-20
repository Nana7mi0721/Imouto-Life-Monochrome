# 更新日志（Changelog）

本项目遵循语义化版本控制（Semantic Versioning）。

---

## [未发布]

### 新增（Added）
- **iOS 私有构建链路**：新增 iOS 导出预设、arm64 GDExtension 静态库构建、
  GitHub Actions `macos-latest` 无签名 IPA 产出、Windows 侧 `Data`/字体注入
  与 Sideloadly 安装文档。产物命名沿用
  `ImoutoLife-<version>-ios-arm64-unsigned[-full].ipa`。
- **移动端存档导入/导出**：标题存档页新增横排“导入”“导出”按钮。导出为
  ZIP（`System.sav`、`SaveDataNN.sav`、`manifest.txt`）；导入同时接受 ZIP
  和单个 `.sav`，单个文件先选择系统/槽 1–4，再显示覆盖确认。导入前校验
  路径/格式、自动备份 `Save/`、原子写入并在完成后提示重启。
- **Android 系统文件选择器**：导入/导出优先调用系统文档选择器，并增加
  `content://` URI 到 ZIP 构建/读取的桥接；iOS 4.7.2 无原生文件对话框时
  自动回退到应用内选择器，`user://` 仍通过 Files/iTunes 文件共享可见。

### 优化与修复（Fixed）
- iOS 使用 64 MiB 解码纹理缓存上限，降低 3 GB 设备浏览大图时的后台终止风险。
- iOS 优先使用注入的 `NotoSansCJKsc-Bold.otf`，缺失时回退 PingFang 等系统字体。
- 修正 iOS Actions 模板检查为 Godot 4.7.2 实际产出的 `ios.zip`，并修正文档中的
  `SHA256SUMS.txt` 校验文件名。

---

## [0.1.1] - 2026-11-20

### 发布（Release）
- **六个 0.1.1 发行包**：Windows 标准/slim 的 setup 与 zip，Android 标准/slim 的
  arm64 APK，统一放在 `work/out/dist/release-assets/0.1.1/`；命名统一为
  `ImoutoLife-<version>-<platform>-<arch>[-setup][-slim]`。
- **正式版本号**：Rust workspace 与 Windows 版本资源为 0.1.1，
  Android `versionName=0.1.1`、`versionCode=2`；沿用 0.1.0 的 release 签名
  证书（SHA-256 `ea94042a…4dd653`），支持覆盖升级且不丢存档。
- **真机验证**：OnePlus PJZ110（Android 15 / SDK 35 / arm64-v8a）上完成
  标准包与 slim 包的覆盖安装、冷启动、标题/剧情渲染、后台资源释放与日志检查；
  `media.pak` 留在 APK 内直读，不再复制约 100 MB 到应用数据目录。
  详见 `docs/release/PACKAGING.md` §8.8。

### 新增（Added）
- **公开发布审计收口**：修复 workspace license 继承、原子存档写入、并行输入热区穿透、
  Android 首次启动后台释放与旧资源清理、公开仓个人路径脱敏、Android 粗体测宽回退。
- **媒体包 v2**：`media.pak` 支持逐条 zstd；新增 WebP 重编码 slim 媒体树
  `tools/package/slim_media.py`，标准版与 slim 版共用同一读取路径。
- **Android 直读媒体包**：`media.pak` 以 `media.pak.blob.cfb` 未压缩留在 APK 内，
  通过 Godot `FileAccess` 随机读取，消除约 100 MB 的第二份应用数据占用。
- **发布档与命名**：新增 `[profile.release-dist]`（fat LTO、strip、panic=abort），
  Windows/Android 产物统一为 `ImoutoLife-<version>-<platform>-<arch>[-slim]`。
- **定制 Godot 模板**：新增 2D/GLES3 裁剪模板构建脚本；`lazy-function-tables`
  使 aggressive 模板可删除 3D/XR 类。Windows 模板 52.1 MB，Android arm64
  引擎库 56.3 MB（见 `docs/release/GODOT_TEMPLATE.md`）。

### 优化与修复（Fixed）
- 清理生产源码中的历史过程注释、内部审查编号与未入库本地路径。
- Android 资源清单新增 `media_pak_in_apk` / `media_pak_blob` 字段，并校验媒体包
  在 APK 内以 `STORED` 存放。

---

## [0.1.0] - 2026-11-19

### 新增（Added）
- **Godot 4 混合前端架构**：基于 Godot 4.7.2 + GDExtension (`wolf-gdext`)，实现 1024x576 像素级视口渲染与跨平台窗口管理。
- **Android 支持**：移植 ARM64 目标架构，完成触控交互与移动端适配。
- **全自动发布流水线**：
  - Windows 端便携版 ZIP 与 NSIS 安装包自动化打包脚本 (`tools/package-godot.sh`)。
  - Android 端 release APK 构建与签名流水线 (`tools/package-android.sh`)。
- **现代化增强特性**：
  - 高分辨率与无级视口缩放支持。
  - F2 统计与成就 Overlay、F3 实时运行时 Inspector。
  - F4 消息历史回顾（Message Log）。
  - 多语言 TSV 本地化引擎与 Mod 二进制数据/音频补丁覆盖支持。
  - 原生热键自定义重绑定 (`--hotkeys`)。

### 优化与修复（Fixed）
- **深度代码审查收敛**：完成 BUG-25 至 BUG-48 的全面修复与回归，包括名牌缓存对齐、操作动作门控、夜间点击热区、行动力数字对齐等。
- **输入与事件调度**：完善选项掩码过滤、等待位响应及鼠标点击边界判定。
- **存档一致性**：验证 `.sav` 格式双向无损往返，提供纯净出厂存档模板。

---

## [0.0.7] - M7 模块扩展
- 完成完整英语语言包（TSV 机制）。
- 落地 Database 记录级二进制补丁与两阶段补丁加载管线。
- 新增启动热键覆盖参数。

## [0.0.6] - M6 输入层对等
- 选项字与掩码过滤对齐。
- 原始键码映射闭环。

## [0.0.5] - M5 超越原版特性
- 视口无级缩放与全屏。
- 运行时调试与状态监视界面。
- 文本补丁与 Mod 清单加载。

## [0.0.4] - M4 对等打磨
- HUD 与状态面板相对坐标对齐。
- 设置界面排版与音频语义修正。
- 渲染 Quad 缓存与性能优化。

## [0.0.3] - M3 完整运行时
- 地图事件调度机与自动事件支持。
- 音频混音与音效生命周期管理。

## [0.0.2] - M2 日常切片
- 日常日程流转与基础交互闭环。

## [0.0.1] - M1 启动与数据
- 标题菜单、存档读取、文本编码与解码支持。

## [0.0.0] - M0 基础骨架
- 数据结构解析与工程多模块骨架搭建。
