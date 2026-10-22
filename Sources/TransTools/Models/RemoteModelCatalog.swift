import Foundation

/// Remote metadata cannot change tensor contracts or execute repository code.
/// New weights/adapters require a verified app release; catalog ordering and descriptions do not.
struct RemoteModelCatalog: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let id: String
        let engineID: String
        let version: String
        let name: String
        let summary: String
        let recommended: Bool
    }
    let schemaVersion: Int
    let revision: Int
    let models: [Entry]
    func applying(to registry: ModelRegistry) throws -> ModelRegistry {
        guard schemaVersion == 1, revision > 0, models.count <= 100,
              Set(models.map(\.id)).count == models.count else { throw ModelManagerError.invalidArtifact }
        for entry in models {
            guard let known = registry.model(entry.id), entry.engineID == known.engineID,
                  entry.version == known.version, !entry.name.isEmpty, entry.name.count <= 100,
                  entry.summary.count <= 1000 else { throw ModelManagerError.unsupportedModel }
        }
        return ModelRegistry(models: registry.models.map { model in
            guard let entry = models.first(where: { $0.id == model.id }) else { return model }
            return AIModelDescriptor(id: model.id, name: entry.name, summary: entry.summary,
                category: model.category, engineID: model.engineID, version: model.version,
                languages: model.languages, requiredFiles: model.requiredFiles, optionalFiles: model.optionalFiles,
                runtime: model.runtime, capabilities: model.capabilities, license: model.license,
                recommended: entry.recommended, dependencies: model.dependencies)
        }, packs: registry.packs)
    }
}
actor RemoteModelCatalogStore {
    static let shared = RemoteModelCatalogStore()
    static let url = URL(string: "https://raw.githubusercontent.com/duynk-tech/TransTools/main/catalog/models-v1.json")!
    private var fetching = false
    private var cache: URL {
        LocalTTSModelStore.base.deletingLastPathComponent().appendingPathComponent("catalog-v1.json")
    }
    func cached(for registry: ModelRegistry) -> ModelRegistry {
        guard let data = try? Data(contentsOf: cache), data.count <= 256_000,
              let feed = try? JSONDecoder().decode(RemoteModelCatalog.self, from: data),
              let applied = try? feed.applying(to: registry) else { return registry }
        return applied
    }
    func update(_ registry: ModelRegistry) async throws -> (ModelRegistry, Int) {
        guard !fetching else { throw URLError(.resourceUnavailable) }
        fetching = true; defer { fetching = false }
        var request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == Self.url.host,
              data.count <= 256_000 else { throw URLError(.badServerResponse) }
        let feed = try JSONDecoder().decode(RemoteModelCatalog.self, from: data)
        let applied = try feed.applying(to: registry)
        if let previous = try? Data(contentsOf: cache),
           let old = try? JSONDecoder().decode(RemoteModelCatalog.self, from: previous), old.revision > feed.revision {
            throw ModelManagerError.invalidArtifact
        }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cache, options: .atomic)
        return (applied, feed.revision)
    }
}
