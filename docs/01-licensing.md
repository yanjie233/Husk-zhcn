# 许可与分发：已定

任务书要求在写出大量原创代码之前把这件事解决掉。它已解决。下面每一条主张都是对照实际源码树中实际的 LICENSE 文件核对过的，而不是凭记忆。

## 决定

**Husk 采用 GPL-2.0-or-later。源码公开。分发方式是侧载 IPA 加上完整对应的源码，绝不上 App Store。**

加入 `LICENSE`（GPL-2.0），并为每个 Husk 编写的文件加上 SPDX 头：

```c
/* SPDX-License-Identifier: GPL-2.0-or-later */
```

## 为什么是 GPL-2.0，以及为什么其实从来就没有真正的选择

QEMU 自己的 `LICENSE`，摘自 `qemu-10.0.12-utm/LICENSE`：

> 1) QEMU 模拟器整体以 GNU 通用公共许可证第 2 版发布。

Husk 把 QEMU 作为 `libqemu-aarch64-softmmu.dylib` 链接进自己的进程，并把该 dylib 随 IPA 一起发布。
这就是对一个组合作品的分发，因此该组合作品必须以 GPLv2 提供。为 Husk 自己的文件选择
`GPL-2.0-or-later` 是恰当的色度：它与 QEMU 的 GPLv2 兼容（该组合实际上就是 GPLv2），
同时又为日后任何需要 GPLv3 的东西留着门。

第二个独立的理由：`husk-ios-jit.c` 派生自 AetherPS4-iOS 的
`src/core/ios/ios_jit_allocator.cpp`，其文件头写着

```
// SPDX-FileCopyrightText: Copyright 2024-2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
```

所以不管 QEMU 怎样，这个文件本来就会是 GPL-2.0-or-later。

## 值得点名的陷阱：UTM 的应用代码是 Apache-2.0

`utm/LICENSE` 是 Apache License 2.0。**Apache-2.0 与 GPLv2 不兼容**
（它与 GPLv3 兼容，可那对我们没用，因为 QEMU 整体是 GPLv2）。于是：

| 对象 | 许可证 | 能用在 Husk 里吗？ |
|---|---|---|
| `utmapp/qemu` fork（我们构建的那个 tarball） | GPL-2.0 — 它*就是* QEMU | **可以** |
| UTM 的 `scripts/build_dependencies.sh` | ISC（文件头注明 Angelo Haller, 2014） | **可以** — 宽松型许可 |
| UTM 的 Swift/ObjC 应用代码、CocoaSpice、它们的 UI | Apache-2.0 | **不可以 — 不要复制** |

到目前为止，Husk 取用了 QEMU 的 tarball，以及构建脚本里的*思路*（工具链 triple、meson 交叉文件的形式）。
没有复制任何 UTM 的应用代码，也不该复制。当 Phase 0 的显示桥接被写出来时，必须从头新写，而不是从 CocoaSpice 改编。

## StikDebug 是 AGPL-3.0，这没问题

`StikDebug-PiP/LICENSE` 是 GNU Affero GPL v3。如果 Husk 链接它，那会是个严重问题。
Husk 并不链接它。StikDebug 是一个**独立应用**，通过 gdb-remote 协议作为调试器附加到 Husk 上。
没有链接、没有共享地址空间、也没有衍生作品——跨越边界的只有一个线路协议（wire protocol），
而那不属于著作权的保护对象。

用户自行从 StikDebug 自己的分发渠道安装它。Husk 应当记录这个依赖并给出链接，而不是把它打包进去。

## 内置 StikJIT：MPL-2.0 与 MIT，会被打包

内置 StikJIT（docs/06-built-in-jit.md）确实会打包代码，而且它并不是 StikDebug 的 AGPL 应用：

