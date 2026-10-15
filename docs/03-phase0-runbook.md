# Phase 0 操作手册 —— 把它带上真机

"设备分界线"以下的一切都已构建，并且在能验证的地方已在宿主机上验证过。下面是剩下的部分，它需要手机。

## 已经被证明的

| 主张 | 是如何检查的 |
|---|---|
| QEMU + 依赖为 arm64-apple-ios 交叉编译 | 对 dylib 执行 `otool -l`：`platform 2`（iOS），minos 16.0，SDK 27.0 |
| QEMU 作为进程内库构建 | `libqemu-aarch64-softmmu.dylib` 导出 `qemu_init`、`qemu_main_loop`、`qemu_cleanup` |
| 应用能触达 Husk 的 JIT + 显示 API | 全部 9 个 `husk_*` 符号在 `nm -gU` 中显示为 `T` |
| brk 陷入序列是正确的 | `otool -tV` 输出与 BreakpointJIT.framework 逐字节一致 |
| 客户机在纯 TCG 下启动 | 已在宿主机上启动：Linux 6.18.35 约 5 秒进入用户空间 |
| 客户机给了我们一个帧缓冲和指针 | 宿主机 dmesg：`fb0: virtio_gpudrmfb`、`QEMU Virtio Tablet`、`QEMU Virtio Keyboard` |
| 应用编译、链接并打包成功 | `BUILD SUCCEEDED`；51 MB 的 bundle，含 dylib、客户机、着色器、脚本 |

## 在设备上测得（iPhone18,1，iOS 27.0，11.7 GB 内存）

首次成功的 JIT 启动：

```
#1: StikDebug attach probe OK (0xcccccccc690000e0)
#1: requesting execute-capable region, size=268435456 (256.0 MiB), attempt 1/3
#1: BreakGetJITMapping returned 0x115254000          <- 749 ms later
#1: dual mapping established: rw=0x125254000 rx=0x115254000 diff=-268435456
selftest: PASS -- executed generated code from the RX alias, got 42
```

| 测量项 | 数值 | 含义 |
|---|---|---|
| `BreakGetJITMapping`，256 MiB | **749 ms**（16,384 页） | 经调试器每页约 46 us。1 GiB 会花掉约 3 s，所以对 Android 来说 `tb-size` 还有实际的增长空间 |
| JIT 分配后的占用 | 274.9 MiB 物理内存 | 在 11.7 GB 面前这无关紧要；当初 `-m 1024` 背后的那份谨慎是不必要的 |
| `qemu_init` 之前的占用 | 13.9 MiB | 应用自身的开销可忽略 |
| 从探测到开始分配 | 80 ms | StikDebug 的往返很便宜 |

双映射的 `diff` 是负的（`rx` 位于 `rw` 下方），这没有问题——
`tcg_splitwx_diff` 是一个有符号偏移。

## 尚未被证明的，按它会出问题的顺序

1. **StikDebug 会受理我们的 `brk`。** 一切都建立在这之上。
2. **JIT 区域足够大，而且到得足够快。** 256 MiB 就是 16,384 次调试器往返。
3. **TCG 真的从 RX 别名里执行。** 如果页面准备静默失败，QEMU 会在第一次跳进生成代码时崩溃。
4. **jetsam 容忍这个占用。** 1 GiB 客户机 + 256 MiB JIT + QEMU 自身。
5. **帧到达 Metal，触摸到达客户机。**

## 运行它

```bash
./scripts/fetch_sources.sh
./scripts/build_ios.sh
./scripts/fetch_phase0_guest.sh
cd src/app && xcodegen generate
```

然后打开 `src/app/Husk.xcodeproj`，在 Husk target 上设置你的签名团队，构建到设备。如果你愿意，也可以像 AetherPS4 发布那样侧载 IPA。

在手机上：安装 StikDebug，启动 Husk，点 **Enable JIT with StikDebug**。
Husk 会把 JIT 脚本以内联方式交过去，所以 StikDebug 内部无需任何配置。它会附加、准备区域并重启 Husk；第二次启动应该就能发现 JIT 已生效并启动客户机。

## 怎么读发生了什么

一切都会落进**同一个按时间排序的文件**：`Documents/husk.log`。在其他任何东西运行之前，`HuskLog.start()` 就把 stdout 和 stderr 重定向进一个管道，并在自己的线程上持续排空它，于是 QEMU 的诊断、Husk 的 C 侧日志和 Swift 层全都按实际发生的顺序交织在一起——当问题变成"JIT 区域是不是在 TCG 试图使用它之前就建好了"时，这个顺序正是要紧的那个。

三种读取方式，按方便程度排列：

1. **在应用内。** 在设置页点 *View logs*，或在客户机运行后点右上角的放大镜按钮。它会实时 tail，并按来源着色（绿色 = JIT，青色 = 显示，黄色 = 客户机内核，红色 = 失败），分享按钮会同时导出 `husk.log` 和 `guest-serial.log`。
2. **Console.app**，连接设备后按 `subsystem:com.husk.app` 过滤。
3. **文件（Files）应用**——`UIFileSharingEnabled` 已设置，因此两个日志都能在 Husk 的 Documents 下看到。

