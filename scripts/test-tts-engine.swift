// Legacy test entry point. The previous suite installed dummy models into the
// user's active model directory; use the isolated XCTest suite instead.
import Foundation
@main struct TTSTestRunner {
    static func main() {
        print("Run: zsh scripts/test-local-tts.sh")
        print("Optional real inference: LOCAL_TTS_FIXTURE=/path/to/assets zsh scripts/test-local-tts.sh")
    }
}
