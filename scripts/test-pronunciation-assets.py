#!/usr/bin/env python3
"""Verify source identity, mappings and decodability; never certify pronunciation."""
import hashlib, io, json, re, subprocess, wave, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
pack = ROOT / "Resources/Pronunciation/Zhuyin"
manifest = json.loads((pack / "manifest.json").read_text())
html = (ROOT / "docs/pronunciation/source-review/bopomofo-mapping.html").read_text()
mapping = {}
for row in re.findall(r"<tr>(.*?)</tr>", html, re.S):
    number = re.search(r"play\('a(\d+)'\)", row)
    symbol = re.search(r"zhStroker\('app', '([^']+)'\)", row)
    if number and symbol:
        mapping[number[1]] = symbol[1]
assert len(mapping) == len(manifest["entries"]) == 37
assert manifest["locale"] == "zh-TW" and manifest["license"] == "CC-BY-4.0"
archive_path = ROOT / "docs/pronunciation/source-review/bopomofo_materials_20170213.zip"
assert hashlib.sha256(archive_path.read_bytes()).hexdigest() == manifest["archiveSHA256"]
with zipfile.ZipFile(archive_path) as archive:
    for entry in manifest["entries"]:
        assert mapping[entry["id"]] == entry["symbol"]
        data = (pack / entry["file"]).read_bytes()
        assert data == archive.read(f"audio/F{entry['id']}.WAV"), "Audio was modified"
        assert hashlib.sha256(data).hexdigest() == entry["sha256"]
        with wave.open(io.BytesIO(data)) as audio:
            assert audio.getnchannels() == 2 and audio.getsampwidth() == 2
            assert audio.getframerate() == 44100 and audio.getnframes() > 0
            assert abs(audio.getnframes()/audio.getframerate() - entry["seconds"]) < 0.001
print("PASS: 37 Zhuyin source mappings, byte identity, hashes and PCM WAVs")

review = ROOT / "docs/pronunciation/source-review/japanese-kana"
if (review / "manifest.json").exists():
    kana = json.loads((review / "manifest.json").read_text())
    assert kana["bundled"] is False and len(kana["entries"]) == 46
    assert len({e["hiragana"] for e in kana["entries"]}) == 46
    assert len({e["katakana"] for e in kana["entries"]}) == 46
    for entry in kana["entries"]:
        path = review / entry["file"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"]
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "null", "-"], check=True, capture_output=True)
    assert all("/seion/wo.mp3" in e["sourceURL"] for e in kana["entries"] if e["hiragana"] == "を")
    print("PASS: 46 Kana candidates, hashes, distinct kana and MP3 decode; not approved/bundled")

english = ROOT / "docs/pronunciation/source-review/english-alphabet"
if (english / "manifest.json").exists():
    meta = json.loads((english / "manifest.json").read_text())
    path = english / meta["file"]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == meta["sha256"]
    assert hashlib.sha1(path.read_bytes()).hexdigest() == "0800e5f83eb0fb9874277fc54741b2653f8ada22"
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "null", "-"], check=True, capture_output=True)
    print("PASS: whole English alphabet source checksum and OGG decode; not approved/bundled")
print("Technical checks do not establish phonetic correctness or independent listening approval.")
