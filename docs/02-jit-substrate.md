# JIT 底层机制：Husk 如何在 iOS 27 上拿到 W+X 内存

状态：**已通过源码阅读验证**（尚未在设备上验证）。
读过的源码，全部是本地 clone，2026 年 9 月：

- `~/Documents/Coding/StikDebug-PiP` — StikDebug @ `94bc9e8`，origin `github.com/StikDebug/StikDebug`
- `~/Documents/Coding/MeloNX-Source` — Ryujinx-on-iOS，附带 `BreakpointJIT.framework`
- `~/Documents/Coding/AetherCore4/aetherps4-public-release` — 用户本人的 shadPS4 iOS 移植，
  其 `src/core/ios/ios_jit_allocator.cpp` 中包含一套生产级、经设备验证的实现

## 为什么那些显而易见的路子是死路

`mmap(PROT_READ|PROT_WRITE|PROT_EXEC)` 对侧载的 iOS 应用不起作用。本可以允许它的
`dynamic-codesigning` entitlement，只对平台二进制，或在 TrollStore/越狱设备上才被尊重。
Hypervisor.framework 对第三方 iOS 应用根本不可用——由 UTM 自己的
`Documentation/Architecture.md` 证实——所以硬件虚拟化被排除在外，每一条客户机指令
都必须经过 TCG，这意味着我们需要一个 JIT，也就意味着我们需要可写且可执行的内存。

## TXM 改变了规则，而在 iOS 27 上它无处不在

Apple 的 Trusted Execution Monitor 取代了旧的、用于代码签名强制执行的页面保护方案。
StikDebug 的 `ProcessInfo+TXM.swift` 精确编码了哪些设备受影响：

- iOS 26：iPhone12,x / A14 一代及更新机型开启 TXM（`iPhone` 硬件版本 >= 14.2），iPad >= 14.5
- **iOS 27：除 `iPad8,11` / `iPad8,12` 之外的一切设备都开启 TXM**

Husk 的目标是 iOS 27（这里唯一安装的 SDK 是 iphoneos27.0），运行在较新的、大内存的
iPhone 上。这些设备里的每一台都受 TXM 强制约束。所以与 TXM 兼容的路径是*唯一*的路径——
那套更老的"只要被调试了就把区域标记成 RWX"的把戏，不是一个可以留在手边备用的方案。

## 机制：用断点搭出来的 RPC 信道

应用无法给自己授予可执行内存。*附加在它身上的调试器*可以。于是应用请调试器来做这件事，
而这条请求信道就是 `brk` 指令。

`BreakpointJIT.framework` 导出三个 `naked` 函数——除了一条 `brk` 和一条 `ret` 之外什么都没有：

```c
void* BreakGetJITMapping(void *addr, size_t len);  // brk #0xf00d, x16 = 1
void  BreakJITDetach(void);                        // brk #0xf00d, x16 = 0
void* BreakMarkJITMapping(size_t bytes);
```

StikDebug 通过 debugserver/gdb-remote 协议附加，并运行一段 JavaScript 脚本
（`StikDebug/Scripts/universal.js`；MeloNX 内嵌了一份 base64 副本，此处解码到
`research/decoded/stikdebug_jit26_universal.js`）。该脚本就是一个朴素的断点分发循环：

1. `vAttach;<pid hex>`
2. 循环：`c`（continue）→ 目标陷入 → 解析 stop reply 中的 `thread:`、`pc`（寄存器 20），
   以及 `x16`（寄存器 10）
3. 读取 `pc` 处的 4 字节，把 `brk` 立即数提取为 `(instr >> 5) & 0xFFFF`
4. 按立即数分发，然后 `P20=<pc+4>` 跳过该 `brk`，再继续

命令号通过 **x16** 送达，参数在 **x0/x1**，返回值在恢复执行之前写回
**x0**——一个系统调用 ABI，只不过"内核"是 USB 线另一端的一个 JavaScript 解释器。

### 真正要紧的那个：`JIT26PrepareRegion`（x16 = 1）

```
x0 = 0, x1 = size   ->   returns an executable region in x0
```

两步，而第二步是不显然的那一步：

```js
let requestRXResponse = send_command(`_M${x1.toString(16)},rx`);   // allocate RX in the inferior
jitPageAddress = BigInt(`0x${requestRXResponse}`);
let prepareJITPageResponse = prepare_memory_region(jitPageAddress, x1);
send_command(`P0=${...jitPageAddress...};thread:${tid};`);          // hand the address back
```

`_M<size>,rx` 是 debugserver 的数据包，含义是"在被调试进程中按这些权限分配内存"。
这给我们一个 R-X 区域。

`prepare_memory_region` 是原生实现的（`JSSupport/JSDebugSupport.swift` →
`handleJITPageWrite`），它所做的全部事情就是，**对区域中每一个单独的 16 KiB 页面**，
发送一个 gdb-remote 的 `M<addr>,1:69` 数据包——经由调试器，向该页面写入一个字节的 `0x69`：

```swift
private let jitPageSize: UInt64 = 16_384
// builds "$M<9 hex digits>,1:69#<cksum>" per page, flushed 128 commands per batch
```

这就是全部的诀窍。调试器向它所控制的一个进程的可执行页面里写入，是被允许的操作，
而这样做会把每个页面都逼进一种状态，使得应用此后可以自己往里写。每个页面都必须被单独触碰；
没被触碰过的页面保持只读。

