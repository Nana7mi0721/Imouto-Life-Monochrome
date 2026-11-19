# docs/re — 逆向与实机证据

本目录是**原版行为的证据层**：每篇都写明取证方法（只读 Ghidra 反编译 / 只读解析
`work/Data` / 实机截图度量）、置信度，以及与 [../ENGINE_BEHAVIOR.md](../engine/ENGINE_BEHAVIOR.md)
§3 清单的对应关系。

> **取证约定**：不执行原版 `Game.exe`。反编译结论附函数 VA 与伪码行号，资源层结论附
> 资源路径，实机结论附截图与度量值。反编译 dump 在 `work/out/re_all/`（未入库）。
>
> **引用仓内实现时用 `文件::符号`，不用行号**——行号会随改动漂移
> （2026-11-18 复核时已把本目录的残留行号引用统一改为符号名）。
> 指向**原版** `Game.exe` 的伪码行号不在此列：那是逆向证据的一部分，必须保留。

| 文件 | 主题 | 对应 §3 条目 | 取证方法 |
|---|---|---|---|
| [RUNTIME_CONSTANTS.md](RUNTIME_CONSTANTS.md) | 原版帧率锁、窗口初始尺寸、过渡掩膜图案、窗口皮肤与九宫格内边距 | §3-12 / §3-10 / §3-1 / §3-2 | 只读 `Game.ini` / `Config.exe` / `Game.exe` 常量与调用点 + 资源直读，不依赖反编译器 |
| [TRANSITION.md](TRANSITION.md) | 过渡语义与掩膜几何、tint × fade 的叠加顺序 | §3-10 / §3-11 | 只读 `work/out/re_all` Ghidra 12.2 全量 dump |
| [TEXT_METRICS.md](TEXT_METRICS.md) | 文本度量：行距公式、禁则、打字机累加水位 | §3-2 / §3-3 / §3-4 / §3-5 / §3-7 | 只读 Ghidra dump，逐项给「原版行为 / 仓内实现 / 差异 / 证据」 |
| [LAYOUT_METRICS.md](LAYOUT_METRICS.md) | 布局与缩放几何：坐标取整、默认原点、九宫格、极小盒、面板全链、超宽选项 | §3-1 / §3-2 / §3-6 / §3-7 / §3-8 / §3-9 | Ghidra dump + 数据解析 + 仓内 Rust 源码三方对照 |
| [SCREENSHOT_METRICS.md](SCREENSHOT_METRICS.md) | 实机截图标定：消息行距 23、选择支行距 27、面板 156×114 / 162×141、内缩 8 | 上述公式的本作落地值 | 实机截图度量（先标定 ≈1.5× 系统缩放再换算） |
| [EVENT_REACHABILITY.md](EVENT_REACHABILITY.md) | 350 个公共事件 + 40 个地图事件的逐事件可达性，以及 5 个场景的视觉回归基线 | 自动化验收 | 真跑：180 帧驱动 + `wolf-cli capture` 黑盒渲染；缺数据时 skip 并 exit 0 |

## 阅读注意

- 行号与 VA 对应各自写作时的快照；原版不变，但仓内实现位置会漂移，**以符号名与结论为准**。
- 反编译 dump 未入库，需要时用 `tools/re/ghidra` 从原版 `Game.exe` 重新 import（约 4 分钟）。
- 与 `../research/` 的分工：research 是**外部资料**（含已被本作实测推翻的条目），
  re 是**原版二进制与数据的取证**。两者都不与规范文档混放。
