# M3-P 全数据字符串解码审计与回归

任务：task-22（owner ver6）。交付物：
- 测试：`crates/wolf-format/tests/m3_string_decode.rs`（4 个用例）
- 本文档：`docs/M3_STRING_DECODE.md`

本作是汉化版：绝大多数显示文本被替换成 GBK 字节，而引擎/模板文本仍是 CP932。所有 `t_str` 都经过
`wolf_format::bytes::decode_wolf_str` 的 UTF-8 / CP932 / GBK 候选打分解码（M4 补：GBK「强壮」
字节 `C7 BF D7 B3` 也恰好是合法 UTF-8，旧实现无条件先选 UTF-8 会解成 U+01FF/U+05F3；现在
按 CJK/kana 加权与 UTF-8 字节奖励综合选分最高者）。本任务把全部字符串容器解析一遍，
统计可疑串，钉住若干正确的中文串，并把 CE250 / CE257 的乱码定性为**源数据损坏**而非解码器缺陷。

## 运行

```bash
cd '/e/Study/github program/Imouto Life' && source tools/env.sh >/dev/null 2>&1
WOLF_DATA_ROOT=work/Data cargo test -q -p wolf-format --test m3_string_decode -- --nocapture
```

结果（有 `work/Data`）：

```
running 4 tests
...  string audit: 82485 strings across 456 files, U+FFFD=1, control=0, halfwidth+CJK=804, empty=50938
test result: ok. 3 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out
```

数据缺失时 `have_data()` 返回 false，用例 `eprintln!("skipping: ...")` 后 `return`，默认 `cargo test` 仍 exit 0。

## 审计范围与方法

解析全部含字符串的容器（`work/Data`）：

| 容器 | 解析 API | 采集字段 |
|---|---|---|
| `BasicData/CommonEvent.dat` | `commonevent::CommonEventData::parse` | title / memo / arg_names / default strings / self 变量名 / return_name / 每个指令 strings |
| `BasicData/DataBase.dat` + `DataBase.project` | `database::Database::parse` + `apply_project_names` | 类型名 / 字段名 / 行名 / 行字符串 |
| `BasicData/CDataBase.dat` + `CDataBase.project` | 同上 | 同上 |
| `BasicData/SysDatabase.dat` + `SysDatabase.project` | `sysdatabase::SysDatabase::parse` + `apply_project_names` | 类型名 / 字段名 / 行名 / 行字符串 |
| `BasicData/Game.dat` | `gamedat::GameDat::parse` | `strings` |
| `MapData/*.mps`（8 张） | `mps::Map::parse` | 地图名 / 事件名 / 每个指令 strings |

统计口径：`456 files` = 456 个来源标签（350 个 `CE <id>` + 各数据库类型标签 + `Game.dat` + 8 张地图）。

## 结果汇总

| 类别 | 数量 | 判定 |
|---|---|---|
| 总字符串 | 82485 | — |
| 含 U+FFFD（替换字符） | **1** | CE257 红茶项，**数据损坏**，allowlist |
| 含控制字符（<0x20，排除 `\\n \\r \\t`） | 0 | 干净 |
| 半角片假名 + CJK 汉字共存 | 804 | **全部为正常日文半角片假名 UI 标签**，非缺陷（见下） |
| 空串 | 50938 | 正常（self 变量名等空占位） |

### U+FFFD：唯一一处 = CE257 红茶项（已知数据缺陷）

见「真实缺陷」小节。测试里以 allowlist 精确匹配（`file=="CE 257" && field=="command_string" && text.contains("红茶")`），
并断言全数据集**仅有这 1 条** U+FFFD，allowlist 之外出现任何替换字符即失败。

### 半角片假名 + CJK 共存（804 条）：不是缺陷

该分类只是「字符串同时含半角片假名与汉字」，在本作是**正常的日文 UI 缩写**（引擎/模板文本用半角片假名压宽度），例如：

```
CE 4  default_strings      ｽﾃｰﾀｽ状態消去
CE 4  command_string       X[移]一時ｽﾃ計算<初期化>
CE 7  memo                 能力値を増減します。…ﾏｲﾅｽを指定。戦闘中も有効。
CE 9  command_string       セルフ15にキャラ番号を入れる、いればｽﾃ異常を付与・消去
CE 14 arg_names            呼び出すﾒﾆｭｰ
CE 17 command_string       X[共]ｱｲﾃﾑ所持数取得
CE 31 command_string       X[戦]ﾀﾞﾒｰｼﾞ・回復ﾎﾟｯﾌﾟｱｯﾌﾟ
```

