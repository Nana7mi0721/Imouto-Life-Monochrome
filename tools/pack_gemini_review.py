#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tools/pack_gemini_review.py — 生成云端 Gemini 只读审查包（单包 ≤ 16 MB）

与 tools/pack_review_bundle.py（云端沙箱构建包）的区别：
  * 沙箱包目标是"能离线编译运行"，因此要带 work/Data 与离线依赖树（上百 MB）；
  * 本脚本目标是"给 Gemini 做只读代码审查"，因此带**完整代码** + 交接文档 +
    新改动补丁 + 字节码数据转储 + 原版/重构截图，不带游戏数据本体与依赖树。

产物（默认 work/out/gemini_upload_<日期>/）：
  00_REVIEW_BRIEF.md        审查说明（本轮范围、关注点、包清单）
  00_README_UPLOAD.md      上传指引（中文）
  01_source_code.zip       crates/ 全量 + 工程根文件
  02_godot_frontend.zip    Godot 工程（scripts/tests/project.godot/main.tscn/gdextension）
  03_docs.zip              docs/ 全量（去掉本地私有目录）
  04_tools.zip             tools/ 脚本（不含 debug/ 与外部二进制）
  05_new_changes.zip       自上一轮 Gemini 审查（1c76dcc）以来的补丁与提交
  06_review_reports.zip    既有审查报告与缺陷台账
  07_bytecode_dumps.zip    全量字节码转储（CE / Map / Opcode 分类）
  08..09_retail_*.zip      原版实机截图（按体积切分）
  10_issue_screenshots.zip 本轮重构问题截图
  SHA256SUMS.txt           每个包的 sha256

用法：
  python -I tools/pack_gemini_review.py
  python -I tools/pack_gemini_review.py --out work/out/gemini_upload_2026-11-15
