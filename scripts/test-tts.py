#!/usr/bin/env python3
"""Verify production speech text cleanup and automatic voice selection."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parent.parent
s=(root/'Sources/TransTools/Services.swift').read_text()
normalize=s[s.index('    public static func normalizeForSpeech'):s.index('    // Manual playback')]
voice=s[s.index('    public func bestVoice(for locale:'):s.index('    // AVSpeechSynthesizerDelegate')]
code='import Foundation\nimport AVFoundation\nstruct Probe { var selectedVoiceID: String? = nil; let installedVoiceSnapshot = AVSpeechSynthesisVoice.speechVoices()\n'+normalize+voice+'}\n'
code+='''
func check(_ ok: Bool, _ label: String) { precondition(ok, label); print("PASS:", label) }
for sample in ["I'm ready.", "Don't worry, we'll help.", "It's John's book."] {
 check(Probe.normalizeForSpeech(sample, languageLocale: "en-US") == sample, "preserve contraction/possessive: " + sample)
}
check(Probe.normalizeForSpeech("I’m ready. We’ll go.", languageLocale: "en-US") == "I'm ready. We'll go.", "curly apostrophes remain contractions")
check(Probe.normalizeForSpeech("**Hello** [laughter]", languageLocale: "en-US") == "Hello", "remove formatting/noise without changing spoken words")
let probe = Probe()
if let voice = probe.bestVoice(for: "en-US") {
 print("Selected English voice:", voice.name, voice.identifier)
 check(!voice.identifier.contains("eloquence") && (!voice.identifier.hasPrefix("com.apple.speech.synthesis.voice.") || voice.identifier.hasSuffix(".Alex")), "automatic English voice excludes legacy/effect voices")
 check(voice.language.hasPrefix("en"), "English voice locale")
}
'''
with tempfile.TemporaryDirectory(prefix='transtools-tts-test-') as tmp:
 p=Path(tmp)/'main.swift';p.write_text(code);binary=Path(tmp)/'test'
 subprocess.run(['swiftc',str(p),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