抽查前 50 条全部为正常日文（`ｽﾃｰﾀｽ` / `ｽﾛｯﾄ` / `ﾒﾆｭｰ` / `ｱｲﾃﾑ` 等半角片假名 + 汉字），没有一条是「中文被当 CP932 读」的乱码。
与 m3-fixer 的全 event 扫描结论一致：`gb_bad && !cp_bad` 共 138 条，其中 136+ 是正常日文 CP932，
只有极少数汉化补丁坏字节才是乱码。

## 真实缺陷（源数据损坏，非 decode_wolf_str bug）

两个缺陷同型：汉化补丁把中文写成 GBK 后，**多出一个孤立的 0xA1**（相邻 `0xA1` 共**奇数**个）。
GBK 把 `0xA1 0xA1` 两两配成全角空格，落单的 `0xA1` 的 trail 变成后面的 `0x20`（空格），
这是非法 GBK trail，严格 GBK 解码失败；随后启发式回退 CP932，把 `0xA1..=0xDF` 当半角片假名 → 乱码。

### CE250「ネットショップ」第一商品名（ダンベル 哑铃）

```
raw (30B) = d1c6c1e5 a1a1a1a1a1a1a1 20×11 32303030 83d2 20
            = 「哑铃」(GBK d1c6 c1e5) + 7×0xA1（奇数） + 11 个空格 + "20000" + 83d2 + 空格
utf-8      = 失败
gbk        = 失败（0xA1 的 trail 是 0x20，非法）
cp932      = 「ﾑﾆﾁ蝪…」半角片假名乱码
decode_wolf_str = "ﾑﾆﾁ蝪｡｡｡｡｡｡           20000υ "
```

对照：CE259「平日メニュー」同商品，`d1c6c1e5 a1×8`（**偶数**）→ 正确解出 `"哑铃　　…20000円"`。
即同一串只要 0xA1 个数为偶数就正常，**根因就是那一个多余的 0xA1**。

CE250 的其它选项（安全套 / 跳蛋 / 春药）字节干净，解码正常。

### CE257 红茶项

```
raw (18B) = baecb2e8 a1a1a1a1a1a1a1 20 32303030 83d2
            = 「红茶」(GBK baec b2e8) + 7×0xA1（奇数） + 空格 + "2000" + 83d2
utf-8      = 失败
gbk        = 失败（奇数 0xA1）
cp932      = 失败
decode_wolf_str = "红茶　　　� 2000円"   （含 1 个 U+FFFD）
```

同型数据损坏，落成替换字符。测试 allowlist 的正是这一条。

### 修复建议

- **修数据，不改解码器**：把奇数个 `0xA1` 改为偶数（删掉多余那一个或补一个），CE250/CE257 即可正常显示。
- 不要为这两条把 `decode_wolf_str` 的「GBK 优先」偏好改强：正如 m3-fixer 实测，`gb_bad && !cp_bad` 的 138 条里
  136+ 是正常日文 CP932，强改偏好会砸掉大量日文 UI（`対象戦闘ｽﾛｯﾄ` / `ｽﾃｰﾀｽ状態` / `[ﾒﾆｭｰ]技能` 等）。

## 测试用例一览（`crates/wolf-format/tests/m3_string_decode.rs`）

1. `every_container_parses_without_replacement_characters` — 解析全部容器；断言 U+FFFD 仅限 CE257 红茶 allowlist（且恰 1 条）；打印统计与样本。
2. `known_chinese_strings_decode_stably` — 核心中文锚点（行动力 / 持有金钱 等）存在；`decode_wolf_str` 对固定 GBK 字节稳定得「看一眼网上商店吧。」。
3. `ce250_first_item_name_is_a_data_defect` — CE250 首项 7×0xA1 奇数、UTF-8 失败、严格 GBK 拒绝、回退半角片假名乱码、不含「哑铃」；CE259 偶数版解码正确以锁死根因；CE257 红茶同型且落 U+FFFD。
4. `ce250_first_item_name_ideally_reads_dumbbell` — `#[ignore]`：若将来修好数据（去掉多余 0xA1），首项应读「哑铃」。