### 客户机自己的内核控制台

`guest-serial.log` 是可获得的信息量最大的单一信号：如果客户机确实在执行翻译后的代码，它的内核会这么说。QEMU 通过一个文件 chardev 写入它（不是 stdio，那会让 QEMU 去抓一个 iOS 上并不存在的 stdin 并在初始化时失败），一个 tail 线程在内容出现时把它折回 `husk.log`，所以它既是一个独立文件，也是统一时间线的一部分。

### 要找的顺序

```
[boot ] device      : iPhoneNN,N
[boot ] TXM expected: YES
[husk-jit] trap guard installed (SIGTRAP, SIGBUS)
[husk-jit] #1: StikDebug attach probe OK (0xe0000069)
[husk-jit] #1: requesting execute-capable region, size=268435456 (256.0 MiB), attempt 1/3
[husk-jit] #1: BreakGetJITMapping returned 0x...
[husk-jit] #1: dual mapping established: rw=0x... rx=0x... size=268435456 diff=...
[husk-jit] footprint[after-jit-alloc]: phys=... MiB
[husk-jit] selftest: RX alias reflects RW writes (0x52800540 0xd65f03c0) -- aliasing OK
[husk-jit] selftest: CALLING generated code at 0x... 
[husk-jit] selftest: PASS -- executed generated code from the RX alias, got 42. JIT is genuinely live.
[husk-dpy] init: console[0]=0x... graphic=1
[husk-dpy] gfx_switch gen=1 surface=0x... 1280x800 stride=5120 bpp=32
[guest ] Booting Linux on physical CPU 0x0000000000
```

### 自测那一行才是关键

`husk_jit_selftest()` 经由 RW 别名写入 `movz w0, #42 ; ret`，在 RX 别名上冲刷 icache，
读回来以证明两个视图共享同样的页面，然后**调用它**。拿回 42 意味着 JIT 是真的能用——
而不是"StikDebug 返回了一个地址"，那是个弱得多的说法。

这一点很重要，因为它抓到的那种失败否则是看不见的。如果 `_M,rx` 分配了内存，
而 `prepare_memory_region` 从不遍历那些页面，那么这次分配看起来完全成功，
而且什么都不会出错，直到 TCG 分支进生成的代码——届时应用会死在模拟器深处、毫无上下文。
自测把那个失败挪到一行有标签的输出上、发生在一个已知的时刻，并且拒绝把区域交给 TCG，
而不是让 QEMU 在上面崩掉。

## 失败模式，以及每一种意味着什么

**探测返回 `0x0` 而不是 `0xe0000069`。** StikDebug 根本没附加，或者附加了又在我们开口之前就分离了。不是 Husk 的 bug——检查 StikDebug 是否真的运行了脚本。

**探测没问题，`BreakGetJITMapping` 三次都返回 0。** StikDebug 附加了，但没有受理 `x16=1` 的 `brk #0xf00d`。最可能是它运行的脚本不是 universal 那个；检查它日志里收到的脚本文本。

**`selftest: FAIL -- RX alias does not reflect RW writes`。** `vm_remap` 成功了，但两个映射并不是由同一批页面支撑的。错在双映射这一步，而不是 StikDebug。

**分配和回读都正常，然后应用死在 `selftest: CALLING`。** 那些页面从未被真正准备好——`_M,rx` 给了我们内存，但逐页的 `M<addr>,1:69` 写入没有发生。对照 StikDebug 自己的日志确认。

**附加耗时非常久。** 预期之中，而且它随 `tb-size` 线性增长。把 `QemuRunner.phase0Arguments()` 中的 `tb-size=256` 降到 `128` 并对比；这是真机上第一个要调的数字。

**应用被杀掉且没有崩溃日志。** jetsam。`footprint[...]` 行给每个阶段都标了界——把最后一个与设备的限制对比，并先把 `-m 1024` 调小，因为 Alpine 根本用不了那么多。

**黑屏，没有崩溃。** 看 `[husk-dpy] init:`——如果它显示 `qemu_console_lookup_by_index(0) returned NULL`，那就没有可附着的图形控制台，下游一切都不会工作。如果它注册正常但始终不出现 `gfx_switch`，说明客户机没有在驱动 GPU。如果 `gfx_switch` 出现了而屏幕仍是黑的，问题在 Metal 那一侧。

**客户机早早死掉且没有有用信息。** 在设置页把详细级别切到 **Firehose**（`-d ...,int,exec,in_asm`）并复现。它会记录每一条被翻译的指令——每分钟数 GB——所以只在抓最初几秒内的崩溃时使用它，但对于"它在第一个 basic block 的第三条指令就死了"这种情况，没有别的办法可用。

## 有意推迟的

- `tb-size` 在测量之前只是个猜测。它是 Phase 0 里最重要的一个数字，因为在 StikDebug 分离之后它就无法再重新商量了。
- `-cpu cortex-a72` 是一个 ARMv8.0 基线。Android 可能需要 ARMv8.2；那是 Phase 1 的问题。
- 目前还没有任何东西调用 `husk_ios_jit_detach()`。在 Phase 0 里让调试器一直开着不花任何代价，并且在尺寸仍在摸索阶段时保留第二次分配的选项。
