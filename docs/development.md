# Agent Deck: development

Agent Deck is a Tern plugin with a window half only. It shows an "Agents" sidebar on the right edge of every tab
(Tern's Files pane takes the left edge). The user-facing overview is the [README](../README.md).

## Layout

- `plugin.toml`: the manifest (plugin id `agent-deck`, name Agent Deck). Its `styles` lists `agents.css`. The code
  reads the id from `tern.plugin.id` (canvas owners, the status segment's command), so it lives only here.
- `agents.css`: the sidebar's look, a copy of Tern's Files pane drawn with Tern's own variables (`--sf-lh`, `--l1`,
  `--l2`, `--t3`, `--t4`, the accent): the head (glyph, bold title, a ⋯ menu shown on hover, the hide button), the
  Live/Recent strip, and tree rows by role `agents.<kind>.<depth>` (a compact indent: an agent's dot under its
  folder's glyph, deeper levels one 10 px step more; one guide line, hover tint, the focused agent's row tinted with
  the accent bar at the canvas's edge, a folder row's count and `+` shown on hover).
  A canvas takes no `font`, so it sets the canvas (role `agents.root`) in the sans face and keeps paths mono.
- `window.luau`: the window entry. It registers the palette commands ("Toggle Agents sidebar" with key ⌥⌘A, "New
  tab in the focused agent's folder", "Arrange tabs by project", "Pin this agent", "Next waiting agent"), the event
  handlers, the status line and tab title formatters, the 1-second subagent tick, the 1-minute session scan and the
  10-minute redraw that folds agents into "Older".
- `lib/sidebar.luau`: the sidebar manager. It reads the agents from Tern, keeps one canvas on the right edge of every
  tab at the shared width (25% of the tab until the user drags it; a copy left on the left edge by an older version
  moves to the right), hides them all on the toggle or ⌘W on one copy, patches only the copies whose content
  changed, keeps the status line counts, focuses an agent on a row click, opens a new tab in a folder (as Tern's
  own New tab would: a shell or the agent command, by the user's preference), resumes a closed session in a new tab,
  shows a subagent in omp's view, copies a session's ID or path from a row's right-click menu (reading the file's
  header off the UI thread), renames an omp session from Rename (Tern's text field, then omp's `/rename <title>` as
  one `send` event on the composer's field), and toasts an agent that waits or finishes off screen. All Tern calls
  live here, in the store, in the three readers and in the entry. It keeps the `hidden` flag and the shared `width`
  in `tern.kv`.
- `lib/store.luau`: the state in `tern.kv` that every window shares and a restart keeps: the pins, the view the strip
  shows (Live or Recent), the open "Older" rows, the folded folders, the folders open in the Recent view, whether the
  Recent view shows every folder, when each agent was last in a turn and when each working agent began its turn (so
  that a plugin reload does not reset the timers).
- `lib/turns.luau`: the pure turn starts: records a start when an agent enters `working` and drops it when the turn
  ends or the pane is gone, and turns a stored start back into a `tern.now()` (by the wall clock after a Tern
  restart).
- `lib/session_reader.luau`: the session reader. One `tern.process.run` of `/bin/sh` (at most once a minute, and on
  `agent_finished` and an exit) reads the headers of the newest omp session files of each folder in
  `~/.omp/agent/sessions`, their last writes and the ones a process holds open; it keeps the result with each
  session's repo. A second `tern.process.run`, of `tern inspect --json` (with each scan, when an agent appears and
  when an agent's pane retitles itself), reads the session file each pane's omp reported to Tern
  (`omp_session_file`): a live agent's session.
- `lib/sessions.luau`: the pure parser of that scan's output (path, id, working directory, title, last write, open),
  of the `tern inspect` answer (session file by pane) and of a session file's header id.
- `lib/session_copy.luau`: what "Copy session ID" and "Copy session path" copy (the header's id or the file's path)
  and the toast that says so, from the start of the file.
- `lib/subagent_reader.luau`: the subagent reader. On each tick it reads the TSP surface of one working agent, in
  rotation: a find read lists the running `task` tool nodes (again once 5 s passed since that agent's last find read,
  or when a call ended), the reads in between set `root` to each of them.
- `lib/subagents.luau`: pure helpers for the reader: find the running `task` nodes and turn their `agent` nodes, at
  every nesting level, into subagents (node id, name, state, depth, parent, type, effort, model, tool). It uses no
  `if … then … else` expression, so a Carly probe can `loadstring` it.
- `lib/hud.luau`: the pure reader of omp's HUD agents counter in a read of the dock (`…running/agents`): whether the
  session has running subagents, so that the reader polls an idle agent again after a plugin reload.
- `lib/effort_reader.luau`: the effort reader. On `agent_state`, `agent_finished` and at start (never on the tick) it
  reads the effort glyph of an omp agent's composer with one read scoped to that node (the first read is scoped to
  the dock), and keeps the level of each pane.
- `lib/effort.luau`: the pure helper for it: finds the `effort` node with role `omp.composer.model.effort`. No
  `if … then … else` expression either.
- `lib/view_model.luau`: the pure view model. Plain data in (the agents with their reported session files, their
  subagents, the pins, the view, the open Older rows, the folded folders, the open Recent folders, the omp sessions
  and the time); out: the canvas node tree (the head, the view strip, and the Live or the Recent tree, with each
  row's right-click menu), the status line segments, the waiting agents in wait order, and the toast text. It also
  names each tab after its main agent. It uses no `tern` global, so the plain `luau` CLI can load it.
- `lib/placement.luau`: the pure placement plan: from the tabs' split trees, which tabs get a copy (beside the
  top-right pane), which copies close, and which copies need a resize to the shared width.
- `lib/patch.luau`: the pure patch diff: the keyed `cx.canvas:set` patch from the view a copy shows to a new one.
  Keys must not contain `.`: a path cannot name them, so their parent goes whole.
- `lib/providers.luau`: the provider table (model name → provider logo id).
- `lib/back_to_main.luau`: the pure finder of omp's "Back to the main session" action in a read of a pane's dock
  (a node id ending in `focus/exit` with a `focus:` click), which a click on a main agent's row runs.
- `lib/viewing.luau`: pure helpers for omp's subagent view, from a read of a pane's dock: which subagent omp shows,
  the subagent rows kept (frozen) meanwhile, the action a subagent row click sends: `focus:<omp id>` on omp's
  composer node (role `omp.editor`), which shows that subagent from the main session or from another subagent, and
  the `send` event that submits a command in the composer's field (none while omp shows a subagent).
- `lib/rename.luau`: the pure Rename helpers: the title its field starts with, and the `/rename <title>` command for
  the title typed (none for a blank, dismissed or unchanged title).
- `lib/new_tab.luau`: the pure launch of a new tab in a folder: a shell, or the user's agent command when the "New
  tabs and splits open" preference says agent (as Tern's own New tab runs).
- `lib/repo_root.luau`: the repo resolver (working directory → main git repo root; worktrees and ovnfs checkouts
  resolve to their main repo). It reads the file system through the functions it gets, and caches each answer.
- `tests/`: the view-model (rows, the Files look: head, ⋯ menu, view strip, folder rows, tree levels; groups, folded
  folders, pins, exited agents, Older, Recent, Recent folders, Needs you, status counts, toasts, tab titles),
  session-scan, provider-table, new-tab, back-to-main, subagent view and click, repo-resolver, subagent, effort,
  placement, patch, turn-start, copy-session (the menu items of every session row, the copied text, the reported
  session files) and rename (the menu item, when it is off, the command and its `send` event) tests.
  `tests/run.luau` runs them all.
- `types/tern.d.luau`: the Tern API definitions for the type check.

## Run the tests

Install the Luau CLI once with `brew install luau`. Then, from the repo root:

```sh
luau tests/run.luau
```

The command prints one line per test and exits non-zero when a test fails. To add a spec file, `require` it in
`tests/run.luau`.

## Type-check

`luau-analyze` cannot load a definitions file, so the check uses `luau-lsp analyze`, which runs the same analyzer
with the Tern definitions. Install it once: download `luau-lsp-macos.zip` from the
[luau-lsp releases](https://github.com/JohnnyMorganz/luau-lsp/releases) and put `luau-lsp` on your `PATH`. Then:

```sh
luau-lsp analyze --platform=standard --definitions=@tern=types/tern.d.luau window.luau lib tests
```

The command exits non-zero on any type error. After a Tern upgrade, regenerate the definitions with
`tern plugin types types`.

## Link into Tern

```sh
tern plugin link "$PWD"   # from the repo root
tern plugin list   # agent-deck … window  ready
```

Tern reloads the plugin on every save in the linked folder, and every `tern plugin link`, `unlink` and `reload`
reloads all plugins. Link only one checkout: a second one clashes on the plugin id. `tern plugin list` reports the
host catalog only; a window entry that fails to load shows as a toast in the Tern window, and handler errors go to
`~/Library/Logs/Tern/tern.log`.

The plugin keeps its state in `tern.kv`, one file per plugin id: `~/Library/Application Support/Tern/plugin-data/
agent-deck/kv.json`. Unlinking a plugin leaves its sidebar canvases open; a checkout linked under another id opens
its own copies beside them, so close the old ones (`tern close <pane>`) when you switch ids.
