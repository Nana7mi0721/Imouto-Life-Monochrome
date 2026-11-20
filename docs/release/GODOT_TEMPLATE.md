# 定制 Godot 4.7.2 导出模板

本页描述 `tools/build-godot-template.sh` 的用途、边界与实测结果。脚本提供两档：

- **safe**：只去掉不用的图形/输入驱动，保留全部引擎类；任何 gdext 配置都能加载。
- **aggressive**：额外删除 3D/XR/Navigation/Physics3D 类，需要 `wolf-gdext`
  启用 `lazy-function-tables`（本仓库已启用），避免启动时解析全部类。

## 结论

- **Windows x86_64 aggressive 模板已实测通过**：52,120,576 B，真实导出 +
  `--headless` 运行 180 帧，GDExtension 正常加载。
- **Android arm64 aggressive 模板已构建**：模板 APK 21,775,866 B，
  `lib/arm64-v8a/libgodot_android.so` 56,326,888 B；尚未做模拟器/真机运行测试。
- safe 档产物保留作回退：Windows 65,948,160 B，Android APK 27,043,886 B。
- 两档都去掉 Vulkan / D3D12 / Metal / AccessKit / SDL / ANGLE，保留 GLES3。

## 为什么 aggressive 需要 lazy-function-tables

`godot-rust 0.5.5` 默认在 stage-init 解析全部公开引擎类。如果模板删掉这些类，
启动会报 `Failed to load class method ...`。本仓库在 `wolf-gdext/Cargo.toml`
为 `godot` 启用了 `lazy-function-tables`，方法指针改为首次调用时才解析；
只要运行时代码不使用被删的类，aggressive 模板就能安全加载。

仍然不能使用的选项：

| 选项 | 缺失示例 |
| --- | --- |
| `deprecated=no` | `get_godot_version`（接口函数，不是 class method；lazy 也不能补） |
| `disable_physics_3d=yes` | OpenXR 的 `ConcavePolygonShape3D` 链接失败 |

注意：Godot 的 `disable_3d=yes` 会在 `SConstruct` 中**强制** `disable_xr=yes`，所以
不能靠“只关 3D、保留 XR”绕过。

Android 额外使用 `module_raycast_enabled=no`：NDK r30 的 clang 在编译 Embree
`bvh_refit` 时崩溃。该模块只注册内部遮挡裁剪器，不注册公开类，因此不会触发
GDExtension 的 class-method 检查。

## 用法

```bash
cd "$(git rev-parse --show-toplevel)" && source tools/env.sh >/dev/null 2>&1

bash tools/build-godot-template.sh --check
bash tools/build-godot-template.sh --windows
bash tools/build-godot-template.sh --android
bash tools/build-godot-template.sh --windows --aggressive
bash tools/build-godot-template.sh --android --aggressive
bash tools/build-godot-template.sh            # 有前置条件时两端都构建
bash tools/build-godot-template.sh --force    # 先 clean 再构建
```

脚本不会生成发布包，也不会写 `work/out/dist`。

### 前置条件

- Python 3 + `curl` + `tar`；脚本会把 SCons 安装到
  `work/out/godot-template/pyenv`。
- Windows：MSVC `vcvars64.bat`（VS BuildTools 18 已实测）。
- Android：Android SDK（`platforms/android-36`、`build-tools/36.1.0`）、
  Android NDK（r30 已实测）、JDK 17–21；缺少 JDK 21 时脚本会下载 Temurin 21 到
  `work/out/godot-template/jdk21`。

脚本首次运行会下载并解包 Godot 4.7.2 源码到
`work/out/godot-template/src`（约 8 GB 构建树）。

## 实际构建参数

Windows：

```text
platform=windows target=template_release arch=x86_64
production=yes lto=full
vulkan=no d3d12=no metal=no accesskit=no sdl=no angle=no
opengl3=yes silence_msvc=no
disable_3d=yes disable_physics_3d=yes disable_navigation_3d=yes   # 仅 aggressive
```

Android：

```text
platform=android target=template_release arch=arm64 ndk_platform=android-24
production=yes lto=thin
vulkan=no d3d12=no metal=no accesskit=no sdl=no angle=no
opengl3=yes swappy=no module_raycast_enabled=no silence_msvc=no
disable_3d=yes disable_physics_3d=yes disable_navigation_3d=yes   # 仅 aggressive
```

Android 不使用 `lto=full`：NDK r30 的 `ld.lld` 在 full LTO 链接阶段崩溃，`lto=thin`
可稳定产出。

## 产物

```text
work/out/godot-template/out/4.7.2/windows/
  godot_windows_template_release_x86_64.exe          65,948,160 B
  godot_windows_template_release_x86_64.console.exe     292,352 B

work/out/godot-template/out/4.7.2/android/
  android_release.apk                                27,043,886 B
  libgodot_android.arm64.so                          71,618,576 B

work/out/godot-template/out/4.7.2-aggressive/windows/
  godot_windows_template_release_x86_64.exe          52,120,576 B
  godot_windows_template_release_x86_64.console.exe     292,352 B

work/out/godot-template/out/4.7.2-aggressive/android/
  android_release.apk                                21,775,866 B
  libgodot_android.arm64.so                          56,326,888 B
```

`android_release.apk` 内含 `lib/arm64-v8a/libgodot_android.so` 与
`lib/arm64-v8a/libc++_shared.so`，仅支持 arm64-v8a。

## 质量验证

Windows 使用真实项目导出验证，而不是只检查文件存在：

```bash
# 1. 在临时项目副本的 Windows preset 中设置
#    custom_template/release=<上面的 Windows 模板>
# 2. 导出
godot --headless --path <temp-project> --export-release "Windows Desktop" \
  work/out/godot-template/export-out2/ImoutoLife.exe
# 3. 把 godot/bin/wolf_gdext.dll 放到导出 exe 旁边
# 4. 跑 180 帧
./ImoutoLife.exe --headless -- \
  --data-root="<repo>/work/Data" --entry=menu --frames=180
```

通过标准：

- 进程退出码 0；
- 日志有 `Initialize godot-rust (API v4.7.stable.official, runtime v4.7.2.stable.custom_build, ...)`；
- 日志有 `wolf-gdext: open game=...`；
- 没有 `Failed to load class method`、`non-existent interface function` 或
  `SCRIPT ERROR`。

Android **只做了构建与 APK 内容检查**（`lib/arm64-v8a/libgodot_android.so`
存在、`get_godot_version` 接口仍在），没有做 APK 导出、模拟器或真机启动测试；
在发布前应补一次 Android 运行验证。

## 接入发布脚本

发布脚本应通过环境变量选择模板，而不是修改 `export_presets.cfg` 的默认值：

```bash
export GODOT_TEMPLATE_WINDOWS="$PWD/work/out/godot-template/out/4.7.2-aggressive/windows/godot_windows_template_release_x86_64.exe"
export GODOT_TEMPLATE_ANDROID="$PWD/work/out/godot-template/out/4.7.2-aggressive/android/android_release.apk"
```

导出前把对应 preset 的 `custom_template/release` 指向该路径即可。标准版与 slim 版
共用同一份模板；slim 只改变 `media.pak` 的媒体源。

## 清理

`work/out/godot-template/` 下除 `out/` 外都是可重建的临时内容，约 8 GB：

```bash
rm -rf work/out/godot-template/src \
       work/out/godot-template/pyenv \
       work/out/godot-template/jdk21 \
       work/out/godot-template/gradle-home \
       work/out/godot-template/android-user-home \
       work/out/godot-template/tmp
```

不要删除 `work/out/godot-template/out/`，除非准备重新构建模板。
