import SwiftUI

// MARK: - Visual effect (Liquid Glass backdrop)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Main view
struct ContentView: View {
    @EnvironmentObject var monitor: PortMonitor
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var l10n: L10n
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                header
                Divider()
                if showSettings {
                    settingsSection
                    Divider()
                }
                statsBar
                Divider()
                filterBar
                Divider()
                listSection
                Divider()
                historySection
            }
            .padding(.vertical, 8)
            }
        }
        .frame(width: 480)
        .onChange(of: launchAtLogin) { _, newValue in
            do { try LaunchAtLogin.set(newValue) }
            catch {
                launchAtLogin = !newValue
                showAlert(l10n.locf("loginItemFailed", error.localizedDescription))
            }
        }
    }

    // MARK: header
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
            Text("PortWatcher").font(.headline).fontDesign(.rounded)
            Spacer()
            Text(relative(monitor.lastUpdated)).font(.caption).foregroundStyle(.secondary)
            Button {
                monitor.refresh()
            } label: {
                // 菊花合并进按钮内部：单独放一个 ProgressView 会紧贴按钮，看起来像「多了一圈」
                if monitor.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless).help(l10n.loc("refresh"))
            // macOS 26 可聚焦按钮在弹窗获键盘焦点时会显示 accent 紫环，关掉它
            .focusable(false)
            Toggle(l10n.loc("autoRefresh"), isOn: $monitor.autoRefresh)
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .help(l10n.loc("autoRefresh"))
            Button {
                withAnimation { showSettings.toggle() }
            } label: {
                Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
            }
            .buttonStyle(.borderless).help(l10n.loc("settings"))
            .focusable(false)
        }
        .padding(.horizontal, 12)
    }

    // MARK: filter
    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $monitor.filter) {
                Text(l10n.loc("filterAll")).tag(FilterMode.all)
                Text(l10n.loc("filterCommon")).tag(FilterMode.common)
                Text(l10n.loc("filterLocal")).tag(FilterMode.local)
                Text(l10n.loc("filterLaunchd")).tag(FilterMode.launchd)
            }
            .pickerStyle(.segmented)
            // ⚠️ frame 默认居中内容：分段控件没撑满定宽 frame 时会被居中，必须显式 leading
            .frame(width: 260, alignment: .leading)
            Spacer()
            TextField(l10n.loc("searchPlaceholder"), text: $monitor.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: settings（低频项收纳区，由顶栏齿轮展开）
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l10n.loc("settingsTitle")).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                Text("v1.0").font(.caption2).foregroundStyle(.tertiary)
            }
            HStack {
                Image(systemName: "powerplug.fill").foregroundStyle(.secondary).font(.caption)
                Toggle(l10n.loc("launchAtLogin"), isOn: $launchAtLogin)
                    .toggleStyle(.switch).controlSize(.small)
                Spacer()
                Button(l10n.loc("quitApp")) { Actions.quit() }
                    .font(.caption).buttonStyle(.bordered).controlSize(.small)
            }
            HStack {
                Image(systemName: "globe").foregroundStyle(.secondary).font(.caption)
                Picker(selection: $l10n.language) {
                    Text(l10n.loc("langSystem")).tag(AppLanguage.system)
                    Text(l10n.loc("langEnglish")).tag(AppLanguage.english)
                    Text(l10n.loc("langChinese")).tag(AppLanguage.chinese)
                } label: { Text(l10n.loc("language")) }
                .pickerStyle(.menu).controlSize(.small)
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: system stats strip
    private var statsBar: some View {
        HStack(spacing: 10) {
            if let s = monitor.systemStats {
                statCard(l10n.loc("mem"), s.memoryUsedPct,
                         "\(formatGB(s.memoryUsedGB)) / \(formatGB(s.memoryTotalGB))")
                statCard(l10n.loc("disk"), s.diskUsedPct,
                         "\(formatGB(s.diskUsedGB)) / \(formatGB(s.diskTotalGB))")
            } else {
                Text(l10n.loc("readingResources")).foregroundStyle(.secondary).font(.caption)
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func statCard(_ title: String, _ pct: Double, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", pct))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(pct > 85 ? .red : (pct > 70 ? .orange : .primary))
            }
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func formatGB(_ gb: Double) -> String {
        if gb >= 1024 { return String(format: "%.1f TB", gb / 1024) }
        return String(format: "%.0f GB", gb)
    }

    // MARK: port list
    private var listSection: some View {
        VStack(spacing: 8) {
            if let summary = monitor.changeSummary {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").foregroundStyle(.tint).font(.caption)
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            if monitor.filtered.isEmpty {
                Text(l10n.loc("noMatch")).foregroundStyle(.secondary).padding(20)
            }
            ForEach(monitor.filtered) { entry in
                PortRow(entry: entry, annotation: monitor.annotations[portKey(entry)])
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: history
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l10n.loc("historyTitle")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(l10n.loc("clear")) { history.clear() }.font(.caption).buttonStyle(.borderless)
            }
            VStack(spacing: 2) {
                if history.visibleRecords.isEmpty {
                    Text(l10n.loc("noHistory")).foregroundStyle(.secondary).padding(8)
                }
                ForEach(history.visibleRecords) { rec in
                    HistoryRow(rec: rec)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var filtered: [PortEntry] { monitor.filtered }

    private func relative(_ d: Date) -> String {
        if d == .distantPast { return l10n.loc("notRefreshed") }
        let f = RelativeDateTimeFormatter()
        f.locale = l10n.locale
        return f.localizedString(for: d, relativeTo: Date())
    }

    private func showAlert(_ message: String) {
        let a = NSAlert()
        a.messageText = "PortWatcher"
        a.informativeText = message
        a.alertStyle = .warning
        a.runModal()
    }
}

// MARK: - Port row with expandable detail
struct PortRow: View {
    let entry: PortEntry
    let annotation: RowAnnotation?

    @EnvironmentObject var monitor: PortMonitor
    @EnvironmentObject var l10n: L10n
    private var isExpanded: Bool { monitor.expandedIDs.contains(entry.id) }
    private func toggleExpanded() {
        if monitor.expandedIDs.contains(entry.id) { monitor.expandedIDs.remove(entry.id) }
        else { monitor.expandedIDs.insert(entry.id) }
    }
    @State private var logs: String?
    @State private var loadingLogs = false
    @State private var plistText: String?
    @State private var showStopConfirm = false
    @State private var aliasDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Button { toggleExpanded() } label: { rowContent }
                    .buttonStyle(.plain)
                if isLikelyWeb(entry) {
                    Button { Actions.openInBrowser(webURL(for: entry.port)) } label: {
                        Image(systemName: "globe").foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .help(l10n.locf("openInBrowserHelp", webURL(for: entry.port)))
                }
                Button {
                    monitor.toggleFavorite(entry.port)
                } label: {
                    let fav = monitor.favorites.contains(entry.port)
                    Image(systemName: fav ? "star.fill" : "star")
                        .foregroundStyle(fav ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help(monitor.favorites.contains(entry.port) ? l10n.loc("favRemove") : l10n.loc("favAdd"))
            }
            if isExpanded { detail }
        }
        .onAppear { aliasDraft = monitor.aliases[entry.port] ?? "" }
        .padding(10)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: collapsed content
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // 端口备注名：显示在端口号前，帮用户一眼识别具体业务
                    if let alias = monitor.aliases[entry.port], !alias.isEmpty {
                        Text(alias)
                            .font(.system(.body, design: .rounded)).fontWeight(.semibold)
                    }
                    // verbatim：避免 LocalizedStringKey 给端口号加千分位逗号
                    Text(verbatim: ":\(entry.port)")
                        .font(.system(.body, design: .monospaced)).fontWeight(.semibold)
                    if let s = entry.serviceHint {
                        Text(s).font(.caption).fontWeight(.semibold).foregroundStyle(.primary)
                    }
                    protoBadge
                    if entry.addressKind == .loopback { tag(l10n.loc("tagLocal"), .green) }
                    else if entry.addressKind == .allInterfaces { tag(l10n.loc("tagPublic"), .red) }
                    if entry.isUserLaunch { tag(l10n.loc("tagAutoLaunch"), .purple) }
                    if let ann = annotation {
                        if ann.state == .new { tag("NEW", .green) }
                        else if ann.state == .restarted { tag(l10n.loc("tagRestart"), .orange) }
                        if let d = ann.memDelta {
                            tag(d > 0 ? "▲ \(formatMem(abs(d)))" : "▼ \(formatMem(abs(d)))",
                                d > 0 ? .red : .green)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Text(entry.processName).font(.caption)
                    Text("· PID \(entry.pid)").font(.caption).foregroundStyle(.secondary)
                    Text("· \(entry.user)").font(.caption).foregroundStyle(.secondary)
                    if let rss = entry.rss {
                        Text("· \(formatMem(rss))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(sourceText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .foregroundStyle(.tertiary).font(.caption)
        }
    }

    // MARK: expanded detail
    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Text(l10n.loc("alias")).font(.caption).foregroundStyle(.secondary)
                TextField(l10n.loc("aliasPlaceholder"), text: $aliasDraft)
                    .textFieldStyle(.roundedBorder)
                Button(l10n.loc("save")) { commitAlias() }
                    .buttonStyle(.bordered).controlSize(.small)
                if monitor.aliases[entry.port] != nil {
                    Button(l10n.loc("clear")) { clearAlias() }
                        .buttonStyle(.borderless).controlSize(.small).tint(.red)
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                gridRow(l10n.loc("listenAddr"), entry.addresses.joined(separator: " + "))
                gridRow(l10n.loc("user"), entry.user)
                if let rss = entry.rss { gridRow(l10n.loc("memUsage"), formatMem(rss)) }
                if let cwd = entry.cwd { gridRow(l10n.loc("workDir"), cwd) }
                if let exec = entry.execPath { gridRow(l10n.loc("executable"), exec) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let label = entry.sourceLabel {
                HStack(spacing: 6) {
                    Text(l10n.loc("sourceLaunchd")).foregroundStyle(.secondary).font(.caption)
                    Text(label).font(.caption).textSelection(.enabled)
                    if let p = entry.sourcePath {
                        Button(l10n.loc("viewPlist")) { loadPlist(p) }
                            .font(.caption).buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            } else {
                Text(l10n.loc("sourceUser"))
                    .foregroundStyle(.secondary).font(.caption)
            }

            if let plistText {
                ScrollView {
                    Text(plistText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.loc("fullCommand")).font(.caption).foregroundStyle(.secondary)
                Text(entry.commandLine)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Text(l10n.loc("processLogs")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if loadingLogs { ProgressView().controlSize(.small) }
                Button(loadingLogs ? l10n.loc("loading") : l10n.loc("loadLogs")) { loadLogs() }
                    .font(.caption).buttonStyle(.bordered).controlSize(.small)
                    .disabled(loadingLogs)
            }
            if let logs {
                ScrollView {
                    Text(logs)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 8) {
                Button { Task.detached { Actions.restart(entry) } } label: {
                    Label(l10n.loc("restart"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button { showStopConfirm = true } label: {
                    Label(l10n.loc("forceStop"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered).controlSize(.small).tint(.red)
                if let exec = entry.execPath {
                    Button { Actions.reveal(exec) } label: {
                        Label(l10n.loc("showInFinder"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                if entry.proto == "TCP" {
                    Button { Actions.openInBrowser(webURL(for: entry.port)) } label: {
                        Label(l10n.loc("openInBrowser"), systemImage: "safari")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Spacer()
                Button { Actions.copy(entry.commandLine) } label: {
                    Label(l10n.loc("copyCommand"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .confirmationDialog(l10n.loc("confirmForceStop"), isPresented: $showStopConfirm) {
            Button(l10n.loc("forceStop"), role: .destructive) { Task.detached { Actions.forceStop(entry) } }
            Button(l10n.loc("cancel"), role: .cancel) {}
        }
    }

    // MARK: helpers
    private var protoBadge: some View {
        Text(entry.proto)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((entry.proto == "TCP" ? Color.blue : Color.orange).opacity(0.15),
                        in: Capsule())
            .foregroundStyle(entry.proto == "TCP" ? Color.blue : Color.orange)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var sourceText: String {
        if let label = entry.sourceLabel {
            return "launchd: \(label)" + (entry.sourcePath.map { "  (\($0))" } ?? "")
        }
        return entry.commandLine
    }

    private func gridRow(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.tertiary)
            Text(v).textSelection(.enabled)
        }
    }

    private func loadPlist(_ path: String) {
        do { plistText = try String(contentsOfFile: path, encoding: .utf8) }
        catch { plistText = l10n.locf("plistReadFailed", error.localizedDescription) }
    }

    private func loadLogs() {
        loadingLogs = true
        logs = nil
        let pid = entry.pid
        Task {
            let text = await Actions.fetchLogs(pid: pid)
            await MainActor.run {
                self.logs = text
                self.loadingLogs = false
            }
        }
    }

    private func commitAlias() {
        monitor.setAlias(entry.port, aliasDraft)
    }

    private func clearAlias() {
        monitor.clearAlias(entry.port)
        aliasDraft = ""
    }
}

// MARK: - History row
struct HistoryRow: View {
    let rec: HistoryRecord
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: rec.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(rec.success ? .green : .red).font(.caption)
            Text(rec.action).font(.caption).fontWeight(.medium)
                .frame(width: 56, alignment: .leading)
            Text(rec.target).font(.caption).lineLimit(1)
            Spacer()
            Text(time(rec.timestamp)).font(.caption2).foregroundStyle(.tertiary)
        }
    }
    private func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}
