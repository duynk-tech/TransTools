#!/usr/bin/env python3
"""Verify production encrypted storage with fake migration and temporary files."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parent.parent
text = (root/'Sources/TransTools/Services.swift').read_text()
source = text[text.index('enum CredentialStore {'):text.index('struct PracticeConversationReply:')]
a = source.index('    private static var storageURL: URL {')
b = source.index('    private static func getHardwareUUID()', a)
source = source[:a] + '    private static var storageURL: URL { URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("credentials.enc") }\n' + source[b:]
source = source.replace('UserDefaults.standard', 'testDefaults')
code = '''import Foundation
import CryptoKit
import IOKit
let testDefaults = UserDefaults(suiteName: "crypto-test-" + UUID().uuidString)!
enum AIProvider: String { case gemini, openai, deepseek, claude, apple, free }
enum LegacyKeychainRecovery {
 static var values = ["gemini": "fake-migrated-secret"]
 static var calls = 0
 static func read(account: String) throws -> String? { calls += 1; return values[account] }
 static func remove(account: String) throws { values.removeValue(forKey: account) }
}
''' + source + '''
let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("credentials.enc")
try CredentialStore.save("fake-migrated-secret", for: .gemini)
precondition(CredentialStore.read(for: .gemini) == "fake-migrated-secret")
let count = LegacyKeychainRecovery.calls
precondition(CredentialStore.read(for: .gemini) == "fake-migrated-secret")
precondition(LegacyKeychainRecovery.calls == count)
let encrypted = try Data(contentsOf: url)
precondition(encrypted.range(of: Data("fake-migrated-secret".utf8)) == nil)
try CredentialStore.save("fake-new-secret", for: .openai)
precondition(CredentialStore.read(for: .openai) == "fake-new-secret")
let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
try Data("corrupt".utf8).write(to: url)
do { try CredentialStore.save("replacement", for: .gemini); preconditionFailure("Expected failure") }
catch { let disk = try Data(contentsOf: url); precondition(disk == Data("corrupt".utf8)) }
precondition(CredentialStore.read(for: .gemini) == "fake-migrated-secret")
print("PASS: AES-GCM encryption, cached reads, 0600 permissions, corrupt-file preservation")
'''
with tempfile.TemporaryDirectory(prefix='crypto-store-') as directory:
    swift = Path(directory)/'main.swift'; swift.write_text(code)
    binary = Path(directory)/'test'
    subprocess.run(['swiftc', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary), directory], check=True)
