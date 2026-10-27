import AVFoundation
import CoreML
import Foundation

/// Ejecutor local de los cuatro grafos Core ML publicados para Supertonic 3.
/// El actor serializa la inferencia para contener el uso de memoria local.
actor SupertonicCoreMLEngine: TTSEngine {
    private struct VoiceStyle {
        let ttl: [Float] // [1, 50, 256]
        let dp: [Float]  // [1, 8, 16]
    }

    private struct Graphs {
        let durationPredictor: MLModel
        let textEncoder: MLModel
        let vectorEstimator: MLModel
        let vocoder: MLModel
    }

    let capabilities = TTSCapabilities(
        supportedLanguages: ["es", "en"],
        supportsWordTiming: false,
        runsLocally: true
    )

    private let manifest: ModelManifest
    private let locator: ModelAssetLocator
    private var graphs: Graphs?
    private var tokenizer: SupertonicTokenizer?
    private var voices: [String: VoiceStyle] = [:]
    private var cancelledRequests = Set<UUID>()

    private let sampleRate: Double = 44_100
    private let textLength = 128
    private let latentChannels = 144
    private let latentMinLength = 17
    private let maxLatentLength = 512
    private let samplesPerLatent = 3_072
    private let odeSteps = 8

    init(manifest: ModelManifest, locator: ModelAssetLocator = ModelAssetLocator()) {
        self.manifest = manifest
        self.locator = locator
    }

    func prepare() async throws {
        if graphs != nil { return }
        let missing = locator.missingRequiredAssets(for: manifest)
        guard missing.isEmpty else { throw TTSError.modelAssetsMissing(missing) }
        guard let indexerURL = locator.resourceURL(named: "unicode_indexer", extension: "json"),
              let stylesURL = locator.directoryURL(named: "voice_styles")
        else {
            throw TTSError.modelAssetsMissing(["unicode_indexer.json", "voice_styles/"])
        }

        let configuration = MLModelConfiguration()
        // VectorEstimator FP16 is intended for the Apple Neural Engine. On
        // recent iPadOS releases `.all` can route part of this graph through
        // Metal/MPS, where the model aborts on a dynamic-shape assertion.
        // Keeping GPU out of the plan preserves local execution while using
        // the CPU only for operations unsupported by ANE.
        configuration.computeUnits = .cpuAndNeuralEngine
        func load(_ name: String) throws -> MLModel {
            guard let url = locator.compiledModelURL(named: name) else {
                throw TTSError.modelAssetsMissing(["\(name).mlmodelc"])
            }
            do {
                return try MLModel(contentsOf: url, configuration: configuration)
            } catch {
                throw TTSError.modelLoadFailed("\(name): \(error.localizedDescription)")
            }
        }

        tokenizer = try SupertonicTokenizer.load(from: indexerURL)
        voices = try Self.loadVoices(from: stylesURL)
        guard !voices.isEmpty else { throw TTSError.modelLoadFailed("No se encontró una voz con formas válidas.") }
        graphs = try Graphs(
            durationPredictor: load("DurationPredictor"),
            textEncoder: load("TextEncoder"),
            vectorEstimator: load("VectorEstimator"),
            vocoder: load("Vocoder")
        )
    }

    func loadedModelNames() -> [String] {
        graphs == nil ? [] : manifest.assets.filter(\.required).map(\.name).sorted()
    }

    func synthesize(_ request: TTSRequest) async throws -> SynthesizedAudio {
        try await prepare()
        guard capabilities.supportedLanguages.contains(request.language) else {
            throw TTSError.integrationPending("El idioma \(request.language) aún no está validado en esta aplicación.")
        }
        guard let tokenizer, let graphs, let voice = voices[request.voiceID] ?? voices["F1"] else {
            throw TTSError.modelLoadFailed("El motor no tiene tokenizador, grafos o voz disponibles.")
        }

        let chunks = try tokenizer.chunks(for: request.text, language: request.language, length: textLength)
        var pcm: [Float] = []
        for (index, chunk) in chunks.enumerated() {
            try checkCancellation(request.id)
            pcm += try synthesizeChunk(
                chunk.text,
                language: request.language,
                voice: voice,
                tokenizer: tokenizer,
                graphs: graphs,
                requestID: request.id,
                appendingTerminalPunctuation: chunk.completesSentence
            )
            if index < chunks.count - 1, chunk.completesSentence {
                pcm += [Float](repeating: 0, count: Int(sampleRate * pauseAfter(chunk)))
            }
        }
        try checkCancellation(request.id)
        let url = try Self.writePCM(pcm, sampleRate: sampleRate, requestID: request.id)
        return SynthesizedAudio(
            fileURL: url,
            duration: Double(pcm.count) / sampleRate,
            format: AudioFormatDescriptor(sampleRate: sampleRate, channels: 1, isInterleaved: false)
        )
    }

    func cancel(requestID: UUID) async {
        cancelledRequests.insert(requestID)
    }

    private func synthesizeChunk(
        _ text: String,
        language: String,
        voice: VoiceStyle,
        tokenizer: SupertonicTokenizer,
        graphs: Graphs,
        requestID: UUID,
        appendingTerminalPunctuation: Bool
    ) throws -> [Float] {
        let tokens = try tokenizer.process(
            text,
            language: language,
            length: textLength,
            appendingTerminalPunctuation: appendingTerminalPunctuation
        )
        let textIDs = try int32Array(tokens.ids, shape: [1, textLength])
        let textMask = try floatArray(tokens.mask, shape: [1, 1, textLength])
        let styleTTL = try floatArray(voice.ttl, shape: [1, 50, 256])
        let styleDP = try floatArray(voice.dp, shape: [1, 8, 16])

        let duration = try predict(graphs.durationPredictor, inputs: [
            "text_ids": textIDs, "style_dp": styleDP, "text_mask": textMask
        ], output: "duration").firstFloat
        guard duration.isFinite, duration > 0 else { return [] }

        let targetSamples = Int(Double(duration) * sampleRate)
        let trueLength = (targetSamples + samplesPerLatent - 1) / samplesPerLatent
        guard trueLength <= maxLatentLength else {
            throw TTSError.integrationPending("El fragmento superó el límite latente del exportador; debe segmentarse más.")
        }
        let latentLength = max(trueLength, latentMinLength)
        let filledLength = min(max(trueLength, 1), latentLength)
        var latentMask = [Float](repeating: 0, count: latentLength)
        for index in 0..<filledLength { latentMask[index] = 1 }

        let textEmbedding = try predict(graphs.textEncoder, inputs: [
            "text_ids": textIDs, "style_ttl": styleTTL, "text_mask": textMask
        ], output: "text_emb")
        let latentMaskArray = try floatArray(latentMask, shape: [1, 1, latentLength])
        let totalSteps = try floatArray([Float(odeSteps)], shape: [1])
        var rng = GaussianRNG(seed: UInt64.random(in: 1...UInt64.max))
        var latent = [Float](repeating: 0, count: latentChannels * latentLength)
        for channel in 0..<latentChannels {
            for frame in 0..<latentLength {
                latent[channel * latentLength + frame] = rng.nextGaussian() * latentMask[frame]
            }
        }

        for step in 0..<odeSteps {
            try checkCancellation(requestID)
            let noisyLatent = try floatArray(latent, shape: [1, latentChannels, latentLength])
            let currentStep = try floatArray([Float(step)], shape: [1])
            latent = try predict(graphs.vectorEstimator, inputs: [
                "noisy_latent": noisyLatent,
                "text_emb": textEmbedding,
                "style_ttl": styleTTL,
                "latent_mask": latentMaskArray,
                "text_mask": textMask,
                "current_step": currentStep,
                "total_step": totalSteps
            ], output: "denoised_latent").floats
        }

        let audio = try predict(graphs.vocoder, inputs: [
            "latent": try floatArray(latent, shape: [1, latentChannels, latentLength])
        ], output: "wav").floats
        return Array(audio.prefix(min(targetSamples, samplesPerLatent * filledLength)))
    }

    private func checkCancellation(_ requestID: UUID) throws {
        if cancelledRequests.remove(requestID) != nil { throw TTSError.cancelled }
    }

    private func pauseAfter(_ chunk: SupertonicTokenizer.Chunk) -> Double {
        // Solo una oración terminada recibe silencio adicional. Las divisiones
        // técnicas del límite de 128 tokens se concatenan sin pausa, para no
        // simular un punto antes de que la oración haya concluido.
        chunk.completesSentence ? 0.22 : 0
    }

    private func predict(_ model: MLModel, inputs: [String: MLMultiArray], output: String) throws -> MLMultiArray {
        let provider = try MLDictionaryFeatureProvider(dictionary: inputs.mapValues { MLFeatureValue(multiArray: $0) })
        let result = try model.prediction(from: provider)
        guard let array = result.featureValue(for: output)?.multiArrayValue else {
            throw TTSError.modelLoadFailed("El modelo no produjo la salida \(output).")
        }
        return array
    }

    private func floatArray(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
        let result = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        guard result.count == values.count else { throw TTSError.modelLoadFailed("Forma Float32 inesperada.") }
        values.withUnsafeBufferPointer { source in
            result.dataPointer.copyMemory(from: source.baseAddress!, byteCount: values.count * MemoryLayout<Float>.size)
        }
        return result
    }

    private func int32Array(_ values: [Int32], shape: [Int]) throws -> MLMultiArray {
        let result = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .int32)
        guard result.count == values.count else { throw TTSError.modelLoadFailed("Forma Int32 inesperada.") }
        values.withUnsafeBufferPointer { source in
            result.dataPointer.copyMemory(from: source.baseAddress!, byteCount: values.count * MemoryLayout<Int32>.size)
        }
        return result
    }

    private static func loadVoices(from directory: URL) throws -> [String: VoiceStyle] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var result: [String: VoiceStyle] = [:]
        for file in files where file.pathExtension == "json" {
            guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
                  let ttl = flatten(object["style_ttl"]), let dp = flatten(object["style_dp"]),
                  ttl.count == 50 * 256, dp.count == 8 * 16
            else { continue }
            result[file.deletingPathExtension().lastPathComponent] = VoiceStyle(ttl: ttl, dp: dp)
        }
        return result
    }

    private static func flatten(_ value: Any?) -> [Float]? {
        if let number = value as? NSNumber { return [number.floatValue] }
        if let array = value as? [Any] {
            return array.reduce(into: []) { partial, element in
                partial += flatten(element) ?? []
            }
        }
        if let dictionary = value as? [String: Any] { return flatten(dictionary["data"]) }
        return nil
    }

    private static func writePCM(_ samples: [Float], sampleRate: Double, requestID: UUID) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("supertonic-\(requestID.uuidString)")
            .appendingPathExtension("caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
        }
        try audioFile.write(from: buffer)
        return url
    }
}

private extension MLMultiArray {
    var floats: [Float] {
        let pointer = dataPointer.bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    var firstFloat: Float { floats.first ?? 0 }
}

private struct GaussianRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextGaussian() -> Float {
        let u1 = nextUniform()
        let u2 = nextUniform()
        return sqrtf(-2 * logf(u1)) * cosf(2 * .pi * u2)
    }

    private mutating func nextUniform() -> Float {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Float((z >> 40) + 1) / Float(1 << 24)
    }
}
