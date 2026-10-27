import Foundation

/// Front-end local, sin G2P: normaliza Unicode, envuelve el idioma y consulta
/// `unicode_indexer.json`. La longitud de entrada de Supertonic está limitada a 128 tokens.
struct SupertonicTokenizer: Sendable {
    struct Tokens: Sendable {
        let ids: [Int32]
        let mask: [Float]
    }

    /// Un fragmento puede ser una continuación técnica de una oración larga.
    /// En ese caso no se añade un punto ficticio ni se debe dejar una pausa.
    struct Chunk: Sendable {
        let text: String
        let completesSentence: Bool
    }

    private static let supportedLanguages: Set<String> = [
        "en", "ko", "ja", "ar", "bg", "cs", "da", "de", "el", "es", "et", "fi",
        "fr", "hi", "hr", "hu", "id", "it", "lt", "lv", "nl", "pl", "pt", "ro",
        "ru", "sk", "sl", "sv", "tr", "uk", "vi", "na"
    ]
    private let indexer: [Int32]

    init(indexer: [Int32]) {
        self.indexer = indexer
    }

    static func load(from url: URL) throws -> SupertonicTokenizer {
        let indexer = try JSONDecoder().decode([Int32].self, from: Data(contentsOf: url))
        guard indexer.count >= 65_536 else {
            throw TTSError.modelLoadFailed("unicode_indexer.json no contiene la tabla Unicode esperada.")
        }
        return SupertonicTokenizer(indexer: indexer)
    }

    func process(
        _ text: String,
        language: String,
        length: Int = 128,
        appendingTerminalPunctuation: Bool = true
    ) throws -> Tokens {
        let normalized = try preprocess(
            text,
            language: language,
            appendingTerminalPunctuation: appendingTerminalPunctuation
        )
        var ids = [Int32](repeating: 0, count: length)
        var mask = [Float](repeating: 0, count: length)
        for (offset, scalar) in normalized.unicodeScalars.prefix(length).enumerated() {
            ids[offset] = scalar.value < indexer.count ? indexer[Int(scalar.value)] : -1
            mask[offset] = 1
        }
        return Tokens(ids: ids, mask: mask)
    }

    func chunks(for text: String, language: String, length: Int = 128) throws -> [Chunk] {
        guard Self.supportedLanguages.contains(language) else {
            throw TTSError.integrationPending("Idioma no compatible con Supertonic: \(language).")
        }
        let candidates = sentenceCandidates(in: text)
        var output: [Chunk] = []
        for candidate in candidates.isEmpty ? [text] : candidates {
            let pieces = try splitToFit(candidate, language: language, length: length)
            let completesSentence = endsSentence(candidate)
            output += pieces.enumerated().map { index, piece in
                Chunk(text: piece, completesSentence: completesSentence && index == pieces.indices.last)
            }
        }
        return output.isEmpty ? [Chunk(text: "", completesSentence: true)] : output
    }

    private func splitToFit(_ text: String, language: String, length: Int) throws -> [String] {
        if try preprocess(text, language: language).unicodeScalars.count <= length {
            return [text]
        }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > 1 else {
            let scalars = Array(text.unicodeScalars)
            guard scalars.count > 1 else { return [text] }
            let midpoint = scalars.count / 2
            return try splitToFit(String(String.UnicodeScalarView(scalars[..<midpoint])), language: language, length: length)
                + splitToFit(String(String.UnicodeScalarView(scalars[midpoint...])), language: language, length: length)
        }
        var fittingWordCount = 0
        for count in 1...words.count {
            let proposal = words.prefix(count).joined(separator: " ")
            if try preprocess(proposal, language: language).unicodeScalars.count <= length {
                fittingWordCount = count
            } else {
                break
            }
        }
        guard fittingWordCount > 0 else {
            return try splitToFit(words[0], language: language, length: length)
                + splitToFit(words.dropFirst().joined(separator: " "), language: language, length: length)
        }
        let preferredStart = max(1, fittingWordCount - 8)
        let preferredBreak = (preferredStart...fittingWordCount).reversed().first { index in
            guard let last = words[index - 1].last else { return false }
            return ",;:—–".contains(last)
        } ?? fittingWordCount
        return try splitToFit(words.prefix(preferredBreak).joined(separator: " "), language: language, length: length)
            + splitToFit(words.dropFirst(preferredBreak).joined(separator: " "), language: language, length: length)
    }

    private func sentenceCandidates(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
        }
        return result
    }

    private func endsSentence(_ text: String) -> Bool {
        let closingCharacters = CharacterSet(charactersIn: "\"'”»)]}")
        let final = text.unicodeScalars.reversed().first { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) && !closingCharacters.contains(scalar)
        }
        return final.map { ".!?…".unicodeScalars.contains($0) } ?? false
    }

    private func preprocess(
        _ text: String,
        language: String,
        appendingTerminalPunctuation: Bool = true
    ) throws -> String {
        guard Self.supportedLanguages.contains(language) else {
            throw TTSError.integrationPending("Idioma no compatible con Supertonic: \(language).")
        }
        var output = text.decomposedStringWithCompatibilityMapping
        output = output
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
        output = output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty { output = "." }
        if appendingTerminalPunctuation,
           let last = output.unicodeScalars.last,
           !".!?;:,'\")]}…".unicodeScalars.contains(last) {
            output.append(".")
        }
        return "<\(language)>\(output)</\(language)>"
    }
}
