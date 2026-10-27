import Foundation

struct Book: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let author: String?
    let importedAt: Date
    let rootPath: String
    /// Ruta relativa de la portada dentro del EPUB extraído. Puede faltar en
    /// EPUB antiguos o en libros que no proporcionan una imagen de portada.
    var coverRelativePath: String?
    var chapters: [EPUBChapter]
    /// Campos heredados de la primera implementación del lector. Se conservan
    /// al decodificar bibliotecas existentes; Readium persiste ahora el
    /// localizador preciso y el progreso global de abajo.
    var lastChapterIndex: Int
    var lastChapterProgress: Double?
    /// Posición precisa que proporciona Readium. Se conserva como JSON opaco
    /// para no acoplar el modelo persistido a una versión concreta de Readium.
    /// Es opcional para mantener compatibles las bibliotecas ya existentes.
    var lastReadiumLocatorJSON: String? = nil
    /// Progreso global asociado al localizador de Readium. Se persiste separado
    /// para mostrar "Continuar" sin acoplar la biblioteca a Readium.
    var lastReadiumTotalProgression: Double? = nil
    /// Fecha local de la última posición informada por Readium.
    var lastReadAt: Date? = nil
    /// Marcadores creados localmente. Cada uno guarda el localizador opaco de
    /// Readium, por lo que sigue funcionando aunque cambie la paginación.
    var bookmarks: [ReadingBookmark] = []

    init(
        id: UUID,
        title: String,
        author: String?,
        importedAt: Date,
        rootPath: String,
        coverRelativePath: String? = nil,
        chapters: [EPUBChapter],
        lastChapterIndex: Int,
        lastChapterProgress: Double?,
        lastReadiumLocatorJSON: String? = nil,
        lastReadiumTotalProgression: Double? = nil,
        lastReadAt: Date? = nil,
        bookmarks: [ReadingBookmark] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.importedAt = importedAt
        self.rootPath = rootPath
        self.coverRelativePath = coverRelativePath
        self.chapters = chapters
        self.lastChapterIndex = lastChapterIndex
        self.lastChapterProgress = lastChapterProgress
        self.lastReadiumLocatorJSON = lastReadiumLocatorJSON
        self.lastReadiumTotalProgression = lastReadiumTotalProgression
        self.lastReadAt = lastReadAt
        self.bookmarks = bookmarks
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, author, importedAt, rootPath, coverRelativePath, chapters, lastChapterIndex
        case lastChapterProgress, lastReadiumLocatorJSON, lastReadiumTotalProgression, lastReadAt, bookmarks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        rootPath = try container.decode(String.self, forKey: .rootPath)
        coverRelativePath = try container.decodeIfPresent(String.self, forKey: .coverRelativePath)
        chapters = try container.decode([EPUBChapter].self, forKey: .chapters)
        lastChapterIndex = try container.decode(Int.self, forKey: .lastChapterIndex)
        lastChapterProgress = try container.decodeIfPresent(Double.self, forKey: .lastChapterProgress)
        lastReadiumLocatorJSON = try container.decodeIfPresent(String.self, forKey: .lastReadiumLocatorJSON)
        lastReadiumTotalProgression = try container.decodeIfPresent(Double.self, forKey: .lastReadiumTotalProgression)
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        bookmarks = try container.decodeIfPresent([ReadingBookmark].self, forKey: .bookmarks) ?? []
    }

    /// Never trust the persisted absolute path here. iPadOS can move an app to a
    /// new container UUID when Xcode installs an update, while preserving the
    /// library JSON and the `Books/<id>` directory. Deriving the URL again keeps
    /// already-imported books readable after each development install.
    var rootURL: URL {
        let fileManager = FileManager.default
        if let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            let currentLocation = applicationSupport
                .appendingPathComponent("ReaderTTS", isDirectory: true)
                .appendingPathComponent("Books", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent("EPUB", isDirectory: true)
            if fileManager.fileExists(atPath: currentLocation.path) {
                return currentLocation
            }
        }

        // Compatibility fallback for records created before relative storage was
        // introduced. New and repaired records resolve through the branch above.
        return URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    var coverURL: URL? {
        guard let coverRelativePath, !coverRelativePath.isEmpty else { return nil }
        let url = rootURL.appendingPathComponent(coverRelativePath).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(rootPath), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}

struct ReadingBookmark: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let locatorJSON: String
    let title: String
    let progression: Double?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        locatorJSON: String,
        title: String,
        progression: Double?,
        createdAt: Date = .now
    ) {
        self.id = id
        self.locatorJSON = locatorJSON
        self.title = title
        self.progression = progression
        self.createdAt = createdAt
    }
}

struct EPUBChapter: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let relativePath: String
    let fragment: String?

    init(id: String, title: String, relativePath: String, fragment: String? = nil) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.fragment = fragment
    }

    func url(in book: Book) -> URL {
        let fileURL = book.rootURL.appendingPathComponent(relativePath)
        guard let fragment, !fragment.isEmpty else { return fileURL }
        var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)
        components?.fragment = fragment
        return components?.url ?? fileURL
    }
}
