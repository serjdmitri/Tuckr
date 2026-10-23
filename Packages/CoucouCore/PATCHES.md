# Changes to Coucou's own files

The sources under `Sources/CoucouCore/App` and `Sources/CoucouCore/CoucouKit` are
upstream's, byte for byte, except for the patches below. Everything else this
app adds sits in `CoucouHost.swift` and `AgentsTabView.swift`.

1. `App/IslandViewContent.swift`, `AgentPill`: the name now has 34 points of
   leading padding so a long name (for example "claude-desktop") no longer
   draws over the pill's mini Mochi. `MusicPill` already does the same.
2. `App/HookServer.swift`, turn end for an external agent (Claude Desktop, Gemini
   CLI, ...): upstream removes its pill 5 seconds after the turn ends. The pill
   now settles to idle after 5 seconds and is removed once the agent has been
   unused for the "Hide after" delay (`AppState.absenceInterval`, 3 minutes by
   default, editable in Agents Settings > General). A later event pushes the
   removal back (`lastSeen`).
3. `App/BotCanvasView.swift`, the big Mochi's body color: upstream tints him with
   the focused pill's color for integration pills only, so an external agent
   (Claude Desktop and the like) showed a white Mochi next to its colored pill.
   External agents now tint him too.
4. `App/ClaudeService.swift`, `Keychain.service`: upstream reads its saved keys
   under "fr.louisraille.NotchBuddy". The standalone Coucou's items there are
   not readable by this app, and macOS shows a Keychain prompt for each one
   that freezes the app until answered. This app uses its own service name, so
   the lookups find nothing and never prompt; keys saved from here are read
   back without a prompt.
5. `App/FlowHub.swift`, `FlowHubController.show`: upstream opens the Coucou Flow
   window (dictation, notes, words, settings). This app has none: Talkify does
   the dictation. Notes (the "Open" on the "notes ready" pill) now open the
   Meetings window and everything else opens Agents Settings. The original is
   kept as `showUpstreamHub`.
6. `App/SettingsView.swift`: a Notetaker section (sidebar row, title, content) holding
   the recording pill's position (bottom, left, right) and the summary engine.
   Upstream keeps both on the Coucou Flow settings page, which this app lacks.
   The section itself is `NotetakerSettingsSection.swift`.
7. `App/SettingsView.swift`, Voice page: the Coucou Flow dictation box is left out. A
   second dictation engine on Right Option would compete with Talkify's.
8. `App/BotCanvasView.swift`, `BotCanvasView` and `MiniBotCanvasView`: their
   `TimelineView` takes its minimum frame interval from an environment value
   (`MochiFrameRate.swift`, nil by default, so nothing changes). The closed
   notch's ears set it to 20 frames a second: Mochi's speed does not depend on
   the frame rate, and drawing at the display's rate cost about a quarter of a core.
9. `App/ShortcutsSettingsView.swift`: the global shortcut list shows only the six
   actions this app handles (open/close, go to alert, jump to terminal, next and
   previous pill, mute). The others belong to chat, voice, screen capture and
   the desktop Mochi, which are off here.
10. `App/AppState.swift` and `App/BotCanvasView.swift`: `hostBotAnchor`, a view the host
    places on Mochi; when set, his gaze is measured from it instead of from where
    Coucou's own island would draw him.
11. `App/AppState.swift`, `App/IslandViewContent.swift`: `pinnedId`, `pin(_:)` and `lookAt(_:)`.
    A pinned agent keeps the big Mochi; picking another pill shows it for a few seconds,
    then the big Mochi returns. Pills get a "Pin to the big Mochi" context menu.
12. `App/IslandViewContent.swift`: `AgentPill` shows a sweeping edge and bouncing dots
    (`PillWorkingActivity`) while its agent is mid-turn.
    The edge sweep is stroked arcs, not a conic gradient (a conic fill is shaded on the
    CPU every frame).
    The edge sweep is now a still ring seen through a conic gradient that is drawn once
    and only turned (a repeating rotation), so it is a smooth gradient and costs the CPU
    nothing per frame.
13. Usage (`UsageAlerts.swift`, `AgentUsageView.swift` and `UsageAlertsSettingsSection.swift` are
    added files): `AppState.usageAgentID`; `AgentsTabView` shows a usage page in place of the
    cards and a dots button by the big Mochi; `AgentPill` shows dots on hover (and
    `PillWorkingActivity` hides its dots then) plus a "Usage" menu entry; `SettingsView` gets a
    "Usage alerts" page.
14. `App/HookServer.swift`: a pill that is created after launch (`upsertExternalAgent`,
    `upsertWorkspaceTask`) takes the focus when it is the pinned one, not only when nothing is
    focused. Before, a pinned Claude pill never got the big Mochi because VS Code, the main
    pill, already held it.
