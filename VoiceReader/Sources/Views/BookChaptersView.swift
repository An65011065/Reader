import SwiftUI

struct BookChaptersView: View {
    let book: EPUBBook
    @Binding var selectedChapterIndex: Int
    @ObservedObject var speech: SpeechService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    coverThumb
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text("Chapter \(selectedChapterIndex + 1) of \(book.chapters.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                List {
                    ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                        ChapterRowView(
                            chapter: chapter,
                            index: index,
                            isSelected: index == selectedChapterIndex,
                            onTap: {
                                selectedChapterIndex = index
                                speech.speak(text: chapter.text)
                                dismiss()
                            }
                        )
                        .listRowSeparator(chapter.nestingLevel == 0 ? .visible : .hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    }
                }
                .listStyle(.plain)
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Chapter row

private struct ChapterRowView: View {
    let chapter: EPUBBook.Chapter
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 0) {
                if chapter.nestingLevel > 0 {
                    Color.clear.frame(width: CGFloat(chapter.nestingLevel) * 24)
                }
                Text(chapter.title)
                    .font(chapter.nestingLevel == 0 ? .body.bold() : .body)
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.75))
                    .lineLimit(2)
                Spacer(minLength: 12)
                Text("\(index + 1)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, chapter.nestingLevel == 0 ? 12 : 7)
        }
        .listRowBackground(Group {
            if isSelected {
                Color(.systemGray5).clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Color.clear
            }
        })
    }
}

// MARK: - Cover thumbnail

private extension BookChaptersView {
    @ViewBuilder
    var coverThumb: some View {
        if let img = book.coverImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 44, height: 60)
                .overlay(Image(systemName: "book.closed.fill").foregroundStyle(.tertiary))
        }
    }
}
