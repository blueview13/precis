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
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.45
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
