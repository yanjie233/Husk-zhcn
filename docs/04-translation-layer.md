# 翻译层：不启动 Android 就运行 Android 应用

状态：**实验性，第一段已经构建。** Settings › Experimental › Android Translation Layer 已存在。可以在那里添加应用，每个应用都会得到一份"运行它需要付出什么"的报告，也可以向手机询问这套设计所依赖的那些问题。**目前还没有任何东西能打开一个应用。** Husk 的其余部分不受影响。

本文读过的源码，2026 年 9 月：

- Android Translation Layer（ATL）`b4bd403`（2026-09-23），
  `gitlab.com/android_translation_layer/android_translation_layer`
- 其 `bionic_translation` `b36c17d` 和 `art_standalone` `66a5d90`
- AetherPS4 `bachata-core` `b7127f0`（2026-09-11），FEXCore 移植

## 为什么

Husk 运行一个 APK 的方式，是在 QEMU 的 TCG 下启动一整套 Android 系统，再显示其中一个应用的表面。这行得通，但在第一帧之前，它要付出一个内核、一个 init、`system_server`、zygote 以及数分钟模拟 CPU 的代价，全部经由一个软件 MMU 翻译（见 [00-architecture.md](00-architecture.md)）。

ATL 表明，运行一个应用根本不需要这些东西。它自己的架构说明把这个切点放在"直接位于应用与 android 框架提供的 Java API 之间"：保留应用的 Dex 和它的 `.so` 文件，在一个普通的宿主进程中运行它们，再交给它们一套框架的重新实现。在 iOS 上这意味着根本没有客户机，应用的原生代码跑在真实 CPU 上而不是 TCG 之下。

## ATL 到底是什么

读自源码，而不是它的 README：

| 部件 | 它是什么 | 许可证 | 在 iOS 上 |
|---|---|---|---|
| `art_standalone` | ART、libcore 及其依赖，被"缝合"到 AOSP 的 android-6.0.1 dalvik 分支上，并为 glibc/musl 宿主构建。约 20,000 个文件。 | Apache-2.0（AOSP）；libcore 中的 OpenJDK 部分为 GPLv2 + Classpath Exception | **移植。** `kPageSize` 是编译期常量 `4096`（`libartbase/base/globals.h`），而 iOS 页面是 16 KiB。其 JIT 代码缓存已经支持 RW/RX 双视图（`jit_code_cache.cc`：`exec_pages_` / `non_exec_pages_`），这恰好就是 Husk 的 `vm_remap` 那一对的形态。只有它的 `memfd_create` 分配需要改动。 |
| `bionic_translation` | 在 glibc/musl 上加载链接了 bionic 的 `.so` 文件：老的 AOSP 链接器（BSD），外加来自 android2gnulinux 的 libc 与 pthread 封装 | 链接器是 BSD；那些封装**完全没有许可证声明** | **替换。** 它的 libc shim 面向 glibc/musl 的结构体布局，而且那些封装反正也不能用：一个没有许可证的文件不是 GPL 项目能拿来用的（对比 [01-licensing.md](01-licensing.md) 中的 BreakpointJIT）。 |
| `src/api-impl` | Android 框架，用 Java 重新实现：819 个文件，其中 329 个带 AOSP 的 Apache 头 | GPL-3.0（ATL）+ Apache-2.0 | Java 在任何 ART 能跑的地方都能跑，**但见"许可"一节。** |
| `src/api-impl-jni` | 框架的原生那一半：83 个 C 文件，基于 GTK4、Wayland、EGL、WebKitGTK、ALSA、libavcodec、libportal | GPL-3.0 | 面向 UIKit、Metal 和 CoreAudio **重写**。iOS 上根本不存在 GTK/Wayland。 |
| `src/libandroid` | NDK 的 `libandroid.so`，架在 GTK、EGL 和 Vulkan 之上 | GPL-3.0 | **重写。** EGL/GLES 来自 ANGLE，而 Husk 已经为 iOS 构建了 ANGLE。 |

## 方案一还是方案二

