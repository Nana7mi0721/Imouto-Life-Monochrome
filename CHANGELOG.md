# 更新日志（Changelog）

本项目遵循语义化版本控制（Semantic Versioning）。

---

## [未发布]

### 修复（Fixed）
- **格子进度条残留复发**：并行计时器现覆盖浴室/日夜菜单/厕所/素股与
  deep-night 交互；退出时清理 `500..=503`、`510..=511`、`520..=521`
  三段 HUD 带，并补齐 `v155/v160/v170/v178` 闸门。修复左侧条只有
  `502/503`、没有 `500` 时完全不擦除的问题。
- 读档成功与返回标题时同步 `raid_scene_active`，避免跨会话旧沿造成
  误擦或漏擦。新增 4 条 `m22_raid_cleanup` 回归并通过整仓 Clippy。
- **开局随机称号乱码**：发行用 `DataBase.dat` 的「ランダム肩書」第 2 行
  第 10 格本身写成了 `³ç`（UTF-8 有效字符，解码器无法识别为乱码），
  而开局应显示「帅哥」。数据库加载时修复该已知损坏格，并同步修复旧存档
  `CData 0:12:0/1` 中已保存的同名乱码；新增 `m28_database_text_repair`
  与两条单元回归。

---

## [0.1.2] - 2026-11-22

### 发布（Release）
- **0.1.2 发行包**：Windows 标准/slim 的 setup 与便携 ZIP、Android 标准/slim
  的 arm64 APK，以及 iOS 标准/slim 的未签名 IPA；命名统一为
  `ImoutoLife-<version>-<platform>-<arch>[-setup][-slim]`，聚合校验和由
  Release 根目录 `SHA256SUMS.txt` 覆盖。三端包已完成本地构建和校验；
  截至 2026-11-23 尚未创建 tag 或上传 GitHub Release。
- **正式版本号**：Rust workspace、Windows 版本资源与 iOS 短版本均为
  `0.1.2`；Android `versionName=0.1.2`、`versionCode=3`，继续使用 0.1.0
  起的同一 release 签名证书，可覆盖升级且不丢存档。

### 新增（Added）
- **iOS 私有构建链路**：新增 iOS 导出预设、arm64 GDExtension 静态库构建、
  GitHub Actions `macos-latest` 无签名 IPA 产出、Windows 侧 `Data`/字体注入
  与 Sideloadly 安装文档。产物命名沿用
  `ImoutoLife-<version>-ios-arm64-unsigned[-slim].ipa`。
- **移动端存档导入/导出**：标题存档页新增横排“导入”“导出”按钮。导出为
  ZIP（`System.sav`、`SaveDataNN.sav`、`manifest.txt`）；导入同时接受 ZIP
  和单个 `.sav`，单个文件先选择系统/槽 1–4，再显示覆盖确认。导入前校验
  路径/格式、自动备份 `Save/`、原子写入并在完成后提示重启。
  - **iOS 系统文件面板**：通过 `wolf-gdext` 的 UIKit 桥接调用
    `UIDocumentPickerViewController`，导入/导出直接进入 iOS「文件」App；
    不再使用 Godot 的应用内文件对话框回退。
  - **iOS 应用信息**：显示名改为“妹！生活 ～单色～”，应用图标改用
    `icon_android.png` 同款素材。
- **Android 系统文件选择器**：导入/导出优先调用系统文档选择器，并增加
  `content://` URI 到 ZIP 构建/读取的桥接；iOS 4.7.2 无原生文件对话框时
  自动回退到应用内选择器，`user://` 仍通过 Files/iTunes 文件共享可见。

### 优化与修复（Fixed）
- **鼠标边沿隔离**：将全局 `mouse_consumed` 改为按位消费，右键取消不再
  连带清掉同帧未消费的左键决定；等待轮询只拿到当前接受的键位，避免并行
  事件互相吞点击或重复触发。
- **读档地图回退**：`220 SaveLoad` 找不到存档地图快照时回退安装
  `SampleMapA` 并写诊断，修复“画面已恢复但没有地图事件运行”的软锁。
- **iOS 标题退出项**：iOS 不允许应用自行退出，标题菜单现在只显示“开始游戏/
  读取存档”，隐藏第三张按钮与命中区，避免选择“退出游戏”后停在最后一帧；
  Windows/Android 仍保留三行菜单与原退出行为。
- **移动端存档安全**：ZIP 导入先限制中央目录条目数、单文件/总解压量和
  解压比，再逐个校验 `.sav`；媒体包 zstd 解码使用索引尺寸上限，避免异常
  压缩数据导致内存失控。
- **原子写入**：新增可覆盖目标的原子替换接口，Windows 使用
  `MoveFileExW(MOVEFILE_REPLACE_EXISTING)`，存档/设置写入不再先删旧文件。
- **iOS 运行稳定性**：文件选择器结果改为线程安全队列，由 Godot 主线程轮询；
  使用 64 MiB 解码纹理缓存上限，并优先加载注入的
  `NotoSansCJKsc-Bold.otf`。
- **打包修复**：NSIS Setup 生成后自动恢复 Medium 完整性，避免
  `Error writing temporary file`；模板构建脚本的 `--check` 不再因
  `set -e` 静默退出。
- 下载页、Windows/Android/iOS 预设和前端版本回退统一到 `0.1.2`；README
  明确官方发行包已包含发行 `Data/` 与干净 `System.sav`。

---

## [0.1.1] - 2026-11-20

### 发布（Release）
- **八个 0.1.1 发行包**：Windows 标准/slim 的 setup 与 zip，Android 标准/slim
  的 arm64 APK，以及 iOS 标准/slim 的 unsigned full IPA；统一放在
  `work/out/dist/release-assets/0.1.1/`；命名统一为
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