"""

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile
import zlib
from datetime import date

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# 上传通道单文件上限 16 MB。留 1 MB 余量给协议层，切分组按 15 MB 封顶。
HARD_LIMIT = 16 * 1024 * 1024
GROUP_LIMIT = 15 * 1024 * 1024

# 上一轮 Gemini 审查所对应的提交。新的审查从它之后开始。
LAST_GEMINI_REVIEW = "1c76dcc"

EXCLUDE_DIR_NAMES = {
    ".git", "target", ".godot", ".recon", "_wolfref", "node_modules",
    ".import", "__pycache__", ".pytest_cache", "dist", "build",
    "debug",  # tools/debug 是本地调试产物
}
EXCLUDE_FILE_EXTS = {
    ".dll", ".exe", ".pdb", ".o", ".a", ".rlib", ".pyc", ".so", ".dylib",
    ".zip",
}
EXCLUDE_FILE_NAMES = {
    "相关链接.txt",       # 本地私有链接表（.gitignore）
    ".rustc_info.json",
    "wolf_gdext.dll",
}
EXCLUDE_REL_PATHS = {
    "docs/wiki文档",      # 本地私有攻略素材（.gitignore）
    "tools/bin",
    "tools/cmake",
    "tools/ffmpeg",
    "godot/addons",       # 第三方 Godot AI MCP 插件，非游戏代码
    "godot/.godot",
    "godot/bin/wolf_gdext.dll",
}


def log(msg):
    print(msg, flush=True)


def run_git(args):
    result = subprocess.run(
        ["git"] + args, cwd=REPO_ROOT, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )
    if result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {result.stderr[:400]}")
    return result.stdout


def is_excluded(rel):
    rel = rel.replace("\\", "/")
    parts = rel.split("/")
    for part in parts[:-1]:
        if part in EXCLUDE_DIR_NAMES:
            return True
    for skip in EXCLUDE_REL_PATHS:
        if rel == skip or rel.startswith(skip + "/"):
            return True
    name = parts[-1]
    if name in EXCLUDE_FILE_NAMES:
        return True
    if os.path.splitext(name)[1].lower() in EXCLUDE_FILE_EXTS:
        return True
    return False


def walk_files(rel_dir):
    """列出仓库内某个目录下的全部文件，返回 [(绝对路径, 归档内路径)]。"""
    base = os.path.join(REPO_ROOT, rel_dir.replace("/", os.sep))
    if not os.path.isdir(base):
        log(f"  [skip] missing dir: {rel_dir}")
        return []
    out = []
    for root, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDE_DIR_NAMES)
        for name in sorted(files):
            full = os.path.join(root, name)
            rel = os.path.relpath(full, REPO_ROOT).replace("\\", "/")
            if is_excluded(rel):
                continue
            out.append((full, rel))
    return out


def existing_files(rel_paths):
    out = []
    for rel in rel_paths:
        full = os.path.join(REPO_ROOT, rel.replace("/", os.sep))
        if os.path.isfile(full):
            out.append((full, rel))
        else:
            log(f"  [skip] missing file: {rel}")
    return out


def write_zip(out_path, items, note=None):
    """写一个 zip。items 为 [(绝对路径, 归档内路径)]。"""
    seen = set()
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        if note:
            zf.writestr("00_PACKAGE_NOTE.txt", note)
        for full, rel in items:
            if rel in seen:
                continue
            seen.add(rel)
            zf.write(full, arcname=rel)
    return os.path.getsize(out_path)


def zip_estimate(path):
    """估算单个文件在 zip(deflate, level 6) 里的压缩后体积。"""
    compressor = zlib.compressobj(6, zlib.DEFLATED, -15)
    total = 0
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            total += len(compressor.compress(chunk))
    total += len(compressor.flush())
    return total


def split_into_groups(items, limit, label):
    """把文件按压缩后体积贪心切成若干组，每组不超过 limit。"""
    groups = []
    current = []
    current_size = 0
    for full, rel in items:
        size = zip_estimate(full)
        if current and current_size + size + 4096 > limit:
            groups.append(current)
            current = []
            current_size = 0
        current.append((full, rel))
        current_size += size + 4096
    if current:
        groups.append(current)
    log(f"  {label}: {len(items)} file(s) -> {len(groups)} group(s)")
    return groups


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def clear_dir(path):
    if os.path.isdir(path):
        shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path, exist_ok=True)


# --- 各包的内容定义 ------------------------------------------------------

TOP_FILES = [
    "Cargo.toml",
    "Cargo.lock",
    "rust-toolchain.toml",
    "AGENTS.md",
    "README.md",
    ".gitignore",
]

REVIEW_REPORT_FILES = [
    "work/out/review/COMPREHENSIVE_CODE_REVIEW_REPORT.md",
    "work/out/review/GAMEPLAY_BUG_REVIEW_REPORT.md",
    "work/out/review/GAMEPLAY_BUG_REVIEW_CHECKLIST.md",
    "work/out/review/POST_DEEPSEEK_BUGS_INVESTIGATION_REPORT.md",
    "work/out/review/POST_DEEPSEEK_FIX_AUDIT.md",
    "work/out/BYTECODE_AUDIT_REPORT.md",
    "work/out/T12_PERF_AUDIT.md",
    "work/out/T13_INTERACTION_UI_AUDIT.md",
    "work/out/T13_SCREENSHOT_TRIAGE.md",
    "work/out/T17_GEMINI_REPORT_AUDIT.md",
    "work/out/T17_NAMEPLATE_ROOTCAUSE.md",
    "work/out/T18_HANDOFF_NEXT_SESSION.md",
    "work/out/T18_INTERACTION_AUDIT.md",
    "work/out/T18_PERF_RENDER_AUDIT.md",
    "docs/Full Code Review 1c76dcc.md",
    "docs/code_review_cb5ecb4_141c524.md",
]

BYTECODE_DUMP_FILES = [
    "work/out/_ce_full.json",
    "work/out/map_full.json",
    "work/out/_op111_classify.json",
    "work/out/ce_condition_matrix.tsv",
]


def build_new_changes(out_dir):
    """把上一轮 Gemini 审查之后的改动做成一个补丁包。"""
    items = []
    diff = run_git(["diff", f"{LAST_GEMINI_REVIEW}..HEAD"])
    stat = run_git(["diff", "--stat", f"{LAST_GEMINI_REVIEW}..HEAD"])
    log_text = run_git([
        "log", "--no-color", "--date=short",
        "--pretty=format:%h %ad %s", f"{LAST_GEMINI_REVIEW}..HEAD",
    ])
    name_status = run_git([
        "diff", "--name-status", f"{LAST_GEMINI_REVIEW}..HEAD",
    ])

    staging = os.path.join(out_dir, "_new_changes_staging")
    clear_dir(staging)
    for name, text in (
        ("CHANGES_since_%s.patch" % LAST_GEMINI_REVIEW, diff),
        ("CHANGES_since_%s.stat" % LAST_GEMINI_REVIEW, stat),
        ("COMMITS_since_%s.txt" % LAST_GEMINI_REVIEW, log_text + "\n"),
        ("FILES_since_%s.txt" % LAST_GEMINI_REVIEW, name_status),
    ):
        with open(os.path.join(staging, name), "w", encoding="utf-8",
                  newline="\n") as handle:
            handle.write(text)
        items.append((os.path.join(staging, name), name))

    # 工作区里尚未入库的新增文件（探针等）。
    untracked = run_git(["ls-files", "--others", "--exclude-standard"]).splitlines()
    keep = [
        rel for rel in untracked
        if rel.startswith("crates/") and rel.endswith(".rs")
    ]
    for rel in keep:
        src = os.path.join(REPO_ROOT, rel.replace("/", os.sep))
        dst = os.path.join(staging, "new_untracked", rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        items.append((dst, os.path.relpath(dst, staging).replace("\\", "/")))
        log(f"  + new untracked: {rel}")

    size = write_zip(os.path.join(out_dir, "05_new_changes.zip"), items)
    shutil.rmtree(staging, ignore_errors=True)
    return size


BRIEF_TEMPLATE = """# 云端 Gemini 只读审查说明（Imouto! Life ~単色～ Rust 重写）

