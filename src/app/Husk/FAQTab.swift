// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The FAQ tab: common problems and what to do about them, so a user stuck on JIT or on an app
/// that will not open has an answer without leaving Husk.
struct FAQTab: View {
    @State private var query = ""

    private var sections: [FAQ.Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return FAQ.sections }
        return FAQ.sections.compactMap { s in
            let items = s.items.filter { $0.question.localizedCaseInsensitiveContains(q) || $0.answer.localizedCaseInsensitiveContains(q) }
            return items.isEmpty ? nil : FAQ.Section(title: s.title, symbol: s.symbol, items: items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { s in
                    Section {
                        ForEach(s.items) { item in FAQRow(item: item, expanded: !query.isEmpty) }
                    } header: {
                        Label(s.title, systemImage: s.symbol)
                    }
                }
                if sections.isEmpty {
                    Text("没有匹配“\(query)”的内容。打开 设置 › 关于 › 打开控制台，可查看 Husk 的运行情况。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("常见问题")
            .searchable(text: $query, prompt: "搜索问题")
        }
    }
}

private struct FAQRow: View {
    let item: FAQ.Item
    var expanded: Bool
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { open || expanded }, set: { open = $0 })) {
            Text(.init(item.answer))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        } label: {
            Text(item.question).font(.body.weight(.medium))
        }
    }
}

enum FAQ {
    struct Item: Identifiable { let question: String; let answer: String; var id: String { question } }
    struct Section: Identifiable { let title: String; let symbol: String; let items: [Item]; var id: String { title } }

