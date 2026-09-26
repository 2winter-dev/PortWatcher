import Foundation
import Combine

enum FilterMode: Hashable {
    case all, common, local, launchd
}

enum ChangeState {
    case `new`, restarted, steady
}

struct RowAnnotation {
    let state: ChangeState
    let memDelta: Int?   // signed KB vs previous scan (nil = unchanged)
}

let commonPorts: Set<Int> = [
    22, 25, 53, 80, 110, 143, 443, 465, 587, 993, 995,
    1433, 1521, 3306, 5432, 6379, 11211, 9200, 27017,
    3000, 4000, 5000, 7000, 8000, 8001, 8080, 8443, 8888, 9000, 9090
]

func portKey(_ e: PortEntry) -> String { "\(e.port)-\(e.proto)" }
func portFromKey(_ k: String) -> String { k.components(separatedBy: "-").first ?? k }

func formatMem(_ kb: Int) -> String {
    let mb = Double(kb) / 1024
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
    return String(format: "%.0f MB", mb)
}

final class PortMonitor: ObservableObject, @unchecked Sendable {
    static let shared = PortMonitor()

    @Published var ports: [PortEntry] = []
    @Published var lastUpdated: Date = .distantPast
    @Published var isRefreshing = false
    @Published var autoRefresh = true { didSet { autoRefresh ? startTimer() : stopTimer() } }
    @Published var filter: FilterMode = .all
    @Published var searchText: String = ""

    @Published var annotations: [String: RowAnnotation] = [:]
    @Published var changeSummary: String? = nil
    @Published var systemStats: SystemStats? = nil
    // 展开态存在模型层（按 entry.id），避免每 5s 刷新重建行视图时丢失用户展开的行
    @Published var expandedIDs: Set<String> = []
    @Published var favorites: Set<Int> = []   // 用户自定义「常用」端口（取代硬编码 commonPorts 的展示语义）
    @Published var aliases: [Int: String] = [:]   // 端口备注名（显示在端口号前，帮用户识别具体业务）

    private var baseline: [String: PortEntry] = [:]
    private var pendingRestart: [String: Int] = [:]
    private var timer: Timer?
    private let interval: TimeInterval = 5

    private init() {
        favorites = PortMonitor.loadFavorites()
        aliases = PortMonitor.loadAliases()
    }

    // MARK: 常用（收藏）持久化
    private static let supportDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/PortWatcher")
    private static var favoritesURL: URL { supportDir.appendingPathComponent("favorites.json") }

    private static func loadFavorites() -> Set<Int> {
        guard let data = try? Data(contentsOf: favoritesURL),
              let arr = try? JSONDecoder().decode([Int].self, from: data) else {
            return commonPorts   // 首次运行用常见端口种子填充「常用」，用户可后续自定义
        }
        return Set(arr)
    }

    private func saveFavorites() {
        let arr = Array(favorites).sorted()
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(arr).write(to: Self.favoritesURL, options: .atomic)
    }

    func toggleFavorite(_ port: Int) {
        if favorites.contains(port) { favorites.remove(port) }
        else { favorites.insert(port) }
        saveFavorites()
    }

    // MARK: 端口备注名持久化
    private static var aliasesURL: URL { supportDir.appendingPathComponent("aliases.json") }

