# Windows alignment with the current Mac app — 2026-10-07

The goal is the same six main screens, controls, readable mint styling and saved user data. Windows uses WASAPI, WPF, Windows OCR, Windows credentials and Ctrl+Alt shortcuts. These substitutions do not require different product navigation.

## Changes in this build

- Six tabs in the top header match Mac: Meeting, Notebook, Quick Translate, Language Learning, Conversation and Settings. Text Reader lives inside Quick Translate.
- Views are created once and reused, so switching tabs preserves local controls and scroll state.
- Buttons share mint styling, fixed border width and predictable heights; deletion controls use red. Transcript cards have a mint border even when not hovered.
- Meeting starts with system audio selected. A stopped transcript is saved before starting the next meeting. Saving the same session again updates its existing ID. Explicit clearing requires confirmation.
- Floating captions retain the last readable pair during empty updates, scroll after layout, and offer Stop Meeting and Open App. Mascot context menu can start a meeting, open captions and hide the main window only after capture starts successfully.
- Conversation can generate a personalized opening, stop recording after an integer silence delay, automatically send recognized speech, and scroll to the newest message. Initial silence does not submit empty speech; resumed speech resets the pause counter. One recording remains capped at sixty seconds.
- Notebook can search titles and transcript content. Notes have a separate editor and preview for headings, bullets and bold. AI summaries update the session that requested them even if selection changes meanwhile.

## Validation

Cross-target Release build on Mac has passed without compiler warnings or errors. Contract tests cover PCM format/resampling, subtitle word preservation, model checksums, storage inventory, GitHub update validation, learning migration/SRS and speech endpoint timing. Actual model inference is explicitly skipped unless its required model paths are supplied.

Windows CI builds the native VieNeu phonemizer, runs the contracts, renders all six WPF routes at 1280×820 and 1000×600 while checking binding errors, then builds the installer and portable ZIP. Screenshots and logs are artifacts, not a claim that interactive Windows 10/11 tests passed.

## Remaining differences requiring work or direct verification

This build is **not 100% feature or visual parity** with the newest Mac app:

- Mac's latest natural scenery, mini chat, richer mascot popup, assistant naming and caption mascot column still need Windows equivalents.
- Notebook does not yet combine meeting and conversation sessions or include the full vocabulary/AI action checklist workflow.
- Windows does not yet include the new personal voice recorder/dataset workflow or the dynamic GitHub model registry screen.
- The newest speech-reading token normalization/AI preparation and adaptive learning features require a Windows port and output-quality tests.
- Offline translation remains a platform gap. The Microsoft compatibility probe is a test tool, not an implemented translation provider. Online Google/AI translation does not imply offline support.
- Loopback/microphone, OCR region selection, caption placement across multiple displays, 125–200% DPI, output audio, installer upgrade/uninstall, and long sessions require Windows 10 and 11 tests. Neither the Mac compiler nor Windows CI screenshots establish those results.

No production download link or version is changed by this preview branch.
