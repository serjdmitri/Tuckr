# The BoringCoucouify

One notch app for the Mac, made of three open-source projects:

| Tab / feature | What it does | From |
| --- | --- | --- |
| **Home** | Music (Spotify, Apple Music), calendar, mirror, battery and volume HUDs | [Boring Notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0) — the base app |
| **Shelf** | Three panels: AirDrop and share, file shelf, drop-to-transcribe | Boring Notch, plus Talkify's transcription |
| **Agents** | Live cards for Claude Code, Codex, Gemini CLI, Cursor and others, approvals and questions in the notch, Mochi, plan-usage pill, global shortcuts | [Coucou](https://github.com/Louis-CFM/coucou) (MIT) |
| **Meetings** | Call recorder with local transcription and a summary | Coucou's Notetaker |
| **Dictation** | Hold Fn to dictate into any app, read aloud, a HUD that takes over the notch while it works, a keyboard board to change shortcuts | [Talkify](https://github.com/tornikegomareli/Talkify) (MIT) |

The closed notch shows music on the left and the agent Mochi on the right. Hovering the left half opens Home, the right half opens Agents. Agent pills hide after 3 minutes of inactivity (changeable in Settings → Agents → General).

This is a personal-use build. It is not released, notarized or supported.

## Requirements

- macOS 26 or later (the deployment target), a Mac with a notch works best
- Xcode with the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`)
- About 650 MB of disk for the Parakeet speech models, downloaded on first use of Meetings or Dictation (shared with a standalone Coucou if you have one)

## Build and install

```bash
scripts/install.sh              # Release build, sign, copy to /Applications, launch
scripts/install.sh --no-launch  # same, without launching
```

The result is `/Applications/The BoringCoucouify.app`. The build is signed in two steps (ad hoc build, then re-signed inside out) because the hardened runtime is off: it makes macOS refuse the vendored MediaRemoteAdapter framework.

### Signing, so permissions stay granted

macOS ties Accessibility and Input Monitoring to the code signature. Create a local self-signed certificate named `TheBoringCoucouify Local Signing` once (steps in [docs/SIGNING.md](docs/SIGNING.md)); `install.sh` finds it and every later install keeps your permissions. Without it the app is signed ad hoc and you re-grant permissions after each install.

### Permissions

- **Accessibility and Input Monitoring** — Fn dictation and global shortcuts
- **Microphone** and **Audio capture** — dictation and the call recorder
- **Calendar** — the Home calendar
- **Automation / media** — music controls

If Fn stops working after a reinstall, run `tccutil reset Accessibility` and grant it again.

## Settings

One home: the Boring Notch settings window, with Dictation, Agents and Meetings pages hosted inside it. The menu bar icon can be switched off there.

## Agents

Coucou's hook server listens on `~/Library/Application Support/NotchBuddy/nb.sock`; the hook relay is `nb-hook` in the same folder. If you already had Coucou installed, your Claude hooks keep working with no changes. Other agents (Codex, Gemini CLI, Cursor, Copilot and more) are installed from Settings → Agents, which shows a preview of the file it will write before it writes anything.

Global shortcuts (Settings → Agents → Shortcuts), the ones this app handles: open or close the Agents tab (off by default, ⌘⇧N), go to alert ⌃⌥A, jump to terminal ⌃⌥T, next and previous pill ⌃⌥] and ⌃⌥[, mute Mochi ⌃⌥M.

Pills are kept in memory, so restarting the app clears them until each agent sends its next event.

## Repository layout

| Path | What |
| --- | --- |
| `boringNotch/` | The app target: Boring Notch plus the changes listed below |
| `boringNotch/Talkify/` | Talkify's sources, compiled into the app (a synchronized Xcode group) |
| `Packages/CoucouCore/` | Coucou as a local Swift package; `CoucouHost.swift`, `AgentsTabView.swift`, `MeetingsTabView.swift` and `NotetakerSettingsSection.swift` are the added glue |
| `Packages/CoucouCore/PATCHES.md` | Every change made to Coucou's own files |
| `UPSTREAM.md` | The upstream commit each part was taken from |
| `scripts/` | `install.sh`, and `make-icon.swift` which renders the app icon set |
| `docs/` | Signing guide and the original Boring Notch README |
| `licenses/`, `THIRD_PARTY_LICENSES` | Licenses of the parts |

Notes for working in the code:

- The Xcode project lists files explicitly; a new file must be added to `project.pbxproj`, except inside `boringNotch/Talkify`.
- Talkify is built in Swift 5 mode inside the app target; Coucou is a Swift 6 package. Talkify's entry point is replaced by `TalkifyRuntime`, and three names were changed to avoid collisions (`TalkifyRuntime`, `TalkifySettingsView`, `TalkifySettingsWindowController`).
- Talkify's Sparkle updater is never started, and the app is not sandboxed.

## Licensing

The combined app is distributed under GPL-3.0 because of Boring Notch (see `LICENSE`). Talkify and Coucou are MIT; their licenses are in `licenses/`. Not everything is free to redistribute: Coucou's name, the Mochi character and its sounds are not MIT (`licenses/Coucou/LICENSE-ASSETS.md`), Talkify's Pop sounds are CC-BY-NC, and one Siri-style image in Talkify has no license. That is fine for personal use and has to be sorted out before any public release.
