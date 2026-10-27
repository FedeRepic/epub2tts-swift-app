import Foundation
import SwiftUI
import UIKit
import ReadiumZIPFoundation
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer

/// Lector principal basado en Readium. Reconstruye un paquete temporal desde
/// la copia extraída del EPUB para conservar libros ya importados.
struct ReadiumReaderScreen: View {
    let book: Book
    let onLocationChange: (String?) -> Void
    let onCreateBookmark: (ReadingBookmark) -> Void
    let onDeleteBookmark: (UUID) -> Void
    @ObservedObject var playback: ReaderPlaybackViewModel

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("readerFontScale") private var fontScale = 1.0
    @AppStorage("readerFontFamily") private var fontFamily = ReaderFont.system.rawValue
    @AppStorage("readerLineHeight") private var lineHeight = 1.55
    @AppStorage("readerLetterSpacing") private var letterSpacing = 0.0
    @AppStorage("readerHorizontalMargin") private var horizontalMargin = 1.0
    @AppStorage("readerHighlightColor") private var highlightColor = "yellow"
    @AppStorage("readerSpeechRate") private var speechRate = 1.1
    @AppStorage("readerTTSVoiceID") private var voiceID = SupertonicVoice.f1.rawValue
    @AppStorage("readerTTSLanguageMode") private var languageMode = TTSSynthesisLanguage.spanish.rawValue
    @AppStorage("readerTTSInitialPrefetchCount") private var initialPrefetchCount = 3
    @StateObject private var viewModel: ReadiumReaderViewModel
    @State private var showsTableOfContents = false
    @State private var showsAppearanceSettings = false
    @State private var showsBookmarks = false
    @State private var bookmarks: [ReadingBookmark]

    init(
        book: Book,
        initialLocatorJSON: String? = nil,
        playback: ReaderPlaybackViewModel,
        onLocationChange: @escaping (String?) -> Void = { _ in },
        onCreateBookmark: @escaping (ReadingBookmark) -> Void = { _ in },
        onDeleteBookmark: @escaping (UUID) -> Void = { _ in }
    ) {
        self.book = book
        self.playback = playback
        self.onLocationChange = onLocationChange
        self.onCreateBookmark = onCreateBookmark
        self.onDeleteBookmark = onDeleteBookmark
        _bookmarks = State(initialValue: book.bookmarks)
        _viewModel = StateObject(wrappedValue: ReadiumReaderViewModel(
            book: book,
            initialLocatorJSON: initialLocatorJSON ?? book.lastReadiumLocatorJSON,
            onLocationChange: onLocationChange
        ))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .preparing(let message):
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparando lector Readium")
                        .font(.headline)
                    Text(message)
                        .foregroundStyle(.secondary)
                }

            case .failed(let message):
                ContentUnavailableView(
                    "No se pudo abrir con Readium",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )

