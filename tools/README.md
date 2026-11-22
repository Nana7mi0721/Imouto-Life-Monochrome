# 工具与自动化脚本索引（tools/）

本目录包含工程构建、自动化测试、打包发布及逆向审计所需的脚本与辅助工具。

## 1. 环境配置

| 脚本 | 说明 | 示例 |
|---|---|---|
| `env.sh` | Bash 环境变量初始化（自动定位项目根、添加 cargo/cmake/ffmpeg 路径） | `source tools/env.sh` |
| `env.ps1` | PowerShell 环境变量初始化 | `. tools/env.ps1` |
| `setpath.ps1` | 永久添加工具链路径至 Windows 用户 PATH | `powershell -File tools/setpath.ps1` |

## 2. 构建脚本

| 脚本 | 目标平台 | 说明 |
|---|---|---|
| `build-godot.sh` | Windows (x86_64) | 编译 `wolf-gdext` 为 `godot/bin/wolf_gdext.dll`（用于 Godot 前端） |
| `build-android.sh` | Android (aarch64) | 交叉编译 `wolf-gdext` 为 Android 动态库 |

## 3. 测试与验证

| 脚本 | 说明 | 适用场景 |
|---|---|---|
| `smoke-godot.sh` | Godot headless 冒烟测试（验证标题、按键、鼠标、读档等基础链路） | GDExtension 构建后常规快速回归 |
| `parity-godot.sh` | 长程与像素级对齐测试（600/1200/1800 帧状态及渲染比对） | 里程碑交付与渲染一致性验证 |
| `audit-godot.sh` | 自动化审计驱动脚本 | 执行特定用例的追踪与证据采集 |

## 4. 打包与发布

| 脚本 | 产出物 | 说明 |
|---|---|---|
| `package-godot.sh` | Windows 便携版 ZIP + NSIS 安装程序 | 完整发布包流水线，自动嵌入 PCK 与必要运行时；`--slim` 生成媒体精简版，`GODOT_TEMPLATE_WINDOWS` 可指定定制 2D 模板 |
| `package-android.sh` | Android APK (`.apk`) | Android 安装包构建、资源打包与对齐签名；`media.pak` 留在 APK 内直读，`GODOT_TEMPLATE_ANDROID` 可指定定制模板 |
| `build-godot-template.sh` | 定制 Godot 导出模板 | 拉取匹配源码并用 SCons 构建精简 Windows/Android 模板，产物在 `work/out/godot-template/out/<version>/` |
| `package/normalize_windows_integrity.sh` | 修复 Windows 可执行文件的 Low 完整性标签 | 在 Low 工作区生成的 NSIS Setup 会被 Windows 以低完整性启动，无法写 `%TEMP%`；脚本在不提权的前提下把文件改回 Medium，内容与哈希不变 |
| `package-playable.sh` | 快速便携测试包 | 供内部测试用的轻量级打包 |

## 5. 辅助子目录

- `tools/package/`：打包模版文件（NSIS 脚本模板 `ImoutoLife.nsi.in`、启动器脚本、图标及资源清单）。
- `tools/re/`：逆向工程分析辅助工具（Ghidra 脚本、字节码解析等）。
