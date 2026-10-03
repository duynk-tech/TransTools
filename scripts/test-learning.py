#!/usr/bin/env python3
"""Exercise production model and scheduling methods without touching user storage."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent
vocab = (root / 'Sources/TransTools/Vocabulary.swift').read_text()
learning = (root / 'Sources/TransTools/LanguageLearning.swift').read_text()
model = vocab[vocab.index('public struct VocabularyItem'):vocab.index('// MARK: - Vocabulary Manager')]
add = vocab[vocab.index('    public func add('):vocab.index('    public func remove(')]
srs = vocab[vocab.index('    public enum SRSGrade'):vocab.index('    public func speak(')]
daily = learning[learning.index('    public func markReviewCompleted('):learning.index('    // Curated Daily')].replace('UserDefaults.standard', 'defaults')
code = 'import Foundation\nimport AVFoundation\n' + model
code += 'final class Harness { var items: [VocabularyItem] = []; func saveItems() {}\n' + add + srs + '}\n'
code += 'final class DailyHarness { var completedReviewsTodayCount = 7; var lastActiveDateString = "yesterday"; let defaults = UserDefaults(suiteName: UUID().uuidString)!\n' + daily + '}\n'
code += '''
func check(_ ok: Bool, _ label: String) { if !ok { fatalError(label) }; print("PASS: " + label) }
let h = Harness()
h.add(word: "確認", meaning: "Nhật", language: "ja")
h.add(word: "確認", meaning: "Trung", language: "zh")
check(h.items.count == 2, "same spelling in two languages preserved")
h.add(word: "確認", meaning: "Nhật updated", language: "ja")
check(h.items.count == 2 && h.items.first?.meaning == "Nhật updated", "same-language duplicate updated")
let id = h.items[0].id
h.review(itemId: id, grade: .easy); h.review(itemId: id, grade: .easy)
h.items[0].dueAt = Date(timeIntervalSinceNow: -60)
check(h.items[0].isMastered && h.dueItems.contains(where: {$0.id == id}), "mastered overdue card still scheduled")
h.review(itemId: id, grade: .again)
check(!h.items[0].isMastered && h.items[0].repetition == 0, "forgotten card returns to learning")
let delay = h.items[0].dueAt!.timeIntervalSinceNow
check(delay > 590 && delay <= 600, "forgotten card due after ten minutes")
let encoded = try JSONEncoder().encode(h.items)
check(try JSONDecoder().decode([VocabularyItem].self, from: encoded) == h.items, "SRS and languages survive persistence")
let old = try JSONDecoder().decode(VocabularyItem.self, from: Data("{\\"word\\":\\"legacy\\",\\"meaning\\":\\"cũ\\"}".utf8))
check(old.language == "en" && old.repetition == 0 && old.dueAt == nil, "legacy data decodes")
let d = DailyHarness()
let today = Date()
d.markReviewCompleted(now: today)
check(d.completedReviewsTodayCount == 1, "new day resets before first review")
d.markReviewCompleted(now: today)
check(d.completedReviewsTodayCount == 2, "same day increments")
d.markReviewCompleted(now: Calendar.current.date(byAdding: .day, value: 1, to: today)!)
check(d.completedReviewsTodayCount == 1, "running app resets on next day")
'''
# Reading and queue wiring are checked separately from the Swift model behavior.
assert 'phonetic: sentence.keyWordReading' in learning
assert 'let due = vocabManager.dueItems.filter { $0.language == learningManager.selectedLanguage.rawValue }' in learning
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / 'main.swift'
    path.write_text(code)
    subprocess.run(['swift', '-module-cache-path', str(root / '.build/module-cache'), str(path)], check=True)
