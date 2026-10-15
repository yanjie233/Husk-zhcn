# Husk 架构

Husk 通过在宿主应用自身的进程内，用 QEMU 的 TCG 启动一个真实的 ARM64 Android 客户机，
并把单个应用的渲染表面全屏呈现出来、看不到任何 Android 界面元素，从而在 iOS 上
运行未经修改的 Android APK。

本文记录哪些内容已**对照源码或构建得到验证**，并清楚标注哪些尚未在设备上运行过。

一个实验性的第二运行时——完全不启动 Android 就运行应用自身的代码——规划在
[04-translation-layer.md](04-translation-layer.md) 中。

## 技术栈

```
┌─────────────────────────────────────────────────────────────┐
│ Husk.app (Swift/ObjC, GPL-2.0-or-later)                     │
│   library grid · full-screen presentation · Metal blit      │
│   touch -> qemu_input_queue_abs/btn                         │
├─────────────────────────────────────────────────────────────┤
│ DisplayChangeListener  (registered from the app side)       │
├─────────────────────────────────────────────────────────────┤
│ libqemu-aarch64-softmmu.dylib   QEMU 10.0.12-utm, GPLv2     │
│   qemu_init() / qemu_main_loop() on a pthread               │
│   TCG, MTTCG, split-W^X via tcg_splitwx_diff                │
├─────────────────────────────────────────────────────────────┤
│ husk-ios-jit.c + husk-brk.S     RX from StikDebug,          │
│                                 RW alias via vm_remap       │
├─────────────────────────────────────────────────────────────┤
│ StikDebug (separate app, AGPL-3.0) attached as debugger     │
└─────────────────────────────────────────────────────────────┘
```

## 已经做出的决定，以及理由

**不使用 hypervisor。** Hypervisor.framework 对第三方 iOS 应用不可用
（UTM 自己的 `Documentation/Architecture.md` 就是这么说的）。UTM 确实为 iOS 提供了一个
`build_hypervisor` 步骤，使用一个反编译的 Hypervisor 框架，但那需要
`com.apple.private.hypervisor`，也就是需要越狱。Husk 面向侧载，所以只能是 TCG。
这是最大的单项性能约束，且没有商量余地。

**QEMU，具体是 `qemu-10.0.12-utm`，而非上游版本。** 上游 QEMU 没有办法把自己构建成一个库，
而 iOS 无法派生进程，所以 QEMU 必须驻留在进程内。UTM 的 fork 增加了 `-Dshared_lib=true`，
由此产出 `libqemu-aarch64-softmmu.dylib`，导出 `qemu_init` / `qemu_main_loop` /
`qemu_cleanup`，外加库构建所需的两处小改动
（`rcu_register_thread` 移入 `qemu_init`；跳过非库的构造函数路径）。上游 v11.1.1 曾被考虑后否决：
把该能力向前移植，对 Phase 0 没有任何好处。

**TCG 的 split-W^X 在上游，因此几乎什么都不需要打补丁。** osy 2020 年
在 `utmapp/qemu` 中的 "tcg: implement bulletproof JIT" 提交——正是为这个问题而写：
"on iOS, we cannot allocate RWX pages without special entitlements"——
以上游 `tcg_splitwx_diff` 的形式被采纳。UTM 当前 107 KB 的 iOS 补丁涉及 28 个文件，
**其中没有一个位于 `tcg/` 之下**。Husk 唯一的 TCG 改动是一个新增的分配器函数。

**同 ISA 不等于零成本。** 任务书说 ARM64-on-ARM64 意味着"无需支付跨 ISA 翻译开销"。
这话只对了一半：不存在指令集不匹配，但系统模式 TCG 仍然要把客户机代码翻译为 TCG IR 再到宿主代码，
并用软件模拟 MMU。相对原生应预期一个很大的常数因子减速，而不是接近原生的速度。结论没有变——
TCG 是唯一选项——但 Phase 1 的耗时预测应据此给出，而且 MTTCG
（客户机 vCPU 跑在各自的宿主线程上）在多核手机上影响很大。

## JIT 路径

在 [02-jit-substrate.md](02-jit-substrate.md) 中有完整记录。简言之：在 iOS 27 上，
每台目标设备都强制执行 TXM，因此可执行内存只能由已附加的调试器授予。Husk 用 `brk #0xf00d`
（x16 = 1）陷入 StikDebug，收到一段由调试器分配的 RX 区域，其中每一页都被调试器逐一触碰过，
再用 `vm_remap` 制造自己的 RW 别名。随后 QEMU 直接把这一对当作 `tcg_splitwx_diff` 使用。

这次分配是**一次性的**——之后 StikDebug 会分离，而一个未被受理的 `brk`
是致命的 SIGTRAP，不是错误返回。QEMU 对此格外合适，因为 TCG 在初始化时依据
`-accel tcg,tb-size=N` 确定一次代码缓冲区大小，此后只冲刷而不再增长。

## 显示与输入

`register_displaychangelistener()` 是公开的 QEMU API，因此显示桥接
**完全不需要任何 QEMU 补丁**。应用注册一个 `DisplayChangeListener`，
接收 `dpy_gfx_switch`（新表面）和 `dpy_gfx_update`（脏矩形）回调，
它们携带由 pixman 图像支撑的 `DisplaySurface`；这些像素被位块传输进一个 `CAMetalLayer`。
输入则反向经由 `qemu_input_queue_abs` / `qemu_input_queue_btn` / `qemu_input_event_sync`
作用于一个 `virtio-tablet-pci`（绝对坐标由触点直接映射，没有需要解决的指针捕获问题）。

有意*没有*从 UTM 的 CocoaSpice 改编：那段代码是 Apache-2.0，与 GPLv2 不兼容。参见
[01-licensing.md](01-licensing.md)。

## Phase 0 状态

| 组件 | 状态 |
|---|---|
| 依赖集合为 arm64-apple-ios 交叉编译 | **已构建** — libffi, glib 2.83, pixman, libucontext, libslirp |
| 面向 iOS 的 `libqemu-aarch64-softmmu.dylib` | **已构建** — 已验证 `platform 2`（iOS），minos 16.0，SDK 27.0 |
| `husk-brk.S` | **已构建** — 反汇编与 BreakpointJIT.framework 逐字节一致 |
| `husk-ios-jit.c` | **编译无警告**（`-Wall -Wextra`），iOS arm64 |
| TCG splitwx 重定向到 iOS 分配器 | **已打补丁**，`patches/husk-qemu-ios-jit.patch` |
| Phase 0 客户机（Alpine 3.24.1 aarch64） | **已抓取**，sha256 已验证 |
| 设备上的 JIT 分配 + 执行自测 | **PASS** — iPhone18,1 / iOS 27.0，256 MiB 用时 749 ms |
| 客户机在设备上于 TCG 下启动 | 进行中 |
| 客户机在设备上进入用户空间 | 尚未 |
| 帧到达 Metal，触摸到达客户机 | 尚未 |

在真机上亲眼看到它工作之前，未验证的行都不应被描述为可用。JIT 那一行之所以变成 PASS，
只是因为自测在真机上从 RX 别名执行了生成的代码并返回 42。
