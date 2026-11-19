# 发布打包（M4-PACKAGE）

把 Rust 重写版构建成一个可分发的目录 `work/out/dist/<version>/`，包含可执行文件、
用户 README、Windows 启动器与校验和。**不打包、不提交游戏数据**（`work/Data`、`.exe`
都在 `.gitignore` 中）。

## 1. 一键打包

msys / git-bash（推荐）：

```bash
cd "/e/Study/github program/Imouto Life"
source tools/env.sh >/dev/null 2>&1
bash tools/package.sh                 # 构建 release 并打包到 work/out/dist/<version>/
bash tools/package.sh --skip-build     # 复用已有 target/release/wolf-cli.exe
bash tools/package.sh --verify --data-root work/Data   # 打包后跑一次 verify 冒烟
```

Windows PowerShell（等价实现）：

```powershell
powershell -ExecutionPolicy Bypass -File tools/package.ps1
powershell -ExecutionPolicy Bypass -File tools/package.ps1 -Verify -DataRoot work/Data
```

两者行为一致：`cargo build --release -p wolf-cli` → 拷 `wolf-cli.exe` → 由
`tools/package/README.txt`、`tools/package/launcher.cmd` 模板渲染出 `README.txt`、
`Play-ImoutoLife.cmd`（替换 `{{VERSION}}` / `{{BUILT}}`）→ 生成 `checksums.txt`。

版本号默认取根 `Cargo.toml` 的 `[workspace.package] version`，可用 `--version` / `-Version` 覆盖。
输出根默认 `work/out/dist`，可用 `--out-root` / `-OutRoot` 覆盖。

## 2. 产物结构

```
work/out/dist/<version>/
  wolf-cli.exe           # release 构建（约 3-8 MB），单文件运行
  README.txt             # 面向用户的说明（数据准备、启动、诊断命令、校验）
  Play-ImoutoLife.cmd    # 双击启动器，自动定位数据根
  checksums.txt          # 各文件 SHA-256，格式 "<hash>  <name>"（sha256sum -c 可用）
```

这些文件全部位于 `work/` 下，天然被 git 忽略；`tools/**` 与 `docs/release/PACKAGING.md` 才是
需要检查/提交的源文件。

## 3. 数据根解析（启动器与 wolf-cli 的一致性）

`wolf-cli` 的数据根解析顺序（`default_root()`）：`--root/-r` 参数 > 环境变量
`WOLF_DATA_ROOT` > 默认 `work/Data`。数据根必须是**解包后的目录**，含 `BasicData/` 与
`MapData/`（BGM/SE/图片/字体都在其下）。运行时**不能**直接挂 `Data.wolf` 原始包；
`--wolf` 仅用于 `verify` 逐字节比对。

`Play-ImoutoLife.cmd` 在调用 `wolf-cli.exe play` 前按同样思路定位数据根：