    private static func loadAliases() -> [Int: String] {
        guard let data = try? Data(contentsOf: aliasesURL),
              let dict = try? JSONDecoder().decode([Int: String].self, from: data) else {
            return [:]
        }
        // 去掉空串，保持干净
        return dict.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func saveAliases() {
        let trimmed = aliases.mapValues { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.value.isEmpty }
        try? JSONEncoder().encode(trimmed).write(to: Self.aliasesURL, options: .atomic)
    }

    /// 设置端口备注名；传空串等同清除
    func setAlias(_ port: Int, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { aliases.removeValue(forKey: port) }
        else { aliases[port] = trimmed }
        saveAliases()
    }

    func clearAlias(_ port: Int) {
        aliases.removeValue(forKey: port)
        saveAliases()
    }

    func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }   // 上一次扫描未结束就不叠加，防止 5s 定时器堆积
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = PortScanner.shared.scan()
            let stats = SystemStatsProvider.snapshot()
            DispatchQueue.main.async {
                guard let self else { return }
                let prevEmpty = self.baseline.isEmpty
                var newMap: [String: PortEntry] = [:]
                for e in list { newMap[portKey(e)] = e }

                var ann: [String: RowAnnotation] = [:]
                var opened = 0, restarted = 0, closed = 0
                var events: [String] = []

                for e in list {
                    let k = portKey(e)
                    if let prev = self.baseline[k] {
                        if prev.pid != e.pid {
                            // 防抖：连续两轮扫到同一新 PID 才算「重启」，过滤 socket 闪断噪音
                            if self.pendingRestart[k] == e.pid {
                                ann[k] = RowAnnotation(state: .restarted, memDelta: nil)
                                restarted += 1
                                events.append(L10n.shared.locf("portRestarted", ":\(e.port)"))
                                self.pendingRestart.removeValue(forKey: k)
                            } else {
                                self.pendingRestart[k] = e.pid
                                ann[k] = RowAnnotation(state: .steady, memDelta: nil)
                            }
                        } else {
                            self.pendingRestart.removeValue(forKey: k)
                            let d = (e.rss ?? 0) - (prev.rss ?? 0)
                            // 波动 <2MB 不显示，避免每 5s 闪 ▲1MB 噪音
                            ann[k] = RowAnnotation(state: .steady, memDelta: abs(d) >= 2048 ? d : nil)
                        }
                    } else {
                        ann[k] = RowAnnotation(state: .new, memDelta: nil)
                        opened += 1
                        events.append(L10n.shared.locf("portAdded", ":\(e.port)"))
                    }
                }

                let closedKeys = self.baseline.keys.filter { newMap[$0] == nil }
                closed = closedKeys.count
                for ck in closedKeys {
                    self.pendingRestart.removeValue(forKey: ck)
                    events.append(L10n.shared.locf("portClosed", ":\(portFromKey(ck))"))
                }

                var seen = Set<String>()
                let uniq = events.filter { seen.insert($0).inserted }

                let newSummary: String?
                if prevEmpty {
                    newSummary = L10n.shared.locf("loadedPorts", list.count)
                } else if uniq.isEmpty {
                    newSummary = nil
                } else {
                    let parts: [String] = [
                        opened > 0 ? L10n.shared.locf("added", opened) : nil,
                        closed > 0 ? L10n.shared.locf("closed", closed) : nil,
                        restarted > 0 ? L10n.shared.locf("restarted", restarted) : nil
                    ].compactMap { $0 }
                    newSummary = parts.joined(separator: " · ")
                        + L10n.shared.loc("eventSep") + uniq.prefix(8).joined(separator: " ")
                }
                // 相等性守卫：值没变就不触发 @Published，减少无谓重渲染
                if self.changeSummary != newSummary { self.changeSummary = newSummary }
                self.annotations = ann
                self.ports = list
                self.baseline = newMap
                self.lastUpdated = Date()
                if self.systemStats != stats { self.systemStats = stats }
                self.isRefreshing = false
            }
        }
    }

    var filtered: [PortEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return ports.filter { e in
            let pass: Bool = {
                switch filter {
                case .all: return true
                case .common: return favorites.contains(e.port)
                case .local: return e.addressKind == .loopback
                case .launchd: return e.isUserLaunch
                }
            }()
            guard pass else { return false }
            if q.isEmpty { return true }
            return "\(e.port)".contains(q)
                || e.processName.lowercased().contains(q)
                || (e.serviceHint?.lowercased().contains(q) ?? false)
                || e.commandLine.lowercased().contains(q)
                || (e.sourceLabel?.lowercased().contains(q) ?? false)
        }
    }
}