            case .ready:
                if let navigator = viewModel.navigator {
                    ReadiumNavigatorContainer(navigator: navigator)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(isPhone ? "" : book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Índice", systemImage: "list.bullet") {
                    showsTableOfContents = true
                }
                .disabled(viewModel.tableOfContents.isEmpty)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isPhone {
                    readerToolsMenu

                    Button {
                        viewModel.togglePlayback(playback: playback, bookTitle: book.title)
                    } label: {
                        Image(systemName: playback.buttonSymbol)
                    }
                    .disabled(viewModel.isExtractingText)
                    .accessibilityLabel(playback.buttonTitle)

                    Button {
                        playback.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .disabled(!playback.canStop)
                    .accessibilityLabel("Detener")
                }

                Button {
                    showsAppearanceSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Configuración del lector")
            }
        }
        .task {
            await viewModel.openIfNeeded()
            viewModel.apply(appearance)
            playback.setSpeechRate(speechRate)
            playback.setVoiceID(voiceID)
            playback.setLanguageMode(languageMode)
            playback.setInitialPrefetchCount(initialPrefetchCount)
            playback.setTextFinishedHandler { [weak viewModel, weak playback] in
                guard let playback else { return }
                viewModel?.continuePlayback(playback: playback, bookTitle: book.title)
            }
            playback.setTextWillFinishHandler { [weak viewModel, weak playback] in
                guard let playback else { return }
                viewModel?.prefetchNextSection(playback: playback)
            }
        }
        .onChange(of: appearance) { _, value in
            viewModel.apply(value)
        }
        .onChange(of: speechRate) { _, value in
            playback.setSpeechRate(value)
        }
        .onChange(of: voiceID) { _, value in
            playback.setVoiceID(value)
        }
        .onChange(of: languageMode) { _, value in
            playback.setLanguageMode(value)
        }
        .onChange(of: initialPrefetchCount) { _, value in
            playback.setInitialPrefetchCount(value)
        }
        .onChange(of: playback.activeSegment) { _, text in
            viewModel.updatePlaybackDecoration(
                text: text,
                tint: playbackTint,
                progression: playback.activeSegmentProgression
            )
        }
        .onChange(of: highlightColor) { _, _ in
            viewModel.updatePlaybackDecoration(
                text: playback.activeSegment,
                tint: playbackTint,
                progression: playback.activeSegmentProgression
            )
        }
        .onDisappear {
            viewModel.clearPlaybackDecoration()
            playback.clearTextFinishedHandler()
            playback.clearTextWillFinishHandler()
            playback.stop()
        }
        .safeAreaInset(edge: .bottom) {
            if case .ready = viewModel.state {
                VStack(spacing: 0) {
                    if viewModel.isExtractingText {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Preparando el texto de esta sección…")
                            Spacer(minLength: 0)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    } else if let error = viewModel.ttsError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                            Spacer(minLength: 0)
                        }
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    if !isPhone {
                        playbackControls
                    }
                    readerFooter
                }
                .background(.bar)
            }
        }
        .sheet(isPresented: $showsTableOfContents) {
            NavigationStack {
                List(viewModel.tableOfContents) { entry in
                    Button {
                        viewModel.go(to: entry)
                        showsTableOfContents = false
                    } label: {
                        Text(entry.title)
                            .foregroundStyle(.primary)
                            .padding(.leading, CGFloat(entry.depth) * 14)
                    }
                    .accessibilityLabel("Ir a \(entry.title)")
                }
                .navigationTitle("Índice")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { showsTableOfContents = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsAppearanceSettings) {
            ReaderAppearanceSettings(
                fontScale: $fontScale,
                fontFamily: $fontFamily,
                lineHeight: $lineHeight,
                letterSpacing: $letterSpacing,
                horizontalMargin: $horizontalMargin,
                highlightColor: $highlightColor,
                speechRate: $speechRate,
                voiceID: $voiceID,
                languageMode: $languageMode,
                initialPrefetchCount: $initialPrefetchCount,
                isPlaybackActive: playback.canStop
            )
        }
        .sheet(isPresented: $showsBookmarks) {
            NavigationStack {
                Group {
                    if bookmarks.isEmpty {
                        ContentUnavailableView(
                            "No hay marcadores",
                            systemImage: "bookmark",
                            description: Text("Guarda tu posición con el botón de marcador.")
                        )
                    } else {
                        List {
                            ForEach(bookmarks) { bookmark in
                                Button {
                                    viewModel.go(to: bookmark)
                                    showsBookmarks = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bookmark.title)
                                            .foregroundStyle(.primary)
                                        if let progression = bookmark.progression {
                                            Text("\(Int((progression * 100).rounded())) % del libro")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .swipeActions {
                                    Button("Eliminar", role: .destructive) {
                                        bookmarks.removeAll { $0.id == bookmark.id }
                                        onDeleteBookmark(bookmark.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Marcadores")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { showsBookmarks = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func addCurrentBookmark() {
        guard let bookmark = viewModel.makeBookmark(),
              !bookmarks.contains(where: { $0.locatorJSON == bookmark.locatorJSON })
        else { return }
        bookmarks.insert(bookmark, at: 0)
        onCreateBookmark(bookmark)
    }

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var readerToolsMenu: some View {
        Menu {
            Button("Marcadores", systemImage: "bookmark") {
                showsBookmarks = true
            }

            Button("Añadir marcador", systemImage: "bookmark.fill") {
                addCurrentBookmark()
            }
            .disabled(!viewModel.canCreateBookmark)

            Divider()

            Button("Temporizador: 15 minutos", systemImage: "moon.zzz") {
                playback.setSleepTimer(minutes: 15)
            }
            .disabled(!playback.canStop)
            Button("Temporizador: 30 minutos", systemImage: "moon.zzz") {
                playback.setSleepTimer(minutes: 30)
            }
            .disabled(!playback.canStop)
            Button("Temporizador: 45 minutos", systemImage: "moon.zzz") {
                playback.setSleepTimer(minutes: 45)
            }
            .disabled(!playback.canStop)

            if playback.sleepTimerEndDate != nil {
                Button("Cancelar temporizador", role: .destructive) {
                    playback.setSleepTimer(minutes: nil)
                }
            }
        } label: {
            Image(systemName: playback.sleepTimerEndDate == nil ? "bookmark" : "bookmark.fill")
        }
        .accessibilityLabel("Marcadores y temporizador")
    }

    private var playbackControls: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.togglePlayback(playback: playback, bookTitle: book.title)
            } label: {
                Label(playback.buttonTitle, systemImage: playback.buttonSymbol)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isExtractingText)

            Button("Detener", systemImage: "stop.fill") {
                playback.stop()
            }
            .buttonStyle(.bordered)
            .disabled(!playback.canStop)

            Divider()
                .frame(height: 28)

            Button("Marcadores", systemImage: "bookmark") {
                showsBookmarks = true
            }
            .buttonStyle(.bordered)

            Button("Añadir marcador", systemImage: "bookmark.fill") {
                addCurrentBookmark()
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canCreateBookmark)

            sleepTimerMenu
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var sleepTimerMenu: some View {
        Menu {
            Button("15 minutos") { playback.setSleepTimer(minutes: 15) }
            Button("30 minutos") { playback.setSleepTimer(minutes: 30) }
            Button("45 minutos") { playback.setSleepTimer(minutes: 45) }
            if playback.sleepTimerEndDate != nil {
                Divider()
                Button("Cancelar temporizador", role: .destructive) {
                    playback.setSleepTimer(minutes: nil)
                }
            }
        } label: {
            Label(
                playback.sleepTimerEndDate == nil ? "Temporizador" : "Temporizador activo",
                systemImage: "moon.zzz"
            )
        }
        .buttonStyle(.bordered)
        .disabled(!playback.canStop)
    }

    @ViewBuilder
    private var readerFooter: some View {
        HStack(spacing: 10) {
            if isPhone {
                if let sleepTimerDescription = playback.sleepTimerDescription {
                    Image(systemName: "moon.zzz.fill")
                    Text(sleepTimerDescription)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(viewModel.positionLabel)
                    .monospacedDigit()
            } else {
                Image(systemName: "book.pages")
                    .foregroundStyle(.tint)
                Text("Readium 3.8.0 · Supertonic local")
                Spacer(minLength: 8)
                Text(viewModel.positionLabel)
                    .monospacedDigit()
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, isPhone ? 6 : 9)
    }

    private var appearance: ReadiumAppearance {
        ReadiumAppearance(
            fontScale: fontScale,
            fontFamily: ReaderFont(rawValue: fontFamily) ?? .system,
            lineHeight: lineHeight,
            letterSpacing: letterSpacing,
            horizontalMargin: horizontalMargin,
            isDark: colorScheme == .dark
        )
    }

    private var playbackTint: UIColor {
        switch highlightColor {
        case "orange": .systemOrange
        case "mint": .systemMint
        case "blue": .systemCyan
        case "pink": .systemPink
        default: .systemYellow
        }
    }
}

/// Conserva el ciclo de vida de reproducción mientras se lee un libro.
struct ReadiumReaderView: View {
    let book: Book
    let onReadiumLocator: (String?) -> Void
    let onCreateBookmark: (ReadingBookmark) -> Void
    let onDeleteBookmark: (UUID) -> Void

    @StateObject private var playback = ReaderPlaybackViewModel()

    var body: some View {
        ReadiumReaderScreen(
            book: book,
            playback: playback,
            onLocationChange: onReadiumLocator,
            onCreateBookmark: onCreateBookmark,
            onDeleteBookmark: onDeleteBookmark
        )
    }
}

private struct ReadiumTableOfContentsEntry: Identifiable {
    let id: String
    let title: String
    let depth: Int
    let link: ReadiumShared.Link
}

private struct ReadiumAppearance: Equatable {
    let fontScale: Double
    let fontFamily: ReaderFont
    let lineHeight: Double
    let letterSpacing: Double
    let horizontalMargin: Double
    let isDark: Bool

    var preferences: EPUBPreferences {
        EPUBPreferences(
            fontFamily: readiumFontFamily,
            fontSize: fontScale * fontFamily.readingScale,
            letterSpacing: letterSpacing,
            lineHeight: lineHeight,
            pageMargins: horizontalMargin,
            publisherStyles: false,
            scroll: true,
            textNormalization: true,
            theme: isDark ? .dark : .light
        )
    }

    private var readiumFontFamily: FontFamily {
        switch fontFamily {
        case .system: .sansSerif
        case .serif: .serif
        case .rounded: .cursive
        case .monospaced: .monospace
        }
    }
}

private struct ReadiumNavigatorContainer: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { navigator }

    func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {}
}

@MainActor
private final class ReadiumReaderViewModel: NSObject, ObservableObject, EPUBNavigatorDelegate {
    enum State: Equatable {
        case preparing(String)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .preparing("Preparando el EPUB local…")
    @Published private(set) var navigator: EPUBNavigatorViewController?
    @Published private(set) var positionLabel = "Inicio"
    @Published private(set) var tableOfContents: [ReadiumTableOfContentsEntry] = []
    @Published private(set) var isExtractingText = false
    @Published private(set) var ttsError: String?

    private let book: Book
    private let initialLocatorJSON: String?
    private let onLocationChange: (String?) -> Void
    private var isOpening = false
    private var lastReportedLocatorJSON: String?
    private var appliedAppearance: ReadiumAppearance?
    private var publication: Publication?
    private var playbackLocator: Locator?

    init(
        book: Book,
        initialLocatorJSON: String?,
        onLocationChange: @escaping (String?) -> Void
    ) {
        self.book = book
        self.initialLocatorJSON = initialLocatorJSON
        self.onLocationChange = onLocationChange
        super.init()
    }

    func openIfNeeded() async {
        guard !isOpening, navigator == nil else { return }
        isOpening = true
        defer { isOpening = false }

        do {
            state = .preparing("Creando una copia de prueba del EPUB…")
            let packageURL = try await Task.detached(priority: .userInitiated) { [rootURL = book.rootURL] in
                try await ReadiumPublicationArchive.packageURL(for: rootURL)
            }.value

            state = .preparing("Leyendo el paquete EPUB con Readium…")
            guard let fileURL = FileURL(url: packageURL) else {
                throw ReadiumReaderError.invalidLocalURL
            }

            let httpClient = DefaultHTTPClient()
            let assetRetriever = AssetRetriever(httpClient: httpClient)
            let asset: Asset
            switch await assetRetriever.retrieve(url: fileURL) {
            case .success(let value):
                asset = value
            case .failure(let error):
                throw error
            }

            let opener = PublicationOpener(
                parser: DefaultPublicationParser(
                    httpClient: httpClient,
                    assetRetriever: assetRetriever,
                    pdfFactory: DefaultPDFDocumentFactory()
                )
            )
            let publication: Publication
            switch await opener.open(asset: asset, allowUserInteraction: false) {
            case .success(let value):
                publication = value
            case .failure(let error):
                throw error
            }

            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocation(),
                config: .init(preferences: .empty)
            )
            navigator.delegate = self
            tableOfContents = Self.flatten(publication.manifest.tableOfContents)
            self.publication = publication
            self.navigator = navigator
            state = .ready
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        if let progression = locator.locations.totalProgression {
            positionLabel = "\(Int((progression * 100).rounded())) %"
        } else {
            positionLabel = "Leyendo"
        }
        report(locator: locator)
    }

    var canCreateBookmark: Bool {
        navigator?.currentLocation?.jsonString != nil
    }

    func makeBookmark() -> ReadingBookmark? {
        guard let locator = navigator?.currentLocation,
              let locatorJSON = locator.jsonString
        else { return nil }

        let title = locator.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReadingBookmark(
            locatorJSON: locatorJSON,
            title: (title?.isEmpty == false) ? title! : "Posición de lectura",
            progression: locator.locations.totalProgression
        )
    }

    func go(to bookmark: ReadingBookmark) {
        guard let navigator, let locator = try? Locator(jsonString: bookmark.locatorJSON) else { return }
        Task {
            _ = await navigator.go(to: locator, options: .animated)
        }
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        state = .failed("Readium informó un problema de navegación: \(error).")
    }

    func apply(_ appearance: ReadiumAppearance) {
        guard appearance != appliedAppearance else { return }
        appliedAppearance = appearance
        navigator?.submitPreferences(appearance.preferences)
    }

    func go(to entry: ReadiumTableOfContentsEntry) {
        guard let navigator else { return }
        Task {
            _ = await navigator.go(to: entry.link, options: .animated)
        }
    }

    func togglePlayback(playback: ReaderPlaybackViewModel, bookTitle: String) {
        if playback.canStop {
            playback.toggle(text: "", bookTitle: bookTitle, chapterTitle: "")
            return
        }
        guard !isExtractingText else { return }

        ttsError = nil
        isExtractingText = true
        Task { [weak self] in
            guard let self else { return }
            defer { isExtractingText = false }
            do {
                let section = try currentSectionText()
                playbackLocator = section.locator
                playback.toggle(
                    text: section.text,
                    bookTitle: bookTitle,
                    chapterTitle: section.title,
                    sourceProgression: section.startProgression
                )
            } catch {
                playback.stop()
                ttsError = error.localizedDescription
            }
        }
    }

    func continuePlayback(playback: ReaderPlaybackViewModel, bookTitle: String) {
        guard !isExtractingText, let publication, let navigator else { return }
        let currentHref = navigator.currentLocation?.href.string ?? playbackLocator?.href.string
        guard let currentHref,
              let currentIndex = publication.readingOrder.firstIndex(where: { $0.href == currentHref })
        else {
            playback.stop()
            return
        }

        let remainingResources = publication.readingOrder.dropFirst(currentIndex + 1)
        guard !remainingResources.isEmpty else {
            playback.stop()
            return
        }

        isExtractingText = true
        ttsError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isExtractingText = false }

            for resource in remainingResources {
                guard let text = try? text(for: resource.href), !text.isEmpty else { continue }
                let navigated = await navigator.go(to: resource, options: .animated)
                guard navigated else { continue }

                // `currentLocation` is updated by Readium's delegate
                // asynchronously. Build the new locator from the destination
                // link so the first highlight cannot point back to the chapter
                // that just finished.
                playbackLocator = Locator(
                    href: resource,
                    mediaType: resource.mediaType ?? .xhtml,
                    title: resource.title
                )
                playback.toggle(
                    text: text,
                    bookTitle: bookTitle,
                    chapterTitle: resource.title ?? "Lectura",
                    sourceProgression: 0,
                    initialPrefetchCount: 1
                )
                return
            }
            playback.stop()
        }
    }

    func prefetchNextSection(playback: ReaderPlaybackViewModel) {
        guard let publication, let navigator else { return }
        let currentHref = navigator.currentLocation?.href.string ?? playbackLocator?.href.string
        guard let currentHref,
              let currentIndex = publication.readingOrder.firstIndex(where: { $0.href == currentHref })
        else { return }

        let remainingResources = publication.readingOrder.dropFirst(currentIndex + 1)
        Task { [weak self] in
            guard let self else { return }
            for resource in remainingResources {
                guard let text = try? text(for: resource.href), !text.isEmpty else { continue }
                playback.prefetchContinuation(text: text)
                return
            }
        }
    }

    func updatePlaybackDecoration(text: String?, tint: UIColor, progression: Double?) {
        guard let navigator else { return }
        guard let text, !text.isEmpty, let playbackLocator else {
            clearPlaybackDecoration()
            return
        }

        let locator = playbackLocator.copy(
            locations: { locations in
                if let progression {
                    locations.progression = progression
                }
            },
            text: { $0.highlight = text }
        )
        let decoration = Decoration(
            id: "supertonic-current-segment",
            locator: locator,
            // An active Readium highlight adds an underline as well as the
            // background color. The reading cursor only needs the latter.
            style: .highlight(tint: tint, isActive: false)
        )
        navigator.apply(decorations: [decoration], in: "supertonic-tts")
        Task {
            _ = await navigator.go(to: locator, options: .animated)
        }
    }

    func clearPlaybackDecoration() {
        navigator?.apply(decorations: [], in: "supertonic-tts")
        playbackLocator = nil
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "\(error)"
    }

    private func initialLocation() -> Locator? {
        guard let json = initialLocatorJSON else { return nil }
        return try? Locator(jsonString: json)
    }

    private func report(locator: Locator) {
        guard let json = locator.jsonString, json != lastReportedLocatorJSON else { return }
        lastReportedLocatorJSON = json
        onLocationChange(json)
    }

    private func currentSectionText() throws -> (text: String, title: String, locator: Locator?, startProgression: Double) {
        guard let publication, let navigator else { throw ReadiumReaderError.noReadableText }
        guard let resourceHref = navigator.currentLocation?.href.string ?? publication.readingOrder.first?.href,
              let unresolvedURL = URL(string: resourceHref, relativeTo: book.rootURL)
        else { throw ReadiumReaderError.noReadableText }

        var components = URLComponents(url: unresolvedURL.absoluteURL, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        let resourceURL = (components?.url ?? unresolvedURL.absoluteURL).standardizedFileURL
        let rootPath = book.rootURL.standardizedFileURL.path + "/"
        guard resourceURL.path.hasPrefix(rootPath) else { throw ReadiumReaderError.noReadableText }

        let fullText = try text(for: resourceHref)
        let readingStart = EPUBReadingStart.in(
            fullText,
            near: navigator.currentLocation?.locations.progression
        )
        let title = navigator.currentLocation?.title
            ?? publication.readingOrder.first(where: { $0.href == resourceHref })?.title
            ?? "Lectura"
        return (readingStart.text, title, navigator.currentLocation, readingStart.progression)
    }

    private func text(for resourceHref: String) throws -> String {
        guard let unresolvedURL = URL(string: resourceHref, relativeTo: book.rootURL) else {
            throw ReadiumReaderError.noReadableText
        }

        var components = URLComponents(url: unresolvedURL.absoluteURL, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        let resourceURL = (components?.url ?? unresolvedURL.absoluteURL).standardizedFileURL
        let rootPath = book.rootURL.standardizedFileURL.path + "/"
        guard resourceURL.path.hasPrefix(rootPath) else { throw ReadiumReaderError.noReadableText }
        return try EPUBPlainTextExtractor.extract(from: resourceURL)
    }

    private static func flatten(_ links: [ReadiumShared.Link], depth: Int = 0) -> [ReadiumTableOfContentsEntry] {
        links.enumerated().flatMap { index, link in
            let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = ReadiumTableOfContentsEntry(
                id: "\(depth)-\(index)-\(link.href)",
                title: (title?.isEmpty == false) ? title! : "Sección",
                depth: depth,
                link: link
            )
            return [entry] + flatten(link.children, depth: depth + 1)
        }
    }
}

/// Readium's progression is based on the rendered publication, while the TTS
/// input is plain text. Starting at the next sentence boundary keeps speech
/// natural even when those two progressions differ slightly.
private enum EPUBReadingStart {
    static func `in`(_ text: String, near progression: Double?) -> (text: String, progression: Double) {
        guard let progression, progression > 0, !text.isEmpty else { return (text, 0) }

        let clampedProgression = min(max(progression, 0), 1)
        let offset = Int((Double(text.count) * clampedProgression).rounded(.down))
        let target = text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex) ?? text.endIndex
        var start = text.endIndex

        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { _, range, _, stop in
            guard range.upperBound >= target else { return }
            start = range.lowerBound
            stop = true
        }

        guard start < text.endIndex else { return (text, 0) }
        let actualOffset = text.distance(from: text.startIndex, to: start)
        let actualProgression = Double(actualOffset) / Double(max(text.count, 1))
        return (String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines), actualProgression)
    }
}

private enum ReadiumPublicationArchive {
    static func packageURL(for extractedEPUBRoot: URL) async throws -> URL {
        let fileManager = FileManager.default
        let packageURL = extractedEPUBRoot
            .deletingLastPathComponent()
            .appendingPathComponent("ReadiumPublication.epub", isDirectory: false)

        if fileManager.fileExists(atPath: packageURL.path) {
            return packageURL
        }

        try await fileManager.zipItem(
            at: extractedEPUBRoot,
            to: packageURL,
            shouldKeepParent: false,
            compressionMethod: .none
        )
        return packageURL
    }
}

private enum ReadiumReaderError: LocalizedError {
    case invalidLocalURL
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .invalidLocalURL:
            "No se pudo preparar una URL local válida para el EPUB."
        case .noReadableText:
            "La sección visible no contiene texto legible para sintetizar."
        }
    }
}
