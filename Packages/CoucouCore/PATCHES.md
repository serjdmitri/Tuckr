# Changes to Coucou's own files

The sources under `Sources/CoucouCore/App` and `Sources/CoucouCore/CoucouKit` are
upstream's, byte for byte, except for the patches below. Everything else this
app adds sits in `CoucouHost.swift` and `AgentsTabView.swift`.

1. `App/IslandViewContent.swift`, `AgentPill`: the name now has 34 points of
   leading padding so a long name (for example "claude-desktop") no longer
   draws over the pill's mini Mochi. `MusicPill` already does the same.
