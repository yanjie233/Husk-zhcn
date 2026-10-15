# Husk 中文版

> 这是 [Leviidev/Husk](https://github.com/Leviidev/Husk) 的简体中文分叉：界面与文档已汉化，
> Android 系统内置中文字体，并由 GitHub Actions 自动构建、发布到 [Releases](https://github.com/yanjie233/Husk-zhcn/releases)。
> 上游的 PS4 模拟层因源码未公开而未包含（其余功能完整）。

<p align="center">
  <a href="https://trendshift.io/repositories/233057?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-233057" target="_blank" rel="noopener noreferrer">
    <img src="https://trendshift.io/api/badge/trendshift/repositories/233057/daily?language=Swift" alt="Leviidev/Husk | Trendshift" width="250" height="55"/>
  </a>
</p>

[![Husk Downloads](https://img.shields.io/github/downloads/leviidev/husk/total?style=for-the-badge&color=5865F2&labelColor=111111)](https://github.com/leviidev/husk/releases)

在 iPhone 上运行 Android 应用和游戏。

添加一个 APK，点它，就会全屏打开。Husk 以两种方式之一运行它，
对应其资料库（Library）的两个分区：

- **翻译层（Translation Layer）。** 游戏自己的 64 位 Android 代码直接在
  iPhone 的处理器上运行，由 Husk 在其周围顶替 Android 的角色：C
  库、游戏发起的 Java 调用、OpenGL ES（通过 ANGLE）、Vulkan
  （通过 MoltenVK）、声音、触摸和手柄。不启动 Android，因此
  游戏几秒内即可开始，其代码从不被模拟。
  参见 [docs/04-translation-layer.md](docs/04-translation-layer.md)。
- **模拟（Emulation）。** 一整套 Android 系统（LineageOS）在 Husk 内部的
  QEMU 下启动，用于翻译层尚无法运行的应用，也用于直接使用
  Android 本身。iOS 不向应用提供 hypervisor，因此处理器是被模拟的，
  这比翻译层慢得多。
  参见 [docs/00-architecture.md](docs/00-architecture.md)。

## 截图

### 在翻译层上运行的游戏

<table>
  <tr>
    <td align="center"><img src="Screenshots/gta-san-andreas.jpeg" alt="GTA: San Andreas" width="100%"><br><sub><b>GTA: San Andreas</b></sub></td>
    <td align="center"><img src="Screenshots/minecraft-dungeons.jpeg" alt="Minecraft Dungeons" width="100%"><br><sub><b>Minecraft Dungeons</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="Screenshots/beach-buggy-racing-2.jpeg" alt="Beach Buggy Racing 2" width="100%"><br><sub><b>Beach Buggy Racing 2</b></sub></td>
    <td align="center"><img src="Screenshots/geometry-dash.jpeg" alt="Geometry Dash" width="100%"><br><sub><b>Geometry Dash</b></sub></td>
  </tr>
</table>

### 应用本身

<table>
  <tr>
    <td align="center" width="33%"><img src="Screenshots/library.png" alt="Library" width="100%"><br><sub><b>资料库</b></sub></td>
    <td align="center" width="33%"><img src="Screenshots/game-settings.png" alt="Game Settings" width="100%"><br><sub><b>游戏设置</b></sub></td>
    <td align="center" width="33%"><img src="Screenshots/settings.png" alt="Settings" width="100%"><br><sub><b>设置</b></sub></td>
  </tr>
</table>

## 翻译层能运行什么

Husk 为其提供了驱动的引擎所制作的游戏：

- Unity
- Unreal Engine 4（通过 Vulkan）
- cocos2d-x
- Godot 3 和 4（GLES2、GLES3 与兼容性渲染器）
- SDL2 和 SDL3，包括 LÖVE 游戏
- GameActivity（Minecraft）与 NativeActivity
- Rockstar 自家的引擎（GTA: San Andreas）

游戏会看到 Google Play 服务已安装但未登录，因此会检查它的那些游戏能正常启动；Play Games 登录、云存档与内购不可用。Geometry Dash 可以加载 [Geode](https://geode-sdk.org) 模组。

APK 需要 64 位（`arm64-v8a`）原生代码。iPhone 无法运行 32 位 ARM
代码，因此只有 32 位库的 APK 无法在此运行。APK 与分发包
（`.xapk`、`.apkm`、`.apks`，或一次 Play 下载分离出的 split
APK 与 asset pack）都可以添加。只用 Java 编写、没有原生引擎的应用在翻译层上不受支持；
运行它们要用模拟。

每次启动 Husk 只运行一个游戏。要切换，请在另一个游戏的页面上按 **Close Husk to Play**；再次打开 Husk 时，那个游戏会自行开始。

游戏的存档可以在其页面备份为 `.zip`，之后在同一个或另一台 iPhone 上恢复。如果某个游戏让 Husk 崩溃，下次启动会显示发生了什么，并附带一份可以分享的报告。

## 安装

**SideStore、AltStore 及其他侧载工具：** 添加 Husk 的源，侧载工具就会安装 Husk，并在其每次发布更新时提供更新。

```
https://raw.githubusercontent.com/yanjie233/Husk-zhcn/main/altsource.json
```

在 SideStore 或 AltStore 中：Sources › + › 粘贴上面的地址。

**或者手动：** 从 [Releases](https://github.com/yanjie233/Husk-zhcn/releases)（`nightly` 即最新构建）下载 `Husk.ipa`，并用 SideStore、AltStore 或 TrollStore 安装。对它们来说这是同一个 IPA：它带有 Husk 的 entitlements，TrollStore 会保留这些 entitlements，而侧载工具会用你自己的重新签名。

Husk 需要 iOS 16.0 或更高版本。

## JIT

翻译层和模拟都需要 JIT，而在 iOS 上 JIT 来自调试器。Husk 可以通过若干种方式获取它，并会逐步引导你完成每一种（Settings › JIT & Sideload）：

- **内置 StikJIT**（iOS 26 及以上）：Husk 自己开启 JIT，无需第二个应用。在 iOS 27 上，它可以在 Settings 中与你的 iPhone 配对，无需电脑。参见 [docs/06-built-in-jit.md](docs/06-built-in-jit.md)。
- **StikDebug**，与 Husk 并排安装。
- **TrollStore 或 Dopamine 越狱**（"Allow JIT in Apps"），仅适用于 iOS 26 之前的版本。从 iOS 26 起，只有调试器才能授予 JIT。

## 构建

本分叉默认走 CI：推送本仓库会触发 [GitHub Actions](https://github.com/yanjie233/Husk-zhcn/actions) 在 macOS 上
执行 `./scripts/ci_build.sh` 并把 `Husk.ipa` / `Husk.tipa` 发布到 Releases（首次约 2–4 小时，之后命中缓存约 20–40 分钟）。
CI 无法构建的两处差异：PS4 层（`libhuskps4.dylib`，上游源码私有，已从工程中移除）与 Java 运行时
（直接取自上游 2.0 发布的 IPA，其源码 `src/java-framework` 自 2.0 起未改动）。

本地构建：Husk 在装有 Xcode 的 Mac 上构建。构建脚本还会调用 `meson`、
`ninja`、`pkg-config`、`python3`、`xcodegen`、`qemu-img`，以及带有
`aarch64-apple-ios` 目标的 Rust 工具链。

```sh
./scripts/ci_build.sh
```

从一份干净的检出开始，这会抓取并交叉编译 Husk 所链接的全部内容：

- QEMU 及其依赖
- ANGLE 和 virglrenderer
- MoltenVK
- 设备端配对库

随后构建应用，并把 IPA 写入 `build/Husk.ipa`。首次运行要花几个小时，之后的运行会复用已经构建好的部分。此后，`./scripts/package_ipa.sh` 只重新构建应用并写出 `~/Desktop/Husk.ipa`。

`tools/regress/run.sh` 通过翻译层在 Mac 上运行一组游戏，并把每个游戏与一张参考截图比对（它需要什么，见 `tools/regress/cases.txt` 顶部）。

## 许可证

GPL-2.0-or-later。Husk 链接了 QEMU，而 QEMU 是 GPLv2，因此发布的二进制是一个 GPLv2 的组合作品，完整源码公开。翻译层是 Husk 自己的代码，采用同样的许可证。Husk 无法上架 App Store，既因为这一点，也因为它需要 `get-task-allow` 外加一个在运行时附加的调试器。参见 [docs/01-licensing.md](docs/01-licensing.md)。
