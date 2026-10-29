import AVFoundation
import CoreVideo
import Foundation
import UIKit
import UserNotifications

/// Progress selfies kept on this iPhone, plus the weekly or monthly reminder.
enum ProgressAlbum {
    static let maxCount = 5
    static let cadenceKey = "progressPhoto.cadence"
    static let askedBeforeKey = "progressPhoto.askedBefore"
    static let cadenceSetAtKey = "progressPhoto.cadenceSetAt"
    static let snoozeUntilKey = "progressPhoto.snoozeUntil"
    static let videoAskedCountKey = "progressPhoto.videoAskedCount"

    enum Cadence: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: return String(localized: "Weekly")
            case .month: return String(localized: "Monthly")
            }
        }

        var progressPrompt: String {
            switch self {
            case .week: return String(localized: "Add this week's picture to your 10-second before-and-after.")
            case .month: return String(localized: "Add this month's picture to your 10-second before-and-after.")
            }
        }
    }

    struct Shot: Codable, Identifiable, Equatable {
        var id: UUID
        var date: Date
        var file: String
    }

    static var cadence: Cadence? {
        get { Cadence(rawValue: UserDefaults.standard.string(forKey: cadenceKey) ?? "") }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: cadenceKey)
            if newValue != nil, cadenceSetAt == nil { cadenceSetAt = .now }
        }
    }

    static var askedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: askedBeforeKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedBeforeKey) }
    }

    static var cadenceSetAt: Date? {
        get {
            let value = UserDefaults.standard.double(forKey: cadenceSetAtKey)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: cadenceSetAtKey) }
    }

    static var snoozeUntil: Date? {
        get {
            let value = UserDefaults.standard.double(forKey: snoozeUntilKey)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: snoozeUntilKey) }
    }

    static var videoAskedCount: Int {
        get { UserDefaults.standard.integer(forKey: videoAskedCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: videoAskedCountKey) }
    }

    static func load() -> [Shot] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([Shot].self, from: data))?.sorted { $0.date < $1.date } ?? []
    }

    @discardableResult
    static func add(_ image: UIImage, date: Date = .now) -> Shot {
        let shot = Shot(id: UUID(), date: date, file: "\(UUID().uuidString).jpg")
        let stored = scaled(image, maxSide: 1600)
        if let data = stored.jpegData(compressionQuality: 0.86) {
            try? data.write(to: directory.appendingPathComponent(shot.file), options: .atomic)
        }
        var shots = load()
        shots.append(shot)
        persist(shots)
        snoozeUntil = nil
        return shot
    }

    static func image(for shot: Shot, maxSide: CGFloat? = nil) -> UIImage? {
        let url = directory.appendingPathComponent(shot.file)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        guard let maxSide else { return image }
        return scaled(image, maxSide: maxSide)
    }

    /// A picture is due once the chosen week or month has passed since the last selfie.
    static func isDue(shots: [Shot] = load()) -> Bool {
        guard cadence != nil else { return false }
        if shots.isEmpty { return false }
        if let snoozeUntil, snoozeUntil > .now { return false }
        guard let due = nextDueDate(shots: shots) else { return false }
        return due <= .now
    }

    static func nextDueDate(shots: [Shot] = load()) -> Date? {
        guard let cadence else { return nil }
        let anchor = shots.map(\.date).max() ?? cadenceSetAt
        guard let anchor else { return nil }
        let calendar = Calendar.current
        switch cadence {
        case .week:
            return calendar.date(byAdding: .day, value: 7, to: anchor)
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: anchor)
        }
    }

    static func weekTitle(_ week: Int) -> String {
        String(localized: "Week \(week)")
    }

    static func frame(_ image: UIImage, week: Int) -> UIImage {
        let size = ProgressFilm.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let titleFont = UIFont(descriptor: UIFont.systemFont(ofSize: 88, weight: .heavy).fontDescriptor.withDesign(.rounded) ?? UIFont.systemFont(ofSize: 88, weight: .heavy).fontDescriptor, size: 88)
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            image.draw(in: aspectFill(image.size, in: size))
            let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.78).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                renderer.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: size.height - 460),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
            let title = weekTitle(week) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white
            ]
            let bounds = title.size(withAttributes: attrs)
            title.draw(
                at: CGPoint(x: (size.width - bounds.width) / 2, y: size.height - 220),
                withAttributes: attrs
            )
        }
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var indexURL: URL { directory.appendingPathComponent("shots.json") }

    private static func persist(_ shots: [Shot]) {
        guard let data = try? JSONEncoder().encode(shots) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func scaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else {
            return redraw(image, size: image.size)
        }
        let ratio = maxSide / longest
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return redraw(image, size: size)
    }

    static func redrawn(_ image: UIImage, size: CGSize) -> UIImage {
        redraw(image, size: size)
    }

    static var filmURL: URL { directory.appendingPathComponent("progress.mp4") }

    static var hasFilm: Bool { FileManager.default.fileExists(atPath: filmURL.path) }

    static func storeFilm(from temporary: URL) throws -> URL {
        let dest = filmURL
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: temporary, to: dest)
        return dest
    }

    private static func redraw(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func aspectFill(_ image: CGSize, in canvas: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: canvas) }
        let scale = max(canvas.width / image.width, canvas.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (canvas.width - size.width) / 2,
            y: (canvas.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// One local reminder for the next progress selfie. Removed when notifications are off.
@MainActor
enum ProgressPhotoReminder {
    private static let identifier = "spotter.progress.photo"

    static func reschedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard UserDefaults.standard.bool(forKey: "pushEnabled") else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }
        guard let fire = nextFireDate(), fire > .now else { return }

        let shots = ProgressAlbum.load()
        let content = UNMutableNotificationContent()
        if shots.isEmpty {
            content.title = String(localized: "Before selfie")
            content.body = String(localized: "Take the picture that starts your 10-second before-and-after.")
        } else if ProgressAlbum.cadence == .month {
            content.title = String(localized: "Monthly progress picture")
            content.body = String(localized: "Add this month's selfie to your 10-second progress video.")
        } else {
            content.title = String(localized: "Weekly progress picture")
            content.body = String(localized: "Add this week's selfie to your 10-second progress video.")
        }
        content.sound = .default
        content.userInfo = ["screen": "progressPhoto"]

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private static func nextFireDate() -> Date? {
        guard let due = ProgressAlbum.nextDueDate() else { return nil }
        var when = due
        if let snooze = ProgressAlbum.snoozeUntil, snooze > when { when = snooze }
        let timed = atReminderClock(when)
        if timed > .now { return timed }
        return nextReminderClock(after: .now)
    }

    private static func atReminderClock(_ day: Date) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        parts.hour = UserDefaults.standard.object(forKey: DayReminder.hourKey) as? Int ?? 8
        parts.minute = UserDefaults.standard.object(forKey: DayReminder.minuteKey) as? Int ?? 0
        return Calendar.current.date(from: parts) ?? day
    }

    private static func nextReminderClock(after date: Date) -> Date? {
        let calendar = Calendar.current
        let today = atReminderClock(date)
        if today > date { return today }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        return atReminderClock(tomorrow)
    }
}

