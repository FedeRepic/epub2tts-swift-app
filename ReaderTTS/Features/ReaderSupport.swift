import Foundation
import SwiftUI

enum ReaderFont: String, CaseIterable, Identifiable {
    case system
    case serif
    case rounded
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Sistema"
        case .serif: "Serif"
        case .rounded: "Redondeada"
        case .monospaced: "Monoespaciada"
        }
    }

    var swiftUIDesign: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }

    /// Compensa las métricas visuales de las familias para que un mismo valor
    /// del control de tamaño conserve una densidad de lectura parecida.
    /// No modifica los márgenes configurados por la persona lectora.
    var readingScale: Double {
        switch self {
        case .system: 1.00
        case .serif: 0.98
        case .rounded: 0.96
        case .monospaced: 0.88
        }
    }
}

private enum ReaderHighlightColor: String, CaseIterable, Identifiable {
    case yellow
    case orange
    case mint
    case blue
    case pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yellow: "Amarillo"
        case .orange: "Naranja"
        case .mint: "Menta"
        case .blue: "Azul"
        case .pink: "Rosa"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .yellow: .yellow
        case .orange: .orange
        case .mint: .mint
        case .blue: .cyan
        case .pink: .pink
        }
    }
}

/// Controles globales compartidos por el lector Readium.
struct ReaderAppearanceSettings: View {
    @Binding var fontScale: Double
    @Binding var fontFamily: String
    @Binding var lineHeight: Double
    @Binding var letterSpacing: Double
    @Binding var horizontalMargin: Double
    @Binding var highlightColor: String
    @Binding var speechRate: Double
    @Binding var voiceID: String
    @Binding var languageMode: String
    @Binding var initialPrefetchCount: Int
    let isPlaybackActive: Bool

    @Environment(\.dismiss) private var dismiss

    private var selectedFont: ReaderFont {
        ReaderFont(rawValue: fontFamily) ?? .system
    }

    private var selectedHighlightColor: ReaderHighlightColor {
        ReaderHighlightColor(rawValue: highlightColor) ?? .yellow
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fuente") {
                    Picker("Familia", selection: $fontFamily) {
                        ForEach(ReaderFont.allCases) { font in
                            Text(font.title).tag(font.rawValue)
                        }
                    }

                    Text("Vista previa de lectura")
                        .font(.system(size: 21 * fontScale * selectedFont.readingScale, design: selectedFont.swiftUIDesign))
                        .lineLimit(1)
                }