### 写入代码：本地 `vm_remap`，不涉及调试器

RX 区域准备好之后，应用为*同一批物理页*造出自己的可写别名，此后再也不需要调试器。摘自
`ios_jit_allocator.cpp`：

```cpp
vm_remap(mach_task_self(), &rw, bytes, 0, VM_FLAGS_ANYWHERE,
         mach_task_self(), (vm_address_t)rx, /*copy=*/FALSE,
         &cur_prot, &max_prot, VM_INHERIT_NONE);
vm_protect(mach_task_self(), rw, bytes, FALSE, VM_PROT_READ | VM_PROT_WRITE);
```

结果是：`rw_addr` 和 `rx_addr` 是两个由同一组物理页支撑的虚拟地址。经由 `rw` 发射代码，
经由 `rx` 执行，两者之间在 `rx` 那一侧调用 `sys_icache_invalidate`。这是教科书式的
split-W^X，而且——对我们来说很重要——它正是 QEMU 的 TCG 已经期待的那种*确切*形态。

注意 `mach_vm.h` 在 iOS SDK 中不可用；改用经典的 `vm_map.h` API，在 64 位 Darwin 上两者等价，
因为 `vm_address_t` 是指针宽度。

## 塑造 Husk 整体设计的那条约束

**分配实际上是一次性的。** 设置完成后，应用调用 `BreakJITDetach()`
（`brk #0xf00d`，x16 = 0 → gdb `D`），调试器消失，`BreakGetJITMapping` 不再被受理。
更糟的是，一个未被受理的 `brk` 不是一次返回错误的失败调用——它是会杀死进程的
真正 `SIGTRAP`。`ios_jit_allocator.cpp` 带着一个 thread-local 的
`g_expecting_jit_mapping_trap` 标志，纯粹是为了让信号处理器能把"StikDebug 这次漏掉了"
与真正的断点区分开，并合成一个 `nullptr` 返回而不是死掉；MeloNX 在
`JIT26Breakpoint.swift` 中有同样的防御，安装的 `SIGTRAP`/`SIGBUS` 处理器只做
`pc += 4; x0 = 0`。

StikDebug 也可能在会话中途被 iOS 的后台唤醒速率限制器杀掉——AetherPS4 的源码记录了
一次 Console.app 抓取，正是一次 "cpulimit violation"。

于是规则是（与这位用户其他项目上的既定指导一致）：**一次性把一处分配的尺寸定到足以证明够用，
绝不围绕"再拿一次"来做设计。**

把尺寸定大确实有实实在在的代价。`prepare_memory_region` 每个 16 KiB 页面经 USB 发送一个数据包，
每条命令还要读一次响应：

| 区域 | 16 KiB 页面数 | `M` 数据包数 |
|---|---|---|
| 256 MiB | 16,384 | 16,384 |
| 512 MiB | 32,768 | 32,768 |
| 1 GiB | 65,536 | 65,536 |
| 2 GiB | 131,072 | 131,072 |

这是附加延迟与 JIT 余量之间的一条直接权衡曲线，也是在设备上第一个要测量的东西。

## 为什么它与 QEMU 配合得出奇地好

QEMU 的 TCG **在初始化时分配一次**其翻译缓冲区，尺寸由 `-accel tcg,tb-size=N` 决定，
而且它内部已经支持 split-W^X（`tcg_splitwx_diff`——RW 和 RX 两半之间是一个固定的指针差，
恰好就是 `vm_remap` 产生的东西）。QEMU 从不需要让缓冲区变大；满了就冲刷并复用它。
一个一次性、固定大小代码缓存的 JIT，正是这套底层机制恰好能支撑的那类 JIT，
这也是 QEMU 而不是某个按需 mmap 的东西成为此处正确引擎的很大一部分原因。

因此集成工作的面很窄：把 QEMU 自己的代码缓冲区分配器换成一个调用
`BreakGetJITMapping` + `vm_remap` 的分配器，让 TCG 现有 splitwx 机制的其余部分原样工作。

## 打包上的坑，代价高昂地学来的

`BreakpointJIT.framework` 绝**不能**被 Xcode target 链接，也绝不能出现在
`LC_LOAD_DYLIB` 中。如果 dyld 在启动时自动加载它，AMFI 会在侧载/免费签名构建上拒绝它——
"has entitlements but is not a main binary"——进程会在 `main()` 之前的静态初始化中
`SIGABRT`。用一个 Run Script 阶段（而不是 "Embed & Sign"）把它复制进 bundle，
再惰性地 `dlopen` 它：

```c
dlopen("@executable_path/Frameworks/BreakpointJIT.framework/BreakpointJIT", RTLD_NOW | RTLD_LOCAL);
```

## 必需的 entitlements

从随产品发布的 `AetherPS4-iOS.entitlements` 确认：

```xml
<key>get-task-allow</key><true/>                                  <!-- lets StikDebug attach -->
<key>dynamic-codesigning</key><true/>                             <!-- honoured only on TrollStore/JB -->
<key>com.apple.developer.kernel.increased-memory-limit</key><true/>
```

第三个是让一个数 GB 大的 Android 客户机在 jetsam 面前活得下来的关键，
而它在这个用户的侧载构建里已经被证明可用。
