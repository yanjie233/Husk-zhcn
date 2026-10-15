// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Settings, as the iOS Settings app lays them out: a card for the app up top, then groups of rows that each
/// push a page of their own. What belongs to the app, what belongs to the emulator, and what the thing is.
struct SettingsTab: View {
    @AppStorage(AppWindows.defaultKey) private var multitask = false
    @AppStorage(CompatibilityStore.askKey) private var askCompat = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AboutSettings() } label: { appCard }
                }

                Section {
                    row(JITSettings(), "bolt.fill", .yellow, "JIT 与侧载", "内置 StikJIT——推荐方式")
                } header: {
                    Text("JIT")
                } footer: {
                    Text("Android 和转译层游戏需要 JIT。Husk 内置的 StikJIT 无需电脑即可开启。")
                }

                Section("通用") {
                    row(DiscoverView(), "sparkle.magnifyingglass", .mint, "发现", "在 F-Droid 等仓库中查找应用")
                    row(LibrarySettings(), "square.grid.2x2.fill", .blue, "资料库", "你的应用和它们的图标")
                    row(PerformanceSettings(), "speedometer", .orange, "性能", "渲染与声音")
                    row(AppearanceSettings(), "paintbrush.fill", .pink, "外观", "浅色或深色、强调色、应用图标")
                }

                Section {
                    Toggle(isOn: $multitask) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("在窗口中打开应用")
                                Text("应用运行时也能使用 Husk").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.purple.gradient)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "macwindow.on.rectangle")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                } header: {
                    Text("多任务")
                } footer: {
                    Text("应用和游戏会开在窗口里，可以移动、缩放，或最小化到 Dock，和 LiveContainer 的多任务一样。"
                       + "每个应用都能在自己的设置中覆盖这一项。")
                }

                Section {
                    Toggle(isOn: $askCompat) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("询问游戏运行情况")
                                Text("玩过之后，每个游戏每次更新询问一次").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.green.gradient)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "list.bullet.clipboard")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                    Link(destination: CompatibilityStore.site) {
                        Label("兼容性列表", systemImage: "safari")
                    }
                } header: {
                    Text("兼容性")
                } footer: {
                    Text("游戏详情页和商店会显示每个应用对所有人的运行情况，数据来自 antiweb.lol。你的报告会连同"
                       + "设备、iOS 版本、Husk 构建和 JIT 方式一起提交到那里。")
                }

                Section("模拟器") {
                    row(InputSettings(), "hand.tap.fill", .indigo, "输入", "屏幕、触摸、键盘")
                    row(NetworkSettings(), "globe", .green, "网络", "互联网与已保存的会话")
                    row(SavedMachineSettings(), "externaldrive.fill", .teal, "已保存的机器", "快照与自动保存")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
        }
    }

    private var appCard: some View {
        HStack(spacing: 14) {
            HuskMark(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Husk").font(.title3.weight(.semibold))
                Text("版本 \(Bundle.main.version) · \(Bundle.main.commit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func row<D: View>(_ destination: D, _ icon: String, _ tint: Color,
                              _ title: String, _ subtitle: String) -> some View {
        NavigationLink { destination } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } icon: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
            }
        }
    }
}

/// A Form, as the system draws one.
private struct HuskForm: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func huskForm() -> some View { modifier(HuskForm()) }
}

// MARK: - Library

struct LibrarySettings: View {
    @ObservedObject private var host = AndroidHost.shared
    @State private var working = false

    var body: some View {
        Form {
            Section {
                DetailRow(label: "应用", value: "\(host.packages.count)", mono: false)
                DetailRow(label: "含图标",
                          value: "\(host.packages.filter { $0.iconPath != nil }.count)",
                          mono: false)
            } footer: {
                Text("这份列表会写入磁盘，所以 Android 还没启动完就"
                   + "已经显示在屏幕上了。")
            }

            Section {
                Button {
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label(working ? "正在刷新…" : "从 Android 刷新",
                          systemImage: "arrow.clockwise")
                }
                .disabled(working || !host.isReady)

                Button {
                    AndroidHost.forgetIcons()
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label("重新获取图标", systemImage: "photo.on.rectangle")
                }
                .disabled(working || !host.isReady)
            } footer: {
                Text("名称和图标来自 Android 自带的启动器，用的是它"
                   + "绘制的那一套。重新获取会丢弃 Husk 的副本并"
                   + "再问一次。")
            }
        }
        .huskForm()
        .navigationTitle("资料库")
    }
}

