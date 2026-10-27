import Foundation

struct ModelManifest: Decodable, Sendable {
    struct Asset: Decodable, Sendable, Identifiable {
        let name: String
        let sha256: String?
        let required: Bool

        var id: String { name }
    }

    let modelID: String
    let repository: URL
    let revision: String
    let license: String
    let minimumOS: String
    let declaredSizeMB: Int
    let downloadedSizeMB: Int
    let assets: [Asset]

    static func load(bundle: Bundle = .main) throws -> ModelManifest {
        guard let url = bundle.url(forResource: "ModelManifest", withExtension: "json") else {
            throw TTSError.modelLoadFailed("No se encontró ModelManifest.json en el bundle.")
        }
        return try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
    }
}
