# Open-source TTS options to replace ElevenLabs

Date: 2026-11-05. Status: research done, waiting for the founder to pick a model.

**Recommendation: VoxCPM2 (OpenBMB/VoxCPM).** Apache-2.0 for both code and weights, 41k stars, pushed today, Hebrew built in, runs on Apple Silicon. Runner-up: Chatterbox Multilingual (MIT, Hebrew), but it is retired and unmaintained.

## What the founder needs

- Natural English coach voice with three deliveries: energetic, calm, matter-of-fact.
- Hebrew support (cues stay English this version; Hebrew is weighed for later).
- High GitHub stars.
- A license that allows bundling generated audio in a paid iOS app: **both** the code and the model weights.
- Runs on the founder's Mac (Apple Silicon) to pre-render clips offline. On-device iOS is a bonus.

## How this was checked

All numbers below were read live on 2026-11-05: GitHub stars, license and last push via `gh api repos/...`; weight licenses and languages via the Hugging Face model API (`huggingface.co/api/models/...`); README and LICENSE text via `gh api`. The GitHub MCP was down, so `gh` CLI was used. Nothing was installed or downloaded.

Hebrew quality numbers are **self-reported by the model authors**, not checked by ear. Only a listening test settles quality.

## Ranked: usable for a paid app

