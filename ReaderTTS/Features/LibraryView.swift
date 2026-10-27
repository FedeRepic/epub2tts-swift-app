import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var showsImporter = false
    @State private var bookPendingDeletion: Book?
    @State private var searchText = ""
    @AppStorage("librarySortOrder") private var sortOrder = LibrarySortOrder.recent.rawValue

    private let epubType = UTType(filenameExtension: "epub") ?? .zip
    private let columns = [GridItem(.adaptive(minimum: 142, maximum: 190), spacing: 22)]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.books.isEmpty && !viewModel.isImporting {
                    ContentUnavailableView(
                        "Tu biblioteca está vacía",
                        systemImage: "books.vertical",
                        description: Text("Importa un EPUB sin DRM para comenzar.")
                    )
                } else if filteredBooks.isEmpty {
                    ContentUnavailableView(
                        "No hay resultados",
                        systemImage: "magnifyingglass",
                        description: Text("Prueba con otro título o autor.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 26) {
                            ForEach(filteredBooks) { book in
                                NavigationLink {
                                    reader(for: book)
                                } label: {
                                    LibraryBookCard(book: book)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Eliminar libro", systemImage: "trash", role: .destructive) {
                                        bookPendingDeletion = book
                                    }
                                }
                                .accessibilityHint("Abre \(book.title)")
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                    }
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $searchText, prompt: "Buscar título o autor")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Importar EPUB", systemImage: "plus") { showsImporter = true }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Picker("Ordenar", selection: $sortOrder) {
                            ForEach(LibrarySortOrder.allCases) { order in
                                Text(order.title).tag(order.rawValue)
                            }
                        }
                    } label: {
                        Label("Ordenar", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [epubType]) { result in
            if case .success(let url) = result { viewModel.importBook(from: url) }
        }
        .alert(
            "¿Eliminar libro?",
            isPresented: Binding(
                get: { bookPendingDeletion != nil },
                set: { if !$0 { bookPendingDeletion = nil } }
            ),
            presenting: bookPendingDeletion
        ) { book in
            Button("Eliminar", role: .destructive) {
                viewModel.deleteBook(book)
                bookPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) { bookPendingDeletion = nil }
        } message: { book in
            Text("Se eliminarán de este iPad el libro y su posición de lectura. Esta acción no se puede deshacer.")
        }
        .alert(
            "No se pudo completar la operación",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("Aceptar", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay {
            if viewModel.isImporting {
                ProgressView("Importando EPUB…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear { viewModel.load() }
    }

    @ViewBuilder
    private func reader(for book: Book) -> some View {
        ReadiumReaderView(
            book: book,
            onReadiumLocator: { locatorJSON in
                viewModel.saveReadiumLocator(bookID: book.id, locatorJSON: locatorJSON)
            },
            onCreateBookmark: { bookmark in
                viewModel.addBookmark(bookID: book.id, bookmark: bookmark)
            },
            onDeleteBookmark: { bookmarkID in
                viewModel.deleteBookmark(bookID: book.id, bookmarkID: bookmarkID)
            }
        )
        .id(book.id)
    }

    private var filteredBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingBooks = query.isEmpty ? viewModel.books : viewModel.books.filter { book in
            book.title.localizedCaseInsensitiveContains(query) ||
            (book.author?.localizedCaseInsensitiveContains(query) ?? false)
        }

        switch LibrarySortOrder(rawValue: sortOrder) ?? .recent {
        case .recent:
            return matchingBooks.sorted { left, right in
                (left.lastReadAt ?? left.importedAt) > (right.lastReadAt ?? right.importedAt)
            }
        case .title:
            return matchingBooks.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .author:
            return matchingBooks.sorted {
                ($0.author ?? $0.title).localizedStandardCompare($1.author ?? $1.title) == .orderedAscending
            }
        }
    }
}

private enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case recent
    case title
    case author

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Últimos leídos"
        case .title: "Título"
        case .author: "Autor"
        }
    }
}

private struct LibraryBookCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            BookCover(book: book)

            Text(book.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let author = book.author, !author.isEmpty {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(.subheadline)
            }

            HStack(spacing: 8) {
                if let progression = book.lastReadiumTotalProgression, progression > 0 {
                    Text("Continuar · \(Int((progression * 100).rounded())) %")
                } else {
                    Text("\(book.chapters.count) capítulos")
                }
                if !book.bookmarks.isEmpty {
                    Label("\(book.bookmarks.count)", systemImage: "bookmark.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BookCover: View {
    let book: Book

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)

            if let url = book.coverURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 34, weight: .medium))
                    Text(book.title)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 12)
                }
                .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(0.66, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.black.opacity(0.13), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 4, y: 3)
        .overlay(alignment: .bottom) {
            if let progression = book.lastReadiumTotalProgression, progression > 0 {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(4, proxy.size.width * progression), height: 4)
                }
                .frame(height: 4)
                .padding(6)
            }
        }
        .accessibilityLabel("Portada de \(book.title)")
    }
}