生成日期：{date}
仓库状态：HEAD = `{head}`（工作区无 tracked 改动，未跟踪的新增文件见 05 包）
上一轮 Gemini 审查基线：`{baseline}`（对应文档 `docs/Full Code Review 1c76dcc.md`）

## 这是什么

《妹！生活 ～単色～》原版（WOLF RPG Engine）的 Rust 重写 + Godot 4.7.2 前端。
本次上传**只做只读代码审查**：不要构建、不要运行原版游戏、不要修改任何文件。

## 包清单

| 包 | 内容 |
|---|---|
{package_table}

## 建议的审查顺序

1. `00_REVIEW_BRIEF.md`（本文件）——先看范围与关注点。
2. `05_new_changes.zip`——**本轮新改动**（自 `{baseline}` 之后的全部补丁）。
3. `01_source_code.zip` / `02_godot_frontend.zip`——完整代码。
4. `03_docs.zip`——架构与交接文档（`docs/HANDOFF_M0.md` 是总纲，
   `docs/reviews/TASKS_REMAINING_BUGS.md` 是当前任务清单）。
5. `06_review_reports.zip` / `07_bytecode_dumps.zip`——历史结论与数据证据。
6. `08..10_*.zip`——原版实机截图与本轮重构问题截图（像素级比对证据）。

## 本轮新改动一句话摘要

自上一轮审查后，工作集中在**实机视觉与交互缺陷**的闭环上：

* 气泡名牌残留：Opcode 150 的 Move/Erase/Hide 新增 `span` 范围语义，
  名牌各组件（36008..36012）整体淡出，不再残留右半圆角。
* 对话框与头像：妹妹说话时对话框统一加高到 136 px，头像底边锚定在 563 px，
  不再探出视口底部，也不再被名牌遮挡。
* 警戒度格子条：移除 Unicode 方块字符映射，改由图集直接发射 19x20 贴图，
  消除字符宽度与贴图尺寸不一致造成的错位与叠影。
* 选项游标框：高度改为 `(pitch + 1).max(font_px + 4)`，上下各留 2 px，
  完整包裹选项文字。
* 夜间交互：透明热区（opacity=0）不再被 hover 门禁拦掉；姿势/结束/存档
  图标补进 `PICTURE_ACTION_CONTROLS`；并行的 Map Event 14 需要按
  `COMMON_SELF_BASE` 过滤，否则会被误判为 CE14 激活而吞掉全屏点击。
* 随机事件：`Sys77..Sys82`（年月日时分秒）此前从未逐帧赋值，导致随机分支
  固定命中同一结果；现由 `Game::frame()` 逐帧填充真实系统时间。
* 鼠标哨兵：实现 Opcode 124 的 `target == -2`（返回像素/图块坐标），
  使恶作剧界面的手掌/注视图标跟随指针。

## 审查重点（欢迎聚焦，但不限）

1. `crates/wolf-vm/src/exec.rs` 的 Opcode 122 / 124 / 150 解码与位掩码，
   以及 `crates/wolf-game/src/picture.rs` 的范围批处理实现是否自洽。
