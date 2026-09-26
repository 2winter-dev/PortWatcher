import Foundation

enum AddressKind {
    case loopback
    case allInterfaces
    case specific
}

struct PortEntry: Identifiable, Equatable {
    // 稳定标识：端口+协议+PID。若用随机 UUID，每 5s 刷新会让整列表被 SwiftUI 销毁重建（卡顿、展开态丢失）
    var id: String { "\(port)-\(proto)-\(pid)" }
    let port: Int
    let proto: String
    var addresses: [String]
    var addressKind: AddressKind
    let processName: String
    let pid: Int
    let user: String
    let isIPv6: Bool
    let sourceLabel: String?
    let sourcePath: String?
    let commandLine: String
    let execPath: String?
    let serviceHint: String?
    let cwd: String?
    let rss: Int?          // resident memory in KB

    /// 系统服务（Apple 守护/代理、系统级路径）：「自启动」标签与筛选时排除
    var isSystemService: Bool {
        if let label = sourceLabel, label.hasPrefix("com.apple.") { return true }
        if let p = sourcePath, p.contains("/System/Library/") { return true }
        return false
    }
    /// 用户级自启动：launchd 托管且非系统服务（排除 ControlCenter 等系统进程）
    var isUserLaunch: Bool { sourceLabel != nil && !isSystemService }
}

// 常用端口 → 人话服务名；命中才显示，生僻名不展示（中英文两套）
let friendlyServiceNamesEN: [Int: String] = [
    22: "SSH", 25: "SMTP", 53: "DNS", 80: "HTTP", 443: "HTTPS",
    465: "SMTPS", 587: "SMTP Submit", 631: "Print IPP", 993: "IMAPS", 995: "POP3S",
    1080: "SOCKS proxy", 3000: "Node/Next dev", 3001: "Dev port", 3306: "MySQL",
    3389: "Remote desktop", 4200: "Angular dev", 5000: "AirPlay/Flask", 5173: "Vite dev",
    5353: "mDNS (Bonjour)", 5432: "PostgreSQL", 5555: "ADB", 6379: "Redis",
    7000: "AirPlay", 8000: "HTTP dev", 8001: "HTTP dev", 8080: "HTTP alt",
    8443: "HTTPS alt", 8888: "Jupyter/HTTP", 9000: "Common dev", 9090: "Admin port",
    9200: "Elasticsearch", 9229: "Node debug", 11211: "Memcached", 27017: "MongoDB"
]

let friendlyServiceNamesZH: [Int: String] = [
    22: "SSH", 25: "SMTP", 53: "DNS", 80: "HTTP", 443: "HTTPS",
    465: "SMTPS", 587: "SMTP 提交", 631: "打印 IPP", 993: "IMAPS", 995: "POP3S",
    1080: "SOCKS 代理", 3000: "Node/Next 开发", 3001: "开发端口", 3306: "MySQL",
    3389: "远程桌面", 4200: "Angular dev", 5000: "AirPlay/Flask", 5173: "Vite dev",
    5353: "mDNS (Bonjour)", 5432: "PostgreSQL", 5555: "ADB", 6379: "Redis",
    7000: "AirPlay", 8000: "HTTP 开发", 8001: "HTTP 开发", 8080: "HTTP 备用",
    8443: "HTTPS 备用", 8888: "Jupyter/HTTP", 9000: "开发常用", 9090: "管理端口",
    9200: "Elasticsearch", 9229: "Node 调试", 11211: "Memcached", 27017: "MongoDB"
]

// 疑似 Web 服务：给「浏览器快捷打开」按钮用（端口特征 + 开发进程关键词）
let webHintPorts: Set<Int> = [
    80, 443, 3000, 3001, 4000, 4200, 4321, 5000, 5173,
    8000, 8001, 8080, 8443, 8888, 9000, 9090, 9229
]
let webProcessKeywords = ["node", "python", "astro", "vite", "next", "php",
                          "flask", "uvicorn", "django", "jekyll", "hugo", "http"]

func isLikelyWeb(_ e: PortEntry) -> Bool {
    guard e.proto == "TCP" else { return false }
    if webHintPorts.contains(e.port) { return true }
    let p = (e.processName + " " + e.commandLine).lowercased()
    return webProcessKeywords.contains { p.contains($0) }
}

func webURL(for port: Int) -> String {
    (port == 443 || port == 8443) ? "https://127.0.0.1:\(port)" : "http://127.0.0.1:\(port)"
}

final class PortScanner: @unchecked Sendable {
    static let shared = PortScanner()
    private var servicesMap: [Int: String] = [:]
    private var plistCache: [String: String?] = [:]

    private init() { loadServices() }

