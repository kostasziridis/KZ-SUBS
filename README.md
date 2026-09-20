# KZ-SUBS

On-device subtitle generation for iPhone. Swift and SwiftUI only — no backend, no
account, no uploads. Once the speech model is on the device, everything works in
Airplane Mode.

## Requirements

- Xcode 16 or newer (not currently installed on this Mac — see *Status* below)
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
| 1 | Navigation, Home, video picker, preview, playback, metadata | Code complete, **not yet compiled** |
| 2 | WhisperKit via SPM, speech service | Not started |
| 3 | Audio extraction | Not started |
| 4 | Timestamps → subtitle segments over the player | Not started |
| 5 | Subtitle timeline | Not started |
| 6 | Subtitle editing | Not started |
| 7 | SRT export | Not started |
| 8 | Caption style editor | Not started |
| 9 | Burned-in video export | Not started |
| 10 | Persistence, errors, polish | Partly in place (storage, project store) |

Phase 1 has not been built or run: Xcode is not installed on this machine, so there
is no iOS SDK to compile against. Every file parses cleanly, but nothing has been
type-checked. Install Xcode, then build before trusting any of it.

## Privacy

No account. No login. No backend. No cloud transcription. No analytics. No ads.
The only permission the app requests is adding a finished video to Photos, and only
at the moment the user asks to save one.