/// A 10-second film of every progress selfie, first to latest.
enum ProgressFilm {
    static let seconds = 10
    static let fps: Int32 = 30
    static let size = CGSize(width: 1080, height: 1920)

    enum FilmError: Error {
        case empty
        case unwritable
    }

    static func write(_ images: [UIImage]) throws -> URL {
        let prepared = images.filter { $0.cgImage != nil }
        guard !prepared.isEmpty else { throw FilmError.empty }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotter-progress-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        input.transform = .identity
        guard writer.canAdd(input) else { throw FilmError.unwritable }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FilmError.unwritable }
        writer.startSession(atSourceTime: .zero)

        let buffers = try prepared.map { try pixelBuffer(from: $0) }
        let total = Int(fps) * seconds
        let queue = DispatchQueue(label: "spotter.progress.film")
        let finished = DispatchSemaphore(value: 0)
        var frame = 0
        var ended = false

        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData {
                if ended { return }
                if frame >= total || writer.status != .writing {
                    ended = true
                    input.markAsFinished()
                    writer.finishWriting { finished.signal() }
                    return
                }
                let index = min(buffers.count - 1, frame * buffers.count / total)
                let time = CMTime(value: CMTimeValue(frame), timescale: fps)
                if !adaptor.append(buffers[index], withPresentationTime: time) {
                    ended = true
                    input.markAsFinished()
                    writer.finishWriting { finished.signal() }
                    return
                }
                frame += 1
            }
        }
        finished.wait()
        guard writer.status == .completed else { throw writer.error ?? FilmError.unwritable }
        return url
    }

    /// Lays the workout mix under the 10-second film. The silent film is kept if the song cannot be added.
    static func withMusic(_ video: URL) async -> (url: URL, credited: Bool) {
        guard let song = BuiltInMix.songs.first?.audioURL else { return (video, false) }
        let picture = AVURLAsset(url: video)
        let music = AVURLAsset(url: song)
        guard let pictureTrack = try? await picture.loadTracks(withMediaType: .video).first,
              let musicTrack = try? await music.loadTracks(withMediaType: .audio).first else {
            return (video, false)
        }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return (video, false)
        }
        let duration = CMTime(seconds: Double(seconds), preferredTimescale: 600)
        do {
            let pictureDuration = try await pictureTrack.load(.timeRange).duration
            let musicDuration = try await musicTrack.load(.timeRange).duration
            try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: minTime(pictureDuration, duration)), of: pictureTrack, at: .zero)
            videoTrack.preferredTransform = .identity
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: minTime(musicDuration, duration)), of: musicTrack, at: .zero)
        } catch {
            return (video, false)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotter-progress-\(UUID().uuidString).mp4")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return (video, false)
        }
        exporter.outputURL = url
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else { return (video, false) }
        return (url, true)
    }

    private static func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) < 0 ? lhs : rhs
    }

    private static func pixelBuffer(from image: UIImage) throws -> CVPixelBuffer {
        let width = Int(size.width)
        let height = Int(size.height)
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { throw FilmError.unwritable }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { throw FilmError.unwritable }
        let upright = image.imageOrientation == .up ? image : ProgressAlbum.redrawn(image, size: CGSize(width: width, height: height))
        guard let cg = upright.cgImage else { throw FilmError.unwritable }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
