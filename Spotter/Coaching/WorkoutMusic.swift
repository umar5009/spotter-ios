import AVFoundation
import Combine
import CoreLocation

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

    static func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let seconds = Int(time.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Loads free, full-length gym songs for a country. These are openly licensed tracks, not 30-second previews.
enum RegionalCatalog {
    struct Result {
        var songs: [GymSong]
        var place: String
        var note: String
    }

    static func load(country code: String) async throws -> Result {
        let code = code.uppercased()
        let place = Locale.current.localizedString(forRegionCode: code) ?? code
        var seen = Set<String>()
        var songs: [GymSong] = []

        try await withThrowingTaskGroup(of: [GymSong].self) { group in
            for term in searchTerms(for: code) {
                group.addTask { await fetch(term: term, place: place) }
            }
            for try await batch in group {
                for song in batch where seen.insert(song.id).inserted {
                    songs.append(song)
                }
            }
        }
        songs = Array(songs.prefix(40))
        guard !songs.isEmpty else { throw CatalogError.empty }
        return Result(
            songs: songs,
            place: place,
            note: String(localized: "Free gym songs in \(place).")
        )
    }

    private static func fetch(term: String, place: String) async -> [GymSong] {
        var components = URLComponents(string: "https://ccmixter.org/api/query")
        components?.queryItems = [
            URLQueryItem(name: "search", value: term),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "f", value: "json")
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Spotter/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode([Upload].self, from: data)
            return decoded.compactMap { $0.song(place: place) }
        } catch {
            return []
        }
    }

    private struct Upload: Decodable {
        var upload_id: Int
        var upload_name: String?
        var user_name: String?
        var license_name: String?
        var files: [MixFile]?

        func song(place: String) -> GymSong? {
            guard let upload_name, let user_name, Self.canPlay(license_name) else { return nil }
            let playable = (files ?? []).compactMap { file -> (URL, TimeInterval)? in
                guard let raw = file.download_url?.lowercased(), raw.hasSuffix(".mp3"),
                      let url = file.download_url.flatMap(URL.init(string:)) else { return nil }
                let duration = Self.clock(file.file_format_info?.ps)
                guard duration >= 70 else { return nil }
                return (url, duration)
            }
            guard let best = playable.max(by: { $0.1 < $1.1 }) else { return nil }
            return GymSong(
                id: String(upload_id),
                title: upload_name,
                artist: user_name,
                album: place,
                duration: best.1,
                artworkURL: nil,
                audioURL: best.0
            )
        }

        /// Open licenses we can play in full. Non-commercial licenses stay out.
        private static func canPlay(_ license: String?) -> Bool {
            let name = (license ?? "").lowercased()
            if name.contains("noncommercial") || name.contains("non-commercial") { return false }
            return name.contains("attribution") || name.contains("sampling")
                || name.contains("public domain") || name.contains("cc0")
        }

        private static func clock(_ text: String?) -> TimeInterval {
            let parts = (text ?? "").split(separator: ":").compactMap { Int($0) }
            switch parts.count {
            case 2: return TimeInterval(parts[0] * 60 + parts[1])
            case 3: return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
            default: return 0
            }
        }
    }

    private struct MixFile: Decodable {
        var download_url: String?
        var file_format_info: Format?

        struct Format: Decodable {
            var ps: String?
        }
    }

    private static func searchTerms(for country: String) -> [String] {
        var terms: [String]
        switch country {
        case "IN":
            terms = ["bollywood", "punjabi", "hindi", "india"]
        case "PK":
            terms = ["punjabi", "urdu", "hindi"]
        case "BD":
            terms = ["bengali", "bangla"]
        case "US", "CA":
            terms = ["hip hop", "rap", "funk"]
        case "GB", "IE":
            terms = ["uk", "hip hop", "electronic"]
        case "AU", "NZ":
            terms = ["australia", "hip hop"]
        case "AE", "SA", "QA", "KW", "BH", "OM":
            terms = ["arabic", "khaleeji"]
        case "BR":
            terms = ["brazil", "funk", "latin"]
        case "MX", "ES", "AR", "CO", "CL":
            terms = ["latin", "reggaeton", "spanish"]
        case "KR":
            terms = ["kpop", "korean"]
        case "JP":
            terms = ["japan", "jpop"]
        case "FR":
            terms = ["french", "electronic"]
        case "DE", "AT", "CH":
            terms = ["german", "electronic"]
        default:
            terms = ["hip hop", "electronic"]
        }
        for extra in ["workout", "gym", "energy", "dance"] where !terms.contains(extra) {
            terms.append(extra)
        }
        return terms
    }

    enum CatalogError: LocalizedError {
        case empty

        var errorDescription: String? {
            String(localized: "No gym songs were found for your country. Try again.")
        }
    }
}

/// Country from GPS, with a hard stop so the song list is never stuck on the prompt.
@MainActor
final class CountryLocator: NSObject, CLLocationManagerDelegate {
    static let shared = CountryLocator()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private var timeoutTask: Task<Void, Never>?
    private var started = false
    private(set) var cachedCountry: String?

    func countryCode() async -> String? {
        if let cachedCountry { return cachedCountry }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            startIfNeeded()
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self?.finish(nil)
            }
        }
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestFix()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            Task { self.finish(nil) }
        }
    }

    private func requestFix() {
        if let location = manager.location, abs(location.timestamp.timeIntervalSinceNow) < 30 * 60 {
            resolve(location)
            return
        }
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard cachedCountry == nil else { return }
            requestFix()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(nil)
            return
        }
        resolve(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func resolve(_ location: CLLocation) {
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { marks, _ in
            let code = marks?.first?.isoCountryCode
            Task { @MainActor in
                self.finish(code)
            }
        }
    }

    private func finish(_ code: String?) {
        if let code { cachedCountry = code.uppercased() }
        timeoutTask?.cancel()
        timeoutTask = nil
        let pending = waiters
        waiters.removeAll()
        let resolved = cachedCountry
        pending.forEach { $0.resume(returning: resolved) }
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
        if isLoadingCatalog { return }
        if !force, !tracks.isEmpty { return }
        isLoadingCatalog = true
        catalogError = nil
        Task {
            async let countryLookup = CountryLocator.shared.countryCode()
            let fallback = (Locale.current.region?.identifier ?? "US").uppercased()
            let firstCountry = CountryLocator.shared.cachedCountry ?? fallback
            do {
                let result = try await RegionalCatalog.load(country: firstCountry)
                apply(result)
                catalogError = nil
            } catch {
                if tracks.isEmpty {
                    catalogError = error.localizedDescription
                }
            }
            isLoadingCatalog = false

            let resolved = (await countryLookup ?? firstCountry).uppercased()
            guard resolved != firstCountry, !isPlaying, !isBuffering else { return }
            if let result = try? await RegionalCatalog.load(country: resolved), !result.songs.isEmpty {
                apply(result)
            }
        }
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
        try? activateSession()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = ducked ? 0.18 : 1
        replaceAudio(player, item: item, generation: generation)
        player.play()
        isBuffering = false
        isPlaying = true
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
        try? activateSession()
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

    private func apply(_ result: RegionalCatalog.Result) {
        let playingID = currentTrack?.id
        tracks = result.songs
        sourceNote = result.note
        if let playingID, let index = result.songs.firstIndex(where: { $0.id == playingID }) {
            currentIndex = index
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

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
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
