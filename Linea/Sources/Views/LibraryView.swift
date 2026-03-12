import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var showPicker = false
    @State private var parseError: String?
    @State private var isImporting = false
    @State private var selectedBook: EPUBBook?

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var columns: [GridItem] {
        // iPad: 5 columns landscape / 4 portrait. iPhone: 3 always.
        let count = hSizeClass == .regular ? 5 : 3
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(library.books) { book in
                                BookTileView(
                                    book: book,
                                    progress: library.progressFor(book.id)
                                )
                                .onTapGesture { selectedBook = book }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        library.removeBook(id: book.id)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showPicker = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Importing…").font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                importEPUB(from: url)
            }
        }
        .fullScreenCover(item: $selectedBook) { book in
            BookReaderContainerView(book: book)
                .environmentObject(library)
        }
        .alert("Import Failed", isPresented: Binding(
            get: { parseError != nil },
            set: { if !$0 { parseError = nil } }
        )) {
            Button("OK") { parseError = nil }
        } message: {
            Text(parseError ?? "")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 72))
                .foregroundStyle(.tertiary)
            Text("No Books Yet")
                .font(.title2.bold())
            Text("Tap + to import an EPUB file")
                .foregroundStyle(.secondary)
            Button(action: { showPicker = true }) {
                Label("Import EPUB", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    // MARK: - Import

    private func importEPUB(from url: URL) {
        isImporting = true
        Task.detached {
            do {
                let book = try EPUBParser().parse(url: url)
                await MainActor.run {
                    library.addBook(book)
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    parseError = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

// MARK: - Book tile

struct BookTileView: View {
    let book: EPUBBook
    let progress: BookProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cover — fills the grid cell width
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .bottom) {
                    coverImage
                        .frame(width: w, height: w * 1.45)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

                    if progress.progressFraction > 0 {
                        VStack(spacing: 0) {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.4)).frame(height: 3)
                                Rectangle()
                                    .fill(.white)
                                    .frame(width: w * progress.progressFraction, height: 3)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(width: w, height: w * 1.45)
            }
            .aspectRatio(1/1.45, contentMode: .fit)

            Text(book.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if progress.progressFraction > 0 {
                Text("\(Int(progress.progressFraction * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let img = book.coverImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text(book.title)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                            .foregroundStyle(.secondary)
                    }
                )
        }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // UTType.epub is available iOS 14+; fall back to a mime-type based type if needed
        let epubType = UTType(mimeType: "application/epub+zip") ?? UTType(filenameExtension: "epub") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [epubType])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Security-scoped resource access required for files outside the app sandbox
            guard url.startAccessingSecurityScopedResource() else { onPick(url); return }
            defer { url.stopAccessingSecurityScopedResource() }
            // Copy to a temp location so the parser can read it freely
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tmp)
            if (try? FileManager.default.copyItem(at: url, to: tmp)) != nil {
                onPick(tmp)
            } else {
                onPick(url)
            }
        }
    }
}
