import Foundation
import Combine

@MainActor
class LibraryStore: ObservableObject {
    @Published var books: [EPUBBook] = []
    @Published var progress: [UUID: BookProgress] = [:]
    @Published var isLoading = false

    private let docsURL: URL
    private let progressURL: URL
    private var saveProgressTask: Task<Void, Never>?  // debounce handle

    // Each book gets its own file: <uuid>.book.json
    private func bookURL(_ id: UUID) -> URL {
        docsURL.appendingPathComponent("\(id.uuidString).book.json")
    }

    // Index file: just stores [UUID] in order (no chapter text)
    private var indexURL: URL { docsURL.appendingPathComponent("library.index.json") }

    init() {
        docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        progressURL = docsURL.appendingPathComponent("progress.json")
        Task { await loadAll() }
    }

    // MARK: - Add / Remove

    func addBook(_ book: EPUBBook) {
        books.removeAll { $0.title == book.title && $0.author == book.author }
        books.insert(book, at: 0)
        Task { await saveBook(book); await saveIndex(); await saveProgress() }
    }

    func removeBook(id: UUID) {
        books.removeAll { $0.id == id }
        progress.removeValue(forKey: id)
        Task {
            try? FileManager.default.removeItem(at: bookURL(id))
            await saveIndex()
            await saveProgress()
        }
    }

    // MARK: - Progress

    func progressFor(_ bookID: UUID) -> BookProgress {
        progress[bookID] ?? BookProgress(bookID: bookID)
    }

    func updateProgress(bookID: UUID, chapterIndex: Int, charOffset: Int, totalWords: Int) {
        var p = progress[bookID] ?? BookProgress(bookID: bookID)
        p.chapterIndex = chapterIndex
        p.wordOffset = charOffset
        p.lastOpened = Date()
        if let book = books.first(where: { $0.id == bookID }), totalWords > 0 {
            let wordsInChapter = book.chapters[chapterIndex].wordCount(upToCharOffset: charOffset)
            let wordsRead = book.chapters[0..<chapterIndex].reduce(0) { $0 + $1.wordCount } + wordsInChapter
            p.progressFraction = min(1.0, Double(wordsRead) / Double(totalWords))
        }
        progress[bookID] = p
        // Debounce: cancel pending save and schedule a new one 1.5s out
        // This prevents hammering disk during active playback (4-5 updates/sec)
        saveProgressTask?.cancel()
        saveProgressTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await saveProgress()
        }
    }

    // MARK: - Load (background)

    private func loadAll() async {
        isLoading = true
        let (loadedBooks, loadedProgress) = await Task.detached(priority: .userInitiated) { [indexURL, progressURL, docsURL] in
            // Load index to get ordered IDs
            var orderedIDs: [UUID] = []
            if let data = try? Data(contentsOf: indexURL),
               let ids = try? JSONDecoder().decode([UUID].self, from: data) {
                orderedIDs = ids
            }

            // Load each book file in order
            var loaded: [EPUBBook] = []
            for id in orderedIDs {
                let url = docsURL.appendingPathComponent("\(id.uuidString).book.json")
                if let data = try? Data(contentsOf: url),
                   let book = try? JSONDecoder().decode(EPUBBook.self, from: data) {
                    loaded.append(book)
                }
            }

            // Fallback: load old monolithic library.json if index doesn't exist yet
            if loaded.isEmpty {
                let legacyURL = docsURL.appendingPathComponent("library.json")
                if let data = try? Data(contentsOf: legacyURL),
                   let legacy = try? JSONDecoder().decode([EPUBBook].self, from: data) {
                    loaded = legacy
                }
            }

            // Load progress
            var prog: [UUID: BookProgress] = [:]
            if let data = try? Data(contentsOf: progressURL),
               let decoded = try? JSONDecoder().decode([UUID: BookProgress].self, from: data) {
                prog = decoded
            }

            return (loaded, prog)
        }.value

        books = loadedBooks
        progress = loadedProgress
        isLoading = false

        // Migrate legacy library.json → per-book files if needed
        if !loadedBooks.isEmpty {
            let legacyURL = docsURL.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                for book in loadedBooks { await saveBook(book) }
                await saveIndex()
                try? FileManager.default.removeItem(at: legacyURL)
            }
        }
    }

    // MARK: - Save (background)

    private func saveBook(_ book: EPUBBook) async {
        let url = bookURL(book.id)
        await Task.detached {
            if let data = try? JSONEncoder().encode(book) {
                try? data.write(to: url, options: .atomic)
            }
        }.value
    }

    private func saveIndex() async {
        let ids = books.map(\.id)
        let url = indexURL
        await Task.detached {
            if let data = try? JSONEncoder().encode(ids) {
                try? data.write(to: url, options: .atomic)
            }
        }.value
    }

    private func saveProgress() async {
        let snap = progress
        let url = progressURL
        await Task.detached {
            if let data = try? JSONEncoder().encode(snap) {
                try? data.write(to: url, options: .atomic)
            }
        }.value
    }
}
