import SwiftUI

struct BookReaderContainerView: View {
    let book: EPUBBook
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var settings: ReadingSettings
    @StateObject private var speech = SpeechService()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var selectedChapterIndex: Int = 0
    @State private var showChapters = false
    @State private var showSettings = false
    @State private var zenMode = false
    @State private var zenWindowSize = 7
    @State private var chromeVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var lastWordOffset: Int = 0

    var currentChapter: EPUBBook.Chapter { book.chapters[selectedChapterIndex] }
    var isIPad: Bool { hSizeClass == .regular }

    // MARK: - Chapter progress bar

    private var chapterProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                Rectangle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: geo.size.width * chapterProgress)
                    .animation(.linear(duration: 0.2), value: chapterProgress)
            }
        }
        .frame(height: 2)
        .ignoresSafeArea(edges: .horizontal)
    }

    /// 0–1 progress within the current chapter based on speech position
    var chapterProgress: Double {
        let total = currentChapter.wordCount
        guard total > 0 else { return 0 }
        let wordsDone = currentChapter.wordCount(upToCharOffset: lastWordOffset)
        return min(1.0, Double(wordsDone) / Double(total))
    }

    var body: some View {
        Group {
            if isIPad { iPadLayout } else { iPhoneLayout }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            chapterProgressBar
        }
        .onAppear {
            let saved = library.progressFor(book.id)
            selectedChapterIndex = min(saved.chapterIndex, book.chapters.count - 1)
            lastWordOffset = saved.wordOffset
            // Restore speech position to where the user left off
            if saved.wordOffset > 0 {
                speech.restorePosition(text: book.chapters[selectedChapterIndex].text,
                                       charOffset: saved.wordOffset)
            }
            resetHideTimer()
        }
        .onDisappear {
            hideTask?.cancel()
            speech.stop()
            saveProgress()
        }
        .onChange(of: selectedChapterIndex) { _ in saveProgress() }
        .onChange(of: speech.currentWordRange.map {
            currentChapter.text.distance(from: currentChapter.text.startIndex, to: $0.lowerBound)
        }) { offset in
            // Keep lastWordOffset in sync so saveProgress() and chapterProgress are always accurate
            if let offset { lastWordOffset = offset }
        }
    }

    // MARK: - iPad

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button(action: {
                        selectedChapterIndex = index
                        speech.speak(text: chapter.text)
                    }) {
                        HStack {
                            if chapter.nestingLevel > 0 {
                                Color.clear.frame(width: CGFloat(chapter.nestingLevel) * 20)
                            }
                            Text(chapter.title)
                                .font(chapter.nestingLevel == 0 ? .body.bold() : .body)
                                .foregroundStyle(index == selectedChapterIndex ? Color.accentColor : Color.primary)
                            Spacer()
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, chapter.nestingLevel == 0 ? 4 : 1)
                    }
                    .listRowSeparator(chapter.nestingLevel == 0 ? .visible : .hidden)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) { Image(systemName: "chevron.left") }
                }
            }
        } detail: {
            readerDetail()
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - iPhone

    private var iPhoneLayout: some View {
        NavigationStack {
            readerContent(withTapHandler: true)
                .background(settings.theme.background)
                .navigationTitle(book.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { dismiss() }) { Image(systemName: "chevron.left") }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(action: { showChapters = true; resetHideTimer() }) {
                            Image(systemName: "list.bullet")
                        }
                        Button(action: { withAnimation { zenMode.toggle() }; resetHideTimer() }) {
                            Image(systemName: zenMode ? "doc.text.fill" : "eye")
                        }
                        Button(action: { showSettings = true; resetHideTimer() }) {
                            Image(systemName: "textformat")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if chromeVisible {
                        VStack(spacing: 0) {
                            // Page indicator
                            Text("Chapter \(selectedChapterIndex + 1) of \(book.chapters.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 4)
                            PlayerControlsView(speech: speech, chapter: currentChapter,
                                               onPrevChapter: goToPrev, onNextChapter: goToNext,
                                               onActivity: resetHideTimer)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        }
        .animation(.easeInOut(duration: 0.22), value: chromeVisible)
        .sheet(isPresented: $showChapters) {
            BookChaptersView(book: book, selectedChapterIndex: $selectedChapterIndex, speech: speech)
        }
        .sheet(isPresented: $showSettings) {
            ReadingSettingsView()
        }
    }

    // MARK: - iPad detail

    private func readerDetail() -> some View {
        readerContent()
            .background(settings.theme.background)
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { withAnimation { zenMode.toggle() } }) {
                        Image(systemName: zenMode ? "doc.text.fill" : "eye")
                    }
                    Button(action: { showSettings = true }) {
                        Image(systemName: "textformat")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Text("Chapter \(selectedChapterIndex + 1) · \(currentChapter.title)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    PlayerControlsView(speech: speech, chapter: currentChapter,
                                       onPrevChapter: goToPrev, onNextChapter: goToNext,
                                       onActivity: resetHideTimer)
                }
            }
            .sheet(isPresented: $showSettings) { ReadingSettingsView() }
    }

    // MARK: - Shared reader content

    @ViewBuilder
    private func readerContent(withTapHandler: Bool = false) -> some View {
        if zenMode {
            ZenModeView(chapter: currentChapter, speech: speech, windowSize: $zenWindowSize,
                        onTap: withTapHandler ? toggleChrome : nil)
        } else {
            ReaderView(chapter: currentChapter, speech: speech,
                       onTap: withTapHandler ? toggleChrome : nil,
                       onWordClick: handleWordClick)
        }
    }

    // MARK: - Chrome

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.22)) { chromeVisible.toggle() }
        if chromeVisible { resetHideTimer() } else { hideTask?.cancel() }
    }

    func resetHideTimer() {
        guard !isIPad else { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) { chromeVisible = false }
            }
        }
    }

    // MARK: - Navigation

    private func goToPrev() {
        guard selectedChapterIndex > 0 else { return }
        selectedChapterIndex -= 1
        speech.speak(text: currentChapter.text)
        resetHideTimer()
    }

    private func goToNext() {
        guard selectedChapterIndex < book.chapters.count - 1 else { return }
        selectedChapterIndex += 1
        speech.speak(text: currentChapter.text)
        resetHideTimer()
    }

    private func saveProgress() {
        // Calculate current word offset from speech position
        var wordOffset = lastWordOffset
        if let range = speech.currentWordRange {
            wordOffset = currentChapter.text.distance(from: currentChapter.text.startIndex, to: range.lowerBound)
            lastWordOffset = wordOffset
        }
        library.updateProgress(bookID: book.id, chapterIndex: selectedChapterIndex,
                               charOffset: wordOffset, totalWords: book.totalWords)
    }

    // MARK: - Word click handler

    private func handleWordClick(_ wordIndex: Int) {
        // Convert word index to character offset in chapter.text
        let charOffset = charOffsetForWordIndex(wordIndex, in: currentChapter.text)
        lastWordOffset = charOffset
        speech.speak(text: currentChapter.text, fromCharOffset: charOffset)
        resetHideTimer()
    }

    /// Convert a word index (0-based) to character offset in text
    private func charOffsetForWordIndex(_ wordIndex: Int, in text: String) -> Int {
        var currentWordIndex = 0
        var i = text.startIndex
        
        while i < text.endIndex {
            // Skip whitespace
            while i < text.endIndex && text[i].isWhitespace {
                i = text.index(after: i)
            }
            
            // Found start of a word
            if i < text.endIndex {
                if currentWordIndex == wordIndex {
                    return text.distance(from: text.startIndex, to: i)
                }
                
                // Skip the word
                while i < text.endIndex && !text[i].isWhitespace {
                    i = text.index(after: i)
                }
                currentWordIndex += 1
            }
        }
        
        return 0
    }
}
