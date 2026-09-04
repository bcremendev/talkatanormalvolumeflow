import Foundation

struct WhisperModel: Identifiable, Hashable {
    let id: String
    let name: String
    let sizeMB: Int
    let englishOnly: Bool
    let note: String

    var filename: String { "ggml-\(id).bin" }
    var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")! }

    static let all: [WhisperModel] = [
        WhisperModel(id: "base.en", name: "Base (English)", sizeMB: 148, englishOnly: true, note: "Fastest, least accurate"),
        WhisperModel(id: "small.en", name: "Small (English)", sizeMB: 488, englishOnly: true, note: "Recommended: fast and accurate"),
        WhisperModel(id: "small", name: "Small (Multilingual)", sizeMB: 488, englishOnly: false, note: "Any language, slightly less accurate in English"),
        WhisperModel(id: "medium.en", name: "Medium (English)", sizeMB: 1530, englishOnly: true, note: "More accurate, 2-3x slower"),
        WhisperModel(id: "large-v3-turbo", name: "Large v3 Turbo (Multilingual)", sizeMB: 1620, englishOnly: false, note: "Best accuracy, needs 16GB+ RAM"),
    ]
    static func byId(_ id: String) -> WhisperModel { all.first { $0.id == id } ?? all[1] }
}

/// Downloads and tracks Whisper model files in Application Support.
final class ModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelManager()

    @Published var progress: [String: Double] = [:]
    @Published var errors: [String: String] = [:]

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()
    private var tasks: [Int: WhisperModel] = [:]

    func path(for model: WhisperModel) -> URL { AppPaths.models.appendingPathComponent(model.filename) }

    func isDownloaded(_ model: WhisperModel) -> Bool {
        let p = path(for: model).path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: p),
              let size = attrs[.size] as? Int else { return false }
        return size > 1_000_000
    }

    var downloadedModels: [WhisperModel] { WhisperModel.all.filter(isDownloaded) }
    func isDownloading(_ model: WhisperModel) -> Bool { progress[model.id] != nil }

    func download(_ model: WhisperModel) {
        guard !isDownloading(model) else { return }
        DispatchQueue.main.async {
            self.progress[model.id] = 0
            self.errors[model.id] = nil
        }
        let task = session.downloadTask(with: model.url)
        tasks[task.taskIdentifier] = model
        task.resume()
    }

    func cancel(_ model: WhisperModel) {
        session.getAllTasks { tasks in
            for t in tasks where self.tasks[t.taskIdentifier]?.id == model.id { t.cancel() }
        }
    }

    func delete(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: path(for: model))
        objectWillChange.send()
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let model = tasks[downloadTask.taskIdentifier] else { return }
        let expected = totalBytesExpectedToWrite > 0 ? Double(totalBytesExpectedToWrite) : Double(model.sizeMB) * 1_048_576
        let p = min(0.999, Double(totalBytesWritten) / expected)
        DispatchQueue.main.async { self.progress[model.id] = p }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let model = tasks[downloadTask.taskIdentifier] else { return }
        let dest = path(for: model)
        var failure: String?
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw NSError(domain: "download", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"])
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            failure = error.localizedDescription
        }
        DispatchQueue.main.async {
            self.progress[model.id] = nil
            if let failure { self.errors[model.id] = failure }
            self.tasks[downloadTask.taskIdentifier] = nil
            self.objectWillChange.send()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let model = tasks[task.taskIdentifier] else { return }
        DispatchQueue.main.async {
            self.progress[model.id] = nil
            if (error as NSError).code != NSURLErrorCancelled {
                self.errors[model.id] = error.localizedDescription
            }
            self.tasks[task.taskIdentifier] = nil
        }
    }
}
