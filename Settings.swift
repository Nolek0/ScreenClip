import Cocoa
import SwiftUI
import ServiceManagement

// MARK: Shared preferences

enum Prefs {
    /// macOS's own "Show Floating Thumbnail" setting. While on, macOS saves the file (and so we copy) ~5 s later.
    static var showThumbnail: Bool {
        get { UserDefaults(suiteName: "com.apple.screencapture")?.object(forKey: "show-thumbnail") as? Bool ?? true }
        set {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            p.arguments = ["write", "com.apple.screencapture", "show-thumbnail", "-bool", newValue ? "true" : "false"]
            try? p.run(); p.waitUntilExit()
        }
    }

    static var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    static func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = L("Couldn't change Launch at Login")
            a.informativeText = L("Move ScreenClip.app to your Applications folder and try again.") + "\n" + error.localizedDescription
            a.runModal()
        }
    }

    static func screenshotFolder() -> URL {
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (loc as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}

// MARK: Window

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, history, updates, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return L("General")
        case .history: return L("History")
        case .updates: return L("Updates")
        case .about: return L("About")
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .history: return "clock.fill"
        case .updates: return "arrow.down.circle.fill"
        case .about: return "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .general: return .gray
        case .history: return .blue
        case .updates: return .green
        case .about: return .purple
        }
    }
}

final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab: SettingsTab = .general
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(_ tab: SettingsTab? = nil) {
        if let tab { SettingsNav.shared.tab = tab }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView())
            w.center()
            window = w
            // Free the whole window (and its SwiftUI views) once it's closed.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.window?.contentViewController = nil; self?.window = nil }
            }
        }
        window?.title = L("ScreenClip Settings")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshTitle() { window?.title = L("ScreenClip Settings") }
}

// MARK: Root view

struct SettingsView: View {
    @AppStorage("language") private var language = "system"
    @ObservedObject private var nav = SettingsNav.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch nav.tab {
                case .general: GeneralPane()
                case .history: HistoryPane()
                case .updates: UpdatesPane()
                case .about: AboutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 720, height: 500)
        .id(language) // re-render every string when the language changes
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                Text("ScreenClip").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.top, 34)
            .padding(.bottom, 14)

            ForEach(SettingsTab.allCases) { tab in
                SidebarRow(tab: tab, selected: nav.tab == tab,
                           badge: tab == .updates && updater.status == .available) { nav.tab = tab }
            }
            Spacer()
            Text(Lf("Version %@", Updater.currentVersion))
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 12)
        }
        .padding(.horizontal, 10)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

