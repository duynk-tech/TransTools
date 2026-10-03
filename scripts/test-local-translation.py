#!/usr/bin/env python3
"""Execute the production routing method with controlled translators."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'Sources/TransTools/Services.swift').read_text()
a=s.index('    static func translate(\n',s.index('// MARK: - Translation Endpoints'))
b=s.index('    static func practiceConversation',a)
method=s[a:b]
code='''import Foundation
import Translation
enum AppLanguage: String { case english, vietnamese }
enum DomainSpecialty: String { case developer; func promptDescription(from: AppLanguage, to: AppLanguage) -> String { "prompt" } }
enum AIProvider: String { case apple, free, gemini }
enum AppleNativeTranslator {
 static var shouldFail = false
 static var unchanged = false
 static func translate(_ text: String, from: AppLanguage, to: AppLanguage) async throws -> String {
  if shouldFail { throw NSError(domain: "probe", code: 1) }
  return unchanged ? text : "local: " + text
 }
}
enum Probe {
 static let translationCache = NSCache<NSString, NSString>()
 static var networkCalls = 0
 static func freeTranslate(_ text: String, from: AppLanguage, to: AppLanguage) async throws -> String { networkCalls += 1; return "online: " + text }
 static func callAI(prompt: String, provider: AIProvider, model: String, key: String) async throws -> String { networkCalls += 1; return "AI" }
''' + method + '''
}
@main struct Run {
 static func main() async throws {
  AppleNativeTranslator.shouldFail = true
  let online = try await Probe.translate("Hello", provider: .apple, model: "", key: "", allowNetworkFallback: true)
  precondition(online == "online: Hello" && Probe.networkCalls == 1)
  do {
   _ = try await Probe.translate("Hello", provider: .apple, model: "", key: "", allowNetworkFallback: false)
   fatalError("Local route swallowed an error or reused online cache")
  } catch { precondition(Probe.networkCalls == 1) }
  AppleNativeTranslator.shouldFail = false
  let local = try await Probe.translate("Hello", provider: .apple, model: "", key: "secret-unused", allowNetworkFallback: false)
  precondition(local == "local: Hello" && Probe.networkCalls == 1)
  AppleNativeTranslator.unchanged = true
  let properName = try await Probe.translate("TransTools", provider: .apple, model: "", key: "", allowNetworkFallback: false)
  precondition(properName == "TransTools" && Probe.networkCalls == 1)
  print("PASS: Apple local never calls network on success, error or unchanged text; online cache stays separate")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='local-routing-') as d:
 p=Path(d)/'main.swift';p.write_text(code);binary=Path(d)/'test'
 subprocess.run(['swiftc','-parse-as-library',str(p),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