1. 第一个命令行参数（可带引号的路径）；
2. 环境变量 `WOLF_DATA_ROOT`；
3. 启动器同目录下的 `Data\`（存在 `Data\BasicData` 时）。

找到后执行 `wolf-cli.exe play --root "<数据根>" <其余参数...>`。窗口 1024x576；
方向键移动，Enter/Z 或鼠标确定，F12 重启；追加 `--audio` 播放 BGM/SE（无音频设备时
自动静音）。找不到数据根时给出提示并以退出码 2 结束。

## 4. 字体

`font_paths()` 的查找顺序：`Game.dat` 的 `font_main`（"Microsoft Yahei UI Bold"）→
内置字体常量 `BUNDLED_FONT_NAMES`（在 `<root>/Fonts`、`<root>`、安装目录搜索）→
其它 `*.ttf/otf/ttc`。Windows 通常自带 `msyhbd.ttc`；缺失时回退到数据目录/安装目录内
附带字体。发布包不额外内嵌字体。

Android 不读取上述 Windows 或原版日文字体，而是使用设备系统的
`Noto Sans CJK SC` / `Source Han Sans SC` / `sans-serif`，并保持
Bold/Regular 两套字重。`tools/package-android.sh` 的 APK 数据暂存会排除
原版 `◆GenJyuuGothicX-P-Bold.ttf` 与 `07やさしさゴシックボールド.ttf`；
`android_data.py verify-apk` 也会拒绝 `.ttf`、`.ttf.blob` 或旧 manifest
中残留的这两个文件。公共 release manifest 与 Windows 发行包不受影响。

## 5. 验收（本任务执行记录）

```bash
source tools/env.sh >/dev/null 2>&1
bash tools/package.sh            # 期望：cargo build --release exit 0，打印 dist 列表
ls -l work/out/dist/<version>/   # 期望：wolf-cli.exe README.txt Play-ImoutoLife.cmd checksums.txt
```

打包脚本只新增文件、不触碰 `src/` 与测试；如需回归验证，另跑
`cargo test -q --workspace`、`WOLF_DATA_ROOT=work/Data cargo test -q --workspace` 与
`wolf-cli verify`。

## 6. 常见坑

- `*.exe` 与 `work/` 都被 git 忽略，dist 产物不会误提交；提交前 `git status` 确认只含
  `tools/package*`、`godot/export_presets.cfg` 与 `docs/release/PACKAGING.md`。
- 用 PowerShell 5.1 读 UTF-8 模板时务必显式按 UTF-8 读取（脚本已用
  `[System.IO.File]::ReadAllText(..., UTF8)`），否则中文 README 会乱码。
- 启动器 `.cmd` 以无 BOM 写回（BOM 会破坏 `@echo off` 首行）；模板本身为 CRLF。
- 数据根必须是解包目录，不是 `Data.wolf`；`play` 不接受 `.wolf`。
- 不改 `game.rs`/`tilemap.rs` 等范围外文件；本任务是纯打包交付物。

## 7. 可双击游玩的完整发布包（Playable Package）

前面的 `tools/package.sh` / `package.ps1` 是诊断包：只有一个 CLI 和 .cmd 启动器，
不带游戏数据，适合开发验证。面向“像正常游戏一样双击 exe 就能玩”的交付使用：

```bash
cd "/e/Study/github program/Imouto Life"
bash tools/package-playable.sh \
  --out-dir "/d/program/Imouto Life" \
  --zip-dir work/out/dist
```

产物结构：

```text
D:\program\Imouto Life\
  Imouto Life.exe        # GUI 启动器，双击即启动，无控制台黑窗
  runtime\wolf-cli.exe   # Rust 引擎（release 构建）
  Data\                  # 完整解包游戏数据（约 178 MB，不含本地编号存档）
  README.txt             # 中文游玩说明
  checksums.txt          # 启动器/引擎/README 的 SHA-256
```

启动器是 `crates/wolf-launcher`（std-only，无外部依赖）：定位同目录 `Data\BasicData`
与 `runtime\wolf-cli.exe`，以 `play --root <Data> --audio` 启动引擎，并用 Windows
`CREATE_NO_WINDOW` 隐藏控制台；引擎 stdout/stderr 写入同目录 `game-log.txt`，启动失败
弹 MessageBox 并写 `launcher-error.log`。额外参数会原样转发，例如
`Imouto Life.exe --load-save "<你的存档路径>"`。

脚本选项：`--skip-build`、`--no-zip`、`--force`（替换已有输出目录）、`--data-root`。
`--force` 只会删除 `work/out/` 或 `D:\program/` 下的目录，避免误删。

递归复制 Data 时会剔除整个 `Save/` 子树，然后在包内重建 `Data/Save/`，只放入一个
干净的 `System.sav`。来源优先为 `work/out/retail_saves/System.sav`；若不存在，再使用
`<data-root>/Save/System.sav` 并打印来源、SHA-256 与 fallback 警告。两者都不存在时
脚本失败。因此发布包
**不含任何本地编号存档（SaveData*.sav），只含干净的 System.sav 模板**。

可用 `--system-save FILE` 显式指定模板，或用 `--dry-run` 只检查数据源并打印过滤计划，
不会构建、复制约 178 MB 数据或创建输出目录；它不是完整发布预检。

## 8. Godot 正式发布包

Godot 前端使用独立的 Windows Desktop release 导出路径，不把 `wolf-cli` 诊断包当作
Godot 发行版：

```bash
cd "/e/Study/github program/Imouto Life"
bash tools/package-godot.sh