**方案一，一个 iOS 原生的翻译层。** Husk 发布为 `arm64-apple-ios` 构建的 ART、一个原生那一半是 UIKit/Metal 的框架层，以及它自己用来加载应用 arm64 `.so` 文件的 loader。

**方案二，在 FEXCore 下运行 ATL。** 不合适，理由就在 FEXCore 移植本身。`bachata-core` *只*构建 FEXCore（`runtime/patches/fex-fexcore-only.patch` 增加了 `BUILD_FEXCORE_ONLY`）。那是 FEX 的 x86-64 → arm64 JIT，去掉了 FEX 的 Linux 前端（它的 ELF 加载器和系统调用层），由 AetherPS4 的 HLE 桥接来提供操作系统。FEXCore 翻译的是 *x86* 代码。翻译层在 iPhone 上要干的活自始至终都是 arm64：为 arm64 构建的 ART，以及几乎每个 APK 都携带的 `arm64-v8a` 库。除非一切都先为 x86-64 重新构建，否则 FEX 没有什么可翻译的，而那会让 iPhone 本可直接执行的每一条指令都多付一次翻译的代价。FEX 的 Linux 前端把系统调用交给一个 Linux 内核，所以那也帮不上忙：Linux → Darwin 的工作仍然存在。（QEMU 的 user mode 同样不是捷径，理由相同：它只能跑在 Linux 和 BSD 宿主上。）

FEXCore *确实*有一席之地，但那是在更后面、且范围很窄。一个原生代码只有 x86 版本的 APK，可以仅让那几个库经由 FEXCore 运行，再像 AetherPS4 桥接 HLE 调用那样桥接到同一套框架上。扫描器已经能识别这类应用（"Native code for x86 only"）。

**决定：方案一。** 这本来也是更受偏好的那个。

## 许可：决定布局的那条约束

值得复用的 Android 运行时的每一个部件，其许可证都无法与 QEMU 的 GPLv2 组合进同一个程序：

- ART 和 AOSP 的框架代码：**Apache-2.0**，与 GPLv2 不兼容。（这与 [01-licensing.md](01-licensing.md) 中 UTM 应用代码的陷阱是同一个。）
- ATL 本身：**GPL-3.0**，同样与仅 GPLv2 的代码不兼容。

Husk 今天把自己的进程链接进了 `libqemu-aarch64-softmmu.dylib`。一个同时又加载 ART 的进程，就是一个同时包含仅 GPLv2 代码和 Apache-2.0 代码的组合作品，而没有人能分发它。

这次改动对此的处理是：**`src/translation-layer/` 下的一切都是 Husk 自己的代码，采用 GPL-2.0-or-later，没有一样来自 ATL 或 AOSP。** 它被编译进应用，而不是编译进 QEMU 库。目前还没有发布任何许可证敏感的东西。这个决定需要**在里程碑 2 之前**做出，也就是 ART 第一次进入构建的时刻。现实的选项有：

1. **一个不含 QEMU 的独立 Husk 构建**，专供翻译层使用。毫无歧义。
2. **一个 IPA，但在一次进程生命周期内绝不同时运行两者。** QEMU 和运行时变成各自独立 `dlopen` 的库，Husk 每次启动只加载其中一个。这算不算"纯粹的聚合（mere aggregation）"是法律问题，不是工程问题，此处不作裁定。

无论哪种情况，Husk 编写的代码都保持 GPL-2.0-or-later。在 GPLv3 下它可以与 ATL 派生或 Apache 代码共存，在 GPLv2 下可以与 QEMU 共存。

## 目标形态

```
┌───────────────────────────────────────────────────────────────┐
│ Husk.app — library, one UIView/CAMetalLayer per Activity      │
├───────────────────────────────────────────────────────────────┤
│ framework (Java, dex)          │ framework native half         │
│   android.app, .view, .widget  │   UIKit/Metal/CoreAudio,      │
│                                │   ANGLE for EGL/GLES          │
├───────────────────────────────────────────────────────────────┤
│ ART for arm64-apple-ios — interpreter first, JIT on Husk's    │
│ RW/RX pair later                                              │
├───────────────────────────────────────────────────────────────┤
│ Husk's loader — the app's arm64 .so files into JIT memory,    │
│ bionic's ABI mapped onto Darwin's libc                        │
├───────────────────────────────────────────────────────────────┤
│ JIT substrate (StikDebug / MAP_JIT / TrollStore), shared with │
│ QEMU mode once it is its own library                          │
└───────────────────────────────────────────────────────────────┘
```

