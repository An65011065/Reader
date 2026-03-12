import AVFoundation
import Combine

class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    // MARK: - Published state
    @Published var isPlaying = false
    @Published var currentWordRange: Range<String.Index>? = nil
    @Published var currentText: String = ""
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var selectedVoice: AVSpeechSynthesisVoice?
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []

    // MARK: - Private
    private let synthesizer = AVSpeechSynthesizer()
    private var fullText = ""
    private var speakingOffset = 0  // Character offset into fullText where current utterance starts

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        loadVoices()

        // Refresh voice list if user downloads/removes voices (iOS 17+)
        if #available(iOS 17.0, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(voicesDidChange),
                name: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                object: nil
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Voice loading

    @objc private func voicesDidChange() {
        DispatchQueue.main.async { self.loadVoices() }
    }

    private func loadVoices() {
        let all = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                guard voice.language.hasPrefix("en") else { return false }
                // Exclude Eloquence character voices (Eddy, Flo, Grandma, Grandpa, Reed, Rocko, Sandy, Shelley, Tessa, Rishi…)
                if voice.identifier.contains("eloquence") { return false }
                // Exclude standard/compact quality — only keep enhanced, premium, personal
                if voice.quality == .default { return false }
                // Exclude other novelty voices on iOS 17+
                if #available(iOS 17.0, *) {
                    if voice.voiceTraits.contains(.isNoveltyVoice) { return false }
                }
                return true
            }
            .sorted { lhs, rhs in
                // Personal Voice first, then by quality tier, then alphabetically
                if #available(iOS 17.0, *) {
                    let lPV = lhs.voiceTraits.contains(.isPersonalVoice)
                    let rPV = rhs.voiceTraits.contains(.isPersonalVoice)
                    if lPV != rPV { return lPV }
                }
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
        // If no enhanced/premium voices downloaded yet, fall back to all non-eloquence English voices
        let filtered = all.isEmpty ? AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.identifier.contains("eloquence") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            : all
        availableVoices = filtered

        if selectedVoice == nil || !filtered.contains(where: { $0.identifier == selectedVoice?.identifier }) {
            selectedVoice = filtered.first
        }
    }

    // MARK: - Personal Voice (iOS 17+)

    func requestPersonalVoiceIfNeeded() {
        guard #available(iOS 17.0, *) else { return }
        Task {
            let status = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
            if status == .authorized {
                await MainActor.run { self.loadVoices() }
            }
        }
    }

    // MARK: - Public API

    func speak(text: String) {
        stop()
        fullText = text
        currentText = text
        speakingOffset = 0
        currentWordRange = nil
        synthesizer.speak(makeUtterance(text: text))
        isPlaying = true
    }

    /// Restore saved position without auto-playing — sets up state so play resumes from offset
    func restorePosition(text: String, charOffset: Int) {
        stop()
        fullText = text
        currentText = text
        speakingOffset = min(charOffset, text.count)
        // Set currentWordRange to the saved offset so highlight shows the right word
        let idx = text.index(text.startIndex, offsetBy: speakingOffset)
        // Find the end of the word at this offset
        var end = idx
        while end < text.endIndex && !text[end].isWhitespace { end = text.index(after: end) }
        currentWordRange = idx..<end
        isPlaying = false
    }

    /// Start speaking from a specific character offset within the text
    func speak(text: String, fromCharOffset offset: Int) {
        stop()
        fullText = text
        currentText = text
        speakingOffset = min(offset, text.count)
        
        let startIndex = text.index(text.startIndex, offsetBy: speakingOffset)
        let textFromOffset = String(text[startIndex...])
        
        currentWordRange = nil
        synthesizer.speak(makeUtterance(text: textFromOffset))
        isPlaying = true
    }

    func pauseOrResume() {
        if synthesizer.isSpeaking {
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
                isPlaying = true
            } else {
                synthesizer.pauseSpeaking(at: .word)
                isPlaying = false
            }
        } else if !fullText.isEmpty {
            // Not yet started (e.g. restored from saved position) — start from speakingOffset
            let startIndex = fullText.index(fullText.startIndex, offsetBy: min(speakingOffset, fullText.count))
            let textFromOffset = String(fullText[startIndex...])
            currentWordRange = nil
            synthesizer.speak(makeUtterance(text: textFromOffset))
            isPlaying = true
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        currentWordRange = nil
        speakingOffset = 0
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        resumeFromCurrentWord(newRate: newRate, newVoice: selectedVoice)
    }

    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoice = voice
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        resumeFromCurrentWord(newRate: rate, newVoice: voice)
    }

    // MARK: - Helpers

    private func resumeFromCurrentWord(newRate: Float, newVoice: AVSpeechSynthesisVoice?) {
        let resumeOffset = currentWordRange.map {
            fullText.distance(from: fullText.startIndex, to: $0.lowerBound)
        } ?? speakingOffset
        
        speakingOffset = resumeOffset
        let resumeText = resumeOffset > 0
            ? String(fullText[fullText.index(fullText.startIndex, offsetBy: resumeOffset)...])
            : fullText

        synthesizer.stopSpeaking(at: .immediate)
        currentWordRange = nil

        let utterance = makeUtterance(text: resumeText)
        utterance.rate = newRate
        utterance.voice = newVoice
        synthesizer.speak(utterance)
        isPlaying = true
    }

    private func makeUtterance(text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = selectedVoice
        // Small tweaks for more natural cadence
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.1
        return utterance
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                            willSpeakRangeOfSpeechString characterRange: NSRange,
                            utterance: AVSpeechUtterance) {
        // The characterRange is relative to the utterance, but we need it relative to fullText
        // Adjust by adding speakingOffset
        let adjustedLocation = characterRange.location + speakingOffset
        let adjustedRange = NSRange(location: adjustedLocation, length: characterRange.length)
        
        guard let range = Range(adjustedRange, in: fullText) else { return }
        
        Task { @MainActor in
            self.currentWordRange = range
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                            didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentWordRange = nil
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        #endif
    }
}

// MARK: - Voice quality display helpers

extension AVSpeechSynthesisVoiceQuality {
    var label: String {
        switch self {
        case .default: return "Standard"
        case .enhanced: return "Enhanced"
        case .premium: return "Premium"
        @unknown default: return "Standard"
        }
    }
}