    private func loadServices() {
        guard let data = FileManager.default.contents(atPath: "/etc/services"),
              let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let l = line.split(separator: "#").first ?? ""
            let parts = l.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let pp = parts[1].split(separator: "/")
            guard pp.count == 2, let port = Int(pp[0]) else { continue }
            if servicesMap[port] == nil { servicesMap[port] = parts[0] }
        }
    }

    func scan() -> [PortEntry] {
        let raws = parseLsof(args: ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-l"], proto: "TCP")
                 + parseLsof(args: ["-iUDP", "-P", "-n", "-l"], proto: "UDP")
        let pids = Array(Set(raws.map { $0.pid }))
        let psMap = psCommands()
        let jobs = launchJobs()
        let cwdMap = cwdMap(pids: pids)

        var entries: [PortEntry] = []
        for r in raws {
            guard let (addr, port, isV6) = parseName(r.name) else { continue }
            let info = psMap[r.pid]
            let cmd = info?.cmd ?? r.command
            let label = jobs[r.pid]
            let plist = label.flatMap { resolvePlistPath($0) }
            let friendly = L10n.shared.langCode == "zh" ? friendlyServiceNamesZH : friendlyServiceNamesEN
            let service = friendly[port]
                ?? (port < 1024 ? servicesMap[port] : nil)
            let execPath = cmd.firstPathComponentOrNil
            let kind = addressKind(of: addr)
            let displayName = execPath?.lastPathComponent ?? r.command
            entries.append(PortEntry(
                port: port, proto: r.proto, addresses: [addr], addressKind: kind,
                processName: displayName, pid: r.pid, user: r.user, isIPv6: isV6,
                sourceLabel: label, sourcePath: plist, commandLine: cmd,
                execPath: execPath, serviceHint: service, cwd: cwdMap[r.pid],
                rss: info?.rss))
        }
        let sorted = entries.sorted { $0.port == $1.port ? $0.proto < $1.proto : $0.port < $1.port }
        return Self.mergeDuplicates(sorted)
    }

    /// lsof 会把 IPv4/IPv6、多 socket 分行列出；按 端口+协议+PID 合并为一行
    private static func mergeDuplicates(_ input: [PortEntry]) -> [PortEntry] {
        func rank(_ k: AddressKind) -> Int {
            switch k { case .loopback: return 1; case .specific: return 2; case .allInterfaces: return 3 }
        }
        var map: [String: PortEntry] = [:]
        var order: [String] = []
        for e in input {
            let k = "\(e.port)-\(e.proto)-\(e.pid)"
            if var prev = map[k] {
                for a in e.addresses where !prev.addresses.contains(a) { prev.addresses.append(a) }
                if rank(e.addressKind) > rank(prev.addressKind) { prev.addressKind = e.addressKind }
                map[k] = prev
            } else {
                map[k] = e
                order.append(k)
            }
        }
        return order.compactMap { map[$0] }
    }

    // MARK: - parsing
    private struct RawPort { let proto: String; let name: String; let command: String; let user: String; let pid: Int }

    private func parseLsof(args: [String], proto: String) -> [RawPort] {
        let out = ProcessRunner.run("/usr/sbin/lsof", args).out
        var result: [RawPort] = []
        for line in out.split(separator: "\n") {
            if line.hasPrefix("COMMAND") { continue }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard tokens.count >= 9, let pid = Int(tokens[1]) else { continue }
            result.append(RawPort(proto: proto, name: tokens[8], command: tokens[0], user: tokens[2], pid: pid))
        }
        return result
    }

    private func parseName(_ raw: String) -> (String, Int, Bool)? {
        var s = raw
        if let paren = s.firstIndex(of: "(") { s = String(s[..<paren]) }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.contains("->") { return nil }
        guard let colon = s.lastIndex(of: ":") else { return nil }
        let addrPart = String(s[..<colon])
        let portPart = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard let port = Int(portPart.filter({ $0.isNumber })) else { return nil }
        var addr = addrPart
        let isV6 = addr.contains(":")
        if addr.hasPrefix("[") && addr.hasSuffix("]") { addr = String(addr.dropFirst().dropLast()) }
        if addr == "*" { addr = "0.0.0.0" }
        return (addr, port, isV6)
    }

    private func addressKind(of addr: String) -> AddressKind {
        if addr == "127.0.0.1" || addr == "::1" { return .loopback }
        if addr == "0.0.0.0" || addr == "*" || addr == "::" { return .allInterfaces }
        return .specific
    }

    // MARK: - ps / launchctl / cwd
    private func psCommands() -> [Int: (rss: Int, cmd: String)] {
        let out = ProcessRunner.run("/bin/ps", ["-ax", "-o", "pid=,rss=,command="]).out
        var map: [Int: (rss: Int, cmd: String)] = [:]
        for line in out.split(separator: "\n") {
            let t = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard t.count >= 3, let pid = Int(t[0]), let rss = Int(t[1]) else { continue }
            let cmd = t.dropFirst(2).joined(separator: " ")
            map[pid] = (rss, cmd)
        }
        return map
    }

    private func launchJobs() -> [Int: String] {
        let out = ProcessRunner.run("/bin/launchctl", ["list"]).out
        var map: [Int: String] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            // launchctl list 三列：PID（未运行为 "-"）、Status、Label——第 1 列是 PID 不是 Label
            guard parts.count >= 3, parts[0] != "-", let pid = Int(parts[0]) else { continue }
            map[pid] = parts[2]
        }
        return map
    }

    private func cwdMap(pids: [Int]) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        let arg = pids.map(String.init).joined(separator: ",")
        let out = ProcessRunner.run("/usr/sbin/lsof", ["-n", "-F", "n", "-d", "cwd", "-p", arg]).out
        var map: [Int: String] = [:]
        var cur: Int?
        for line in out.split(separator: "\n") {
            if line.hasPrefix("p") { cur = Int(line.dropFirst()) }
            else if line.hasPrefix("n"), let pid = cur { map[pid] = String(line.dropFirst()) }
        }
        return map
    }

    private func resolvePlistPath(_ label: String) -> String? {
        if let cached = plistCache[label] { return cached }
        let candidates = [
            "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist",
            "/Library/LaunchAgents/\(label).plist",
            "/Library/LaunchDaemons/\(label).plist",
            "/System/Library/LaunchAgents/\(label).plist",
            "/System/Library/LaunchDaemons/\(label).plist"
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c) {
            plistCache[label] = c
            return c
        }
        plistCache[label] = nil
        return nil
    }
}

extension String {
    var firstPathComponentOrNil: String? {
        let trimmed = self.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let first = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return first.contains("/") ? first : nil
    }
    var lastPathComponent: String {
        return (self as NSString).lastPathComponent
    }
}
