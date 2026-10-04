# Local Natural TTS

## Implementation

- Official Supertonic 3 Swift reference, adapted into `LocalSpeechBackend`, MIT code license retained in app Resources/Licenses.
- Supertonic uses statically linked ONNX Runtime through Microsoft's Swift package. VieNeu and Qwen use separately managed private Python/SDK environments installed from the app; users do not configure system Python.
- Model revision pinned to `aafc6e32416a594460b32413efc49d7fe4ce6d46`. Four ONNX files, tokenizer/config, F1 voice and model license: **398,668,255 bytes**. All SHA-256 values come from LFS metadata or direct hashing of resources at that immutable revision.
- Inference is serialized in a Swift actor and uses up to four CPU threads on Apple Silicon/Intel. CPU execution is deliberate: the official Swift example does not enable a GPU/CoreML provider. No claim of Neural Engine acceleration.
- Supertonic languages: Vietnamese, English, Japanese, Korean. Chinese can use the separately installed Qwen adapter; see [per-language routing](language-voice-routing.md).

## Runtime and privacy

Choosing Natural Local Voice bypasses Edge/Gemini/cloud TTS. Unavailable language, missing installation, initialization, synthesis or initial playback failure uses direct macOS speech. No runtime model fetch or conversation upload. The model downloader only runs after explicit Download & Enable / license acceptance.

ONNX sessions and voice tensors load only on the first reading and remain warm between sentences. Idle timeout (120 seconds), warning/critical memory pressure, disabling/removing the model or switching to a different local backend schedules resource release. Session operations are serialized; an ongoing inference finishes/cancels before release.

Current utterance and at most four preceding utterances (512 characters each) enter rule-based prosody. No local LLM. Model controls are voice preset and speed; semantic emotion affects relative speed, punctuation carries pauses. Precise pitch, emotion conditioning and word-level emphasis are not supported by this backend and are not advertised as implemented.

## Playback

The router segments sentences, protects URLs/decimals/known abbreviations, caps normal chunks at word boundaries and starts playback after the first generated chunk. The next chunk is synthesized while preceding audio plays. Japanese/Korean long strings receive further chunking through the reference backend. A single unusually long token is preserved.

TTSService retains its existing auto-meeting queue and queue bound; manual playback interrupts. The existing new-translation policy additionally chooses interrupt versus queue. Each chunk has one completion owner; stop invalidates the request so late audio cannot play. Volume is applied to PCM samples. Long-text first-audio latency is measured, not guaranteed below one second on all Macs or cold model loads.

## Model installation

Application Support/TransTools/Models/TTS contains staging and versioned model directories. Each HTTPS download has size and incremental SHA-256 validation before installation. HTTPS redirects only. The metadata is a compiled, pinned allowlist, never arbitrary server filesystem paths. Installation commits an atomic `current.json` pointer after every file validates. A failed/cancelled update preserves the existing pointer/model. Previous model files remain until Remove Model to protect in-flight sessions; disk usage includes all stored versions. Removal deletes the TTS model store, not unrelated TransTools data.

Update checks compare the installed revision with the tested catalog shipped in the application. New model versions are delivered through TransTools updates, rather than silently trusting upstream `main`.

## Licenses and sources

- Swift reference: https://github.com/supertone-oss-archive/supertonic/tree/main/swift
- Model and language metadata: https://huggingface.co/supertone-oss-archive/supertonic-3/tree/aafc6e32416a594460b32413efc49d7fe4ce6d46
- Open RAIL-M model license: https://huggingface.co/supertone-oss-archive/supertonic-3/blob/aafc6e32416a594460b32413efc49d7fe4ce6d46/LICENSE
- ONNX Runtime: https://github.com/microsoft/onnxruntime-swift-package-manager

The app displays the complete model license before download and includes license copies in its bundle. Model use is subject to Open RAIL-M restrictions. Model weights are not bundled in the initial application.

## Verification

`LOCAL_TTS_FIXTURE=/path/to/verified/assets swift test -c release --filter LocalTTSTests`

`LOCAL_TTS_NETWORK_TEST=1 swift test -c release --filter LocalTTSTests.testRealNetworkDownload` opts into an actual 399 MB HTTPS download/install validation.

Tests exercise semantic Vietnamese correction, question detection, bounded context, language fallback, checksum corruption/path traversal, segmentation, atomic installation/cancellation/removal, real ONNX synthesis in four languages and audio queue/interruption. Generated voice samples are retained in `/tmp/transtools-natural-voice-samples` for listening review. Nonzero waveforms and durations verify actual inference but do not certify pronunciation quality; listening review remains necessary.

Observed integration run on the development Mac: ten tests passed, including a real HTTPS download. Four-language sample generation ranged from roughly 0.7–2 seconds across cold/warm runs; below-one-second playback is a target, not a guaranteed contract. The official Swift source snapshot used is `1e9799e964ea4c0dad7cde993b65c3c813a7b373`.
