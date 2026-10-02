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
              releaseURL.scheme == "https", releaseURL.host == "trans-tools.vercel.app" else {
            throw ValidationError.invalidManifest
        }
        for asset in [zip, dmg] {
            guard asset.url.scheme == "https",
                  asset.url.host?.hasSuffix(".public.blob.vercel-storage.com") == true,
                  asset.sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
                  asset.size > 0 else { throw ValidationError.invalidManifest }
        }
    }

    enum ValidationError: LocalizedError {
        case invalidManifest
        var errorDescription: String? { "Thông tin cập nhật không hợp lệ. Vui lòng thử lại sau." }
    }
}
