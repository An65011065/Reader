import SwiftUI

struct ZenModeView: View {
    let chapter: EPUBBook.Chapter
    @ObservedObject var speech: SpeechService
    @Binding var windowSize: Int
    var onTap: (() -> Void)?
    var onLongPressStart: (() -> Void)?
    var onLongPressEnd: (() -> Void)?

    @State private var isHeld = false

    private var words: [String] {
        chapter.text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    private var activeWordIndex: Int {
        guard let range = speech.currentWordRange else { return 0 }
        let prefix = String(chapter.text[chapter.text.startIndex..<range.lowerBound])
        let count = prefix
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        return min(count, max(0, words.count - 1))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if words.isEmpty {
                Text("No text").foregroundStyle(.secondary)
            } else {
                wordRow
            }

            // Word count picker — bottom left, above controls
            VStack {
                Spacer()
                HStack {
                    windowPicker
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 100)
            }

        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .gesture(
            LongPressGesture(minimumDuration: 0.4)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second = value, !isHeld {
                        isHeld = true
                        onLongPressStart?()
                    }
                }
                .onEnded { _ in
                    guard isHeld else { return }
                    isHeld = false
                    onLongPressEnd?()
                }
        )
    }

    // MARK: - Horizontal word row

    private var wordRow: some View {
        let active = activeWordIndex
        let half = windowSize / 2
        let effectiveWindow = min(windowSize, words.count)
        let start = max(0, min(active - half, words.count - effectiveWindow))
        let end   = min(words.count - 1, max(0, start + effectiveWindow - 1))
        let adjStart = max(0, end - effectiveWindow + 1)
        let visibleIndices = adjStart <= end ? Array(adjStart...end) : []

        return GeometryReader { geo in
            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)
                ForEach(Array(visibleIndices.enumerated()), id: \.offset) { _, wordIdx in
                    let distance = wordIdx - active
                    WordTokenView(
                        word: words[wordIdx],
                        distance: distance,
                        totalSlots: windowSize
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width)
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: active)
        }
    }

    // MARK: - Window size picker

    private var windowPicker: some View {
        Menu {
            ForEach([3, 5, 7, 9, 11], id: \.self) { n in
                Button(action: { windowSize = n }) {
                    HStack {
                        Text("\(n) words")
                        if windowSize == n { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "eye")
                    .font(.caption)
                Text("\(windowSize) words")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.08), in: Capsule())
        }
    }
}

// MARK: - Single word token

private struct WordTokenView: View {
    let word: String
    let distance: Int
    let totalSlots: Int

    private var isActive: Bool { distance == 0 }
    private var halfSlots: CGFloat { CGFloat(totalSlots / 2 + 1) }

    private var scale: CGFloat {
        isActive ? 1.0 : max(0.4, 1.0 - CGFloat(abs(distance)) * 0.18)
    }

    private var opacity: Double {
        isActive ? 1.0 : max(0.1, 1.0 - Double(abs(distance)) * (0.9 / Double(halfSlots)))
    }

    private var fontSize: CGFloat { 36 }

    var body: some View {
        Text(word)
            .font(.system(size: fontSize, weight: isActive ? .bold : .light, design: .rounded))
            .foregroundStyle(isActive ? Color(red: 0.910, green: 0.251, blue: 0.047) : Color.white)
            .lineLimit(1)
            .fixedSize()
            .scaleEffect(scale)
            .opacity(opacity)
            .padding(.horizontal, isActive ? 10 : 6)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isActive)
    }
}