                Section("Texto") {
                    HStack {
                        Text("Tamaño")
                        Spacer()
                        Text("\(Int((fontScale * 18).rounded())) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $fontScale, in: 0.8...1.6, step: 0.1)
                        .accessibilityLabel("Tamaño de texto")
                    HStack {
                        Text("A").font(.caption)
                        Spacer()
                        Text("A").font(.title2)
                    }
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("Interlineado")
                        Spacer()
                        Text(String(format: "%.2f", lineHeight))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $lineHeight, in: 1.2...2.0, step: 0.05)
                        .accessibilityLabel("Espaciado entre líneas")

                    HStack {
                        Text("Espacio entre letras")
                        Spacer()
                        Text(String(format: "%.1f pt", letterSpacing))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $letterSpacing, in: 0...2.0, step: 0.1)
                        .accessibilityLabel("Espacio entre letras")
                }

                Section("Página") {
                    HStack {
                        Text("Márgenes")
                        Spacer()
                        Text(String(format: "%.1f", horizontalMargin))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $horizontalMargin, in: 0.5...2.0, step: 0.25)
                        .accessibilityLabel("Márgenes horizontales")
                    Text("El modo claro u oscuro sigue la apariencia del sistema.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Seguimiento de voz") {
                    Picker("Color de resaltado", selection: $highlightColor) {
                        ForEach(ReaderHighlightColor.allCases) { color in
                            Text(color.title).tag(color.rawValue)
                        }
                    }
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedHighlightColor.swiftUIColor)
                            .frame(width: 30, height: 18)
                        Text("El fragmento en reproducción se resalta en este color.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Voz local") {
                    Picker("Voz", selection: $voiceID) {
                        ForEach(SupertonicVoice.allCases) { voice in
                            Text(voice.title).tag(voice.rawValue)
                        }
                    }

                    Picker("Idioma de síntesis", selection: $languageMode) {
                        ForEach(TTSSynthesisLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }

                    Picker("Velocidad", selection: $speechRate) {
                        Text("0,9×").tag(0.9)
                        Text("1,0×").tag(1.0)
                        Text("1,1×").tag(1.1)
                        Text("1,2×").tag(1.2)
                        Text("1,3×").tag(1.3)
                    }

                    Picker("Precarga de audio", selection: $initialPrefetchCount) {
                        Text("1 fragmento").tag(1)
                        Text("2 fragmentos").tag(2)
                        Text("3 fragmentos").tag(3)
                        Text("4 fragmentos").tag(4)
                        Text("5 fragmentos").tag(5)
                    }

                    Text("Define cuántos fragmentos se preparan al comenzar y se mantienen por delante durante la escucha. Más precarga reduce pausas, pero demora más el inicio y usa más memoria.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LabeledContent("Calidad") {
                        Text("Verificada · 8 pasos")
                            .foregroundStyle(.secondary)
                    }
                    Text("La calidad se mantiene en la configuración validada del modelo para preservar estabilidad y consumo predecible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .disabled(isPlaybackActive)

                if isPlaybackActive {
                    Text("Detén la reproducción para cambiar la voz o la precarga. La velocidad se puede cambiar al iniciar la siguiente escucha.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Restablecer apariencia") {
                        fontScale = 1.0
                        fontFamily = ReaderFont.system.rawValue
                        lineHeight = 1.55
                        letterSpacing = 0
                        horizontalMargin = 1.0
                        highlightColor = ReaderHighlightColor.yellow.rawValue
                    }

                    Button("Restablecer voz") {
                        speechRate = 1.1
                        voiceID = SupertonicVoice.f1.rawValue
                        languageMode = TTSSynthesisLanguage.spanish.rawValue
                        initialPrefetchCount = 3
                    }
                    .disabled(isPlaybackActive)
                }
            }
            .navigationTitle("Configuración del lector")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if TTSSynthesisLanguage(rawValue: languageMode) == nil {
                    languageMode = TTSSynthesisLanguage.spanish.rawValue
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

@MainActor
final class ReaderPlaybackViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case preloading(ready: Int, target: Int)
        case synthesizing(current: Int, total: Int)
        case playing(current: Int, total: Int, duration: TimeInterval)
        case paused(current: Int, total: Int, remaining: TimeInterval)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var activeSegment: String?
    @Published private(set) var activeSegmentProgression: Double?
    @Published private(set) var sleepTimerEndDate: Date?

    private struct PreparedContinuation {
        let id: UUID
        let text: String
        let audio: SynthesizedAudio
    }

    private let audioPlayer = AudioPlaybackController(enablesSystemControls: true)
    private var engine: SupertonicCoreMLEngine?
    private var sessionID: UUID?
    private var segments: [EPUBSpeechChunker.Segment] = []
    private var audioCache: [Int: SynthesizedAudio] = [:]
    private var requestsInFlight = Set<Int>()
    private var inFlightRequestIDs: [Int: UUID] = [:]
    private var currentSegmentIndex = 0
    private var language = "es"
    private var nowPlayingBookTitle = ""
    private var nowPlayingChapterTitle = ""
    private var isPerformingInitialPrefetch = false
    private var initialPrefetchTarget = 0
    private var playbackCompletionTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?
    private var textFinishedHandler: (() -> Void)?
    private var textWillFinishHandler: (() -> Void)?
    private var continuationPrefetchTask: Task<Void, Never>?
    private var preparedContinuation: PreparedContinuation?
    private var speechRate: Float = 1.1
    private var voiceID = SupertonicVoice.f1.rawValue
    private var languageMode = TTSSynthesisLanguage.spanish
    private var initialPrefetchCount = 3
    private var sourceProgression = 0.0

    init() {
        audioPlayer.onRemotePlay = { [weak self] in self?.resumeFromSystemControl() }
        audioPlayer.onRemotePause = { [weak self] in self?.pauseFromSystemControl() }
    }

    var buttonTitle: String {
        switch state {
        case .idle, .failed: "Escuchar"
        case .preloading, .synthesizing: "Detener"
        case .playing: "Pausar"
        case .paused: "Reanudar"
        }
    }

    var buttonSymbol: String {
        switch state {
        case .idle, .failed: "play.fill"
        case .preloading, .synthesizing: "stop.fill"
        case .playing: "pause.fill"
        case .paused: "play.fill"
        }
    }

    var message: String? {
        switch state {
        case .idle: nil
        case .preloading(let ready, let target): "Preparando audio local para una escucha fluida… \(ready) de \(target) fragmentos"
        case .synthesizing(let current, let total): "Sintetizando fragmento \(current) de \(total) localmente…"
        case .playing(let current, let total, let duration): String(format: "Reproduciendo fragmento %d de %d · %.1f s · %.1f×", current, total, duration, speechRate)
        case .paused(let current, let total, _): "Pausa · fragmento \(current) de \(total)"
        case .failed(let message): message
        }
    }

    var hasError: Bool {
        if case .failed = state { return true }
        return false
    }

    var statusSymbol: String {
        switch state {
        case .preloading: "arrow.down.circle.fill"
        case .synthesizing: "waveform"
        case .playing: "speaker.wave.2.fill"
        case .paused: "pause.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .idle: "play.fill"
        }
    }

    var preloadProgress: Double? {
        guard case .preloading(let ready, let target) = state, target > 0 else { return nil }
        return Double(ready) / Double(target)
    }

    var canStop: Bool {
        switch state {
        case .idle, .failed: false
        case .preloading, .synthesizing, .playing, .paused: true
        }
    }

    var sleepTimerDescription: String? {
        guard let sleepTimerEndDate else { return nil }
        let secondsRemaining = max(0, sleepTimerEndDate.timeIntervalSinceNow)
        let minutesRemaining = max(1, Int((secondsRemaining / 60).rounded(.up)))
        return "Se detendrá en aproximadamente \(minutesRemaining) min"
    }

    func setSpeechRate(_ value: Double) {
        guard !canStop else { return }
        speechRate = Float(min(max(value, 0.8), 1.6))
    }

    func setVoiceID(_ value: String) {
        guard !canStop, let voice = SupertonicVoice(rawValue: value) else { return }
        voiceID = voice.rawValue
    }

    func setLanguageMode(_ value: String) {
        guard !canStop else { return }
        languageMode = TTSSynthesisLanguage(rawValue: value) ?? .spanish
    }

    func setInitialPrefetchCount(_ value: Int) {
        guard !canStop else { return }
        initialPrefetchCount = min(max(value, 1), 5)
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndDate = nil

        guard let minutes, minutes > 0 else { return }
        let duration = TimeInterval(minutes * 60)
        sleepTimerEndDate = Date.now.addingTimeInterval(duration)
        sleepTimerTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func setTextFinishedHandler(_ handler: @escaping () -> Void) {
        textFinishedHandler = handler
    }

    func clearTextFinishedHandler() {
        textFinishedHandler = nil
    }

    func setTextWillFinishHandler(_ handler: @escaping () -> Void) {
        textWillFinishHandler = handler
    }

    func clearTextWillFinishHandler() {
        textWillFinishHandler = nil
    }

    /// Synthesizes only the first sentence group of the next chapter while
    /// the final group of the current chapter is still playing.
    func prefetchContinuation(text: String) {
        guard preparedContinuation?.text != text else { return }
        continuationPrefetchTask?.cancel()
        preparedContinuation = nil

        guard let firstSegment = EPUBSpeechChunker.segments(from: text).first
        else { return }

        let id = UUID()
        let request = TTSRequest(text: firstSegment.spokenText, language: language, voiceID: voiceID)
        continuationPrefetchTask = Task { [weak self] in
            do {
                guard let self else { return }
                let engine = try await self.loadEngine()
                let audio = try await engine.synthesize(request)
                guard !Task.isCancelled else { return }
                guard self.preparedContinuation?.id == nil else { return }
                self.preparedContinuation = PreparedContinuation(id: id, text: text, audio: audio)
            } catch {
                // The normal start path will synthesize the chapter if this
                // best-effort prefetch cannot complete.
            }
        }
    }

    func toggle(
        text: String,
        bookTitle: String,
        chapterTitle: String,
        sourceProgression: Double? = nil,
        initialPrefetchCount: Int? = nil
    ) {
        switch state {
        case .idle, .failed:
            start(
                text: text,
                bookTitle: bookTitle,
                chapterTitle: chapterTitle,
                sourceProgression: sourceProgression,
                initialPrefetchCount: initialPrefetchCount
            )
        case .preloading, .synthesizing: stop()
        case .playing: pause()
        case .paused: resume()
        }
    }

    func stop() {
        resetPlayback(keepingSleepTimer: false)
    }

    private func resetPlayback(keepingSleepTimer: Bool) {
        let cancellingIDs = Array(inFlightRequestIDs.values)
        sessionID = nil
        segments.removeAll()
        audioCache.removeAll()
        requestsInFlight.removeAll()
        inFlightRequestIDs.removeAll()
        currentSegmentIndex = 0
        isPerformingInitialPrefetch = false
        initialPrefetchTarget = 0
        playbackCompletionTask?.cancel()
        playbackCompletionTask = nil
        if !keepingSleepTimer {
            sleepTimerTask?.cancel()
            sleepTimerTask = nil
            sleepTimerEndDate = nil
            continuationPrefetchTask?.cancel()
            continuationPrefetchTask = nil
            preparedContinuation = nil
        }
        audioPlayer.stop()
        audioPlayer.clearNowPlaying()
        activeSegment = nil
        activeSegmentProgression = nil
        state = .idle
        if let engine {
            Task {
                for requestID in cancellingIDs {
                    await engine.cancel(requestID: requestID)
                }
            }
        }
    }

    private func start(
        text: String,
        bookTitle: String,
        chapterTitle: String,
        sourceProgression: Double?,
        initialPrefetchCount: Int?
    ) {
        activeSegment = nil
        activeSegmentProgression = nil
        let newSegments = EPUBSpeechChunker.segments(from: text)
        guard !newSegments.isEmpty else {
            state = .failed("No hay texto disponible para sintetizar.")
            return
        }

        let prefetchedAudio = takePreparedContinuation(matching: text)
        let newSession = UUID()
        sessionID = newSession
        language = languageMode.engineLanguage
        nowPlayingBookTitle = bookTitle
        nowPlayingChapterTitle = chapterTitle
        segments = newSegments
        audioCache.removeAll()
        requestsInFlight.removeAll()
        inFlightRequestIDs.removeAll()
        currentSegmentIndex = 0
        self.sourceProgression = min(max(sourceProgression ?? 0, 0), 1)
        initialPrefetchTarget = min(max(initialPrefetchCount ?? self.initialPrefetchCount, 1), segments.count)
        isPerformingInitialPrefetch = true
        state = .preloading(ready: 0, target: initialPrefetchTarget)
        if let prefetchedAudio {
            audioCache[0] = prefetchedAudio
            updateInitialPrefetch(session: newSession)
        } else {
            for index in 0..<initialPrefetchTarget {
                requestAudio(for: index, session: newSession)
            }
        }
    }

    private func requestAudio(for index: Int, session: UUID) {
        guard segments.indices.contains(index), audioCache[index] == nil, !requestsInFlight.contains(index) else { return }
        requestsInFlight.insert(index)
        if index == currentSegmentIndex && !isPerformingInitialPrefetch {
            state = .synthesizing(current: index + 1, total: segments.count)
        }
        let request = TTSRequest(text: segments[index].spokenText, language: language, voiceID: voiceID)
        inFlightRequestIDs[index] = request.id

        Task {
            do {
                let engine = try await loadEngine()
                let audio = try await engine.synthesize(request)
                guard sessionID == session else { return }
                requestsInFlight.remove(index)
                inFlightRequestIDs[index] = nil
                audioCache[index] = audio
                if self.isPerformingInitialPrefetch {
                    self.updateInitialPrefetch(session: session)
                } else if index == currentSegmentIndex {
                    playCachedSegment(at: index, session: session)
                }
            } catch {
                guard sessionID == session else { return }
                requestsInFlight.remove(index)
                inFlightRequestIDs[index] = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func playCachedSegment(at index: Int, session: UUID) {
        guard sessionID == session, let audio = audioCache[index] else { return }
        do {
            let playbackDuration = try audioPlayer.play(fileURL: audio.fileURL, rate: speechRate)
            activeSegmentProgression = segmentProgression(at: index)
            activeSegment = segments[index].highlightedText
            audioPlayer.updateNowPlaying(
                bookTitle: nowPlayingBookTitle,
                chapterTitle: nowPlayingChapterTitle,
                isPlaying: true
            )
            state = .playing(current: index + 1, total: segments.count, duration: playbackDuration)
            requestAudio(for: index + initialPrefetchCount, session: session)
            if index == segments.count - 1 {
                textWillFinishHandler?()
            }
            scheduleAdvance(after: playbackDuration, index: index, session: session)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func advance(session: UUID) {
        guard sessionID == session else { return }
        let nextIndex = currentSegmentIndex + 1
        guard segments.indices.contains(nextIndex) else {
            if let textFinishedHandler {
                resetPlayback(keepingSleepTimer: true)
                textFinishedHandler()
            } else {
                stop()
            }
            return
        }
        currentSegmentIndex = nextIndex
        audioCache = audioCache.filter { $0.key >= nextIndex }
        if audioCache[nextIndex] != nil {
            playCachedSegment(at: nextIndex, session: session)
        } else {
            state = .synthesizing(current: nextIndex + 1, total: segments.count)
            requestAudio(for: nextIndex, session: session)
        }
    }

    private func pause() {
        guard case .playing(let current, let total, _) = state,
              let remaining = audioPlayer.pause()
        else { return }
        playbackCompletionTask?.cancel()
        playbackCompletionTask = nil
        audioPlayer.updateNowPlaying(bookTitle: nowPlayingBookTitle, chapterTitle: nowPlayingChapterTitle, isPlaying: false)
        state = .paused(current: current, total: total, remaining: remaining)
    }

    private func resume() {
        guard case .paused(let current, let total, _) = state else { return }
        do {
            let remaining = try audioPlayer.resume()
            audioPlayer.updateNowPlaying(bookTitle: nowPlayingBookTitle, chapterTitle: nowPlayingChapterTitle, isPlaying: true)
            state = .playing(current: current, total: total, duration: remaining)
            scheduleAdvance(after: remaining, index: currentSegmentIndex, session: sessionID)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func scheduleAdvance(after duration: TimeInterval, index: Int, session: UUID?) {
        guard let session else { return }
        playbackCompletionTask?.cancel()
        playbackCompletionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard let self, self.sessionID == session, self.currentSegmentIndex == index else { return }
            self.advance(session: session)
        }
    }

    private func pauseFromSystemControl() {
        guard case .playing = state else { return }
        pause()
    }

    private func resumeFromSystemControl() {
        guard case .paused = state else { return }
        resume()
    }

    private func updateInitialPrefetch(session: UUID) {
        guard sessionID == session, isPerformingInitialPrefetch else { return }
        let ready = (0..<initialPrefetchTarget).reduce(into: 0) { count, index in
            if audioCache[index] != nil { count += 1 }
        }
        guard ready == initialPrefetchTarget else {
            state = .preloading(ready: ready, target: initialPrefetchTarget)
            return
        }
        isPerformingInitialPrefetch = false
        for index in 1...initialPrefetchCount {
            requestAudio(for: index, session: session)
        }
        playCachedSegment(at: 0, session: session)
    }

    private func segmentProgression(at index: Int) -> Double {
        let totalCharacters = max(segments.reduce(0) { $0 + $1.highlightedText.count }, 1)
        let charactersBeforeSegment = segments.prefix(index).reduce(0) { $0 + $1.highlightedText.count }
        let playbackProgression = Double(charactersBeforeSegment) / Double(totalCharacters)
        return min(sourceProgression + ((1 - sourceProgression) * playbackProgression), 1)
    }

    private func takePreparedContinuation(matching text: String) -> SynthesizedAudio? {
        guard let preparedContinuation, preparedContinuation.text == text else { return nil }
        continuationPrefetchTask?.cancel()
        continuationPrefetchTask = nil
        self.preparedContinuation = nil
        return preparedContinuation.audio
    }

    private func loadEngine() async throws -> SupertonicCoreMLEngine {
        if let engine { return engine }
        let manifest = try ModelManifest.load()
        let newEngine = SupertonicCoreMLEngine(manifest: manifest)
        try await newEngine.prepare()
        engine = newEngine
        return newEngine
    }
}

private enum EPUBSpeechChunker {
    struct Segment: Sendable {
        /// El texto se mantiene sin puntuación añadida para que Readium pueda
        /// encontrarlo y resaltarlo exactamente como aparece en el EPUB.
        let highlightedText: String
        /// Los encabezados sin punto reciben una puntuación solo para el motor,
        /// de modo que la voz cierre el título antes del texto del capítulo.
        let spokenText: String
    }

    /// Supertonic admite 128 tokens por inferencia. Esta cifra deja margen para
    /// las etiquetas de idioma del tokenizador y, cuando caben, permite agrupar
    /// dos oraciones completas. Nunca se divide una oración aquí por longitud.
    static func segments(
        from text: String,
        maximumCharacters: Int = 112,
        maximumSentencesPerSegment: Int = 2
    ) -> [Segment] {
        let blocks = text
            .components(separatedBy: "\n\n")
            .map { normalize($0) }
            .filter { !$0.isEmpty }

        return blocks.flatMap {
            segments(in: $0,
                     maximumCharacters: maximumCharacters,
                     maximumSentencesPerSegment: maximumSentencesPerSegment)
        }
    }

    private static func segments(
        in block: String,
        maximumCharacters: Int,
        maximumSentencesPerSegment: Int
    ) -> [Segment] {
        let sentences = sentences(in: block)

        // Un título EPUB suele llegar como un bloque breve sin puntuación final.
        // Al conservar cada bloque por separado, también evitamos que un título
        // válido se una accidentalmente al primer párrafo.
        guard !sentences.isEmpty else {
            return [segment(for: block, isHeading: isLikelyHeading(block))]
        }

        var result: [Segment] = []
        var current: [String] = []

        func appendCurrent() {
            guard !current.isEmpty else { return }
            let text = current.joined(separator: " ")
            result.append(segment(for: text, isHeading: false))
            current.removeAll(keepingCapacity: true)
        }

        for sentence in sentences {
            let candidate = (current + [sentence]).joined(separator: " ")
            if !current.isEmpty,
               (current.count >= maximumSentencesPerSegment || candidate.count > maximumCharacters) {
                appendCurrent()
            }

            // Una oración larga se entrega completa al motor. Si supera el
            // límite físico de su tokenizador, este hará una continuación sin
            // insertar silencio ni convertirla en una oración terminada.
            if sentence.count > maximumCharacters {
                result.append(segment(for: sentence, isHeading: false))
            } else {
                current.append(sentence)
            }
        }
        appendCurrent()
        return result
    }

    private static func sentences(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            let normalized = normalize(sentence)
            if !normalized.isEmpty { result.append(normalized) }
        }
        return result
    }

    private static func segment(for text: String, isHeading: Bool) -> Segment {
        let highlightedText = normalize(text)
        let spokenText: String
        if isHeading && !endsSentence(highlightedText) {
            spokenText = highlightedText + "."
        } else {
            spokenText = highlightedText
        }
        return Segment(highlightedText: highlightedText, spokenText: spokenText)
    }

    private static func isLikelyHeading(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        return text.count <= 120 && words.count <= 14 && !endsSentence(text)
    }

    private static func endsSentence(_ text: String) -> Bool {
        let punctuation = CharacterSet(charactersIn: ".!?…")
        let closingCharacters = CharacterSet(charactersIn: "\"'”»)]}")
        let final = text.unicodeScalars.reversed().first { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) && !closingCharacters.contains(scalar)
        }
        return final.map { punctuation.contains($0) } ?? false
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum EPUBPlainTextExtractor {
    static func extract(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let source = try decode(data)
        let withoutNonTextElements = source
            .replacingOccurrences(of: "(?is)<(script|style|head)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        let withParagraphs = withoutNonTextElements
            .replacingOccurrences(of: "(?i)</?(p|div|h[1-6]|li|blockquote|br|tr|section|article)[^>]*>", with: "\n", options: .regularExpression)
        let withoutTags = withParagraphs
            .replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)
        let plainText = decodeEntities(in: withoutTags)
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n[ \\n]+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else { throw EPUBTextExtractionError.emptyChapter }
        return plainText
    }

    private static func decode(_ data: Data) throws -> String {
        if let string = String(data: data, encoding: .utf8) { return string }
        if let string = String(data: data, encoding: .utf16) { return string }
        if let string = String(data: data, encoding: .windowsCP1252) { return string }
        if let string = String(data: data, encoding: .isoLatin1) { return string }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    private static func decodeEntities(in text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

enum EPUBTextExtractionError: LocalizedError {
    case emptyChapter

    var errorDescription: String? {
        switch self {
        case .emptyChapter: "El capítulo no contiene texto legible."
        }
    }
}
