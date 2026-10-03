#!/usr/bin/env python3
"""Verify the production OCR language detector with representative sentences."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parent.parent
services = (root/'Sources/TransTools/Services.swift').read_text()
languages = services[services.index('public enum AppLanguage:'):services.index('// MARK: - Subtitle Display Mode')]
ocr = (root/'Sources/TransTools/ScreenOCRService.swift').read_text()
detect = ocr[ocr.index('    nonisolated static func detectLanguage'):ocr.index('    func translateReviewedText')]
code = 'import Foundation\nimport NaturalLanguage\n' + languages + 'enum Probe {\n' + detect + '}\n' + '''
let samples: [(String, AppLanguage)] = [
("Please confirm the meeting time and send me the project report tomorrow morning.", .english),
("Vui lòng xác nhận thời gian cuộc họp và gửi cho tôi báo cáo dự án vào sáng mai.", .vietnamese),
("明日の会議の時間を確認して、プロジェクトの報告書を送ってください。", .japanese),
("请确认明天的会议时间，并把项目报告发送给我。", .chinese),
("내일 회의 시간을 확인하고 프로젝트 보고서를 보내 주세요.", .korean)]
for (text, expected) in samples {
 precondition(Probe.detectLanguage(text) == expected, "Wrong OCR language: " + expected.rawValue)
 print("PASS OCR language:", expected.rawValue)
}
precondition(Probe.detectLanguage("") == nil)
print("PASS OCR empty input")
'''
with tempfile.TemporaryDirectory(prefix='ocr-language-') as directory:
    swift = Path(directory)/'test.swift'; swift.write_text(code)
    binary = Path(directory)/'test'
    subprocess.run(['swiftc', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
