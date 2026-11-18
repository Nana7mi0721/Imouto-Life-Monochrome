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

这些文件全部位于 `work/` 下，天然被 git 忽略；`tools/**` 与 `docs/PACKAGING.md` 才是
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
  `tools/package*`、`godot/export_presets.cfg` 与 `docs/PACKAGING.md`。
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
  Data\                  # release-data.manifest 精确白名单；Save\ 仅含 System.sav
  README.txt
  checksums.txt          # 包内所有文件的 SHA-256
work/out/dist/godot/Imouto Life setup.zip
work/out/dist/godot/Imouto Life setup.zip.sha256
work/out/dist/godot/Imouto Life setup.exe
work/out/dist/godot/Imouto Life setup.exe.sha256
```

`Imouto Life setup.zip` 的顶层目录固定为
`妹！生活 ～单色～ Godot/`；解压后直接进入该文件夹运行。

### 8.1 Data 白名单

`tools/package/release-data.manifest` 是发行包的唯一 Data 来源。当前清单为
**746 个文件 / 127,928,202 B**，再加干净的 `Data/Save/System.sav`
（155,615 B）后共 **747 个文件 / 128,083,817 B**。脚本不会复制完整
`work/Data`，只逐条复制清单中的相对路径。

相对完整 `work/Data` 当前排除 **618 个文件 / 55,684,128 B**，其中包含：

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
`SaveData*.sav` 都不会复制。

白名单校验器 `tools/package/release_data.py` 会拒绝绝对路径、`..`、
反斜杠、盘符、重复路径和符号链接逃逸；复制后再次比较目标文件集合，必须与
“清单 + `Save/System.sav`”完全相同。

### 8.2 Godot 导出预设

`godot/export_presets.cfg` 的 `Windows Desktop` 预设：

- `export_filter="all_resources"`；
- include 过滤器包含 `bin/*.gdextension`；
- exclude 过滤器排除 `addons/godot_ai/*`、`tests/*`、`bin/~*`、
  `bin/*.dll` 与只用于写入 exe 图标的 `icon_windows.png`；
- `application/icon="res://icon_windows.png"`，源图从
  `work/Data/icon_windows.png` 复制到 `godot/icon_windows.png`；
  Godot 4.7.2 会把 2048×2048 PNG 自动转换成多尺寸 Windows 图标，无需预生成 ICO；
- 运行时窗口图标使用 `application/config/windows_native_icon="res://window_icon.ico"`：
  32/48/64/128/256 帧来自 `work/Data/icon_windows.png`（任务栏/Alt-Tab），
  16×16 帧保留为无 GDExtension 时的后备标题栏图标。正常 Windows GUI 启动后，
  `GameView.gd` 会把 `res://icon_titlebar.png`（`inusuku.png` 的 256×256 头部
  裁切）经 GDExtension 以高分辨率 `WM_SETICON ICON_SMALL` 设置到标题栏，
  `ICON_BIG` 仍保持 ICO 的大帧；F11 切换窗口模式后会重新应用。
  exe 文件图标仍由上面的 `application/icon` 单独控制；
- Windows 资源字段从 `export_presets.cfg` 读取并同步给 Inno Setup：
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
4. staging 精确白名单并复核 `Data/Save/` 只能有 `System.sav`；
5. 生成包内 `checksums.txt`，可用 `sha256sum -c` 复核；
6. 校验便携 zip 可读、顶层目录正确，并生成 zip 外部 `.sha256`；
7. 如生成安装版，调用 Inno Setup 编译 `Imouto Life setup.exe` 并生成外部 `.sha256`。

### 8.4 Inno Setup 安装版

安装脚本模板是 `tools/package/ImoutoLife.iss.in`，由
`tools/package/render_inno.py` 注入实际路径、版本、发布者、版权和图标；
安装包图标来自 `tools/package/icon_windows.ico`（16/24/32/48/64/128/256）。

- 语言固定为简体中文（`ChineseSimplified.isl`，不显示语言选择页）；
- 默认安装目录为 `{autopf}\妹！生活 ～单色～ Godot`，用户可在安装向导中
  选择其它位置；游戏文件直接落在该 `app` 目录；
- 创建开始菜单快捷方式，桌面快捷方式为可选任务；
- `Data\Save\` 不参与覆盖式安装；首次安装只补充不存在的 `System.sav`，
  并标记为卸载时保留，避免升级或卸载删除玩家存档；
- 安装包使用和 exe 相同的高清图标，并写入版本、公司、产品名和版权。

生成安装版需要 Inno Setup 6 的 `ISCC.exe`。脚本依次查找
`ISCC_BIN`、`--iscc PATH`、项目内 `work/out/tools/InnoSetup6/ISCC.exe`
以及常见系统安装路径；缺失时真实打包会停止，`--no-setup` 可只生成便携包。
本轮只完成脚本与配置准备，尚未实际编译 `Setup.exe`。

`--dry-run` 只报告模板是否存在并继续打印数据计划，用于在无模板环境中检查过滤逻辑；
真实 release 导出仍会因模板缺失而失败。上一轮导出已验证的底层数据：

- `Imouto Life.exe` 109,299,944 B，PCK 内嵌；
- `bin\wolf_gdext.dll` 6,517,248 B；
- `Data/` 747 个文件，约 124 MiB；
- 旧命名 zip 约 141 MiB；新命名便携包与安装包将在下次正式打包时生成。

精简 Data 验证：`smoke.gd` 输出 `pictures=4 sprites=4`；
`save_roundtrip.gd` 新游戏自动走到卧室并保存/重载均为 38 张图片，
`System.sav` 哈希前后不变。

其它选项：`--no-zip`、`--no-setup`、`--iscc PATH`、`--skip-build`、`--force`、
`--out-dir`、`--zip-dir`、`--manifest`、`--system-save`、`--preset`。

