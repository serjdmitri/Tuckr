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
