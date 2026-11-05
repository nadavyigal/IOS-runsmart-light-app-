# Coach voice choice

Date: 2026-11-05. Status: candidate, waiting for the founder to listen.

- Voice: **Alex - Conversational Business** (ElevenLabs library voice)
- Voice id: `hLygPNd2gK6Azddorc5W`
- Model: `eleven_v4` (supports audio tags)
- Why: warm, confident American male; the library description says it sounds like an experienced coach, not an announcer. It sits between energetic and calm, so one voice can carry all three tones.
- Runner-up for the later second voice: **Carrie: Fun and Professional** (`AEu9YBjNQiyxUMNdplQu`), warm, clear female coach voice.

## Delivery per tone (one audio tag, same for every line of the tone)

| Tone | Tag |
|---|---|
| Motivating | `[energetic]` |
| Calm | `[softly]` |
| Technical | `[matter of fact]` |

No `voice_settings` changes (eleven_v4 has no speed setting; pace comes from tags).

## How clips are generated

One take per tone: all lines of one variant in one prompt, separated by `[long pause]`, `generations_count: 1`. One take keeps the delivery and loudness even across lines. The prepare script splits the take on silence and maps each piece to its line in order; each piece is checked against its text by transcription.

## Cost

Sample round (variant 1 of every line, 3 takes): estimate 1,726 credits, about $0.35 (533 + 558 + 635).

## Open

- Library voices: confirm the ElevenLabs plan allows commercial use of generated audio before clips ship (Task 7).
