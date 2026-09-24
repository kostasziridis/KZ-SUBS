# KZ-SUBS

On-device subtitle generation for iPhone. Swift and SwiftUI only — no backend, no
account, no uploads. Once the speech model is on the device, everything works in
Airplane Mode.

## Requirements

- Xcode 16 or newer (Xcode 27.0 in use here)
- iOS 18.0+ (raised from 17 so the export can use `export(to:as:)` rather than the
  deprecated `exportAsynchronously`)
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
| 7 | SRT export | **Done** |
| 8 | Caption styles, colours, karaoke | **Done** |
| 9 | Burned-in video export | **Done** |
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

## Languages

The app is in English and Greek, and follows the phone: a Greek iPhone gets Greek,
everything else gets English. There is no setting, because iOS already knows.

Translations live in `Sources/Resources/Localizable.xcstrings`. SwiftUI looks strings
up automatically from a `Text` literal; a plain `String` has to ask, which is what the
`String(localized:)` calls in the enums and error messages are for.

To find strings that have been added since the last pass:

```
xcodebuild -project KZ-SUBS.xcodeproj -scheme KZSubs -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/kzsubs-loc SWIFT_EMIT_LOC_STRINGS=YES build
python3 Tools/tidy-string-catalog.py /tmp/kzsubs-loc
```

That build makes Xcode rewrite the catalogue, and it makes a mess of it - duplicate
keys for anything containing a number, and the real ones marked stale. The script
undoes that and lists whatever still needs Greek. An ordinary build leaves the
catalogue alone, so this is only needed when strings change.

## Spelling

Misspelled words in the subtitle editor get a dotted underline, and tapping one offers
what it was probably meant to be. Correcting a word never moves its timing, so the
styles that light up words one by one keep working.

The editor also counts the suspect words across the whole video and offers them in one
pass - "is this video spelled correctly" must not depend on whether the user happened
to open every subtitle. A suggestion is reshaped to the word it replaces before it is
applied, so «Ολα» becomes «Όλα» rather than «όλα» and «ιντερνετ.» keeps its full stop.
"Keep as it is" is remembered, because a review that asks twice about the same surname
is a review nobody finishes.

Greek carries its own dictionary. iOS lists Greek among its spell-checking languages
but has nothing behind it - it does not flag even pure nonsense, while French, German,
Spanish, Italian and Russian all work - and Apple's on-device language model does not
speak Greek at all (24 languages, none of them `el`). Everything other than Greek goes
to the system checker, which is good.

`Sources/Resources/GreekWords.bin` holds 828,806 words in 1.6 MB. It is built from
`Tools/el_GR.dic` with:

```
python3 Tools/build-greek-dictionary.py
```

That dictionary is el_GR 0.9 from the elspell project, tri-licensed MPL 1.1 / GPL 2.0 /
LGPL 2.1; we use it under the MPL, and Settings → Acknowledgements says so. The copy in
`Tools/` is the unmodified upstream file, kept in the repository so the build is
reproducible and the source stays available as the licence asks.

It only knows whether a word exists. A correctly spelled word in the wrong place - the
mistake speech recognition makes most - looks perfectly fine to it.

## Vocabulary

Settings → Vocabulary holds names the engine would otherwise guess at. They are handed
to it as Whisper's conditioning prompt before it listens, which biases it towards those
spellings - the only way to teach it a name without retraining anything, and the only
correction in the app that happens *before* the mistake rather than after.

It works in any language, Greek included, because it steers the recognition itself
rather than the text that comes out.

The prompt is short: 111 tokens, which is roughly 25-30 Greek words. Whatever does not
fit is dropped from the bottom of the list, so the order on screen is the order of
importance. `WhisperService.vocabularyPrompt` is separated from the tokenizer so the
trimming rule can be tested without loading a 600 MB model.

## Two engines

Settings → Speech engine picks who listens. Both run entirely on the phone.

- **Standard** is Whisper through WhisperKit, as before. It is the only one that can
  use the vocabulary, because it is the only one that takes a prompt.
- **Alternative** is NVIDIA's Parakeet TDT 0.6B v3, converted to Core ML, through
  FluidAudio. Same 25 European languages including Greek. CC-BY-4.0 model, Apache 2.0
  package.

Measured on the bundled Greek clip, in the Simulator, which has no Neural Engine - so
treat the times as a ratio between two CPU runs and nothing more:

| | Standard (Whisper) | Alternative (Parakeet) |
|---|---|---|
| 5s Greek clip | 19.6s | 1.4s |
| Errors | «καινούριο» for «καινούργιο» - both are valid spellings | «όλου» for «όλους», «υποτίτρησμένα» for «υποτιτλισμένα» |
| Word timings | 12 | 12 |
| Download | ~630 MB | ~470 MB |

Parakeet writes `<unk>` where it cannot place a character, and Greek final sigma trips
it - that is where «όλους» lost its ς. Those marks are stripped before anything reaches
a caption, which leaves a word short rather than a caption with `<unk>` in it.

`ParakeetService` is the only file that imports FluidAudio, exactly as `WhisperService`
is the only one that imports WhisperKit. It returns the same `SpeechTranscript`, so
nothing above the services knows which engine ran.