# 数据计划/过滤逻辑检查：不构建、不导出、不复制 Data
bash tools/package-godot.sh --dry-run
```

默认产物：

```text
work/out/dist/godot/<version>/
  Imouto Life.exe        # Godot release 导出（PCK 内嵌）
  bin\wolf_gdext.dll     # release GDExtension；GDExtension 清单按 res://bin/ 解析
  Data\                  # 15 个明文清单文件 + Save\System.sav + media.pak
  README.txt
  按键功能指引.txt        # F4/F11/F8/F5 等显示快捷键与游戏操作
  checksums.txt          # 包内所有文件的 SHA-256
work/out/dist/godot/Imouto Life setup.zip
work/out/dist/godot/Imouto Life setup.zip.sha256
work/out/dist/godot/Imouto Life setup.exe
work/out/dist/godot/Imouto Life setup.exe.sha256
```

`Imouto Life setup.zip` 的顶层目录固定为
`妹！生活 ～单色～ Godot/`；解压后直接进入该文件夹运行。

### 8.1 发行 Data 结构与 media.pak

`tools/package/release-data.manifest` 仍是发行包的唯一 Data 来源。当前清单为
**748 个文件 / 127,928,510 B**。打包时固定把以下 7 个媒体前缀从明文 staging
中排除，交给 `media-pack` 写入 `Data/media.pak`：

```text
Picture/  cg/  BGM/  SE/  CharaChip/  SystemFile/  BalloonBase_CafeLatte/
```

这 7 个前缀当前共 **733 个文件 / 113,002,637 B**，是媒体包的 payload。
其余 **15 个文件 / 14,925,873 B** 保持明文：9 个 `BasicData/` 文件、
5 个已注册 `MapData/` 地图和 `◆GenJyuuGothicX-P-Bold.ttf`。最终 Data 结构为：

```text
Data\
  BasicData\                  # 9 个数据库/工程/瓦片集文件（明文）
  MapData\                    # 5 张已注册地图（明文）
  Save\System.sav             # 唯一允许的干净存档模板（明文，155,615 B）
  ◆GenJyuuGothicX-P-Bold.ttf   # 字体（明文）
  media.pak                   # Picture/cg/BGM/SE/CharaChip/SystemFile/
                              # BalloonBase_CafeLatte 的只读媒体包
