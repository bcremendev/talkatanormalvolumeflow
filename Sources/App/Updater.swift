import AppKit
import Combine

/// Checks GitHub Releases for a newer version and installs it in place.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "bcremendev/talkatanormalvolumeflow"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!

    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String, zip: URL)
        case downloading(Double)
        case installing
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    /// Dev runs (swift build / dist folder) can't self-update; they just open the releases page.
    static var canSelfUpdate: Bool {
        let p = Bundle.main.bundleURL.path
        return p.hasSuffix(".app") && !p.contains("/.build/") && !p.contains("/dist/")
    }
    var availableVersion: String? { if case .available(let v, _) = state { return v } else { return nil } }

    private var timer: Timer?

    /// Check now, then once a day.
    func startPeriodicChecks() {
        Task { await check(quiet: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in await Updater.shared.check(quiet: true) }
        }
    }

    /// `quiet` = don't show "up to date" / network errors (background check).
    func check(quiet: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }
        if !quiet { state = .checking }
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String; let assets: [Asset]
        }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let rel = try JSONDecoder().decode(Release.self, from: data)
            let latest = rel.tag_name.hasPrefix("v") ? String(rel.tag_name.dropFirst()) : rel.tag_name
            lastChecked = Date()
            guard Self.isNewer(latest, than: Self.currentVersion),
                  let zip = rel.assets.first(where: { $0.name.hasSuffix(".zip") })?.browser_download_url else {
                if !quiet { state = .upToDate }
                else if case .checking = state { state = .idle }
                return
            }
            state = .available(version: latest, zip: zip)
        } catch {
            if !quiet { state = .error("Couldn't check for updates. Are you online?") }
            else if case .checking = state { state = .idle }
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Downloads the zip, verifies the signature, swaps the app bundle and relaunches.
    func installAvailable() {
        guard case .available(_, let zip) = state else { return }
        guard Self.canSelfUpdate else { NSWorkspace.shared.open(Self.releasesPage); return }
        state = .downloading(0)
        Task { await install(zip: zip) }
    }

    private func install(zip: URL) async {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("tanvf-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zipFile = work.appendingPathComponent("update.zip")
            try await download(zip, to: zipFile)
            state = .installing

            // Unpack
            try run("/usr/bin/ditto", ["-x", "-k", zipFile.path, work.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                    .first(where: { $0.pathExtension == "app" }) else { throw Err("The download didn't contain the app.") }

            // Only accept a bundle signed by the same team as the running app.
            let ours = try teamID(of: Bundle.main.bundleURL)
            let theirs = try teamID(of: newApp)
            guard !ours.isEmpty, ours == theirs else { throw Err("The download isn't signed by the same developer, so it was not installed.") }
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])

            // Swap after we quit: a tiny shell script waits for this process to exit, replaces the bundle, relaunches.
            let target = Bundle.main.bundleURL
            let old = work.appendingPathComponent("old.app")
            let script = """
            #!/bin/sh
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            mv "\(target.path)" "\(old.path)" && mv "\(newApp.path)" "\(target.path)" || { mv "\(old.path)" "\(target.path)"; exit 1; }
            xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null
            open "\(target.path)"
            rm -rf "\(work.path)"
            """
            let scriptURL = work.appendingPathComponent("swap.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [scriptURL.path]
            try p.run()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: work)
            state = .error(error.localizedDescription)
        }
    }

    private func download(_ url: URL, to dest: URL) async throws {
        let (tmp, resp) = try await URLSession.shared.download(from: url, delegate: nil)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Err("Download failed.") }
        try FileManager.default.moveItem(at: tmp, to: dest)
        state = .downloading(1)
    }

    private func teamID(of app: URL) throws -> String {
        let out = try run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path])
        for line in out.components(separatedBy: "\n") where line.hasPrefix("TeamIdentifier=") {
            return String(line.dropFirst("TeamIdentifier=".count))
        }
        return ""
    }

    @discardableResult
    private func run(_ exe: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw Err("\(URL(fileURLWithPath: exe).lastPathComponent) failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return out
    }

    struct Err: LocalizedError { let msg: String; init(_ m: String) { msg = m }; var errorDescription: String? { msg } }
}