// MARK: - Performance

struct PerformanceSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var gpuMode =
        UserDefaults.standard.object(forKey: "husk.gpuMode") as? Bool ?? true
    @State private var sound = UserDefaults.standard.bool(forKey: "husk.sound")
    @State private var soundDevice =
        UserDefaults.standard.object(forKey: "husk.soundDevice") as? Bool ?? true

    var body: some View {
        Form {
            Section {
                Picker("渲染器", selection: $gpuMode) {
                    Text("GPU").tag(true)
                    Text("CPU").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: gpuMode) { v in
                    UserDefaults.standard.set(v, forKey: "husk.gpuMode")
                    HuskLog.log("ui", v ? "GPU renderer selected" : "CPU renderer selected")
                }
            } header: {
                Text("渲染器")
            } footer: {
                Text(gpuMode
                     ? "Android 通过 Metal 使用真实 GPU 绘制——帧率约为"
                     + "四倍。这是默认选项。"
                     : "每个像素都由模拟的 CPU 绘制。慢得多，只有"
                     + "GPU 出问题时才值得选它。")
            }

            Section {
                DetailRow(label: "帧率",
                          value: runner.fps > 0
                                 ? String(format: "%.0f fps", runner.fps) : "—")
                DetailRow(label: "客体屏幕",
                          value: "\(QemuRunner.lastGuestRes.w)×\(QemuRunner.lastGuestRes.h)")
            } header: {
                Text("当前")
            }

            Section {
                Toggle("声音", isOn: $sound)
                    .onChange(of: sound) { v in
                        UserDefaults.standard.set(v, forKey: "husk.sound")
                        HuskLog.log("ui", v ? "sound on" : "sound off")
                    }
                if sound {
                    Toggle("挂载声音设备", isOn: $soundDevice)
                        .onChange(of: soundDevice) { v in
                            UserDefaults.standard.set(v, forKey: "husk.soundDevice")
                        }
                }
            } header: {
                Text("声音")
            } footer: {
                Text("添加一个声音设备。挂载期间无法保存 Android——"
                   + "QEMU 拒绝对带声音设备的机器做快照——因此每次"
                   + "启动都要冷启动。无论开关如何切换，都要付出一次"
                   + "冷启动的代价。")
            }
        }
        .huskForm()
        .navigationTitle("性能")
    }
}

// MARK: - Input

struct InputSettings: View {
    @State private var landscapeGuest =
        UserDefaults.standard.bool(forKey: "husk.landscapeGuest")
    @State private var customRes = UserDefaults.standard.bool(forKey: "husk.customRes")
    @State private var widthText = InputSettings.stored("husk.resWidth", 720)
    @State private var heightText = InputSettings.stored("husk.resHeight", 1280)

    /// Sizes worth offering without typing. Deliberately short: these are the
    /// shapes a phone guest is actually run at, not a catalogue of every panel
    /// ever made.
    private static let presets: [(name: String, w: Int, h: Int)] = [
        ("小屏 — 360 × 800", 360, 800),
        ("高清 — 720 × 1280", 720, 1280),
        ("全高清 — 1080 × 1920", 1080, 1920),
        ("横屏高清 — 1280 × 720", 1280, 720),
        ("平板 — 1280 × 800", 1280, 800),
    ]

    private static func stored(_ key: String, _ fallback: Int) -> String {
        let v = UserDefaults.standard.integer(forKey: key)
        return String(v > 0 ? v : fallback)
    }

    /// What the typed numbers actually come to, or nothing if they are not a
    /// size the guest can be given.
    private var effective: (w: Int, h: Int)? {
        QemuRunner.validResolution(w: Int(widthText) ?? 0, h: Int(heightText) ?? 0)
    }