| # | Repo | Stars | Last push | Code license | Weights license | Hebrew | Mac setup | Voice and delivery notes | License trap |
|---|---|---|---|---|---|---|---|---|---|
| 1 | [OpenBMB/VoxCPM](https://github.com/OpenBMB/VoxCPM) (VoxCPM2) | 41,086 | 2026-11-05 | Apache-2.0 | Apache-2.0 (`openbmb/VoxCPM2`) | Yes, native. Authors report Hebrew CER 2.98% (Fish S2-Pro: 15.27%) | Low-medium: `pip install voxcpm`, MPS used automatically on Apple Silicon. Weights 4.96 GB. MLX ports (`mlx-community/VoxCPM2-8bit`, Apache-2.0) also exist | 2B model, 48 kHz. **Voice Design**: make a new voice from a text description, no recording needed. **Controllable cloning**: keep one voice and add `(energetic, upbeat)` style hints, which maps cleanly to our three tones | None found in the license. The model card asks for "thorough testing" before production. Hebrew score is self-reported |
| 2 | [resemble-ai/chatterbox](https://github.com/resemble-ai/chatterbox) (Multilingual V3) | 27,583 | 2026-11-04 | MIT | MIT (`ResembleAI/chatterbox`, `mlx-community/chatterbox-multilingual-v3`) | Yes, one of 23 languages. No published Hebrew score | Low: `pip install`, ships `example_for_mac.py` using MPS; MLX port exists | 0.5B model. `exaggeration` knob sets energy (calm to energetic). Needs a reference voice clip to clone | **Retired research since August 2026, no maintenance or fixes.** The reference clip must be a voice we own the rights to. Every file carries an invisible Perth watermark (harmless for us) |
| 3 | [QwenLM/Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) | 14,228 | 2026-03-17 | Apache-2.0 | Apache-2.0 (`Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign`) | **No.** 10 languages, no Hebrew | Low: MLX build in `mlx-audio` | Strong English with natural-language instructions for emotion and pace. Best English-only pick | None found. Fails the Hebrew need |
| 4 | [hexgrad/kokoro](https://github.com/hexgrad/kokoro) (Kokoro-82M) | 9,922 | 2025-08-06 | Apache-2.0 | Apache-2.0 | **No** in the official model. A Hebrew fine-tune exists but is non-commercial (row in the Hebrew table) | Very low: 82M model, MLX build, fast | Clean English, but no emotion control: one flat delivery per voice. Small enough to run on iPhone | Official model is clean. The Hebrew fine-tune is not |
| 5 | [KittenML/KittenTTS](https://github.com/KittenML/KittenTTS) | 16,802 | 2026-10-27 | Apache-2.0 | Apache-2.0 | No | Very low, tiny model | Built for size, not warmth. Below the "human coach" bar | None |

## Rejected: license blocks a paid app, or not a fit

| Repo | Stars | Code license | Weights license | Hebrew | Why rejected |
|---|---|---|---|---|---|
| [microsoft/VibeVoice](https://github.com/microsoft/VibeVoice) | 55,493 | MIT | MIT | No (TTS weights en/zh) | MIT, but Microsoft's README says it does not recommend it for commercial or real-world use. No Hebrew |
| [coqui-ai/TTS](https://github.com/coqui-ai/TTS) (XTTS-v2) | 46,184 | MPL-2.0 | Coqui Public Model License: **non-commercial** | No | Trap: code is open, weights are non-commercial, and Coqui shut down so no commercial license can be bought. Repo last pushed 2024-08 |
| [2noise/ChatTTS](https://github.com/2noise/ChatTTS) | 39,988 | AGPL-3.0 | **CC BY-NC 4.0** | No | Weights non-commercial |
| [suno-ai/bark](https://github.com/suno-ai/bark) | 39,310 | MIT | MIT | No | Unmaintained since 2024-08, unstable output, no Hebrew |
| [myshell-ai/OpenVoice](https://github.com/myshell-ai/OpenVoice) | 38,140 | MIT | MIT | No | No Hebrew, no push since 2025-04 |
| [fishaudio/fish-speech](https://github.com/fishaudio/fish-speech) | 33,595 | Fish Audio Community License | S2-Pro: Fish Audio **Research** License | Listed, weak (authors of VoxCPM measured 15.27% CER) | Trap: commercial use only while total company revenue is under USD 500,000, then a paid license is required. S2-Pro weights are research-only |
| [index-tts/index-tts](https://github.com/index-tts/index-tts) | 24,953 | Custom (bilibili) | Custom | No (en/zh) | Custom license, no Hebrew |
| [nari-labs/dia](https://github.com/nari-labs/dia) | 19,408 | Apache-2.0 | Apache-2.0 | No | English only, built for two-person dialogue |
| [SWivid/F5-TTS](https://github.com/SWivid/F5-TTS) | 15,517 | MIT | **CC BY-NC 4.0** | No | Trap: MIT code, non-commercial weights |
| [Zyphra/Zonos](https://github.com/Zyphra/Zonos) | 7,240 | Apache-2.0 | Apache-2.0 | No | Good emotion control, but no Hebrew and no push since 2025-03 |
| [canopyai/Orpheus-TTS](https://github.com/canopyai/Orpheus-TTS) | 6,394 | Apache-2.0 | Apache-2.0, gated | No | English only, gated download |

## Hebrew-specific projects

Key finding: **every dedicated Hebrew voice model found is non-commercial or unlicensed.** Most are trained on SASPEECH (the Robo-Shaul dataset from Kan 11), whose license says "You may not make use of the Dataset for commercial or broadcast needs" (openslr.org/134). Commercial Hebrew today comes only from general multilingual models with open weights: VoxCPM2 and Chatterbox.

| Repo | Stars | License | Usable in a paid app? | Notes |
|---|---|---|---|---|
| [phonikud/phonikud](https://github.com/phonikud/phonikud) | 123 | CC BY 4.0 | **Yes, with attribution** | Not a voice. Adds Hebrew vowel marks and phonemes to plain text. Useful later as a front-end if a model misreads Hebrew words |
| [slp-rl/HebTTS](https://github.com/slp-rl/HebTTS) | 112 | **No license file** | No | No license means no permission. Trained on HebDB (CC BY 4.0), but the code and weights themselves are not licensed |
| [thewh1teagle/israwave](https://github.com/thewh1teagle/israwave) | 42 | None stated | No | Trained on SASPEECH (non-commercial) |
| [thewh1teagle/phonikud-chatterbox](https://github.com/thewh1teagle/phonikud-chatterbox) | 15 | None stated | No as-is | Chatterbox plus Phonikud. Shows the pairing works; we could rebuild it from the two licensed parts |
| [phonikud/phonikud-tts](https://github.com/phonikud/phonikud-tts) | 13 | CC BY-NC 4.0 plus academic-only | No | Says "Commercial use and non-academic non-commercial use are not permitted" |
| [avri-schneider/kokoro-hebrew](https://github.com/avri-schneider/kokoro-hebrew) | 7 | Code MIT, weights gated non-commercial | No | Trap: MIT repo, non-commercial weights (SASPEECH) |
| `facebook/mms-tts-heb` (Hugging Face) | n/a | CC BY-NC 4.0 | No | Non-commercial and robotic |

## Recommendation

**Use VoxCPM2 for the coach clips.**

1. **License is clean end to end.** Apache-2.0 on code and on the weights we would download. No revenue cap, no research-only clause.
2. **It is the only maintained option that meets every need.** Chatterbox also has MIT weights and Hebrew, but it was retired in August 2026 and gets no fixes.
3. **Three deliveries map directly.** Design one coach voice from a description (no real person cloned, so no voice rights issue), then render each tone with a style hint: `(energetic, upbeat)`, `(calm, soft)`, `(neutral, matter-of-fact)`. Same voice, three deliveries, like the ElevenLabs tag plan.
4. **Hebrew is native,** with the best self-reported Hebrew score of the models checked. Hebrew cues stay out of this version unless the founder decides otherwise.
5. **Runs on the founder's Mac** (MPS or MLX). 104 short clips render offline in minutes. No API key, no per-clip cost.

Risks to check in the sample round:
- Quality claims are the authors' own. Judge by ear against the Apple voice.
- Voice Design picks a new voice each time. Lock the voice by saving one good render and using it as the reference for every later clip, with a fixed seed.
- 5 GB download and a Python setup on the Mac. Needs the founder's yes before install.

If VoxCPM2 fails the listening test: try Chatterbox Multilingual next (same license class, Hebrew), then Qwen3-TTS if Hebrew is dropped.
