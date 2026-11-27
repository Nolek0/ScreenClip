import AVFoundation
import Cocoa
import ScreenCaptureKit

/// Records the screen under the mouse to a .mov file.
/// Frames go straight from ScreenCaptureKit to the hardware H.264 encoder and onto disk, so memory stays low.
final class Recorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    static let shared = Recorder()
    static let recordingAttr = "com.screenclip.recording"

    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    private(set) var startDate: Date?

    /// Called on the main thread with the finished file (nil if nothing was recorded).
    var onFinished: ((URL?) -> Void)?
    /// Called on the main thread when recording can't start.
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private var outputURL: URL?
    private let queue = DispatchQueue(label: "screenclip.recorder", qos: .userInitiated)

    func toggle() { isRecording ? stop() : start() }

    func start() {
        guard !isRecording, !isBusy else { return }
        isBusy = true
        Task {
            do {
                try await begin()
                await MainActor.run { self.isBusy = false; self.isRecording = true; self.startDate = Date() }
            } catch {
                self.cleanup(deleteFile: true)
                await MainActor.run { self.isBusy = false; self.onError?(error) }
            }
        }
    }

    private func begin() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Record the display the mouse is on.
        let (displayID, scale): (CGDirectDisplayID, CGFloat) = await MainActor.run {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
            return (id, screen.backingScaleFactor)
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw NSError(domain: "ScreenClip", code: 1)
        }

        // Native resolution, capped at 2560 px wide to keep files and memory small.
        var w = Int(CGFloat(display.width) * scale), h = Int(CGFloat(display.height) * scale)
        if w > 2560 { h = h * 2560 / w; w = 2560 }
        w -= w % 2; h -= h % 2

        let cfg = SCStreamConfiguration()
        cfg.width = w
        cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange  // half the memory of BGRA, what the encoder wants
        cfg.queueDepth = 4
        cfg.showsCursor = true

        let url = Self.newFileURL()
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(4_000_000, w * h * 3),
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw NSError(domain: "ScreenClip", code: 2) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "ScreenClip", code: 3) }

        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        queue.sync {
            self.writer = writer
            self.input = input
            self.outputURL = url
            self.sessionStarted = false
            self.stream = stream
        }
        try await stream.startCapture()
    }

    static func newFileURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return Prefs.screenshotFolder().appendingPathComponent("Screen Recording \(f.string(from: Date())).mov")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid, let writer, let input, writer.status == .writing else { return }
        // Only frames with new content.
        guard let info = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = info.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: sb.presentationTimeStamp)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.stop() }
    }

    func stop() {
        guard isRecording, let stream else { return }
        isRecording = false
        isBusy = true
        Task {
            try? await stream.stopCapture()
            queue.async {
                guard let writer = self.writer, let input = self.input, self.sessionStarted else {
                    self.cleanup(deleteFile: true)
                    DispatchQueue.main.async { self.isBusy = false; self.onFinished?(nil) }
                    return
                }
                // Keep the video running until the moment the user stopped, even if the screen didn't change.
                writer.endSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
                input.markAsFinished()
                let url = self.outputURL
                writer.finishWriting {
                    let ok = writer.status == .completed
                    if ok, let url {
                        let tag = Array("1".utf8)
                        _ = setxattr(url.path, Self.recordingAttr, tag, tag.count, 0, 0)
                    }
                    self.cleanup(deleteFile: !ok)
                    DispatchQueue.main.async { self.isBusy = false; self.onFinished?(ok ? url : nil) }
                }
            }
        }
    }

    private func cleanup(deleteFile: Bool) {
        queue.async {
            if deleteFile, let url = self.outputURL { try? FileManager.default.removeItem(at: url) }
            self.stream = nil
            self.writer = nil
            self.input = nil
            self.outputURL = nil
            self.sessionStarted = false
        }
        DispatchQueue.main.async { self.startDate = nil }
    }
}
