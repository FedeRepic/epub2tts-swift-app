import Foundation
import ReadiumZIPFoundation

enum EPUBImportError: LocalizedError {
    case invalidArchive
    case unsafePath(String)
    case tooLarge
    case missingPackage
    case noReadableChapters

    var errorDescription: String? {
        switch self {
        case .invalidArchive: "El archivo no es un EPUB ZIP válido."
        case .unsafePath(let path): "El EPUB contiene una ruta no permitida: \(path)."
        case .tooLarge: "El EPUB supera el límite de importación local."
        case .missingPackage: "No se encontró el paquete OPF del EPUB."
        case .noReadableChapters: "El EPUB no contiene capítulos XHTML/HTML legibles."
        }
    }
}

actor EPUBImporter {
    private let store: BookLibraryStore
    private let fileManager = FileManager.default
    private let maxUncompressedBytes = UInt64(250 * 1_024 * 1_024)

    init(store: BookLibraryStore) { self.store = store }

    func `import`(sourceURL: URL) async throws -> Book {
        let id = UUID()
        let destination = try await store.bookDirectory(id: id)
        let extraction = destination.appendingPathComponent("EPUB", isDirectory: true)
        try fileManager.createDirectory(at: extraction, withIntermediateDirectories: true)
        let archive: Archive
        do {
            archive = try await Archive(url: sourceURL, accessMode: .read)
        } catch {
            throw EPUBImportError.invalidArchive
        }

        var expanded: UInt64 = 0
        for entry in try await archive.entries() {
            guard isSafe(entry.path) else { throw EPUBImportError.unsafePath(entry.path) }
            expanded += entry.uncompressedSize
            guard expanded <= maxUncompressedBytes else { throw EPUBImportError.tooLarge }
            let destinationURL = extraction.appendingPathComponent(entry.path)
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try await archive.extract(entry, to: destinationURL)
        }

        let parser = EPUBPackageParser(rootURL: extraction)
        let metadata = try parser.parse()
        guard !metadata.chapters.isEmpty else { throw EPUBImportError.noReadableChapters }
        // Store a relative location only. The app container's absolute path is not
        // stable across Xcode installs or app updates.
        return Book(
            id: id,
            title: metadata.title,
            author: metadata.author,
            importedAt: .now,
            rootPath: "Books/\(id.uuidString)/EPUB",
            coverRelativePath: metadata.coverRelativePath,
            chapters: metadata.chapters,
            lastChapterIndex: 0,
            lastChapterProgress: 0
        )
    }

    func refreshNavigationTitles(in books: [Book]) -> [Book] {
        books.map { book in
            guard let metadata = try? EPUBPackageParser(rootURL: book.rootURL).parse(), !metadata.chapters.isEmpty else {
                return book
            }
            var refreshed = book
            refreshed.chapters = metadata.chapters
            refreshed.coverRelativePath = metadata.coverRelativePath
            return refreshed
        }
    }

    private func isSafe(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
}

private struct EPUBPackageParser {
    let rootURL: URL

    private struct NavigationDestination {
        let relativePath: String
        let fragment: String?
        let title: String
    }

    func parse() throws -> (title: String, author: String?, chapters: [EPUBChapter], coverRelativePath: String?) {
        let container = rootURL.appendingPathComponent("META-INF/container.xml")
        let rootFile = try XMLRootFileParser.parse(url: container)
        guard !rootFile.isEmpty else { throw EPUBImportError.missingPackage }
        let packageURL = rootURL.appendingPathComponent(rootFile)
        let package = try OPFParser.parse(url: packageURL)
        let base = packageURL.deletingLastPathComponent()
        let spineItems = package.spine.compactMap { id -> (id: String, item: OPFParser.Item, relativePath: String)? in
            guard let item = package.manifest[id], item.mediaType.contains("html") else { return nil }
            let chapterURL = base.appendingPathComponent(item.href)
            guard FileManager.default.fileExists(atPath: chapterURL.path) else { return nil }
            let relativePath = chapterURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            return (id, item, relativePath)
        }
        let navigation = loadNavigationDestinations(package: package, packageBaseURL: base)
        let coverRelativePath: String? = package.coverItem.flatMap { item -> String? in
            let coverURL = base.appendingPathComponent(item.href).standardizedFileURL
            let rootPath = rootURL.standardizedFileURL.path + "/"
            guard coverURL.path.hasPrefix(rootPath), FileManager.default.fileExists(atPath: coverURL.path) else { return nil }
            return String(coverURL.path.dropFirst(rootPath.count))
        }
        let spineByPath = Dictionary(uniqueKeysWithValues: spineItems.map { ($0.relativePath, $0) })
        let chapters: [EPUBChapter]
        if !navigation.isEmpty {
            let tocChapters = navigation.enumerated().compactMap { index, destination -> EPUBChapter? in
                guard let spineItem = spineByPath[destination.relativePath] else { return nil }
                return EPUBChapter(
                    id: "\(spineItem.id)-toc-\(index)",
                    title: destination.title,
                    relativePath: destination.relativePath,
                    fragment: destination.fragment
                )
            }
            chapters = tocChapters.isEmpty
                ? spineItems.map { EPUBChapter(id: $0.id, title: $0.item.title ?? "Capítulo", relativePath: $0.relativePath) }
                : tocChapters
        } else {
            chapters = spineItems.map { EPUBChapter(id: $0.id, title: $0.item.title ?? "Capítulo", relativePath: $0.relativePath) }
        }
        return (package.title ?? "Sin título", package.author, chapters, coverRelativePath)
    }

    private func loadNavigationDestinations(package: OPFParser, packageBaseURL: URL) -> [NavigationDestination] {
        let navigationItem = package.manifest.values.first {
            $0.properties.split(separator: " ").contains("nav")
        }
        let ncxItem = package.spineTOCID.flatMap { package.manifest[$0] }
            ?? package.manifest.values.first(where: { $0.mediaType.contains("ncx") })
        let entries: [(href: String, title: String)]
        let navigationBaseURL: URL
        if let navigationItem {
            let navigationURL = packageBaseURL.appendingPathComponent(navigationItem.href)
            entries = (try? EPUBNavDocumentParser.parse(url: navigationURL)) ?? []
            navigationBaseURL = navigationURL.deletingLastPathComponent()
        } else if let ncxItem {
            let ncxURL = packageBaseURL.appendingPathComponent(ncxItem.href)
            entries = (try? EPUBNCXParser.parse(url: ncxURL)) ?? []
            navigationBaseURL = ncxURL.deletingLastPathComponent()
        } else {
            entries = []
            navigationBaseURL = packageBaseURL
        }

        return entries.compactMap { entry in
            guard let destination = destination(for: entry.href, title: entry.title, baseURL: navigationBaseURL) else { return nil }
            return destination
        }
    }

    private func destination(for href: String, title: String, baseURL: URL) -> NavigationDestination? {
        let pieces = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = pieces.first.map(String.init) ?? href
        guard !path.isEmpty else { return nil }
        let resolved = baseURL.appendingPathComponent(path).standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path + "/"
        guard resolved.hasPrefix(rootPath) else { return nil }
        let fragment = pieces.count > 1 ? String(pieces[1]) : nil
        return NavigationDestination(
            relativePath: String(resolved.dropFirst(rootPath.count)),
            fragment: fragment,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private final class XMLRootFileParser: NSObject, XMLParserDelegate {
    private var result = ""
    static func parse(url: URL) throws -> String {
        let delegate = XMLRootFileParser()
        let parser = XMLParser(contentsOf: url)!
        parser.delegate = delegate
        guard parser.parse() else { throw EPUBImportError.missingPackage }
        return delegate.result
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if name == "rootfile" { result = attributes["full-path"] ?? "" }
    }
}

private final class OPFParser: NSObject, XMLParserDelegate {
    struct Item { let href: String; let mediaType: String; let title: String?; let properties: String }
    private(set) var title: String?
    private(set) var author: String?
    private(set) var manifest: [String: Item] = [:]
    private(set) var spine: [String] = []
    private(set) var spineTOCID: String?
    private var coverManifestID: String?
    private var currentField: String?
    private var currentValue = ""

    var coverItem: Item? {
        let propertiesCover = manifest.values.first {
            $0.properties.split(separator: " ").contains("cover-image")
        }
        return propertiesCover
            ?? coverManifestID.flatMap { manifest[$0] }
            ?? manifest.values.first {
                $0.mediaType.hasPrefix("image/") &&
                ($0.href.lowercased().contains("cover") || $0.title?.lowercased().contains("cover") == true)
            }
    }

    static func parse(url: URL) throws -> OPFParser {
        let delegate = OPFParser()
        let parser = XMLParser(contentsOf: url)!
        parser.delegate = delegate
        guard parser.parse() else { throw EPUBImportError.missingPackage }
        return delegate
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if name == "item", let id = attributes["id"], let href = attributes["href"], let type = attributes["media-type"] {
            manifest[id] = Item(href: href, mediaType: type, title: attributes["title"], properties: attributes["properties"] ?? "")
        } else if name == "meta",
                  attributes["name"]?.lowercased() == "cover",
                  let coverID = attributes["content"] {
            coverManifestID = coverID
        } else if name == "spine" {
            spineTOCID = attributes["toc"]
        } else if name == "itemref", let idref = attributes["idref"] {
            spine.append(idref)
        } else if name.hasSuffix("title") || name.hasSuffix("creator") {
            currentField = name
            currentValue = ""
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { currentValue += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard currentField == name else { return }
        if name.hasSuffix("title") { title = currentValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        if name.hasSuffix("creator") { author = currentValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        currentField = nil
    }
}

private final class EPUBNavDocumentParser: NSObject, XMLParserDelegate {
    private var currentHref: String?
    private var currentText = ""
    private var result: [(href: String, title: String)] = []
    private var elementDepth = 0
    private var tocDepth: Int?

    static func parse(url: URL) throws -> [(href: String, title: String)] {
        let delegate = EPUBNavDocumentParser()
        guard let parser = XMLParser(contentsOf: url) else { return [] }
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.result
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        elementDepth += 1
        if name == "nav" {
            let type = attributes["epub:type"] ?? attributes["type"] ?? attributes["role"] ?? ""
            if type.split(separator: " ").contains("toc") || type == "doc-toc" {
                tocDepth = elementDepth
            }
        }
        guard name == "a", tocDepth != nil, let href = attributes["href"] else { return }
        currentHref = href
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentHref != nil { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        if name == "a", let href = currentHref {
            let title = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { result.append((href, title)) }
            currentHref = nil
            currentText = ""
        }
        if name == "nav", tocDepth == elementDepth { tocDepth = nil }
        elementDepth -= 1
    }
}

private final class EPUBNCXParser: NSObject, XMLParserDelegate {
    private struct NavPoint {
        var href: String?
        var title = ""
    }

    private var navPoints: [NavPoint] = []
    private var readsText = false
    private var result: [(href: String, title: String)] = []

    static func parse(url: URL) throws -> [(href: String, title: String)] {
        let delegate = EPUBNCXParser()
        guard let parser = XMLParser(contentsOf: url) else { return [] }
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.result
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "navPoint": navPoints.append(NavPoint())
        case "content":
            if !navPoints.isEmpty { navPoints[navPoints.count - 1].href = attributes["src"] }
        case "text": readsText = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readsText, !navPoints.isEmpty { navPoints[navPoints.count - 1].title += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch name {
        case "text": readsText = false
        case "navPoint":
            guard let point = navPoints.popLast(), let href = point.href else { return }
            let title = point.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { result.append((href, title)) }
        default: break
        }
    }
}