## 与 m3-fixer 定性的一致性

本报告与 m3-fixer（m00532）结论完全一致：CE250 乱码 = 源数据损坏；`bytes.rs` 的 `gb_bad && !cp_bad → 取 CP932` 早退
分支对正常日文是正确的，不应改成偏好 GBK。本任务只加测试与文档，**未改任何 `src`**。

---

## 2026-11-15 追加：半角表意标点否决（中文乱码修复）

### 问题

实机仍能看到中文乱码，例如 CE295 pc53 的 `\E哦｡ｭｸ遑｢ｸ邵遑ｭ｣｡｣ｿ`（应读作「欸…哥、哥哥…！？」）与
SampleMapA ev17 pc388 的 `\E欸…？哥…哥…？我…为什么…？`。根因在上面的「半角片假名 + CJK 共存」启发式：
汉化补丁把 `…` 写成 `A1 AD`、`？` 写成 `A3 BF`，而 CP932 把 `A1..A4` 读成半角表意标点
`｡ ｢ ｣ ､`（U+FF61..U+FF64）。中文对白只要含省略号或问号，CP932 读法就会同时满足
「像日文 + 含半角片假名 + cp932/gbk 各有一个汉字对」，于是被强行按 CP932 读，输出半角片假名噪声。

### 修法：否决而不是删除启发式

**不能直接删掉启发式**。本条启发式当前决定 1,113 处 / 110 个 unique 串的读法，其中 98 条是
**wolf 引擎通用的日文标签**（`[ｽﾃｰﾀｽ]HP名称` / `基本ｼｽﾃﾑ用変数` / `顔画像 [ﾊﾞﾄﾙ･ｽﾃｰﾀｽ用]` 等）——
它们不是本作画面上的日文正文，而是引擎自带的**数据库列名**，0 条落在 op101/102/文本图，
却是 **op250 的数据库 label**：`crates/wolf-game/src/db.rs:877` 的
`resolve_labels()` 拿它们去 `.project` 名称表查真实索引。删掉启发式会让 286 处 op250 寻址读到别的格子
（例如 `基本ｼｽﾃﾑ用変数` 的真实目标是 CDataBase type 18，而不是数字操作数 20/21），HUD 与战斗数值会错位。

采用**最小否决**：保留启发式，但当 CP932 读法里出现 U+FF61..U+FF64 时不走它——这些引擎通用标签不会出现这四个
半角表意标点，而它们的出现恰恰是「payload 其实是 GBK」的指纹。

### 否决范围的上界

上界必须停在 **U+FF64**。再放宽一个码位就会命中 U+FF65（半角中点 `･`），而零售数据里的
`顔画像 [ﾊﾞﾄﾙ･ｽﾃｰﾀｽ用]` 确实含它——该 label 有 4 处 op250 寻址，一旦翻转会指向错误的列。

### 实测（`work/out/probe_heur/`，79,582 payload 全语料）

| 否决范围 | 改变的串 | 其中是 op250 label |
|---|---|---|
| **FF61..FF64（采用）** | 21 处 / 12 unique | **0** ✅ |
| FF61..FF65 | 26 处 | 4 ❌（砸 `顔画像 [ﾊﾞﾄﾙ･ｽﾃｰﾀｽ用]`） |
| 整段删除 | 1,113 处 / 110 unique | 1,007 ❌ |

本仓实现与建议方案的预期逐行比对：**1,383 行里 1,362 行一致，21 行不同 —— 21 行全部是「修复」，0 行回归**。
修复内容为 16 条中文对白（欸…哥、哥哥…！？ / 欸…为什么哥哥拿着我的内裤…？ / 欸…？哥…哥…？我…为什么…？ 等）
与 5 条汉化补丁漏改的日文（`以下フェラ処理です` / `見せつけオナニーに変化します` / `ちくび愛撫`）。

### 测试

`crates/wolf-format/tests/wolf_str_decode.rs` 新增 4 条：中文省略号 / 中文问号 / 汉化残留日文 /
含 U+FF65 的 op250 label 保持 CP932（`顔画像 [ﾊﾞﾄﾙ･ｽﾃｰﾀｽ用]`）。
