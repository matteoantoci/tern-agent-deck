--!strict
-- The pure view model: turns the agent list into the sidebar's canvas node tree.
-- Calls no Tern API, so the plain `luau` CLI can load and test it.

local subagents = require("./subagents")
local viewing = require("./viewing")

local viewModel = {}

export type Node = { k: string, p: { [string]: any }?, c: { Node }? }

export type AgentState = "working" | "waiting_input" | "idle" | "exited"

--- One agent, as plain data: the entry fills it from `cx.agents:list()` and the pane and tab it runs in.
export type Agent = {
	pane: number,
	state: AgentState,
	--- The pane title as Tern gives it (omp starts it with an icon character and a space).
	title: string?,
	--- The tab the agent's pane sits in (nil when parked) and the name the user gave that tab.
	tab: number?,
	tabName: string?,
	cwd: string?,
	--- The model as Tern shows it; may end in a thinking-level glyph.
	model: string?,
	--- The model as omp's session file names it (`provider/model`); nil for an agent that is not omp or whose
	--- session file was not read yet. The hover card shows it rather than `model`.
	route: string?,
	--- The thinking-effort level of omp's composer (`off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, or
	--- `auto` before it resolves); nil for an agent that shows none.
	effort: string?,
	--- The agent's last assistant message (Markdown).
	lastMessage: string?,
	--- A short summary of `lastMessage` by omp's light model, when the message is long; nil until it arrives.
	summary: string?,
	--- Whether a run is making the summary of `lastMessage` now.
	summarizing: boolean?,
	--- `tern.now()` when the agent began its current turn; the timer counts from here.
	workingSince: number?,
	--- The root of the agent's main git repo (worktrees and ovnfs checkouts resolve to their main repo); nil when
	--- the agent works outside a git repo.
	repo: string?,
	--- `os.time()` of the agent's last turn; nil for an agent never seen active, which counts as new.
	activeAt: number?,
	--- The omp session file the agent's omp reported to Tern (`omp_session_file` in `tern inspect`); nil for an agent
	--- that reported none (not omp, or not read yet).
	sessionFile: string?,
}

--- A pinned agent, as `tern.kv` keeps it: the pane id, with the working directory and the pane title as backup keys
--- for when the pane id changes (a daemon restart), and the omp session file the agent last reported: a pin finds
--- the live agent that runs that session first, and a click on a pin whose agent stopped resumes it.
export type Pin = {
	pane: number,
	cwd: string?,
	title: string?,
	sessionFile: string?,
}

--- A top-level omp session file, as the session reader found it.
export type Session = {
	--- The absolute path of the `.jsonl` file: `omp --resume` opens it.
	file: string,
	id: string?,
	--- The working directory from the session's header.
	cwd: string,
	--- The main git repo of `cwd`, as for agents; nil outside a repo.
	repo: string?,
	--- The session's title (omp starts it with an icon character); nil or empty until omp names the session.
	title: string?,
	--- `os.time()` of the file's last write.
	at: number,
	--- Whether a running process holds the file open (a live agent, in Tern or elsewhere).
	open: boolean?,
}

--- What the sidebar lists: the live agents (the zones Needs you, Working and Idle, with their agents grouped by
--- project) or the closed sessions (the folders with closed sessions, newest first).
export type View = "live" | "recent"

--- A subscription quota, as the quota reader found it in omp's `usage_history`: the provider's and the account's
--- display names (`Claude`, `work`; no account for a row without an email), the window (`7d`, `5h`, `Weekly`), the
--- fraction used (0..1), how close it is to its limit, and when its window resets (wall-clock milliseconds).
export type Quota = {
	provider: string,
	account: string?,
	label: string,
	used: number,
	status: "ok" | "warning" | "exhausted",
	resetsAt: number,
}

export type Input = {
	agents: { Agent },
	--- `tern.now()`: monotonic milliseconds.
	now: number,
	--- `os.time()`: wall-clock seconds, for the age of idle agents.
	time: number?,
	--- The user's home folder, so that repo headers show `~/…`.
	home: string?,
	--- The subagents of each working omp agent's running `task` call, by pane; other agents have none.
	subagents: { [number]: subagents.Subagents }?,
	--- The pinned agents, in the order the user pinned them.
	pins: { Pin }?,
	--- Whether the Idle zone shows its agents that idled for a day or more ("Older than a day" is open).
	olderOpen: boolean?,
	--- Whether each agent's subagent lines are open, by pane. An agent the user did not choose one for has them open
	--- while it is this tab's agent, and closed otherwise.
	subsOpen: { [number]: boolean }?,
	--- The omp sessions the reader found, in any order; nil before the first read.
	sessions: { Session }?,
	--- The keys of the folders whose closed sessions show in the Recent view.
	recentOpen: { [string]: boolean }?,
	--- Whether the Recent view shows every folder, rather than only the first few.
	recentAll: boolean?,
	--- The view the strip shows chosen; Live when nil.
	view: View?,
	--- The pane the user last focused outside the sidebar: this tab's agent. Its row is drawn with the accent, and its
	--- project comes first in every zone.
	focused: number?,
	--- The omp id of the subagent each pane's omp shows in its view ("Viewing <name>"), by pane: while the focused
	--- pane shows one, that subagent's row is drawn selected instead of its agent's.
	viewing: { [number]: string }?,
	--- The model (`provider/model`) of each session file the session reader read (main agents' and subagents'), by
	--- file; a subagent's hover card names its model from it.
	routes: { [string]: string }?,
	--- The current subscription quotas, from omp's `agent.db`; nil when the read failed or gave none. A quota near or
	--- at its limit shows as one line under the Live/Recent switch.
	quotas: { Quota }?,
	--- The id the plugin runs under (`tern.plugin.id`), which names its commands; the status segment has no click
	--- without it.
	plugin: string?,
}

--- A status line segment, as `tern.chrome.status` takes it.
export type Segment = { text: string, icon: string?, tone: string?, command: string? }

export type Output = {
	view: Node,
	--- The status line: one segment with the working and waiting counts, or none while no agent works or waits.
	status: { Segment },
	--- The panes of the waiting agents, pinned ones too, the one that has waited longest first ("Next waiting
	--- agent" focuses the first).
	waiting: { number },
}

-- Each state reaches the canvas as data: the role of its title icon, dot, square or strip bar ends in the state
-- (`agents.glyph.working`, `agents.square.done`, `agents.bar.running`), and `agents.css` gives each state its Tern
-- color: working and running `--live`, waiting `--warn`, done `--ok`, failed `--bad`, idle `--t3`, exited and stopped
-- `--t4`. No state takes a Tern tone, so the accent marks only this tab's agent. A hollow mark is a row that is not
-- updated live: a closed session's dot, or the square of a subagent the sidebar cannot read while omp shows another
-- one (it may still run). Only a working agent's title icon moves: `agents.css` fades it slowly.
type State = "working" | "waiting" | "idle" | "exited" | "running" | "done" | "failed" | "stopped" | "frozen"

-- What the hover card says each agent state is.
local LABEL: { [AgentState]: string } = {
	working = "Working",
	waiting_input = "Waiting for you",
	idle = "Idle",
	exited = "Exited",
}

-- `text` cut to at most `bytes` bytes at the start of a UTF-8 character, with `…`; whole when it fits.
local function clip(text: string, bytes: number): string
	if #text <= bytes then
		return text
	end
	local cut = bytes
	-- Back off to the start of a UTF-8 character.
	while cut > 1 and bit32.band(string.byte(text, cut + 1), 0xC0) == 0x80 do
		cut -= 1
	end
	return string.sub(text, 1, cut) .. "…"
end

-- Context every row reads: the time, how many agents share each tab, and the focused pane.
type Shared = {
	now: number,
	--- `os.time()`, for the age of idle and waiting agents; nil when unknown.
	time: number?,
	perTab: { [number]: number },
	focused: number?,
	viewing: { [number]: string },
	--- The model (`provider/model`) of each session file the reader read, by file.
	routes: { [string]: string },
	--- Whether each agent's subagent lines are open, by pane, as the user chose; nil when the user chose none.
	subsOpen: { [number]: boolean },
}

local function nonEmpty(text: string?): string?
	if type(text) ~= "string" then
		return nil
	end
	local trimmed = string.match(text, "^%s*(.-)%s*$")
	if trimmed == "" then
		return nil
	end
	return trimmed
end

-- The pane title without the icon character and space that omp puts in front.
local function plainTitle(title: string?): string?
	if type(title) ~= "string" then
		return nil
	end
	return nonEmpty(string.match(title, "^[\128-\255]+%s+(.*)$") or title)
end

-- The title as a row shows it: omp's icon character in front (it tells the session's context at a glance) is kept;
-- nil when no text follows the icon.
local function shownTitle(title: string?): string?
	if not plainTitle(title) then
		return nil
	end
	return nonEmpty(title)
end

-- The last part of a working directory, or nil.
local function folderTail(cwd: string?): string?
	return cwd and nonEmpty(string.match(cwd, "([^/]+)/*$"))
end

-- The agent's own name: the pane title with omp's icon, else the folder name.
local function ownName(agent: Agent): string
	return shownTitle(agent.title) or folderTail(agent.cwd) or "Agent"
end

-- Whether the user named the agent's tab and the agent is alone in it: the tab name then names the agent.
local function tabNamed(agent: Agent, shared: Shared): string?
	local tabName = nonEmpty(agent.tabName)
	if tabName and agent.tab and shared.perTab[agent.tab] == 1 then
		return tabName
	end
	return nil
end

-- The tab name the user set, when the agent is alone in its tab; else the pane title; else the folder name.
local function name(agent: Agent, shared: Shared): string
	return tabNamed(agent, shared) or ownName(agent)
end

