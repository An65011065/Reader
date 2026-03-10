import Foundation
import SwiftUI

// MARK: - Core book model

struct EPUBBook: Identifiable, Codable {
    let id: UUID
    let title: String
    let author: String
    let coverImageData: Data?
    let chapters: [Chapter]

    init(id: UUID = UUID(), title: String, author: String, coverImageData: Data?, chapters: [Chapter]) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImageData = coverImageData
        self.chapters = chapters
    }

    var coverImage: UIImage? {
        coverImageData.flatMap { UIImage(data: $0) }
    }

    // MARK: Chapter

    struct Chapter: Identifiable, Codable {
        let id: UUID
        let title: String
        let text: String          // plain text for TTS
        let html: String          // original HTML for rendering
        let playOrder: Int
        let nestingLevel: Int

        init(id: UUID = UUID(), title: String, text: String, html: String = "", playOrder: Int, nestingLevel: Int = 0) {
            self.id = id
            self.title = title
            self.text = text
            self.html = html
            self.playOrder = playOrder
            self.nestingLevel = nestingLevel
        }

        var wordCount: Int { wordCount(upToCharOffset: text.count) }  // calls shared helper, no extra allocation

        /// Count whitespace-delimited words in text up to (not including) the given character offset.
        /// O(offset) — iterates only the needed prefix.
        func wordCount(upToCharOffset charOffset: Int) -> Int {
            guard charOffset > 0 else { return 0 }
            var count = 0
            var inWord = false
            for ch in text.prefix(min(charOffset, text.count)) {
                if ch.isWhitespace || ch.isNewline { inWord = false }
                else if !inWord { inWord = true; count += 1 }
            }
            return count
        }
    }

    var totalWords: Int { chapters.reduce(0) { $0 + $1.wordCount } }
}

// MARK: - Reading progress (persisted separately)

struct BookProgress: Codable {
    let bookID: UUID
    var chapterIndex: Int
    var wordOffset: Int          // character offset within chapter text
    var lastOpened: Date

    var progressFraction: Double = 0.0   // 0–1

    init(bookID: UUID) {
        self.bookID = bookID
        self.chapterIndex = 0
        self.wordOffset = 0
        self.lastOpened = Date()
    }
}
