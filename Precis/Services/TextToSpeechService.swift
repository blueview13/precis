import Foundation
import AVFoundation

public protocol TextToSpeechServiceProtocol {
    func speak(_ text: String)
    func stop()
}

public final class TextToSpeechService: TextToSpeechServiceProtocol {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    public func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        let voiceIdentifier = UserDefaults.standard.string(forKey: Self.voicePreferenceKey) ?? ""
        utterance.voice = voiceIdentifier.isEmpty
            ? AVSpeechSynthesisVoice(language: Locale.current.identifier)
            : AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        utterance.rate = 0.45
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    public static let voicePreferenceKey = "readingSpeechVoiceIdentifier"

    public static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            if $0.language == $1.language { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return $0.language.localizedCaseInsensitiveCompare($1.language) == .orderedAscending
        }
    }
}
