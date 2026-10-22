import Foundation

enum NotebookLearningPolicy {
    static func candidates(_ records: [CaptionRecord], language: String) -> [CaptionRecord] {
        records.filter { row in
            !row.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !row.vietnamese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && row.original.count <= 300 && row.vietnamese.count <= 500
                && (row.sourceLanguage == nil || row.sourceLanguage == language)
                && (row.targetLanguage == nil || row.targetLanguage == "vi")
                // A prefix translation is useful live, but not a verified
                // original/meaning pair for a saved learning exercise.
                && (row.translationSource == nil || row.translationSource == row.original)
        }
    }
}
