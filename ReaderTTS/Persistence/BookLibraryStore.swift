import Foundation

actor BookLibraryStore {
    private let fileManager = FileManager.default

    private var libraryURL: URL {
        get throws {
            let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = base.appendingPathComponent("ReaderTTS", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    func loadBooks() throws -> [Book] {
        let url = try libraryURL.appendingPathComponent("library.json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Book].self, from: Data(contentsOf: url))
            .sorted { $0.importedAt > $1.importedAt }
    }

    func saveBooks(_ books: [Book]) throws {
        let url = try libraryURL.appendingPathComponent("library.json")
        let data = try JSONEncoder().encode(books)
        try data.write(to: url, options: .atomic)
    }

    func bookDirectory(id: UUID) throws -> URL {
        let directory = try libraryURL.appendingPathComponent("Books", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func deleteBookDirectory(id: UUID) throws {
        let directory = try libraryURL
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
