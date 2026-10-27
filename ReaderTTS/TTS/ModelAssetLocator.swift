import Foundation

struct ModelAssetLocator: Sendable {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func missingRequiredAssets(for manifest: ModelManifest) -> [String] {
        manifest.assets
            .filter(\.required)
            .map(\.name)
            .filter { compiledModelURL(named: $0) == nil }
    }

    func compiledModelURL(named name: String) -> URL? {
        bundle.url(forResource: name, withExtension: "mlmodelc")
            ?? bundle.url(forResource: name, withExtension: "mlmodelc", subdirectory: "CompiledModels")
    }

    func resourceURL(named name: String, extension fileExtension: String) -> URL? {
        bundle.url(forResource: name, withExtension: fileExtension)
    }

    func directoryURL(named name: String) -> URL? {
        guard let root = bundle.resourceURL else { return nil }
        let url = root.appendingPathComponent(name, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
