import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UIKit

/// Asks for the first selfie, then for weekly or monthly pictures, then for a shareable 10-second video.
@MainActor
final class ProgressPhotoCenter: ObservableObject {
    @Published private(set) var shots: [ProgressAlbum.Shot] = []
    @Published private(set) var thumbs: [UUID: UIImage] = [:]
    @Published var prompt: Prompt?
    @Published var showCamera = false
    @Published var showLibrary = false
    @Published var pickerItem: PhotosPickerItem?
    @Published var shareFile: ShareFile?
    @Published var viewer: ProgressViewer?
    @Published private(set) var hasFilm = ProgressAlbum.hasFilm
    @Published var rendering = false
    @Published var errorMessage: String?
    var filmCredit: String?

    private var followUp: Prompt?
    private var dismissHandled = false

    enum Prompt: Equatable {
        case before, cadence, progress, video

        var title: String {
            switch self {
            case .before: return String(localized: "Take your before selfie")
            case .cadence: return String(localized: "How often should Spotter ask?")
            case .progress: return String(localized: "Time for a progress picture")
            case .video: return String(localized: "Share a 10-second video?")
            }
        }

        var message: String {
            switch self {
            case .before:
                return String(localized: "A picture today starts a 10-second before-and-after. Spotter can remind you each week or month to add the next one.")
            case .cadence:
                return String(localized: "Choose weekly or monthly pictures so you can see your progress, then turn them into a video for friends.")
            case .progress:
                return ProgressAlbum.cadence?.progressPrompt
                    ?? String(localized: "Add a picture to your 10-second before-and-after.")
            case .video:
                return String(localized: "Spotter can turn your pictures into a 10-second video with Week 1 to Week 5 slides and music, ready to send to friends.")
            }
        }
    }

    struct ShareFile: Identifiable {
        let id = UUID()
        let url: URL
        var credit: String?
    }

    func openPhoto(_ shot: ProgressAlbum.Shot) {
        viewer = .photo(shot.id)
    }

    func openFilm() {
        guard ProgressAlbum.hasFilm else { return }
        viewer = .film
    }

    func shareSavedFilm() {
        guard ProgressAlbum.hasFilm else { return }
        shareFile = ShareFile(url: ProgressAlbum.filmURL, credit: filmCredit)
    }

    init() { reload() }

    func consider(paywallVisible: Bool) {
        if paywallVisible { prompt = nil }
    }

    /// Opened from the progress-picture notification. The pictures card is already on Progress.
    func presentFromNotification() {
        reload()
        prompt = nil
    }

