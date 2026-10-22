import Foundation

struct UpdateManifest: Decodable {
    struct Asset: Decodable {
        let url: URL
        let sha256: String
        let size: Int
    }
    let schemaVersion: Int
    let version: String
    let title: String
    let notes: String
    let publishedAt: String
    let releaseURL: URL
    let zip: Asset
    let dmg: Asset

    func validate() throws {
        guard schemaVersion == 1,
              version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
              releaseURL.scheme == "https",
              (releaseURL.host == "trans-tools.vercel.app" ||
               (releaseURL.host == "github.com" && releaseURL.path == "/duynk-tech/TransTools/releases/tag/v\(version)")) else {
            throw ValidationError.invalidManifest
        }
        for asset in [zip, dmg] {
            guard asset.url.scheme == "https",
                  (asset.url.host?.hasSuffix(".public.blob.vercel-storage.com") == true ||
                   (asset.url.host == "github.com" &&
                    asset.url.path.hasPrefix("/duynk-tech/TransTools/releases/download/v\(version)/") &&
                    ["TransTools.zip", "TransTools.dmg"].contains(asset.url.lastPathComponent))),
                  asset.sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
                  asset.size > 0 else { throw ValidationError.invalidManifest }
        }
    }

    enum ValidationError: LocalizedError {
        case invalidManifest
        var errorDescription: String? { "Thông tin cập nhật không hợp lệ. Vui lòng thử lại sau." }
    }
}


extension UpdateManifest {
    private struct GitHubRelease: Decodable {
        struct File: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int
            let digest: String?
        }
        let tag_name: String
        let name: String?
        let body: String?
        let published_at: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [File]
    }
    static func fromGitHub(_ data: Data) async throws -> UpdateManifest {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        guard !release.draft, !release.prerelease,
              version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else {
            throw ValidationError.invalidManifest
        }
        let prefix = "https://github.com/duynk-tech/TransTools/releases/download/v\(version)/"
        func asset(_ name: String) async throws -> Asset {
            guard let file = release.assets.first(where: { $0.name == name }),
                  file.browser_download_url.absoluteString == prefix + name else { throw ValidationError.invalidManifest }
            var hash = file.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
            if hash == nil {
                guard let checksum = release.assets.first(where: { $0.name == name + ".sha256" }),
                      checksum.browser_download_url.absoluteString == prefix + name + ".sha256" else { throw ValidationError.invalidManifest }
                var request = URLRequest(url: checksum.browser_download_url)
                request.timeoutInterval = 15
                let (bytes, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count < 4096,
                      let text = String(data: bytes, encoding: .utf8) else { throw ValidationError.invalidManifest }
                let fields = text.split(whereSeparator: { $0.isWhitespace })
                guard fields.count == 2, fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name else { throw ValidationError.invalidManifest }
                hash = String(fields[0])
            }
            return Asset(url: file.browser_download_url, sha256: hash ?? "", size: file.size)
        }
        let manifest = UpdateManifest(schemaVersion: 1, version: version,
            title: release.name ?? "Trans Tools v\(version)", notes: release.body ?? "",
            publishedAt: release.published_at ?? "",
            releaseURL: URL(string: "https://github.com/duynk-tech/TransTools/releases/tag/v\(version)")!,
            zip: try await asset("TransTools.zip"), dmg: try await asset("TransTools.dmg"))
        try manifest.validate()
        return manifest
    }
}
