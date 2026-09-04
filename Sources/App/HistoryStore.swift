import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var text: String
    var rawText: String
    var appName: String
    var durationSeconds: Double
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var entries: [HistoryEntry] = []
    private let limit = 300

    private init() { load() }

    func add(_ e: HistoryEntry) {
        entries.insert(e, at: 0)
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        save()
    }

    func clear() { entries = []; save() }
    func delete(_ e: HistoryEntry) { entries.removeAll { $0.id == e.id }; save() }

    private func load() {
        guard let d = try? Data(contentsOf: AppPaths.history),
              let list = try? JSONDecoder().decode([HistoryEntry].self, from: d) else { return }
        entries = list
    }

    private func save() {
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: AppPaths.history, options: .atomic) }
    }
}