-- The text of an agent's row: as `name`, without omp's icon (the row draws it apart, in the state's color).
local function rowTitle(agent: Agent, shared: Shared): string
	return tabNamed(agent, shared) or plainTitle(agent.title) or folderTail(agent.cwd) or "Agent"
end

-- The model name without the thinking-level glyph (a trailing private-use character) and spaces.
local function plainModel(model: string?): string?
	if type(model) ~= "string" then
		return nil
	end
	return nonEmpty(string.match(model, "^(.-)[\128-\255%s]*$"))
end

-- The two items that copy a session's ID (read from its file's header on the click) and the absolute path of its
-- `.jsonl` file; both off, saying `why`, when the session file is not known.
local function copyItems(file: string?, why: string): { { [string]: any } }
	if not file then
		return {
			{ id = "copy-id", label = "Copy session ID", icon = "copy", disabled = why },
			{ id = "copy-path", label = "Copy session path", icon = "copy", disabled = why },
		}
	end
	return {
		{ id = "copy-id=" .. file, label = "Copy session ID", icon = "copy" },
		{ id = "copy-path=" .. file, label = "Copy session path", icon = "copy" },
	}
end

local NO_SESSION_FILE = "omp has not reported a session file for this agent"

-- Why Rename is off for `agent`, or nil when it is on. Rename sends omp's `/rename <title>` through the composer, so
-- it needs a running omp agent (one that reported its session file) whose composer runs commands: not while omp
-- shows a subagent (the composer is that subagent's chat box then) or while the agent waits for an answer.
local function renameOff(agent: Agent, viewingSub: boolean): string?
	if agent.state == "exited" then
		return "The agent is not running"
	elseif not agent.sessionFile then
		return "Only an omp session can be renamed, and this agent reported none"
	elseif viewingSub then
		return "omp shows a subagent: go back to the main session first"
	elseif agent.state == "waiting_input" then
		return "The agent waits for your answer"
	end
	return nil
end

-- A right-click offers Pin or Unpin, Rename, the copy items, and Interrupt while the agent is in a turn (Ctrl-C at
-- an idle omp prompt clears the editor, and a second one quits).
local function menu(agent: Agent, pane: string, pinned: boolean, viewingSub: boolean): { { [string]: any } }
	local inTurn = agent.state == "working" or agent.state == "waiting_input"
	local off = renameOff(agent, viewingSub)
	local items: { { [string]: any } } = {
		if pinned
			then { id = "unpin=" .. pane, label = "Unpin", icon = "pin" }
			else { id = "pin=" .. pane, label = "Pin", icon = "pin" },
		if off
			then { id = "rename", label = "Rename", icon = "pencil", disabled = off }
			else { id = "rename=" .. pane, label = "Rename", icon = "pencil" },
	}
	for _, item in copyItems(agent.sessionFile, NO_SESSION_FILE) do
		table.insert(items, item)
	end
	table.insert(items, {
		id = "interrupt=" .. pane,
		label = "Interrupt",
		icon = "stop",
		disabled = if inTurn then false else "The agent is not in a turn",
	})
	return items
end

local MINUTE, HOUR, DAY = 60, 60 * 60, 24 * 60 * 60

-- The roles `agents.css` styles. The root sets the canvas in the sans face; the chrome holds the Live/Recent switch
-- and the quota line (`agents.quota`); the body holds the zones (`agents.zone`), each a head row and its project
-- groups (`agents.project`), each a label row and its agent rows. Each list row has the role `agents.<kind>.<depth>`
-- (see `rowRole`). A row's parts: the title icon in its state's color (`agents.glyph.<state>`), the name (cut with an
-- ellipsis in CSS, so that Tern adds no tooltip of its own under a row's hover card), the time, and the controls that
-- show on hover. A zone head has a square in its state's color (`agents.square.<state>`) and its status.
local ROLE = {
	root = "agents.root",
	chrome = "agents.chrome",
	views = "agents.views",
	quota = "agents.quota",
	view = "agents.view",
	viewOn = "agents.view.on",
	body = "agents.body",
	zone = "agents.zone",
	project = "agents.project",
	older = "agents.older",
	mine = "agents.mine",
	calm = "agents.calm",
	chev = "agents.chev",
	icon = "agents.icon",
	glyph = "agents.glyph.",
	square = "agents.square.",
	dot = "agents.dot.",
	name = "agents.name",
	detail = "agents.detail",
	rule = "agents.rule",
	time = "agents.time",
	count = "agents.count",
	meta = "agents.meta",
	hover = "agents.hover",
	--- The strip at the end of an agent's row, open or closed (`agents.strip.open`).
	strip = "agents.strip",
	--- The strip's "N done", shown when no subagent runs.
	tally = "agents.tally",
	--- One bar of the strip, per running subagent (`agents.bar.running`).
	bar = "agents.bar.",
	--- The strip's "+N", for the running subagents past the last bar.
	more = "agents.more",
	--- A Needs you card (`agents.card`), its question (clamped to 2 lines) and its mono footer.
	card = "agents.card",
	question = "agents.question",
	footer = "agents.footer",
	--- The number of Needs you cards after the Live switch.
	needs = "agents.needs",
}

-- A list row's kind: `item` (a clickable row: an agent, a subagent, a session, "N more"), `on` (this tab's agent's
-- row, or the subagent its omp shows), `head` (a zone's head), `label` (a project's label), `folder` (a Recent folder
-- row with its chevron), `fold` (Older than a day: a chevron and a label) and `info` (the done and incomplete lines,
-- which take no click).
type Kind = "item" | "on" | "head" | "label" | "folder" | "fold" | "info"

-- `agents.<kind>.<depth>`: depth 0 for the rows of a zone, one more per level below an agent; the CSS indents a row
-- by its depth.
local function rowRole(kind: Kind, depth: number): string
	return "agents." .. kind .. "." .. tostring(depth)
end

-- A name takes the free room (pushing the end marks to the right end) unless a detail follows it: then, as in a
-- list item, the name keeps its width and the detail flexes and is cut first.
local function nameNode(text: string, style: string?, hasDetail: boolean?): Node
	local p: { [string]: any } = { role = ROLE.name }
	if not hasDetail then
		p.grow = 1
	end
	if style then
		p.spans = { { t = text, s = style } }
	else
		p.text = text
	end
	return { k = "text", p = p }
end

-- The secondary part after a name (a subagent's role and parent): plain text, so that `agents.css` draws it dimmer
-- and smaller than the name; it takes the free room and is cut first when the row is narrow.
local function detailNode(text: string): Node
	return { k = "text", p = { text = text, role = ROLE.detail, grow = 1, basis = 0 } }
end

-- A state dot in the icon column: filled, or hollow for a row that is not updated live.
local function dotNode(state: State, label: string, hollow: boolean?): Node
	return { k = "text", p = { spans = { { t = if hollow then "○" else "●" } }, aria = label, role = ROLE.dot .. state } }
end

-- A small square in a state's color, as a zone head and a subagent line show it; `agents.css` draws the square.
-- `label` names the state for a screen reader.
local function squareNode(state: State, label: string?): Node
	local p: { [string]: any } = { text = "■", wrap = "none", role = ROLE.square .. state }
	if label then
		p.aria = label
	end
	return { k = "text", p = p }
end

-- Tern's icon for an agent whose title has no omp icon (an agent that is not omp, or not titled yet). Tern ships no
-- icon named "agent"; `sparkle` is the one its aliases give a model.
local AGENT_ICON = "sparkle"

-- The icon character omp puts at the start of a title, or nil when the title has none or no text follows it.
local function titleGlyph(title: string?): string?
	if type(title) ~= "string" or not plainTitle(title) then
		return nil
	end
	return string.match(title, "^([\128-\255]+)%s")
end

-- A row's title icon in the color of `state`: omp's icon character from `title`, else Tern's agent icon. `label`
-- names the state for a screen reader.
local function titleIcon(title: string?, state: State, label: string): Node
	local glyph = titleGlyph(title)
	if glyph then
		return { k = "text", p = { text = glyph, wrap = "none", aria = label, role = ROLE.glyph .. state } }
	end
	return { k = "icon", p = { name = AGENT_ICON, aria = label, role = ROLE.glyph .. state } }
end

-- `seconds` in its largest whole unit, the one time format of the sidebar: `45s`, `4m`, `3h`, `2d`.
local function duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s < MINUTE then
		return string.format("%ds", s)
	elseif s < HOUR then
		return string.format("%dm", s // MINUTE)
	elseif s < DAY then
		return string.format("%dh", s // HOUR)
	end
	return string.format("%dd", s // DAY)
end

-- A row's time, neutral (`agents.css` sets it in the mono face with tabular figures).
local function timeNode(seconds: number): Node
	return { k = "text", p = { text = duration(seconds), wrap = "none", role = ROLE.time } }
end

-- A hover card's facts: an aligned grid of muted labels and their values, as `tern.ui.kv` builds it.
type Facts = { { k: string, v: string } }

local function factsNode(facts: Facts): Node?
	if #facts == 0 then
		return nil
	end
	local items: { { k: { { [string]: string } }, v: { { [string]: string } } } } = {}
	for _, fact in facts do
		table.insert(items, { k = { { t = fact.k, s = "muted" } }, v = { { t = fact.v } } })
	end
	return { k = "kv", p = { items = items } }
end

-- The hover card's first line: the name, the state after it and, while the agent works, the live turn timer.
local function cardHead(name: string, state: string, age: number?): Node
	local text: Node = { k = "text", p = { spans = { { t = name, s = "strong" }, { t = " · " .. state, s = "muted" } } } }
	if not age then
		return text
	end
	local children: { Node } = { text, { k = "elapsed", p = { age = age } } }
	return { k = "row", p = { gap = "sm" }, c = children }
end

-- A hover card: its head, its facts, then the rest, with room between the parts.
local function card(head: Node, facts: Facts, rest: { Node }): Node
	local children: { Node } = { head }
	local grid = factsNode(facts)
	if grid then
		table.insert(children, grid)
	end
	for _, node in rest do
		table.insert(children, node)
	end
	return { k = "col", p = { gap = "sm" }, c = children }
end

-- A last message this long or longer gets a summary from omp's light model (`lib/summaries.luau`); a shorter one
-- shows whole.
local SUMMARY_FROM = 280

--- Whether the last message `text` is long enough that its hover card shows a summary of it.
function viewModel.needsSummary(text: string): boolean
	local trimmed = nonEmpty(text)
	return trimmed ~= nil and #trimmed >= SUMMARY_FROM
end

-- The hover card's last message: whole (Markdown) when short; when long, its summary, else a note while the summary
-- is being made, else (no summary could be made) its start. Each is a Markdown node, which wraps to the card's width:
-- a `text` node with a line limit drew a cut line with `…` in Tern 0.9.36.
local function messageNode(message: string, summary: string?, summarizing: boolean?): Node
	if #message < SUMMARY_FROM then
		return { k = "md", p = { text = message } }
	end
	local short = nonEmpty(summary)
	if short then
		return { k = "md", p = { text = short } }
	end
	if summarizing then
		return { k = "text", p = { spans = { { t = "Summarizing the last message…", s = "muted" } } } }
	end
	return { k = "md", p = { text = clip(message, SUMMARY_FROM) } }
end

-- omp's thinking levels, which a model route may end in (`:high`).
local LEVELS = { off = true, minimal = true, low = true, medium = true, high = true, xhigh = true, max = true }

-- One model, as `provider/model` without omp's routing suffixes: the `@<upstream>` pin and the `:<level>` thinking
-- suffix (the effort has its own line). Nil for no model.
local function modelRoute(model: string?): string?
	local route = nonEmpty(model)
	if not route then
		return nil
	end
	route = string.match(route, "^[^@]*") :: string
	local base, suffix = string.match(route, "^(.*):(%a+)$")
	if base and LEVELS[suffix] then
		route = base
	end
	return nonEmpty(route)
end

-- How an agent's row shows its state: the state of its title icon, the name of that state, and the time the row
-- shows in seconds (the turn timer while it works; while it waits, the wait; else the time since its last turn),
-- nil when unknown.
type Shown = { state: State, label: string, seconds: number? }

local function shownState(agent: Agent, shared: Shared): Shown
	if agent.state == "working" then
		return { state = "working", label = "Working", seconds = math.max(0, shared.now - (agent.workingSince or shared.now)) / 1000 }
	end
	local time, activeAt = shared.time, agent.activeAt
	local since = if time and activeAt then math.max(0, time - activeAt) else nil
	if agent.state == "waiting_input" then
		return { state = "waiting", label = "Waiting for you", seconds = since }
	elseif agent.state == "exited" then
		return { state = "stopped", label = "Stopped", seconds = since }
	end
	return { state = "idle", label = "Idle", seconds = since }
end

-- An agent's row at `depth`: its title icon in the state's color, its title, and its time; a stopped agent's row adds
-- a resume icon that shows on hover. A row carries no tooltip: its hover card holds every fact: the state and the
-- live turn timer, the model, the effort and the last message (or its summary).
local function row(agent: Agent, shared: Shared, pinned: boolean, depth: number): Node
	local shown = shownState(agent, shared)
	local children: { Node } = { titleIcon(agent.title, shown.state, shown.label), nameNode(rowTitle(agent, shared)) }
	if shown.seconds then
		table.insert(children, timeNode(shown.seconds))
	end
	if agent.state == "exited" then
		table.insert(children, { k = "icon", p = { name = "play", role = ROLE.hover } })
	end
	local facts: Facts = {}
	-- omp's session names the model as `provider/model`; an agent without one (not omp) shows Tern's model name, in
	-- lower case as the routes are.
	local display = plainModel(agent.model)
	local model = modelRoute(agent.route) or (display and string.lower(display))
	if model then
		table.insert(facts, { k = "Model", v = model })
	end
	local effort = nonEmpty(agent.effort)
	if effort then
		table.insert(facts, { k = "Effort", v = effort })
	end
	local age = if agent.state == "working" then math.max(0, shared.now - (agent.workingSince or shared.now)) else nil
	local rest: { Node } = {}
	local message = nonEmpty(agent.lastMessage)
	if message then
		table.insert(rest, messageNode(message, agent.summary, agent.summarizing))
	end
	local pane = string.format("%.0f", agent.pane)
	-- A stopped agent (it shows only while pinned) has no program to focus: a click resumes its session.
	local click = if agent.state == "exited" and agent.sessionFile
		then "resume=" .. agent.sessionFile
		else "focus=" .. pane
	local props: { [string]: any } = {
		key = "agent-" .. pane,
		gap = "sm",
		role = rowRole(if shared.focused == agent.pane then "on" else "item", depth),
		actions = { click = click, menu = menu(agent, pane, pinned, shared.viewing[agent.pane] ~= nil) },
		hovercard = card(cardHead(name(agent, shared), LABEL[agent.state], age), facts, rest),
	}
	return { k = "row", p = props, c = children }
end

--- One section of the sidebar: the agents of one main git repo, or of one working directory outside any repo.
export type Group = {
	--- The repo root, or the working directory of agents outside any repo; nil for agents with neither.
	folder: string?,
	--- The folder's short path (`~/Personal/oh-my-pi`), which its row's hover card shows.
	label: string,
	--- The folder's name: its row's text, the sort key of the sections and the tab name of "Arrange tabs by project".
	name: string,
	--- The section's canvas key: stable for a folder, and free of the `.` that separates `set` paths.
	key: string,
	--- The group's agents in start order.
	agents: { Agent },
}

-- The section of agents that tell neither a repo nor a working directory.
local NO_FOLDER = "No folder"

--- `path` with the home folder written as `~`, as the repo headers show it.
function viewModel.shortPath(path: string, home: string?): string
	local base = home and string.match(home, "^(.-)/*$")
	if base and base ~= "" then
		if path == base then
			return "~"
		end
		if string.sub(path, 1, #base + 1) == base .. "/" then
			return "~" .. string.sub(path, #base + 1)
		end
	end
	return path
end

-- Keeps letters, digits and `-`, and writes every other byte as `_XX`: two inputs never share the result, and it
-- has no `.`, which a patch path cannot name.
local function keyPart(text: string): string
	return (string.gsub(text, "[^%w%-]", function(c: string): string
		return string.format("_%02X", string.byte(c))
	end))
end

local function groupKey(folder: string): string
	return "repo-" .. keyPart(folder)
end

-- The folder a section stands for: the main repo, else the working directory (without a trailing `/`).
local function folderFor(repo: string?, dir: string?): string?
	if repo then
		return repo
	end
	local cwd = nonEmpty(dir)
	if not cwd then
		return nil
	end
	return if cwd == "/" then cwd else string.match(cwd, "^(.-)/*$")
end

-- The folder an agent's section stands for.
local function folderOf(agent: Agent): string?
	return folderFor(agent.repo, agent.cwd)
end

-- Pane ids grow as panes open, so they give the start order; states never move a row.
local function startOrder(agents: { Agent }): { Agent }
	local ordered = table.clone(agents)
	table.sort(ordered, function(a, b)
		return a.pane < b.pane
	end)
	return ordered
end

--- The name each tab takes from its main agent, by tab id: the first agent in start order that sits in the tab and
--- has not exited, named as its row names it (the pane title with omp's icon, else the folder). Tabs without such
--- an agent are absent.
function viewModel.tabTitles(agents: { Agent }): { [number]: string }
	local out: { [number]: string } = {}
	for _, agent in startOrder(agents) do
		local tab = agent.tab
		if tab and agent.state ~= "exited" and out[tab] == nil then
			out[tab] = ownName(agent)
		end
	end
	return out
end

--- The title of `tab`, from the names `tabTitles` gave: the name the user gave the tab, else its main agent's name;
--- nil (Tern's own title) for a tab without an agent.
function viewModel.tabTitle(tab: { id: number, name: string? }, titles: { [number]: string }): string?
	return nonEmpty(tab.name) or titles[tab.id]
end

--- The agents grouped by folder: an agent in a git repo under its main repo, any other under its working directory.
--- The sections sort alphabetically by the folder name their row shows (ignoring case), folders of the same name by
--- short path; agents with no folder at all come last. Agent states play no part, so sections never move when a
--- state changes.
function viewModel.groups(agents: { Agent }, home: string?): { Group }
	local byFolder: { [string]: Group } = {}
	local groups: { Group } = {}
	local loose: Group = { label = NO_FOLDER, name = NO_FOLDER, key = "no-folder", agents = {} }
	local function add(folder: string): Group
		local group: Group = {
			folder = folder,
			label = viewModel.shortPath(folder, home),
			name = string.match(folder, "([^/]+)/*$") or folder,
			key = groupKey(folder),
			agents = {},
		}
		byFolder[folder] = group
		table.insert(groups, group)
		return group
	end
	for _, agent in startOrder(agents) do
		local folder = folderOf(agent)
		if folder then
			table.insert((byFolder[folder] or add(folder)).agents, agent)
		else
			table.insert(loose.agents, agent)
		end
	end
	table.sort(groups, function(a, b)
		local na, nb = string.lower(a.name), string.lower(b.name)
		if na ~= nb then
			return na < nb
		end
		local la, lb = string.lower(a.label), string.lower(b.label)
		if la ~= lb then
			return la < lb
		end
		return a.label < b.label
	end)
	if #loose.agents > 0 then
		table.insert(groups, loose)
	end
	return groups
end

-- The Files pane's folder glyphs, which a Recent folder row shows: Material Icon Theme's filled folders.
local FOLDER, FOLDER_OPEN = "mi-folder", "mi-folder-open"

-- An icon in the icon column.
local function iconNode(icon: string, tone: string?): Node
	return { k = "icon", p = { name = icon, tone = tone, role = ROLE.icon } }
end

-- The chevron of a row that opens and closes the rows under it.
local function chevron(open: boolean): Node
	return { k = "icon", p = { name = if open then "chev" else "chev-r", role = ROLE.chev } }
end

-- A count in small mono digits: always shown (`meta`), or only while the pointer is on its row (`count`).
local function countNode(count: number, role: string): Node
	return { k = "text", p = { spans = { { t = tostring(count), s = "muted" } }, wrap = "none", role = role } }
end

-- A row that opens and closes the rows under it and is no folder (Older than a day): the chevron, its label and its
-- count. A click on it sends `click`.
local function foldRow(key: string, label: string, count: number, open: boolean, click: string, depth: number): Node
	local children: { Node } = { chevron(open), nameNode(label), countNode(count, ROLE.meta) }
	local p: { [string]: any } = { key = key, gap = "sm", role = rowRole("fold", depth), actions = { click = click } }
	return { k = "row", p = p, c = children }
end

-- The `+` button that opens a new tab in `folder` (a repo when `repo`); it shows while the pointer is on its row.
local function plusButton(folder: string, repo: boolean): Node
	return {
		k = "button",
		p = {
			icon = "plus",
			size = "sm",
			variant = "quiet",
			title = if repo then "New tab in this repo" else "New tab in this folder",
			role = ROLE.hover,
			actions = { click = "new=" .. folder },
		},
	}
end

-- The hover card of a row that stands for `folder`: its short path, then `extra`.
local function folderCard(folder: string, home: string?, extra: { Node }?): Node
	local lines: { Node } = { { k = "text", p = { spans = { { t = viewModel.shortPath(folder, home), s = "path" } } } } }
	for _, line in extra or ({} :: { Node }) do
		table.insert(lines, line)
	end
	return { k = "col", p = { gap = "xs" }, c = lines }
end

-- What a folder row shows: its key and the action of a click on it, the folder and its name, whether it is a repo,
-- whether it shows its rows, the count of its rows, its depth, and the lines its hover card adds after the short
-- path.
type FolderSpec = {
	key: string,
	click: string,
	folder: string,
	name: string,
	repo: boolean,
	open: boolean,
	count: number,
	depth: number,
	home: string?,
	extra: { Node }?,
}

-- A Recent folder row: the chevron (open while it shows its rows), the folder glyph, the folder's name, and, while
-- the pointer is on it, the count of its rows and the `+` that starts an agent there. Its hover card gives the
-- folder's short path.
local function folderRow(spec: FolderSpec): Node
	local children: { Node } = {
		chevron(spec.open),
		iconNode(if spec.open then FOLDER_OPEN else FOLDER),
		nameNode(spec.name),
		countNode(spec.count, ROLE.count),
		plusButton(spec.folder, spec.repo),
	}
	local p: { [string]: any } = {
		key = spec.key,
		gap = "sm",
		role = rowRole("folder", spec.depth),
		actions = { click = spec.click },
		hovercard = folderCard(spec.folder, spec.home, spec.extra),
	}
	return { k = "row", p = p, c = children }
end

-- Whether a group's agents work in a git repo (else in a plain folder).
local function isRepo(group: Group): boolean
	local first = group.agents[1]
	return first ~= nil and first.repo ~= nil
end

-- A project's label in a zone: its name in muted text, a light rule to the right edge and, while the pointer is on
-- it, the `+` that starts an agent there. Its hover card gives the folder's short path. Agents with no folder get
-- the label "No folder", with neither.
local function projectLabel(group: Group, home: string?): Node
	local children: { Node } = {
		{ k = "text", p = { text = group.name, role = ROLE.name } },
		{ k = "rule", p = { role = ROLE.rule, grow = 1 } },
	}
	local p: { [string]: any } = { key = "head", gap = "sm", role = rowRole("label", 0) }
	local folder = group.folder
	if folder then
		table.insert(children, plusButton(folder, isRepo(group)))
		p.hovercard = folderCard(folder, home)
	end
	return { k = "row", p = p, c = children }
end

-- omp renders nested subagents down to its `MAX_NESTED_TASK_RENDER_DEPTH` (8), counting the first level as 0: the
-- sidebar lists every level it sends (depth 1 to 9 here), and only a deeper one, if omp ever sent it, folds into
-- one "+N deeper" line.
local MAX_DEPTH = 8 + 1

-- The session file omp writes for the subagent `name` (its omp id, nesting levels joined by `>` as omp names the
-- `agent` node) of the agent whose session file is `main`. omp writes a subagent's session to `<dir>/<omp id>.jsonl`,
-- where `<dir>` is the file of the session that started it without `.jsonl` (`subtaskSessionFile` in omp's
-- `task/executor.ts`), so `A>B` is `<main without .jsonl>/A/A.B.jsonl`. Nil when `main` is unknown or a level of the
-- name is no omp id (letters, digits, `_` and `-`).
local function subagentFile(main: string?, name: string): string?
	if not main or string.sub(main, -#".jsonl") ~= ".jsonl" then
		return nil
	end
	local path = string.sub(main, 1, -#".jsonl" - 1)
	local id = ""
	for i, level in string.split(name, ">") do
		if not string.match(level, "^[%w_%-]+$") then
			return nil
		end
		id = if i == 1 then level else id .. "." .. level
		path ..= "/" .. id
	end
	return path .. ".jsonl"
end

--- The session file of the subagent `name` (its omp id with `>` between levels) of the agent whose session file is
--- `main`; nil when it cannot be told.
viewModel.subagentFile = subagentFile

-- How a subagent line shows a subagent: the state of its square, and the name of that state for a screen reader.
local SUB_STATE: { [string]: { state: State, label: string } } = {
	running = { state = "running", label = "Running" },
	pending = { state = "idle", label = "Queued" },
	done = { state = "done", label = "Done" },
	failed = { state = "failed", label = "Failed" },
	aborted = { state = "stopped", label = "Stopped" },
}

-- Whether a subagent runs or waits in the queue: only those take a bar of the strip.
local function runs(sub: subagents.Subagent): boolean
	return sub.status == "running" or sub.status == "pending"
end

-- What a subagent line shows as a state: a subagent that only waits on its own subagents, or one whose state is the
-- last one read while omp shows another subagent, says so.
local function subShown(sub: subagents.Subagent, frozen: boolean): { state: State, label: string }
	if frozen then
		return { state = "frozen", label = "Not live" }
	end
	if sub.waiting and runs(sub) then
		return { state = "waiting", label = "Waiting on its subagents" }
	end
	return SUB_STATE[sub.status] or { state = "idle", label = "Queued" }
end

-- A path of 3 or more parts in what a subagent does keeps only its file name: `/Users/me/x/view.luau` shows as
-- `…/view.luau`, so that a long path does not push the rest of the line out.
local function cutPaths(text: string): string
	return (string.gsub(text, "[^%s'\"`()]+", function(word: string): string
		local _, parts = string.gsub(word, "[^/]+", "")
		if parts < 3 then
			return word
		end
		return "…/" .. (string.match(word, "([^/]+)/*$") or word)
	end))
end

-- The time a subagent line shows, in seconds: while it runs, since it started; once it ended, since it ended; nil
-- when the reader saw it only finished.
local function subSeconds(sub: subagents.Subagent, now: number): number?
	if not sub.since then
		return nil
	end
	return math.max(0, now - sub.since) / 1000
end

-- One subagent at any nesting level, as a line one step under its agent plus one step per depth: its square in the
-- state's color, its own name (the last level of its omp id), what it does now (the call, with a long path cut to its
-- file name; a failed one with no call shows "failed"), and its time. The hover card repeats them with the model (as
-- its session file names it, `provider/model`, else omp's model id), the effort and the whole call. A click asks to
-- show the subagent in omp's view (`subagent=<pane> <omp id>`); a right-click copies the ID or path of its own
-- session file, found from its agent's (`agentFile`).
local function subLine(
	sub: subagents.Subagent,
	pane: string,
	agentFile: string?,
	depth: number,
	selected: boolean,
	frozen: boolean,
	shared: Shared
): Node
	local role = nonEmpty(sub.role)
	local parent = if sub.depth > 1 then nonEmpty(sub.parent) else nil
	local levels = string.split(sub.name, ">")
	local own = levels[#levels]
	local shown = subShown(sub, frozen)
	local intent = nonEmpty(sub.intent)
	local call = if intent
		then cutPaths(intent)
		elseif sub.status == "failed"
		then "failed"
		else nonEmpty(role)
	local children: { Node } = { squareNode(shown.state, shown.label), nameNode(own, nil, call ~= nil) }
	if call then
		table.insert(children, detailNode(call))
	end
	local seconds = subSeconds(sub, shared.now)
	if seconds then
		table.insert(children, timeNode(seconds))
	end
	local facts: Facts = {}
	if role then
		table.insert(facts, { k = "Role", v = role })
	end
	if parent then
		table.insert(facts, { k = "Under", v = parent })
	end
	local file = subagentFile(agentFile, sub.name)
	local model = modelRoute(file and shared.routes[file]) or modelRoute(sub.model)
	if model then
		table.insert(facts, { k = "Model", v = model })
	end
	local effort = nonEmpty(sub.effort)
	if effort then
		table.insert(facts, { k = "Effort", v = effort })
	end
	if intent then
		table.insert(facts, { k = "Doing", v = intent })
	end
	local rest: { Node } = {}
	if frozen then
		table.insert(rest, { k = "text", p = { spans = { { t = "Not updated while omp shows another subagent", s = "muted" } } } })
	end
	return {
		k = "row",
		p = {
			key = "sub-" .. keyPart(sub.id),
			gap = "sm",
			role = rowRole(if selected then "on" else "item", depth),
			actions = {
				click = "subagent=" .. pane .. " " .. sub.id,
				menu = copyItems(file, if agentFile then "The subagent's name is no omp id" else NO_SESSION_FILE),
			},
			hovercard = card(cardHead(own, shown.label), facts, rest),
		},
		c = children,
	}
end

-- A line under the subagents that says something about them and takes no click: a level deeper than omp lists, the
-- cut read.
local function infoLine(key: string, icon: Node, text: string, style: string, depth: number): Node
	local children: { Node } = { icon, nameNode(text, style) }
	return { k = "row", p = { key = key, gap = "sm", role = rowRole("info", depth) }, c = children }
end

-- The counts of a crew, as the strip's tooltip and its "N done" read them: the subagents that run, the ones that wait
-- on the user, the ones queued, and the finished ones by result.
type Crew = { running: number, waiting: number, queued: number, done: number, failed: number, stopped: number }

local function count(subs: subagents.Subagents): Crew
	local crew: Crew = { running = 0, waiting = 0, queued = 0, done = 0, failed = 0, stopped = 0 }
	for _, sub in subs.agents do
		if sub.status == "running" then
			if sub.waiting then
				crew.waiting += 1
			else
				crew.running += 1
			end
		elseif sub.status == "pending" then
			crew.queued += 1
		elseif sub.status == "done" then
			crew.done += 1
		elseif sub.status == "failed" then
			crew.failed += 1
		elseif sub.status == "aborted" then
			crew.stopped += 1
		end
	end
	return crew
end

-- The strip shows at most this many bars; the running subagents past it count in one "+N".
local STRIP_BARS = 8

-- The counts of `crew` as the strip's tooltip gives them: "3 running · 1 waiting · 1 done · 1 failed", the empty
-- counts left out.
local function crewText(crew: Crew): string
	local parts: { string } = {}
	local function add(n: number, word: string)
		if n > 0 then
			table.insert(parts, string.format("%d %s", n, word))
		end
	end
	add(crew.running, "running")
	add(crew.waiting, "waiting")
	add(crew.queued, "queued")
	add(crew.done, "done")
	add(crew.failed, "failed")
	add(crew.stopped, "stopped")
	return table.concat(parts, " · ")
end

-- The strip at the end of an agent's row, when the agent has subagents: one bar in the working color per running
-- subagent, at most `STRIP_BARS`, then "+N"; with none running, a neutral "N done" in the same place; with none
-- running and none done, no strip. A click shows or hides the subagent lines (`subs=<pane> open` or
-- `subs=<pane> closed`); the tooltip lists every count and says what a click does, so that a failure is one hover
-- away also while the lines are closed.
local function stripNode(pane: string, crew: Crew, open: boolean): Node?
	local running = crew.running
	if running == 0 and crew.done == 0 then
		return nil
	end
	local title = crewText(crew) .. (if open then ". Click: hide them" else ". Click: show them")
	local click = "subs=" .. pane .. (if open then " closed" else " open")
	local children: { Node } = {}
	if running > 0 then
		for _ = 1, math.min(running, STRIP_BARS) do
			table.insert(children, { k = "text", p = { text = "▮", wrap = "none", role = ROLE.bar .. "running" } })
		end
		if running > STRIP_BARS then
			table.insert(children, { k = "text", p = { text = "+" .. tostring(running - STRIP_BARS), role = ROLE.more } })
		end
	else
		table.insert(children, { k = "text", p = { text = tostring(crew.done) .. " done" } })
	end
	return {
		k = "row",
		p = {
			key = "strip",
			gap = "none",
			role = if running > 0 then (if open then ROLE.strip .. ".open" else ROLE.strip) else ROLE.tally,
			title = title,
			actions = { click = click },
		},
		c = children,
	}
end

-- The agent's row at `depth`, with the subagent strip at its end, and below it the lines of its subagents one step
-- down per nesting level: every one while the lines are open (`agents.strip.open`), else only the failed ones (a
-- failure never hides). A warning line says when Tern cut the read, and one that +N running subagents sit past the
-- levels omp renders. This tab's agent, and its open lines, are one block, which `agents.css` draws with the accent.
local function entry(agent: Agent, shared: Shared, subs: subagents.Subagents?, pinned: boolean, depth: number): Node
	local main = row(agent, shared, pinned, depth)
	if not subs or agent.state == "exited" or #subs.agents == 0 then
		return main
	end
	local pane = string.format("%.0f", agent.pane)
	local crew = count(subs)
	local chosen = shared.subsOpen[agent.pane]
	local open = if chosen ~= nil then chosen else shared.focused == agent.pane
	-- The strip goes right after the name, before the time.
	local children = main.c :: { Node }
	local strip = stripNode(pane, crew, open)
	if strip then
		table.insert(children, 3, strip)
	end
	local lines: { Node } = { main }
	local failed: { Node } = {}
	local deeper = 0
	-- While the lines are open, the subagent the focused pane's omp shows takes the selection from its agent's row.
	local viewed = shared.viewing[agent.pane]
	local shown = if shared.focused == agent.pane then viewed else nil
	for _, sub in subs.agents do
		local selected = open and viewing.shows(sub, shown)
		if selected then
			(main.p :: { [string]: any }).role = rowRole("item", depth)
		end
		if sub.depth > MAX_DEPTH then
			if sub.status == "running" then
				deeper += 1
			end
		elseif open or sub.status == "failed" then
			local frozen = subs.frozen == true and not viewing.shows(sub, viewed)
			local line = subLine(sub, pane, agent.sessionFile, depth + sub.depth, selected, frozen, shared)
			table.insert(if open then lines else failed, line)
		end
	end
	if open then
		if deeper > 0 then
			local text = string.format("+%d deeper", deeper)
			table.insert(lines, infoLine("subs-deeper", iconNode("more", "muted"), text, "muted", depth + 1))
		end
		if subs.incomplete then
			local text = "subagents may be incomplete"
			table.insert(lines, infoLine("subs-incomplete", iconNode("warn", "warning"), text, "warning", depth + 1))
		end
	end
	-- A closed strip still shows a failure, one step under its agent as a flat line: its depth means nothing there.
	for _, line in failed do
		(line.p :: { [string]: any }).role = rowRole("item", depth + 1)
		table.insert(lines, line)
	end
	if #lines == 1 then
		return main
	end
	local p: { [string]: any } = { key = "tree-" .. pane, gap = "none" }
	if shared.focused == agent.pane then
		p.role = ROLE.mine
	end
	return { k = "col", p = p, c = lines }
end

-- An idle agent whose last turn ended this long ago (in seconds) folds into "Older than a day", unless it is pinned
-- or this tab's agent.
local OLDER_AFTER = DAY

local function isOlder(agent: Agent, time: number?): boolean
	local activeAt = agent.activeAt
	return agent.state == "idle" and time ~= nil and activeAt ~= nil and time - activeAt >= OLDER_AFTER
end

-- The milliseconds after `ms` until a time of `ms` milliseconds shows another text (`45s` → `46s`, `4m` → `5m`).
local function untilChange(ms: number): number
	local seconds = ms / 1000
	local unit = if seconds < MINUTE then 1 elseif seconds < HOUR then MINUTE elseif seconds < DAY then HOUR else DAY
	return (unit - seconds % unit) * 1000
end

-- How bad each quota status is; a quota that is fine has none and shows no line.
local QUOTA_RANK: { [string]: number } = { exhausted = 2, warning = 1 }

-- A quota near or at its limit, with the seconds left until its window resets.
type HotQuota = { quota: Quota, left: number }

-- The quotas near or at their limit whose window has not reset at `time` (`os.time()`), the worst first: exhausted
-- before warning, then the higher use.
local function hotQuotas(quotas: { Quota }?, time: number): { HotQuota }
	local hot: { HotQuota } = {}
	local list: { Quota } = quotas or {}
	for _, quota in list do
		local left = quota.resetsAt / 1000 - time
		if QUOTA_RANK[quota.status] and left > 0 then
			table.insert(hot, { quota = quota, left = left })
		end
	end
	table.sort(hot, function(a, b)
		local ra, rb = QUOTA_RANK[a.quota.status], QUOTA_RANK[b.quota.status]
		if ra ~= rb then
			return ra > rb
		end
		return a.quota.used > b.quota.used
	end)
	return hot
end

-- Which agent each pin names, by the pin's index: the running agent that has the pin's session file open, else the
-- agent in the pin's pane when its working directory agrees, else the first agent, in start order, that no other pin
-- names and that has the pin's working directory and title.
local function matchPins(agents: { Agent }, pins: { Pin }): { [number]: Agent }
	local byPane: { [number]: Agent } = {}
	local byFile: { [string]: Agent } = {}
	for _, agent in startOrder(agents) do
		byPane[agent.pane] = agent
		local file = agent.sessionFile
		if file and agent.state ~= "exited" and byFile[file] == nil then
			byFile[file] = agent
		end
	end
	local matched: { [number]: Agent } = {}
	local taken: { [Agent]: boolean } = {}
	for i, pin in pins do
		local agent = pin.sessionFile and byFile[pin.sessionFile]
		if agent and not taken[agent] then
			matched[i] = agent
			taken[agent] = true
		end
	end
	for i, pin in pins do
		local agent = byPane[pin.pane]
		if not matched[i] and agent and not taken[agent] and (pin.cwd == nil or agent.cwd == pin.cwd) then
			matched[i] = agent
			taken[agent] = true
		end
	end
	local ordered: { Agent }? = nil
	for i, pin in pins do
		if not matched[i] and pin.cwd and pin.title then
			ordered = ordered or startOrder(agents)
			for _, agent in ordered :: { Agent } do
				if not taken[agent] and agent.cwd == pin.cwd and agent.title == pin.title then
					matched[i] = agent
					taken[agent] = true
					break
				end
			end
		end
	end
	return matched
end

--- The pins with the pane id, working directory, title and session file of the agent each one names now, so that
--- the backup keys follow the agent and a pin found by them takes its new pane id. A pin that names no agent stays
--- as it is.
function viewModel.resolvePins(agents: { Agent }, pins: { Pin }): { Pin }
	local matched = matchPins(agents, pins)
	local out: { Pin } = {}
	for i, pin in pins do
		local agent = matched[i]
		if agent then
			table.insert(out, {
				pane = agent.pane,
				cwd = agent.cwd or pin.cwd,
				title = agent.title or pin.title,
				sessionFile = agent.sessionFile or pin.sessionFile,
			})
		else
			table.insert(out, pin)
		end
	end
	return out
end

--- The index of the pin that names the agent in `pane`, as the Live view matches them; nil when none does.
function viewModel.pinOf(agents: { Agent }, pins: { Pin }, pane: number): number?
	for i, agent in matchPins(agents, pins) do
		if agent.pane == pane then
			return i
		end
	end
	return nil
end

--- The milliseconds until the view shows something else with no event to say so (a row's or a subagent line's time
--- shows another text, an idle agent folds into "Older than a day", or a quota's reset shows another text or
--- passes), so that the sidebar redraws then; nil when nothing will.
function viewModel.redrawDue(input: Input): number?
	local due: number? = nil
	local function soon(ms: number)
		if due == nil or ms < due then
			due = ms
		end
	end
	local pinned: { [number]: boolean } = {}
	for _, agent in matchPins(input.agents, input.pins or {}) do
		pinned[agent.pane] = true
	end
	local time = input.time
	for _, agent in input.agents do
		local activeAt = agent.activeAt
		if agent.state == "working" then
			soon(untilChange(math.max(0, input.now - (agent.workingSince or input.now))))
		elseif time and activeAt and (agent.state ~= "exited" or pinned[agent.pane]) then
			soon(untilChange(math.max(0, time - activeAt) * 1000))
			local exempt = pinned[agent.pane] or agent.pane == input.focused
			if agent.state == "idle" and not exempt and not isOlder(agent, time) then
				soon((activeAt + OLDER_AFTER - time) * 1000)
			end
		end
		local subs = (input.subagents or {})[agent.pane]
		if subs and agent.state ~= "exited" then
			for _, sub in subs.agents do
				if sub.since then
					soon(untilChange(math.max(0, input.now - sub.since)))
				end
			end
		end
	end
	if time then
		-- A reset a day or more away shows its weekday; a nearer one counts down, and its line goes when it passes.
		-- `time` counts whole seconds: on a boundary, the next text shows a second later.
		for _, hot in hotQuotas(input.quotas, time) do
			local left = hot.left
			local change
			if left >= DAY then
				change = left - DAY
			else
				local unit = if left < MINUTE then 1 elseif left < HOUR then MINUTE else HOUR
				change = left % unit
			end
			soon((if change > 0 then change else 1) * 1000)
		end
	end
	return due
end

-- A folder lists at most this many closed sessions.
local RECENT_SESSIONS = 5

-- A closed session at `depth`: a hollow dot, its title with omp's icon (or "Untitled") and, at the right end, how
-- long ago it was last written. A click resumes it in a new tab; a right-click copies its ID or path.
local function sessionRow(session: Session, time: number?, depth: number): Node
	local children: { Node } = { dotNode("exited", "Closed", true), nameNode(shownTitle(session.title) or "Untitled") }
	if time then
		table.insert(children, timeNode(time - session.at))
	end
	return {
		k = "row",
		p = {
			key = "session-" .. keyPart(session.id or session.file),
			gap = "sm",
			role = rowRole("item", depth),
			actions = { click = "resume=" .. session.file, menu = copyItems(session.file, NO_SESSION_FILE) },
		},
		c = children,
	}
end

-- The hover card line of a Recent folder: how long ago its newest session was written.
local function lastSession(sessions: { Session }, time: number): Node
	return factsNode({ { k = "Last session", v = duration(time - sessions[1].at) .. " ago" } }) :: Node
end

local function folderName(folder: string): string
	return string.match(folder, "([^/]+)/*$") or folder
end

-- A folder of the Recent view at `depth`, with its closed sessions (newest first): its folder row (a click opens
-- or closes it) and, while open, its newest sessions one level under it.
local function recentFolder(folder: string, repo: boolean, sessions: { Session }, depth: number, input: Input): Node
	local key = groupKey(folder)
	local open = (input.recentOpen or {})[key] == true
	local count = math.min(#sessions, RECENT_SESSIONS)
	local time = input.time
	local rows: { Node } = {
		folderRow({
			key = "head",
			click = "recent=" .. key,
			folder = folder,
			name = folderName(folder),
			repo = repo,
			open = open,
			count = count,
			depth = depth,
			home = input.home,
			extra = if time then { lastSession(sessions, time) } else nil,
		}),
	}
	if open then
		for i = 1, count do
			table.insert(rows, sessionRow(sessions[i], time, depth + 1))
		end
	end
	return { k = "col", p = { key = key, gap = "none" }, c = rows }
end

-- A folder without a live agent shows in the Recent view while it has a session written in the last this many
-- seconds.
local RECENT_FOLDER_AGE = 7 * DAY
-- The Recent view shows this many folders until the user opens the rest.
local RECENT_FOLDERS = 5

-- A folder of the Recent view: its folder and its closed sessions, newest first.
type RecentFolder = { folder: string, repo: boolean, sessions: { Session } }

-- The last row of the Recent view while some folders do not show (or, once they all show, the row that hides them
-- again).
local function moreRow(icon: string, text: string): Node
	local children: { Node } = { iconNode(icon, "muted"), nameNode(text, "muted") }
	local p: { [string]: any } = { key = "more", gap = "sm", role = rowRole("item", 0), actions = { click = "recent-more" } }
	return { k = "row", p = p, c = children }
end

-- The folders of the Recent view, each once, the one with the newest closed session first: a folder with a live
-- agent (pinned ones too) and closed sessions of any age, and a folder with no live agent and a closed session from
-- the last week (with no wall-clock time, only the live ones).
local function recentFolders(input: Input, closed: { Session }, sessionsOf: { [string]: { Session } }): { RecentFolder }
	local time = input.time
	local live: { [string]: boolean } = {}
	for _, agent in input.agents do
		local folder = folderOf(agent)
		if folder and agent.state ~= "exited" then
			live[folder] = true
		end
	end
	local folders: { RecentFolder } = {}
	local seen: { [string]: boolean } = {}
	for _, session in closed do
		local folder = folderFor(session.repo, session.cwd)
		if folder and not seen[folder] then
			seen[folder] = true
			if live[folder] or (time ~= nil and time - session.at <= RECENT_FOLDER_AGE) then
				table.insert(folders, { folder = folder, repo = session.repo ~= nil, sessions = sessionsOf[folder] })
			end
		end
	end
	return folders
end

local function sameDir(a: string?, b: string?): boolean
	local x, y = a and nonEmpty(a), b and nonEmpty(b)
	return x ~= nil and y ~= nil and string.match(x, "^(.-)/*$") == string.match(y, "^(.-)/*$")
end

-- The newest session in `cwd` whose title is `title` (both without omp's icon); nil when none is, or either is
-- unknown.
local function titledSession(sessions: { Session }?, cwd: string?, title: string?): string?
	local plain = plainTitle(title)
	if not sessions or not plain then
		return nil
	end
	local best: Session? = nil
	for _, session in sessions do
		if sameDir(session.cwd, cwd) and plainTitle(session.title) == plain and (best == nil or session.at > best.at) then
			best = session
		end
	end
	return best and best.file
end

-- The sessions no live agent has open, newest first. A session a process holds open is live; so is, for each live
-- agent, the newest session of its working directory with its title, or else its newest untitled one (omp titles a
-- session only after the first turns).
local function closedSessions(sessions: { Session }, agents: { Agent }): { Session }
	local ordered = table.clone(sessions)
	table.sort(ordered, function(a, b)
		if a.at ~= b.at then
			return a.at > b.at
		end
		return a.file > b.file
	end)
	local live: { [Session]: boolean } = {}
	local function claim(agent: Agent, title: string?): boolean
		for _, session in ordered do
			if not live[session] and sameDir(session.cwd, agent.cwd) and plainTitle(session.title) == title then
				live[session] = true
				return true
			end
		end
		return false
	end
	for _, agent in startOrder(agents) do
		if agent.state ~= "exited" then
			local title = plainTitle(agent.title)
			if not (title and claim(agent, title)) then
				claim(agent, nil)
			end
		end
	end
	local out: { Session } = {}
	for _, session in ordered do
		if not live[session] and not session.open then
			table.insert(out, session)
		end
	end
	return out
end

-- The waiting agents among `agents`, the one that has waited longest first. An agent's last activity is the moment
-- it began to wait (the entry records it then); an agent with no record counts as waiting since now.
local function waitOrder(agents: { Agent }): { Agent }
	local waiting: { Agent } = {}
	for _, agent in agents do
		if agent.state == "waiting_input" then
			table.insert(waiting, agent)
		end
	end
	table.sort(waiting, function(a, b)
		local ta, tb = a.activeAt or math.huge, b.activeAt or math.huge
		if ta ~= tb then
			return ta < tb
		end
		return a.pane < b.pane
	end)
	return waiting
end

-- The question of a subagent that asks the user: omp's tray names its current call as the tool's verb and what the
-- call acts on, so a running subagent inside the `ask` tool shows `Ask <question>`. Nil for any other subagent; an
-- empty string when the call shows no question.
local function asks(sub: subagents.Subagent): string?
	if sub.status ~= "running" or type(sub.intent) ~= "string" then
		return nil
	end
	local intent = sub.intent :: string
	if intent == "Ask" then
		return ""
	end
	return string.match(intent, "^Ask%s+(.*)$")
end

-- One Needs you card: how long its agent or subagent has waited, in seconds, and its node.
type NeedsCard = { seconds: number, node: Node }

-- A card's footer, in the mono face: the project (the repo, or the folder outside a repo), the tab and, for a
-- subagent, its type; each part left out when unknown. Nil when no part is known.
local function cardFooter(agent: Agent, role: string?): Node?
	local parts: { string } = {}
	local project = folderTail(folderOf(agent))
	if project then
		table.insert(parts, project)
	end
	if agent.tab then
		table.insert(parts, string.format("tab %.0f", agent.tab))
	end
	if role then
		table.insert(parts, role)
	end
	if #parts == 0 then
		return nil
	end
	return { k = "text", p = { spans = { { t = table.concat(parts, " · "), s = "mono" } }, role = ROLE.footer, wrap = "none" } }
end

-- A Needs you card: its head (the title icon or square in the waiting color, the title and the wait time in the
-- waiting color), the question (`agents.css` clamps it to 2 lines), and the footer. The card takes the click, the
-- right-click menu and the hover card of the row it stands for, so it holds no button.
local function needsCard(key: string, icon: Node, title: string, seconds: number?, question: string?, footer: Node?, from: Node): Node
	local head: { Node } = { icon, nameNode(title) }
	if seconds then
		table.insert(head, { k = "text", p = { text = duration(seconds), wrap = "none", role = ROLE.time .. ".waiting" } })
	end
	local children: { Node } = { { k = "row", p = { key = "head", gap = "sm" }, c = head } }
	if question then
		table.insert(children, { k = "text", p = { key = "question", text = clip(question, SUMMARY_FROM), role = ROLE.question } })
	end
	if footer then
		table.insert(children, footer)
	end
	local p = from.p :: { [string]: any }
	return {
		k = "col",
		p = { key = key, role = ROLE.card, gap = "xs", actions = p.actions, hovercard = p.hovercard },
		c = children,
	}
end

-- The Needs you cards, the one that has waited longest first: one per waiting agent (pinned ones too), and one per
-- subagent of a live agent that asks the user, named after itself "in <agent title>". omp gives no start for a
-- subagent's wait, so its card counts from the start of its run.
local function needsCards(input: Input, shared: Shared): { NeedsCard }
	local pinned: { [number]: boolean } = {}
	for _, agent in matchPins(input.agents, input.pins or {}) do
		pinned[agent.pane] = true
	end
	local cards: { NeedsCard } = {}
	for _, agent in waitOrder(input.agents) do
		local shown = shownState(agent, shared)
		local pane = string.format("%.0f", agent.pane)
		local from = row(agent, shared, pinned[agent.pane] == true, 0)
		local icon = titleIcon(agent.title, "waiting", shown.label)
		local node = needsCard("need-" .. pane, icon, rowTitle(agent, shared), shown.seconds, nonEmpty(agent.lastMessage), cardFooter(agent), from)
		table.insert(cards, { seconds = shown.seconds or 0, node = node })
	end
	local subs = input.subagents or {}
	for _, agent in startOrder(input.agents) do
		local crew = subs[agent.pane]
		if crew and agent.state ~= "exited" then
			local pane = string.format("%.0f", agent.pane)
			for _, sub in crew.agents do
				local question = asks(sub)
				if question then
					local levels = string.split(sub.name, ">")
					local title = levels[#levels] .. " in " .. rowTitle(agent, shared)
					local seconds = subSeconds(sub, shared.now)
					local from = subLine(sub, pane, agent.sessionFile, 0, false, false, shared)
					local icon = squareNode("waiting", "Waiting for you")
					local key = "need-" .. pane .. "-" .. keyPart(sub.id)
					local node = needsCard(key, icon, title, seconds, nonEmpty(question), cardFooter(agent, nonEmpty(sub.role)), from)
					table.insert(cards, { seconds = seconds or 0, node = node })
				end
			end
		end
	end
	-- A stable sort: equal waits keep the order above.
	local order: { [NeedsCard]: number } = {}
	for i, card in cards do
		order[card] = i
	end
	table.sort(cards, function(a, b)
		if a.seconds ~= b.seconds then
			return a.seconds > b.seconds
		end
		return order[a] < order[b]
	end)
	return cards
end

-- The action a click on the status segment runs: the "Next waiting agent" command of the plugin `plugin` (Tern names
-- a plugin command `plugin.<plugin id>.<command id>`).
local function nextWaiting(plugin: string?): string?
	return plugin and "plugin." .. plugin .. ".next-waiting"
end

-- The status line counts every agent in a turn, pinned or not; a click on it runs `plugin`'s Next waiting agent.
local function status(agents: { Agent }, plugin: string?): { Segment }
	local working, waiting = 0, 0
	for _, agent in agents do
		if agent.state == "working" then
			working += 1
		elseif agent.state == "waiting_input" then
			waiting += 1
		end
	end
	if working == 0 and waiting == 0 then
		return {}
	end
	local text = string.format("%d working · %d waiting", working, waiting)
	local command = nextWaiting(plugin)
	if waiting > 0 then
		return { { text = text, icon = "bell", tone = "warn", command = command } }
	end
	return { { text = text, icon = "activity", tone = "muted", command = command } }
end

local function context(input: Input): Shared
	local shared: Shared = {
		now = input.now,
		time = input.time,
		perTab = {},
		focused = input.focused,
		viewing = input.viewing or {},
		routes = input.routes or {},
		subsOpen = input.subsOpen or {},
	}
	for _, agent in input.agents do
		if agent.tab then
			shared.perTab[agent.tab] = (shared.perTab[agent.tab] or 0) + 1
		end
	end
	return shared
end

export type Notice = { level: "success" | "info" | "error", text: string, sub: string? }

local NOTICE: { [string]: { level: "success" | "info" | "error", says: string } } = {
	waiting = { level = "info", says = "needs you" },
	done = { level = "success", says = "finished" },
	failed = { level = "error", says = "failed" },
}

--- The toast for the agent in `pane`: it began to wait (`waiting`) or ended its turn (`done`, `failed`). Names the
--- agent as its row does, with the short path of its section's folder below; nil when no agent runs in `pane`.
function viewModel.notice(input: Input, pane: number, what: "waiting" | "done" | "failed"): Notice?
	for _, agent in input.agents do
		if agent.pane == pane then
			local notice = NOTICE[what]
			local folder = folderOf(agent)
			return {
				level = notice.level,
				text = name(agent, context(input)) .. " " .. notice.says,
				sub = folder and viewModel.shortPath(folder, input.home),
			}
		end
	end
	return nil
end

-- A button of the Live/Recent switch, drawn as the shown one when it is.
local function viewButton(label: string, view: View, shown: View): Node
	return {
		k = "button",
		p = {
			text = label,
			size = "sm",
			variant = "quiet",
			role = if view == shown then ROLE.viewOn else ROLE.view,
			actions = { click = "view=" .. view },
		},
	}
end

-- A quota as one line: `Claude · work · 7d 97% · resets Sun`. The reset reads as a weekday when a day or more away,
-- else as the time left (`resets in 38m`).
local function quotaText(quota: Quota, left: number): string
	local parts = { quota.provider }
	if quota.account then
		table.insert(parts, quota.account)
	end
	table.insert(parts, string.format("%s %d%%", quota.label, math.round(quota.used * 100)))
	local reset = if left >= DAY then os.date("%a", quota.resetsAt // 1000) else "in " .. duration(left)
	table.insert(parts, "resets " .. reset)
	return table.concat(parts, " · ")
end

-- The quota line under the Live/Recent switch: the worst quota near or at its limit (exhausted before warning, then
-- the higher use) after a square in the warning or the error color, "+N" for the others, and all of them in the
-- tooltip; nil while every quota is fine.
local function quotaLine(quotas: { Quota }?, time: number?): Node?
	if not time then
		return nil
	end
	local hot = hotQuotas(quotas, time)
	if #hot == 0 then
		return nil
	end
	local lines: { string } = {}
	for _, entry in hot do
		table.insert(lines, quotaText(entry.quota, entry.left))
	end
	local worst = hot[1].quota
	local parts: { Node } = {
		squareNode(if worst.status == "exhausted" then "failed" else "waiting"),
		nameNode(lines[1]),
	}
	if #hot > 1 then
		table.insert(parts, { k = "text", p = { text = "+" .. tostring(#hot - 1), wrap = "none", role = ROLE.meta } })
	end
	return {
		k = "row",
		p = { key = "quota", role = ROLE.quota, gap = "sm", title = table.concat(lines, "\n") },
		c = parts,
	}
end

-- The head: the Live/Recent switch, with the waiting mark and the number of Needs you cards after Live while any
-- shows (in both views), and under it the quota line while a quota is near or at its limit. What the old ⋯ menu did
-- stays in the palette commands.
local function chrome(view: View, input: Input, needs: number): Node
	local views: { Node } = { viewButton("Live", "live", view) }
	if needs > 0 then
		local label = tostring(needs) .. " need you"
		table.insert(views, squareNode("waiting", label))
		table.insert(views, { k = "text", p = { text = tostring(needs), wrap = "none", role = ROLE.needs } })
	end
	table.insert(views, viewButton("Recent", "recent", view))
	local children: { Node } = { { k = "row", p = { key = "views", role = ROLE.views, gap = "none" }, c = views } }
	local quota = quotaLine(input.quotas, input.time)
	if quota then
		table.insert(children, quota)
	end
	return { k = "col", p = { key = "chrome", role = ROLE.chrome, gap = "none" }, c = children }
end

-- The closed sessions of each folder, newest first, by folder.
local function sessionsByFolder(closed: { Session }): { [string]: { Session } }
	local out: { [string]: { Session } } = {}
	for _, session in closed do
		local folder = folderFor(session.repo, session.cwd)
		if folder then
			local list = out[folder] or {}
			out[folder] = list
			table.insert(list, session)
		end
	end
	return out
end

-- A zone of the Live view: its head (the square in its state's color, its name and its status), then `body`.
local function zone(key: string, state: State, title: string, status: string, body: { Node }): Node
	local head: Node = {
		k = "row",
		p = { key = "head", gap = "sm", role = rowRole("head", 0) },
		c = { squareNode(state), nameNode(title), { k = "text", p = { text = status, wrap = "none", role = ROLE.meta } } },
	}
	table.insert(body, 1, head)
	return { k = "col", p = { key = key, role = ROLE.zone, gap = "none" }, c = body }
end

-- The project groups of `agents` (each one a member of a group in `order`) in the order of `order`, each its label
-- and its agents' entries, the agents sorted by `before`.
local function projectGroups(
	order: { Group },
	agents: { Agent },
	before: (Agent, Agent) -> boolean,
	render: (Agent) -> Node,
	home: string?
): { Node }
	local member: { [Agent]: boolean } = {}
	for _, agent in agents do
		member[agent] = true
	end
	local out: { Node } = {}
	for _, group in order do
		local listed: { Agent } = {}
		for _, agent in group.agents do
			if member[agent] then
				table.insert(listed, agent)
			end
		end
		if #listed > 0 then
			table.sort(listed, before)
			local nodes: { Node } = { projectLabel(group, home) }
			for _, agent in listed do
				table.insert(nodes, render(agent))
			end
			table.insert(out, { k = "col", p = { key = group.key, role = ROLE.project, gap = "none" }, c = nodes })
		end
	end
	return out
end

-- The Live view: the zones Needs you (`cards`, the one that has waited longest first), Working and Idle,
-- in that order, each hidden while empty. Inside Working and Idle, the agents group by project, in one project
-- order for every zone: this tab's project first, then by name. Inside a project, this tab's agent comes first, then
-- the pinned agents in pin order, then the others: in Working, the longest turn first; in Idle, the newest turn
-- first and the stopped pins last. A pinned agent that stopped shows in Idle. The idle agents whose last turn ended
-- a day ago or more, but for the pinned ones and this tab's, fold under "Older than a day". A calm line shows while
-- no zone does.
local function liveBody(input: Input, shared: Shared, cards: { NeedsCard }): { Node }
	local subs = input.subagents or {}
	local pins: { Pin } = input.pins or {}
	local matched = matchPins(input.agents, pins)
	local pinned: { [number]: boolean } = {}
	local pinIndex: { [Agent]: number } = {}
	for i, agent in matched do
		pinned[agent.pane] = true
		pinIndex[agent] = i
	end

	local working: { Agent } = {}
	local idle: { Agent } = {}
	local older: { Agent } = {}
	local shown: { Agent } = {}
	-- Stopped pins by the row each one shows as, when its pane is gone: the pin's index.
	local gone: { [Agent]: number } = {}
	for _, agent in input.agents do
		if agent.state == "working" then
			table.insert(working, agent)
			table.insert(shown, agent)
		elseif agent.state == "idle" then
			local exempt = pinned[agent.pane] or agent.pane == shared.focused
			table.insert(if not exempt and isOlder(agent, input.time) then older else idle, agent)
			table.insert(shown, agent)
		end
	end
	-- A pinned agent that stopped: its program exited, or its pane is gone and it shows from what the pin remembers.
	-- A click resumes its session: the one it reported, else the one the pin remembers, else the newest session of
	-- its folder with its title (a pin stored before pins kept the session file).
	local stopped = 0
	for i, pin in pins do
		local agent = matched[i]
		if not agent or agent.state == "exited" then
			local clone: Agent = if agent
				then table.clone(agent)
				else { pane = pin.pane, state = "exited", title = pin.title, cwd = pin.cwd }
			clone.sessionFile = clone.sessionFile or pin.sessionFile or titledSession(input.sessions, clone.cwd, clone.title)
			pinIndex[clone] = i
			if not agent then
				gone[clone] = i
			end
			stopped += 1
			table.insert(idle, clone)
			table.insert(shown, clone)
		end
	end

	-- One project order for every zone: this tab's project first, then the order of `groups` (by name).
	local order = viewModel.groups(shown, input.home)
	for _, agent in input.agents do
		if agent.pane == shared.focused and agent.state ~= "exited" then
			local mine = folderOf(agent)
			for i, group in order do
				if group.folder == mine then
					table.insert(order, 1, table.remove(order, i) :: Group)
					break
				end
			end
		end
	end

	-- This tab's agent first, then the pins in pin order, then the others.
	local function rank(a: Agent, b: Agent): boolean?
		local ma, mb = a.pane == shared.focused and a.state ~= "exited", b.pane == shared.focused and b.state ~= "exited"
		if ma ~= mb then
			return ma
		end
		local pa, pb = pinIndex[a] or math.huge, pinIndex[b] or math.huge
		if pa ~= pb then
			return pa < pb
		end
		return nil
	end
	local function longestTurn(a: Agent, b: Agent): boolean
		local ranked = rank(a, b)
		if ranked ~= nil then
			return ranked
		end
		local sa, sb = a.workingSince or shared.now, b.workingSince or shared.now
		if sa ~= sb then
			return sa < sb
		end
		return a.pane < b.pane
	end
	local function newestTurn(a: Agent, b: Agent): boolean
		local xa, xb = a.state == "exited", b.state == "exited"
		if xa ~= xb then
			return xb
		end
		local ranked = rank(a, b)
		if ranked ~= nil then
			return ranked
		end
		local ta, tb = a.activeAt or math.huge, b.activeAt or math.huge
		if ta ~= tb then
			return ta > tb
		end
		return a.pane < b.pane
	end
	local function render(agent: Agent): Node
		local index = gone[agent]
		if not index then
			return entry(agent, shared, subs[agent.pane], pinIndex[agent] ~= nil, 0)
		end
		-- The pin's pane id may name another agent now, so its Unpin names the pin, not the pane; with no session
		-- file known, a click says the agent is gone.
		local ghost = row(agent, shared, true, 0)
		local key = tostring(index)
		local p = ghost.p :: { [string]: any }
		p.key = "gone-" .. key
		p.role = rowRole("item", 0)
		local items = p.actions.menu :: { { [string]: any } }
		items[1] = { id = "forget=" .. key, label = "Unpin", icon = "pin" }
		if not agent.sessionFile then
			p.actions.click = "gone=" .. key
		end
		return ghost
	end

	local children: { Node } = {}
	if #cards > 0 then
		local nodes: { Node } = {}
		for _, card in cards do
			table.insert(nodes, card.node)
		end
		table.insert(children, zone("zone-needs", "waiting", "Needs you", tostring(#cards), nodes))
	end
	if #working > 0 then
		local body = projectGroups(order, working, longestTurn, render, input.home)
		table.insert(children, zone("zone-working", "working", "Working", #working .. " busy", body))
	end
	if #idle + #older > 0 then
		local body = projectGroups(order, idle, newestTurn, render, input.home)
		if #older > 0 then
			local open = input.olderOpen == true
			table.insert(body, foldRow("older", "Older than a day", #older, open, "older", 0))
			if open then
				local groups = projectGroups(order, older, newestTurn, render, input.home)
				table.insert(body, { k = "col", p = { key = "older-list", role = ROLE.older, gap = "none" }, c = groups })
			end
		end
		local status = tostring(#idle + #older) .. (if stopped > 0 then string.format(" · %d stopped", stopped) else "")
		table.insert(children, zone("zone-idle", "idle", "Idle", status, body))
	end
	if #children == 0 then
		table.insert(children, {
			k = "text",
			p = { key = "calm", role = ROLE.calm, text = "No agent runs. Open Recent to resume a session" },
		})
	end
	return children
end

-- The Recent view: its folders at the top level (see `recentFolders`), 5 of them until the "N more" row at the end
-- opens the rest; an empty state when there is no closed session to show.
local function recentBody(input: Input): { Node }
	local closed = closedSessions(input.sessions or {}, input.agents)
	local folders = recentFolders(input, closed, sessionsByFolder(closed))
	local children: { Node } = {}
	local shown = if input.recentAll then #folders else math.min(#folders, RECENT_FOLDERS)
	for i = 1, shown do
		local recent = folders[i]
		table.insert(children, recentFolder(recent.folder, recent.repo, recent.sessions, 0, input))
	end
	if #folders > RECENT_FOLDERS then
		table.insert(
			children,
			if input.recentAll then moreRow("chev", "Show fewer") else moreRow("more", string.format("%d more", #folders - shown))
		)
	end
	if #children == 0 then
		table.insert(children, {
			k = "empty",
			p = {
				key = "empty",
				icon = "history",
				title = "No recent sessions",
				text = "Closed omp sessions of the last 7 days show here",
			},
		})
	end
	return children
end

function viewModel.build(input: Input): Output
	local shared = context(input)
	local view: View = if input.view == "recent" then "recent" else "live"
	local cards = needsCards(input, shared)
	local body = if view == "recent" then recentBody(input) else liveBody(input, shared, cards)
	local waiting: { number } = {}
	for _, agent in waitOrder(input.agents) do
		table.insert(waiting, agent.pane)
	end
	return {
		view = {
			k = "col",
			p = { role = ROLE.root, gap = "none" },
			c = {
				chrome(view, input, #cards),
				{ k = "col", p = { key = "body", role = ROLE.body, gap = "none" }, c = body },
			},
		},
		status = status(input.agents, input.plugin),
		waiting = waiting,
	}
end

return viewModel
