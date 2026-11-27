# Agent Deck: development

Agent Deck is a Tern plugin with a window half only. It shows an "Agents" sidebar on the right edge of every tab
(Tern's Files pane takes the left edge). The user-facing overview is the [README](../README.md).

## Layout

- `plugin.toml`: the manifest (plugin id `agent-deck`, name Agent Deck). Its `styles` lists `agents.css`. The code
  reads the id from `tern.plugin.id` (canvas owners, the status segment's command), so it lives only here.
- `agents.css`: the sidebar's look, drawn only with Tern's theme variables (`--t1`..`--t4`, `--l1`..`--l3`, `--live`,
  `--warn`, `--ok`, `--bad`, `--accent`, `--r-chip`, `--r-card`, `--sans`, `--mono`, `--ease`), so that a theme
  recolors it and makes it square or round. It styles nodes by role (Tern draws a node's `role` as `data-role`): the
  head (`agents.chrome`: the Live/Recent switch and the quota line), the zones (`agents.zone`, `agents.head`, the
  zone square `agents.square.<state>`), the project labels (`agents.label`, `agents.rule`), the rows by role
  `agents.<kind>.<depth>`, the title icon in its state's color (`agents.glyph.<state>`), the subagent strip
  (`agents.strip` with one `agents.bar.running` per running subagent, or `agents.tally`, "N subagents", while none
  runs but some wait or are queued; no strip when every subagent finished), the Needs you cards (`agents.card`), and this tab's agent
  (`agents.mine`, the only use of the accent besides keyboard focus). State colors: working and running `--live`,
  waiting `--warn`, done `--ok`, failed `--bad`, idle `--t3`, stopped and frozen `--t4`. All motion stops under the
  system's reduced motion and Tern's Reduce motion setting. A canvas takes no `font`, so it sets the canvas (role
  `agents.root`) in the sans face and keeps machine strings mono.
- `window.luau`: the window entry. It registers the palette commands ("Toggle Agents sidebar" with key ⌥⌘A, "New
  tab in the focused agent's folder", "Arrange tabs by project", "Pin this agent", "Next waiting agent"), the event
  handlers (also the canvas actions: open or close subagent lines, the Older and Earlier folds, the view), the status
  line and tab title formatters, the 1-second subagent tick and the 1-minute session scan.
- `lib/sidebar.luau`: the sidebar manager. It reads the agents from Tern, keeps one canvas on the right edge of every
  tab at the shared width (25% of the tab until the user drags it; a copy left on the left edge by an older version
  moves to the right), hides them all on the toggle or ⌘W on one copy, patches only the copies whose content
  changed, keeps the status line counts, focuses an agent on a row click, opens a new tab in a folder (as Tern's
  own New tab would: a shell or the agent command, by the user's preference), resumes a closed session in a new tab,
  shows a subagent in omp's view, copies a session's ID or path from a row's right-click menu (reading the file's
  header off the UI thread), renames an omp session from Rename (Tern's text field, then omp's `/rename <title>` as
  one `send` event on the composer's field), and toasts an agent that waits or finishes off screen. With each session scan it starts the quota read and the credential read,
  and it gives the view model the quotas and the costs. It redraws when a shown time changes (`viewModel.redrawDue`). All Tern calls
  live here, in the store, in the three readers and in the entry. It keeps the `hidden` flag and the shared `width`
  in `tern.kv`.
- `lib/store.luau`: the state in `tern.kv` that every window shares and a restart keeps: the pins, the view the strip
  shows (Live or Recent), the open subagent lines of each agent (`subs-open`), the Older and Earlier folds
  (`older-open`, `earlier-open`), when each agent was last in a turn and when each working agent began its turn (so
  that a plugin reload does not reset the timers). Once per VM it removes the keys the sidebar no longer uses.
- `lib/turns.luau`: the pure turn starts: records a start when an agent enters `working` and drops it when the turn
  ends or the pane is gone, and turns a stored start back into a `tern.now()` (by the wall clock after a Tern
  restart).
- `lib/session_reader.luau`: the session reader. One `tern.process.run` of `/bin/sh` (at most once a minute, and on
  `agent_finished` and an exit) reads the headers of the newest omp session files of each folder in
  `~/.omp/agent/sessions`, their last writes and the ones a process holds open; it keeps the result with each
  session's repo. A second `tern.process.run`, of `tern inspect --json` (with each scan, when an agent appears and
  when an agent's pane retitles itself), reads the session file each pane's omp reported to Tern
  (`omp_session_file`): a live agent's session. After each of those reads, one `grep` and `sed` over the reported
  files reads their `model_change` entries and the model of each assistant message; the last one in each file is the
  main agent's model as `provider/model`, which its hover card shows. With them, the cost reader reads what those
  sessions cost.
- `lib/cost_reader.luau`: the cost reader. A read-only query of omp's `agent.db` (`sqlite3 -readonly`, with each
  scan; only `id`, `provider` and `credential_type` of `auth_credentials`) gives each credential's type. With the
  model read, one `find` and `stat` lists the reported session files and every file in their session folders (the
  subagents', at any depth), and one `tail`, `head` and `awk` per file that grew reads only the bytes after the
  offset kept for it: the `usage.cost.total` and `credentialId` of each assistant message. The running totals per
  file give each live session's cost: `api_key` credentials as money spent, `oauth` ones as subscription use. A
  failed query or read shows no cost.
- `lib/quota_reader.luau`: the quota reader. With each session scan, one read-only query of omp's `agent.db`
  (`sqlite3 -readonly`, 5 s timeout) selects the latest `usage_history` row of each account and limit; it prints no
  `account_key`. A failed, slow or unknown answer gives no quotas, so no quota line.
- `lib/quotas.luau`: the pure parser of that query's output (provider, email, window, label, use, status, reset).
  It drops stale resets and unknown statuses, names providers (anthropic → Claude, xai → Grok,
  google-antigravity → Gemini) and windows (`7 Day` → `7d`), and takes the account from the email.
- `lib/costs.luau`: the pure parser of those outputs (credential types, file sizes, the cost records of each read,
  a line the read cut counted on the next read) and the sum of a session's cost.
- `lib/sessions.luau`: the pure parser of that scan's output (path, id, working directory, title, last write, open),
  of the `tern inspect` answer (session file by pane), of the `model_change` entries (model by file) and of a
  session file's header id.
- `lib/session_copy.luau`: what "Copy session ID" and "Copy session path" copy (the header's id or the file's path)
  and the toast that says so, from the start of the file.
- `lib/summaries.luau`: the summary reader. For each main agent with a long last message (280 characters or more),
  one `omp -p --model @smol` run (no tools, extensions, skills, rules, context files or session; about 4 s, 8 s when
  the answer needs shortening) writes a short summary for its hover card. A working agent's message is summarized
  once it stayed the same 15 s; until a new summary arrives, the card shows the pane's summary before. The
  summaries live in `tern.kv`, shared by every window; one run at a time.
- `lib/subagent_reader.luau`: the subagent reader. On each tick it reads the dock of one polled agent (working, or
  idle with a running subagent), in rotation, with one read scoped to the dock: the subagents come from omp's tray
  there, and the read also tells which subagent omp shows. An unpolled live agent has its dock checked every 5 s, one
  a tick, so that an idle agent whose subagents still run is found, also after a plugin reload. While omp shows a
  subagent and the read has no tray, the last rows stay, frozen.
- `lib/subagents.luau`: pure helpers for the reader: turn the tray's agent cards (`omp.tray.card`, `item = "agent"`)
  into subagents. omp lists every subagent of its registry there, at every nesting level, so an agent that runs
  again after its `task` call ended (a message revived or woke it) shows as running. The card's omp id (`Anna.Bob`)
  gives the depth and the parent; the card gives the state, `waiting`, the type (from `aria`), the model id with the
  effort (`omp.tray.model`) and what it does now (`omp.tray.call`). It uses no `if … then … else` expression, so a
  Carly probe can `loadstring` it. The tray shows while Tern's "agents tray" setting is on (the default); with it
  off, omp draws no tray and the sidebar shows no subagents.
- `lib/effort_reader.luau`: the effort reader. On `agent_state`, `agent_finished` and at start (never on the tick) it
  reads the effort glyph of an omp agent's composer with one read scoped to that node (the first read is scoped to
  the dock), and keeps the level of each pane.
- `lib/effort.luau`: the pure helper for it: finds the `effort` node with role `omp.composer.model.effort`. No
  `if … then … else` expression either.
- `lib/view_model.luau`: the pure view model. Plain data in (the agents with their reported session files, their
  subagents, the pins, the view, the open subagent lines, the Older and Earlier folds, the omp sessions, the cost of
  each session file, the quotas and the time); out: the canvas node tree, the status line segments, the waiting
  agents in wait order, the toast text and `redrawDue` (the milliseconds until a shown time or a quota's reset text
  changes). The Live tree is the zones Needs you (cards, longest wait first), Working and Idle (agents under project
  labels, the pins first in pin order, then the others in start order, so that times and the focus move no row; idle
  agents older than a day folded, but for the pins); the Recent tree is days (Today, Yesterday, This week, Earlier) with
  project labels. Each row carries its hover card (state, tab, title, summary, facts, cost lines, subagent counts,
  hint) and its right-click menu. It also names each tab after its main agent. It uses no `tern` global, so the plain
  `luau` CLI can load it.
- `lib/placement.luau`: the pure placement plan: from the tabs' split trees, which tabs get a copy (beside the
  top-right pane), which copies close, and which copies need a resize to the shared width.
- `lib/patch.luau`: the pure patch diff: the keyed `cx.canvas:set` patch from the view a copy shows to a new one.
  Keys must not contain `.`: a path cannot name them, so their parent goes whole.
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
- `tests/`: one spec per area. View model, read through `tests/visible.luau` (the rows, zones, state parts and hover
  cards a user sees): `view_model`, `live_zones`, `needs_you`, `row_chips`, `state_colors`, `subagent_strip`,
  `hover_card`, `cost_card`, `quota_line`, `recent`, `pins`, `tab_titles`, `turns`, `viewing`, `show_subagent`,
  `back_to_main`, `copy_session`, `rename`, `new_tab`. Pure parsers and helpers: `sessions`, `subagents`,
  `subagent_reader`, `effort`, `costs`, `cost_reader`, `quotas`, `quota_reader`, `repo_root`, `placement`, `patch`.
  `tests/harness.luau` is the test harness and `tests/canvas.luau` a stand-in canvas that applies a patch. `tests/run.luau` runs them
  all.
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
