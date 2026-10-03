#!/usr/bin/env python3
"""Verify Settings cancellation cannot stop another feature or lose queued captions."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parent.parent
source = (root/'Sources/TransTools/Services.swift').read_text()
start = source.index('    public func stopPreview()')
end = source.index('    private func processNextInQueue()', start)
method = source[start:end]
code = 'import Foundation\nstruct Probe { var isSettingsPreview = false; var speechQueue = [String](); var stops = 0; var played = [String](); mutating func stop() { stops += 1; isSettingsPreview = false; speechQueue.removeAll() }; mutating func processNextInQueue() { isSettingsPreview = false; if !speechQueue.isEmpty { played.append(speechQueue.removeFirst()) } }\n' + method.replace('public func', 'mutating func') + '''
}
var conversation = Probe()
conversation.speechQueue = ["caption"]
conversation.stopPreview()
precondition(conversation.stops == 0 && conversation.speechQueue == ["caption"])
var preview = Probe()
preview.isSettingsPreview = true
preview.speechQueue = ["first", "second"]
preview.stopPreview()
precondition(preview.stops == 1 && preview.played == ["first"] && preview.speechQueue == ["second"])
preview.stopPreview()
precondition(preview.stops == 1)
print("PASS: preview cancellation preserves another owner and queued captions")
'''
with tempfile.TemporaryDirectory(prefix='preview-owner-') as directory:
    swift = Path(directory)/'main.swift'; swift.write_text(code)
    subprocess.run(['swift', '-module-cache-path', str(root/'.build/module-cache'), str(swift)], check=True)
