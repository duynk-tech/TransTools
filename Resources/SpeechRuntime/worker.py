"""Private stdio TTS worker. No HTTP listener, shell, or remote model code."""
import argparse, base64, contextlib, io, json, os, sys, time
from pathlib import Path

MODEL_REPOS = {
    "vieneu": [("pnnbao-ump/VieNeu-TTS-v3-Turbo", "61b85e3d937fbbacb387714180e8182823512523", ["onnx_update/*", "config.json", "speaker_encoder.onnx", "denoiser.onnx", "voices_v3_turbo.json", "README.md"]),
               ("OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX", "ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae", ["*.onnx", "*.data", "*.json", "README.md"])],
    "qwen": [("mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit", "049ef77fe8816b536193c0c25f9a214d17921282", ["*.json", "*.safetensors", "*.txt", "*.model", "*.tiktoken", "README.md", "speech_tokenizer/*"])],
}
QWEN_LANGUAGES = {"zh": "Chinese", "en": "English", "ja": "Japanese", "ko": "Korean", "de": "German", "fr": "French", "ru": "Russian", "pt": "Portuguese", "es": "Spanish", "it": "Italian"}

def configure(root, install):
    root.mkdir(parents=True, exist_ok=True)
    os.environ["HF_HOME"] = str(root / "hub")
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    os.environ["OMP_NUM_THREADS"] = "4"
    if not install:
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"


def download(engine, root):
    from huggingface_hub import snapshot_download
    for repo, revision, patterns in MODEL_REPOS[engine]:
        print("Downloading " + repo, file=sys.stderr, flush=True)
        snapshot_download(repo_id=repo, revision=revision, allow_patterns=patterns, max_workers=2,
                          local_dir=root / "assets" / repo.split("/")[-1])


def bind_local_artifacts(engine, root):
    import huggingface_hub
    original = huggingface_hub.hf_hub_download
    paths = {r[0]: root / "assets" / r[0].split("/")[-1] for r in MODEL_REPOS[engine]}
    def local_download(repo_id, filename, *args, **kwargs):
        if repo_id in paths:
            path = paths[repo_id] / (kwargs.get("subfolder") or "") / filename
            if not path.is_file(): raise FileNotFoundError("Missing installed artifact: " + filename)
            return str(path)
        return original(repo_id, filename, *args, **kwargs)
    huggingface_hub.hf_hub_download = local_download



def load(engine, root):
    bind_local_artifacts(engine, root)
    if engine == "vieneu":
        from vieneu import Vieneu
        return Vieneu(mode="v3turbo", backend="onnx", device="cpu", precision="fp32", threads=4), None
    import mlx.core as mx
    from huggingface_hub import snapshot_download
    from mlx_audio.tts.utils import load_model
    mx.set_cache_limit(128 * 1024 * 1024)
    mx.set_memory_limit(3 * 1024 * 1024 * 1024)
    repo, revision, _ = MODEL_REPOS[engine][0]
    path = str(root / "assets" / repo.split("/")[-1])
    return load_model(path), mx


def voices(engine, model):
    if engine == "vieneu":
        return [{"id": voice_id, "title": label} for label, voice_id in model.list_preset_voices()]
    return [{"id": name, "title": name} for name in model.supported_speakers]


def synthesize(engine, model, req):
    import numpy as np
    import soundfile as sf
    text = req.get("text", "").strip()
    language = req.get("language", "").lower().split("-")[0]
    if not text or len(text) > 500:
        raise ValueError("Empty or oversized chunk")
    started = time.monotonic()
    if engine == "vieneu":
        if language != "vi": raise ValueError("VieNeu is configured for Vietnamese only")
        audio = model.infer(text, voice=req.get("voice") or "Hải Đăng", max_chars=200)
        sr = 48000
    else:
        if language not in QWEN_LANGUAGES: raise ValueError("Unsupported Qwen language")
        results = model.generate_custom_voice(text=text, language=QWEN_LANGUAGES[language], speaker=req.get("voice") or "Vivian", max_tokens=1024, temperature=0.7)
        arrays = []
        for result in results:
            arrays.append(np.asarray(result.audio, dtype=np.float32))
            sr = result.sample_rate
        if not arrays: raise ValueError("Model returned no audio")
        audio = np.concatenate(arrays)
    audio = np.asarray(audio, dtype=np.float32).reshape(-1)
    if len(audio) < sr // 10 or len(audio) > sr * 120 or not np.isfinite(audio).all() or np.max(np.abs(audio)) < 0.0001:
        raise ValueError("Invalid or silent audio")
    speed = max(0.7, min(1.5, float(req.get("speed", 1))))
    if abs(speed - 1) > 0.02:
        import librosa
        audio = librosa.effects.time_stretch(audio, rate=speed)
    # Time stretching preserves pitch; never speed up by changing the sample rate.
    audio = np.clip(audio * max(0, min(1, float(req.get("volume", 1)))), -1, 1)
    wav = io.BytesIO(); sf.write(wav, audio, sr, format="WAV", subtype="PCM_16")
    return {"wav": base64.b64encode(wav.getvalue()).decode(), "sampleRate": sr, "duration": len(audio) / sr,
            "latencyMs": int((time.monotonic() - started) * 1000)}


