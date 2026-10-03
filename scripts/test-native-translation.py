#!/usr/bin/env python3
"""Probe installed Apple language packs and production translator with synthetic text."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parent.parent
source = (root / 'Sources/TransTools/Services.swift').read_text()
language = source[source.index('public enum AppLanguage:'):source.index('// MARK: - Subtitle Display Mode')]
translator = source[source.index('#if canImport(Translation)\n@available(macOS 15.0'):source.index('// MARK: - Specialized Domain')]
code = 'import Foundation\nimport Translation\n' + language + translator + '''
@main struct Probe {
 @MainActor static func main() async throws {
 for (language, text) in [(AppLanguage.english, "Hello! How are you today?"), (.japanese, "こんにちは。今日は元気ですか。"), (.chinese, "你好，你今天好吗？"), (.korean, "안녕하세요. 오늘 기분이 어때요?")] {
 let status = await LanguageAvailability().status(from: Locale.Language(identifier: language.appleLanguageCode), to: Locale.Language(identifier: "vi"))
 print(language.rawValue, "→ vi:", status)
 guard status == .installed else { continue }
 let preparing = Date()
 await AppleNativeTranslator.prepareInstalled(from: language, to: .vietnamese)
 print("Prepared", Int(Date().timeIntervalSince(preparing) * 1000), "ms")
 for run in 1...2 {
 let start = Date()
 let reply = try await AppleNativeTranslator.translate(text, from: language, to: .vietnamese)
 precondition(!reply.isEmpty && reply != text)
 print("PASS", run, Int(Date().timeIntervalSince(start) * 1000), "ms:", reply)
 }
 }
 let same = try await AppleNativeTranslator.translate("Xin chào", from: .vietnamese, to: .vietnamese)
 precondition(same == "Xin chào")
 print("PASS: same-language passthrough")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='native-translation-') as directory:
    swift = Path(directory) / 'probe.swift'; swift.write_text(code)
    binary = Path(directory) / 'probe'
    subprocess.run(['swiftc', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
