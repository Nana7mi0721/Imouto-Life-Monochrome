## 变更概述
简要描述本 PR 的核心改动内容、动机及所解决的问题。

## 涉及模块
- [ ] `crates/wolf-format` (数据与格式解码)
- [ ] `crates/wolf-save` (存档系统)
- [ ] `crates/wolf-vm` (虚拟机调度)
- [ ] `crates/wolf-render` / `crates/wolf-audio` (音画渲染)
- [ ] `crates/wolf-game` (游戏层业务逻辑)
- [ ] `crates/wolf-cli` / `crates/wolf-launcher` (CLI 与启动器)
- [ ] `crates/wolf-gdext` / `godot/` (Godot 4 前端与桥接)
- [ ] `docs/` / `tools/` (文档与构建脚本)

## 验证与测试
- [ ] `cargo check -q --workspace` 编译通过
- [ ] `cargo test -q --workspace` 默认单元测试通过
- [ ] 本地运行测试验证（如有涉及真实游戏数据或 Godot 前端验证请注明）

## 检查项
- [ ] 代码风格符合 `.editorconfig` 规范
- [ ] 未提交任何原始受限商业游戏资产（`work/Data/`）
- [ ] 说明文档与注释使用中性客观的工程化语言
