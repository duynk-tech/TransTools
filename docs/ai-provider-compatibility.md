# AI provider compatibility

TransTools routes text translation, grammar, meeting summaries and spoken conversation replies through `AITransport`. Speech input and playback remain Apple's local speech services; a Live/TTS model is not used for this text pipeline.

| Provider | Discovery | Text endpoint | Authentication |
| --- | --- | --- | --- |
| Gemini | `/v1beta/models`, paginated; requires `generateContent` | `/v1beta/models/{id}:generateContent` | `x-goog-api-key` |
| OpenAI | `/v1/models`, filters non-text models | GPT-4 and chat aliases: `/v1/chat/completions`; newer/reasoning models: `/v1/responses` | Bearer |
| DeepSeek | `/models` | `/chat/completions` | Bearer |
| Claude | `/v1/models`, paginated | `/v1/messages` | `x-api-key`, `anthropic-version: 2023-06-01` |

Sampling parameters are omitted to avoid model-specific rejection. GPT reasoning uses the appropriate completion/output token field, rather than legacy `max_tokens`. Gemini and Claude assemble text blocks and exclude thinking blocks. OpenAI Responses reads message output blocks rather than assuming the first output item is text. OpenAI requests set `store: false`.

The exact selected model is tried first. Only a 404 triggers discovery and another model from the same provider. Successful recovery is cached in memory, then notifies the app to update its selected model and saved preference when that selection still matches. Authentication, quota, network and server failures propagate without switching providers or consuming paid retries on different models. Catalog membership alone does not prove that a generation request will succeed; use **Kiểm tra AI** or **Kiểm tra kết nối** for an actual generation check.

## Validation (2026-10-02)

- `python3 scripts/test-ai.py`: 27 checks passed; executes production transport with mock HTTP responses; covers request schemas/authentication, Gemini pagination/capabilities, text parsing, selected-model preservation, 404 recovery and no retries for HTTP 400/401/403/429/500.
- `python3 scripts/test-ai.py --live`: uses locally configured encrypted credentials without printing keys; tests discovery, generation and the production conversation prompt using the app's saved model preference. Only synthetic input is sent.
- Installed app: **Kiểm tra AI** displayed “Kết nối thành công · Gemini · gemini-flash-lite-latest”; the previous `gemini-2.5-flash` selection updated after successful recovery.
- Live Gemini: model discovery, generation and conversation prompt passed. Example reply: “Hello! I am doing well, thank you. How is your day going today?”
- OpenAI, DeepSeek and Claude: no configured keys on this machine; live validation remains pending. Mock/schema verification is not evidence of account access or production service availability.

## Official references

- [Gemini Models API](https://ai.google.dev/api/models)
- [Gemini model catalog](https://ai.google.dev/gemini-api/docs/models)
- [OpenAI Responses migration](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [OpenAI Chat API](https://developers.openai.com/api/reference/resources/chat)
- [DeepSeek Models API](https://api-docs.deepseek.com/api/list-models/)
- [DeepSeek model catalog](https://api-docs.deepseek.com/quick_start/pricing/)
- [Claude Models API](https://platform.claude.com/docs/en/api/models/list)
- [Claude model catalog](https://platform.claude.com/docs/en/models/overview)
