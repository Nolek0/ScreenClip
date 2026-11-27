import Cocoa
import ImageIO

// MARK: Storage

struct Shot: Identifiable, Hashable {
    let url: URL
    let date: Date
    var id: URL { url }
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    static let maxItems = 200

    @Published private(set) var shots: [Shot] = []
    let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("ScreenClip/History", isDirectory: true)
        // Migrate the history folder used by early (French) builds.
        let old = base.appendingPathComponent("ScreenClip/Historique", isDirectory: true)
        if FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.moveItem(at: old, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        shots = urls.filter { !$0.lastPathComponent.hasPrefix(".") }.map { url in
            let d = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return Shot(url: url, date: d)
        }.sorted { $0.date > $1.date }
    }

    /// Keeps a private copy so the history survives even if the original is deleted.
    func add(_ source: URL) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        var dest = dir.appendingPathComponent("Screenshot \(f.string(from: Date())).\(source.pathExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("Screenshot \(f.string(from: Date())) (\(n)).\(source.pathExtension)"); n += 1
        }
        guard (try? FileManager.default.copyItem(at: source, to: dest)) != nil else { return }
        reload()
        for old in shots.dropFirst(Self.maxItems) { try? FileManager.default.removeItem(at: old.url) }
        if shots.count > Self.maxItems { reload() }
    }

    func delete(_ url: URL, permanently: Bool) {
        if permanently { try? FileManager.default.removeItem(at: url) }
        else { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        Thumbs.cache.removeObject(forKey: url as NSURL)
        reload()
    }

    /// permanently: true deletes the files for good instead of moving them to the Trash.
    func clear(permanently: Bool) {
        for s in shots {
            if permanently { try? FileManager.default.removeItem(at: s.url) }
            else { try? FileManager.default.trashItem(at: s.url, resultingItemURL: nil) }
        }
        Thumbs.cache.removeAllObjects()
        reload()
    }
}

enum Thumbs {
    static let cache = NSCache<NSURL, NSImage>()
    static func load(_ url: URL, size: Int = 600) -> NSImage? {
        if let c = cache.object(forKey: url as NSURL) { return c }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        let img = NSImage(cgImage: cg, size: .zero)
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}


// MARK: Menu row with a visible preview

/// A button shown over the preview after a right-click.
struct ShotAction {
    let symbol: String
    let title: String
    /// true: close the History menu before running (needed for AirDrop, Finder…).
    let closesMenu: Bool
    let run: () -> Void
}

/// Custom menu row: big preview + date. Menus ignore large item images, so we draw our own view.
/// Right-click (or ctrl-click) shows action buttons over the preview, inside the menu.
final class ShotMenuView: NSView {
    let onClick: () -> Void
    var actions: [ShotAction] = [] { didSet { overlay.actions = actions } }
    private var hovered = false { didSet { needsDisplay = true } }
    private let overlay = ActionOverlay()
    private var showingActions = false {
        didSet { overlay.isHidden = !showingActions; overlay.hoverIndex = nil }
    }
    static let width: CGFloat = 280, previewH: CGFloat = 150
    private var previewFrame: NSRect { NSRect(x: 14, y: 26, width: Self.width - 28, height: Self.previewH) }