    var body: some View {
        Form {
            Section {
                Picker("屏幕", selection: $landscapeGuest) {
                    Text("竖屏").tag(false)
                    Text("横屏").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(customRes)
                .onChange(of: landscapeGuest) { v in
                    UserDefaults.standard.set(v, forKey: "husk.landscapeGuest")
                    HuskLog.log("ui", v ? "guest panel will be landscape"
                                        : "guest panel will be portrait")
                }
            } header: {
                Text("屏幕")
            } footer: {
                Text(customRes
                     ? "自定义分辨率会自行决定屏幕形状，开启期间这一项"
                     + "不起作用。想要横屏就填一个更宽的尺寸。"
                     : "Android 一旦运行就无法改变屏幕方向，所以"
                     + "横屏游戏在竖屏上会被上下加黑边挤成一条，看起来"
                     + "很小。只有以横屏创建，它才能铺满屏幕——"
                     + "竖屏应用则改为自己加黑边。代价是一次冷启动。")
            }

            Section {
                Toggle("自定义分辨率", isOn: $customRes)
                    .onChange(of: customRes) { v in
                        UserDefaults.standard.set(v, forKey: "husk.customRes")
                        store()
                        HuskLog.log("ui", v ? "custom resolution on: "
                                            + "\(widthText)x\(heightText)"
                                            : "custom resolution off")
                    }

                if customRes {
                    Picker("预设", selection: Binding(
                        get: { presetIndex },
                        set: { i in
                            guard i >= 0, i < Self.presets.count else { return }
                            widthText = String(Self.presets[i].w)
                            heightText = String(Self.presets[i].h)
                            store()
                        })) {
                        ForEach(0..<Self.presets.count, id: \.self) { i in
                            Text(Self.presets[i].name).tag(i)
                        }
                        Text("自定义").tag(-1)
                    }

                    HStack {
                        Text("宽度")
                        Spacer()
                        TextField("720", text: $widthText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: widthText) { _ in store() }
                    }
                    HStack {
                        Text("高度")
                        Spacer()
                        TextField("1280", text: $heightText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: heightText) { _ in store() }
                    }

                    if let size = effective {
                        DetailRow(label: "Android 实际使用",
                                  value: "\(size.w) × \(size.h)")
                    } else {
                        Text("宽高都必须在 240 到 2560 之间。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                DetailRow(label: "当前运行", value: running)
            } header: {
                Text("分辨率")
            } footer: {
                Text("屏幕是在机器启动时构建的，改一次就要冷启动一次，"
                   + "而且下一次保存会覆盖按旧尺寸保存的机器——改回去"
                   + "又要一次。尺寸会取整到 8 的倍数。越大越慢："
                   + "每个像素都由一台模拟的手机绘制。Android 的密度"
                   + "不随屏幕变化，所以更大的屏幕显示的内容更多，"
                   + "而不是字更大。")
            }

            Section {
                Text("触摸始终开启。键盘和旋转控件在客体屏幕"
                   + "底部的胶囊条里；手柄和指针还没有接通。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("操控")
            }
        }
        .huskForm()
        .navigationTitle("输入")
    }

    /// The panel the guest actually has, which only means anything while there
    /// is a guest: the stored value is last launch's until one starts.
    private var running: String {
        guard QemuRunner.shared.isRunning else { return "未启动" }
        return "\(QemuRunner.lastGuestRes.w) × \(QemuRunner.lastGuestRes.h)"
    }

    /// Which preset the typed numbers are, if any.
    private var presetIndex: Int {
        guard let size = effective else { return -1 }
        return Self.presets.firstIndex { $0.w == size.w && $0.h == size.h } ?? -1
    }

    private func store() {
        UserDefaults.standard.set(Int(widthText) ?? 0, forKey: "husk.resWidth")
        UserDefaults.standard.set(Int(heightText) ?? 0, forKey: "husk.resHeight")
    }
}

// MARK: - Network

struct NetworkSettings: View {
    @State private var keepNetwork =
        UserDefaults.standard.object(forKey: "husk.keepNetwork") as? Bool ?? true

    var body: some View {
        Form {
            Section {
                Toggle("保存时保留网络", isOn: $keepNetwork)
                    .onChange(of: keepNetwork) { v in
                        UserDefaults.standard.set(v, forKey: "husk.keepNetwork")
                    }
            } footer: {
                Text(keepNetwork
                     ? "保存会关掉应用，但让 Android 的框架继续运行，"
                     + "所以恢复之后网络依然可用。"
                     : "保存时也会停掉框架。这样会清空所有 GPU 资源，"
                     + "更稳定——但网络可能要到冷启动之后才恢复。")
            }

            Section {
                Text("Android 通过 QEMU 自己网络上的一块虚拟网卡"
                   + "访问互联网。你手机网络中的任何设备都看不到客体，"
                   + "客体也看不到它们。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("连接方式")
            }
        }
        .huskForm()
        .navigationTitle("网络")
    }
}

// MARK: - JIT and sideloading

struct JITSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var autoStart = Onboarding.autoStart
    @AppStorage(JITCoordinator.autoEnableKey) private var autoJIT = false
    @State private var keepAttached = JITBootstrap.keepDebuggerAttached

    private var pairingLabel: String {
        switch jit.pairingSource {
        case .onDevice: return "已在此设备上配对"
        case .imported: return "已导入配对文件"
        case nil: return "尚未设置"
        }
    }

    var body: some View {
        Form {
            Section {
                JITCard()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                Picker("方式", selection: $jit.method) {
                    ForEach(JITMethod.allCases) { Text($0.title).tag($0) }
                }
                DetailRow(label: "StikDebug",
                          value: JITBootstrap.isStikDebugInstalled ? "已安装" : "未找到", mono: false)
                DetailRow(label: "TrollStore",
                          value: JITBootstrap.isTrollStoreInstalled ? "已安装" : "未找到", mono: false)
                DetailRow(label: "用 TrollStore 安装",
                          value: JITBootstrap.isInstalledWithTrollStore ? "是" : "否", mono: false)
                DetailRow(label: "越狱",
                          value: JITBootstrap.debuggedAtLaunch ? "已允许应用使用 JIT"
                               : JITBootstrap.isJailbroken ? "已检测到" : "未检测到", mono: false)
                DetailRow(label: "内置配对", value: pairingLabel, mono: false)
                Button {
                    jit.showSetup = true
                } label: {
                    Label("设置 JIT", systemImage: "wand.and.stars")
                }
            } header: {
                Text("其他开启 JIT 的方式")
            } footer: {
                Text(jit.method == .automatic
                     ? jit.automaticDescription + " 内置 StikJIT 需要 iOS 26、LocalDevVPN 和一份"
                       + "配对文件；在 iOS 27 上 Husk 可以自己生成配对文件。"
                     : HuskBuiltInJIT.unavailableReason ?? "内置 StikJIT 需要 LocalDevVPN 和一份配对"
                       + "文件；在 iOS 27 上 Husk 可以自己生成配对文件。")
            }

            Section {
                DetailRow(label: "调试器",
                          value: JITBootstrap.isDebuggerAttached ? "已附加" : "未附加",
                          mono: false)
                DetailRow(label: "可执行内存",
                          value: JITBootstrap.isLive ? "已获取" : "未申请", mono: false)
                // The two routes, named separately. Either one is enough, and
                // when someone reports "JIT does not work" these two rows are
                // the whole diagnosis.
                DetailRow(label: "陷阱响应器",
                          value: husk_ios_jit_self_route() != nil ? "不需要"
                               : JITBootstrap.prewarmed ? "正在响应" : "无响应",
                          mono: false)
                if let route = husk_ios_jit_self_route() {
                    DetailRow(label: "由 Husk 提供",
                              value: String(cString: route) == "MAP_JIT" ? "MAP_JIT（TrollStore 权限）" : "普通内存（已调试或已越狱）",
                              mono: false)
                }
                // Cached answer only: running the probe from a view body
                // could freeze the app (see JITBootstrap.mapJITWorks).
                DetailRow(label: "MAP_JIT",
                          value: JITBootstrap.deviceEnforcesTXM ? "未使用（TXM）"
                               : JITBootstrap.mapJITResult.map { $0 ? "可执行" : "被拒绝" }
                                 ?? "未测试",
                          mono: false)
                DetailRow(label: "设置后的调试器",
                          value: JITBootstrap.detached ? "已分离" : "已附加",
                          mono: false)
                if let why = JITBootstrap.lastFailure {
                    Text(why).font(.caption).foregroundStyle(.orange)
                }
                if !JITBootstrap.ready {
                    Button {
                        jit.enable()
                    } label: {
                        Label("用 \(jit.resolvedMethod.title) 开启 JIT", systemImage: "bolt.fill")
                    }
                    .disabled(jit.busy)
                    Button {
                        _ = JITBootstrap.requestTrollStoreAttach()
                    } label: {
                        Label("用 TrollStore 开启 JIT", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("JIT")
            } footer: {
                Text("Husk 需要既能写入又能执行的内存，而在 iOS 上这需要"
                   + "一个已附加的调试器。有两种办法：一个是响应陷阱请求的"
                   + "调试器，另一个是内核允许任何被调试进程使用的 MAP_JIT "
                   + "映射。任意一种都够用——具体能用哪种取决于设备和 iOS "
                   + "版本，所以 Husk 会两种都测一遍，而不是凭空假设。")
            }

            Section {
                Toggle("启动时开启 JIT", isOn: $autoJIT)
                    .disabled(!HuskBuiltInJIT.isAvailable)
            } footer: {
                Text(HuskBuiltInJIT.isAvailable
                     ? "每次 Husk 在 JIT 未开启时打开，都会请内置的 StikJIT 把它打开，"
                       + "游戏无需点按即可开玩。需要先完成一次 StikJIT 设置（配对）。"
                     : "需要内置的 StikJIT，它在 iOS 26 及以上可用。")
            }

            Section {
                Toggle("启动时开启 Android", isOn: $autoStart)
                    .onChange(of: autoStart) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoStart")
                    }
            } footer: {
                Text("JIT 就绪后，Husk 一打开就启动客体系统。")
            }

            Section {
                Toggle("保持调试器附加", isOn: $keepAttached)
                    .onChange(of: keepAttached) { v in JITBootstrap.keepDebuggerAttached = v }
            } footer: {
                Text("默认关闭。JIT 区域一经占用，Husk 就会与 StikDebug 分离，"
                   + "因为被 iOS 挂起的调试器在下次需要时会卡住整个应用。"
                   + "只有要收集 StikDebug 自身日志时才打开它。")
            }

            Section {
                Text("APK 可以从资料库的 + 按钮或“文件”标签页安装。"
                   + "分包套装——一个基础 APK 加上它的配置分包——必须"
                   + "一起选择；只装基础包会因缺少原生库而失败。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("侧载")
            }
        }
        .huskForm()
        .navigationTitle("JIT 与侧载")
    }
}

// MARK: - Saved machine

struct SavedMachineSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var autoSave =
        UserDefaults.standard.object(forKey: "husk.autoSave") as? Bool ?? true
    @State private var useSnapshot =
        UserDefaults.standard.object(forKey: "husk.downloadSnapshot") as? Bool ?? true
    @State private var askWhichToDelete = false
    @State private var deleteResult: String?
    @AppStorage(GuestImage.askUpdatesKey) private var askUpdates = true

    var body: some View {
        Form {
            Section {
                Toggle("自动保存", isOn: $autoSave)
                    .onChange(of: autoSave) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoSave")
                        HuskLog.log("ui", v ? "automatic saving on" : "automatic saving off")
                    }
                Button {
                    QemuRunner.shared.saveState(reason: "asked from settings")
                } label: {
                    Label(runner.isSavingState ? "正在保存…" : "立即保存",
                          systemImage: "externaldrive.badge.checkmark")
                }
                .disabled(runner.isSavingState)
            } footer: {
                Text("Husk 会恢复已保存的机器而不是重新启动它，只要几秒"
                   + "而不是几分钟。写入期间画面会定住。关闭后没有任何东西"
                   + "会自动保存——包括安装应用之后。")
            }

            Section {
                Button(role: .destructive) { askWhichToDelete = true } label: {
                    Label("删除已保存的机器", systemImage: "trash")
                }
                .disabled(!QemuRunner.shared.hasSnapshot)
                if let deleteResult {
                    Text(deleteResult).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(QemuRunner.shared.hasSnapshot
                     ? "当前保存的是 "
                     + ((QemuRunner.shared.snapshotDisplay ?? "sw").contains("gl")
                        ? "GPU" : "软件渲染") + "。"
                     : "没有保存任何机器，Android 会冷启动。")
            }

            Section {
                Toggle("下载预启动快照", isOn: $useSnapshot)
                    .onChange(of: useSnapshot) { v in
                        UserDefaults.standard.set(v, forKey: "husk.downloadSnapshot")
                    }
            } footer: {
                Text("首次下载会多出约 2 GB。它是用软件渲染器抓取的，"
                   + "所以在 GPU 上不会使用——GPU 模式冷启动一次后"
                   + "会保存自己的快照。")
            }

            Section {
                Toggle("询问 Android 更新", isOn: $askUpdates)
            } footer: {
                Text("有新的 Android 镜像或快照发布时，Husk 会询问一次是否下载。"
                   + "在 Android 下载完成之前不会询问。")
            }
        }
        .huskForm()
        .navigationTitle("已保存的机器")
        .confirmationDialog("要删除哪一台已保存的机器？", isPresented: $askWhichToDelete,
                            titleVisibility: .visible) {
            Button("GPU 机器", role: .destructive) { forget("gl", "GPU") }
            Button("软件渲染机器", role: .destructive) { forget("sw", "软件渲染") }
            Button("取消", role: .cancel) { }
        } message: {
            Text("Android 会冷启动一次，随后重新保存一台。")
        }
    }

    private func forget(_ mode: String, _ name: String) {
        if QemuRunner.shared.forgetSnapshot(mode: mode) {
            deleteResult = "已删除\(name)机器。下次启动将冷启动。"
        } else {
            deleteResult = "没有保存\(name)机器，因此没有删除任何内容。"
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @State private var appIcon = HuskAppIcon.current
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.system
    @AppStorage(Holiday.key) private var holiday = true
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.colorScheme) private var scheme
    @State private var custom: Color = AppTheme.shared.accentColor

    private let iconColumns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        Form {
            Section {
                Picker("外观", selection: $appearance) {
                    ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { v in
                    HuskLog.log("ui", "appearance: \(v.rawValue)")
                }
                Toggle("节日装饰", isOn: $holiday)
            } header: {
                Text("主题")
            } footer: {
                Text("“跟随系统”随手机变化：白天浅色，夜间深色。客体自己的"
                   + "屏幕无论如何都是深色——那是另一台手机的画面。")
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                    ForEach(AppTheme.presets) { preset in
                        Button {
                            theme.accentColor = preset.color
                            custom = preset.color
                        } label: {
                            swatch(preset.color, selected: preset.color.themeHex == theme.accentColor.themeHex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 6)

                ColorPicker("自定义颜色", selection: $custom, supportsOpacity: false)
                    .onChange(of: custom) { theme.accentColor = $0 }
            } header: {
                Text("强调色")
            } footer: {
                Text("为整个应用中的按钮、开关和选中状态着色。")
            }

            Section {
                LazyVGrid(columns: iconColumns, spacing: 14) {
                    ForEach(HuskAppIcon.allCases) { icon in
                        Button {
                            appIcon = icon
                            HuskAppIcon.apply(icon)
                        } label: {
                            VStack(spacing: 8) {
                                if let art = icon.preview(dark: scheme == .dark) {
                                    Image(uiImage: art)
                                        .resizable().scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(appIcon == icon ? Color.accentColor : .clear, lineWidth: 3))
                                }
                                Text(icon.title)
                                    .font(.caption)
                                    .foregroundStyle(appIcon == icon ? Color.accentColor : .primary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("应用图标")
            } footer: {
                Text("“自动”跟随系统外观——浅色、深色和着色。其余图标固定"
                   + "为某一种外观。切换后 iOS 会弹出它自己的确认框，无法关闭。")
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func swatch(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.9), lineWidth: selected ? 2 : 0).padding(-4))
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(color.isLight ? .black : .white)
                }
            }
            .frame(maxWidth: .infinity)
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var showLogs = false
    @AppStorage(TranslationLayer.devInfoKey) private var devInfo = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    HuskMark(size: 84)
                    Text("Husk").font(.title2.weight(.semibold))
                    Text("版本 \(Bundle.main.version)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("构建", value: Bundle.main.commit)
                LabeledContent("系统镜像", value: GuestImage.imageVersion)
                LabeledContent("渲染器",
                               value: runner.displayKind == .gl ? "GPU"
                                    : runner.displayKind == .software ? "CPU"
                                    : "未启动")
            }

            Section {
                Toggle(isOn: $devInfo) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("开发者信息")
                        Text("Android 转译层页面中的技术细节："
                           + "清单报告、设备检查和运行日志。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if devInfo {
                    NavigationLink { TLChecksView() } label: {
                        Label("设备检查", systemImage: "stethoscope")
                    }
                    NavigationLink { MassTestView() } label: {
                        Label("批量测试", systemImage: "square.stack.3d.down.forward")
                    }
                }
                Button { showLogs = true } label: {
                    Label("打开控制台", systemImage: "terminal")
                }
            } footer: {
                Text("Husk 在你的 iPhone 上用一套真实的 Android 系统运行未经修改的 Android APK。"
                   + "控制台显示 Husk 的实时日志、客体的串口输出和 QEMU 自身的"
                   + "输出——诊断这里的任何问题都离不开这三个文件。")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogs) { LogView() }
    }
}

extension Bundle {
    var version: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
    var commit: String {
        (infoDictionary?["HuskBuildCommit"] as? String) ?? "?"
    }
}