FluidAudio is pinned to 0.13.7: from 0.14 it adds a binary xcframework target whose
release archive does not download, which stops the whole project resolving.

## Liquid Glass

Adopted where it belongs and nowhere else. Liquid Glass is the material of the
navigation layer - bars, toolbars, controls floating over something - and never of the
content layer, so the cards in a scrolling list are deliberately not made of it.

Three places use it: the caption size slider, the play button over the picture, and the
style sheet's own background. `View.floatingGlass(in:interactive:)` in `AppTheme` is the
only place that decides - `glassEffect` on iOS 26 and later, the hand-made translucency
the app always had below that, so nothing changes for iOS 18.

Glass carries its own edge, so the hairline borders went with it. The style sheet stops
overriding its own background on iOS 26: setting it replaced the system's material with
a flat copy of what it used to be.

## Importing subtitles

A video whose subtitles already exist does not need transcribing: the import screen
offers "Import subtitle file" beside Generate, which skips the model download entirely.

The parser is written line by line rather than block by block, because the layout
varies more than the format does: the textbook file puts the number, the timing and the
text on three lines, and plenty of tools put all three on one. Both are read, along with
files that have no blank lines between cues.

`.srt` files arrive in two quite different shapes under the same extension. Most hold a
sentence or two per cue, which are captions already. Some hold a single word per cue -
those are not captions at all, they are word timings, and they are exactly what the
karaoke and spotlight styles need. `SRTImporter` tells them apart by the average words
per cue and keeps the second kind as timings rather than flattening them into one-word
captions, so an imported file can drive word-by-word highlighting the same way the
speech engines do.

Grouping timed words into subtitles is one rule in `SubtitleSegmenter.group`, shared
with the engines - break on a pause, on the end of a sentence, or before a block would
grow past two lines.

### Credits the engine invents

Whisper learned from subtitle files, and most of those name whoever made them. Over
silence or music it will write one of those lines out - "Υπότιτλοι AUTHORWAVE",
"Subtitles by the Amara.org community" - as confidently as it writes real speech. That
confidence is why the engine's own thresholds never catch it: to the model this is not
a guess.

`HallucinatedCredits` removes them on the way out of both engines, judging the text
rather than the engine's confidence, and only recognising what appears in a credit and
nowhere else: a subtitling house's name, or a short line that opens by announcing who
did the subtitling. A sentence that merely mentions subtitles runs longer than a credit
and stays.

It cuts words, not whole subtitles, because the invented line does not always arrive
alone - real output runs it straight into the sentence that follows. The word timings
are cut with it and the subtitle pulled in around what is left, so nothing sits on
screen through the silence the credit came from.

The app also appears in Files, so a subtitle file can be dropped straight into it.
Projects and videos live in Application Support, so the exposed folder holds only what
the user puts there.

### What the export must match

The exported file is drawn from `CaptionBlockView` - the very view the editor previews
- so the design carries over. Two things still had to be made to agree with it.

The editor looks up the *one* subtitle covering a moment and shows that one. The
exporter drew every caption whose time range covered the frame, so a subtitle whose end
ran past its own words - which a speech engine's decoding window will hand back - came
out printed over the two that followed, in a project the editor had shown as clean.
`CaptionRasterizer.separate` now ends each subtitle where the next begins, over whole
subtitles rather than the drawn word frames: cutting the frames alone lets a long
subtitle reclaim the screen between the words of the one replacing it, and the caption
flicks back and forth. The compositor draws the newest matching caption and no more.

`CaptionFlowLayout` measured the words at the width it was proposed and placed them at
the width it was granted. Those differ by the rounding of a size the layout itself
returned, and that fraction is enough to push the last word onto a second line - one the
measured height made no room for, so the video showed it sliced through. Both passes now
break the lines at the proposed width, and the reported width is rounded up so a parent
working in whole pixels cannot hand back less room than the words were measured in.

## Exporting subtitles

The `.srt` file comes in the two shapes the format is used for. Whole subtitles is what
a player expects. One word at a time keeps every word's own timing, which is the only
form that survives into word-by-word captions somewhere else - and the same shape the
importer reads back.

The choice defaults to whichever the project is using: a style that lights up words one
by one is built from word timings, and writing whole sentences would throw away exactly
those. The two files are named apart, so both can be made and told apart afterwards.

A subtitle written by hand has no word timings, so it is written as one cue in either
shape rather than split on spaces with invented ones.

## Undo

The editor keeps whole snapshots of the subtitles rather than an inverse of each
operation - a few hundred small structs cost almost nothing to copy, and a snapshot
cannot drift out of step with the edits the way a hand-written undo eventually does.

Edits that belong together share a coalescing key, so typing a word leaves one undo step
rather than one per keystroke. A deletion or a spelling correction passes no key,
because each of those is a decision of its own. Caption style is deliberately not
covered: dragging and pinching are continuous, and snapshotting them would fill the
stack with noise.

## Privacy

No account. No login. No backend. No cloud transcription. No analytics. No ads.
The only permission the app requests is adding a finished video to Photos, and only
at the moment the user asks to save one.
