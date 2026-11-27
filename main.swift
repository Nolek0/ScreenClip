import Cocoa
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var source: DispatchSourceFileSystemObject?
    var folder: URL!
    var known = Set<String>()
    weak var historyMenu: NSMenu?
    /// The menu bar menu is open: never rebuild it then (that's what left History empty).
    var menuIsOpen = false
    var needsRebuild = false
    var cancellables = Set<AnyCancellable>()
    var clipboardProvider: ClipboardImage?
    /// Set when the user picks "Check for Updates…": the menu reopens to show the result.
    var manualCheck = false
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
    var recordingEnabled: Bool {
        get { defaults.object(forKey: "recordingEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "recordingEnabled") }
    }
    var recTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenClip")
        startWatching()
        rebuildMenu()
        setupRecording()

        // Settings (incl. language) can change from the Settings window: keep the menu in sync.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildMenu()
            self?.applyHotkey()
            SettingsWindow.shared.refreshTitle()
        }
        Updater.shared.$status.receive(on: RunLoop.main).sink { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.rebuildMenu()
                if self.manualCheck, status != .checking {
                    self.manualCheck = false
                    self.statusItem.button?.performClick(nil)  // show the result right in the menu bar
                }
            }
        }.store(in: &cancellables)

        // Re-check the screenshot folder periodically in case the user changes it.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Also retry if watching never started (e.g. Desktop access granted after launch).
            if self.source == nil || Prefs.screenshotFolder() != self.folder { self.startWatching() }
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

    /// nil when the folder can't be read (e.g. Desktop access not granted yet).
    func listFiles() -> Set<String>? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    func startWatching() {
        source?.cancel()
        folder = Prefs.screenshotFolder()
        // Not readable yet: try again on the next timer tick rather than treating every file as new.
        guard let files = listFiles() else { source = nil; rebuildMenu(); return }
        known = files
        source = nil
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
        guard let now = listFiles() else { return }
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
    /// Puts PNG data on the clipboard. A TIFF version (some older apps want it) is only built if an app asks
    /// for it, so ScreenClip never keeps a big uncompressed copy of every screenshot in memory.
    func writeImage(_ url: URL) -> Bool {
        if Media.isVideo(url) { return writeFile(url) }
        let ok: Bool = autoreleasepool {
            guard let png = ClipboardImage.pngData(from: url) else { return false }
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            let provider = ClipboardImage(png: png)
            item.setDataProvider(provider, forTypes: [.tiff])
            let pb = NSPasteboard.general
            pb.clearContents()
            guard pb.writeObjects([item]) else { return false }
            clipboardProvider = provider
            return true
        }
        if ok { flashIcon() }
        return ok
    }

    /// Videos go on the clipboard as a file (like ⌘C in Finder): pasting works in Messages, Mail, Discord, Finder…
    /// and the video itself is never loaded into memory.
    func writeFile(_ url: URL) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.writeObjects([url as NSURL]) else { return false }
        flashIcon()
        return true
    }

    func flashIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.updateRecordingIndicator() }
    }

    // MARK: Screen recording

    func setupRecording() {
        Recorder.shared.onFinished = { [weak self] url in self?.recordingFinished(url) }
        Recorder.shared.onError = { [weak self] _ in self?.recordingFailed() }
        HotKey.shared.onPress = { [weak self] in
            guard let self, self.recordingEnabled || Recorder.shared.isRecording else { return }
            Recorder.shared.toggle()
        }
        applyHotkey()
        Recorder.shared.$isRecording.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateRecordingIndicator(); self?.rebuildMenu() }
        }.store(in: &cancellables)
    }

    private var registeredHotkey: String?
    func applyHotkey() {
        let want = recordingEnabled ? HotKey.currentPreset.label : nil
        guard want != registeredHotkey else { return }
        registeredHotkey = want
        if want != nil { HotKey.shared.register(HotKey.currentPreset) }
        else if !Recorder.shared.isRecording { HotKey.shared.unregister() }
    }

    /// Menu bar icon: a red dot and a timer while recording, the camera otherwise.
    func updateRecordingIndicator() {
        guard let button = statusItem.button else { return }
        if Recorder.shared.isRecording {
            let red = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")?
                .withSymbolConfiguration(red)
            button.imagePosition = .imageLeading
            let tick = { [weak self] in
                guard let start = Recorder.shared.startDate else { return }
                let s = Int(Date().timeIntervalSince(start))
                self?.statusItem.button?.title = String(format: " %d:%02d", s / 60, s % 60)
            }
            tick()
            if recTimer == nil { recTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() } }
        } else {
            recTimer?.invalidate(); recTimer = nil
            button.title = ""
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenClip")
        }
    }

    func recordingFinished(_ url: URL?) {
        updateRecordingIndicator()
        guard let url else { return }
        HistoryStore.shared.add(url)
        _ = writeFile(url)
        if deleteAfterCopy { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }

    func recordingFailed() {
        updateRecordingIndicator()
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L("Screen recording permission needed")
        a.informativeText = L("Allow ScreenClip in System Settings › Privacy & Security › Screen & System Audio Recording, then try again.")
        a.addButton(withTitle: L("Open System Settings"))
        a.addButton(withTitle: L("Cancel"))
        if a.runModal() == .alertFirstButtonReturn,
           let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc func toggleRecording() { Recorder.shared.toggle() }
    @objc func toggleRecordingEnabled() { recordingEnabled.toggle() }

    // MARK: Menu

    func rebuildMenu() {
        guard statusItem != nil else { return }
        if menuIsOpen { needsRebuild = true; return }
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "ScreenClip", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if let folder {
            let f = NSMenuItem(title: Lf("Folder: %@", folder.lastPathComponent), action: nil, keyEquivalent: "")
            f.isEnabled = false
            menu.addItem(f)
        }
        menu.addItem(.separator())
        if Recorder.shared.isRecording {
            let r = item(L("Stop Recording"), #selector(toggleRecording))
            r.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            if #available(macOS 14.4, *) { r.subtitle = HotKey.currentPreset.label }
            menu.addItem(r)
            menu.addItem(.separator())
        } else if recordingEnabled {
            let r = item(L("Start Recording"), #selector(toggleRecording))
            r.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
            if #available(macOS 14.4, *) { r.subtitle = HotKey.currentPreset.label }
            menu.addItem(r)
            menu.addItem(.separator())
        }

        let h = NSMenuItem(title: L("History"), action: nil, keyEquivalent: "")
        h.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let sub = HistoryMenu(title: L("History"))  // new each rebuild: a submenu can only have one parent
        sub.delegate = self
        h.submenu = sub
        historyMenu = sub
        menu.addItem(h)
        menu.addItem(.separator())

        menu.addItem(updateItem())
        menu.addItem(.separator())

        // Quick general settings (language stays in the Settings window).
        let g = NSMenuItem(title: L("General"), action: nil, keyEquivalent: "")
        g.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        let gm = NSMenu(title: L("General"))
        let auto = item(L("Copy screenshots automatically"), #selector(toggleEnabled))
        auto.state = enabled ? .on : .off
        gm.addItem(auto)
        let thumb = item(L("Show screenshot thumbnail"), #selector(toggleThumbnail))
        thumb.state = Prefs.showThumbnail ? .on : .off
        thumb.toolTip = L("macOS shows the preview in the corner, but copying waits about 5 seconds.")
        gm.addItem(thumb)
        let del = item(L("Delete file after copying"), #selector(toggleDeleteAfterCopy))
        del.state = deleteAfterCopy ? .on : .off
        gm.addItem(del)
        let rec = item(L("Record the screen with a shortcut"), #selector(toggleRecordingEnabled))
        rec.state = recordingEnabled ? .on : .off
        gm.addItem(rec)
        let login = item(L("Launch at login"), #selector(toggleLogin))
        login.state = Prefs.launchAtLogin ? .on : .off
        gm.addItem(login)
        g.submenu = gm
        menu.addItem(g)
        let settings = item(L("Settings…"), #selector(showSettings), key: ",")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)
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
    @objc func toggleThumbnail() { Prefs.showThumbnail.toggle(); rebuildMenu() }
    @objc func toggleDeleteAfterCopy() { defaults.set(!deleteAfterCopy, forKey: "deleteAfterCopy") }
    @objc func toggleLogin() { Prefs.setLaunchAtLogin(!Prefs.launchAtLogin); rebuildMenu() }
    @objc func checkForUpdates() {
        manualCheck = true
        Updater.shared.check()
    }
    @objc func installUpdate() { Updater.shared.install() }

    /// The update line of the menu: its text and action follow the updater's state.
    func updateItem() -> NSMenuItem {
        let u = Updater.shared
        let i: NSMenuItem
        switch u.status {
        case .idle:
            i = item(L("Check for Updates…"), #selector(checkForUpdates))
            i.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        case .checking, .downloading, .installing:
            let text = u.status == .checking ? L("Checking…") : (u.status == .downloading ? L("Downloading…") : L("Installing…"))
            i = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            i.isEnabled = false
            i.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)
        case .upToDate:
            i = item(L("You're up to date."), #selector(checkForUpdates))
            i.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.systemGreen]))
            if #available(macOS 14.4, *) { i.subtitle = Lf("Version %@", Updater.currentVersion) }
        case .available:
            i = item(Lf("Update %@ Available", u.latest?.version ?? ""), #selector(installUpdate))
            i.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.systemBlue]))
            if #available(macOS 14.4, *) { i.subtitle = L("Update Now") }
        case .failed(let msg):
            i = item(msg, #selector(checkForUpdates))
            i.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
            if #available(macOS 14.4, *) { i.subtitle = L("Check Now") }
        }
        return i
    }

    // MARK: History submenu (filled each time it opens)

    /// Free the previews as soon as the History menu closes.
    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem.menu { menuIsOpen = true }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menuIsOpen = false
        // Once everything is closed (and any clicked action has run), free the previews
        // and apply changes that came in while the menu was open.
        DispatchQueue.main.async {
            guard !self.menuIsOpen else { return }
            if let h = self.historyMenu {
                h.removeAllItems()
                h.addItem(NSMenuItem(title: L("History"), action: nil, keyEquivalent: ""))  // refilled on open
            }
            Thumbs.cache.removeAllObjects()
            if self.needsRebuild { self.needsRebuild = false; self.rebuildMenu() }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu is HistoryMenu else { return }
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
        let orig = item(L("Also delete the original screenshots"), #selector(toggleDeleteOriginals))
        orig.state = HistoryStore.deleteOriginals ? .on : .off
        menu.addItem(orig)
        menu.addItem(.separator())
        let header = NSMenuItem(title: clickToCopy ? L("Click a screenshot to copy it") : L("Click a screenshot to open it"),
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        if #available(macOS 14.4, *) { header.subtitle = L("Right-click for more options") }
        menu.addItem(header)
        let fmt = DateFormatter()
        fmt.locale = Lang.locale
        fmt.dateStyle = .short; fmt.timeStyle = .medium; fmt.doesRelativeDateFormatting = true
        for shot in store.shots.prefix(historyMenuCount) {
            let url = shot.url
            let row = NSMenuItem()
            let view = ShotMenuView(image: Thumbs.load(url), title: fmt.string(from: shot.date), badge: Thumbs.duration(url)) { [weak self] in
                self?.historyClicked(url)
            }
            view.actions = shotActions(url)
            row.view = view
            menu.addItem(row)
        }
        menu.addItem(.separator())
        menu.addItem(item(L("Open History Folder"), #selector(openHistoryFolder)))
    }

    // MARK: Right-click menu on a history screenshot

    func shotActions(_ url: URL) -> [ShotAction] {
        var list = [
            ShotAction(symbol: "doc.on.doc", title: L("Copy"), closesMenu: true) { [weak self] in _ = self?.writeImage(url) },
            ShotAction(symbol: "eye", title: L("Open"), closesMenu: true) { NSWorkspace.shared.open(url) },
            ShotAction(symbol: "folder", title: "Finder", closesMenu: true) { NSWorkspace.shared.activateFileViewerSelecting([url]) },
        ]
        if let airdrop = NSSharingService(named: .sendViaAirDrop), airdrop.canPerform(withItems: [url]) {
            list.append(ShotAction(symbol: "dot.radiowaves.left.and.right", title: "AirDrop", closesMenu: true) {
                NSApp.activate(ignoringOtherApps: true)
                airdrop.perform(withItems: [url])
            })
        }
        list.append(ShotAction(symbol: "trash", title: L("Delete"), closesMenu: true) { [weak self] in
            HistoryStore.shared.delete(url, permanently: self?.permanentDelete ?? false)
        })
        return list
    }

    func historyClicked(_ url: URL) {
        if clickToCopy { _ = writeImage(url) } else { NSWorkspace.shared.open(url) }
    }
    @objc func openHistoryFolder() { NSWorkspace.shared.open(HistoryStore.shared.dir) }
    @objc func toggleDeleteOriginals() { defaults.set(!HistoryStore.deleteOriginals, forKey: "deleteOriginals") }
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

/// Lazily turns the PNG into TIFF only when an app pastes asking for TIFF.
final class ClipboardImage: NSObject, NSPasteboardItemDataProvider {
    private var png: Data?
    init(png: Data) { self.png = png }

    static func pngData(from url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png", let d = try? Data(contentsOf: url) { return d }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        autoreleasepool {
            guard let png, let rep = NSBitmapImageRep(data: png),
                  let tiff = rep.tiffRepresentation(using: .lzw, factor: 0) else { return }
            item.setData(tiff, forType: type)
        }
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) { png = nil }
}

/// The History submenu, recognised by its class (never by a reference that a rebuild could replace).
final class HistoryMenu: NSMenu {}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
