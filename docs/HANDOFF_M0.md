# Imouto! Life ～単色～ Rust 重写 — 新会话交接

本文件写给**下一个接手的会话**（agent 或人）。读完这一份就能继续，不需要翻聊天记录。
仓库：`E:/Study/github program/Imouto Life`（**尚无 .git、无 Cargo.toml、无代码，只有 docs/**）。
撰写时状态：2025-10-30；上一作（续作）仓库 `E:/Study/github program/imoto life` HEAD `c6d8ea7`，`wolf-cli verify` = PASS 70 checks。

---

## 0. 直接复制给新会话的提示词

```text
接手一个进行中的项目：用 Rust 数据级重写《妹！生活 ～単色～》（いぬすく 2019，WOLF RPG Editor 制作，手上是 zh-CN 汉化 2.03）。
仓库：E:/Study/github program/Imouto Life（目前只有 docs/，没有 .git、没有代码）。
姊妹项目（已完成的续作重写，代码在这里复用）：E:/Study/github program/imoto life，HEAD c6d8ea7，wolf-cli verify PASS 70/70。

第一步，按顺序读这些文件（都在 Imouto Life/docs/ 下）：
1. HANDOFF_M0.md ← 本文件，全部结论与陷阱都在里面
2. GPT_RESEARCH_GROUPS.md（附 B 有里程碑表与数据勘察结论）
3. docs/research/gpt-reports/ 下 deep-research-report*.md 共 6 份 + GPT_RESEARCH_GROUPS.md（GPT 调研报告，其中若干条已被数据实测推翻，HANDOFF_M0.md §7 有采信/推翻清单）

然后：
- 在 Imouto Life 建 git 仓库 + Cargo workspace（7 个 crate 从 imoto life 复制），按 HANDOFF_M0.md §5 的 M0 清单逐条做；
- 数据根用 work/Data（HANDOFF_M0.md §5 有复制命令；原始 Data.wolf 的解包方式已验证，§3.2）；
- 每完成一项就跑 `./target/debug/wolf-cli.exe verify` 和 `cargo test -q --workspace`，并以本作自己的 docs/BASELINE.json 为准。

硬性要求：
- 不要重做已完成的工作（数据勘察、格式解密、6 份调研报告都已完成）；
- 不要照抄上一作的 docs/BASELINE.json（那是第一部游戏的期望值）；
- 不要为 Sys 变量 104/105 建 player/camera/滚动模型（本作 5 张注册地图都是定屏，§3.7）；
- 不要用 PowerShell 抢前台/模拟按键截图；截图只能让用户按游戏内 PrintScreen；
- 环境初始化：先 `source tools/env.sh`（从上一作复制并改两处绝对路径，§8）；
- 每推进一步就更新 HANDOFF_M0.md 的「进度」段，方便下一次交接。
```

---

## 1. 一句话现状

**数据层已经全部勘完、引擎层几乎不用写新东西**：本作有 350 个公共事件（其中 212..303 是本作自有 92 个，0..211 是 WOLF 自带「基本システム Ver2.20」模板）、8 张地图（注册 5 张）、46+35 个 opcode **全部**已在续作的解释器里实现过；真正要做的是「把续作的 7 个 crate 搬过来 + 加一张 WOLF 2.00 世代常量表 + 修 CP932 的 .project 读取 + 补一个 DXArchive VER6 解包分支」，然后才是内容/演出（日常循环、妹妹状态、H 场景、相册）。

**本作没有战斗、没有公会/任务/探索。** 这是内容与演出项目，不是代码量项目。

---

## 2. 两个仓库

| 仓库 | 路径 | 状态 |
| --- | --- | --- |
| 本作（第二作，Imouto! Life ～単色～） | `E:/Study/github program/Imouto Life` | 只有 docs/（7 个 md + docs/vendor/uberwolf-ref/），**未 git init、无代码** |
| 姊妹作（续作 Living With Sister: Monochrome Fantasy，已完成到 M6） | `E:/Study/github program/imoto life` | HEAD `c6d8ea7`；`verify` PASS 70/70；507 个 #[test]；7 个 crate 共 47,417 行 |

上一作的未跟踪 scratch（**不要提交**）：`crates/wolf-format/examples/opscan.rs`、`crates/wolf-format/tests/_scratch_cdata.rs`、`crates/wolf-format/tests/_scratch_event.rs`。

本作安装目录：`E:/EROGAME/Imouto! Life ~Monochrome~ zh-CN Ver`（12 个文件：Config.exe 299,008 B / **Data.wolf 176,347,260 B** / Game.exe 6,365,184 B / Game.ini 156 B / GuruguruSMF4.dll 147,456 B / manual01..06.jpg 1000x1415 / readme.txt 1,142 B）。

`readme.txt`（UTF-16LE）要点：(C) いぬすく《妹！生活 ～単色～》2019/8/11；inusuku@inusuku.dojin.com；<https://ci-en.jp/creator/64>；「本作品使用 SmokingWOLF 的 WOLF RPG Editor 制作」<http://www.silversecond.net/>；**需要鼠标**；Z/ENTER/左键=决定，X/BS/右键=取消；禁止二次发布与商业利用。
`Game.ini`：`Start=0 SoftModeFlag=0 WindowModeFlag=1 SEandBGM=3 FrameSkip=0 Proxy= ProxyPort= ScreenShotFlag=1 F12_Reset=1 Display_Number=0 Old_DirectX_Use=0`（`ScreenShotFlag=1` ⇒ 游戏内 PrintScreen 会往安装目录写 1024x576 原生帧，这是唯一允许的截图取证方式）。
`manual01..06.jpg` 是官方说明书（一手 UI 资料）；读具体术语前必须重开图看，不要凭记忆引用。

---

## 3. 已实测确认的硬事实

### 3.1 Data.wolf 已解开（头号成果，可复现）

* 文件 176,347,260 B，首 8 字节 `83 5D CC 7D 49 D4 DC F1` —— **不是明文 `DX`**，因为整包（含 64/48 字节头）被 key 循环 XOR。
* 本作是**老世代 DXArchive VER6** 归档（不是现代 VER8，也不是 WolfCrypt/WolfProt，不需要 Game.exe 里的任何材料；Game.exe 只被 UberWolfCli 用来定位游戏目录，内容无关，已用 1000 字节随机文件复验）。
* 固定 key（UberWolf `DEFAULT_CRYPT_MODES` 里 "Wolf RPG v2.20" 那条，12 字节）：`38 50 40 28 72 4f 21 70 3b 73 35 38`，经 `KeyCreate` 变换后得实际 XOR 流 **`c7 05 ca 7d 8d e3 de f1 d9 0c 85 f4`**（12 字节循环）。
* 解出的头（48 字节 `<HHIQQQQQ`）：`Head 0x5844 Version 6 HeadSize 145348 DataStart 48 NameStart 176201912 FileStart 56708 DirStart 144836 CodePage 932`。
* 结构：`DARC_HEAD_VER6` 48 B / `DARC_FILEHEAD_VER6` 64 B / `DARC_DIRECTORY_VER6` 32 B；**文件数据地址相对 DataStart，子目录地址相对 DirectoryTableStart，文件表与目录表相对 NameP**；文件名 = `NameP + NameAddress` 处 `u16 n` 然后 `+ n*4 + 4` 取到 NUL 的 CP932（名字表里同名并列 UPPERCASE 与原始大小写两份，n 就是跳过多少个 4 字节组）；数据 XOR 的 position 基准是 **DataSize**（不是数据偏移）。
* 解压分支（22 个条目用到）：`u32 destsize / u32 srcsize(=字段值-9) / u8 keycode`，之后 `keycode` 为转义、`code>keycode` 要 `-1`、`conbo=(code>>3)+(code&4? *sp<<5 : 0)+4`、`index` 1..3 字节可变宽 +1、复制走「倍增 memcpy」逻辑；权威实现 `docs/vendor/uberwolf-ref/DXLib/DXArchiveVer6.cpp:1343`。
* **验证：1,361 个条目 / 179,877,496 B，逐字节比对 100% 相同（verified 1361 / bad 0）**，其中 1,339 个未压缩、22 个压缩（全部是 `BasicData/*.dat|.project`、8 张 `.mps`、`BasicData/EncodedIconList.xxxxx` 和一个 2,355,728 B 的 TTF）。
* 复现脚本（在上一作仓库 `work/` 下，已 gitignore）：`_dw8.py`（全量校验，**已复制到本仓库 docs/vendor/uberwolf-ref/dw8_verify.py**）、`_dw2.py`（头+目录树）、`_dw5.py`/`_dw6.py`/`_dw7.py`（未压缩/压缩清单与解压）。
* 参考实现：`docs/vendor/uberwolf-ref/`（`DXLib/DXArchive.h, DXArchiveVer6.h, DXArchiveVer6.cpp, Huffman.h, Huffman.cpp` + `UberWolfLib/WolfDec.cpp, WolfDec.h` + LICENSE）。完整 UberWolf 源码在上一作 `work/uw/UberWolf-main/`（gitignore）。下载方式：`curl -sSL 'https://codeload.github.com/Sinflower/UberWolf/tar.gz/refs/heads/main' -o uw.tgz`（codeload 可用；api.github.com/contents 必须带 `?ref=main`）。

**⇒ 结论：Rust 侧自举解包是明确可移植的工作，不是研究课题。** 顺序：VER6 头 → 12 字节 KeyCreate/KeyConv → 目录表遍历 → VER6 的 Huffman/LZ。

### 3.2 已解包的数据树（直接开工用）

**已复制进本仓库：`work/Data`（1,361 文件 / 179,877,496 B = 171.5 MiB，已核对与解包树一致）**；原件在上一作仓库 `work/imouto/Data`，与 UberWolfCli 全新解包 `diff -rq` 完全一致。
资产分布：BGM 69.2 MB、cg 47.9 MB、BattleEffect 15.4 MB、根目录 13.3 MB（两份 TTF）、SE 10.6 MB、Picture 9.5 MB（330 个 `album_000..` 相册图）、BasicData 2.9 MB、MapChip 0.7 MB（102 个 pipo 系列）、SystemFile 0.6 MB（22）、MapData 0.6 MB、SystemGraphic 0.5 MB（21，含 `WindowBase.png`/`CursorBase.png`/`TitleGraphic.png`）、Fog_BackGround/BalloonBase_CafeLatte/CharaChip（11）/FIcon 各 ~0.1 MB；cg 393 文件（`bg_NNN_MM.jpg` / `bg_NNN_sNN.png`）。
字型：Data 根下有 `07やさしさゴシックボールド.ttf`（2,355,728 B）与 `◆GenJyuuGothicX-P-Bold.ttf`（11,575,152 B）；但 Game.dat 用的是系统字体 `Microsoft Yahei UI Bold`（`C:/Windows/Fonts/msyhbd.ttc` 16,883,552 B 存在）。

### 3.3 Game.dat（29,172 B，版本 2.00）

`version_header 0x00`；`u8_len 22`，`u8_settings [16,8,8,1,60,0,1,3,0,0,0,6,14,0,0,4,9,4,0,1,1,1]`；9 个字符串：`Imouto! Life ~Monochrome~ zh-CN Ver.` / `0000-0000` / 第 3 个是敏感字段（占位遮蔽，勿复述、勿猜测） / `Microsoft Yahei UI Bold` / 5 个空串 / `Ver2.03`；recorded_size 29,171 = filesize-1 ✓；`unknown_size 11`（续作为 0，**新字段，解析要容忍**）；`u16_len 19`，`u16_settings [38218,2,1,4,2,8,4,16,8,32,16,64,32,128,64,10000,1024,576,222]`（续作前 15 项相同，第 16 项 325、后段 `(1024,576,0,0,0,21569)`）；随机种子 **22507 / 23301**；static random 28,942 B，最大值 **251**（续作 28,936 / 127）；footer **0xC2**。分辨率同为 1024x576、tile 16、60 fps。

### 3.4 CommonEvent.dat（2,227,358 B，**格式与续作完全一致，只有版本/脚注不同**）

magic 7 B + `version_header 0x00` + 类型后缀 `FC\0` + `version 0x8F` + u32 事件数 **350** + 事件记录 + footer **0x8F**。
350 事件全部按续作的字段顺序（unknown4 → memo → SEP_1 0x8F → arg_names → arg pages → value pages → defaults → SEP_2 0x90 + colour + 100 self names → SEP_3 0x91 → SEP_4 0x92 + return_name + return_id）走完，零结构意外。
规模：**63,506 槽，空行 9,890，实体 53,616**；regular opcode 直方图（46 种，含 0）：
`0:9890, 99:62, 101:2113, 102:163, 103:7050, 105:4, 106:75, 107:1, 111:4271, 112:101, 121:8442, 122:448, 123:93, 124:197, 125:70, 126:6, 130:1, 140:168, 150:5433, 160:1, 170:194, 171:94, 172:445, 174:9, 175:1, 176:54, 179:687, 180:1426, 201:55, 210:2869, 211:4, 212:267, 213:612, 220:2, 221:8, 222:1, 250:2699, 270:5, 281:3, 290:249, 300:1158, 401:7562, 420:1012, 421:85, 498:881, 499:4535`。
**没有 opcode 104**（续作才有）。`raw_condition` 只有 32/34/35/18/99 五种 ⇒ `run_condition = raw & 0x0F` 得 0/2/3。
事件分区（`work/imouto/ce_titles.txt` 有全文）：
* **0..211 = WOLF「基本システム Ver2.20」模板**（前缀 ○ / ▲ / ◆ / X[共] / X[移] / X[戦]，208 号就叫「【基本ｼｽﾃﾑVer2.20説明書】」）——续作已实现过同类，可复用。
* **212..303 = 本作自有 92 个**（含槽数）：212 フキダシ会話文表示 169、213 アイコン表示長い 61、214 応援会話リコ 166、216 性興味監視 16、219 ■事後処理中断 784、220 ■事後処理 783、221 ぴぽや感情・状態ｱｲｺﾝ表示 61、222 画面拡大 22、223 ウィンドウ処理 666、224 フィールド上処理 262、225/226 深夜1吐息A/B 30、227 深夜1表示 392、228 深夜1衣服 842、229 深夜1アニメ 54、230 深夜1 157、231 文字エフェクトみぎ 959、232 文字エフェクトひだり 1285、233 文字エフェクトセリフ 385、234 文字エフェクト挿入 385、235 文字エフェクト例外 169、237 Hステータス 112、238 ステータス 78、239 アイテムリスト 55、240 立ち絵表示 257、241 ┗立ち絵瞬き 54、242 ステータス表示 44、243 時刻表示 68、244 行動力変動 28、245 夜コマンド 1016、246 ┣コミュニケーション 288、247 ┣ＴＶ視聴 1210、248 ┣ゲーム 450、**249 ┣お風呂 3912（全库最大）**、250 ┣ネットショップ 594、251 ┗就寝 1250、252..255 日中処理 学生/フリーター/社会人/ダメ人間 15/13/33/20、256 日中メニュー 977、257 帰宅メニュー 325、258 晩ごはん処理 1726、259 休日メニュー 2670、260 ┗休日ゲーム 441、261 ×◆座標変数初期化 52、262 ▲先頭空白削除 48、263 ▲文字列数値判定 57、**270 ┣[ﾒｯｾｰｼﾞ]表示処理 2744**、271 オートスキップ 157、273 お風呂タイマー2 668、274 お風呂タイマー1 1993、275 カットイン呼び出しお風呂 192、276 カットイン顔表示 107、**277 ┣警戒度メータ 237**、279 実行バー表記 96、280 カットイン呼び出し 27、281 カットインタイマー右 1119、282 カットインタイマー左 690、283 カットイン呼び出し夜 880、284 射精 358、285..288 文字エフェクト ローター/電マ/バイブ/アナルバイブ 82/46/58/46、290 コマンドカットイン 127、293 カットイン呼び出しトイレ 107、294 トイレタイマー1 666、295 トイレ処理 816、296 ■プレイ傾向 263、297 スタッフロール 36、298 素股処理 192、299 素股タイマー 378、300 カットイン呼び出し素股 73、301 アルバム表示 471、302 クレジット 249、303 アルバム画面呼び出し 905。
* **304..349 全是 1 槽空占位。**

### 3.5 数据库三件套 + .project 编码（**第 5 处世代差异**）

| 文件 | 大小 | version | footer | 类数 / 行数 |
| --- | --- | --- | --- | --- |
| DataBase.dat | 102,901 | 0xC1 | 0xC1 | 40 / 756 |
| CDataBase.dat | 84,203 | 0xC1 | 0xC1 | 30 / 649 |
| SysDatabase.dat | 11,614 | 0xC1 | 0xC1 | 28 / 1,074（**type 6 系統変数名只有 135 行**，续作 150） |
| SysDataBaseBasic.dat | 438 | 0xC0 | 0xC0 | 与续作**逐字节相同** |
| TileSetData.dat | 59,770 | **0xD1 (209)** | 0xCF | 续作是 0xD2，我们的 loader 两个都收 |
| MapTree.dat | 416 | 0x90 | 0xBC | 与续作同形（子节点顺序不同） |
| MapTreeOpenStatus.dat | 75 | — | 0x26 | 同形 |

`.project` 伴生文件：**本作是 CP932，续作是 UTF-8**。`SysDatabase.project` 21,025 B 首字节 `1C 00 00 00 0B 00 00 00 83 7D 83 62 83 76 90 DD 92 E8 00`（= cp932「マップ設定」）；续作同名文件 35,972 B 是 `E3 83 9E…`（UTF-8）。
上一作 `crates/wolf-format/src/database.rs:533-545 fn name_at` 只试 UTF-8，会在第一个名字上失败 ⇒ **整份名字表返回 0 条**。修法：UTF-8 失败后回退 CP932（`dxarchive/sjis.rs` / `cp932.rs` 已有解码器）。
`.project` 记录格式（两代都逐字节走到末尾，imoto SysDatabase 35,972/35,972、imouto 21,025/21,025）：`u32 type_count` → 每类：t_str 类名 / u32 字段数 + t_str×n / u32 行数 + t_str×n / t_str 描述 / u32 byte_len + byte_len 字节（字段类型码）/ 块1 u32 n + n×t_str（字段注释）/ 块2 u32 n + n×(u32 k + k×t_str)（字符串参数）/ 块3 u32 n + n×(u32 k + 4k 字节)（数值参数）/ 块4 u32 n + 4n 字节（默认值）。

### 3.6 地图：磁盘 8 张，**注册 5 张**

`SysDatabase` type 0（マップ設定，field positions `[2000,1000,1001,1002,1003,2001,2002,2003]`）注册：
row 0 `MapData/TitleMap.mps` 53x30（タイトル）、row 1 `MapData/SampleMapA.mps` 64x36（自宅1）、row 3 `MapData/Map003.mps` 70x170（ニューゲーム処理）、row 24 `MapData/Map024.mps` 53x30（ロード処理）、row 31 `MapData/Map031.mps` 53x30（セーブ）。
未注册的是引擎示例：Dungeon 40x30、Map002 100x30、SampleMapB 30x30。
所有 `.mps` 都是 `version 0x65` / footer 0x66 / `version_header 0x00` —— **续作的 mps loader 原样兼容**（`crates/wolf-format/src/mps.rs:76 VERSIONS [0x65,0x66]`）。
地图事件总计 **56 事件 / 102 页 / 12,266 槽 / 空行 2,188 / 实体 10,078 / 35 种 opcode**：
`{0:2188, 101:767, 102:31, 103:351, 111:1033, 112:4, 121:2522, 122:6, 123:61, 124:76, 125:3, 126:17, 130:8, 140:79, 150:622, 151:7, 161:1, 162:1, 172:56, 174:1, 179:2, 180:127, 201:73, 210:855, 212:18, 213:46, 221:2, 250:80, 270:3, 290:72, 401:1849, 420:222, 421:13, 498:2, 499:1068}`。
逐图：Dungeon 5/6/79、Map002 5/13/416、Map003 2/15/47、Map024 1/16/3、Map031 1/17/63、**SampleMapA 35/95/11,558**、SampleMapB 6/101/36、TitleMap 1/102/64。
SampleMapA 重点事件（M2 目标）：ev0 ニューゲーム処理 @(30,0) trigger1 367 槽；ev1 妹寝そべる 6 页；ev9 日中メニュー 2 页；ev15 コマンドリスト表示 9 页（槽 116/68/70/139/62/66/56/70/42）；ev16 コマンド選択判定 458；**ev17 コマンド実行 7 页（4980 槽为主）**；ev18 カーソル切り替え 1567；ev19 当たり判定描画 209；ev20 例外処理監視 101；ev23 深夜表情自動変更 654；ev26 アイテムクリック監視 352；ev30 スタッツ 323；ev31 パンツ詳細 302；ev35 アルバム起動判定 2 页。

### 3.7 全局变量表 = 状态模型的权威命名（SysDatabase type 14，302 行）

`14 妹位置、20 妹信頼度、21 妹性興味、22 妹感度、23 妹機嫌、24 妹快感、25 妹不愉快、26 媚薬効果、4 時、5 分、6 曜日、7 所持金、8 就寝時間、18/19 睡眠深さ/最大、32 日中メニュー、33..41 物品、42 スタミナ消費、50 ダンベル、51 トレーニングマシン、52 コンドーム、56 深夜終了、59 嫌悪感割合値、60 基礎行動力、61 ボーナス行動力、62 精力、63 嫌悪感最大値、64 嫌悪感、65 テンション、66 射精感、70 深夜パート、74/75 スタミナ量/MAX、77 安眠茶、78 アフターピル、97 休日メニュー、99 経過日数、100 深夜1、115 拡大率X、119 就寝兄、122 中出し、127 妊娠、129 妹欲求不満度、138 リビングに居る、143/144/145 電マ/バイブ/アナルバイブ、150 アナル開発度、`**154 警戒度**`、155 お風呂タイマー1、160 お風呂タイマー2、163 はじめから、170 トイレタイマー、175 立ち絵表示位置、176 スタッツ表示中、177 フリー乱数、178 素股タイマー、180 射精回数、187 イカせた回数、189 総射精量、199 クリア、200 妊娠エンド、201 100日到達、202 パンツコンプリート、203 エンディング、205 処女、209 安全日、210..229 パンツ1..20、230 祭り、231 旅行、232 クリスマス、234 正月、235 バレンタイン、237 アルバムアイコン表示、238 アルバム表示中、244/245/246 各开放、247 アルバム回想実行中、248 クレジット中、249/250 お花見、260 コマンド実行中、299 サークルロゴ`。
Sys 变量（type 6，135 行）中 row 104 = `Ｘスクロール値`、row 105 = `Ｙスクロール値`（与续作逐字相同），row 1/2 = メッセージウィンドウ X/Y、3/4 = 選択肢ウィンドウ X/Y、110 = 乱数シード、111 = [読]画面アクティブ状態、115 = [Read]Game.exe version(x100)、116/117/118 = Screen size X/Y + Tile size。
**⇒ M3 的结论可直接沿用：104/105 是引擎维护的相机滚动输出，没有脚本读写；本作 5 张注册地图都是定屏（无行走图事件页），不要建 player/camera 跟随模型。**
完整名字表已落盘：上一作 `work/out/imouto_var_names.txt`（10,189 B），含 SysDatabase type 4/5/6/14、type 0/7/8/13 的全部行名。

### 3.8 数据库类型清单（判断「模板残留」用）

`DataBase` 40 类（0 技能 37 字段/44 行、2 アイテム 21/25、3 武器 35/40、4 防具 40/40、6 戦闘コマンド 4/19、8 状態設定 46/24、9 敵個体 26/42、10 敵行動AI 48/40、11/12 属性/状態耐性 100、13 敵グループ 12/41、15 用語設定 32/1、17 システム設定 35/1、20 吹き出しアイコン 4/11、21 EXスキル 4/40、22 吹き出し会話 20/10、23 サポートキャラ 4/10、24 立ち絵設定用 5/10、25 ランダム肩書 20/21、26 メッセージウィンドウ種類 35/9、30 アニメ設定 1/100、31 統計テキスト 4/4）。
`CDataBase` 30 类（0 主人公ステータス 60/17、3 属性耐性 100/40、6 パーティー情報 7/1、7/8/9 所持個数 1/10、18 基本ｼｽﾃﾑ用変数 2/100、19 万能ｳｨﾝﾄﾞｳ一時DB 11/200、25/26/27 キーコンフィグ系）。
**战斗相关表（DataBase 9/10/11/12/13/21）与 `BattleEffect/` 15.4 MB 资产都是 WOLF 模板残留**，本作无战斗玩法（地图事件里也没有战斗事件）——M0 资产审计可标死资产。

---

## 4. 世代表：需要改的常量（**只此 4 处 + 1 处编码**）

上一作硬编码的是续作（2.10）的常量。**不要改成「两代都接受」的硬编码**：改用「按容器头 `version_header` / version 字节选一套常量表」的 `WolfGeneration`（2.00 → `version_header 0x00`；2.10 → `0x55`），保证两作的 verify 基线互不污染。

| 位置（上一作路径） | 现值（2.10） | 本作（2.00） | 说明 |
| --- | --- | --- | --- |
| `crates/wolf-format/src/gamedat.rs:41` | `FOOTER = 0xC3` | **0xC2** | 校验点在 `:93` |
| `crates/wolf-format/src/commonevent.rs:102` | `FOOTER = 0x90` | **0x8F** | `version 0x8F` **不校验**（`parse` 只读不判，见 `:123`），`version_header 0x00` 也不校验；只需放宽 footer |
| `crates/wolf-format/src/database.rs:40,42` | `VERSION = FOOTER = 0xC2` | **0xC1 / 0xC1** | 闸门在 `:65`，三个 .dat 一致 |
| `crates/wolf-format/src/tileset.rs:44-48` | `VERSION_210 0xD2 / VERSION_209 0xD1 / FOOTER 0xCF` | **0xD1 已在白名单** | 无需改 |
| `crates/wolf-format/src/mps.rs:76,95` | `VERSIONS [0x65,0x66] / FOOTER 0x66` | **0x65 已支持** | 无需改 |
| `crates/wolf-format/src/maptree.rs:63,65,145` | `0x90 / 0xBC / 0x26` | 完全相同 | 无需改 |
| `crates/wolf-format/src/database.rs:533-545` `fn name_at` | 只试 UTF-8 | **需 CP932 回退** | 否则 `.project` 名字表全丢 |
| `crates/wolf-format/src/dxarchive/mod.rs:29,32` | `HEADER_SIZE 64 / VERSION 8` | **VER6 分支**（48 B 头 / u64 地址 / 12 字节 key） | 新增，勿改现有 VER8 路径 |

`wolf-cli verify` 对 `work/imouto/Data` 的现状（放宽前）：15 项 FAIL = game.parse footer 0xC2、ce.parse footer 0x8F、database.parse ×3（`unsupported database version 0xC1`，`database.rs:65`）、maptree.children_of_0 顺序（3,24,31 vs 3,31,24，只是顺序）、mps 七项（全是按续作算的期望值：maps 8 vs 9、events 56 vs 73、pages 102 vs 134、slots 12,266 vs 37,610、blank 2,188 vs 7,052、real 10,078 vs 30,558、opcodes 34 vs 40、empty_maps 0 vs 2；`mps.parse 0 parse errors`）、tileset.version（210 vs 209）。`save.*`/`dxarchive.*` 全 ok（save 读的是续作存档）。

---

## 5. M0 开工清单（按顺序，每步可验证）

1. **建仓库**：`cd 'E:/Study/github program/Imouto Life' && git init`；复制上一作的 `.gitignore`（含 `/target`、`/work/`、`*.exe`、`/tools/{bin,cmake,ffmpeg}/`）、`rust-toolchain.toml`（channel stable + rustfmt + clippy）、`tools/env.sh`（改 `T` 与 `IMO` 两处绝对路径）、`tools/env.ps1`/`setpath.ps1`。
2. **搬 crate**：`cp -r '/e/Study/github program/imoto life/crates' .` + 复制根 `Cargo.toml`（7 成员、resolver 2、`workspace.package` version 0.1.0 / edition 2021 / rust-version 1.87 / license MIT OR Apache-2.0 / publish false、profile.dev opt-level 1 debug 1、dev.package."*" opt-level 2、release opt-level 3 + lto thin + codegen-units 1）。`cargo build -q` 必须绿。
3. **数据已就位**：`work/Data` 已含 1,361 文件 / 179,877,496 B（无需再复制；若要重来：`cp -r '/e/Study/github program/imoto life/work/imouto/Data' work/Data`）。`work/` 要进 `.gitignore`。`wolf-cli` 的 `WOLF_DATA_ROOT` 默认指向 `./work/full`（`crates/wolf-cli/src/main.rs:580`，默认值在 `:517`），本作要改成 `./work/Data`。
4. **WolfGeneration**：按上表加两代常量表 + 用 `version_header`/`version` 选表；`gamedat`/`commonevent`/`database`/`tileset` 的解析都改成「读表拿常量」。
5. **.project CP932**：`name_at` 加 CP932 回退，然后确认 `SysDatabase.project` 能出 28 个类名、`DataBase.project` 40 个、`CDataBase.project` 30 个。
6. **本作基线**：写 `docs/BASELINE.json`（**不要照抄上一作**），先落这些键：`game_dat`（25 个游戏参数、种子 22507/23301、分辨率 1024x576）、`common_events`（350 / 63,506 / 9,890 / 53,616 / 46 opcodes）、`map_events`（56 / 102 / 12,266 / 10,078 / 35 opcodes）、`precompile`、`tileset_data`（版本 209）、`file_versions`（各 .dat 的 version+footer）、`wolf_archives`（1,361 条目 / 179,877,496 B；若实现 VER6 解包，再加 `dxarchive_ver6` 键：key、1,339 未压缩 + 22 压缩、逐字节校验计数）。
7. **wolf-cli 子命令**：`verify / precompile / list / capture / play / run` 沿用；`capture` 的 `--map` / `--map-run` / `--boot` 要改成本作注册地图名（TitleMap / SampleMapA / Map003 / Map024 / Map031）。
8. **（可选但推荐先做）VER6 解包分支**：把 `work/_dw8.py` 的逻辑移植到 `crates/wolf-format/src/dxarchive/ver6.rs`，让 `wolf-cli verify --wolf` 直接读 `Data.wolf` 并与磁盘树逐字节比对 —— **验收标准就是 1,361/1,361 全等**，这是整条数据链的自证。
9. 跑 `cargo test -q --workspace` + `verify` 全绿后提交（`git -c user.name=... -c user.email=... commit -F work/_commit.txt`）。

---

## 6. 上一作代码地图（复用时的定位表）

| 关注点 | 位置 |
| --- | --- |
| wolf-cli 子命令分发 | `crates/wolf-cli/src/main.rs:311-412`；`play.rs` 为交互播放 |
| 数据根 `WOLF_DATA_ROOT` | `crates/wolf-cli/src/main.rs:580`（默认 `./work/full`，见 `:517`） |
| 游戏安装目录探测 | `crates/wolf-cli/src/main.rs:1874 fn game_dir` |
| Game.dat 解析 | `crates/wolf-format/src/gamedat.rs`（`FOOTER` `:41`，校验 `:93`） |
| CommonEvent 解析 | `crates/wolf-format/src/commonevent.rs`（字段序列 `parse_event`，footer `:102`） |
| 数据库 + .project | `crates/wolf-format/src/database.rs`（`ProjectNames::parse` `:415`，`name_at` `:533`，`project_type_at` `:554`） |
| mps / tileset / maptree | `crates/wolf-format/src/{mps,tileset,maptree}.rs` |
| DXArchive VER8 | `crates/wolf-format/src/dxarchive/{mod,key,huffman,lz,crc32,sjis,cp932}.rs`（VER6 新分支加在这里） |
| VM 解释器 | `crates/wolf-vm/src/{exec,program,magic,rng}.rs`；`exec.rs` 的 match 臂覆盖 0/99/101../121/150/210/250/270/290/300/401/420/498/499 等，**本作 46+35 种全部在内** |
| 渲染 | `crates/wolf-render/src/{lib,text,diff}.rs`（wgpu 30 + glyphon 0.12）与 `examples/imgdiff.rs` |
| 游戏层 | `crates/wolf-game/src/{game,map_runtime,picture,tilemap,choice,window,assets,db,key}.rs` |
| 像素对照工具 | `cargo run -p wolf-render --example imgdiff -- A.png B.png [--out diff.png]` |

---

## 7. 6 份 GPT 调研报告 vs 数据实测（采信 / 推翻）

报告在 `docs/research/gpt-reports/deep-research-report.md`..` (5).md`（7,485 / 10,513 / 7,360 / 6,822 / 9,865 / 10,418 B），前置问题组同目录 `GPT_RESEARCH_GROUPS.md`。**总体质量参差：多为二手攻略，凡与数据冲突一律以数据为准。**

| 结论 | 判定 |
| --- | --- |
| 正式日文名 `妹！せいかつ ～モノクローム～`，作者 いぬすく，2019 年 8 月（readme 写 08-11，报告写 08-22） | 采信（日期取 readme） |
| 本作**无官方中/英文版、无 Steam 版**；我们这份 zh-CN 是民间汉化（改了标题串与字体为 Microsoft Yahei UI Bold） | 采信，且被 Game.dat 的两个字符串直接证实 |
| 四种身份基础值：学生 行動力 60 / 金钱 3000–6000 / 就寝 24:00；フリーター 40 / 8000–12000 / 23:00；社会人 30 / 30000–50000 / 23:00；ダメ人間 25 / 1000 / 24:00；行動力上限 99（ダンベル +5、筋トレ机 +15） | **高价值，待与事件 252..255、244、251 交叉核对后入基线** |
| 道具：お茶 +10、玉露 +20、紅茶 +5 且就寝 +1h、コーヒー 就寝 +2h（至凌晨 2 点）、精力剤 精力上限 +1（上限 9）+2 精力 +20 行動力、媚薬 感度最大 + 快感 50%、安眠茶 浅眠→熟睡、アフターピル 3 天内清怀孕 | 待核对（事件 250 ネットショップ / 33..41 物品变量） |
| 妹妹四项 = 信頼（数）/ 興味（数）/ 感度（%）/ キゲン（五档：爆発寸前 / 不機嫌 / 普通 / 上機嫌 / 兄Love），興味 每日自动下降 | 采信（对应全局 20/21/22/23） |
| 阈值：信頼≥150 且上機嫌 ⇒ 共浴；≥200 ⇒ 新选项；≥250 ⇒ 帮洗身；興味≥150 ⇒「我也想做」；≥200 ⇒ 口交取代手交；信頼≥300 ⇒ 额外 H/CG；同居 100 天 ⇒ HappyEnd；所持金≥100000 且「産めばいい」⇒ TrueEnd；共 3 个结局 | 待核对（全局 199/200/201/202/203/127/209） |
| **报告称「警戒度」在任何资料里都没出现** | **推翻**：全局变量 **154 = 警戒度**，事件 **277 ┣警戒度メータ** 236 槽在实现它 |
| 报告 3（UI/操作）：方向键移动、Z/Enter 确认、长按加速、F12 退出；Config.exe 选项名与默认值「未找到」 | 低价值，只能靠说明书（manual01..06）与实机截图补 |
| 报告 1（引擎世代）：2.00≈2011-07-19、2.02a 2012-06-10、2.10 2013-08-09、2.20 2017-03-22（内部又写 2016-11-22，自相矛盾）、3.00 2022-11-22；「Ver2.10 起改了数据加密方式」 | 部分采信；**本作实测是 DXArchive VER6 + WOLF v2.20 固定 key，与「2.10 改加密」的说法不矛盾但也不能据此推世代，一律以容器头字节为准** |
| 报告 0 称未公开 CG/结局/BGM 数量 | 采信；但数据里可直接数：cg 393 文件、Picture 相册 330 张、BGM 目录 69.2 MB |

**报告没覆盖、但数据已给的**：注册地图只有 5 张；事件分区（0..211 模板 / 212..303 自有）；opcode 全覆盖；Data.wolf 已解；`.project` 是 CP932；SysDatabase type6 只有 135 行。

---

## 8. 环境与协作陷阱（血泪，别重踩）

1. **每条 bash 命令开头**：`cd '/e/Study/github program/Imouto Life' && source tools/env.sh >/dev/null 2>&1`（env.sh 提供 msys PATH + 中科大 rustup 镜像 + `CARGO_NET_GIT_FETCH_WITH_CLI`）。路径必须用 msys 形式（`/e/...`）。
2. `C:/Users/REISEN/.cargo/config.toml` 必须保留 `[http] proxy = ''`：注册表代理（127.0.0.1:7890）会被 cargo/libcurl 采用而 curl 不采用，症状是「curl 能连镜像、cargo 不能」。
3. **sccache 会破坏 MSVC 链接**（LNK1104 lnk{GUID}.tmp）——不要开。
4. **GitHub 直连下载只有 ~2 KB/s**：源码包走 `codeload.github.com`（已验证可用），普通文件用 `ghfast.top` 前缀；`api.github.com` 可读元数据，但读文件内容要带 `?ref=main` 并检查 `.message`（限流）。`cargo-binstall` 不可用（os error 5），用 `cargo install --locked`。
5. **不要用 PowerShell 抢前台/模拟按键截图**（用户明令：会造成他无法操作电脑）。截图只能由用户按游戏内 PrintScreen（`ScreenShotFlag=1`），产物落在安装目录，1024x576 原生。
6. **Python 补丁脚本必须写 `newline=''` 且「写 .new 再 `os.replace`」**：曾因 `io.open(newline='\\n')`（C 层先截断文件再报非法 newline）把 `game.rs` 截成 0 字节。引用锚点要先 `assert` 存在。
7. **临时输出放 `work/out/`**：`/tmp` 在 Windows 上映射到系统临时目录，bash 派生的子进程写它会 `PermissionDenied (os error 5)`；测试临时目录用 `target/test-scratch` + `env!(CARGO_MANIFEST_DIR)`。
8. 交互式截图/报告都落到 `work/out/`；`work/` 与 `/tools/{bin,cmake,ffmpeg}/` 已 gitignore。
9. 团队规模上限 8 人（lead + 7）；共享任务板用 `team_task_*`；写作用域按文件/目录切分。
10. 提交身份按命令传入：`git -c user.name='imoto lead' -c user.email='lead@imoto.local' commit ...`；`git add` 的 CRLF 警告无害。

---

## 9. 不要做的事

* 不要为 Sys 104/105 建玩家坐标/相机跟随/滚动模型（§3.7）。
* 不要把 opcode 104（本作没有）或战斗模板当成待实现功能。
* 不要照抄上一作的 `docs/BASELINE.json`（期望值属于第一部游戏）。
* 不要把 `.wolf` 解密当成「未解难题」——已解开（§3.1），也不要引入 WolfCrypt/WolfProt 的复杂路径（那是 2.225+ 世代）。
* 不要在没读说明书/实机截图的情况下凭 GPT 报告写 UI 数值。
* 不要提交 `work/`（175 MB 数据 + 探针脚本）、`tools/bin|cmake|ffmpeg`、`*.exe`。

---

## 10. 恢复后的第一条命令

```bash
cd '/e/Study/github program/Imouto Life' && source tools/env.sh 2>/dev/null || echo 'run M0 step 1 first (copy tools/env.sh)'
git status --short 2>/dev/null | head
cat docs/HANDOFF_M0.md | head -60
```

若 M0 已开工，接着跑：

```bash
cargo build -q --workspace && cargo test -q --workspace 2>&1 | tail -20
WOLF_DATA_ROOT="$PWD/work/Data" ./target/debug/wolf-cli.exe verify | tail -20
```

---

## 11. 进度

> 完整的按时间顺序进度日志（M0–M7 与 C 任务，每一步的改动、验证数字与坑）已拆到
> **[HANDOFF_PROGRESS.md](HANDOFF_PROGRESS.md)**。本节只保留**当前状态摘要**；
> 新会话判断“现在是什么状态”以本节 + 各专题文档为准，查历史细节再翻日志。

### 11.1 当前状态（2026-11-18）

* **2026-11-18 复审开放项与正式发包（当前状态）**：`F-07` 模态期间已停止
  `wolf.frame()`；`F-11` 由 `textpic::is_inline_image_only()` 区分纯图片条与
  图文混排，Atlas 贴图补 anchor/scale/alpha；`Assets` 增加 256 MiB 近似 LRU；
  两份 Godot 回归接入 smoke 并改用 `--data-root`；发布预设关闭 console wrapper，
  `AGENTS.md` 改为 9 个 crate。`cargo test -p wolf-game --lib` 373/373、
  `m14_visual_regression` 5/5、`wolf-cli verify` PASS 64/1、Godot smoke exit 0。
  正式便携 ZIP 为 764 entries / 751 files（UTF-8 中文顶层目录），
  `Data/Save` 仅含干净 `System.sav`；`Setup.exe` 已由 Inno Setup 6.7.4 生成，
  版本资源语言为简体中文。产物在 `work/out/dist/godot/`，哈希见
  `Imouto Life setup.zip.sha256` 与 `Imouto Life setup.exe.sha256`。
  `cargo test --workspace` 仅余已记录的玩家 `SaveData01` 夹具漂移
  `m17_ui_regressions::night_message_click_is_not_eaten_by_parallel_pollers`。

* **2026-11-18 开场 SE 多行 cell 的 CRLF 文件名修复（当前状态）**：
  `DataBase.dat` 的用户 DB 音效行形如
  `SystemFile/[SE]Cancel.ogg\r\n80\r\n100`；opcode 140 之前把整段 cell 当作
  文件名字符串，Godot 侧扩展名变成 `ogg\r\n80\r\n100`，导致
  `[SE]Cancel`/`[SE]Cursor` 等 16 个 SE 报 `unsupported extension`。
  `crates/wolf-vm/src/exec.rs` 的 `split_sound_cell()` 现在按首行取文件名、
  后两行取音量/音高；`split_first_line()` 同时修正 122 首行截取的 CRLF 行尾。
  新增 3 条回归，`smoke-godot.sh` exit 0 且不再出现该 audio warning。
  发行包仍需 Inno Setup 6 的 `ISCC.exe` 才能生成 `Setup.exe`；便携 ZIP 不受影响。

* **2026-11-18 开场取消穿透与窗口图标（当前状态）**：`102` 无 `421` 时，
  Esc/右键/框外点击不再回落到块尾；VM 只有拿到真实 cancel/choice 目标才解除等待，
  宿主同时消费输入边沿。修复前会跳过 `SampleMapA ev0 pc32-92` 的职业 flag、金钱
  与 AP，并改变问题 2 的随机消费。真实数据回归
  `m27_choice_cancel` 3/3、`m27_opening_choice_cancel` 5/5；Esc 与正常选择的问题 2、
  职业 roll 完全一致。初始可见余额 `10000` 经查明是固定随机表抽到「熊头」扣 10000，
  CE242 将负余额 clamp 到 0，再由 pc300 伙食费 `+10000`，不是漏执行；四职业 job roll
  实际不同（3539/8718）。另将 Windows 运行时图标拆为两层：
  `godot/window_icon.ico` 的大帧为 `icon_windows.png` 任务栏/Alt-Tab 图标，
  Godot GUI 启动后由 GDExtension 用 `icon_titlebar.png`（`inusuku.png` 的
  256×256 头部裁切，已收紧到脸/发/领口）设置高分辨率 `ICON_SMALL` 标题栏
  图标；F11 后会重发，避免 ICO 固定 16×16 帧的放大模糊。临时 `--export-pack`
  已确认两个图标资源进入 PCK（16 个运行文件）。

* **2026-11-18 开场第二问随机化**：`SampleMapA ev0` 固定两个选择点（职业问 +
  四场景抽一）；此前文档把 `问题2..问题5` 误写成连续五问。默认静态随机游标从 0
  开始，因此第二问恒为温泉；Godot 窗口入口现在在 `open()` 后、`boot()` 前调用
  `WolfGame.set_live_rng(true)`，CLI/headless/capture 仍保持确定性，
  `WOLF_LIVE_RNG=0` 可关闭。真实数据回归 `m25_live_rng` 16/16、
  `m27_opening_choice_cancel` 5/5，Godot smoke 全过。

* **2026-11-17 安装版准备（当前状态，未打包）**：`export_presets.cfg` 已补全
  `0.1.0.0`、产品名/文件描述、`Inusuku` 公司与版权；脚本从预设动态读取这些
  字段，避免 Godot 编辑器同步覆盖。新增 Inno Setup 模板与渲染器
  （`tools/package/ImoutoLife.iss.in`、`render_inno.py`）及多尺寸
  `tools/package/icon_windows.ico`；安装器固定简体中文，默认安装到
  `妹！生活 ～单色～ Godot` 文件夹，保留 `Data/Save`。打包脚本规划输出
  `Imouto Life setup.zip`（顶层同名文件夹）与 `Imouto Life setup.exe`，
  支持 `--no-setup` / `--iscc PATH`。Godot 默认把 exe 版本资源语言写成
  英语（美国，`0x0409`）；新增 `tools/package/windows_version_language.py`
  在导出后改为简体中文（`0x0804`），并重算 PE checksum。已在旧发行 exe
  副本上验证 Windows 显示“简体中文（中国大陆）”、脚本二次运行幂等、
  checksum 校验通过，内嵌 PCK 的 13 个运行文件仍完整（该时点尚无运行时窗口
  图标）。本机尚无
  `ISCC.exe`，因此只有准备，没有执行构建或生成新包。

* **2026-11-17 Godot Windows x64 发行包（当前状态）**：正式
  `work/out/dist/godot/0.1.0/Imouto Life.exe` 已导出，exe 图标来自
  `work/Data/icon_windows.png`。发行 Data 使用
  `tools/package/release-data.manifest` 精确白名单：746 个素材 +
  `Data/Save/System.sav`，共 747 文件 / 128,083,817 B；完整 `work/Data`
  中排除 618 文件 / 55,684,128 B（`MapChip`、`FIcon`、`BattleEffect`、
  `Fog_BackGround`、`SystemGraphic`、未注册地图和未引用资源）。导出器
  实际把 DLL 放根目录，但 GDExtension 清单按 `res://bin/wolf_gdext.dll`
  解析；脚本已重排为 `bin\wolf_gdext.dll` 并做 SHA-256 校验，
  `348aa5d3...`。PCK 只含 13 个运行文件，不含 addons/tests/图标/重复 DLL。
  包内 checksums 750 项通过；精简 Data 上 `smoke.gd` 为
  `pictures=4 sprites=4`，`save_roundtrip.gd` 新游戏/重载均 38 图，
  `System.sav` 哈希不变。Godot 4.7.2 模板已安装，旧的“模板缺失”状态作废。

* **2026-11-17 存档翻页残留文本收口（当前状态）**：`CE131` 先改页码、
  `CE94` 后重建四行图片，旧实现在这两帧按新页查槽失败后回退到上一页的
  `picture.text`，导致旧槽号、游玩时长和哥哥称号闪现。`save_slot_text_override()`
  现在先核对标签图片末端的当前槽位号；旧页标签未重建时整行三组文字一起隐藏，
  重建后恢复正常覆盖，空槽仍显示“没有数据”。新增
  `m25_save_slot::a_page_turn_never_shows_the_previous_pages_raw_text`，覆盖左右
  翻页并逐帧断言。`m25_save_slot` 17/17、`m3_save_ui_roundtrip` 10/10、
  `m25_cursor_follow` 1/1、`m3_title_mouse` 8/8、`m3_title_visibility` 4/4；
  `smoke-godot.sh` exit 0，最新 DLL SHA-256 为
  `9c9e32812cfe5ea371b560d571ab8de0d6bbef6c76561d7b965a901e87cde635`。

* **2026-11-17 全量审查 `2411996` 收口（当前状态）**：`F-01` 判定误报
  （`0x0010` 是间接目标标志，不是首行截取），只订正 `docs/OPCODE_122.md`；
  `F-02/F-03` 新增 Godot Windows Desktop 导出预设与 `tools/package-godot.sh`，
  导出排除 `godot_ai`/`tests`/`bin/~*`，`--export-pack` 已实跑验证；
  `F-04/F-12` 启动失败面板与 headless `quit(1)`、模态 F11 已落地；
  `F-05` 坏 checksum 只警告不拒载；`F-06` 两个发行脚本剔除全部本地编号存档，
  仅注入干净 `System.sav`；`F-08` 图片按钮回退收窄到 `5|21|22|28` 且只跳过
  `v100`；`F-09` 改 `BTreeMap::range`；`F-10` 返回标题清资源缓存。
  `F-07`/`F-11` 按用户决定暂缓。定向回归全过；全量测试在出厂存档副本上仅余
  长期基线（choice×3 / db×2 / textpic×1 / m18 1 / m3_manual_rules 1）与两条
  旧存档界面期望。Godot 关闭后已同步 `godot/bin/wolf_gdext.dll`
  （`ef6e9694...`），`smoke-godot.sh` exit 0、启动错误/F11 测试通过；本机仍无
  4.7.2 导出模板，最终 exe 未生成。另修开始新游戏标题闪回：`130 Teleport` 不再
  提前清负号层，Map003 自己用黑幕覆盖并擦除标题；新增 `m3_title_transition`，
  标题链回归全过，DLL 重建为 `bc6d931e...`，`smoke-godot.sh` exit 0。
  详见 `docs/AUDIT_2411996_FIX_REPORT.md`。

* **2026-11-17 `review_a2a618d_report.md` 收口（当前状态）**：报告前 6 项已核实
  落地；两项遗留已修。存档栏鼠标悬停现在把 CE94 的 `290 type 5` 闪烁从旧行迁移到
  `self[610]` 当前行，新增 `m25_save_slot` 回归；气泡正文在 `36013` 上增加
  `x+12/y+6` 内边距并让框体额外向上增长 10 px，三行文本四周留白有断言。
  `m25_save_slot` 14/14（跳过两条会临时写玩家存档的自动存档用例）、
  `m19_balloon_ui` 3/3、`m17_text_layer` 5/5、`m17_ui_regressions` 22/22、
  `m25_sister_body_rects` 3/3、`m25_sister_pose5` 4/4、`m25_return_to_title` 2/2、
  `m25_cursor_follow` 10/10；`cargo test --workspace --no-run` 通过；
  `build-godot.sh` 成功，`smoke-godot.sh` exit 0。玩家存档未改写。

* **2026-11-17 实机报告 5 项收口（当前状态）**：枕头 Ev 13 优先于睡姿
  Ev 12；恶作剧 `1109` 底框不再注册为姿势按钮；相册 Ev 35 的点击沿交还
  并行轮询页，宿主不再消费或停掉它；CE270 正文首帧即按头像文件采用
  107 px 气泡高度；CE94 存档栏重排为参考左栏
  `x=48, y=84+row*116, 636×112`，右侧 6 行注意事项框由 Godot 绘制，
  槽 1 标“自动存档”，左下仅游玩时长，右侧单行日/星期/时间/哥哥称号，
  渲染/鼠标/键盘光标共用 `save_grid_row_layout()`。`m25_save_slot` 15/15、
  `m25_sister_pose5` 4/4、`m17_ui_regressions` 22/22（跳过既有夜间夹具）、
  `m3_map_click` 8/8、`m21_cursor_hover` 7/7，`smoke-godot.sh` exit 0，
  DLL 已重建。默认 workspace 仍有 4 条既有字体度量失败
  （choice×3 / textpic×1），与本轮无关；玩家存档未回滚。

* **2026-11-16 实机复审收口（当前状态）**：按 `review_46de4eb_and_ux_bugs_report.md`
  与用户新截图继续收口。
  - **侧拉栏文字**：`CE238/CE239` 的 `321..325` / `2301..2319` 文本 `Move` 指令
    没有动画尾参，宿主只在 `owner_event == 238/239` 时用首参（20 帧）作为滑动时长，
    文字和底板同步；`m17_ui_regressions::side_panel_text_labels_slide_in_lockstep_with_the_drawer`
    通过。
  - **指针**：不再跟随 Sys74；白天、选项、气泡、存单格、相册/数据/设置等鼠标页面
    都显示引擎手型指针，仅前端弹窗让位给系统箭头；标题菜单保持箭头，**标题读档格
    显示手**。指针 z 提到 `UI_Z + 100`。`m25_cursor_follow` **10/10**。
  - **存单弹窗**：鼠标移动更新按钮高亮；关闭弹窗加 `_modal_release_guard`，物理
    键未全部松开前强制 `buttons=0` 并清 latch，避免“按下取消”在下一物理帧穿透成
    底层读档/覆盖保存；弹窗事件统一 `set_input_as_handled()`。`save_slot_modal.gd`
    覆盖悬停、按住取消不穿透、读档成功，并校验 `SaveData01` 字节不变。
  - **顶栏行动力条**：按姊妹作不满值特写改为 `165×14`、`[531,15,165,14]`；1 px
    纯白外框，当前值纯白，已消耗部分 `#646464`。文字与条墨迹均 `y=15..28`，
    中轴 `y=21.5`；数值仍右对齐 `x=750`。
  - **验证**：`cargo fmt --all --check` 干净；`m14_visual_regression` 5/5；
    `bash tools/smoke-godot.sh` exit 0（`pictures=4 sprites=4`）。用户实机存档已被
    覆盖为第 2 天 19:00，依赖出厂 `SaveData01` 的旧用例会漂移，**不得回滚玩家存档**。

* **实机报告 11 项全部收口（2026-11-15，当前状态）**：详见 `docs/LIVE_PLAY_FIX_REPORT.md`。
  - 核实结论：`live_play_issues_and_fixes_report.md` 的 11 项断言里 **7 项是宿主 bug**
    （#1 气泡闪脸、#2 对话框过高、#3 进度条残留、#5b 睡眠呼吸、#6 中文乱码、#7 顶栏行动力条、
    #8 转场渐变）、**3 项按用户裁定统一**（#4 光标回落、#5a BAD/GOOD 粗细统一为 8、#9 侧拉栏双向补间）、
    **1 项零售原样/报告误判**（#5a 原始读法）；报告引用的 9 张 `{GUID}.png`
    截图本机全部不存在，视觉证据不可复现。
  - **已落地**：#1 气泡模式全程屏蔽原生 `19500..=19503`；#2 气泡高 136→107、头像底 563→558
    （零售截图 1.5x 实测：气泡洗色逻辑 459.3..566.0）；#3 新增 `raid_cleanup`，夜袭场景结束的
    那一帧擦 `500..=503` 并清 `2000090/91/92/154`（`2000091/92` 全作无处归零）；
    #5b 同图重绘保留 `breath/zoom/pattern`，并行 CE237 不再每帧清零相位；
    #7 顶栏条改成几何判定（零售黑幕在 y=36，不遮顶栏）；#8 `150 Move` 的 fade 变成真正的
    alpha 斜坡（`fade_from/fade_start`）；E 宿主读 `GetLocalTime` + `--clock` 可钉住；
    F 读档路径补 `.mps` 后缀。
  - **#4 已按用户裁定改成回落（2026-11-15 晚）**：零售确实是"粘住"的——脚本自带
    的默认回落分支（`SampleMapA` Ev18 pc 42，写 `var121 = 0` → `CharaChip/hand3.png`）
    挡在最后一个探针 `1111` 后面，而正式夜袭流程把 `1111` 删掉了（Ev19 pc 66
    `150 [818, 1111, 0]`），`124` 于是回答 -1，链在最后一节断掉。宿主补上这条规则：
    新增 `crates/wolf-game/src/cursor_fallback.rs`——**身体部位图标只在指针停在热区上
    时有效**，否则回落成普通手掌；热区集合取 Ev18 自己探的 `1100..=1108` 与 `1111`；
    回落目标是零售自己的 `hand3`（`CURSOR_PLAIN_HAND = 0`），想换成报告写的
    `hand1`（握拳，`var121 = 2`）只改这一个常量。`GameHost::hover()` 的命中测试
    抽成自由函数 `hover_picture()`，宿主规则与脚本 `124` field 8 共用同一套判定。
    逃生口 `WOLF_CURSOR_FALLBACK_OFF`。`m21_cursor_hover` 4 → **7 条**回归。
  - **回归状态**：`cargo test -q --workspace --no-fail-fast`（绝对路径 `WOLF_DATA_ROOT`）
    **8 红，0 新增**（choice×3 / db×2 / textpic×1 / m18 `hidden_and_transparent...` /
    m3_manual_rules `late_night_bedtime...`，全是长期基线）；本轮新增回归 **32 条**
    （m19_balloon_ui 3、m19_picture_motion 14、m20_clock 3、m21_cursor_hover 4、
    m22_raid_cleanup 5、m23_map_path 1、m24_live_play_rulings 2）；
    `wolf-cli verify` **PASS 64 / 1 SKIP**；`m14` 的 `saveui` 基线随出厂存档归位由
    `576_221` 记到 `576_228`（真实渲染变化：`1a9fafe` 改了存档格面板锚点；夹具另加
    指纹守卫，画面结构数字未动）。
  - **文档订正（2026-11-15 晚）**：`m14` 那三个像素的成因改写为「真实渲染变化」
    （`1a9fafe` 改了存档格面板锚点），不再是「夹具漂移」；
    `docs/OPCODE_122.md` 按当前代码订正为 `mode & 0xFF00` / 分支 `0x0200`
    （`f52db44` 改的 `0xFFF0` / `0x0010` 已随 `b23a1e1` 回退），并在开头记了这条
    仍开放的差异；`docs/REVIEW_9a817e4_FIX_REPORT.md` 的状态横幅细化为逐条现状，
    §0 表格标「已回退」，§2 各节补「当前现状」，§4 标注数字是 `f52db44` 那轮的快照，
    §5 列出因回退重新开放的五项（Opcode 122 掩码 / `\img` 贴图分层 /
    动作键范围收窄 / `150 Move` 活跃槽位遍历 / Godot 回归脚本接入 smoke）。
  - **覆盖度独立复核**：只读代理逐条核对实机报告 11 项断言，全部有真实代码落点，
    32 条新增回归逐条对得上，无「只写在报告里」的情况。
  - 空间：删 `target/debug/incremental` 与 210 个 `.pdb`（2.4 GB），
    `target` 8.3 GB → **5.8 GB**，仓库合计 9.6 GB → **7.1 GB**
    （`work/Data` 176 MB、`work/out` 822 MB 未动）。
  - 实机环境：`godot/bin/wolf_gdext.dll` 已重建
    （SHA256 `80ccf7877af4166f66f14e0c16bffd797fe038cb2edd313bee8577f612eeac4f`，
    比所有 `.rs` 都新）；玩家存档备份在 `work/out/player_saves_2026-11-15/`，
    `work/Data/Save/` 已是出厂存档。

* **M25 实机 UX 四项收口（2026-11-15 深夜，当前状态）**：输入 `github_audit_rng_and_ux_report.md`
  + `ux方案.md`（外部只读产物），用户拍板顺序 1→5。详见 **`docs/M25_LIVE_UX.md`**。
  - **§二 光标（第二轮，2026-11-15 深夜改写）**：上一条结论**作废**——用户实机复核后
    指出「零售白天那张是明显和 hand3 一模一样」。重新取证：零售有**两个**指针。
    **白天的手型光标是系统指针**（Windows 手型光标位图 = `CharaChip/hand3.png` 第 0 格，
    热点 `(4, 1)`），可见性由**系统变量 74「マウスポインタ表示する？」**决定，全库只有
    `CE 224`（フィールド上処理，parallel，条件 `global[1] == 1`）在写（字段动作中写 0、
    结束写 1）；**Picture 2999 只管深夜悪作剧**（`SampleMapA` Ev 14「マウス追従」，
    条件 `var120 == 1`，图标由 Ev 18 按 `var121` 选）。零售存档佐证：`SaveData01`
    （第 1 天 19:30 周一）`var120 = 0`、`var121 = 0`，而同一时刻截图里有手。
    **落地（引擎侧）**：新增 `crates/wolf-game/src/pointer.rs`——引擎自己画系统指针
    （`CharaChip/hand3.png` 第 0 格，按热点把指尖放在鼠标上；后续用户复审改为
    所有鼠标页面显示，标题菜单除外、标题读档格显示），
    落在独立的单槽"屏幕" `Game::pointer`，**不进游戏图集**（脚本图片计数与存档不受影响）；
    脚本画了 2999 时引擎指针让位；前端 `GameView.gd` 在 2998/2999 在屏时隐藏系统箭头。
    回归 `m25_cursor_follow` **10 条**；`m14_visual_regression` 两个地图场景重录基线。
  - **§一 RNG（opt-in）**：`WOLF_LIVE_RNG=1` 时新档/读档的随机游标加时间基扰动；
    环境变量没设时**逐位等价**（回归基线不受影响）。回归 `m25_live_rng` 15 条。
  - **§三 站立立绘/睡姿热区（2026-11-16 订正）**：`CE240` 的 `900..903` 只是对话/
    统计页显示层，原版不作为点击目标；统计页置 `v176=1`，妹妹事件 1/2/3/4/12/25 都带
    `v176==0` 门控，对话则由消息/选项消费输入。宿主现在只要看到任一可见
    `Picture/stand_*` 就返回 `None`；普通卧室按 `ptr_sc` 截图量出的 6 个 1024×576
    全身矩形命中对应地图事件。alpha 命中与 16 px 地图兜底已删除。回归
    `m25_sister_pose5` 3 条 + `m25_sister_body_rects` 3 条。
  - **§四 存读档**：`Game::request_load(&Path)` 打通"`SaveRequest` 入队安全"（原字段
    private，两份文档都漏了；方案里的 `Path::new(path.to_string().as_str())` 编译不过）；
    **CE131 槽号算法实测钉死**：self `600` 模式(0 写/1 读)、`610` 行、`611` 页、
    `612` 绝对槽号、`613` 总页数、`626/627` 每页行/槽 ⇒ **绝对槽号 = `611*627+610+1`**，
    共 12 槽 3 页（第 1/2/3 页第三行写 `SaveData03/07/11`，已写盘实测）。
    **存单弹窗**：零售存档格单击即覆盖（误点毁档），本轮在 Godot `_input` 最顶部拦截，
    非空槽弹「保存到此槽 / 读取此存档 / 取消」，保存按钮**重放原点击**让游戏自己写。
    **返回标题入口**：自由地图 `Esc` → 自绘确认面板（是/否，默认"否"）；在存单/
    相册/数据等二级界面 `Esc` 继续作为运行时的取消别名，不叠返回标题框。
    **晚饭后槽 1 自动存档**：`CE258` 正常结束那帧写 `SaveData01`，**宿主开关
    `set_auto_save_slot`，默认关**；Godot 只在真窗口非 capture 会话打开。
  - **回归状态**：`cargo test -q --workspace --no-fail-fast` **与长期基线逐条一致、
    0 条新增**；本轮新增 **35 条**（m25_cursor_follow 4、m25_live_rng 15、
    m25_sister_pose5 4、m25_return_to_title 2、m25_save_slot 13）+ Godot 端到端
    `godot/tests/save_slot_modal.gd`（已接入 `tools/smoke-godot.sh`）；
    `cargo fmt --all --check` 干净；`wolf-cli verify` PASS 64 / 1 SKIP；
    `bash tools/smoke-godot.sh` exit 0。
* **T14 实机 UI/性能收口（2026-11-12 深夜，当前状态）**：最新冷构建下新游戏/读档
  第 `1/2/3/6/10` 帧均 `yellowish=0 / greenish=0`；读档 HUD 的 100x8 白色带框精力条
  在第 1 帧已实际绘制。相册图标纳入图片墨迹命中，侧栏关闭态命中扩到屏幕 `x=0`，
  动作子菜单中的结束箭头可窄范围绕过 ev21 的分页条件并启动确认脚本；混合 ADD/SUB/MUL
  批处理后的体力和 overlay 固定用 normal-blend 末尾批层。161 冻结帧只在 freeze
  时回读一次并复用纹理。600 帧读档 `ready=114.3ms / wolf_avg=0.536ms /
  draw_avg=0.315ms`，新游戏 `ready=110.1ms / wolf_avg=0.484ms / draw_avg=0.308ms`；
  `smoke-godot.sh` 全绿，`parity-godot.sh 600 --pixel-check=600` PASS（MAE 1.3852）。
  详见 `TASKS_REMAINING_BUGS.md` §0.1 与 `HANDOFF_PROGRESS.md` 同日 T14 条目。

* **T13 性能/UI 收口（2026-11-12，当前状态）**：
  - 玩法前端已完全移除地图瓦片桥接：`wolf-gdext` 与 `GameView.gd` 不再请求或绘制
    `tile_quads` / `tile_pixels` / `tile_revision` / `tile_tint`，只保留动态
    picture/text/HUD。核心 `Game::tile_quads()`、`Atlas` 合成与 CLI `capture --map`
    仍保留给取证/诊断。T12 的单纹理烘焙方案和 packet 字段只作历史记录，
    `t12_tile_bake*` 已删除；当前源码不包含 `Atlas::composite_tile_layer()`。
  - atlas 上传改为只发打包内容包围盒。旧实现的整页 4096² 上传为 **64 MiB/次**，
    现已移除；`m17_render_regressions` 当前包围盒示例为 2607x576 / **5.7 MiB**，
    19:07 读档 600 帧为 `sync_uploads=1` / `sync_MiB=4.1`、`wolf_avg_ms=0.443`、
    `draw_avg_ms=0.302`、`physics_avg_ms=0.752`（`work/out/t13_final_loadsave_600.log`）。
    该日志早于最后一轮气球对话补丁，只作性能路径证据。
  - 已修并有回归：黑色阴影人头（CE63 tone 填充零）、黄绿斑点/黄色地图背景
    （前端不再发 tile）、夜间首次提示点击消失、保存/相册/数据/结束图片矩形命中、
    夜间数据图标被结束按钮覆盖时隐藏、BAD 条负缩放、侧栏两个三角把手
    （状态 y≈118..157、物品 y≈260..297；关闭面板仅右侧 25px 在屏内，保存图标优先）、
    卧室内妹妹 900..903 可见矩形并集命中（2026-11-16 订正：站立立绘改为纯显示层，
    普通卧室按全身矩形命中）、身份-CG 分支。中央对话也已修：
    `36013` 使用消息正文行距并清理 `\ax/\ay` 前导，气球向上增长，三行落在
    493/516/539，气球可见时过滤原生 `19500/19501`；`m17_text_layer` 3 passed。
  - `m14_visual_regression` 当前 **5 passed**：saveui 的 101 像素差已归因为测试
    遗留的 `SaveData03.sav` 第四存档格。隔离只保留出货 `SaveData01/02` 时恢复
    25 live / 13 text pictures、non-black 576227；与基线 576221 只差 6 像素
    （光标/栅格相位）。已加 `depends_on_save_grid` fixture 守卫，未改基线。
    侧栏现在只响应 `try_side_panel_handle` 的两个三角把手区：状态
    `STATUS_HANDLE_Y=(118,157)`、物品 `ITEM_HANDLE_Y=(260,297)`；关闭面板仅右侧
    25px 在屏内，空白滑条（例如 y=192）不触发，保存图标等图片按钮优先；仍无
    按住拖拽手势。哥哥体力条只有 `精力 3/3` 与
    `行动力60/65` 文本证据（CE214），数据中无独立图形槽位；保存按钮没有独立
    hover 资源；BAD 外框厚度与人物 alpha 轮廓仍缺原版证据。`36014` 的
    `message` 字面量在原版实机图 `work/out/shot_metrics/full_89EF.png`（由 `prt sc/`
    的 1532×862 窗口截图缩放而来）中同样出现在名牌上，属零售行为；在确认不同说话人
    的名牌规则前**不按占位符隐藏**。连续同人翻页的瞬态闪烁仍需原版逐帧证据，未加 latch。
  - 旧编号必须分源：**历史台账 BUG-20/21 已闭环，22/23/24 非缺陷**；**报告 §六
    BUG-20/21/22/23/24 已全部闭环**。§六 BUG-21 于 2026-11-13 在 `install_map`
    中按 `MAP_SELF_BASE` 清扫无主地图协程（`COMMON_SELF_BASE` 不受影响），
    `m16_old_bug_review` 由此变为 4 passed / 0 ignored（`hist_bug20` / `hist_bug23`
    空范围 no-op / `hist_bug24` / `report_s6_bug21`）；旧台账 BUG-23 不应再写成
    “用户可见仍未修复”。
  - **最终 DLL 已重建并验收**：`godot/bin/wolf_gdext.dll` 为 20:09:05，
    7,651,840 字节，SHA-256 `fee3e727f7ad964a8ccd2b57aaf600d743c1405a2eb702eed5d41ea794efadd1`，
    与 `target/godot` 同哈希。最终 `smoke-godot.sh` 全绿，
    `parity-godot.sh 600 --pixel-check=0` PASS；读档 180 帧
    `wolf_avg_ms=0.565` / `draw_avg_ms=0.287`、黄/绿像素均为 0；新游戏
    300 帧三行正文 493/516/539 且无原生 `19500/19501`。若用户仍看到旧现象，
    必须先完全退出 Godot 编辑器/游戏进程再重开，Windows 不会热替换已加载 DLL。
  - **T12 补丁 + m14 收口（2026-11-13 续查）**：`Assets::alpha_bounds_in` 二级键缓存、
    `install_map` 的 `MAP_SELF_BASE` 清扫、`wolf-gdext` 选项双 clone 合并均已落地。
    `m14_visual_regression` 由 2 红转 **5 passed**：T18 `1a9fafe` 的 slot 230 行动力文本
    拆分只让两场景的 text picture/item/line 各 +1，像素基线 533187/554890 **未动**；
    T18 的稳定 `hover` 让 CE238/CE239 hide 页不再每帧重画，停靠侧栏从零售 0.2 alpha
    变成 1.0，已在 `game.rs` 用 `SIDE_PANEL_PARKED_ALPHA=0.2`（`x ≤ -300` 且无过渡）
    复原。细节见 `docs/HANDOFF_T12_PATCH_AND_LEDGER.md` §4.1。
* **审计修复轮（2026-11-13 晚，当前状态）**：`docs/imouto_life_rebuild_fixes_and_full_audit.md` 的 §一 6 项截图与 §二 P1/P2 已落地。选项 `(0,0)` 回退居中 + 控制码剥离；失活 `choices` 由 `frame`/`install_map` 自动回收（`m3_mouse_menu` 14 passed）；行动力条在黑屏开场不再误出，宿主条改 100×12 深灰槽 + 亮边（`HUD_ACTION_VALUE_X=716`）；`36002` 底边钳到 576，`m17_ui_regressions` 21 passed；`message` 名牌按原版实机图保留，连续同人翻页瞬态仍待原版逐帧证据。RNG 读档按 `playtime_frames` 定位表游标（`.sav` 无字段，同存档重放仍同）；Godot `audio_cache` 上限 64、`key_config_revision` 缓存、`WolfText` 段落缓存。m14 仍 **5 passed**（533187/554890），workspace 只余既有 `m3_manual_rules::late_night_bedtime...`；Godot 9 个 headless 脚本全绿。两轮报告见 `docs/AUDIT_REBUILD_FIX_REPORT.md`；代码提交 `b2b6998` 已 push `origin/master`。
* **Gemini 全量审查 `1c76dcc` 处理（2026-11-14，当前状态）**：`docs/Full Code Review 1c76dcc.md` 新 P1 成立并已修——`Game::text_quads` 现将 `balloon_frame_growth()` 提前计入 `TextQuadKey`，`36014` 人名牌在多行流式换行时随 `36008..=36012` 同步上移；新增 `a_streaming_balloon_lifts_the_nameplate_through_the_text_cache`（1 passed）。P3 行动力条按报告方案 2 右对齐：`HUD_ACTION_LABEL_X 560→545`、`HUD_ACTION_BAR [608,18,100,12]→[593,18,100,12]`、`HUD_ACTION_VALUE_X 716→750`，`GameView.gd` fallback 同步；新增三位数回归（1 passed），`m14_visual_regression` 仍 **5 passed**（533187/554890）。报告两条“待核对 `1a9fafe`”均已在当前代码闭环：`121` 不再对 `SelfVar` 强制 `batch_count=0`（`op121_self_range_updates_every_slot_in_the_range`），瞬时 `Move` 已清 `transition` 且 `move_cancels_an_erase_fade` 断言 `opacity==255`；`spawn_child` 也已继承 `is_parallel`。`125` 单协程同帧多次 `123` 只消费一次仍保留为已知边界项。额外发现 `m3_status_panel::ce238_relative_panel_lands_at_the_left_edge` 失败（面板停在 -305），本轮未触碰相对绘制路径，待单独排查。详见 `docs/GEMINI_REVIEW_1c76dcc_FIX_REPORT.md`。
* **实机截图四轮复核与 5 项视觉/交互缺陷闭环（2026-11-15，当前状态）**：
  1. **名牌右半边残留彻底消除**：`exec.rs` 为 `PictureAction::Move` 解码 `head & 0x0100_0000` 标志位的 `span`；`picture.rs` 实现范围批量移动（`lo..=hi`），CE270 执行 `150 Move 36008..36012` 时所有名牌组件同步淡出至 0 透明度，右半圆角（36010）残留彻底消失。
  2. **妹妹对话框加高 136px & 头像完整容纳**：按原版实机视觉效果（`ptr_sc/卧室_点击妹妹_首句话.png`），妹妹说话出现半身头像（36002）时，气泡对话框统一定位加高至 136px（`BALLOON_FACE_FRAME_MIN_HEIGHT = 136`，y=428..564）；头像底边统一定位在 `BALLOON_FACE_BOTTOM_Y = 563.0`（发顶在 y>=444，距名牌底边 434 留出 10px 清晰空隙），头像完整容纳于对话框内，不超出底边亦不被名牌遮挡。
  3. **警戒度等黑色实心格子对齐与消除叠影**：彻底移除 `message.rs` 和 `textpic.rs` 中的 `inline_box_glyph`，文本层不对 `\img` 生成字符；仅由 `Atlas::sprites_with_panel_rect_excluding` 渲染原版 19x20 PNG 精确贴图 quads，消除 Unicode 字符与贴图的双重叠印与字宽步进错位，格子完全对齐、无错位。
  4. **选项游标小框高度与包裹**：`choice.rs` 将游标框高度调整为 `(pitch + 1.0).max(font_px + 4.0)`（28.0px，行距 27.0px），顶部 Y 坐标设为 `row[1] - 2.0`；在选项文字上下各留出 2px 边距，文字上下笔画完整居中包裹，无任何笔划被截断。
  5. **恶作剧界面光标切换与按钮可点**：
     - 光标：`GameView.gd` 每帧监测，当 Picture 2999（手掌/注视/谈话等恶作剧光标）存在且可见时自动隐藏原生箭头（`Input.mouse_mode = Input.MOUSE_MODE_HIDDEN`），在光标销毁或窗口失焦时恢复 `MOUSE_MODE_VISIBLE`。
     - 按钮：`PICTURE_ACTION_CONTROLS` 补充 `(1109, 22, "Picture/pose_iconarea.png")`，`picture_action_event_at` 规范化 Windows 反斜杠路径，`Game::hover()` 补充 1109；在正常夜间互动下实机验证点击结束（1108）弹出确认选项 `["是", "否"]`，点击姿势（1110）弹出换姿势选项 `["是 ", "否 "]`，点击存档（-5）稳定唤起存档界面（CE14）。
  6. **验证**：`godot/tests/verify_ui_and_interaction_fixes.gd` 通过；`bash tools/smoke-godot.sh` 全套 100% 通过；`godot/bin/wolf_gdext.dll` 同步更新生效。
* **深度审查 BUG-25..BUG-48 修复完成（2026-11-12 封板快照）**：现行审查报告为 `docs/reviews/CODE_REVIEW_4ROUND.md`（第一至四轮），T0–T11 已全部落地。`cargo fmt --all -- --check` / `git diff --check` 通过，`cargo check -q --workspace` 0 error，默认 `cargo test -q --workspace` exit 0；真实数据 workspace 仅剩 2 项既有 `db` 姊妹作期望差异，AutoEvents 与标题历史差异已消除。`verify` PASS 64 / 1 SKIP，`precompile` PASS 19 / 0（blocks 5416 / loops 881 / implicit_closes 0）；`m14_visual_regression` 最终 **5 passed**：saveui 的 101 像素差已归因为 `SaveData03.sav` 第四格 fixture 漂移，隔离 01/02 两格后 25/13、576227（差 6 像素光标/栅格相位），已加 `depends_on_save_grid` 守卫且未改基线。CE43 改为标题菜单进入沿一次性触发，CE94 曾恢复 9280x1152 tenths 几何与真实 `<TRI-RIGHT>`，saveui 回到 13 text pictures / 54 glyphs / 27728 textured / atlas 21。Godot build/smoke 通过，parity 600 帧 PASS；m16 三组回归共 17 项真实数据全过。清理后 `du -sh .` = **8.1 GB**（work 796 M / target 7.3 G）。实施细节见 `docs/HANDOFF_DEEP_REVIEW_FIX.md`，任务收口见 `docs/TASKS_REMAINING_BUGS.md` §0。**当前工作区已撤销 tenths 渲染补偿；2026-11-13 复核后默认全量测试仅剩既有的 `m3_manual_rules::late_night_bedtime_skips_to_next_evening`，真实数据下另有两项既有 `db` 文本差异，以 §0.1 的最新实况为准。**

* **全量静态字节码深度审计沉淀与 5 项深水区系统缺陷归档（2026-11-11）**：编写并沉淀 `tools/audit_bytecode.py`，全量静态扫描 350 个 Common Event 与 8 张地图 102 个地图页面的 **63,506 条指令**，生成 `work/out/BYTECODE_AUDIT_REPORT.md`。审计引擎涵盖全量操作码覆盖、虚拟硬件状态差集、Picture 槽位主/并行协程竞争碰撞（定位 15 组交叉槽位）、循环无让步死循环风险、视口级演出特效等 5 大维度。新排查出 **BUG-20**（地图动态实体跟随气泡/图标坐标锚定缺失，`character_state` 字段 6/7 恒返回 None）、**BUG-21**（鼠标滚轮系统彻底瘫痪，`engine_state(10)` 滚轮移动量硬编码 0）、**BUG-22**（鼠标移出窗口检测失效，字段 11/12 走 `_ => None` 导致指针残留）、**BUG-23**（全屏闪烁与震动因无挂载 Picture 被抛弃）、**BUG-24**（按键连发延迟误绑定到 `sys(15/16)`）。已同步更新 `work/out/review/POST_DEEPSEEK_BUGS_INVESTIGATION_REPORT.md`，总缺陷台账扩充至 24 项，升级为五批次修复路线。消解各文档历史冲突：纠正 `docs/M3_EVENT_GRAPH.md` 的 `raw - 600_000` 错误公式为 `caller + (raw - 600_100)`；统一 BUG-02（人名牌）闭环口径（固定模式由 290 视口平移固定在 276,456 屏内，已由 op112 掩码剥离闭环并经 `m15` 验证，不依赖 `character_state`；消解与 BUG-20 的概念重叠）；统一 BUG-04 为 NOT-A-BUG。
* **POST_DEEPSEEK 审查 19 项修复完成（2026-11-11）**：18 项修复、BUG-04 判为原版设计。VM 补 `250` 字符串写库、`210/211` 600_100 相对事件、跨事件公共 Self（15M+100*ev+slot）、`121/122` 间接代入、`213` 未命中不再杀协程、`125` 单帧清零、`123` 鼠标边沿广播；存档网格鼠标槽位与同帧刷新、负槽命中盒、地图换页不强杀父事件、UI 按槽位排序、BGS 独立总线 + 同曲跳过、EndGame 退出、op102 外部点击。**BUG-02 已闭环**：根因是 `CE270 pc92` 的 `112` 操作数 `0x11186A05` 把字符串变量类型标志放在 bit 24，低 24 位 `0x00186A05 = 1_600_005` 才是 CSelf5；旧解码保留 bit 24 后每帧误判“消息变化”，反复清 `self56` 并隐藏名字牌。`eval_string_condition` 左右操作数统一 `raw & 0x00FF_FFFF` 后，图 `36014` 在消息期间持续可见。`tests/m15_balloon_name.rs` 要求连续 60 帧可见、文本含“妹妹”、矩形非空且完全在 1024×576 内、`warnings == 0`。固定模式 `2002` 的屏幕位置由 `290` kind 2 对 `36000..36015` 的 `(512,536)` 平移得到，`36014` 约在 `(276,456)`，不需要 `character_state`；**不要伪造角色坐标**。验证：默认 workspace exit 0；数据套件仅 7 个既有姊妹作差异；verify PASS 64/1 SKIP；precompile PASS 19/0；m14 5/5（title peak=8）；smoke-godot exit 0；parity 600 帧 PASS。**复核收尾补充**：`Screen::picture_rect` 对 CE131 等 window 图改为使用窗口盒而不是 18x18 皮肤，修复真实鼠标点击可见槽位仍落到第 1 槽的问题；新增 `m3_menu_screens` 槽位中心命中、`m3_hud_buttons` 连续开关菜单、`m3_event_page_switch` 阻塞事件清理三组回归。`dynamic_labels` 基线由 51 修正为实测 3。工作区清理后 `du -sh .` = 7.5 GB。
* **独立审查 17 项缺陷修复完成（2026-11-11）**：VM（op111 运算符掩码/位积、op121 溢出、op122 高级模式、op213 跳入/跳出循环上下文）、文本（`\cdb`/`\udb`/`\sdb` 展开 + numeric 回退、消息右边距 32 px）、图片（锚点 2..6、独立 X/Y 缩放与存档 `scale_y`、九宫格整体吸附）、输入（鼠标短按锁存、Enter 边沿、失焦首帧屏蔽）、存档（`mds1` 字符串、公共事件 Self 池、BGM）、Godot（跨平台字体、atlas 满时重打包）、parity（`--menu-only --prime`，600 帧 MAE **0.7529 PASS**）。CE63 空消息框、CE240/241 立绘、CE244 行动力等实机问题均已回归；测试对 Stateful 公共事件改为按需清空/播种 Self 池，`m3_visual_text` 的读档上下文改为真实 `prime_engine() → load_save()` 顺序。
* **Godot 迁移 P0 + P1 核心 + P2 输入/文字/长程 parity 完成（2026-11-10）**：新增 `crates/wolf-gdext`（GDExtension 混合桥，gdext 0.5.5 + `api-4-7`）与 `godot/` 工程；Godot 4.7.2 负责窗口/渲染/输入/音频，Rust 保留格式/VM/存档/游戏层。标题菜单与 Rust `title.png` 基线 **99.779% 像素完全一致**。**输入**：`WolfKeys.gd` 镜像 `play.rs` 的 scancode+100 表与 `App::bits()`，`key_map.gd` 97 项全过；`GameView` 用 `_input` 跟踪物理键并通过 `WolfGame.key_config()` 实时吃 Sys52/54/56 改键。**读档界面**：`load_menu.gd` 从标题菜单用真实 Down/Enter 进入 CE14→CE131，两次 Down 落到空槽 3（确认不加载），Up 两次 + Enter 加载 `SaveData01`，退回卧室 **50 picture / 14 text**，含 `220 SaveLoad: loaded`。**文字**：`WolfText.gd` 按 cosmic-text 基线 `round(y)+round(size*1.023193)` 与 FreeType ascent 差做逐字号 shift，四份 ±2px 黑字复刻 `\E`；新游戏 600 帧 **MAE 0.769→0.368、±8 99.28→99.45%**，零售读档 **0.888→0.423**，消息 300 帧 **2.191→0.594、±8 98.48→99.14%**；标题不变，文字 rect 外零回归。**长程 parity**：`tools/parity-godot.sh` 在 600/1200/1800 帧逐项等于 Rust（16,038/43,938/71,838 指令；4,526/14,726/24,926 picture；15 message/3 choice/0 warning/3 sound），600 帧像素 MAE 0.3680。**冻结过渡审计**：161/162 只在未注册的 `SampleMapB.mps`（PlayerTouch 示例）出现，正式 5 张图没有，故本作不可达；实现与单测保留。**存档闭环**（同日已修）：`savegame::part1_from_map` 在模板 Part1 为空时写地图快照与 35 个对象，静态字段与零售 SaveData01 零差异，新游戏 save→load→resume 恢复 SampleMapA。**P2 补丁（同日）**：标题 CE43 是单次渲染器，光标变化时 `AutoEvents::restart(43)` 重放，深色 `menu*_a` 跟随方向键/滚轮/悬停；`Game::apply_wheel` 让 op102 选项直接移光标、CE131 存档网格滚轮=左右页键、其它 123 菜单=上下；`GameView` 用 `_input` 锁存鼠标按下/坐标，快速点击与右键不再丢；`--capture` 冻结物理帧；Godot 全局字体 fallback 实测会把文字度量改坏（600 帧 MAE 0.368→3.11）已回退，21,009 个静态字符只缺 5 个私用区/乱码码点。新增 `m6_title_wheel.rs`、`mouse_latch.gd`、`title_wheel.gd`、`gameview_title_wheel.gd`。**陷阱**：玩家保存会覆盖 `work/Data/Save/SaveData01/02.sav`，已备份到 `work/out/player_saves_2026-11-10/` 并按 50-picture 出货状态恢复；`m14_visual_regression` 增加 `depends_on_save` 守卫。**仍缺**：游戏内存档点（`SampleMapA ev5` 调 CE14）的脚本化写槽验证、weight 400 字重对照、真缺字时的逐字形 fallback、Part1 运行态字段、导出打包。排查流程见 `docs/GODOT_DEBUGGING.md`，迁移细节见 `docs/GODOT_MIGRATION.md` §4–6。
* 里程碑 **M0–M7 全部完成并推送**。
* **C 任务**（原版 Game.exe 静态逆向，Ghidra 12.2 + JDK 25）已完成，结论见
  `docs/ENGINE_BEHAVIOR.md` §3.2、`docs/RE_GAME_EXE.md` 与 `docs/re/*.md`；
  其中可落地部分**已改到 crates/**（提交 4ac380d）。
* 验证基线：`cargo test -q --workspace` **exit 0**；本作数据套件
  `WOLF_DATA_ROOT=$PWD/work/Data cargo test -q --workspace --no-fail-fast` 仅 7 个
  既有姊妹作期望差异（auto_events 3、db 2、game title 2）；
  `wolf-cli verify` **PASS 64 / 1 SKIP**（dxarchive.header）。
* 2026-11-03：opcode 102 的空可选行动不再画成 `0` 行（CE245 夜菜单 5 行、CE248 游戏菜单 4 行）；
  `cargo test -q -p wolf-cli --test m14_visual_regression` 5 passed，日命令基线已按 5 行重录。
* 2026-11-03：HUD/普通 text picture 改用 `Game.dat` 的 Bold face（cosmic-text 请求 400 时会退到 Segoe UI Symbol，数字窄 16%）；`19:30` 墨迹宽度 53→63 与实机参考一致，并补 4px 垂直基线偏移；存档 tenths UI 标签仍用 regular 400。`cargo test -q --workspace` exit 0，视觉回归 5 passed。
* 2026-11-03：普通像素 HUD 文本的 ASCII 空格按 **0.5 em** 度量（原版混合字体/字距的事实规则），其余字形仍用 msyhbd 实际 advance；右上 `同居 1天` 整块由 x≈952.6 左移到 943.3，line2 宽 47.3→56.7（参考≈57），`19:30` 不变。capture 文本 quad 按空格拆成独立 span，单测里的空格式期望已改为忽略空白比较。`cargo test -q --workspace` exit 0，视觉回归 5 passed，verify PASS 64/1 SKIP。
* 2026-11-03：新增可双击游玩发布包 `crates/wolf-launcher` + `tools/package-playable.sh`；安装到 `D:\program\Imouto Life`（`Imouto Life.exe` + `runtime\wolf-cli.exe` + 全量 `Data\`，188 MB），zip 153 MB 在 `work/out/dist/Imouto Life-0.1.0-playable.zip`。包内 release `wolf-cli verify` PASS 64/1 SKIP，`capture --menu-only` 1024x576 渲染成功。 `cargo test -q --workspace` exit 0。清理：删除 `work/out/zipcheck`、`work/out/launcher_probe`、`target/debug/incremental`、`target/release`；当前 `du -sh .` = 5.6 GB。
* **真机 GPU play 路径已验证**（2026-11-02，RTX 5060 Laptop / Vulkan / 1024x576）：
  boot 600 帧、load-save 900 帧、event 245 600 帧、menu-only 600 帧，四个入口全部
  **exit 0 / 0 warning**；标题画面离屏 capture 正确。
* 工作区 `du -sh .` = **7.5 GB**（2026-11-11 复核收尾清理后：work 334 M，其中 `work/Data` 176 M、`work/out` 159 M；target 7.1 G = debug 6.2 G（Rust CLI/测试全量）+ `target/godot` 894 M；`target/debug/incremental`、`target/release`、`target/ver6`、`work/out/dllprobe` 已清，未跟踪 probe/dump 已清）。Godot 运行时只编 `wolf-gdext`（不含 wgpu/winit），旧 debug 栈是 Rust CLI/测试所需；P3 下线旧前端后可清。
* 2026-11-03 工作区 `du -sh .` 为 **5.6 GB**（当时 target 4.1 G；release/incremental 已清；work 1.5 G = Data 176 M + work/out 1.3 G；发布包在 `D:\program\Imouto Life` 188 M）。该数字仅作历史对照。

### 11.2 最近三轮摘要

| 时间 | 内容 | 提交 |
|---|---|---|
| 2026-11-14 | 实机排查三轮：开场空槽/19:00 卧室背景/连续同人名牌/随机事件时间种子/夜间部位与姿势点击/格子条全面闭环 | 本提交 |
| 2026-11-14 | 实机截图二轮复核：开场空槽、茶摊乱码、格子条基础映射 | beb9693 / e5b4d61 |
| 2026-11-14 | 代码审查修复：Gemini 审查 1c76dcc 闭环，行动力条拆分重构 | 112ed76 |


### 11.3 仍开放的事项

* 气泡消息/人名牌已闭环（2026-11-11），不再列为开放事项；根因、修复与几何结论见 §11.1。
* 打字机速度（原版约 2× 当前实现）——`Sys9→p+0x80` 写入点未定位，本作 CE48 速度 500 ≈ 瞬显，暂不改。
* 选择面板宽度加数属 **B 级**：89EF 实测 156.3 = 140+16 精确吻合，EE37 多 5.3 px 未解释。
* `kind≥0` 掩膜过渡、`window.rs` 极小盒角折半——本作不触发，明确不实现。
* 存档/读档界面（CE94/CE131）的十分之一单位几何是 2026-11-02 的历史修复记录；当前工作区已删除 `Screen::ui_scale_for`、`TENTHS_UI`/`tenths_block` 与渲染二次 `/10`，不应再把该补偿当作现行实现。历史测量见 docs/re/SCREENSHOT_METRICS.md §6；**注意**：`work/Data/Save/SaveData01.sav` 曾被玩家在存档界面覆盖为含 94 张存档界面图的版本，依赖它精确像素数的测试已改为自洽断言或按「非干净 HUD 存档」跳过。设置界面（CE95）的 tenths 描述同样是历史依据，当前文本样式由 `Game::uses_regular_ui_text` 处理。
* `m14_visual_regression` 已于 2026-11-13 收口为 5 passed（停靠侧栏 alpha 回归已修复、
  行动力拆分只重钉文本计数），详见 §11.1 末条与 `docs/HANDOFF_T12_PATCH_AND_LEDGER.md` §4.1。
