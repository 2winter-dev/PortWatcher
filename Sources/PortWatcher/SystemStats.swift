import Foundation

struct SystemStats: Equatable {
    let memoryUsedPct: Double
    let memoryUsedGB: Double
    let memoryTotalGB: Double
    let diskUsedPct: Double
    let diskUsedGB: Double
    let diskTotalGB: Double
}

enum SystemStatsProvider {
    static func snapshot() -> SystemStats {
        // 物理内存总量
        let totalStr = ProcessRunner.run("/usr/sbin/sysctl", ["-n", "hw.memsize"]).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let totalBytes = Int64(totalStr) ?? 0

        // vm_stat：仿 Activity Monitor 口径，已用 = active + speculative + wired + compressed
        //（inactive 属可回收缓存，不计入占用；free 在 macOS 上常年极低）
        let vm = ProcessRunner.run("/usr/bin/vm_stat", []).out
        var pageSize: Int64 = 4096
        var active: Int64 = 0
        var speculative: Int64 = 0
        var wired: Int64 = 0
        var compressed: Int64 = 0
        for line in vm.split(separator: "\n") {
            let s = String(line)
            if let r = s.range(of: "page size of ") {
                let rest = String(s[r.upperBound...])
                let token = rest.split(separator: " ").first.map(String.init) ?? ""
                let num = token.filter { $0.isNumber }
                if let p = Int64(num), p > 0 { pageSize = p }
            }
            if s.hasPrefix("Pages active:") { active = parseNum(s) }
            else if s.hasPrefix("Pages speculative:") { speculative = parseNum(s) }
            else if s.hasPrefix("Pages wired down:") { wired = parseNum(s) }
            else if s.hasPrefix("Pages occupied by compressor:") { compressed = parseNum(s) }
        }
        let usedBytes = (active + speculative + wired + compressed) * pageSize
        let memPct = totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0

        // df -k：⚠️ macOS APFS 下 `/` 是只读系统快照卷，Used 只有十几 GB，
        // 真实数据占用在 /System/Volumes/Data 卷；读错卷会得到「12GB/460GB 但 49%」的矛盾数字
        func diskSnapshot(_ path: String) -> (usedK: Int64, totalK: Int64, pct: Double)? {
            let out = ProcessRunner.run("/bin/df", ["-k", path]).out
            let lines = out.split(separator: "\n")
            guard lines.count >= 2 else { return nil }
            let cols = String(lines[1]).split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
            guard cols.count >= 5, let total = Int64(cols[1]), total > 0 else { return nil }
            let used = Int64(cols[2]) ?? 0
            // 百分比用 used/total 自算，与显示的「已用/总量」两个数自洽
            //（df 的 Capacity 列在 APFS 上按 used/(used+avail) 算，会剔除可清除空间，跟总量对不上）
            return (used, total, Double(used) / Double(total) * 100)
        }
        let snap = diskSnapshot("/System/Volumes/Data") ?? diskSnapshot("/")
        var diskPct: Double = 0
        var usedK: Int64 = 0
        var totalK: Int64 = 0
        if let s = snap {
            usedK = s.usedK
            totalK = s.totalK
            diskPct = s.pct
        }

        let bytesToGB = 1024.0 * 1024.0 * 1024.0
        let kbToGB = 1024.0 * 1024.0
        return SystemStats(
            memoryUsedPct: memPct,
            memoryUsedGB: Double(usedBytes) / bytesToGB,
            memoryTotalGB: Double(totalBytes) / bytesToGB,
            diskUsedPct: diskPct,
            diskUsedGB: Double(usedK) / kbToGB,
            diskTotalGB: Double(totalK) / kbToGB
        )
    }

    private static func parseNum(_ s: String) -> Int64 {
        let digits = s.filter { $0.isNumber }
        return Int64(digits) ?? 0
    }
}
