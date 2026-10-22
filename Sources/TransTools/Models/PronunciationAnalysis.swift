import Foundation

/// A recognizer transcript is not a pronunciation assessment. Only a validated
/// analyzer can supply calibrated phoneme/rhythm/stress scores in Shadow Me.
struct PronunciationAnalysisRequest: Sendable {
    let referenceText: String
    let language: String
    let referenceAudio: URL
    let learnerAudio: URL
}
struct PronunciationAssessment: Sendable {
    let feedback: String
    let phonemeAccuracy: Double?
    let rhythm: Double?
    let stress: Double?
}
protocol PronunciationAnalyzer: Sendable {
    var supportedLanguages: Set<String> { get }
    func analyze(_ request: PronunciationAnalysisRequest) async throws -> PronunciationAssessment
}
