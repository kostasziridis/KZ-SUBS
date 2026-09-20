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
| 3 | Audio extraction | Not started |
| 4 | Timestamps → subtitle segments over the player | Not started |
| 5 | Subtitle timeline | Not started |
| 6 | Subtitle editing | Not started |
| 7 | SRT export | Not started |
| 8 | Caption style editor | Not started |
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

## Privacy

No account. No login. No backend. No cloud transcription. No analytics. No ads.
The only permission the app requests is adding a finished video to Photos, and only
at the moment the user asks to save one.
