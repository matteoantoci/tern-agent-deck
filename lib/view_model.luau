--!strict
-- The pure view model: turns the agent list into the sidebar's canvas node tree.
-- Calls no Tern API, so the plain `luau` CLI can load and test it.

local providers = require("./providers")
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
	--- The thinking-effort level of omp's composer (`off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, or
	--- `auto` before it resolves); nil for an agent that shows none.
	effort: string?,
	--- The agent's last assistant message (Markdown).
	lastMessage: string?,
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
--- for when the pane id changes (a daemon restart).
export type Pin = {
	pane: number,
	cwd: string?,
	title: string?,
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

--- What the sidebar lists: the live agents (Needs you, Pinned, the folders with their agents and subagents) or the
--- closed sessions (the folders with closed sessions, newest first).
export type View = "live" | "recent"

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
	--- The keys of the groups whose "Older" row is open.
	olderOpen: { [string]: boolean }?,
	--- The keys of the folder sections the user folded in the Live view: they show only their folder row.
	folded: { [string]: boolean }?,
	--- The omp sessions the reader found, in any order; nil before the first read.
	sessions: { Session }?,
	--- The keys of the folders whose closed sessions show in the Recent view.
	recentOpen: { [string]: boolean }?,
	--- Whether the Recent view shows every folder, rather than only the first few.
	recentAll: boolean?,
	--- The view the strip shows chosen; Live when nil.
	view: View?,
	--- The pane the user last focused outside the sidebar: its agent's row is drawn selected.
	focused: number?,
	--- The omp id of the subagent each pane's omp shows in its view ("Viewing <name>"), by pane: while the focused
	--- pane shows one, that subagent's row is drawn selected instead of its agent's.
	viewing: { [number]: string }?,
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

-- Color goes only to states that ask for a look: working (accent) and waiting (warning). An idle agent is the resting
-- state, a filled neutral dot. A hollow dot marks a row that is not updated live: an exited pinned agent, a closed
-- session, or a subagent the sidebar cannot read while omp shows another one (it may still run). A working dot
-- pulses, as the dot of a running subagent in omp's own view does.
local DOT: { [AgentState]: { tone: string, label: string, hollow: boolean?, pulse: boolean? } } = {
	working = { tone = "accent", label = "Working", pulse = true },
	waiting_input = { tone = "warning", label = "Waiting for you" },
	idle = { tone = "muted", label = "Idle" },
	exited = { tone = "dim", label = "Exited", hollow = true },
}

-- A hover card holds at most this many bytes of the last message, so that a long answer does not
-- fill the canvas's 256 KiB per update.
local MESSAGE_BYTES = 4000

local function clip(text: string): string
	if #text <= MESSAGE_BYTES then
		return text
	end
	local cut = MESSAGE_BYTES
	-- Back off to the start of a UTF-8 character.
	while cut > 1 and bit32.band(string.byte(text, cut + 1), 0xC0) == 0x80 do
		cut -= 1
	end
	return string.sub(text, 1, cut) .. "…"
end

-- Context every row reads: the time, how many agents share each tab, and the focused pane.
type Shared = { now: number, perTab: { [number]: number }, focused: number?, viewing: { [number]: string } }

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

-- The agent's own name: the pane title, else the folder name.
local function ownName(agent: Agent): string
	return plainTitle(agent.title)
		or (agent.cwd and nonEmpty(string.match(agent.cwd, "([^/]+)/*$")))
		or "Agent"
end

-- The tab name the user set, when the agent is alone in its tab; else the pane title; else the folder name.
local function name(agent: Agent, shared: Shared): string
	local tabName = nonEmpty(agent.tabName)
	if tabName and agent.tab and shared.perTab[agent.tab] == 1 then
		return tabName
	end
	return ownName(agent)
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
-- it needs an omp agent (one that reported its session file) whose composer runs commands: not while omp shows a
-- subagent (the composer is that subagent's chat box then) or while the agent waits for an answer.
local function renameOff(agent: Agent, viewingSub: boolean): string?
	if not agent.sessionFile then
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

-- The roles `agents.css` styles; the sidebar copies the look of Tern's Files pane. The root sets the canvas in the
-- sans face; the chrome holds the head (the glyph, the title, the tools) and the view strip. Each list row has the
-- role `agents.<kind>.<depth>` (see `rowRole`); its parts: the chevron, the 14 px icon column (a toned icon, a state
-- dot, or an untoned glyph in the icon color: the head's and the folder rows'), the name and the dim detail (cut with
-- an ellipsis in CSS, so that Tern adds no tooltip of its own under a row's hover card), the count a folder row shows
-- on hover and the one a head always shows, the controls that show on hover, and the spinner or bell at an agent
-- row's right end.
local ROLE = {
	root = "agents.root",
	chrome = "agents.chrome",
	top = "agents.top",
	glyph = "agents.glyph",
	title = "agents.title",
	tool = "agents.tool",
	hide = "agents.hide",
	views = "agents.views",
	view = "agents.view",
	viewOn = "agents.view.on",
	body = "agents.body",
	chev = "agents.chev",
	icon = "agents.icon",
	dot = "agents.dot",
	name = "agents.name",
	detail = "agents.detail",
	count = "agents.count",
	meta = "agents.meta",
	hover = "agents.hover",
	status = "agents.status",
}

-- A list row's kind: `item` (a clickable row: an agent, a subagent, a session, "N more"), `on` (the focused
-- agent's row, drawn selected), `folder` (a folder row with its chevron), `fold` (Older: a chevron and a label),
-- `head` (Needs you, Pinned) and `info` (the done and incomplete lines, which take no click).
type Kind = "item" | "on" | "folder" | "fold" | "head" | "info"

-- `agents.<kind>.<depth>`: the CSS indents a row by its depth (depth 1 under its folder's glyph, any deeper one
-- 10 px step more) and draws the guide line.
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

-- The secondary part after a name (a subagent's role and parent, a waiting agent's folder): plain text, so that
-- `agents.css` draws it dimmer and smaller than the name; it takes the free room and is cut first when the row is
-- narrow.
local function detailNode(text: string): Node
	return { k = "text", p = { text = text, role = ROLE.detail, grow = 1, basis = 0 } }
end

-- A state dot in the 14 px icon column: filled, or hollow for a row that is not updated live. A live dot takes Tern's
-- `pulse` effect (opacity 1 → 0.45 over 1.6 s), the look of a running subagent's dot in omp's own view; Tern stops it
-- under reduced motion and while the pane is hidden.
local function dotNode(tone: string, label: string, hollow: boolean?, pulse: boolean?): Node
	local span: { [string]: string } = { t = if hollow then "○" else "●", s = tone }
	if pulse then
		span.fx = "pulse"
	end
	return { k = "text", p = { spans = { span }, aria = label, role = ROLE.dot } }
end

-- One hover-card line: a muted label and its value.
local function fact(label: string, value: string): Node
	local spans: { { [string]: string } } = { { t = label .. " ", s = "muted" }, { t = value } }
	return { k = "text", p = { spans = spans } }
end

-- The hover card's first line: the name, and the state after it.
local function cardHead(name: string, state: string): Node
	return { k = "text", p = { spans = { { t = name, s = "strong" }, { t = " · " .. state, s = "muted" } } } }
end

-- The hover card's effort line: the glyph and the level.
local function effortFact(level: string): Node
	local children: { Node } = { { k = "effort", p = { level = level } }, fact("Effort", level) }
	return { k = "row", p = { gap = "sm" }, c = children }
end

-- The hover card's model line: the provider's logo, when the table knows the model's maker, and the model.
local function modelFact(model: string): Node
	local provider = providers.of(model)
	if not provider then
		return fact("Model", model)
	end
	local children: { Node } = { { k = "icon", p = { name = "provider-" .. provider } }, fact("Model", model) }
	return { k = "row", p = { gap = "sm" }, c = children }
end

-- The mark at the right end of an agent row: the spinner while it works, the bell while it waits for the user. Both
-- stay neutral: the state dot carries the color.
local function endMark(state: AgentState): Node?
	if state == "working" then
		return { k = "spinner", p = { style = "braille", tone = "muted", role = ROLE.status } }
	elseif state == "waiting_input" then
		return { k = "icon", p = { name = "bell", tone = "muted", role = ROLE.status } }
	end
	return nil
end

-- An agent's row at `depth` in the tree: the state dot, the name and, when `place` is given, the repo's folder name
-- after it (the Needs you strip shows where each agent works), then the spinner or the bell. A row carries no
-- tooltip: its hover card holds every fact: the state, the repo, the model with its provider's logo, the effort,
-- the live turn timer and the last message.
local function row(agent: Agent, shared: Shared, pinned: boolean, depth: number, place: { name: string, path: string }?): Node
	local dot = DOT[agent.state]
	local shownName = name(agent, shared)
	local children: { Node } = {
		dotNode(dot.tone, dot.label, dot.hollow, dot.pulse),
		-- An exited agent shows only while pinned, dimmed.
		nameNode(shownName, if agent.state == "exited" then "dim" else nil, place ~= nil),
	}
	local card: { Node } = { cardHead(shownName, dot.label) }
	if place then
		table.insert(children, detailNode(place.name))
		table.insert(card, fact("Repo", place.path))
	end
	local mark = endMark(agent.state)
	if mark then
		table.insert(children, mark)
	end
	local model = plainModel(agent.model)
	if model then
		table.insert(card, modelFact(model))
	end
	local effort = nonEmpty(agent.effort)
	if effort then
		table.insert(card, effortFact(effort))
	end
	if agent.state == "working" then
		local age = math.max(0, shared.now - (agent.workingSince or shared.now))
		local timer: { Node } = { { k = "text", p = { spans = { { t = "Working for", s = "muted" } } } }, { k = "elapsed", p = { age = age } } }
		table.insert(card, { k = "row", p = { gap = "sm" }, c = timer })
	end
	local message = nonEmpty(agent.lastMessage)
	if message then
		table.insert(card, { k = "md", p = { text = clip(message) } })
	end
	local pane = string.format("%.0f", agent.pane)
	local props: { [string]: any } = {
		key = "agent-" .. pane,
		gap = "sm",
		role = rowRole(if shared.focused == agent.pane then "on" else "item", depth),
		actions = { click = "focus=" .. pane, menu = menu(agent, pane, pinned, shared.viewing[agent.pane] ~= nil) },
		hovercard = { k = "col", p = { gap = "xs" }, c = card },
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
--- has not exited, named as its row names it (the pane title without omp's icon, else the folder). Tabs without
--- such an agent are absent.
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

-- The Files pane's folder glyphs: Material Icon Theme's filled folders.
local FOLDER, FOLDER_OPEN = "mi-folder", "mi-folder-open"

-- An icon in the 14 px icon column.
local function iconNode(icon: string, tone: string?): Node
	return { k = "icon", p = { name = icon, tone = tone, role = ROLE.icon } }
end

-- The chevron of a row that opens and closes the rows under it.
local function chevron(open: boolean): Node
	return { k = "icon", p = { name = if open then "chev" else "chev-r", role = ROLE.chev } }
end

-- A count in the Files pane's small mono digits: always shown (`meta`), or only while the pointer is on its row
-- (`count`).
local function countNode(count: number, role: string): Node
	return { k = "text", p = { spans = { { t = tostring(count), s = "muted" } }, wrap = "none", role = role } }
end

-- A section head (Needs you, Pinned): its icon, its label and the count of its rows. It takes no click.
local function head(icon: string, tone: string, label: string, count: number): Node
	local children: { Node } = { iconNode(icon, tone), nameNode(label), countNode(count, ROLE.meta) }
	return { k = "row", p = { key = "head", gap = "sm", role = rowRole("head", 0) }, c = children }
end

-- A row that opens and closes the rows under it and is no folder (Older): the chevron, its label and its count. A
-- click on it sends `click`.
local function foldRow(key: string, label: string, count: number, open: boolean, click: string, depth: number): Node
	local children: { Node } = { chevron(open), nameNode(label, "muted"), countNode(count, ROLE.meta) }
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

-- What a folder row shows: its key and the action of a click on it, the folder (nil for agents with none) and its
-- name, whether it is a repo, whether it shows its rows, the count of its rows, its depth, and the lines its hover
-- card adds after the short path.
type FolderSpec = {
	key: string,
	click: string,
	folder: string?,
	name: string,
	repo: boolean,
	open: boolean,
	count: number,
	depth: number,
	home: string?,
	extra: { Node }?,
}

-- A folder row like the Files pane's: the chevron (open while it shows its rows), the folder glyph, the folder's
-- name, and, while the pointer is on it, the count of its rows and the `+` that starts an agent there. Its hover card
-- gives the folder's short path.
local function folderRow(spec: FolderSpec): Node
	local children: { Node } = {
		chevron(spec.open),
		{ k = "icon", p = { name = if spec.open then FOLDER_OPEN else FOLDER, role = ROLE.glyph } },
		nameNode(spec.name),
		countNode(spec.count, ROLE.count),
	}
	local p: { [string]: any } = {
		key = spec.key,
		gap = "sm",
		role = rowRole("folder", spec.depth),
		actions = { click = spec.click },
	}
	local folder = spec.folder
	if folder then
		table.insert(children, plusButton(folder, spec.repo))
		local card: { Node } = { { k = "text", p = { spans = { { t = viewModel.shortPath(folder, spec.home), s = "path" } } } } }
		for _, line in spec.extra or ({} :: { Node }) do
			table.insert(card, line)
		end
		p.hovercard = { k = "col", p = { gap = "xs" }, c = card }
	end
	return { k = "row", p = p, c = children }
end

-- Whether a group's agents work in a git repo (else in a plain folder).
local function isRepo(group: Group): boolean
	local first = group.agents[1]
	return first ~= nil and first.repo ~= nil
end

-- omp renders nested subagents down to its `MAX_NESTED_TASK_RENDER_DEPTH` (8), counting the first level as 0: the
-- sidebar lists every level it sends (depth 1 to 9 here), and only a deeper one, if omp ever sent it, folds into
-- one "+N deeper" line.
local MAX_DEPTH = 8 + 1

local FINISHED = { done = true, failed = true, aborted = true }

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

-- One running subagent, at any nesting level, at `depth` in the tree (one level under its agent): the running dot,
-- the name, a dim detail with its type and, below the first level, the subagent it runs under, and the spinner. The
-- hover card repeats them with the model, effort, current tool and intent. A click asks to show the subagent in omp's
-- view (`subagent=<pane> <node id>`); a right-click copies the ID or path of its own session file, found from its
-- agent's (`agentFile`). A `frozen` row (its state is the last one read, while omp shows another subagent) has a
-- muted dot, no spinner, and says so.
local function subRow(
	sub: subagents.Subagent,
	pane: string,
	agentFile: string?,
	depth: number,
	selected: boolean,
	frozen: boolean
): Node
	local role = nonEmpty(sub.role)
	local parent = if sub.depth > 1 then nonEmpty(sub.parent) else nil
	local detail: { string } = {}
	if role then
		table.insert(detail, role)
	end
	if parent then
		table.insert(detail, "in " .. parent)
	end
	local state = if frozen then "Not live" else "Running"
	local children: { Node } =
		{ dotNode(if frozen then "dim" else "accent", state, frozen, not frozen), nameNode(sub.name, nil, #detail > 0) }
	if #detail > 0 then
		table.insert(children, detailNode(table.concat(detail, " · ")))
	end
	if not frozen then
		table.insert(children, endMark("working") :: Node)
	end
	local card: { Node } = { cardHead(sub.name, state) }
	if role then
		table.insert(card, fact("Role", role))
	end
	if parent then
		table.insert(card, fact("Under", parent))
	end
	-- omp names a subagent's model with its route (`anthropic/claude-opus-5-5`); the model alone is enough.
	local model = sub.model and nonEmpty(string.match(sub.model, "([^/]*)$"))
	if model then
		table.insert(card, fact("Model", model))
	end
	local effort = nonEmpty(sub.effort)
	if effort then
		table.insert(card, effortFact(effort))
	end
	local tool = nonEmpty(sub.tool)
	if tool then
		table.insert(card, fact("Tool", tool))
	end
	local intent = nonEmpty(sub.intent)
	if intent then
		table.insert(card, fact("Intent", intent))
	end
	if frozen then
		table.insert(card, { k = "text", p = { spans = { { t = "Not updated while omp shows another subagent", s = "muted" } } } })
	end
	return {
		k = "row",
		p = {
			key = "sub-" .. keyPart(sub.id),
			gap = "sm",
			role = rowRole(if selected then "on" else "item", depth),
			actions = {
				click = "subagent=" .. pane .. " " .. sub.id,
				menu = copyItems(
					subagentFile(agentFile, sub.name),
					if agentFile then "The subagent's name is no omp id" else NO_SESSION_FILE
				),
			},
			hovercard = { k = "col", p = { gap = "xs" }, c = card },
		},
		c = children,
	}
end

-- A line under the subagents that says something about them and takes no click: the done count, the cut read.
local function infoLine(key: string, icon: string, tone: string, text: string, style: string, depth: number): Node
	local children: { Node } = { iconNode(icon, tone), nameNode(text, style) }
	return { k = "row", p = { key = key, gap = "sm", role = rowRole("info", depth) }, c = children }
end

-- Whether any of `subs` runs: omp runs `task` subagents in the background, so they can outlive their agent's turn.
local function running(subs: subagents.Subagents): boolean
	for _, sub in subs.agents do
		if sub.status == "running" then
			return true
		end
	end
	return false
end

-- The agent's row at `depth`, wrapped while it works or any of its subagents runs with the rows of its running subagents at every nesting level,
-- one line that counts the finished ones, and a warning when Tern cut the read, all one level deeper.
local function entry(agent: Agent, shared: Shared, subs: subagents.Subagents?, pinned: boolean, depth: number): Node
	local main = row(agent, shared, pinned, depth)
	if not subs or not (agent.state == "working" or (agent.state ~= "exited" and running(subs))) then
		return main
	end
	local pane = string.format("%.0f", agent.pane)
	local lines: { Node } = { main }
	local done, deeper = 0, 0
	-- The subagent the focused pane's omp shows takes the selection from its agent's row.
	local viewed = shared.viewing[agent.pane]
	local shown = if shared.focused == agent.pane then viewed else nil
	for _, sub in subs.agents do
		if sub.depth > MAX_DEPTH then
			if sub.status == "running" then
				deeper += 1
			end
		elseif sub.status == "running" then
			local selected = viewing.shows(sub, shown)
			if selected then
				(main.p :: { [string]: any }).role = rowRole("item", depth)
			end
			local frozen = subs.frozen == true and not viewing.shows(sub, viewed)
			table.insert(lines, subRow(sub, pane, agent.sessionFile, depth + 1, selected, frozen))
		elseif FINISHED[sub.status] then
			done += 1
		end
	end
	if deeper > 0 then
		local text = string.format("+%d deeper", deeper)
		table.insert(lines, infoLine("subs-deeper", "more", "muted", text, "muted", depth + 1))
	end
	if done > 0 then
		local text = string.format("%d %s done", done, if done == 1 then "subagent" else "subagents")
		table.insert(lines, infoLine("subs-done", "check", "muted", text, "muted", depth + 1))
	end
	if subs.incomplete then
		local text = "subagents may be incomplete"
		table.insert(lines, infoLine("subs-incomplete", "warn", "warning", text, "warning", depth + 1))
	end
	if #lines == 1 then
		return main
	end
	return { k = "col", p = { key = "tree-" .. pane, gap = "none" }, c = lines }
end

-- An idle agent whose last turn ended this long ago (in seconds) folds into its group's "Older" row.
local OLDER_AFTER = DAY

local function isOlder(agent: Agent, time: number?): boolean
	local activeAt = agent.activeAt
	return agent.state == "idle" and time ~= nil and activeAt ~= nil and time - activeAt >= OLDER_AFTER
end

--- The seconds until the next idle agent folds into "Older", so that the sidebar redraws then; nil when none will.
function viewModel.olderDue(input: Input): number?
	local time = input.time
	if time == nil then
		return nil
	end
	local due: number? = nil
	for _, agent in input.agents do
		local activeAt = agent.activeAt
		if agent.state == "idle" and activeAt ~= nil and not isOlder(agent, time) then
			local left = activeAt + OLDER_AFTER - time
			if due == nil or left < due then
				due = left
			end
		end
	end
	return due
end

-- Which agent each pin names, by the pin's index: the agent in the pin's pane when its working directory agrees,
-- else the first agent, in start order, that no other pin names and that has the pin's working directory and title.
local function matchPins(agents: { Agent }, pins: { Pin }): { [number]: Agent }
	local byPane: { [number]: Agent } = {}
	for _, agent in agents do
		byPane[agent.pane] = agent
	end
	local matched: { [number]: Agent } = {}
	local taken: { [Agent]: boolean } = {}
	for i, pin in pins do
		local agent = byPane[pin.pane]
		if agent and not taken[agent] and (pin.cwd == nil or agent.cwd == pin.cwd) then
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

--- The pins with the pane id, working directory and title of the agent each one names now, so that the backup
--- keys follow the agent and a pin found by them takes its new pane id. A pin that names no agent stays as it is.
function viewModel.resolvePins(agents: { Agent }, pins: { Pin }): { Pin }
	local matched = matchPins(agents, pins)
	local out: { Pin } = {}
	for i, pin in pins do
		local agent = matched[i]
		if agent then
			table.insert(out, { pane = agent.pane, cwd = agent.cwd or pin.cwd, title = agent.title or pin.title })
		else
			table.insert(out, pin)
		end
	end
	return out
end

--- The index of the pin that names the agent in `pane`, as the Pinned section matches them; nil when none does.
function viewModel.pinOf(agents: { Agent }, pins: { Pin }, pane: number): number?
	for i, agent in matchPins(agents, pins) do
		if agent.pane == pane then
			return i
		end
	end
	return nil
end

-- A folder lists at most this many closed sessions.
local RECENT_SESSIONS = 5

-- How long ago `seconds` was, in the largest whole unit: `now`, `5m`, `2h`, `3d`.
local function ago(seconds: number): string
	if seconds < MINUTE then
		return "now"
	elseif seconds < HOUR then
		return string.format("%dm", seconds // MINUTE)
	elseif seconds < DAY then
		return string.format("%dh", seconds // HOUR)
	end
	return string.format("%dd", seconds // DAY)
end

-- A closed session at `depth`: a hollow dot, its title (or "Untitled") and, at the right end, how long ago it was
-- last written. A click resumes it in a new tab; a right-click copies its ID or path.
local function sessionRow(session: Session, time: number?, depth: number): Node
	local children: { Node } = { dotNode("dim", "Closed", true), nameNode(plainTitle(session.title) or "Untitled") }
	if time then
		local age = ago(math.max(0, time - session.at))
		table.insert(children, { k = "text", p = { spans = { { t = age, s = "muted" } }, wrap = "none", role = ROLE.meta } })
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
	local when = ago(math.max(0, time - sessions[1].at))
	return fact("Last session", if when == "now" then "just now" else when .. " ago")
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
	local shared: Shared = { now = input.now, perTab = {}, focused = input.focused, viewing = input.viewing or {} }
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

-- The ⋯ menu of the head: what the palette commands do, from the sidebar.
local MORE: { any } = {
	{ id = "new-here", label = "New tab here", icon = "plus" },
	{ id = "arrange-by-repo", label = "Arrange tabs by project", icon = "folder" },
	"-",
	{ id = "toggle-sidebar", label = "Toggle sidebar", icon = "sidebar", keys = { "cmd", "alt", "A" } },
}

-- A quiet icon button of the head or the view strip.
local function toolButton(icon: string, title: string, role: string, click: string): Node
	return {
		k = "button",
		p = { icon = icon, size = "sm", variant = "quiet", title = title, role = role, actions = { click = click } },
	}
end

-- The head, as the Files pane's: the glyph, the bold title, the ⋯ menu and the button that hides the sidebar; then
-- the strip of view buttons, the shown one tinted.
local function chrome(view: View): Node
	local top: { Node } = {
		{ k = "icon", p = { name = "users", role = ROLE.glyph } },
		{ k = "text", p = { text = "Agents", role = ROLE.title, grow = 1 } },
		{
			k = "menu",
			p = { icon = "more", title = "More", trigger = "quiet", size = "sm", align = "end", role = ROLE.tool, items = MORE },
		},
		toolButton("sidebar", "Hide sidebar", ROLE.hide, "toggle-sidebar"),
	}
	local views: { Node } = {
		toolButton("activity", "Live", if view == "live" then ROLE.viewOn else ROLE.view, "view=live"),
		toolButton("history", "Recent", if view == "recent" then ROLE.viewOn else ROLE.view, "view=recent"),
	}
	return {
		k = "col",
		p = { key = "chrome", role = ROLE.chrome, gap = "none" },
		c = {
			{ k = "row", p = { key = "top", role = ROLE.top, gap = "sm" }, c = top },
			{ k = "row", p = { key = "views", role = ROLE.views, gap = "xs" }, c = views },
		},
	}
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

-- The Live view: Needs you, Pinned, then each folder's row with its agents (and their subagents) one level under
-- it, the old idle ones under its Older row. An empty state offers a new agent when no agent shows.
local function liveBody(input: Input, shared: Shared): { Node }
	local subs = input.subagents or {}
	local olderOpen = input.olderOpen or {}
	local pins: { Pin } = input.pins or {}
	local matched = matchPins(input.agents, pins)
	local pinned: { [number]: boolean } = {}
	for _, agent in matched do
		pinned[agent.pane] = true
	end
	-- Pinned agents show only in Pinned; exited agents leave the list unless pinned.
	local listed: { Agent } = {}
	for _, agent in input.agents do
		if not pinned[agent.pane] and agent.state ~= "exited" then
			table.insert(listed, agent)
		end
	end

	local children: { Node } = {}
	-- Needs you: the waiting agents that are not pinned, which also keep their rows in their folder sections. Each
	-- names its folder.
	local strip: { Node } = {}
	for _, agent in waitOrder(listed) do
		local folder = folderOf(agent)
		local place = folder and { name = folderName(folder), path = viewModel.shortPath(folder, input.home) }
		table.insert(strip, row(agent, shared, false, 1, place))
	end
	if #strip > 0 then
		table.insert(strip, 1, head("bell", "warning", "Needs you", #strip))
		table.insert(children, { k = "col", p = { key = "needs-you", gap = "none" }, c = strip })
	end
	if #pins > 0 then
		local section: { Node } = { head("pin", "muted", "Pinned", #pins) }
		for i, pin in pins do
			local agent = matched[i]
			if agent then
				table.insert(section, entry(agent, shared, subs[agent.pane], true, 1))
			else
				-- The pinned agent is gone: it shows as exited, from what the pin remembers. Its pane id may name
				-- another agent now, so its click and menu name the pin, not the pane.
				local ghost = row({ pane = pin.pane, state = "exited", title = pin.title, cwd = pin.cwd }, shared, true, 1)
				local index = tostring(i)
				local p = ghost.p :: { [string]: any }
				p.key = "gone-" .. index
				p.role = rowRole("item", 1)
				p.actions = { click = "gone=" .. index, menu = { { id = "forget=" .. index, label = "Unpin", icon = "pin" } } }
				table.insert(section, ghost)
			end
		end
		table.insert(children, { k = "col", p = { key = "pinned", gap = "none" }, c = section })
	end

	local groups = viewModel.groups(listed, input.home)
	if #pins == 0 and #groups == 0 then
		local start: Node = {
			k = "button",
			p = { text = "New tab here", icon = "plus", size = "sm", actions = { click = "new-here" } },
		}
		table.insert(children, {
			k = "empty",
			p = {
				key = "empty",
				icon = "terminal",
				title = "No agents running",
				text = "Start one here, or run omp in any pane",
			},
			c = { start },
		})
	end
	-- Each folder's section: its folder row, then, unless the user folded it, the agents in start order and the
	-- "Older" row with, while it is open, the old idle agents one level under it.
	local folded = input.folded or {}
	for _, group in groups do
		local open = folded[group.key] ~= true
		local section: { Node } = {
			folderRow({
				key = "head",
				click = "fold=" .. group.key,
				folder = group.folder,
				name = group.name,
				repo = isRepo(group),
				open = open,
				count = #group.agents,
				depth = 0,
				home = input.home,
			}),
		}
		if open then
			local older: { Agent } = {}
			for _, agent in group.agents do
				if isOlder(agent, input.time) then
					table.insert(older, agent)
				else
					table.insert(section, entry(agent, shared, subs[agent.pane], false, 1))
				end
			end
			if #older > 0 then
				local olderShown = olderOpen[group.key] == true
				table.insert(section, foldRow("older", "Older", #older, olderShown, "older=" .. group.key, 1))
				if olderShown then
					for _, agent in older do
						table.insert(section, entry(agent, shared, subs[agent.pane], false, 2))
					end
				end
			end
		end
		table.insert(children, { k = "col", p = { key = group.key, gap = "none" }, c = section })
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
	local body = if view == "recent" then recentBody(input) else liveBody(input, shared)
	local waiting: { number } = {}
	for _, agent in waitOrder(input.agents) do
		table.insert(waiting, agent.pane)
	end
	return {
		view = {
			k = "col",
			p = { role = ROLE.root, gap = "none" },
			c = { chrome(view), { k = "col", p = { key = "body", role = ROLE.body, gap = "none" }, c = body } },
		},
		status = status(input.agents, input.plugin),
		waiting = waiting,
	}
end

return viewModel