    func beginCapture() {
        guard shots.count < ProgressAlbum.maxCount else {
            errorMessage = String(localized: "Five pictures is the limit for a 10-second video.")
            return
        }
        ProgressAlbum.askedBefore = true
        dismissHandled = false
        SpotterAnalytics.click("progress_photo_capture", screen: "progress_photo")
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showLibrary = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.showCamera = true }
                    else { self.showLibrary = true }
                }
            }
        default:
            showLibrary = true
        }
    }

    /// Hides the ask without recording an answer, so it can return on Progress.
    func hidePrompt() {
        guard !showCamera, !showLibrary else { return }
        prompt = nil
    }

    func declineBefore() {
        ProgressAlbum.askedBefore = true
        SpotterAnalytics.click("progress_photo_later", screen: "progress_photo", ["kind": "before"])
        queue(.cadence)
    }

    func choose(_ cadence: ProgressAlbum.Cadence) {
        ProgressAlbum.cadence = cadence
        SpotterAnalytics.click("progress_photo_cadence", screen: "progress_photo", ["value": cadence.rawValue])
        Task { await ProgressPhotoReminder.reschedule() }
    }

    func snooze() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
        ProgressAlbum.snoozeUntil = tomorrow
        SpotterAnalytics.click("progress_photo_later", screen: "progress_photo", ["kind": "due"])
        Task { await ProgressPhotoReminder.reschedule() }
    }

    func declineVideo() {
        ProgressAlbum.videoAskedCount = shots.count
        SpotterAnalytics.click("progress_photo_video_skip", screen: "progress_photo")
    }

    func save(_ image: UIImage) {
        guard shots.count < ProgressAlbum.maxCount else {
            showCamera = false
            showLibrary = false
            errorMessage = String(localized: "Five pictures is the limit for a 10-second video.")
            return
        }
        ProgressAlbum.add(image)
        reload()
        Haptics.success()
        SpotterAnalytics.log("progress_photo", ["count": shots.count])
        showCamera = false
        showLibrary = false
        pickerItem = nil
        Task { await ProgressPhotoReminder.reschedule() }
        followUp = nil
        prompt = nil
    }

    func cancelCapture() {
        showCamera = false
        followUp = nil
    }

    func captureSheetClosed() {
        guard !dismissHandled, !showCamera, !showLibrary else { return }
        dismissHandled = true
        followUp = nil
        prompt = nil
    }

    func makeVideo() {
        let chosen = Array(shots.prefix(ProgressAlbum.maxCount))
        let frames = chosen.enumerated().compactMap { index, shot -> UIImage? in
            guard let image = ProgressAlbum.image(for: shot) else { return nil }
            return ProgressAlbum.frame(image, week: index + 1)
        }
        guard !frames.isEmpty else {
            errorMessage = String(localized: "Take a selfie to make a 10-second video.")
            return
        }
        rendering = true
        SpotterAnalytics.click("progress_photo_video", screen: "progress_photo", ["count": frames.count])
        let payload = frames.compactMap { $0.pngData() }
        Task {
            defer { rendering = false }
            do {
                let silent = try await Task.detached(priority: .userInitiated) {
                    let images = payload.compactMap { UIImage(data: $0) }
                    return try ProgressFilm.write(images)
                }.value
                let mixed = await ProgressFilm.withMusic(silent)
                let stored = try ProgressAlbum.storeFilm(from: mixed.url)
                filmCredit = mixed.credited ? BuiltInMix.credit : nil
                ProgressAlbum.videoAskedCount = shots.count
                hasFilm = true
                viewer = .film
                _ = stored
                SpotterAnalytics.log("progress_video_ready", ["count": frames.count])
            } catch {
                errorMessage = String(localized: "Spotter couldn't make the video. Try again.")
            }
        }
    }

    #if DEBUG
    /// Fills in sample pictures when fewer than three exist, then shows the share alert.
    func previewTenSecondVideo() {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -14, to: .now) ?? .now
        if shots.count < 3 {
            let missing = 3 - shots.count
            for offset in 0..<missing {
                let index = shots.count + offset
                let date = calendar.date(byAdding: .day, value: index * 7, to: start) ?? .now
                ProgressAlbum.add(samplePicture(index), date: date)
            }
            reload()
        }
        ProgressAlbum.askedBefore = true
        ProgressAlbum.videoAskedCount = 0
        prompt = .video
    }

    private func samplePicture(_ index: Int) -> UIImage {
        let colors: [UIColor] = [
            UIColor(red: 0.776, green: 1, blue: 0.239, alpha: 1),
            UIColor(red: 1, green: 0.741, blue: 0.180, alpha: 1),
            UIColor(red: 0.545, green: 0.478, blue: 1, alpha: 1)
        ]
        let size = CGSize(width: 1080, height: 1920)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            colors[index % colors.count].setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let title = "\(index + 1)" as NSString
            let caption = "Sample" as NSString
            title.draw(
                in: CGRect(x: 80, y: 760, width: size.width - 160, height: 220),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 180, weight: .heavy),
                    .foregroundColor: UIColor.black
                ]
            )
            caption.draw(
                in: CGRect(x: 80, y: 980, width: size.width - 160, height: 80),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                    .foregroundColor: UIColor.black.withAlphaComponent(0.7)
                ]
            )
        }
    }
    #endif

    func reload() {
        shots = ProgressAlbum.load()
        var next: [UUID: UIImage] = [:]
        for shot in shots {
            next[shot.id] = ProgressAlbum.image(for: shot, maxSide: 360)
        }
        thumbs = next
        hasFilm = ProgressAlbum.hasFilm
    }

    private func queue(_ next: Prompt) {
        DispatchQueue.main.async { [weak self] in
            self?.prompt = next
        }
    }
}

