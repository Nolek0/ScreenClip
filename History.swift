import Cocoa
import ImageIO

// MARK: Storage

struct Shot: Identifiable, Hashable {
    let url: URL
    let date: Date
    var id: URL { url }
}

final class HistoryStore {
    static let shared = HistoryStore()
    static let maxItems = 200

    private(set) var shots: [Shot] = []
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

    func delete(_ shot: Shot) {
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
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

/// Custom menu row: big preview + date. Menus ignore large item images, so we draw our own view.
final class ShotMenuView: NSView {
    let onClick: () -> Void
    private var hovered = false { didSet { needsDisplay = true } }
    static let width: CGFloat = 280, previewH: CGFloat = 150

    init(image: NSImage?, title: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.previewH + 34))
        let iv = NSImageView(frame: NSRect(x: 14, y: 26, width: Self.width - 28, height: Self.previewH))
        iv.image = image
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 6
        iv.layer?.masksToBounds = true
        iv.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        addSubview(iv)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 14, y: 5, width: Self.width - 28, height: 16)
        addSubview(label)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
    }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited(with e: NSEvent) { hovered = false }
    override func mouseUp(with e: NSEvent) {
        enclosingMenuItem?.menu?.supermenu?.cancelTracking()
        enclosingMenuItem?.menu?.cancelTracking()
        onClick()
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