def stream_speech(engine, model, req):
    import numpy as np
    import soundfile as sf
    text = req.get("text", "").strip()
    language = req.get("language", "").lower().split("-")[0]
    if not text or len(text) > 500: raise ValueError("Empty or oversized chunk")
    if engine == "vieneu":
        if language != "vi": raise ValueError("Unsupported VieNeu language")
        chunks = model.infer_stream(text, voice=req.get("voice") or "Hải Đăng", max_chars=200)
        sr = 48000
    else:
        if language not in QWEN_LANGUAGES: raise ValueError("Unsupported Qwen language")
        chunks = model.generate_custom_voice(text=text, language=QWEN_LANGUAGES[language], speaker=req.get("voice") or "Vivian",
                    max_tokens=1024, temperature=0.7, stream=True, streaming_interval=0.48)
        sr = 24000
    pending = []
    count = 0
    total = 0
    peak = 0.0
    started = time.monotonic()
    def packet(samples):
        audio = np.concatenate(samples)
        if not np.isfinite(audio).all(): raise ValueError("Non-finite audio")
        audio = np.clip(audio * max(0, min(1, float(req.get("volume", 1)))), -1, 1)
        wav = io.BytesIO(); sf.write(wav, audio, sr, format="WAV", subtype="PCM_16")
        return {"wav": base64.b64encode(wav.getvalue()).decode(), "sampleRate": sr, "duration": len(audio) / sr,
                "latencyMs": int((time.monotonic() - started) * 1000)}
    for chunk in chunks:
        audio = np.asarray(chunk if engine == "vieneu" else chunk.audio, dtype=np.float32).reshape(-1)
        if len(audio): peak = max(peak, float(np.max(np.abs(audio))))
        pending.append(audio); count += len(audio); total += len(audio)
        if total > sr * 120: raise ValueError("Oversized audio")
        if count >= sr * 0.48:
            yield packet(pending)
            pending = []; count = 0
    if count: yield packet(pending)
    if total < sr // 10 or not peak >= 0.0001: raise ValueError("Missing or silent audio")


def verify_install(engine, root):
    import hashlib
    marker = json.loads((root / "installed.json").read_text())
    if marker.get("engine") != engine or marker.get("revisions") != [r[1] for r in MODEL_REPOS[engine]]:
        raise ValueError("Incompatible installed model; reinstall required")
    entries = marker.get("files", [])
    if not entries: raise ValueError("Missing integrity manifest")
    for entry in entries:
        path = root / entry["path"]
        if not path.resolve().is_relative_to(root.resolve()) or not path.is_file() or path.stat().st_size != entry["bytes"]:
            raise ValueError("Installed model incomplete; reinstall required")
    # Hash is checked once per worker startup, never in a SwiftUI render or per sentence.
    for entry in entries:
        path = root / entry["path"]
        digest = hashlib.sha256()
        with path.open("rb") as file:
            for block in iter(lambda: file.read(1024 * 1024), b""): digest.update(block)
        if digest.hexdigest() != entry["sha256"]:
            raise ValueError("Model checksum mismatch; reinstall required")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", choices=MODEL_REPOS, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    configure(args.root, args.install)
    protocol = sys.stdout
    # Third-party startup messages must not corrupt the JSON-line protocol.
    with contextlib.redirect_stdout(sys.stderr):
        if args.install: download(args.engine, args.root)
        else: verify_install(args.engine, args.root)
        model, mx = load(args.engine, args.root)
        voice_list = voices(args.engine, model)
        if args.install:
            sample = "Xin chào, chúng ta cùng học nhé." if args.engine == "vieneu" else "你好，我们一起学习吧。"
            result = synthesize(args.engine, model, {"text": sample, "language": "vi" if args.engine == "vieneu" else "zh"})
            import hashlib
            integrity = []
            for path in sorted(args.root.rglob("*")):
                if path.is_file() and not path.is_symlink() and ("assets" in path.parts or "blobs" in path.parts) and ".cache" not in path.parts:
                    digest = hashlib.sha256()
                    with path.open("rb") as file:
                        for block in iter(lambda: file.read(1024 * 1024), b""): digest.update(block)
                    integrity.append({"path": str(path.relative_to(args.root)), "bytes": path.stat().st_size, "sha256": digest.hexdigest()})
            marker = {"schemaVersion": 1, "engine": args.engine, "voices": voice_list, "revisions": [r[1] for r in MODEL_REPOS[args.engine]], "files": integrity,
                      "smokeTest": {k: v for k, v in result.items() if k != "wav"}}
            temp_marker = args.root / "installed.json.tmp"
            temp_marker.write_text(json.dumps(marker, ensure_ascii=False))
            temp_marker.replace(args.root / "installed.json")
            (args.root / "sample.wav").write_bytes(base64.b64decode(result["wav"]))
            print(json.dumps({"installed": True, "engine": args.engine, "smokeTest": marker["smokeTest"]}), file=protocol, flush=True)
            return
    print(json.dumps({"ready": True, "voices": voice_list}), file=protocol, flush=True)
    for line in sys.stdin:
        try:
            req = json.loads(line)
            if req.get("command") == "quit": return
            if req.get("stream") and abs(float(req.get("speed", 1)) - 1) <= 0.02:
                generator = stream_speech(args.engine, model, req)
                while True:
                    with contextlib.redirect_stdout(sys.stderr):
                        result = next(generator, None)
                    if result is None: break
                    result.update(id=req["id"], chunk=True)
                    print(json.dumps(result), file=protocol, flush=True)
                print(json.dumps({"id": req["id"], "done": True}), file=protocol, flush=True)
                if mx: mx.clear_cache()
                continue
            with contextlib.redirect_stdout(sys.stderr): result = synthesize(args.engine, model, req)
            result["id"] = req["id"]
            print(json.dumps(result), file=protocol, flush=True)
            if mx: mx.clear_cache()
        except Exception as exc:
            print(json.dumps({"id": locals().get("req", {}).get("id"), "error": str(exc)[:400]}), file=protocol, flush=True)

if __name__ == "__main__": main()