struct ProgressPhotoPrompt: ViewModifier {
    @ObservedObject var photos: ProgressPhotoCenter

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $photos.showCamera, onDismiss: { photos.captureSheetClosed() }) {
                SelfieCamera(
                    onCapture: { photos.save($0) },
                    onCancel: { photos.cancelCapture() }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $photos.showLibrary, selection: $photos.pickerItem, matching: .images)
            .onChange(of: photos.pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photos.save(image)
                    }
                    photos.pickerItem = nil
                    photos.showLibrary = false
                }
            }
            .onChange(of: photos.showLibrary) { _, open in
                if !open { photos.captureSheetClosed() }
            }
            .fullScreenCover(item: $photos.viewer) { item in
                ProgressMediaCover(item: item)
                    .environmentObject(photos)
            }
            .sheet(item: $photos.shareFile) { file in
                ActivityShare(url: file.url, credit: file.credit)
                    .ignoresSafeArea()
            }
            .alert(
                "Progress video",
                isPresented: Binding(
                    get: { photos.errorMessage != nil },
                    set: { if !$0 { photos.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(photos.errorMessage ?? "")
            }
            .overlay {
                if photos.rendering {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().tint(Theme.accent)
                            Text("Making your 10-second video")
                                .font(.display(17, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
    }
}

struct ProgressPhotoStrip: View {
    @EnvironmentObject private var photos: ProgressPhotoCenter

    private var atLimit: Bool { photos.shots.count >= ProgressAlbum.maxCount }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Pictures").eyebrow()
                    Spacer()
                    Text("\(min(photos.shots.count, ProgressAlbum.maxCount)) of \(ProgressAlbum.maxCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                if photos.shots.isEmpty {
                    Text("Add up to 5 selfies. Spotter makes a 10-second video with Week 1 to Week 5 slides and music.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(photos.shots.prefix(ProgressAlbum.maxCount).enumerated()), id: \.element.id) { index, shot in
                                Button {
                                    photos.openPhoto(shot)
                                } label: {
                                    VStack(spacing: 6) {
                                        thumb(photos.thumbs[shot.id])
                                        Text(ProgressAlbum.weekTitle(index + 1))
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if ProgressAlbum.cadence == nil {
                    HStack(spacing: 8) {
                        Text("Reminders")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 8)
                        reminderButton("Weekly") { photos.choose(.week) }
                        reminderButton("Monthly") { photos.choose(.month) }
                    }
                }
                Button {
                    photos.beginCapture()
                } label: {
                    Label(atLimit ? "5 pictures saved" : "Take a selfie", systemImage: "camera.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(atLimit)
                .opacity(atLimit ? 0.45 : 1)
                if photos.hasFilm {
                    Button("Watch 10-second video") { photos.openFilm() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
                if !photos.shots.isEmpty {
                    Button(photos.hasFilm ? "Update 10-second video" : "Make a 10-second video") { photos.makeVideo() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func reminderButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.accent, in: Capsule())
    }

    private func thumb(_ image: UIImage?) -> some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.surfaceHigh
            }
        }
        .frame(width: 72, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum ProgressViewer: Identifiable {
    case photo(UUID)
    case film

    var id: String {
        switch self {
        case .photo(let id): return "photo-\(id.uuidString)"
        case .film: return "film"
        }
    }
}

private struct ProgressMediaCover: View {
    @EnvironmentObject private var photos: ProgressPhotoCenter
    @Environment(\.dismiss) private var dismiss
    let item: ProgressViewer
    @State private var share = false

    var body: some View {
        NavigationStack {
            Group {
                switch item {
                case .photo(let id): photo(id)
                case .film: film
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if case .film = item {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Share") { share = true }
                            .fontWeight(.bold)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $share) {
            ActivityShare(url: ProgressAlbum.filmURL, credit: photos.filmCredit)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func photo(_ id: UUID) -> some View {
        let shots = Array(photos.shots.prefix(ProgressAlbum.maxCount))
        if let index = shots.firstIndex(where: { $0.id == id }),
           let image = ProgressAlbum.image(for: shots[index]) {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text(ProgressAlbum.weekTitle(index + 1))
                    .font(.display(28, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(20)
            .navigationTitle(ProgressAlbum.weekTitle(index + 1))
        }
    }

    private var film: some View {
        FilmPlayer(url: ProgressAlbum.filmURL)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("10-second video")
    }
}

private struct FilmPlayer: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}

private struct SelfieCamera: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        if UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SelfieCamera
        init(_ parent: SelfieCamera) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

private struct ActivityShare: UIViewControllerRepresentable {
    let url: URL
    var credit: String?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [url]
        if let credit { items.append(credit) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        controller.popoverPresentationController?.sourceView = controller.view
    }
}
