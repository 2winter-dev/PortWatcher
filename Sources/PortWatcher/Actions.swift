import Foundation
import AppKit
import ServiceManagement

enum ProcessRunner {
    static func run(_ executable: String, _ args: [String]) -> (exit: Int32, out: String, err: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let outP = Pipe()
        let errP = Pipe()
        proc.standardOutput = outP
        proc.standardError = errP
        do { try proc.run() } catch { return (-1, "", error.localizedDescription) }
        // 必须先把两根管道读到 EOF 再 waitUntilExit，否则子进程输出超过 64KB 管道缓冲会死锁
        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        group.enter()
        DispatchQueue.global().async { outData = outP.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = errP.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.wait()
        proc.waitUntilExit()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (proc.terminationStatus, out, err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func spawnShell(_ command: String, cwd: String?) -> (Int32, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        if let cwd = cwd { proc.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let outP = Pipe()
        let errP = Pipe()
        proc.standardOutput = outP
        proc.standardError = errP
        do { try proc.run() } catch { return (-1, L10n.shared.locf("launchFailed", error.localizedDescription)) }
        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        group.enter()
        DispatchQueue.global().async { outData = outP.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = errP.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.wait()
        proc.waitUntilExit()
        let err = String(data: errData, encoding: .utf8) ?? ""
        _ = String(data: outData, encoding: .utf8)
        return (proc.terminationStatus, err.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}

struct Actions {
    static func restart(_ e: PortEntry) {
        let hist = HistoryStore.shared
        if let label = e.sourceLabel {
            let domain = "gui/\(getuid())/\(label)"
            let r = ProcessRunner.run("/bin/launchctl", ["kickstart", "-k", domain])
            hist.add(HistoryRecord(timestamp: Date(), action: L10n.shared.loc("actRestart"),
                target: ":\(e.port) \(e.proto) \(e.processName)",
                detail: label, success: r.exit == 0,
                message: r.exit == 0 ? L10n.shared.loc("restartedViaLaunchctl") : r.err))
        } else {
            _ = ProcessRunner.run("/bin/kill", ["-9", "\(e.pid)"])
            Thread.sleep(forTimeInterval: 1.0)
            let r = ProcessRunner.spawnShell(e.commandLine, cwd: e.cwd)
            hist.add(HistoryRecord(timestamp: Date(), action: L10n.shared.loc("actRestart"),
                target: ":\(e.port) \(e.proto) \(e.processName)",
                detail: e.commandLine, success: r.0 == 0,
                message: r.0 == 0 ? L10n.shared.loc("restartedViaCmd") : r.1))
        }
        PortMonitor.shared.refresh()
    }

    static func forceStop(_ e: PortEntry) {
        let hist = HistoryStore.shared
        if let label = e.sourceLabel {
            _ = ProcessRunner.run("/bin/launchctl", ["kill", "SIGKILL", "gui/\(getuid())/\(label)"])
        }
        let r = ProcessRunner.run("/bin/kill", ["-9", "\(e.pid)"])
        hist.add(HistoryRecord(timestamp: Date(), action: L10n.shared.loc("actForceStop"),
            target: ":\(e.port) \(e.proto) \(e.processName)",
            detail: "PID \(e.pid)", success: r.exit == 0,
            message: r.exit == 0 ? L10n.shared.loc("sigkillSent") : r.err))
        PortMonitor.shared.refresh()
    }

    static func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    static func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func quit() {
        NSApplication.shared.terminate(nil)
    }

    static func fetchLogs(pid: Int) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                // ⚠️ macOS `log show` 没有 --limit 选项（传了会报 unrecognized option），截尾在代码里做
                let r = ProcessRunner.run("/usr/bin/log",
                    ["show", "--predicate", "processID == \(pid)",
                     "--last", "20m", "--style", "compact"])
                if r.exit == 0 {
                    let lines = r.out.split(separator: "\n")
                    let tail = lines.suffix(300).joined(separator: "\n")
                    cont.resume(returning: tail.isEmpty ? L10n.shared.loc("noLogs") : tail)
                } else {
                    cont.resume(returning: L10n.shared.locf("logReadFailed", r.err))
                }
            }
        }
    }
}
