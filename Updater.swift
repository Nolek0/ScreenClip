import Cocoa

/// Checks GitHub Releases for a newer version and installs it in place (download DMG → swap app → relaunch).
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "Nolek0/ScreenClip"

    struct Release: Equatable {
        let version: String
        let notes: String
        let dmg: URL
        let page: URL
    }
    enum Status: Equatable { case idle, checking, upToDate, available, downloading, installing, failed(String) }

    @Published private(set) var status: Status = .idle
    @Published private(set) var latest: Release?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
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

    var isBusy: Bool { [.checking, .downloading, .installing].contains(status) }

    /// silent: used for the automatic check, which shows nothing unless an update exists.
    func check(silent: Bool = false) {
        guard !isBusy else { return }
        if !silent { status = .checking }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ScreenClip-Updater", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async { self.handle(data, silent: silent) }
        }.resume()
    }

    private func handle(_ data: Data?, silent: Bool) {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else {
            if !silent { status = .failed(L("Couldn't check for updates.")) }
            return
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.compactMap { $0["browser_download_url"] as? String }
            .first { $0.lowercased().hasSuffix(".dmg") }
            .flatMap(URL.init(string:))
        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/\(Self.repo)/releases")!
        if Self.isNewer(version, than: Self.currentVersion), let dmg {
            latest = Release(version: version, notes: json["body"] as? String ?? "", dmg: dmg, page: page)
            status = .available
        } else {
            latest = nil
            status = silent ? .idle : .upToDate
        }
    }

    // MARK: Install

    private struct UpdateError: Error {}

    func install() {
        guard let release = latest, !isBusy else { return }
        status = .downloading
        URLSession.shared.downloadTask(with: release.dmg) { tmp, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            guard let tmp, ok else { return self.fail() }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("ScreenClipUpdate-\(UUID().uuidString)")
            let dmg = work.appendingPathComponent("update.dmg")
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                try fm.moveItem(at: tmp, to: dmg)
            } catch { return self.fail() }
            DispatchQueue.main.async { self.status = .installing }
            DispatchQueue.global(qos: .userInitiated).async {
                do { try self.apply(dmg: dmg, work: work) } catch { self.fail() }
            }
        }.resume()
    }

    private func fail() {
        DispatchQueue.main.async { self.status = .failed(L("Update failed.")) }
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError() }
        return p.terminationStatus
    }

    private func apply(dmg: URL, work: URL) throws {
        let fm = FileManager.default
        let mount = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        let newApp = work.appendingPathComponent("ScreenClip.app")
        do {
            try run("/usr/bin/ditto", [mount.appendingPathComponent("ScreenClip.app").path, newApp.path])
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        } catch {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            throw error
        }
        // Only ever replace ourselves with ScreenClip.
        guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else { throw UpdateError() }
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app",
              fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else { throw UpdateError() }

        // Wait for this process to quit, swap the bundle, relaunch, clean up.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$2" && mv "$3" "$2"
        open "$2"
        rm -rf "$4"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", "\(getpid())", target.path, newApp.path, work.path]
        try p.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}
