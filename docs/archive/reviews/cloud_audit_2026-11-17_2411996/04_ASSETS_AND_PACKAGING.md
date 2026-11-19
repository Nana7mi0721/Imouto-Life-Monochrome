# 素材、封包与第三方代码审查报告 (`04_ASSETS_AND_PACKAGING.md`)

> **归档说明（2026-11-18）**：本文为2026-11-17 云端只读全量审查（基线 `2411996`）的组成部分，内容已被 [`docs/reviews/cloud_audit_2026-11-18_e716f08/`](../../../reviews/cloud_audit_2026-11-18_e716f08) 取代，
> 仅作证据链追溯，**不再代表当前工程事实**。文中行号、计数与结论可能已过时，
> 引用前请先核对现行文档。


---

## 1. 游戏素材审计 (`UNVERIFIED_ENV`)

受云端容器无 `work/Data` 与 `assets` 分支限制，无法在本机执行 `wolf-cli assets` 与 `m3_asset_refs`：
- **无法验证项**：当前数据根的总文件数、总字节数、按目录（`BGM/`、`SE/`、`cg/`、`Picture/`、`MapChip/`、`CharaChip/`、`SystemFile/`、`BattleEffect/`、字体、未注册地图、存档夹具）的静态与动态引用分布均为 `UNVERIFIED_ENV`。
- **历史基线提示（需在有数据时重跑确认）**：`GEMINI_FULL_AUDIT_GUIDE.md` §9.2 提及历史一次仅按 `op150` 字面量扫描为 1,069 个图片中 652 引用 / 417 未引用（含 `BattleEffect/` 47 个约 15.35 MiB）。由于 `op150` 扫描不覆盖 `kind 1/4` 动态字符串、tile layer 与数据库引用，**必须重跑以下基线命令并人工逐项裁决**：
  ```bash
  WOLF_DATA_ROOT="$AUDIT_DATA" cargo run -q -p wolf-cli -- assets --root "$AUDIT_DATA" --include-maps --format json
  ```

---

## 2. 封包脚本与发布路径审计

### 2.1 `tools/package-playable.sh`（CLI 可双击包）静态缺陷
1. **无过滤全量复制 `Data/`（P1, `F-06`）**：`tools/package-playable.sh:131` 执行 `cp -a "$DATA_ROOT/." "$OUT_DIR/Data/"`。这会导致：
   - 本机测试/调试残留的 `Save/` 存档被一并打包发给玩家；
   - 确认不使用的模板资源（如未注册示例地图、`BattleEffect/` 等，待实机数据裁决后）无法被裁剪。
2. **包名与二进制命名错位风险核实**：`crates/wolf-launcher/Cargo.toml` 定义 `name = "imouto-launcher"` 与 `[[bin]] name = "imouto-life"`，与 `package-playable.sh:91,95` 的 `-p imouto-launcher` 和 `target/release/imouto-life.exe` 一致；但 `AGENTS.md:49` 与文档常称其为 `wolf-launcher`，容易造成维护混淆。
3. **跨平台与校验和覆盖不足**：
   - 脚本硬编码 `cygpath` 与 `.exe`，仅能在 Windows MSYS2/Git Bash 下运行。
   - `checksums.txt`（`package-playable.sh:140`）仅校验 `Imouto Life.exe`、`runtime/wolf-cli.exe`、`README.txt`，未校验 `Data/` 核心文件完整性。

### 2.2 Godot 正式导出阻断 (`F-02`)
1. **缺失 `godot/export_presets.cfg`**：`godot/` 目录下没有任何导出预设文件，无法执行标准 Godot 导出（`godot --headless --export-release`）。
2. **GDExtension 平台限制**：`godot/bin/wolf_gdext.gdextension:9-10` 仅声明了 `windows.debug.x86_64` 与 `windows.release.x86_64` 指向 `res://bin/wolf_gdext.dll`。Linux 与 macOS 均未配置动态库路径，也无对应构建脚本。
3. **两套前端定位需明确**：当前 `package-playable.sh` 产出的是基于 `wolf-cli`（wgpu）的包，而非玩家实际在迁移中的 Godot 前端包。

---

## 3. 第三方插件 `godot/addons/godot_ai` 风险审计 (`F-03`)

| 检查项 | 静态核查结果 |
|---|---|
| 启用状态 | **已在 `godot/project.godot:32` 启用**（`enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")`） |
| 运行时 Autoload | **已全局注册**（`godot/project.godot:20`: `_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"`） |
| 来源与许可证 | `godot/addons/godot_ai/LICENSE` 为 **MIT License**（Copyright 2025 Godot AI contributors），许可证可商用/再分发 |
| 运行时行为 | `game_helper.gd` 在游戏进程注册 `"mcp"` 调试消息捕获，响应截图/调试请求；注释说明在导出 release 版调试通道关闭时闲置，但仍会在启动时加载约 58 KB GDScript 及依赖工具类 |
| 发行风险 | 1. 导出时若不通过 `export_presets.cfg` 显式排除 `addons/godot_ai/*`，会把整个 MCP 插件（约 500+ KB）打包进发行版；<br>2. 保持 Autoload 开启会在每个玩家的 `_ready` 阶段额外初始化调试节点。 |

**建议**：在建立 `godot/export_presets.cfg` 时，将 `addons/godot_ai/*` 加入导出排除列表，并把 `_mcp_game_helper` 从默认发布配置中剥离。

---

## 4. 供应链与 CI 状态
- `Cargo.lock` 与 `rust-toolchain.toml` 已入库锁定版本，Workspace 统一声明 `license = "MIT OR Apache-2.0"`、`rust-version = "1.87"`。
- 仓库根目录无 `.github/workflows/` CI 配置，所有编译、冒烟、视觉回归与打包均依赖本地手动脚本执行，缺乏自动化 Release Gate。