    init(image: NSImage?, title: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.previewH + 34))
        let iv = NSImageView(frame: previewFrame)
        iv.image = image
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 6
        iv.layer?.masksToBounds = true
        iv.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        addSubview(iv)
        overlay.frame = previewFrame
        overlay.isHidden = true
        addSubview(overlay)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 14, y: 5, width: Self.width - 28, height: 16)
        addSubview(label)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    // Keep every click for this view (the image and label must not swallow them).
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
    }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited(with e: NSEvent) { hovered = false; showingActions = false }
    override func mouseMoved(with e: NSEvent) {
        guard showingActions else { return }
        overlay.hoverIndex = overlay.index(at: overlay.convert(e.locationInWindow, from: nil))
    }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) {
        if e.modifierFlags.contains(.control) { return toggleActions() }  // ctrl-click = right-click
        if showingActions {
            if let i = overlay.index(at: overlay.convert(e.locationInWindow, from: nil)) {
                let action = actions[i]
                if action.closesMenu {
                    closeMenu()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { action.run() }
                } else {
                    action.run()
                    showingActions = false
                }
            } else {
                showingActions = false
            }
            return
        }
        closeMenu()
        onClick()
    }
    override func rightMouseDown(with e: NSEvent) { toggleActions() }
    override func rightMouseUp(with e: NSEvent) {}

    private func toggleActions() {
        guard !actions.isEmpty else { return }
        showingActions.toggle()
        if showingActions {
            overlay.hoverIndex = overlay.index(at: overlay.convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil))
        }
    }
    private func closeMenu() {
        enclosingMenuItem?.menu?.supermenu?.cancelTracking()
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

/// Dark layer over the preview with round icon buttons.
final class ActionOverlay: NSView {
    var actions: [ShotAction] = [] { didSet { needsDisplay = true } }
    var hoverIndex: Int? { didSet { if oldValue != hoverIndex { needsDisplay = true } } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func slot(_ i: Int) -> NSRect {
        let w = bounds.width / CGFloat(max(actions.count, 1))
        return NSRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height)
    }
    func index(at p: NSPoint) -> Int? {
        guard bounds.contains(p) else { return nil }
        return actions.indices.first { slot($0).contains(p) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let d: CGFloat = 38
        for (i, a) in actions.enumerated() {
            let s = slot(i)
            let circle = NSRect(x: s.midX - d / 2, y: s.midY - 2, width: d, height: d)
            let hot = hoverIndex == i
            (a.symbol == "trash" ? NSColor.systemRed : (hot ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.18))).setFill()
            NSBezierPath(ovalIn: circle).fill()
            if hot && a.symbol == "trash" {
                NSColor.white.withAlphaComponent(0.25).setFill(); NSBezierPath(ovalIn: circle).fill()
            }
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold).applying(.init(paletteColors: [.white]))
            if let img = NSImage(systemSymbolName: a.symbol, accessibilityDescription: a.title)?.withSymbolConfiguration(cfg) {
                let sz = img.size
                img.draw(in: NSRect(x: circle.midX - sz.width / 2, y: circle.midY - sz.height / 2, width: sz.width, height: sz.height))
            }
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .medium),
                                                        .foregroundColor: NSColor.white, .paragraphStyle: para]
            (a.title as NSString).draw(in: NSRect(x: s.minX, y: circle.minY - 17, width: s.width, height: 13), withAttributes: attrs)
        }
    }
}

/// Red "Clear History" button shown at the top of the History submenu.
final class ClearMenuView: NSView {
    let onClick: () -> Void
    private let label: String
    private var hovered = false { didSet { needsDisplay = true } }

    init(label: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        self.label = label
        super.init(frame: NSRect(x: 0, y: 0, width: ShotMenuView.width, height: 44))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 12, dy: 6)
        (hovered ? NSColor.systemRed.blended(withFraction: 0.2, of: .black)! : NSColor.systemRed).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        let text = NSMutableAttributedString()
        if let icon = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold).applying(.init(paletteColors: [.white]))) {
            let a = NSTextAttachment(); a.image = icon
            text.append(NSAttributedString(attachment: a))
            text.append(NSAttributedString(string: "  "))
        }
        text.append(NSAttributedString(string: label))
        text.addAttributes([.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white],
                           range: NSRange(location: 0, length: text.length))
        let s = text.size()
        text.draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2))
    }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited(with e: NSEvent) { hovered = false }
    override func mouseUp(with e: NSEvent) {
        enclosingMenuItem?.menu?.supermenu?.cancelTracking()
        enclosingMenuItem?.menu?.cancelTracking()
        // Let the menu close before showing any alert.
        DispatchQueue.main.async { self.onClick() }
    }
}
