import Cocoa
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var source: DispatchSourceFileSystemObject?
    var folder: URL!
    var known = Set<String>()
    weak var historyMenu: NSMenu?
    var cancellables = Set<AnyCancellable>()
    let defaults = UserDefaults.standard

    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    var clickToCopy: Bool { defaults.object(forKey: "clickToCopy") as? Bool ?? true }
    var permanentDelete: Bool { defaults.bool(forKey: "permanentDelete") }
    var deleteAfterCopy: Bool { defaults.bool(forKey: "deleteAfterCopy") }
    var historyMenuCount: Int { defaults.object(forKey: "historyMenuCount") as? Int ?? 30 }
    var autoCheckUpdates: Bool { defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true }

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenClip")
        startWatching()
        rebuildMenu()

        // Settings (incl. language) can change from the Settings window: keep the menu in sync.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildMenu()
            SettingsWindow.shared.refreshTitle()
        }
        Updater.shared.$status.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }.store(in: &cancellables)

        // Re-check the screenshot folder periodically in case the user changes it.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Prefs.screenshotFolder() != self.folder { self.startWatching() }
        }
        if autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Updater.shared.check(silent: true) }
            Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
                if self?.autoCheckUpdates == true { Updater.shared.check(silent: true) }
            }
        }
    }

    // Opening the app again (e.g. double-click in Applications) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
    }

    // MARK: Folder watching

    func listFiles() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    func startWatching() {
        source?.cancel()
        folder = Prefs.screenshotFolder()
        known = listFiles()
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
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
        return getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
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

    /// Puts the image on the clipboard. Also used by the history menu.
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
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let title = NSMenuItem(title: "ScreenClip", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if let folder {
            let f = NSMenuItem(title: Lf("Folder: %@", folder.lastPathComponent), action: nil, keyEquivalent: "")
            f.isEnabled = false
            menu.addItem(f)
        }
        if Updater.shared.status == .available, let v = Updater.shared.latest?.version {
            let u = item(Lf("Update %@ Available", v), #selector(showUpdates))
            u.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(u)
        }
        menu.addItem(.separator())

        let h = NSMenuItem(title: L("History"), action: nil, keyEquivalent: "")
        h.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let sub = NSMenu(title: L("History"))  // new each rebuild: a submenu can only have one parent
        sub.delegate = self
        h.submenu = sub
        historyMenu = sub
        menu.addItem(h)
        menu.addItem(.separator())

        let auto = item(L("Copy Automatically"), #selector(toggleEnabled))
        auto.state = enabled ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())

        let settings = item(L("Settings…"), #selector(showSettings), key: ",")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)
        let upd = item(L("Check for Updates…"), #selector(checkForUpdates))
        upd.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(upd)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit ScreenClip"), action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc func toggleEnabled() { enabled.toggle() }
    @objc func showSettings() { SettingsWindow.shared.show() }
    @objc func showUpdates() { SettingsWindow.shared.show(.updates) }
    @objc func checkForUpdates() {
        SettingsWindow.shared.show(.updates)
        Updater.shared.check()
    }

    // MARK: History submenu (filled each time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === historyMenu else { return }
        menu.removeAllItems()
        let store = HistoryStore.shared
        store.reload()
        if store.shots.isEmpty {
            let e = NSMenuItem(title: L("No screenshots yet"), action: nil, keyEquivalent: "")
            e.isEnabled = false
            menu.addItem(e)
            return
        }
        let clearItem = NSMenuItem()
        clearItem.view = ClearMenuView(label: permanentDelete ? L("Delete History Permanently") : L("Clear History")) { [weak self] in
            self?.clearHistory()
        }
        menu.addItem(clearItem)
        let perm = item(L("Skip Trash (Delete Permanently)"), #selector(togglePermanent))
        perm.state = permanentDelete ? .on : .off
        menu.addItem(perm)
        menu.addItem(.separator())
        let header = NSMenuItem(title: clickToCopy ? L("Click a screenshot to copy it") : L("Click a screenshot to open it"),
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let fmt = DateFormatter()
        fmt.locale = Lang.locale
        fmt.dateStyle = .short; fmt.timeStyle = .medium; fmt.doesRelativeDateFormatting = true
        for shot in store.shots.prefix(historyMenuCount) {
            let url = shot.url
            let row = NSMenuItem()
            row.view = ShotMenuView(image: Thumbs.load(url), title: fmt.string(from: shot.date)) { [weak self] in
                self?.historyClicked(url)
            }
            menu.addItem(row)
        }
        menu.addItem(.separator())
        menu.addItem(item(L("Open History Folder"), #selector(openHistoryFolder)))
    }

    func historyClicked(_ url: URL) {
        if clickToCopy { _ = writeImage(url) } else { NSWorkspace.shared.open(url) }
    }
    @objc func openHistoryFolder() { NSWorkspace.shared.open(HistoryStore.shared.dir) }
    @objc func togglePermanent() { defaults.set(!permanentDelete, forKey: "permanentDelete") }

    func clearHistory() {
        let count = HistoryStore.shared.shots.count
        if permanentDelete {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.alertStyle = .critical
            a.messageText = Lf("Permanently delete %d screenshots?", count)
            a.informativeText = L("They won't go to the Trash. This can't be undone.")
            a.addButton(withTitle: L("Delete Permanently")).hasDestructiveAction = true
            a.addButton(withTitle: L("Cancel"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        HistoryStore.shared.clear(permanently: permanentDelete)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
