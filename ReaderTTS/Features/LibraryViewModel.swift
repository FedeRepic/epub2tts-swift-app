import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var errorMessage: String?
    @Published private(set) var isImporting = false

    private let store = BookLibraryStore()
    private lazy var importer = EPUBImporter(store: store)
    private var readiumSaveTask: Task<Void, Never>?

    func load() {
        Task {
            do {
                let loadedBooks = try await store.loadBooks()
                books = await importer.refreshNavigationTitles(in: loadedBooks)
                try await store.saveBooks(books)
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func importBook(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        isImporting = true
        errorMessage = nil
        Task {
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
                isImporting = false
            }
            do {
                let book = try await importer.import(sourceURL: url)
                books.insert(book, at: 0)
                try await store.saveBooks(books)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveReadiumLocator(bookID: UUID, locatorJSON: String?) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        guard books[index].lastReadiumLocatorJSON != locatorJSON else { return }
        books[index].lastReadiumLocatorJSON = locatorJSON
        books[index].lastReadiumTotalProgression = ReadiumLocatorProgress.totalProgression(in: locatorJSON)
        books[index].lastReadAt = .now

        // Readium can report several positions while the reader settles after
        // a gesture. Debouncing avoids writing the library for each callback.
        let snapshot = books
        readiumSaveTask?.cancel()
        readiumSaveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            try? await store.saveBooks(snapshot)
        }
    }

    func addBookmark(bookID: UUID, bookmark: ReadingBookmark) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        guard !books[index].bookmarks.contains(where: { $0.locatorJSON == bookmark.locatorJSON }) else { return }
        books[index].bookmarks.insert(bookmark, at: 0)
        saveLibraryImmediately()
    }

    func deleteBookmark(bookID: UUID, bookmarkID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].bookmarks.removeAll { $0.id == bookmarkID }
        saveLibraryImmediately()
    }

    private func saveLibraryImmediately() {
        let snapshot = books
        readiumSaveTask?.cancel()
        Task { [store] in
            try? await store.saveBooks(snapshot)
        }
    }

    func deleteBook(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        let previousBooks = books
        books.remove(at: index)
        errorMessage = nil
        Task {
            do {
                try await store.saveBooks(books)
                try await store.deleteBookDirectory(id: book.id)
            } catch {
                books = previousBooks
                try? await store.saveBooks(previousBooks)
                errorMessage = "No se pudo eliminar \(book.title): \(error.localizedDescription)"
            }
        }
    }
}

private enum ReadiumLocatorProgress {
    static func totalProgression(in locatorJSON: String?) -> Double? {
        guard let locatorJSON,
              let data = locatorJSON.data(using: .utf8),
              let locator = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locations = locator["locations"] as? [String: Any],
              let progression = locations["totalProgression"] as? NSNumber
        else { return nil }
        return min(max(progression.doubleValue, 0), 1)
    }
}
