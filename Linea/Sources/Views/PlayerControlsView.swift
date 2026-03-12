import SwiftUI
import AVFoundation

// Speed options as a multiplier of AVSpeechUtteranceDefaultSpeechRate
private let speedOptions: [(label: String, multiplier: Float)] = [
    ("0.5×", 0.5),
    ("0.75×", 0.75),
    ("1×", 1.0),
    ("1.25×", 1.25),
    ("1.5×", 1.5),
    ("2×", 2.0),
]

struct PlayerControlsView: View {
    @ObservedObject var speech: SpeechService
    let chapter: EPUBBook.Chapter
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void
    var onActivity: (() -> Void)? = nil   // called on any interaction to reset chrome timer

    @State private var expanded = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedControls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            collapsedPill
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: expanded)
        .padding(.bottom, 24)
        .padding(.horizontal, 24)
    }

    // MARK: - Collapsed pill (always visible)

    private var collapsedPill: some View {
        HStack(spacing: 16) {
            // Prev
            Button(action: { onPrevChapter(); scheduleHide(); onActivity?() }) {
                Image(systemName: "backward.end.fill")
                    .font(.body.weight(.semibold))
            }

            // Play / Pause
            Button(action: {
                if speech.isPlaying || speech.currentWordRange != nil {
                    speech.pauseOrResume()
                } else {
                    speech.speak(text: chapter.text)
                }
                scheduleHide(); onActivity?()
            }) {
                Image(systemName: speech.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 28)
            }

            // Next
            Button(action: { onNextChapter(); scheduleHide(); onActivity?() }) {
                Image(systemName: "forward.end.fill")
                    .font(.body.weight(.semibold))
            }

            Divider().frame(height: 20)

            // Speed menu
            speedMenu

            // Voice menu
            voiceMenu

            Spacer()

            // Chevron — tap to expand/collapse
            Button(action: toggleExpanded) {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8) // larger tap target
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    // MARK: - Expanded panel

    private var expandedControls: some View {
        VStack(spacing: 14) {
            // Chapter title
            Text(chapter.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .padding(.bottom, 8)
    }

    // MARK: - Speed menu

    private var speedMenu: some View {
        Menu {
            ForEach(speedOptions, id: \.label) { option in
                Button(action: {
                    speech.setRate(AVSpeechUtteranceDefaultSpeechRate * option.multiplier)
                    scheduleHide(); onActivity?()
                }) {
                    HStack {
                        Text(option.label)
                        if isCurrentSpeed(option.multiplier) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(currentSpeedLabel)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Voice menu

    private var voiceMenu: some View {
        Menu {
            // Personal Voice section (iOS 17+)
            let personalVoices: [AVSpeechSynthesisVoice] = {
                if #available(iOS 17.0, *) {
                    return speech.availableVoices.filter { $0.voiceTraits.contains(.isPersonalVoice) }
                }
                return []
            }()
            if !personalVoices.isEmpty {
                Section("Your Voice") {
                    ForEach(personalVoices, id: \.identifier) { voice in
                        voiceButton(voice, icon: "person.wave.2.fill")
                    }
                }
            }

            // Quality tiers
            ForEach([AVSpeechSynthesisVoiceQuality.premium, .enhanced, .default], id: \.rawValue) { quality in
                let voices = speech.availableVoices.filter { isNonPersonalVoice($0, quality: quality) }
                if !voices.isEmpty {
                    Section(quality.label) {
                        ForEach(voices, id: \.identifier) { voice in
                            voiceButton(voice, icon: nil)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                Text(speech.selectedVoice?.name ?? "Voice")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
        }
        .onAppear { speech.requestPersonalVoiceIfNeeded() }
    }

    private func isNonPersonalVoice(_ voice: AVSpeechSynthesisVoice, quality: AVSpeechSynthesisVoiceQuality) -> Bool {
        guard voice.quality == quality else { return false }
        if #available(iOS 17.0, *) { return !voice.voiceTraits.contains(.isPersonalVoice) }
        return true
    }

    @ViewBuilder
    private func voiceButton(_ voice: AVSpeechSynthesisVoice, icon: String?) -> some View {
        Button(action: { speech.setVoice(voice); scheduleHide(); onActivity?() }) {
            HStack {
                if let icon { Image(systemName: icon) }
                Text(voice.name)
                if speech.selectedVoice?.identifier == voice.identifier {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    // MARK: - Helpers

    private func toggleExpanded() {
        expanded.toggle()
        if expanded { scheduleHide(); onActivity?() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                withAnimation { expanded = false }
            }
        }
    }

    private var currentSpeedLabel: String {
        let current = speech.rate / AVSpeechUtteranceDefaultSpeechRate
        return speedOptions.min(by: { abs($0.multiplier - current) < abs($1.multiplier - current) })?.label ?? "1×"
    }

    private func isCurrentSpeed(_ multiplier: Float) -> Bool {
        abs(speech.rate - AVSpeechUtteranceDefaultSpeechRate * multiplier) < 0.01
    }
}
