import MediaPlayer
import SwiftUI

/// Vertical music tab on the live camera.
struct MusicSidebarButton: View {
    var playing: Bool
    var libraryOpen: Bool
    var action: () -> Void

    private var filled: Bool { playing || libraryOpen }

    var body: some View {
        Button(action: action) {
            ZStack {
                if playing {
                    MiniEqualizer(playing: true, color: .black)
                } else {
                    Image(systemName: libraryOpen ? "xmark" : "music.note")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(filled ? Color.black : Color.white)
            .frame(width: 44, height: 44)
            .background {
                Circle().fill(filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.black.opacity(0.72)))
            }
            .overlay {
                Circle().stroke(Color.white.opacity(filled ? 0 : 0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Workout music"))
        .accessibilityHint(Text(libraryOpen ? "Closes the song list" : "Opens songs to train with"))
    }
}

/// Playback controls shown with the song list after the music button is tapped.
struct NowPlayingStrip: View {
    @ObservedObject var player: WorkoutMusicPlayer

    @State private var scrubTime: TimeInterval = 0
    @State private var isScrubbing = false

    /// Catalog length, such as 2:11. The 30-second preview file must not replace it.
    private var shownDuration: TimeInterval {
        max(player.duration, player.currentTrack?.duration ?? 0)
    }

    var body: some View {
        if let track = player.currentTrack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    MiniEqualizer(playing: player.isPlaying && !player.isBuffering)
                }
                .foregroundStyle(.white)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(player.isPlaying ? "\(track.title) is playing" : "\(track.title) is paused"))

                VStack(spacing: 2) {
                        Slider(
                            value: Binding(
                                get: { isScrubbing ? scrubTime : player.currentTime },
                                set: { scrubTime = $0 }
                            ),
                            in: 0...max(shownDuration, 1),
                            onEditingChanged: { editing in
                                if editing {
                                    isScrubbing = true
                                    scrubTime = player.currentTime
                                } else {
                                    player.seek(to: scrubTime)
                                    isScrubbing = false
                                }
                            }
                        )
                        .tint(Theme.accent)
                        HStack {
                            Text(GymSong.format(isScrubbing ? scrubTime : player.currentTime))
                            Spacer()
                            Text(GymSong.format(shownDuration))
                        }
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        if let error = player.catalogError {
                            Text(error)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack {
                        Spacer(minLength: 0)
                        transport
                        Spacer(minLength: 0)
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            transportButton("backward.end.fill", label: "Previous song") {
                player.previous()
                SpotterAnalytics.click("previous_workout_track", screen: "workout", ["track": player.currentTrack?.id ?? ""])
            }
            transportButton(player.isPlaying ? "pause.fill" : "play.fill",
                            label: player.isPlaying ? "Pause" : "Play",
                            prominent: true,
                            showsProgress: player.isBuffering) {
                let pausing = player.isPlaying
                player.toggle()
                SpotterAnalytics.click(pausing ? "pause_workout_track" : "resume_workout_track",
                                       screen: "workout",
                                       ["track": player.currentTrack?.id ?? ""])
            }
            transportButton("forward.end.fill", label: "Next song") {
                player.next()
                SpotterAnalytics.click("next_workout_track", screen: "workout", ["track": player.currentTrack?.id ?? ""])
            }
        }
    }

    private func transportButton(_ symbol: String, label: String, prominent: Bool = false, showsProgress: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            ZStack {
                if showsProgress && prominent {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: prominent ? 16 : 13, weight: .bold))
                }
            }
            .foregroundStyle(prominent ? Color.black : Color.white)
            .frame(width: 40, height: 40)
            .background(prominent ? Theme.accent : Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}

/// Song list over the live camera. Playback continues on the workout screen.
struct WorkoutMusicLibrary: View {
    @ObservedObject var player: WorkoutMusicPlayer
    @Binding var isPresented: Bool
    @State private var showPhoneLibrary = false

    var body: some View {
        libraryCard
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var libraryCard: some View {
        VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workout music")
                            .font(.display(22, weight: .bold))
                            .foregroundStyle(.white)
                        Text(player.sourceNote.isEmpty
                             ? String(localized: "Finding popular gym songs near you.")
                             : player.sourceNote)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    CircleIconButton(symbol: "xmark", action: close)
                        .accessibilityLabel(Text("Close music"))
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 8)

                HStack(spacing: 8) {
                    Button {
                        player.showWorkoutMix()
                        Haptics.tap()
                        SpotterAnalytics.click("show_workout_mix", screen: "workout")
                    } label: {
                        Label("Workout mix", systemImage: "music.note")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        openPhoneLibrary()
                    } label: {
                        Label("This iPhone", systemImage: "iphone")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                NowPlayingStrip(player: player)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 8) {
                        if player.isLoadingCatalog && player.tracks.isEmpty {
                            ProgressView()
                                .tint(Theme.accent)
                                .padding(.vertical, 28)
                        } else if let error = player.catalogError, player.tracks.isEmpty {
                            VStack(spacing: 12) {
                                Text(error)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .multilineTextAlignment(.center)
                                Button("Try again") {
                                    player.loadCatalog(force: true)
                                }
                                .buttonStyle(GlassButtonStyle())
                            }
                            .padding(.vertical, 20)
                        }
                        ForEach(Array(player.tracks.enumerated()), id: \.element.id) { index, track in
                            songRow(index: index, track: track)
                        }
                        if !player.tracks.isEmpty {
                            Text(player.tracks.contains(where: { $0.artist == "Kevin MacLeod" })
                                 ? BuiltInMix.credit
                                 : String(localized: "\(player.tracks.count) songs saved on this iPhone."))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: .infinity)
                .onAppear { player.loadCatalog() }
            }
            .sheet(isPresented: $showPhoneLibrary) {
                PhoneMusicPicker { songs in
                    player.useSavedSongs(songs)
                }
            }
            .contentShape(Rectangle())
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func songRow(index: Int, track: GymSong) -> some View {
        let current = player.currentIndex == index
        let playing = current && player.isPlaying
        return Button {
            let pausing = current && player.isPlaying
            player.select(index: index)
            SpotterAnalytics.click(pausing ? "pause_workout_track" : "play_workout_track",
                                   screen: "workout",
                                   ["track": track.id])
            Haptics.tap()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(current ? Theme.accent : Color.white.opacity(0.08))
                        .frame(width: 48, height: 48)
                    if let artwork = track.artworkURL {
                        AsyncImage(url: artwork) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.white.opacity(0.08)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if current && player.isBuffering {
                        ProgressView().tint(.white)
                    } else if current || track.artworkURL == nil {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(current ? Color.black : Color.white)
                            .shadow(color: .black.opacity(0.45), radius: 3)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.display(16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(track.artist) · \(track.album)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if playing {
                    MiniEqualizer(playing: true)
                } else {
                    Text(track.durationText)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(10)
            .background(current ? Theme.accent.opacity(0.14) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(track.title), \(track.artist)"))
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func openPhoneLibrary() {
        Haptics.tap()
        SpotterAnalytics.click("open_phone_music", screen: "workout")
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            showPhoneLibrary = true
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        showPhoneLibrary = true
                    } else {
                        player.libraryAccessDenied()
                    }
                }
            }
        default:
            player.libraryAccessDenied()
        }
    }

    private func close() {
        SpotterAnalytics.click("close_workout_music", screen: "workout")
        Haptics.tap()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            isPresented = false
        }
    }
}

/// Picks songs already stored on this iPhone. Cloud-only Apple Music tracks stay hidden.
struct PhoneMusicPicker: UIViewControllerRepresentable {
    var onPick: ([GymSong]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = true
        picker.showsCloudItems = false
        picker.showsItemsWithProtectedAssets = false
        picker.prompt = String(localized: "Songs saved on this iPhone. No Apple Music subscription needed.")
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let parent: PhoneMusicPicker
        init(_ parent: PhoneMusicPicker) { self.parent = parent }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPick mediaItemCollection: MPMediaItemCollection) {
            parent.onPick(mediaItemCollection.items.compactMap(GymSong.saved(from:)))
            parent.dismiss()
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            parent.dismiss()
        }
    }
}

struct MiniEqualizer: View {
    var playing: Bool
    var color: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !playing)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: playing ? 4 + 9 * bar(time, index: index) : 4)
                }
            }
            .frame(width: 13, height: 14, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func bar(_ time: TimeInterval, index: Int) -> CGFloat {
        CGFloat(abs(sin(time * 7 + Double(index) * 0.9)))
    }
}
