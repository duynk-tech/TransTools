import Foundation
let good: [String: Any] = ["schemaVersion": 1, "version": "1.3.1", "title": "TransTools", "notes": "", "publishedAt": "2026-10-02T00:00:00Z", "releaseURL": "https://trans-tools.vercel.app/releases", "zip": ["url": "https://example.public.blob.vercel-storage.com/releases/app.zip", "sha256": String(repeating: "a", count: 64), "size": 100], "dmg": ["url": "https://example.public.blob.vercel-storage.com/releases/app.dmg", "sha256": String(repeating: "b", count: 64), "size": 200]]
func check(_ object: [String: Any], accepted: Bool, name: String) {
    do {
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: JSONSerialization.data(withJSONObject: object))
        try manifest.validate()
        precondition(accepted, name)
    } catch { precondition(!accepted, name) }
    print("PASS: \(name)")
}
check(good, accepted: true, name: "valid manifest")
for (field, value) in [("schemaVersion", 2 as Any), ("version", "1.3.1-beta" as Any), ("releaseURL", "http://trans-tools.vercel.app/releases" as Any)] {
    var object = good; object[field] = value
    check(object, accepted: false, name: "reject \(field)")
}
for (field, value) in [("url", "https://malicious.example/app.zip" as Any), ("sha256", "invalid" as Any), ("size", 0 as Any)] {
    var object = good; var asset = object["zip"] as! [String: Any]; asset[field] = value; object["zip"] = asset
    check(object, accepted: false, name: "reject asset \(field)")
}
var missing = good; missing.removeValue(forKey: "zip")
check(missing, accepted: false, name: "reject missing zip")
