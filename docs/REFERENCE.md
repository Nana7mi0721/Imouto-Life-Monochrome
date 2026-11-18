# 参考资料索引（REFERENCE）

本文件登记重写本作时可用的一手/二手资料。所有路径均为仓库内相对路径或本机绝对路径。

## 1. 日文原版（一手，最高价值）

* 路径：`E:\EROGAME\限界!？お兄ちゃん 「妹!せいかつ」～モノクローム～2.03`
  * 说明：这是**日文原版**（非汉化）。原先目录名因 CP932→GBK 编码错乱变成乱码，已按用户授权还原为规范日文名；内部 12 个日文文件名也一并还原（`マニュアル01..06.jpg`、`お読みください.txt`、`更新履歴.txt`、`やさしさゴシックボールド.ttf` 等）。ASCII 文件名（`Game.exe`、`*.wolf`、`Save` 等）保持不变。
  * 结构：顶层含 `Data/`（已解包的 **17 个 .wolf 归档**：BasicData / MapData / Picture / BGM / SE / CharaChip / MapChip / SystemFile / SystemGraphic / BalloonBase_CafeLatte / BattleEffect / EnemyGraphic / FIcon / Fog_BackGround / cg 等）、`Save/`、`Game.exe`、`Config.exe`、`Game.ini`、`Game_ErrorLog.txt`、`GuruguruSMF4.dll`、两份字体、6 页官方说明书 `マニュアル01..06.jpg`、`お読みください.txt`、`更新履歴.txt`。
  * 用途：可直接对照**原始 UI 文本 / 字体 / 说明书**，免去从汉化版反推原版的一整轮猜测；说明书 6 页是一手 UI 参照。
  * 注意：本作目标对齐 **2.03**（日文原版与 zh-CN 汉化均为 2.03）。攻略站 AyauGaming 写的是 2.04，数值不能直接当 2.03 结论。

## 2. 攻略与研究链接（二手）

来源清单见 `docs/相关链接.txt`（GPT 搜集，已按证据价值排序）。最值得收藏的五份：

| 优先级 | 资料 | 用途 |
| --- | --- | --- |
| 1 | [Gamerch 攻略 Wiki](https://gamerch.com/biim/318371) | 事件流程、UI、道具、状态、结局条件 |
| 2 | [AyauGaming 数值攻略](https://ayaugaming.com/rj258445) | 行动消耗、属性成长、事件门槛（针对 2.04，慎用） |
| 3 | [Doureview 攻略/感想](https://www.doureview.com/blog-entry-236.html) | 结局、行动效果交叉核对 |
| 4 | [PTT 玩家讨论](https://www.pttweb.cc/bbs/H-GAME/M.1620109249.A.106) | 边界条件、特殊事件反例 |
| 5 | [官方作品介绍页](https://masukuinu.sakura.ne.jp/imouto/mono_01/index.html) | 作者原始描述、功能名称 |

作者一手来源：CI-en <https://ci-en.dlsite.com/creator/64>、官网 <https://inusuku.dojin.com/>、X <https://x.com/inusuku>。

**下一步建议**（来自链接整理者）：把 Gamerch / AyauGaming / Doureview 三份攻略里的每个数值抽成一张交叉验证表，同值标为高可信、异值标版本差异、单源值保留来源标签，避免把攻略作者的错误写进 Rust 引擎。

## 3. 实机截图（一手，zh-CN 2.03）

目录：`ptr_sc/`（**39 张 PNG，gitignore，本地证据**）。用户按游戏内 PrintScreen 取得，
文件名用中文描述画面内容。尺寸约 1533–1542 × 862–910，即 **1024×576 原生帧的 1.5 倍缩放**
（窗口截图带边框），适合对**布局**（不是字形——汉化字体为 Microsoft Yahei UI Bold）。

> 早先登记过的 `prt sc/`（10 张 GUID 命名的 PNG）已不存在；该目录名只存在于
> `.gitignore` 与历史文档里，**不要**再去那里找图。当前实机证据一律取自 `ptr_sc/`。

| 分组 | 代表文件 | 界面 |
| --- | --- | --- |
| 标题与存档 | `标题.png`、`标题_存档.png`、`数据.png` | 标题画面、标题→存档画面、系统数据面板 |
| 开场 | `开场对话_妈妈.png`、`开始游戏_选项1.png`、`开始游戏_选项2.png` | 序幕妈妈对话、两个初始选项分支 |
| 室内日常 | `卧室1.png`、`卧室2.png`、`卧室_存档.png`、`卧室_右侧item表拉出.png`、`卧室_点击妹妹_首句话.png`、`卧室_点击妹妹_交互选项.png`、`卧室_点击妹妹_交互_玩游戏_结束.png`、`卧室_妹妹交互_选项_泡茶.png` | 卧室场景、存档界面、道具栏、对话框与选项 |
| 对话与消息框 | `对话_妹妹1.png`、`中央消息.png`、`中央消息_system提示.png` | 底部气泡、中央消息框、系统提示消息框 |
| 夜间互动 | `恶作剧_首次系统提示.png`、`恶作剧_BAD&GOOD条特写.png`、`恶作剧_凝视胸部_穿衣.png`、`恶作剧_存档.png`、`恶作剧_选择结束_二次确认(再次点击会出现选项).png`、`恶作剧_选择结束_过场开头.png` | BAD/GOOD 条特写、参数百分比、结束二次确认、存档 |
| 洗澡支线 | `洗澡_一个人洗_去偷窥_浴室.png`…（5 张） | 浴室场景与偷窥分支的选项/过场 |
| 妹妹姿态 | `ev1 妹寝そべる.png`、`ev2 妹ソファー.png`、`ev3 妹座る.png`、`ev4 妹体育座り.png`、`ev12 就寝妹.png`、`ev25 妹座るバスタオル.png` | 睡/坐/躺等姿态的立绘差分 |
| 白天与外出 | `白天_起床_妹妹对话.png`、`白天_出门_妹妹对话.png`、`白天_过场（社会人）.png`、`傍晚_购物.png`、`傍晚_购物后回家_过场.png` | 时间推进与外出购物流程 |
| 相册 | `相册.png` | 回忆相册格位 |

顶栏在两套界面里一致：时间 + 星期 + 姓名/身份（学生）+ 行动力 xx/65 + 精力 3/3 + 持有金钱。右下角有「数据」按钮、左下角有「保存」按钮。

## 4. 存档样本（一手）

zh-CN 安装目录 `E:\EROGAME\Imouto! Life ~Monochrome~ zh-CN Ver\Save\`：`SaveData01.sav`(293,742 B)、`System.sav`(155,615 B)。`wolf-cli verify` 的 save 段已能解析（version 0x80 / end_byte 0x19 / checksum_ok）。日文原版 `Save/` 亦有对应样本。