2. `crates/wolf-game/src/game.rs` 中 `Sys77..Sys82` 的逐帧写入：
   是否会影响存档回放与既有测试的确定性。
3. `crates/wolf-game/src/atlas.rs` / `textpic.rs` / `message.rs`：
   贴图方案取代字符映射后，是否还有别的 `\\img` 引用路径没有覆盖。
4. `crates/wolf-game/src/choice.rs` 的游标框几何与行距/字号的关系。
5. `crates/wolf-gdext/src/lib.rs` 与 `godot/scripts/GameView.gd` 的每帧逻辑：
   是否存在重复计算或状态不同步（原生鼠标光标隐藏/恢复的时机）。
6. `godot/tests/verify_ui_and_interaction_fixes.gd` 与
   `godot/tests/verify_p0_fixes.gd` 的断言强度：是否真的能挡住回归。
7. 已知未处理项（不要当成新缺陷重复报）：见 `docs/reviews/TASKS_REMAINING_BUGS.md`
   的"未处理"段与 `docs/HANDOFF_PROGRESS.md` 末尾条目。

## 输出要求

* 每条结论请给出：`文件:行号`、现象、复现或推理路径、严重度（P0/P1/P2/P3）。
* 区分"真缺陷"与"设计取舍"；改动引入的回归请单独成组列出。
* 若某条属于已归档的历史问题，请在开头标注"重复"，并指向对应报告编号。
* 不要臆造原版行为；若需要原版证据，请指明需要哪张截图或哪段字节码。
"""

UPLOAD_README = """# 上传指引（给云端 Gemini）

日期：{date}

## 步骤

1. 把本目录下 `01` ~ `10` 开头的所有 zip **逐个上传**给云端 Gemini
   （每个文件都 ≤ 16 MB，可单文件上传）。
2. 同时上传 `00_REVIEW_BRIEF.md` 作为**第一条消息**（或直接粘贴其内容）。
3. `SHA256SUMS.txt` 可选上传，用于让 Gemini 核对文件完整性。

## 校验（可选）

```bash
sha256sum -c SHA256SUMS.txt
```

## 约定

