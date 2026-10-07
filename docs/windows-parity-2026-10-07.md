# Windows alignment with the current Mac app — 2026-10-07

The goal is the same six main screens, controls, readable mint styling and saved user data. Windows uses WASAPI, WPF, Windows OCR, Windows credentials and Ctrl+Alt shortcuts. These substitutions do not require different product navigation.

## Changes in this build

- The executable and installer use the current mint application icon. The native phonemizer build tree lives outside the publish folder; package validation rejects build SDK/source folders.
- Six tabs in the top header match Mac: Meeting, Notebook, Quick Translate, Language Learning, Conversation and Settings. Text Reader lives inside Quick Translate.
- Views are created once and reused, so switching tabs preserves local controls and scroll state.
- Buttons and selection menus share mint styling, fixed border width and predictable heights; deletion controls use red. Transcript cards have a mint border even when not hovered.
- Meeting starts with system audio selected. A stopped transcript is saved before starting the next meeting. Saving the same session again updates its existing ID. Explicit clearing requires confirmation.
- Floating captions retain the last readable pair during empty updates, scroll after layout, and offer Stop Meeting and Open App. Mascot context menu can start a meeting, open captions and hide the main window only after capture starts successfully.
- Conversation can generate a personalized opening, stop recording after an integer silence delay, automatically send recognized speech, and scroll to the newest message. Initial silence does not submit empty speech; resumed speech resets the pause counter. One recording remains capped at sixty seconds.
- Mini chat shares the conversation state when the main window closes during an active conversation. Ending the session invalidates in-flight replies. The floating caption window can show the assistant in its own first column. Assistant naming is saved and applied to the header and conversation identity.
- Vietnamese Text Reader can request token-only pronunciation suggestions from configured AI for numbers, dates and acronyms. Only enumerated spans are replaced in a separate spoken copy; the source text is unchanged. The request is cancellable, has a 15-second deadline and falls back to the source if the response is invalid.
- Notebook can search titles and transcript content. Notes have a separate editor and preview for headings, bullets and bold. AI summaries update the session that requested them even if selection changes meanwhile.

## Validation

Cross-target Release build on Mac has passed without compiler warnings or errors. Contract tests cover PCM format/resampling, subtitle word preservation, model checksums, storage inventory, GitHub update validation, learning migration/SRS and speech endpoint timing. The native Windows run [37585741860](https://github.com/duynk-tech/TransTools/actions/runs/37585741860) passed 55 checks with zero skipped checks on Windows x64 build 26100, including real Supertonic and VieNeu inference and pinned phonemizer golden output. This run also produced the installer and portable package after the package-content checks. Interactive audio capture was not performed.

Windows CI builds the native VieNeu phonemizer, runs the contracts, renders all six WPF routes at 1280×820 and 1000×600 while checking binding errors, with long-text meeting/conversation/notebook fixtures and separate mini-chat/subtitle captures in the newer harness, then builds the installer and portable ZIP. Screenshots and logs are artifacts, not a claim that interactive Windows 10/11 tests passed.

## Remaining differences requiring work or direct verification

This build is **not 100% feature or visual parity** with the newest Mac app:

- The richer Mac mascot popup and topic-specific scenery still need Windows equivalents; the Windows meeting garden uses static time-of-day colors and native vector shapes.
- Notebook does not yet combine meeting and conversation sessions or include the full vocabulary/AI action checklist workflow.
- Windows does not yet include the new personal voice recorder/dataset workflow or the dynamic GitHub model registry screen.
- The full speech pause controls, pronunciation verification/retry policy and adaptive learning features still require a Windows port and output-quality tests.
- Offline translation remains a platform gap. The Microsoft compatibility probe is a test tool, not an implemented translation provider. Online Google/AI translation does not imply offline support.
- Loopback/microphone, OCR region selection, caption placement across multiple displays, 125–200% DPI, output audio, installer upgrade/uninstall, and long sessions require Windows 10 and 11 tests. Neither the Mac compiler nor Windows CI screenshots establish those results.

No production download link or version is changed by this preview branch.
