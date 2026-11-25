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
        dir = base.appendingPathComponent("ScreenClip/Historique", isDirectory: true)
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
        f.dateFormat = "yyyy-MM-dd 'à' HH.mm.ss"
        var dest = dir.appendingPathComponent("Capture \(f.string(from: Date())).\(source.pathExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("Capture \(f.string(from: Date())) (\(n)).\(source.pathExtension)"); n += 1
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

    func clear() {
        for s in shots { try? FileManager.default.trashItem(at: s.url, resultingItemURL: nil) }
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
