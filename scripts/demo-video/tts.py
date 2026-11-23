#!/usr/bin/env python3
"""用 ElevenLabs 为每个场景生成旁白（带逐字时间戳，用于字幕）。

token 读自 ~/.config/elevenlabs/token；输出到 build/demo-video/audio/<id>.mp3 与 <id>.json。
用法：python3 -I tts.py voices                 列出可用音色
      python3 -I tts.py gen <voice_id> [ids…]   生成（文本没变的场景跳过）
"""
import base64, hashlib, json, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / "build" / "demo-video" / "audio"
TOKEN = (Path.home() / ".config/elevenlabs/token").read_text().strip()
MODEL = "eleven_multilingual_v2"


def api(path, body=None):
    req = urllib.request.Request("https://api.elevenlabs.io" + path, method="POST" if body else "GET",
                                 headers={"xi-api-key": TOKEN, "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body else None)
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def voices():
    for v in api("/v1/voices")["voices"]:
        labels = v.get("labels") or {}
        print(v["voice_id"], v["name"], v.get("category"), labels.get("gender"), labels.get("accent"), labels.get("language"))


def gen(voice, only):
    OUT.mkdir(parents=True, exist_ok=True)
    scenes = json.loads((HERE / "scenes.json").read_text())
    for s in scenes:
        if only and s["id"] not in only:
            continue
        key = hashlib.sha1(f"{voice}|{MODEL}|{s['vo']}".encode()).hexdigest()[:12]
        meta = OUT / f"{s['id']}.json"
        if meta.exists() and json.loads(meta.read_text()).get("key") == key and not only:
            print("skip", s["id"]); continue
        r = api(f"/v1/text-to-speech/{voice}/with-timestamps?output_format=mp3_44100_192", dict(
            text=s["vo"], model_id=MODEL, language_code="zh",
            voice_settings=dict(stability=0.5, similarity_boost=0.8, style=0.15, use_speaker_boost=True, speed=1.05)))
        (OUT / f"{s['id']}.mp3").write_bytes(base64.b64decode(r["audio_base64"]))
        a = r["alignment"]
        meta.write_text(json.dumps(dict(key=key, text=s["vo"], chars=a["characters"], start=a["character_start_times_seconds"],
                                        end=a["character_end_times_seconds"]), ensure_ascii=False))
        print("ok", s["id"], round(a["character_end_times_seconds"][-1], 2), "s")


if __name__ == "__main__":
    if sys.argv[1] == "voices":
        voices()
    else:
        gen(sys.argv[2], sys.argv[3:])
