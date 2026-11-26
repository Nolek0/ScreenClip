import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var source: DispatchSourceFileSystemObject?
    var folderFD: Int32 = -1
    var folder: URL!
    var known = Set<String>()
    let defaults = UserDefaults.standard

    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled"); rebuildMenu() }
    }
    var clickToCopy: Bool {
        get { defaults.object(forKey: "clickToCopy") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "clickToCopy"); rebuildMenu() }
    }
    /// macOS waits ~5 s (floating thumbnail) before saving the file. Turning the thumbnail off makes it instant.
    var instantCapture: Bool {
        get { UserDefaults(suiteName: "com.apple.screencapture")?.object(forKey: "show-thumbnail") as? Bool == false }
        set {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            p.arguments = ["write", "com.apple.screencapture", "show-thumbnail", "-bool", newValue ? "false" : "true"]
            try? p.run(); p.waitUntilExit()
            rebuildMenu()
        }
    }
    var deleteAfterCopy: Bool {
        get { defaults.bool(forKey: "deleteAfterCopy") }
        set { defaults.set(newValue, forKey: "deleteAfterCopy"); rebuildMenu() }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenClip")
        rebuildMenu()
        startWatching()
        // Keep the menu checkmarks in sync when the option is changed from the history window.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildMenu()
        }
        // Re-check the screenshot folder periodically in case the user changes it.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.screenshotFolder() != self.folder { self.startWatching() }
        }
    }

    // MARK: Folder watching

    func screenshotFolder() -> URL {
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (loc as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func listFiles() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    func startWatching() {
        source?.cancel()
        folder = screenshotFolder()
        known = listFiles()
        folderFD = open(folder.path, O_EVTONLY)
        guard folderFD >= 0 else { return }
        let fd = folderFD
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in self?.folderChanged() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
        rebuildMenu()
    }

    func folderChanged() {
        let now = listFiles()
        let added = now.subtracting(known)
        known = now
        guard enabled else { return }
        for name in added {
            tryCopy(folder.appendingPathComponent(name), attempt: 0)
        }
    }

    // The screenshot tag and image data can land slightly after the file appears: retry briefly.
    func tryCopy(_ url: URL, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.03 : 0.15)) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            if self.isScreenshot(url), self.copyToClipboard(url) { return }
            if attempt < 10 { self.tryCopy(url, attempt: attempt + 1) }
        }
    }

    func isScreenshot(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf"].contains(ext) else { return false }
        // macOS tags screenshots with this extended attribute.
        let size = getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0)
        return size > 0
    }

    @discardableResult
    func copyToClipboard(_ url: URL) -> Bool {
        guard writeImage(url) else { return false }
        HistoryStore.shared.add(url)
        if deleteAfterCopy {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        return true
    }

    /// Puts the image on the clipboard. Also used by the history window.
    func writeImage(_ url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url), image.isValid else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        flashIcon()
        return true
    }

    func flashIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenClip")
        }
    }

    // MARK: Menu

    func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "ScreenClip", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if let folder {
            let f = NSMenuItem(title: "Folder: \(folder.lastPathComponent)", action: nil, keyEquivalent: "")
            f.isEnabled = false
            menu.addItem(f)
        }
        menu.addItem(.separator())
        let h = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        h.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let sub = NSMenu(title: "History")  // new each rebuild: a submenu can only have one parent
        sub.delegate = self
        h.submenu = sub
        menu.addItem(h)
        menu.addItem(.separator())
        add(menu, "Copy Automatically", #selector(toggleEnabled), enabled)
        add(menu, "Instant Capture (No Thumbnail)", #selector(toggleInstant), instantCapture)
        add(menu, "Click to Copy in History", #selector(toggleClickToCopy), clickToCopy)
        add(menu, "Delete File After Copying", #selector(toggleDelete), deleteAfterCopy)
        add(menu, "Launch at Login", #selector(toggleLogin), SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ScreenClip", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func add(_ menu: NSMenu, _ title: String, _ sel: Selector, _ on: Bool) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        menu.addItem(item)
    }

    @objc func toggleEnabled() { enabled.toggle() }
    @objc func toggleInstant() { instantCapture.toggle() }
    @objc func toggleClickToCopy() { clickToCopy.toggle() }
    // MARK: History submenu (filled each time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "History" else { return }
        menu.removeAllItems()
        let store = HistoryStore.shared
        store.reload()
        if store.shots.isEmpty {
            let e = NSMenuItem(title: "No screenshots yet", action: nil, keyEquivalent: "")
            e.isEnabled = false
            menu.addItem(e)
            return
        }
        let header = NSMenuItem(title: clickToCopy ? "Click a screenshot to copy it" : "Click a screenshot to open it",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateStyle = .short; fmt.timeStyle = .medium; fmt.doesRelativeDateFormatting = true
        for shot in store.shots.prefix(30) {
            let url = shot.url
            let item = NSMenuItem()
            item.view = ShotMenuView(image: Thumbs.load(url), title: fmt.string(from: shot.date)) { [weak self] in
                self?.historyClicked(url)
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "Open History Folder", action: #selector(openHistoryFolder), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    func historyClicked(_ url: URL) {
        if clickToCopy { _ = writeImage(url) } else { NSWorkspace.shared.open(url) }
    }
    @objc func openHistoryFolder() { NSWorkspace.shared.open(HistoryStore.shared.dir) }
    @objc func clearHistory() { HistoryStore.shared.clear() }
    @objc func toggleDelete() { deleteAfterCopy.toggle() }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change Launch at Login"
            a.informativeText = "Move ScreenClip.app to your Applications folder and try again.\n\(error.localizedDescription)"
            a.runModal()
        }
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
