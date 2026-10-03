#!/usr/bin/env python3
"""Regression: live updates must not reopen a hidden dashboard."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/TransTools/App.swift').read_text()
method = source[source.index('    func attachMainWindow('):source.index('    func showMainWindow()', source.index('    func attachMainWindow('))]
delegate = source[source.index('final class MainWindowDelegate:'):source.index('struct WindowAccessor:')]
code = '''import Foundation
import AppKit
protocol NSWindowDelegate {}
final class Screen { let visibleFrame = NSRect(x: 0, y: 0, width: 1200, height: 800) }
enum NSScreen { static let main: Screen? = nil }
final class NSWindow {
 var isVisible = false
 var isReleasedWhenClosed = true
 var delegate: NSWindowDelegate?
 var screen: Screen? = nil
 func setFrame(_ rect: NSRect, display: Bool) {}
 func makeKeyAndOrderFront(_ sender: Any?) { isVisible = true }
 func orderOut(_ sender: Any?) { isVisible = false }
}
final class Application { var activations = 0; func activate(ignoringOtherApps: Bool) { activations += 1 } }
let NSApp = Application()
''' + delegate + '''
final class Probe {
 weak var mainWindow: NSWindow?
 let windowDelegate = MainWindowDelegate()
''' + method + '''
}
let model = Probe()
let window = NSWindow()
model.attachMainWindow(window)
precondition(window.isVisible && window.delegate != nil && !window.isReleasedWhenClosed)
let activations = NSApp.activations
precondition(!model.windowDelegate.windowShouldClose(window))
precondition(!window.isVisible)
for _ in 0..<100 { model.attachMainWindow(window) }
precondition(!window.isVisible && NSApp.activations == activations)
window.makeKeyAndOrderFront(nil)
model.attachMainWindow(window)
precondition(window.isVisible && NSApp.activations == activations)
let replacement = NSWindow()
model.attachMainWindow(replacement)
precondition(replacement.isVisible && model.mainWindow === replacement)
print("PASS: 100 live updates keep dashboard hidden; explicit reopen and replacement work")
'''
with tempfile.TemporaryDirectory(prefix='main-window-lifecycle-') as d:
    path = Path(d)/'main.swift'; path.write_text(code)
    subprocess.run(['swift', '-module-cache-path', str(root/'.build/module-cache'), str(path)], check=True)