struct SidebarRow: View {
    let tab: SettingsTab
    let selected: Bool
    let badge: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(tab.color.gradient))
                Text(tab.title).font(.system(size: 13))
                Spacer()
                if badge { Circle().fill(.red).frame(width: 8, height: 8) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.22) : (hover ? Color.primary.opacity(0.06) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Toggle with a grey explanation line under its title.
struct DetailToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Panes

struct GeneralPane: View {
    @AppStorage("language") private var language = "system"
    @AppStorage("enabled") private var enabled = true
    @AppStorage("deleteAfterCopy") private var deleteAfterCopy = false
    @AppStorage("recordingEnabled") private var recordingEnabled = true
    @AppStorage("recordHotkey") private var hotkey = 0
    @State private var showThumb = Prefs.showThumbnail
    @State private var login = Prefs.launchAtLogin
    @State private var folder = Prefs.screenshotFolder()

    var body: some View {
        Form {
            Section(L("Language")) {
                Picker(L("Language"), selection: $language) {
                    Text(L("System Default")).tag("system")
                    Divider()
                    ForEach(Lang.all, id: \.code) { Text($0.name).tag($0.code) }
                }
            }
            Section(L("Screenshots")) {
                Toggle(L("Copy screenshots automatically"), isOn: $enabled)
                DetailToggle(title: L("Show screenshot thumbnail"),
                             detail: L("macOS shows the preview in the corner, but copying waits about 5 seconds."),
                             isOn: $showThumb)
                    .onChange(of: showThumb) { Prefs.showThumbnail = $0 }
                DetailToggle(title: L("Delete file after copying"),
                             detail: L("The file goes to the Trash once it's in your clipboard. It stays in the history."),
                             isOn: $deleteAfterCopy)
                LabeledContent(L("Screenshot folder")) {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.blue)
                        Text(folder.lastPathComponent).foregroundStyle(.secondary)
                        Button(L("Show in Finder")) { NSWorkspace.shared.open(folder) }
                    }
                }
            }
            Section(L("Screen Recording")) {
                DetailToggle(title: L("Record the screen with a shortcut"),
                             detail: Lf("Press %@ to start recording the screen, and again to stop. The video goes to your clipboard and history.", HotKey.presets[hotkey].label),
                             isOn: $recordingEnabled)
                Picker(L("Shortcut"), selection: $hotkey) {
                    ForEach(HotKey.presets.indices, id: \.self) { Text(HotKey.presets[$0].label).tag($0) }
                }
                .disabled(!recordingEnabled)
            }
            Section(L("App")) {
                Toggle(L("Launch at login"), isOn: $login)
                    .onChange(of: login) { on in
                        guard on != Prefs.launchAtLogin else { return }
                        Prefs.setLaunchAtLogin(on)
                        login = Prefs.launchAtLogin
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            showThumb = Prefs.showThumbnail
            login = Prefs.launchAtLogin
            folder = Prefs.screenshotFolder()
        }
    }
}

struct HistoryPane: View {
    @AppStorage("clickToCopy") private var clickToCopy = true
    @AppStorage("historyMenuCount") private var menuCount = 30
    @AppStorage("permanentDelete") private var permanentDelete = false
    @AppStorage("deleteOriginals") private var deleteOriginals = true
    @ObservedObject private var store = HistoryStore.shared

    var body: some View {
        Form {
            Section(L("History menu")) {
                DetailToggle(title: L("Click to copy"),
                             detail: L("Clicking a screenshot in the History menu copies it. When off, it opens in Preview."),
                             isOn: $clickToCopy)
                Picker(L("Screenshots shown in menu"), selection: $menuCount) {
                    ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Section(L("Storage")) {
                LabeledContent(L("Saved screenshots")) {
                    Text("\(store.shots.count)").monospacedDigit().foregroundStyle(.secondary)
                }
                DetailToggle(title: L("Also delete the original screenshots"),
                             detail: L("Clearing or deleting from the history also removes the screenshot files from your Desktop."),
                             isOn: $deleteOriginals)
                Toggle(L("Skip Trash when clearing"), isOn: $permanentDelete)
                HStack {
                    Button(L("Open History Folder")) { NSWorkspace.shared.open(store.dir) }
                    Spacer()
                    Button {
                        (NSApp.delegate as? AppDelegate)?.clearHistory()
                    } label: {
                        Label(permanentDelete ? L("Delete History Permanently") : L("Clear History"), systemImage: "trash.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(store.shots.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { store.reload() }
    }
}

struct UpdatesPane: View {
    @AppStorage("autoCheckUpdates") private var autoCheck = true
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ScreenClip").font(.title3.weight(.semibold))
                        Text(Lf("Version %@", Updater.currentVersion)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusView
                }
                .padding(.vertical, 4)
            }
            if updater.status == .available || updater.status == .downloading || updater.status == .installing,
               let r = updater.latest {
                Section(L("What's new")) {
                    Text(Lf("Version %@ is available.", r.version)).font(.headline)
                    ScrollView {
                        Text(notes(r.notes))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 150)
                    HStack {
                        Text(L("ScreenClip will restart to finish updating.")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("View on GitHub")) { NSWorkspace.shared.open(r.page) }
                        Button(L("Update Now")) { updater.install() }
                            .buttonStyle(.borderedProminent)
                            .disabled(updater.isBusy)
                    }
                }
            }
            Section {
                Toggle(L("Check automatically at launch"), isOn: $autoCheck)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var statusView: some View {
        switch updater.status {
        case .checking: progress(L("Checking…"))
        case .downloading: progress(L("Downloading…"))
        case .installing: progress(L("Installing…"))
        case .available:
            Label(Lf("Update %@ Available", updater.latest?.version ?? ""), systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        case .upToDate:
            VStack(alignment: .trailing, spacing: 6) {
                Label(L("You're up to date."), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button(L("Check Now")) { updater.check() }
            }
        case .failed(let msg):
            VStack(alignment: .trailing, spacing: 6) {
                Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Button(L("Check Now")) { updater.check() }
            }
        case .idle:
            Button(L("Check Now")) { updater.check() }.buttonStyle(.borderedProminent)
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text).foregroundStyle(.secondary) }
    }

    /// Release notes are Markdown: drop heading markers and render inline formatting.
    private func notes(_ md: String) -> AttributedString {
        let cleaned = md.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            while l.hasPrefix("#") { l.removeFirst() }
            return l.trimmingCharacters(in: .init(charactersIn: " "))
        }.joined(separator: "\n")
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(cleaned)
    }
}

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            Text("ScreenClip").font(.system(size: 28, weight: .bold))
            Text(Lf("Version %@", Updater.currentVersion)).foregroundStyle(.secondary)
            Text(L("Copies your Mac screenshots straight to the clipboard."))
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/\(Updater.repo)")!)
            } label: {
                Label(L("View on GitHub"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
            Spacer()
            Text("MIT License").font(.caption).foregroundStyle(.tertiary).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }
}
