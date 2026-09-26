import Foundation
import Combine

struct HistoryRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let action: String
    let target: String
    let detail: String
    let success: Bool
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), action: String,
         target: String, detail: String, success: Bool, message: String) {
        self.id = id; self.timestamp = timestamp; self.action = action
        self.target = target; self.detail = detail; self.success = success; self.message = message
    }
}

final class HistoryStore: ObservableObject, @unchecked Sendable {
    static let shared = HistoryStore()

    @Published var records: [HistoryRecord] = []
    private let fileURL: URL
    private let retention: TimeInterval = 48 * 3600

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortWatcher", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let arr = try? JSONDecoder().decode([HistoryRecord].self, from: data) else {
            records = []
            return
        }
        records = arr
        prune()
    }

    func add(_ rec: HistoryRecord) {
        records.append(rec)
        prune()
        save()
    }

    func clear() {
        records = []
        save()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        records = records.filter { $0.timestamp >= cutoff }
    }

    private func save() {
        prune()
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL)
        }
    }

    var visibleRecords: [HistoryRecord] {
        records.sorted { $0.timestamp > $1.timestamp }
    }
}