| 对象 | 许可证 | 位置 |
|---|---|---|
| StikJIT 1.9.0 XCFramework，未经修改（[`StikDebug/StikJIT` tag `1.9.0`](https://github.com/StikDebug/StikJIT/tree/1.9.0)，`StikJIT.xcframework.zip` SHA-256 `806664393770c68e75f2b6429955bfdd88cfaad09fec2ba70f8ed615ff90c060`） | MPL-2.0 | `src/app/Frameworks/`，嵌入 `Husk.app/Frameworks`，且只由 `HuskJITHelper` 扩展使用 |
| [idevice](https://github.com/jkcoxson/idevice)，位于 StikJIT 内部以及 `libhusk_rppairing.a`（0.1.68） | MIT | 链接 |
| idevice 的 Rust 依赖，由 `src/rppairing-ios/Cargo.lock` 锁定 | MIT, Apache-2.0, BSD-3-Clause 或 ISC | 静态链接在应用中 |
| Husk 的配对封装（`src/rppairing-ios`） | GPL-2.0-or-later | 静态链接在应用中 |

MPL-2.0 是文件级 copyleft，与 GPL 兼容（MPL-2.0 §3.3），而且 StikJIT 的源码在上面那个 tag 处公开，
那就是该二进制的对应源码。许可证文本随应用一起发布，分别为 `LICENSE-StikJIT-MPL-2.0.txt`、
`LICENSE-idevice-MIT.txt` 和 `LICENSES-rppairing-crates.txt`（由
`scripts/build_rppairing_ios.sh` 重新生成）。

## BreakpointJIT：靠移除依赖来解决

`BreakpointJIT.framework`（bundle id `com.stossy11.BreakpointJIT`）以裸 Mach-O 形式发布，
**其分发物中任何地方都没有许可证文件**。把它 vendor 进来的 MeloNX 是 MIT——
但那覆盖的是 Ryujinx 的代码，而不是某个第三方丢进 `Dependencies/` 的二进制。
一个没有许可证的二进制，不是一个 GPL 项目能对它建立动态链接依赖的东西。

结果证明这无关紧要，因为该框架只有 11 条指令。`otool -tV` 能把整个东西反汇编出来：

```
_BreakGetJITMapping:  mov x16, #0x1 ; brk #0xf00d ; ret
_BreakJITDetach:      mov x16, #0x0 ; brk #0xf00d ; ret
_BreakMarkJITMapping: brk #0x69     ; ret
```

Husk 自己在 `src/ios-jit/husk-brk.S` 中实现这些，并汇编出逐字节相同的编码。被复现的是到
StikDebug 的*接口*——brk 立即数和 x16 命令号，这些在 StikDebug 自己的 AGPL JavaScript 中
都有明白的文档——而不是任何人的独创性表达。完全由一个外部协议规定的三对指令，
不构成有意义的作者性贡献。

这也是更好的工程做法。去掉这个框架，就移除了 `dlopen` 间接层，更重要的是移除了当初迫使其
惰性加载的那个 AMFI 失败模式：一个带有 entitlements 的嵌入式框架在侧载构建上会在启动时被拒绝
（"has entitlements but is not a main binary"），在 `main()` 之前的静态初始化阶段就把进程杀掉。

## 分发

- **公开源码仓库**，完整且可构建。当我们把一份 IPA 交到某人手里时，正是它满足
  GPLv2 §3。
- **IPA 版本**通过 AltStore / SideStore / TrollStore 侧载，与 AetherPS4 现有的发布方式一致。
- **不上 App Store。** 两个独立的拦路石，任何一条都足够：GPLv2 的条款与 App Store 的
  分发限制相冲突（早已定论的 VLC 问题），以及 Husk 根本上需要 `get-task-allow` 外加一个
  在运行时附加的外部调试器，而 App 审核不允许这样做。

## 打包的客户机镜像——唯一仍然悬着的一项

这一项推迟到 Phase 1，不在此作答，但不该被忘记：

- **Phase 0 的 Debian arm64 客户机**不进行再分发。构建时抓取它；它从不进入仓库或 IPA。
- **AOSP** 的用户空间是 Apache-2.0，但 **Husk 启动的那个 Linux 内核是 GPLv2**，
  这意味着发布一个内核二进制，就迫使我们也提供它的源码。锁定确切的内核 tag，
  并把源码链接放在镜像旁边。
- **Google Play Services 绝不能打包**，任务书已经这样声明——任务书是对的，
  这是一项许可上的禁止，而不只是复杂度上的论据。
