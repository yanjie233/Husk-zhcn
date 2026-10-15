# 补丁

## `husk-qemu-ios-jit.patch`

Husk 自己的。在 iOS 上把 `tcg/region.c` 的 split-W^X 分配器重定向到
`alloc_code_gen_buffer_splitwx_husk_ios()`，其可执行那一半取自 StikDebug 而不是
本地分配（TXM 禁止后者）。由 `scripts/integrate_husk.sh` 应用，同时把 `src/ios-jit/*`
复制进 QEMU 源码树。

GPL-2.0-or-later，与它所打补丁的文件一致。

## `husk-spirv-cross-zero-init-stride.patch`

Husk 自己的，针对 MoltenVK 锁定的那个 SPIRV-Cross 版本。当一个计算着色器的共享内存
带有零初始化器（DXVK 的 groupshared 变量）时，MSL 后端会用一个循环把它清零，而它把这个
循环的步长写成了 `gl_WorkGroupSize`，但该内置变量只有在着色器用到 WorkgroupSize 时才会被
声明。于是 Metal 编译失败，整条管线被丢弃。当没有该内置变量时，步长现在改由 LocalSize /
LocalSizeId 提供。由 `scripts/build_moltenvk_ios.sh` 应用。

Apache-2.0，与它所打补丁的文件一致。

## `qemu-10.0.12-utm.patch`、`pixman-0.38.0.patch`、`libslirp-v4.9.1.patch`

不是我们的。逐字取自 UTM 的 `patches/` 目录
（https://github.com/utmapp/UTM），vendor 进来是为了让构建在不 clone UTM 的情况下
也可复现。

这些是对 QEMU、pixman 和 libslirp 的补丁，因此它们携带的是这些项目的许可证，而不是
UTM 自己的 Apache-2.0——QEMU 那个补丁是 GPL-2.0。这个区别很重要：UTM 的*应用*代码是
Apache-2.0，与 GPLv2 不兼容，绝不能复制进 Husk。见
`docs/01-licensing.md`。

UTM 的构建脚本（`scripts/build_dependencies.sh`）——Husk 的
`scripts/build_ios.sh` 借用了它的工具链设置——采用 ISC 许可
（注明 Angelo Haller, 2014），因而是宽松型许可。