```

即 **17 个文件** = 15 个明文清单文件 + `Save/System.sav` + `media.pak`。
`media.pak` 的 payload 是 113,002,637 B；容器本身还有头部/索引等开销，
实际大小以构建输出和 `checksums.txt` 为准，不在文档里写死。

相对完整 `work/Data` 当前排除 **619 个文件 / 55,910,216 B**（含未列入
manifest 的媒体和模板资源），其中包含：

- `MapChip/` 整目录：当前 Godot 发行路径不调用 `tile_quads()`，只画
  scenery/picture；因此 102 个瓦片图都不会进入发行包。原始 `work/Data`
  仍保留，供 `wolf-cli capture --map`、测试和未来瓦片功能使用。
- `FIcon/`、`BattleEffect/`、`Fog_BackGround/`、`SystemGraphic/`：
  当前无运行时消费路径；`BattleEffect` 仅有未注册 `Map002.mps` 和战斗模板引用。
- 3 张未注册地图（`Dungeon.mps`、`Map002.mps`、`SampleMapB.mps`）；
  只保留注册的 5 张地图。
- 未被脚本/数据库/引擎路径引用的 `Picture`、`cg`、BGM/SE、`CharaChip`
  和 `BasicData` 图标/辅助文件。

`Data/Save/` 由脚本单独注入，只允许一个 `System.sav`；所有本地
`SaveData*.sav` 都不会复制。staging 使用 `--exclude-prefix` 排除媒体前缀，
并以 `--defer-verify` 先复制明文；`media-pack` 生成 `media.pak` 后再调用
`release_data.py verify --exclude-prefix ... --extra media.pak`。校验器会拒绝
绝对路径、`..`、反斜杠、盘符、重复路径和符号链接逃逸，最终文件集合必须精确等于
“过滤后的清单 + `Save/System.sav` + `media.pak`”；任何散落的媒体文件都会作为
unexpected 失败，7 个媒体前缀目录还会被脚本显式检查必须不存在。

### 8.2 Godot 导出预设

`godot/export_presets.cfg` 的 `Windows Desktop` 预设：

- `export_filter="all_resources"`；
- include 过滤器包含 `bin/*.gdextension`；
- exclude 过滤器排除 `addons/godot_ai/*`、`tests/*`、`bin/~*`、
  `bin/*.dll` 与只用于写入 exe 图标的 `icon_windows.png`；
- `application/icon="res://icon_windows.png"`，源图从
  `work/Data/icon_windows.png` 复制到 `godot/icon_windows.png`；
  Godot 4.7.2 会把 2048×2048 PNG 自动转换成多尺寸 Windows 图标，无需预生成 ICO；
- 运行时窗口图标使用 `application/config/windows_native_icon="res://window_icon.ico"`。
  该 ICO 由 `tools/package/make_windows_icon.py` 重建，含
  16/20/24/32/40/48/64/128/256 九帧，**每一帧**都来自
  `work/Data/icon_windows.png`。它是程序/任务栏/Alt-Tab 图标，
  不得混入 inusuku 头像；NSIS 的 `tools/package/icon_windows.ico`
  使用同一套九帧。
  正常 Windows GUI 启动后，`GameView.gd` 通过 GDExtension 的
  `titlebar_icon_size()`（`GetDpiForWindow` +
  `GetSystemMetricsForDpi(SM_CXSMICON)`）取得实际物理尺寸，优先加载
  `res://icon_titlebar_{16,20,24,32,40,48}.png` 中对应的小图，再以
  `WM_SETICON ICON_SMALL` 设置标题栏；缺失对应尺寸时才回落到
  `res://icon_titlebar.png`（256×256，inusuku 头像裁切）的 Lanczos
  缩放。inusuku 只用于这一层标题栏覆盖；`ICON_BIG` 仍保持
  `icon_windows` ICO 的大帧；F4/F11 切换窗口模式后会重新应用。
  exe 文件图标仍由上面的 `application/icon` 单独控制；
- Windows 资源字段从 `export_presets.cfg` 读取并同步给 NSIS 安装器：
  `file_version` / `product_version` 为 Cargo 版本补足四段（当前 `0.1.0.0`），
  `product_name` 与 `file_description` 为 `妹！生活 ～单色～ Godot`，
  公司名和版权使用当前预设中的 `Inusuku` / `Copyright (c) 2026 Inusuku`；
- Godot 4.7.2 仍会把 Windows 版本资源写成英语（美国，`0x0409`），且
  “属性 → 详细信息 → 语言”显示的是 PE 资源目录的语言 ID，改字符串字段无效。
  导出后由 `tools/package/windows_version_language.py` 把 `RT_VERSION`
  资源语言改为简体中文（`0x0804`），同步语言键和 `Translation` 项，并重算
  PE checksum；不改变文件大小或内嵌 PCK；
- 导出走 `--export-release`，PCK 内不包含开发插件、测试脚本或图标源。

`_mcp_game_helper` 仍保留在 `project.godot` 作为开发期 autoload；启用中的
`mcp_export_plugin.gd` 会在导出期间从导出的项目设置快照剥离该 autoload，结束后恢复
编辑器内存状态。因此不需要条件化或删除 `project.godot` 的 autoload，发布包通过
预设排除插件文件。

导出器实际会把 Windows GDExtension DLL 放在 exe 根目录，但 PCK 中的清单仍按
`res://bin/wolf_gdext.dll` 查找；脚本会把 DLL 重排到 `bin\wolf_gdext.dll`，
并在打包后用 SHA-256 确认它与 `godot/bin/wolf_gdext.dll` 完全一致。DLL 不再
重复写入 PCK，exe 因此比全量嵌入版本小约 6.5 MB。

### 8.3 自动校验

脚本在构建前检查本机 Godot 导出模板：

```text
%APPDATA%\Godot\export_templates\<godot-version>\
  windows_release_x86_64.exe
  windows_debug_x86_64.exe
```

`GODOT_EXPORT_TEMPLATES` 可覆盖模板根目录，`GODOT_BIN` 或 `--godot` 可覆盖 Godot
可执行文件。模板缺失时脚本给出目标目录和安装方式并失败；**不会自动下载约 1.2 GB
的模板包**。Godot 4.7.2 模板本机已安装，可直接导出。

导出后脚本会：

1. 解析内嵌 PCK，要求只有运行文件，且不含 `addons/`、`tests/`、`icon_windows.png`
   或重复的 DLL；新增 `window_icon.ico`、`icon_titlebar.png` 后当前实际为 16 个文件；
2. 把 exe 的版本资源语言改为简体中文，并复核 PE checksum 与 PCK 完整；
3. 检查 `bin\wolf_gdext.dll` 与构建 DLL 的 SHA-256 相同；
4. 以 `--exclude-prefix` 和 `--defer-verify` staging 15 个明文清单文件 +
   `Data/Save/System.sav`，并复核 `Data/Save/` 只能有 `System.sav`；
5. 构建并调用 `target/release/media-pack.exe`，从源 `--data-root` 和同一个
   manifest 生成 `Data/media.pak`；
6. 调用 `release_data.py verify --exclude-prefix ... --extra media.pak`，要求最终
   文件集合精确为 17 个文件，并额外检查 7 个媒体前缀目录/文件都不存在；
7. 生成包内 `checksums.txt`，可用 `sha256sum -c` 复核；
   `tools/package/KEYBOARD_GUIDE.txt` 会以 CRLF 写为包内
   `按键功能指引.txt`，并同样进入校验和；
8. 校验便携 zip 可读、顶层目录正确，并生成 zip 外部 `.sha256`；
9. 如生成安装版，调用 NSIS 编译 `Imouto Life setup.exe` 并生成外部 `.sha256`。

媒体打包器由 `tools/package-godot.sh` 构建：
`cargo build -q --release -p wolf-format --bin media-pack`，产物固定为
`target/release/media-pack.exe`。`--skip-build` 只表示复用现有
`godot/bin/wolf_gdext.dll`；如果 packer 尚不存在，脚本仍会单独构建它。
调用接口为
`media-pack --root DIR --manifest FILE --include-prefix PREFIX ... --output FILE`，
其中 `--include-prefix` 固定重复 7 次，`--output` 为 `Data/media.pak`。

### 8.4 NSIS 安装版

安装脚本模板是 `tools/package/ImoutoLife.nsi.in`，由
`tools/package/render_nsis.py` 注入实际路径、版本、发布者、版权和图标；
安装包图标来自 `tools/package/icon_windows.ico`（16/24/32/48/64/128/256）。

- 语言固定为简体中文（MUI `SimpChinese`，不显示语言选择页），使用标准
  NSIS 目录页，用户可以在向导中自由选择安装位置；
- 默认安装目录为 `$LOCALAPPDATA\Programs\妹！生活 ～单色～ Godot`；如果用户
  选择的是父目录，离开目录页时会自动追加「妹！生活 ～单色～ Godot」游戏
  文件夹，避免游戏文件直接散落在所选根目录；
- 创建开始菜单快捷方式（默认勾选），桌面快捷方式为可选组件；
- 覆盖安装时先备份再恢复 `Data\Save\System.sav`，编号存档不参与覆盖；
  卸载时先把整个 `Data\Save` 改名为 `.save-keep`，删除其余 `Data` 内容后
  再恢复；若改名失败则保留整个 `Data`，避免误删玩家存档；
- 安装包使用和 exe 相同的高清图标，并写入版本、公司、产品名和版权。
- 安装信息写入 HKCU 卸载注册表项，卸载器同时删除开始菜单和可选桌面快捷方式。
- 卸载器删除 `README.txt`、`按键功能指引.txt` 与 `checksums.txt`；玩家存档
  仍按上面的 `.save-keep` 流程保留。

生成安装版需要 NSIS 3.x 的 `makensis.exe`。脚本依次查找
`MAKENSIS_BIN`、`--makensis PATH`、项目内
`work/out/tools/nsis-3.11/nsis-3.11/makensis.exe` 以及常见系统安装路径；
缺失时真实打包会停止，`--no-setup` 可只生成便携包。编译时脚本把
`TEMP`/`TMP` 指向 `work/out/nsis/temp`，避免本机临时目录权限导致
`Internal compiler error #12345`。
本机 `work/out` 还带有 Low Mandatory Level 完整性标签和禁止删除子项的 ACL。
从该目录双击 `Setup.exe` 时，安装器会继承低完整性级别，无法写普通
`%TEMP%`，表现为 `NSIS Error: Error writing temporary file` 或错误码 2。
实机测试或交付前必须把 Setup/ZIP 复制到普通用户目录（例如
`D:\REISEN\Downloads\...`）再运行。

`--dry-run` 只报告模板是否存在，并打印媒体包前缀、pack payload、明文 staging
文件数/字节与最终 Data 文件数；它不构建、不导出、不打包、不复制数据。packer
尚未构建时 dry-run 会明确提示，并跳过实际打包。真实 release 导出仍会因模板
缺失而失败。

当前输出预期（体积会随构建变化，不在文档中写死最终 Setup 大小或哈希）：

- `Data/` 17 个文件：15 个明文清单文件 + `Save/System.sav` + `media.pak`；
- `media.pak` 的 payload 为 733 个文件 / 113,002,637 B，容器大小另含头部/索引；
- `Imouto Life.exe`、`bin\wolf_gdext.dll`、便携 ZIP 与 NSIS Setup 的体积
  以实际构建输出为准；
- 包内 `checksums.txt` 和各外部 `.sha256` 是最终校验依据。

精简 Data 验证：`smoke.gd` 输出 `pictures=4 sprites=4`；
`save_roundtrip.gd` 新游戏自动走到卧室并保存/重载均为 38 张图片，
`System.sav` 哈希前后不变。

其它选项：`--no-zip`、`--no-setup`、`--makensis PATH`、`--skip-build`、`--force`、
`--out-dir`、`--zip-dir`、`--manifest`、`--system-save`、`--preset`。

### 8.5 media.pak 的格式边界与图标格式

- `Data/media.pak` 是由 `media-pack` 从同一份 release manifest 中筛选 7 个媒体
  前缀生成的只读单文件包。包内只包含媒体条目；`BasicData`、`MapData`、`Save`
  和字体仍以明文散文件发布，Godot PCK 仍只包含脚本/场景/运行资源。
- 该包使用固定密钥 XOR 混淆。**它是混淆，不是强加密，也不提供 DRM**：密钥在
  客户端中，能提高直接浏览/复制素材的门槛，但无法抵抗有意的逆向或提取。
- Mod overlay 仍可用：玩家/Mod 可以继续按原 `Data/` 目录结构放置同名散文件覆盖；
  `media.pak` 是只读后备，不应手工修改，需要更新内容时用 packer 重新生成。
- 打开 Godot 的 `encrypt_pck` 不能替代媒体包：它只覆盖 PCK 内的脚本/场景等资源，
  且官方导出模板不支持；它不能保护外部 `Data/media.pak`。
- Windows 的可执行文件/窗口图标最终使用 ICO（内部为多尺寸位图），不接受
  SVG。`work/Data/inusuku.png` 本身是 400×400 位图，转成 SVG 不会恢复细节；
  只有拿到真正的矢量源文件时，才值得从矢量逐档渲染。当前
  `tools/package/make_windows_icon.py` 会把 `icon_windows.png` 采样成
  程序/安装器 ICO 的全部九帧；inusuku 的
  `icon_titlebar_{16,20,24,32,40,48}.png` 仅用于运行时标题栏覆盖。
  两组资源不得交叉：安装器/程序图标必须是 `icon_windows` 系列。
  `GameView.gd` 再按实际 DPI 选择标题栏尺寸，避免把 256×256 图交给
  Windows 标题栏现场缩小。

### 8.6 0.1.0 最终发布与清理记录（2026-11-19）

本轮 Windows / Android 发布包已统一放到普通用户目录，避免从 `work/out`
继承 Low Mandatory Level / 受限 ACL：

```text
D:\REISEN\Downloads\Imouto Life 0.1.0\
  README.txt
  Windows\
    Imouto Life setup.exe
    Imouto Life setup.exe.sha256
    Imouto Life setup.zip
    Imouto Life setup.zip.sha256
    README.txt
    按键功能指引.txt
    SHA256SUMS.txt
  Android\
    ImoutoLife-0.1.0-arm64.apk
    ImoutoLife-0.1.0-arm64.apk.idsig
    ImoutoLife-0.1.0-arm64.apk.sha256
    README_ANDROID.txt
    checksums.txt
```

实际交付物与校验值：

| 产物 | 字节数 | SHA-256 |
|---|---:|---|
| `Imouto Life setup.exe` | 147,841,600 | `d3998c4a87858736f140f0ddec576d77221dbded2d59cbca42513a72119cd1a7` |
| `Imouto Life setup.zip` | 159,435,986 | `d5cd573d3965e0a1a663ecb1d8b903913fca39b16454f15194da0fe51bc924a2` |
| `ImoutoLife-0.1.0-arm64.apk` | 144,902,270 | `2c3157ebae1c7f97ef7cb907e1f650bcf50b6a947f091069c825cffd951baf7f` |

Windows 便携 ZIP 顶层固定为 `妹！生活 ～单色～ Godot/`，`Data/Save/` 只含
干净 `System.sav`。Windows `SHA256SUMS.txt`、Android `checksums.txt` 与 APK
签名校验均已通过。

Android 0.1.0 使用 release 签名，证书 DN 为
`CN=Imouto Life, OU=Release, O=Inusuku, L=Shanghai, ST=Shanghai, C=CN`，
证书 SHA-256 为
`ea94042afd8ced39ddbd03137bfaeee4fdb74ae31220a1698fb368544a4dd653`。
签名材料保存在：

```text
work/out/android/private/imouto-life-release.keystore
work/out/android/private/release-keystore.txt
```

这两个文件被 git 忽略，**不得上传、打进 APK/ZIP/安装器或公开文档**；必须离线备份，
后续覆盖升级必须继续使用同一 keystore 和 alias。口令只保存在同目录的本地说明文件
中，不写入仓库。

发布后清理了 `target/`、`work/out` 顶层一次性截图/日志/提交说明、旧
`ImoutoLife_fix_bundle_*.zip`、重复的 Android `media.pak`、`portable/`、
`re_all/`、`wolfmanual/` 等临时或可重建产物。`work/out` 现在只保留：

- `dist/godot/` 与 `dist/android/0.1.0/` 最终发布包；
- `android/private/` release 签名材料；
- `retail_saves/System.sav` 干净存档模板；
- `tools/nsis-3.11/` 安装器构建工具；
- `_archive/` 历史证据/报告（保留最终截图、审计报告与小型复现脚本；
  已删除其中所有旧 `.sav`）。

项目内所有 `SaveData*.sav` 已删除；`work/Data/Save/System.sav` 已用干净零售模板
重置，当前两者 SHA-256 均为
`aaf62fc54c1df1ee63f3e5338b05ec349476346ec1a42b532c8cba0e3b3d888d`。
因此依赖旧玩家编号存档的视觉/夜间夹具测试不会再用损坏或漂移的本地存档；
需要这些夹具时应从干净模板新建，而不是恢复已删除的旧快照。
清理后工作区为 **0.66 GB / 2,794 个文件**（`work` 619.43 MB，
`work/out` 443.91 MB），`target/` 已不存在。

