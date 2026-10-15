# 内置 StikJIT 与设备端配对

Husk 需要一个已附加的调试器才能在 iOS 上拿到可执行内存（[02-jit-substrate.md](02-jit-substrate.md)）。这个调试器可以是 StikDebug 应用，也可以是 Husk 自带的内置 StikJIT 助手。两者都会对正在运行的 Husk 进程执行同一份打包的 `husk-jit.js`。

## 选择方式

**Settings › JIT & sideload › Method**：

- **Automatic**（默认）：装了 StikDebug 就用 StikDebug，其次是 TrollStore，否则用内置 StikJIT。失败后 Husk 不会自行切换方式；错误信息会告诉你该修什么。
- **StikDebug**：Husk 一直使用的 URL scheme 交接方式。
- **TrollStore**：请求 TrollStore 开启 JIT（`apple-magnifier://enable-jit`），适用于通过 TrollStore 安装的 Husk。
- **内置 StikJIT**：不需要第二个应用。需要 iOS 26、LocalDevVPN，以及这台 iPhone 的远程配对文件——在 iOS 27 上 Husk 自己就能生成它。

在设备上配对或导入配对文件，都会选中内置 StikJIT。

## 引导流程

首次运行的设置有一个 **Turn on JIT** 页面，**Settings › JIT & sideload › Set up JIT** 会打开同一个引导流程。在所选方式尚未配置时，点 Start 且当前没有 JIT，也会打开它。它提供三条入口：

1. **在这台 iPhone 上配对**（iOS 27）。点 **Start pairing** 并允许本地网络访问，打开 **Settings › Privacy & Security › Developer Mode**，滚动到底部，点 **Pair with Husk**，再输入 Husk 显示的代码。该代码也会出现在 iOS 的后台任务横幅中以及一条通知里。
2. **使用配对文件**，在电脑上按 [StikDebug pairing-file guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md) 制作。
3. **使用 StikDebug**，流程以选中 StikDebug 结束。
4. **使用 TrollStore**，同样地，适用于通过 TrollStore 安装的 Husk。

前两条会继续走相同的两个步骤：

- **Connect LocalDevVPN**。连接成功后 LocalDevVPN 通过 `husk://` URL scheme 回到 Husk。
- **Check setup**，它会检查 VPN，并下载、挂载、校验与之匹配的 Developer Disk Image，然后 **Enable JIT**。

如果设备重置了连接，它就不再接受该配对（每次设备端配对都会取代上一次），因此引导流程会提供 **Pair again**。如果联系不到设备，它会提供 LocalDevVPN。一次 iOS 更新之后，**Reset Developer Disk Image** 可以清掉过期的 DDI 数据。

## 它如何工作

### 设备端配对

iOS 27 可以与它在本地网络上发现的电脑配对，由 iPhone 一侧发起。Husk 为自己的 iPhone 扮演那台电脑：

- `libhusk_rppairing.a`（`src/rppairing-ios`，由 `scripts/build_rppairing_ios.sh` 构建）封装 [idevice](https://github.com/jkcoxson/idevice) 的 `PairableHost`。它监听一个 TCP 端口并执行配对。
- `JITPairing.swift` 通过 mDNSResponder 把该端口以 `_remotepairing-pairable-host._tcp` Bonjour 服务的形式广播出去，因此只需要"本地网络"权限，不需要 multicast entitlement。
- 用户停留在 Settings 期间，Husk 靠一个 iOS 26 的持续处理任务（`<bundle id>.pairing.session`）保持运行。如果 iOS 拒绝它——通常是因为某个侧载工具改了 bundle identifier——Husk 在后台只有通常那约 30 秒，引导流程会明说这一点。五分钟仍未完成的配对会被停止。

每一次配对都会在同一个标识符下生成一个新的主机密钥，因此 iPhone 会用它对 Husk 的最新记录替换掉早先的记录，只有最新的那份配对文件才有效。

配对文件存放在 `Documents/StikJIT/pairingFile.plist`，通过 Finder 的文件共享可见。它对设备敏感：Husk 只把它发送给自己的助手进程。

### 助手

一个进程无法同步地调试自己，所以 StikJIT 运行在 `HuskJITHelper` 中，这是一个嵌在 `Husk.app/PlugIns/HuskJITHelper.appex` 里的应用扩展。它是一个位于 `com.apple.ar.viewer` 扩展点上的经典应用扩展，从不在任何地方被展示，Husk 通过 `NSExtension` 按其 bundle 标识符启动它，就像 LiveContainer 启动它的 LiveProcess 那样。Husk 在扩展请求（`HuskJITMessages.swift`）中以 JSON 形式把自己的 PID、配对文件和 `husk-jit.js` 发送给它。StikJIT.framework 位于 `Husk.app/Frameworks`，助手就从那里加载它。助手用 `forceScript` 调用 StikJIT，并在脚本受理陷入请求期间保持附加。Husk 轮询 `CS_DEBUGGED`，随后以与 StikDebug 附加之后完全相同的方式认领自己的 JIT 区域，然后分离；正是那次分离结束了助手的请求。

### 构建

```
./scripts/build_rppairing_ios.sh   # needs rustup + `rustup target add aarch64-apple-ios`
./scripts/package_ipa.sh
```

`ci_build.sh` 两个都会跑。在 `src/rppairing-ios` 中运行 `cargo test` 会执行配对库的宿主机测试。

## 签名与安装

应用、`HuskJITHelper` 和 StikJIT.framework 必须一起签名，而且侧载工具必须保留应用扩展。如果做不到，就改用 StikDebug。

用用户自己的 Apple ID 签名的侧载工具（SideStore、AltStore、Plume、Impactor）会在 bundle 标识符后追加它们的 team ID。Husk 在运行时从 `PlugIns/HuskJITHelper.appex/Info.plist` 读取助手的标识符，所以这样能行。更早的一个助手是 ExtensionKit 扩展，通过一个以 Husk 原始标识符命名的扩展点被找到；改名后的安装会以 "Failed to add observer" 失败。

要在另一个 bundle 标识符下构建，请在 `src/app/project.yml` 中设置 `HUSK_BUNDLE_IDENTIFIER`。应用和助手（`<id>.JITHelper`）都会跟随它。

打包件的许可情况见 [01-licensing.md](01-licensing.md)。