    static let sections: [Section] = [
        Section(title: "JIT", symbol: "bolt.fill", items: [
            Item(question: "JIT 是什么，Husk 为什么需要它？",
                 answer: "Android 应用和游戏在运行时才编译，这需要既能写入又能执行的内存。"
                       + "iOS 只允许在有调试器附加到应用时这样做。开启 JIT 会短暂附加一个调试器。"
                       + "没有它，Husk 可以显示你的资料库，但无法启动 Android 或游戏。"),
            Item(question: "我该用哪种方式开启 JIT？",
                 answer: "• **iOS 27 或更高：** 设置 › JIT › 在此 iPhone 上配对。无需电脑。\n"
                       + "• **iOS 26：** 内置的 StikJIT，加上在电脑上生成的配对文件，以及 LocalDevVPN。\n"
                       + "• **更旧的 iOS，或运行在 LiveContainer 内的 Husk：** 使用 StikDebug 应用。\n"
                       + "• **用 TrollStore 安装：** 在 TrollStore 中打开它的 URL Scheme 设置。\n"
                       + "• **用 Dopamine 越狱：** 在越狱设置中为应用开启 JIT。"),
            Item(question: "StikJIT 提示无法连接，或开启 JIT 失败",
                 answer: "1. 确认 **LocalDevVPN** 已安装并连接。状态栏里应显示 VPN 图标。\n"
                       + "2. 必须开启 Wi-Fi，尽管数据不会离开你的 iPhone。\n"
                       + "3. 必须开启**开发者模式**（设置 › 隐私与安全性 › 开发者模式）。\n"
                       + "4. 首次使用时 Husk 会下载 Apple 的开发者磁盘映像，可能需要一分钟，请等它完成。\n"
                       + "5. 仍然失败？把 LocalDevVPN 关掉再打开，然后重新配对。"),
            Item(question: "开发者模式里没有“与 Husk 配对”",
                 answer: "先在 Husk 中点按 **开始配对**，并在询问时允许**本地网络**访问。如果之前拒绝过，"
                       + "到 设置 › 隐私与安全性 › 本地网络 › Husk 中开启。必须开启 Wi-Fi。"
                       + "还需先启用开发者模式，首次启用会重启 iPhone。"),
            Item(question: "我的配对文件失效了",
                 answer: "iPhone 的信任设置被重置后配对文件就会失效，有时 iOS 更新之后也会。"
                       + "重新生成一个；如果你是 iOS 27，也可以直接在 iPhone 上配对，再到 设置 › JIT 中重新导入。"),
            Item(question: "StikDebug 能打开，但 JIT 仍未开启",
                 answer: "单独打开 StikDebug，确认它已有你的配对文件，且 LocalDevVPN 已连接。"
                       + "把 StikDebug 更新到最新版本。Husk 会自己把脚本发给 StikDebug，所以无需在 StikDebug 里为 Husk 做任何配置。"),
            Item(question: "为什么我得再开一次 JIT？",
                 answer: "JIT 只在 Husk 运行期间有效。当 iOS 在后台关掉 Husk，或你把它划掉关闭，"
                       + "下次启动就得重新开启 JIT。用“在此 iPhone 上配对”或配对文件时只需点一下。"),
            Item(question: "不用 JIT 能用 Husk 吗？",
                 answer: "你可以浏览和导入应用，但任何 Android 内容都跑不起来。每个游戏和应用都需要 JIT。"),
        ]),
        Section(title: "Husk 本体", symbol: "app.badge", items: [
            Item(question: "Husk 完全打不开",
                 answer: "• **打开后立刻关闭：** 签名证书多半已过期。免费 Apple 账户只有 7 天有效期。"
                       + "用你的侧载工具重新签名或重装 Husk；应用和存档都会保留。\n"
                       + "• **“不受信任的开发者”：** 前往 设置 › 通用 › VPN 与设备管理，信任你的证书。\n"
                       + "• **要求开启开发者模式：** 到 设置 › 隐私与安全性 中开启。"),
            Item(question: "我玩游戏时 Husk 关掉了",
                 answer: "再次打开 Husk 会显示发生了什么，并给出一份可分享的报告。通常是游戏内存不足，"
                       + "或碰到了 Husk 尚不支持的东西。关掉其他应用；如果反复出现，就分享这份报告。"),
            Item(question: "怎么获取日志来反馈问题？",
                 answer: "在资料库中打开该应用的详情页，点按 **分享报告**。要拿 Husk 自己的日志，前往 "
                       + "设置 › 关于 › **打开控制台**。在那里开启**开发者信息**能看到更多细节。"),
            Item(question: "怎么更新 Husk？",
                 answer: "有新版本时 Husk 会告诉你。用原来的侧载工具把新 IPA 覆盖安装到旧版之上即可。"
                       + "资料库、应用和存档都会保留。"),
        ]),
        Section(title: "应用与游戏", symbol: "gamecontroller.fill", items: [
            Item(question: "应用打不开",
                 answer: "在资料库中打开它的详情页，Husk 会说明停止的原因：\n"
                       + "• **受保护的应用：** 它会检查自己是否运行在真实 Android 手机上，或使用了反作弊、DRM。Husk 不会绕过这些。\n"
                       + "• **CPU 指令集不对：** 该 APK 只有 32 位代码。请找 arm64（arm64-v8a）版本。\n"
                       + "• **应用不完整或缺少游戏数据：** 该 APK 需要分包文件或 OBB。请导入完整的 .apks、.xapk 或 .apkm。\n"
                       + "• **需要 Google：** 该应用需要 Google 账号，或 Husk 提供不了的 Play 服务。\n"
                       + "• **用到 Husk 还没有的东西：** 分享报告，好把它补上。"),
            Item(question: "屏幕一直黑着",
                 answer: "大型游戏首次启动要准备代码和数据，最多可能需要一分钟。"
                       + "之后如果还是黑的，关掉再打开一次；若毫无变化，就分享报告。"),
            Item(question: "修改版或重打包的 APK 会闪退",
                 answer: "APKVISION 之类的网站重打包时，常把应用代码换成自家的库，或加上防篡改检查，"
                       + "这些东西更容易出问题。试试开发者或 APKMirror 上的原始 APK。"),
            Item(question: "我可以导入哪些文件？",
                 answer: ".apk，以及分包形式的 .apks、.xapk 或 .apkm。可以共享给 Husk、从“文件”打开，或在资料库中点按 +。"),
            Item(question: "游戏运行很慢，或者手机发烫",
                 answer: "关掉其他应用，让手机降温。游戏是原生运行的，但有些活儿真实 Android 手机由硬件完成，这里却压在 CPU 上。"
                       + "低电量模式也会拖慢 Husk。"),
            Item(question: "能用手柄吗？",
                 answer: "能。在蓝牙设置里把它连到 iPhone，支持手柄的游戏就能识别到。"),
            Item(question: "游戏运行时能用 Husk 吗？",
                 answer: "在设置中开启 **在窗口中打开应用**。之后应用会开在一个窗口里，可以移动、缩放和最小化。"),
            Item(question: "Google 登录用不了",
                 answer: "Husk 没有 Google Play 服务，所以“使用 Google 登录”按钮可能失败。如果应用提供邮箱或其他登录方式，请改用它们。"),
        ]),
        Section(title: "存档与存储", symbol: "externaldrive.fill", items: [
            Item(question: "我的存档在哪？",
                 answer: "每个应用的数据都存在 Husk 内部。在应用详情页，**备份存档**把它们导出，**恢复存档**再把它们还原回来，"
                       + "也可以还原到另一台 iPhone。"),
            Item(question: "Husk 占了太多存储空间",
                 answer: "导入的应用和它们的数据都在 Husk 的文件夹里。到游戏详情页删掉不再玩的游戏。"
                       + "完整 Android 系统下载大约多出 2 GB，只有运行 Android 本身才用得上。"),
        ]),
        Section(title: "Android", symbol: "cpu", items: [
            Item(question: "应用和 Android 有什么区别？",
                 answer: "大多数应用和游戏直接跑在你的 iPhone 上，和原生应用一样。完整 Android 系统是另一个选项，"
                       + "更慢，供那些只能在真实 Android 里运行的东西使用。"),
            Item(question: "Android 启动要很久",
                 answer: "首次启动会下载 Android 镜像并冷启动，要花几分钟。"
                       + "之后 Husk 会恢复已保存的虚拟机，速度快得多。"),
        ]),
    ]
}
