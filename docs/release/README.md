# 发布流水线与资产管理（docs/release）

本目录包含 Windows / Android 双端自动化打包流程、资源封包规范与仓库资产清理台账。

## 文档清单

| 文档 | 状态 | 核心内容 |
|---|---|---|
| [PACKAGING.md](PACKAGING.md) | **现行 · 交付** | 全平台打包指南：Windows NSIS 安装包、便携 ZIP 与 Android ARM64 Release APK 签名流水线 |
| [IOS_PRIVATE_BUILD.md](IOS_PRIVATE_BUILD.md) | 现行 · 私有 | iOS 未签名 IPA：Actions 构建、Data/字体注入、Sideloadly 安装与 7 天重签边界 |
| [GODOT_TEMPLATE.md](GODOT_TEMPLATE.md) | 现行 · 构建 | 定制 Godot 4.7.2 导出模板：safe/aggressive 参数、实测体积与打包接入 |
| [ASSETS.md](ASSETS.md) | 现行 · 规范 | 素材导出与封包规范：`wolf-cli assets`、媒体清单校验与数据库资源提取 |
| [PROJECT_ASSETS.md](PROJECT_ASSETS.md) | 现行 · 资产 | 仓库资产盘点：发布后清理记录、保留资产与证据链清单 |

## 产物与交付路径

- **Windows 发行包**：`work/out/dist/godot/<version>/` 与命名规范的
  `ImoutoLife-<version>-windows-amd64-setup.exe` / `.zip`（可选 `-slim` 媒体精简版）
- **Android 安装包**：`work/out/dist/android/<version>/` 与
  `work/out/dist/android-slim/<version>/`，文件名为
  `ImoutoLife-<version>-android-arm64.apk` / `-slim.apk`。
  `media.pak` 以未压缩的 `.blob.cfb` 留在 APK 内并由运行时直接随机读取，
  首次启动不再复制第二份到应用数据目录。
- **iOS IPA**：`work/out/dist/ios/<version>/`，engine-only 文件名为
  `ImoutoLife-<version>-ios-arm64-unsigned.ipa`；在 Windows 注入数据后为
  `ImoutoLife-<version>-ios-arm64-unsigned-full.ipa`（标准）或
  `ImoutoLife-<version>-ios-arm64-unsigned-full-slim.ipa`（slim）。两个 full
  IPA 作为 Release 附件分发，engine-only IPA 保留在 CI artifact/本地；
  IPA 与注入后的 Data 均不提交仓库。
