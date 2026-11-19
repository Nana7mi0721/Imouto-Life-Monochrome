# 贡献指南（Contributing Guide）

感谢对本项目（2D 游戏数据级 Rust 重构运行时与 Godot 交互前端）的关注与支持！为了保持仓库的代码质量、结构规范与协作效率，请遵循以下流程与约定。

---

## 1. 架构总览

本仓库采用 Cargo Workspace 多模块结构，前端依托 Godot 4 引擎：

- `crates/wolf-format`：WOLF RPG 格式解析（Game.dat, 数据库, 字节码, DXArchive）
- `crates/wolf-save`：`.sav` 存档双向序列化与变量映射
- `crates/wolf-vm`：字节码虚拟机调度器与执行引擎
- `crates/wolf-render`：离屏渲染与文字排版
- `crates/wolf-audio`：音频混音与音效调度
- `crates/wolf-game`：游戏业务层（地图逻辑、UI 状态机、交互判定、设置与相册）
- `crates/wolf-cli`：命令行工具（验证 `verify`、预编译 `precompile`、回放、运行）
- `crates/wolf-launcher`：Windows 无控制台启动引导器
- `crates/wolf-gdext`：Godot 4 GDExtension 动态链接库绑定层
- `godot/`：Godot 4.7.2 前端工程（场景渲染、视口管理与触控/输入事件捕获）

---

## 2. 环境准备

1. **Rust 语言工具链**：Rust Stable（以 `rust-toolchain.toml` 为准）。
2. **构建环境**：
   - Windows 环境推荐在 Git-Bash 中执行构建与测试脚本。
   - 每次会话开始时载入环境配置：
     ```bash
     source tools/env.sh
     ```
3. **Godot 引擎**：Godot 4.7.2（需配置 `GODOT_BIN` 环境变量）。

---

## 3. 开发与测试流程

### 3.1 本地编译
```bash
cargo build -q --workspace
```

### 3.2 运行测试
- **基础工作区测试**（跳过需原始游戏数据的用例）：
  ```bash
  cargo test -q --workspace
  ```
- **完整数据验证测试**（需设置原始数据绝对路径）：
  ```bash
  WOLF_DATA_ROOT="$PWD/work/Data" cargo test -q -p <crate-name>
  ```
- **数据一致性校验**：
  ```bash
  WOLF_DATA_ROOT=work/Data ./target/debug/wolf-cli.exe verify
  ```

### 3.3 Godot 前端验证
```bash
bash tools/build-godot.sh     # 产出 godot/bin/wolf_gdext.dll
bash tools/smoke-godot.sh     # 执行自动化冒烟验证
bash tools/parity-godot.sh    # 长程像素与 VM 状态对齐验证
```

---

## 4. 协作约定与代码准则

1. **写作用域隔离**：在并行开发或多模块重构时，各任务涉及的文件范围需明确界定，避免修改冲突。
2. **数据与敏感文件保护**：
   - 绝对不要提交原始受限游戏解包资产（`work/Data/` 已通过 `.gitignore` 排除）。
   - 构建生成物、临时分析探针与私有截图切勿提交至版本库。
3. **提交规范**：
   - 提交信息应简明准确，描述修改动机、涉及模块与验证方式。
   - 保持中性、客观的工程化技术描述。
4. **深入阅读**：
   - 详细工程协作规则见 [AGENTS.md](AGENTS.md)。
   - 历史进度与里程碑日志见 [docs/HANDOFF_PROGRESS.md](docs/HANDOFF_PROGRESS.md)。
   - 全量文档导航见 [docs/README.md](docs/README.md)。
