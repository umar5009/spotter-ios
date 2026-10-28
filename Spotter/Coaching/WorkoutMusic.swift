import AVFoundation
import Combine
import MediaPlayer

/// A catalog song chosen for the user's country.
struct GymSong: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkURL: URL?
    let audioURL: URL?

    var durationText: String { Self.format(duration) }

    /// A song stored on this iPhone. Apple Music streams have no local file and are left out.
    static func saved(from item: MPMediaItem) -> GymSong? {
        guard !item.isCloudItem, let url = item.assetURL else { return nil }
        let rawTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GymSong(
            id: "library-\(item.persistentID)",
            title: rawTitle.isEmpty ? String(localized: "Song") : rawTitle,
            artist: item.artist ?? String(localized: "Saved on this iPhone"),
            album: item.albumTitle ?? String(localized: "This iPhone"),
            duration: item.playbackDuration,
            artworkURL: nil,
            audioURL: url
        )
    }

    static func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let seconds = Int(time.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Shared playback session so the coach can talk without stopping the song.
enum WorkoutAudio {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

/// Full songs shipped with the app. Kevin MacLeod, incompetech.com, CC BY 4.0.
enum BuiltInMix {
    static let note = String(localized: "Workout mix. No Apple Music subscription. You can also play songs saved on this iPhone.")
    static let credit = String(localized: "Music by Kevin MacLeod (incompetech.com), CC BY 4.0.")

    private static let catalog: [(file: String, title: String, duration: TimeInterval)] = [
        ("hustle", "Hustle", 121),
        ("volatile-reaction", "Volatile Reaction", 165),
        ("movement-proposition", "Movement Proposition", 141),
        ("five-card-shuffle", "Five Card Shuffle", 136)
    ]

    static var songs: [GymSong] {
        catalog.compactMap { entry in
            let url = Bundle.main.url(forResource: entry.file, withExtension: "mp3", subdirectory: "Resources/Music")
                ?? Bundle.main.url(forResource: entry.file, withExtension: "mp3", subdirectory: "Music")
                ?? Bundle.main.url(forResource: entry.file, withExtension: "mp3")
            guard let url else { return nil }
            return GymSong(
                id: entry.file,
                title: entry.title,
                artist: "Kevin MacLeod",
                album: String(localized: "Workout mix"),
                duration: entry.duration,
                artworkURL: nil,
                audioURL: url
            )
        }
    }
}


/// Plays free full-length songs during a workout. The coach can still talk over them.
@MainActor
final class WorkoutMusicPlayer: ObservableObject {
    nonisolated(unsafe) static weak var active: WorkoutMusicPlayer?

    @Published private(set) var tracks: [GymSong] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogError: String?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var sourceNote = ""

    nonisolated(unsafe) private(set) var holdsAudioSession = false

    var currentTrack: GymSong? {
        guard let currentIndex, tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    private var audio: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var wantsPlayback = false
    private var playGeneration = 0
    private var failedSkips = 0
    nonisolated(unsafe) private var ducked = false
    nonisolated(unsafe) private var ticker: Timer?

    init() {
        Self.active = self
        ticker = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    deinit {
        ticker?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if Self.active === self { Self.active = nil }
    }

    func loadCatalog(force: Bool = false) {
        if !force, !tracks.isEmpty { return }
        showWorkoutMix()
    }

    func showWorkoutMix() {
        let songs = BuiltInMix.songs
        let playingID = currentTrack?.id
        if let playingID, let index = songs.firstIndex(where: { $0.id == playingID }) {
            tracks = songs
            currentIndex = index
        } else {
            if playingID != nil { stop() }
            tracks = songs
        }
        sourceNote = BuiltInMix.note
        isLoadingCatalog = false
        catalogError = songs.isEmpty ? String(localized: "The workout mix couldn't be loaded.") : nil
    }

    /// Plays songs the user already has on this iPhone. Streaming Apple Music tracks are skipped.
    func useSavedSongs(_ songs: [GymSong]) {
        guard !songs.isEmpty else {
            catalogError = String(localized: "Those songs aren't saved on this iPhone. Apple Music streams need a subscription. Choose a downloaded song, or use the workout mix.")
            return
        }
        tracks = songs
        sourceNote = String(localized: "Songs saved on this iPhone. No subscription needed.")
        catalogError = nil
        play(index: 0)
    }

    func libraryAccessDenied() {
        catalogError = String(localized: "Allow Media & Apple Music access in Settings to play songs saved on this iPhone. A subscription is not required. The workout mix still plays.")
    }

    func select(index: Int) {
        if currentIndex == index {
            toggle()
        } else {
            play(index: index)
        }
    }

    func toggle() {
        if isPlaying || isBuffering {
            pause()
        } else {
            resume()
        }
    }

    func next() {
        guard !tracks.isEmpty else { return }
        play(index: (currentIndex ?? -1) + 1)
    }

    /// Restarts the current song after a few seconds, otherwise skips to the previous one.
    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !tracks.isEmpty else { return }
        play(index: (currentIndex ?? 0) - 1)
    }

    func play(index: Int) {
        guard !tracks.isEmpty else {
            loadCatalog()
            return
        }
        let count = tracks.count
        let wrapped = ((index % count) + count) % count
        let song = tracks[wrapped]
        currentIndex = wrapped
        wantsPlayback = true
        holdsAudioSession = true
        isPlaying = true
        isBuffering = true
        currentTime = 0
        duration = song.duration > 1 ? song.duration : 0
        failedSkips = 0
        playGeneration += 1
        let generation = playGeneration
        catalogError = nil
        audio?.pause()
        guard let url = song.audioURL else {
            isPlaying = false
            isBuffering = false
            catalogError = String(localized: "This song couldn't play. Try the next one.")
            return
        }
        activateSession()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = ducked ? 0.18 : 1
        replaceAudio(player, item: item, generation: generation)
        player.play()
    }

    func pause() {
        wantsPlayback = false
        audio?.pause()
        isPlaying = false
        isBuffering = false
    }

    func resume() {
        guard let index = currentIndex, tracks.indices.contains(index) else {
            play(index: 0)
            return
        }
        if audio?.currentItem == nil {
            play(index: index)
            return
        }
        wantsPlayback = true
        holdsAudioSession = true
        isPlaying = true
        activateSession()
        audio?.play()
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = target
        audio?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func stop() {
        playGeneration += 1
        wantsPlayback = false
        holdsAudioSession = false
        audio?.pause()
        audio = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        isPlaying = false
        isBuffering = false
        currentIndex = nil
        currentTime = 0
        duration = 0
    }

    /// Lowers the song while the coach is speaking.
    nonisolated func setDucked(_ ducked: Bool) {
        self.ducked = ducked
        Task { @MainActor in
            self.audio?.volume = ducked ? 0.18 : 1
        }
    }

    private func replaceAudio(_ player: AVPlayer, item: AVPlayerItem, generation: Int) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        audio = player
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, generation == self.playGeneration else { return }
                self.failedSkips = 0
                self.next()
            }
        }
    }

    private func activateSession() {
        WorkoutAudio.activate()
    }

    private func sync() {
        guard wantsPlayback || isPlaying || currentIndex != nil else { return }
        guard let item = audio?.currentItem else { return }
        let time = audio?.currentTime().seconds ?? 0
        if time.isFinite, time >= 0 { currentTime = time }
        let reported = item.duration.seconds
        if reported.isFinite, reported > 1 { duration = reported }
        if item.status == .failed {
            isBuffering = false
            isPlaying = false
            guard wantsPlayback, failedSkips < 3 else {
                wantsPlayback = false
                catalogError = String(localized: "This song couldn't play. Try the next one.")
                return
            }
            failedSkips += 1
            wantsPlayback = false
            next()
            return
        }
        switch audio?.timeControlStatus {
        case .playing:
            isPlaying = true
            isBuffering = false
        case .waitingToPlayAtSpecifiedRate:
            isPlaying = wantsPlayback
            isBuffering = wantsPlayback
        case .paused:
            isBuffering = false
            if !wantsPlayback { isPlaying = false }
        default:
            isBuffering = wantsPlayback
        }
    }
}