## 难点，以及每个难点正在如何被回答

每一项都写明它是**已测量**、**已处理**，还是仍然**悬而未决**。

### 库的可执行内存：已在手机上测量

一个库的代码必须可执行，而它的数据必须可写，并且两者相隔固定距离：编译出来的代码用 PC 相对方式（`adrp`）找到自己的全局变量。因此每个库映像都需要紧挨着可执行内存的普通内存。Husk 的 JIT 内存是一整块区域、一次性授予，所以 loader 必须从其中切分出各个映像。有两种可能的布局，真机检查会用真实生成的代码把两者都试一遍：

- **carve**：先映射可执行内存，再把其中的数据页替换成普通内存；
- **place**：先保留普通内存，再在数据前方的某个选定地址上映射一个可执行页。

两者在 qemu-user 下的 arm64 Linux 上都通过了（`tests/translation-layer/run.sh`），这验证了检查所生成的代码本身。XNU 是否允许其中任何一种，要由手机来回答。这些检查运行在 MAP_JIT 可执行的地方（TrollStore，以及调试器就够用的 iOS 版本）。一个*受理陷入*的调试器所授予的区域，属于编译进 QEMU 库里的那个分配器，所以那种情况被报告为未测量。要测量它，就得把 `src/ios-jit/husk-ios-jit.c` 挪进一个自己的小库，两种模式都链接它。

预算：这块区域是一次性的（见 [02-jit-substrate.md](02-jit-substrate.md)），所以它必须装下一个应用加载的每一个库，再加上 ART 的代码缓存。光一个 Unity IL2CPP 游戏的 `libil2cpp.so` 就有几十 MB。

### 16 KiB 页面：已处理，逐库进行

iOS 页面是 16 KiB。一个按 4 KiB 页面链接的库，可能把代码和可写数据放进同一个 16 KiB 页面，那就会要求该页面同时可执行又可写。扫描器按 16 KiB 页面规划每个 arm64 库的布局，与 loader 将要做的完全一致（`husk-tl-elf.c` 中的 `tl_page_plan`），并统计这些页面。`PT_GNU_RELRO` 下的可写字节不计入：它们只在重定位期间被写入，而 loader 是经由 RW 别名做这件事的。自 2025 年 11 月起，Google Play 要求面向 Android 15 及以上的新应用和更新携带兼容 16 KiB 的原生代码，所以现在来自 Play 的 APK 都是干净的。更老的会被标为"needs work"，而解法就是对那少数几个页面做写入模拟。

### 线程寄存器：已在手机上测量

Clang 的 Android 目标在每个受保护函数里都从 `TPIDR_EL0 + 0x28` 读取栈保护 cookie。测试套件在固件上确认了这一点：`mrs x8, TPIDR_EL0; ldr x9, [x8, #0x28]`。在 glibc 上，ATL 能蒙混过去，是因为 glibc 的线程指针正好可以安置 bionic 那些槽位。Darwin 则把线程指针放在 `TPIDRRO_EL0` 里，所以 `TPIDR_EL0` 可能干脆是空闲的。`tpidr` 检查要测量的就是这个：它是否为零、在四个线程上设置的值能否熬过数百次上下文切换，以及能否熬进信号处理器。如果通过，Android 代码就能原样运行。如果失败，每一条 `mrs Xn, tpidr_el0` 都得在加载时被改写，而扫描器已经按库统计过它们了。

### x18：已在手机上测量

Clang 对 Android 和 iOS 目标都保留 x18（已核查：它为 `aarch64-linux-gnu` 分配 x18，而从不为 `aarch64-linux-android` 或 `arm64-apple-ios` 分配），所以普通的 Android 代码从不碰它。启用了影子调用栈构建的代码，以及可能来自更老编译器的库，会碰它。`x18` 检查要测量 XNU 是否保留它。

