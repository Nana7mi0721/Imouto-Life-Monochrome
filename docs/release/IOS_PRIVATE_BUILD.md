# iOS 私有构建与签名安装

本页描述仅用于个人/获授权测试的 iOS 构建流程：macOS 或 GitHub Actions 先产出
不含游戏数据的 engine-only unsigned IPA，Windows 再把本作数据注入 IPA，最后由
Sideloadly 使用自己的 Apple ID 重签名并安装。

> **数据权利边界**：`work/Data` 与本作媒体/字体属于原权利方。不要公开上传、
> 分发或提交完整 IPA、`Data/`、注入后的 IPA，也不要提交 `NotoSansCJKsc-Bold.otf`。
> 仅为你自己合法持有的数据做私有测试。仓库只提交源码、脚本与文档。

## 1. 固定参数

iOS 导出预设位于 `godot/export_presets.cfg` 的 `[preset.2]`：

| 项目 | 值 |
| --- | --- |
| 设备族 | iPhone + iPad |
| 方向 | 横屏（由 `godot/project.godot` 的手持方向设置决定） |
| Bundle ID | `com.inusuku.imoutolife` |
| 短版本 | `0.1.1` |
| 构建号 | `2` |
| 最低 iOS | `15.0` |
| 架构 | arm64 |
| 图标 | `res://icon_windows.png` → `icons/icon_1024x1024` |
| 导出方式 | 仅导出 Xcode 工程（`application/export_project_only=true`） |
| 文件访问 | Files App 与 iTunes 文件共享开启，便于私有存档备份 |

`application/app_store_team_id="XXXXXXXXXX"` 只是 Godot 要求的非空 10 字符占位值。
本 unsigned 导出不使用真实 Team ID；Sideloadly 会用登录的 Apple ID 生成临时签名。

## 2. CI：产出 engine-only IPA

手动触发 `.github/workflows/ios-unsigned.yml`（workflow_dispatch）。工作流在
`macos-latest` 上执行：

1. 下载 Godot 4.7.2 macOS 编辑器与 iOS export templates；
2. `bash tools/build-ios.sh` 产出
   `godot/bin/ios/libwolf_gdext.a`；
3. `bash tools/package-ios.sh --skip-build --unsigned --force` 导出 Xcode 工程，
   调用 `xcodebuild` 以无签名方式构建 arm64 `.app`，再压缩成 IPA；
4. 上传两个文件：

```text
work/out/dist/ios/0.1.1/ImoutoLife-0.1.1-ios-arm64-unsigned.ipa
work/out/dist/ios/0.1.1/SHA256SUMS.txt
```

CI **不包含** `Data/` 或字体，也不会把完整 IPA 上传到公开位置。GitHub Actions 的
artifact 有保留期限，下载后请放到本地 `work/out/`，不要把 IPA 提交进 git。

## 3. macOS 本地打包

前置条件：macOS、Xcode（命令行工具已选好）、Rust 的
`aarch64-apple-ios` target、Godot 4.7.2 及对应 iOS export templates。

```bash
cd "$(git rev-parse --show-toplevel)"
source tools/env.sh >/dev/null 2>&1

export GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
bash tools/package-ios.sh --unsigned --force
```

如已有 `godot/bin/ios/libwolf_gdext.a`，可复用并跳过 Rust 构建：

```bash
bash tools/package-ios.sh --unsigned --skip-build --force
```

自定义路径和 Godot 可执行文件：

```bash
bash tools/package-ios.sh \
  --godot "/Applications/Godot.app/Contents/MacOS/Godot" \
  --out-dir "work/out/dist/ios/0.1.1" \
  --unsigned \
  --force
```

产物：

```text
work/out/dist/ios/0.1.1/ImoutoLife-0.1.1-ios-arm64-unsigned.ipa
work/out/dist/ios/0.1.1/SHA256SUMS.txt
```

Godot 4.7 对 `--export-release "iOS" <out>/ImoutoLife.xcodeproj` 的实际布局是
`<out>/ImoutoLife/ImoutoLife.xcodeproj`。脚本会递归定位工程，并用
`xcodebuild -list` 自动选择可用的 scheme（优先 `godot_apple_embedded`，其次
`ImoutoLife`），不依赖硬编码。

### macOS 本地完整包（可选）

如果只想在本机直接测试带数据的 IPA，可在压缩前注入：

```bash
bash tools/package-ios.sh \
  --unsigned \
  --data-dir "work/out/dist/godot/0.1.1/Data" \
  --force
```

