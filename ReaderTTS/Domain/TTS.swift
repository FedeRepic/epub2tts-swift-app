import Foundation

/// Estilos de voz presentes en el paquete Supertonic distribuido con la app.
/// Los nombres son los identificadores originales de los archivos de estilo;
/// no prometen un género, acento o idioma concreto.
enum SupertonicVoice: String, CaseIterable, Identifiable, Sendable {
    case f1 = "F1"
    case f2 = "F2"
    case f3 = "F3"
    case f4 = "F4"
    case f5 = "F5"
    case m1 = "M1"
    case m2 = "M2"
    case m3 = "M3"
    case m4 = "M4"
    case m5 = "M5"

    var id: String { rawValue }
    var title: String { "Voz \(rawValue)" }
}

enum TTSSynthesisLanguage: String, CaseIterable, Identifiable, Sendable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spanish: "Español"
        case .english: "Inglés"
        }
    }

    var engineLanguage: String { rawValue }
}

struct TTSRequest: Sendable, Hashable {
    let id: UUID
    let text: String
    let language: String
    let voiceID: String

    init(id: UUID = UUID(), text: String, language: String = "es", voiceID: String = "F1") {
        self.id = id
        self.text = text
        self.language = language
        self.voiceID = voiceID
    }
}

struct AudioFormatDescriptor: Sendable, Hashable {
    let sampleRate: Double
    let channels: Int
    let isInterleaved: Bool
}

struct SynthesizedAudio: Sendable, Hashable {
    let fileURL: URL
    let duration: TimeInterval
    let format: AudioFormatDescriptor
}

struct TTSCapabilities: Sendable, Hashable {
    let supportedLanguages: Set<String>
    let supportsWordTiming: Bool
    let runsLocally: Bool
}

protocol TTSEngine: Sendable {
    var capabilities: TTSCapabilities { get }
    func prepare() async throws
    func synthesize(_ request: TTSRequest) async throws -> SynthesizedAudio
    func cancel(requestID: UUID) async
}

enum TTSError: LocalizedError, Sendable, Equatable {
    case modelAssetsMissing([String])
    case modelLoadFailed(String)
    case integrationPending(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelAssetsMissing(let names):
            return "Faltan los activos del modelo: \(names.joined(separator: ", "))."
        case .modelLoadFailed(let detail):
            return "No fue posible cargar Core ML: \(detail)"
        case .integrationPending(let detail):
            return "La canalización de síntesis aún no está lista: \(detail)"
        case .cancelled:
            return "La síntesis fue cancelada."
        }
    }
}