* 只读审查：不要构建、不要运行原版游戏、不要修改 `work/Data/`。
* 所有包内的路径都是相对仓库根目录的，解压后可直接对应仓库结构。
* 不含 `work/Data/`（175 MB 游戏数据）、`target/`、`godot/bin/*.dll`、
  `godot/addons/`（第三方插件）、`.git/`。
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=None)
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    out_dir = args.out or os.path.join(
        REPO_ROOT, "work", "out", f"gemini_upload_{args.date}"
    )
    out_dir = os.path.abspath(out_dir)
    clear_dir(out_dir)
    log(f"output dir: {out_dir}\n")

    head = run_git(["rev-parse", "--short", "HEAD"]).strip()

    packages = []  # [(文件名, 说明)]

    # 01 源码
    items = existing_files(TOP_FILES)
    items += walk_files("crates")
    size = write_zip(os.path.join(out_dir, "01_source_code.zip"), items,
                     "Imouto! Life — Rust workspace source (all 9 crates).\n")
    packages.append(("01_source_code.zip", f"Rust 全量源码（{len(items)} 个文件）"))
    log(f"01_source_code.zip {size / 1048576:.2f} MB")

    # 02 Godot 前端
    items = existing_files([
        "godot/project.godot",
        "godot/main.tscn",
        "godot/bin/wolf_gdext.gdextension",
        "godot/bin/wolf_gdext.gdextension.uid",
    ])
    items += walk_files("godot/scripts")
    items += walk_files("godot/tests")
    size = write_zip(os.path.join(out_dir, "02_godot_frontend.zip"), items,
                     "Imouto! Life — Godot 4.7.2 frontend (GDScript).\n")
    packages.append(("02_godot_frontend.zip", f"Godot 前端（{len(items)} 个文件）"))
    log(f"02_godot_frontend.zip {size / 1048576:.2f} MB")

    # 03 文档
    items = walk_files("docs")
    size = write_zip(os.path.join(out_dir, "03_docs.zip"), items,
                     "Imouto! Life — architecture, handoff and review docs.\n")
    packages.append(("03_docs.zip", f"文档全量（{len(items)} 个文件）"))
    log(f"03_docs.zip {size / 1048576:.2f} MB")

    # 04 工具
    items = walk_files("tools")
    size = write_zip(os.path.join(out_dir, "04_tools.zip"), items,
                     "Imouto! Life — build, audit and packaging scripts.\n")
    packages.append(("04_tools.zip", f"工具脚本（{len(items)} 个文件）"))
    log(f"04_tools.zip {size / 1048576:.2f} MB")

    # 05 新改动
    size = build_new_changes(out_dir)
    packages.append(("05_new_changes.zip", "自上一轮 Gemini 审查以来的全部补丁"))
    log(f"05_new_changes.zip {size / 1048576:.2f} MB")

    # 06 审查报告
    items = existing_files(REVIEW_REPORT_FILES)
    items += walk_files("work/out/review")
    size = write_zip(os.path.join(out_dir, "06_review_reports.zip"), items,
                     "Imouto! Life — review reports and defect ledger.\n")
    packages.append(("06_review_reports.zip", f"历史审查报告（{len(items)} 个文件）"))
    log(f"06_review_reports.zip {size / 1048576:.2f} MB")

    # 07 字节码转储
    items = existing_files(BYTECODE_DUMP_FILES)
    size = write_zip(os.path.join(out_dir, "07_bytecode_dumps.zip"), items,
                     "Imouto! Life — full bytecode dumps (CE / Map / Opcode).\n")
    packages.append(("07_bytecode_dumps.zip", "全量字节码数据转储"))
    log(f"07_bytecode_dumps.zip {size / 1048576:.2f} MB")

    # 08/09 原版实机截图
    shots = walk_files("ptr_sc")
    groups = split_into_groups(shots, GROUP_LIMIT, "retail screenshots")
    for index, group in enumerate(groups, start=1):
        suffix = chr(ord("a") + index - 1)
        name = f"{7 + index:02d}_retail_screenshots_{suffix}.zip"
        size = write_zip(os.path.join(out_dir, name), group,
                         "Imouto! Life — original retail screenshots.\n")
        packages.append((name, f"原版实机截图 {index}/{len(groups)}（{len(group)} 张）"))
        log(f"{name} {size / 1048576:.2f} MB")

    # 10 本轮重构问题截图
    items = walk_files("重构游戏问题截图")
    size = write_zip(os.path.join(out_dir, "10_issue_screenshots.zip"), items,
                     "Imouto! Life — issue screenshots from the current round.\n")
    packages.append(("10_issue_screenshots.zip", f"本轮问题截图（{len(items)} 个文件）"))
    log(f"10_issue_screenshots.zip {size / 1048576:.2f} MB")

    # 说明文件
    table = "\n".join(f"| `{name}` | {desc} |" for name, desc in packages)
    brief = BRIEF_TEMPLATE.format(
        date=args.date,
        head=head,
        baseline=LAST_GEMINI_REVIEW,
        package_table=table,
    )
    with open(os.path.join(out_dir, "00_REVIEW_BRIEF.md"), "w",
              encoding="utf-8", newline="\n") as handle:
        handle.write(brief)
    with open(os.path.join(out_dir, "00_README_UPLOAD.md"), "w",
              encoding="utf-8", newline="\n") as handle:
        handle.write(UPLOAD_README.format(date=args.date))

    # 校验：每个包都必须是合法 zip 且 ≤ 16 MB
    print()
    failures = []
    sums = []
    for name, _desc in packages:
        path = os.path.join(out_dir, name)
        size = os.path.getsize(path)
        ok = zipfile.is_zipfile(path)
        with zipfile.ZipFile(path) as zf:
            bad = zf.testzip()
            count = len(zf.namelist())
        status = "OK" if ok and bad is None and size <= HARD_LIMIT else "FAIL"
        if not ok or bad is not None:
            failures.append(f"{name}: corrupt (bad={bad})")
        if size > HARD_LIMIT:
            failures.append(f"{name}: {size} bytes > 16 MB")
        sums.append(f"{sha256_of(path).upper()}  {name}")
        print(f"  {name:<38} {size / 1048576:6.2f} MB  {count:5d} entries  {status}")

    with open(os.path.join(out_dir, "SHA256SUMS.txt"), "w",
              encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(sums) + "\n")

    if failures:
        raise SystemExit("FAILED:\n  " + "\n  ".join(failures))

    total = sum(os.path.getsize(os.path.join(out_dir, n)) for n, _ in packages)
    print(f"\n{len(packages)} package(s), total {total / 1048576:.2f} MB, all <= 16 MB")
    print(f"upload dir: {out_dir}")


if __name__ == "__main__":
    main()
