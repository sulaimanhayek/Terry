# Terry

A minimal meeting transcriber for macOS. Terry uses Apple's on-device speech recognition, so it works offline, needs no account or API key, and audio never leaves your Mac.

## Features

- **Record anytime.** Press Record in the window (⌘R) or choose Start Transcribing from the menu bar. The transcript appears live as you talk.
- **Meetings.** A small banner offers to transcribe when Zoom, Teams, Meet, FaceTime or another app starts using the microphone. When the call ends, the transcript finishes on its own.
- **Both sides.** Your microphone is labelled **Me**. Other participants are **Them**, captured from your Mac's sound output. Your speakers' sound picked up by the mic is filtered out.
- **Plain files.** Each transcript is a Markdown file in `~/Documents/Terry`. To sync, choose a folder in iCloud Drive or Google Drive in Settings. The files always stay local.
- Light and dark appearance, lives in the menu bar, optional open at login.

## Requirements

macOS 26 or later. Building needs Swift 6.2 or later from Xcode or the Command Line Tools.

## Build

```sh
make run       # build build/Terry.app and open it
make install   # copy it to /Applications
make test      # unit and integration tests
make bench     # CPU while transcribing a meeting in real time
```

Builds are signed ad hoc, so macOS asks for permissions again after each rebuild. To keep them, sign with your identity: `make app SIGN="Apple Development: you@example.com"`.

## Permissions

The first recording asks for:

- **Microphone**, for your voice.
- **System audio recording**, for other participants. You can turn this off in Settings with "Transcribe other participants".
- **Documents folder**, if notes are kept in the default folder.

Meeting detection needs no permission. It only checks which apps are using the microphone and never hears their audio.

If a language's speech model isn't on your Mac yet, macOS downloads it once. After that, transcription works offline.

## Performance

Measured on an M3 MacBook with `make bench` and `top`. One core = 100%.

| | CPU |
|---|---|
| Idle, watching for meetings | 0.0%, no wakeups |
| Transcribing both sides of a meeting | Terry 1.8% + macOS speech service 7% |

## Code layout

```
Sources/Terry/
  App/            launch, menu bar, settings keys
  Audio/          microphone and system-audio capture
  Transcription/  on-device speech recognition, echo filtering
  Notes/          recording sessions, Markdown notes on disk
  Meeting/        meeting detection and the floating banner
  Views/          window, note view, settings
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branch and pull request workflow.