`--data-dir` 会把数据复制到 `.app/Data`。这样得到的仍是 unsigned IPA，签名前
不要再用注入脚本重复处理。该完整 IPA 只能私有使用，不得分发。

## 4. Windows：向 IPA 注入 Data

Windows 侧不需要 `zip` 命令，脚本使用 Python 3 的 `zipfile`。输入必须是尚未签名
的 engine-only IPA；**必须在 Sideloadly 签名之前注入**，否则注入会使已有签名失效。

仓库根目录（Git Bash）：

```bash
cd "$(git rev-parse --show-toplevel)"
source tools/env.sh >/dev/null 2>&1

bash tools/inject-ios-data.sh \
  "work/out/dist/ios/0.1.1/ImoutoLife-0.1.1-ios-arm64-unsigned.ipa" \
  "work/out/dist/godot/0.1.1/Data" \
  --font "path/to/NotoSansCJKsc-Bold.otf" \
  --out "work/out/dist/ios/0.1.1/ImoutoLife-0.1.1-ios-arm64-unsigned-full.ipa"
```

如果数据目录中已经有正确的 `NotoSansCJKsc-Bold.otf`，可以省略 `--font`；没有该
字体时游戏会回退到 iOS 系统字体，但文字度量可能与 Windows 基线不同。字体文件
不要提交到仓库。

脚本行为：

- 拒绝绝对路径、反斜杠、盘符、`..` 路径穿越和多个 `Payload/*.app`；
- 用输入 `Data/` 完整替换 `<app>/Data`，避免旧数据残留；
- 可选把字体写成 `<app>/Data/NotoSansCJKsc-Bold.otf`；
- 原 IPA 中的符号链接条目按原字节复制，不依赖 Windows 创建符号链接的权限；
- 原条目的 Unix mode 通过 `ZipInfo.external_attr` 保留（可执行位不丢失）；
- 输出前检查 `Payload/*.app`、`Data/BasicData` 和 ZIP CRC。

默认输出名是输入名去掉 `.ipa` 后加 `-full.ipa`。成功时会打印 SHA-256。期望文件：

```text
work/out/dist/ios/0.1.1/ImoutoLife-0.1.1-ios-arm64-unsigned-full.ipa
```

也可以直接使用位置参数，省略显式 `--out`：

```bash
bash tools/inject-ios-data.sh \
  "work/out/dist/ios/0.1.1/ImoutoLife-0.1.1-ios-arm64-unsigned.ipa" \
  "work/out/dist/godot/0.1.1/Data" \
  --font "path/to/NotoSansCJKsc-Bold.otf"
```

## 5. Sideloadly 签名与安装

1. 在 Windows 安装 Apple 设备驱动（iTunes/Apple Devices）和 Sideloadly，USB 连接
   iPhone/iPad，解锁并选择“信任此电脑”。
2. 把 `ImoutoLife-0.1.1-ios-arm64-unsigned-full.ipa` 拖入 Sideloadly。
3. 输入自己的 Apple ID，按提示完成免费开发者签名；不要使用他人的账号。
4. 选择设备并开始安装。若系统要求开发者模式，按下一节开启后重试。
5. 安装完成后首次启动可能提示“不受信任的开发者”，按下一节信任证书。

免费 Apple ID 的常见限制（Apple 可能调整，以 Sideloadly/Xcode 提示为准）：

- 签名通常 **7 天后过期**，过期后 App 无法启动；用同一 Apple ID、同一 Bundle ID
  覆盖签名可继续使用，操作前仍建议备份存档。
- 免费配置通常限制为 **3 台设备**，同一设备上并行自签 App 数量也有限。达到上限时
  需要撤销旧设备/App 或等待配额恢复。
- 这不是 App Store 分发，不能替代正式签名、TestFlight 或企业证书。

## 6. 开发者模式与证书信任

**开发者模式（iOS 16+）**：设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启设备 →
重启后再次确认。若入口未出现，先连接 Sideloadly/Xcode 尝试安装一次，或确认系统
版本支持该入口。

**信任证书**：首次启动被拦截后，进入设置 → 通用 → VPN 与设备管理 → 在“开发者
App”下选择对应 Apple ID/开发者证书 → 信任。随后重新启动游戏。

**iOS 18.7.12 不支持 TrollStore**：不要尝试 TrollStore 或依赖永久签名的方案；
该版本请使用 Sideloadly/开发者证书流程。也不要为了安装而关闭系统安全机制。

## 7. 存档、升级与备份