### 直接系统调用：已统计，仍悬而未决

bionic 自己发起系统调用，所以 shim 把它们整个替换掉。但有些代码以内联方式用 Linux 编号发出 `svc #0`（Go 的运行时、某些防篡改代码），而 iOS 会把那些当作 Darwin 调用。扫描器按库统计 `svc` 指令。loader 将不得不把每一条都补丁成对 shim 的调用。

### Darwin libc 之上的 bionic：悬而未决

这是 loader 中最大的机械性部分。结构体布局（`stat`、`dirent`、`sigaction`）、`errno` 取值、`open`/`mmap` 标志、信号编号、`pthread_mutex_t` 大小（bionic arm64 上 40 字节，Darwin 上 64 字节），以及 bionic 的 `__sF` stdio，全都不一样。扫描器给出的每个应用的"它需要的 Android 库"清单，就是必须提供的东西的清单。

### 32 位应用：原生方式不可行

自 A11 起，Apple 的 CPU 就不再执行 AArch32 代码。一个只有 `armeabi-v7a` 库的 APK 需要一个 CPU 模拟器，扫描器会这么说。

### ART：悬而未决

为 `arm64-apple-ios` 构建，`kPageSize` = 16 KiB。它先以纯解释器方式启动：`-Xusejit:false`，并且不做 boot-image dex2oat（ATL 的 README 对 Apple Silicon Linux 给出同样的变通办法）。等代码缓存落到 Husk 的 RW/RX 那一对之上，JIT 再跟上。

## 里程碑

| # | 内容 | 状态 |
|---|---|---|
| M0 | 设置项、翻译层自己的 APK store、逐应用报告、真机检查 | **已构建** — 已在宿主机测试；尚未在手机上运行 |
| M1 | 真机检查在硬件上通过；JIT 底层机制自成一个库，从而"受理陷入"的那种情况也能被测量 | 未开始 |
| M2 | 为 `arm64-apple-ios` 构建的 ART，仅解释器模式，在进程内从一个 Dex 文件运行 `main()`。**先做许可决定。** | 未开始 |
| M3 | Husk 的 loader：把一个 arm64 `.so` 装进 JIT 内存，针对第一版 bionic shim 重定位；`JNI_OnLoad` 运行 | 未开始 |
| M4 | 带 UIKit 原生半边的框架：一个纯 Java 应用显示一个带文字和按钮的 Activity | 未开始 |
| M5 | 经 ANGLE 的 GLES：一个 NativeActivity 游戏画出画面 | 未开始 |
| M6 | 音频、输入、输入法、存储、网络 | 未开始 |
| 之后 | ART 的 JIT 落到 RW/RX 那一对上；面向纯 x86 库的 FEXCore | — |

在真机上亲眼看到它工作之前，M0 以上的任何内容都不应被描述为可用。

## 现在存在什么

- `src/translation-layer/`，C 语言编写并编译进应用：
  - `husk-tl-zip.c`：一个 APK 读取器（ZIP、ZIP64、stored 与 deflated 条目），为不可信输入而写。
  - `husk-tl-elf.c`：ELF 分析，包括 loader 将复用的 16 KiB 页面规划器，以及 Android 打包重定位（APS2）与 RELR 的解码器。
  - `husk-tl-scan.c`：逐应用的报告。
  - `husk-tl-probe.c`：真机检查。
- `src/app/Husk/TranslationLayer.swift`：那个设置项、APK store（`Documents/TranslationLayer/`，与 Android 的分开）、报告以及检查页面。
- `tests/translation-layer/run.sh`：
  - 在手工推导出的布局上运行页面规划器；
  - 在由 clang 和 lld 构建的真实 arm64 Android 库上运行扫描器，其重定位、导入与栈保护计数与 `llvm-readelf`、`llvm-objdump` 对照核验；
  - 真机检查，作为 arm64 代码在 qemu-user 下运行。

  `fuzz.c` 是针对那两个解析器的 libFuzzer 测试。在 ASan 和 UBSan 下 300,000 次运行中两者都未曾崩溃。
