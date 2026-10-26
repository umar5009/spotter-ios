import AVFoundation
import UIKit

/// Spoken coaching. Rate-limited so cues never pile up, and ducks workout music instead of stopping it.
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = VoiceCoach()

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpoken: [String: Date] = [:]
    private var lastAny = Date.distantPast
    private var activeUtterance: ObjectIdentifier?

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "voiceEnabled") as? Bool ?? true
    }

    private override init() {
        super.init()
        synthesizer.delegate = self
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
    }

    /// - Parameters:
    ///   - key: Identifies the cue for its cooldown (defaults to the text).
    ///   - cooldown: Minimum seconds before the same cue may repeat.
    ///   - priority: Interrupts anything currently being said.
    func say(_ text: String, key: String? = nil, cooldown: TimeInterval = 4, priority: Bool = false) {
        guard enabled else { return }
        let now = Date()
        let k = key ?? text
        if let last = lastSpoken[k], now.timeIntervalSince(last) < cooldown { return }
        if !priority {
            if synthesizer.isSpeaking || now.timeIntervalSince(lastAny) < 1.2 { return }
        }
        lastSpoken[k] = now
        lastAny = now

        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.voice = Self.systemVoice
        activeUtterance = ObjectIdentifier(utterance)
        if priority, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        WorkoutMusicPlayer.active?.setDucked(true)
        synthesizer.speak(utterance)
    }

    /// Speaks in the language the iPhone is using, and falls back to English.
    private static var systemVoice: AVSpeechSynthesisVoice? {
        let preferred = Locale.preferredLanguages
        for identifier in preferred {
            if let voice = AVSpeechSynthesisVoice(language: identifier) { return voice }
            let code = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
            if let voice = AVSpeechSynthesisVoice(language: code) { return voice }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        if WorkoutMusicPlayer.active?.holdsAudioSession != true {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.releaseDuck(for: utterance)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.releaseDuck(for: utterance)
        }
    }

    private func releaseDuck(for utterance: AVSpeechUtterance) {
        guard ObjectIdentifier(utterance) == activeUtterance else { return }
        activeUtterance = nil
        WorkoutMusicPlayer.active?.setDucked(false)
    }
}

enum Haptics {
    static func rep() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
