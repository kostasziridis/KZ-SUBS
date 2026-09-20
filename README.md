# KZ-SUBS

On-device subtitle generation for iPhone. Swift and SwiftUI only — no backend, no
account, no uploads. Once the speech model is on the device, everything works in
Airplane Mode.

## Requirements

- Xcode 16 or newer (Xcode 27.0 in use here)
- iOS 17.0+ iPhone (physical device required for real speech performance)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — already installed via Homebrew

## Opening the project

The Xcode project is generated from `project.yml`. After changing files or folders:

```bash
cd ~/gitApps/KZ-SUBS && xcodegen generate
```

Then open `KZ-SUBS.xcodeproj`, select your development team under
*Signing & Capabilities*, and run on an iPhone.

## Architecture

MVVM with a strict boundary between UI and processing.

```
Sources/
  App/          App entry point and app-wide state
  Models/       Value types: project, segments, style, language, errors
  ViewModels/   @MainActor @Observable, UI-facing state only
  Services/     Media, storage and persistence work — never @MainActor
  Views/        SwiftUI, organised by screen
  Utilities/    Formatters, theme, logging, preview data
```

Rules the codebase holds to:

- Views never touch AVFoundation, the file system or (later) the speech engine directly.
- Heavy work runs off the main actor; view models only marshal results onto it.
- Imported videos are copies inside the app container. The user's Photos library is
  never modified.
- Project files store *file names*, not absolute paths, so a new app container after
  an update or restore does not orphan a project.

## Status

| Phase | Scope | State |
|-------|-------|-------|
| 1 | Navigation, Home, video picker, preview, playback, metadata | **Done** — builds and verified on simulator |
| 2 | WhisperKit via SPM, speech service | **Done** — Greek and English verified on simulator |
| 3 | Audio extraction → transcription → saved project | **Done** — verified on simulator |
| 4 | Readable segments rendered over the player | **Done** |
| 5 | Playback sync (timeline track still to come) | **Partly done** |
| 6 | Edit text and timing, add and delete | **Done** |
| 7 | SRT export | Not started |
| 8 | Caption styles, colours, karaoke | **Done** |
| 9 | Burned-in video export | Not started |
| 10 | Persistence, errors, polish | Partly in place (storage, project store) |

Phase 1 builds clean (Xcode 27, iOS 27 SDK, no source warnings) and was verified on
the iPhone 17 Pro simulator: video import, orientation-correct metadata, playback,
scrubbing, language selection, the no-audio path and settings all work.

Phase 2 adds WhisperKit 1.1.0 (SPM) behind `WhisperService`. Verified on the
simulator against bundled clips with known wording: English matched word for word,
Greek matched apart from two accepted spelling variants, and word-level timings came
through (12 and 16 words). Simulator inference is CPU-only and took ~19s for a 5s
clip; the Neural Engine on device should be far faster — measure it there.

The model is `openai_whisper-large-v3-v20240930_turbo_632MB`, chosen by
`ModelManager` from the device's supported list. English-only builds are excluded by
name: both the `.en` suffix and the whole `distil-whisper` family, which is
English-only despite carrying no suffix.

A DEBUG-only "Speech check" screen under Settings runs this test on device.

The flow is: choose a video → one-time setup (only when no model is on the device
yet, explaining the size, the rough time and that it happens once) → generating →
choose a style → editor.

Phase 3 joins it up: `AudioExtractor` streams a video's soundtrack to 16 kHz mono
WAV through `AVAssetReader`/`AVAssetWriter` (the video track is never touched and
memory stays flat), `TranscriptionViewModel` drives model prep → extraction →
transcription with cancellation at every step, and `ProcessingView` reports each
stage in its own words. A finished run saves a `SubtitleProject`, so Recent Projects
is now real.

Verified end to end on the simulator with a 16s portrait clip of Greek speech and
the language left on Auto Detect: Greek identified unaided, 5 subtitles on sentence
boundaries, 3 of 5 lines word-perfect, one variant spelling and one compound word
split. 26s of transcription on simulator CPU, reproduced across two runs.

### A warning about testing this on the Simulator

The Simulator has no Neural Engine, so Core ML compiles bulky CPU/GPU variants of
the model on every load and writes them to `Library/Caches/<bundle id>` inside the
app container - roughly 3 GB per run, which reached 6.8 GB here. Fill the disk and
the failures look nothing like their cause: a `SIGBUS` inside libBNNS on
memory-mapped weights, a corrupted simulator dyld cache that stops the app
launching at all, and a `SIGSEGV` inside WhisperKit's tokenizer. All three cleared
up once there was space. Keep several GB free, and clear that cache directory
between runs. On device this does not happen - Core ML targets the Neural Engine
and the artifacts are far smaller.

## Privacy

No account. No login. No backend. No cloud transcription. No analytics. No ads.
The only permission the app requests is adding a finished video to Photos, and only
at the moment the user asks to save one.
