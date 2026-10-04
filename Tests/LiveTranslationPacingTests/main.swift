import Foundation
func check(_ result: Bool, _ message: String) {
    precondition(result, message)
}
check(!LiveTranslationPacing.balanced.ready(text: "We should", quiet: 0.8, elapsed: 2), "Do not translate a short fragment at the time limit")
check(LiveTranslationPacing.balanced.ready(text: "We should", quiet: 1.5, elapsed: 2.5), "Short fragment eventually translates after a pause")
check(LiveTranslationPacing.balanced.ready(text: "Yes.", quiet: 0.25, elapsed: 0.25), "Complete short answer remains fast")
check(LiveTranslationPacing.balanced.ready(text: "We should meet tomorrow", quiet: 0.8, elapsed: 0.8), "Normal context pause")
check(LiveTranslationPacing.contextual.ready(text: "We should meet tomorrow", quiet: 0.1, elapsed: 3), "Continuous speech remains bounded")
check(LiveTranslationPacing.balanced.ready(text: "你好。", quiet: 0.25, elapsed: 0.25), "CJK sentence boundary")
print("Pacing checks passed")