- 游戏存档位于 App 的 `user://Save`；预设已开启 Files App/iTunes 文件共享，
  可在 Files 的“我的 iPhone/iPad”中查看并复制 `Save/` 做备份。
- 标题画面的存档页提供“导入”“导出”按钮。Android 调用系统文档选择器；
  iOS 4.7.2 没有原生文件对话框后端，会自动回退到应用内选择器，但 iOS 的
  `user://` 就是 Files App 中可见的应用 Documents 目录：
  - 导入：先在 Files 中把 `.zip` 或 `.sav` 复制到游戏目录，再点“导入”
    选择。单个 `.sav` 会先要求选择系统存档或槽 1–4，再弹覆盖确认；
    ZIP 会说明将替换/移除哪些存档并提示自动备份；
  - 导出：备份写入同一目录，完成后可在 Files 中复制到 iCloud/其他位置。
- 覆盖安装时保持相同 Bundle ID (`com.inusuku.imoutolife`) 和同一 Apple ID，通常可
  保留沙盒数据；升级前仍应先复制 `Save/`。
- 7 天签名过期后不要先删除 App；直接重新签名覆盖安装通常能保留数据。若必须卸载，
  先备份 `Save/`。
- 不要把自己的存档、完整 `Data/` 或注入 IPA 上传到公开仓库、网盘公开链接或 issue。

## 8. 常见问题

| 现象 | 处理 |
| --- | --- |
| `tools/package-ios.sh requires macOS with Xcode` | 该脚本只能在 macOS 运行；Windows 只运行 `tools/inject-ios-data.sh`。 |
| Godot 报 `Export template not found` | 在 Godot 4.7.2 中安装 iOS export templates，确认 `ios.zip` 存在。 |
| Godot 报 App Store Team ID 为空 | 预设中的 `XXXXXXXXXX` 占位值不得清空；unsigned 导出仍要求非空。 |
| `xcodebuild: error: ... scheme ... not found` | 删除 `--out-dir` 后重跑，脚本会重新读取 `xcodebuild -list`；也可检查 Xcode 是否能打开生成的 `.xcodeproj`。 |
| `iOS GDExtension static library missing` | 先在 macOS 执行 `bash tools/build-ios.sh`，或去掉 `--skip-build`。 |
| `Python 3 was not found` | 安装 Python 3.8+，或设置 `PYTHON_BIN` 指向 `python.exe`。 |
| 注入后提示 `missing Payload/*.app` | 输入不是有效 IPA，或下载/解压不完整；重新获取 engine-only IPA。 |
| App 启动即退出或提示未信任 | 开启开发者模式并信任证书；确认使用的是注入后、由 Sideloadly 重新签名的 IPA。 |
| 7 天后无法启动 | 免费签名过期；用同一账号重新签名覆盖安装，先备份 `Save/`。 |
| 设备/App 数量达到上限 | 在 Apple ID 的开发者设备列表中移除不再使用的设备，或等待配额恢复。 |

## 9. 校验

macOS：

```bash
cd work/out/dist/ios/0.1.1
shasum -a 256 -c SHA256SUMS.txt
```

Windows 可对注入后的 IPA 计算并比对 SHA-256：

```powershell
certutil -hashfile "work\out\dist\ios\0.1.1\ImoutoLife-0.1.1-ios-arm64-unsigned-full.ipa" SHA256
```

发布检查只需确认最终 IPA 文件名、SHA-256、注入后的 `Payload/*.app/Data/BasicData`
存在；不要把 `work/out/`、IPA 或数据加入 git。

## 10. 已构建产物（2026-11-21）

GitHub Actions `iOS Unsigned IPA` run `44770540312` 已成功完成：

| 产物 | 大小 | SHA-256 |
| --- | ---: | --- |
| `ImoutoLife-0.1.1-ios-arm64-unsigned.ipa` | 32,216,634 B | `cf2f011cadc7cb3b9e49feddbc70f0f0d69e6cfe9561fbf6df2eec52be83828c` |
| `ImoutoLife-0.1.1-ios-arm64-unsigned-full.ipa` | 153,216,224 B | `5a390ca61bb3ffaeb0ab8fb38abeab0e38e288e91ffe599b5cf511220e330d2e` |

两个文件位于 `work/out/dist/ios/0.1.1/`，同目录 `SHA256SUMS.txt` 覆盖两者。
full IPA 已包含 `Payload/ImoutoLife.app/Data/BasicData` 与
`Data/NotoSansCJKsc-Bold.otf`；尚未在 iPhone XR 上完成 Sideloadly 安装验证。
