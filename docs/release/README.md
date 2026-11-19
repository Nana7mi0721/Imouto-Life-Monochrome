# 发布流水线与资产管理（docs/release）

本目录包含 Windows / Android 双端自动化打包流程、资源封包规范与仓库资产清理台账。

## 文档清单

| 文档 | 状态 | 核心内容 |
|---|---|---|
| [PACKAGING.md](PACKAGING.md) | **现行 · 交付** | 全平台打包指南：Windows NSIS 安装包、便携 ZIP 与 Android ARM64 Release APK 签名流水线 |
| [ASSETS.md](ASSETS.md) | 现行 · 规范 | 素材导出与封包规范：`wolf-cli assets`、媒体清单校验与数据库资源提取 |
| [PROJECT_ASSETS.md](PROJECT_ASSETS.md) | 现行 · 资产 | 仓库资产盘点：发布后清理记录、保留资产与证据链清单 |

## 产物与交付路径

- **Windows 发行包**：`work/out/dist/<version>/`（含 `Imouto Life setup.exe` 与 `Imouto Life setup.zip`）
- **Android 安装包**：`work/out/dist/<version>/`（含 `ImoutoLife-release.apk`）
