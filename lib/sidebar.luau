--!strict
-- The sidebar manager: reads the agents and the panes they run in from Tern, feeds the view model, and keeps one
-- Agents canvas in every tab up to date. Every Tern call of the sidebar lives here or in the entry; the view
-- model, the placement plan and the patch diff make none.

local backToMain = require("./back_to_main")
local effortReader = require("./effort_reader")
local newTab = require("./new_tab")
local patch = require("./patch")
local placement = require("./placement")
local rename = require("./rename")
local repoRoot = require("./repo_root")
local sessionCopy = require("./session_copy")
local sessionReader = require("./session_reader")
local store = require("./store")
local subagentReader = require("./subagent_reader")
local subagents = require("./subagents")
local viewModel = require("./view_model")
local viewing = require("./viewing")

local sidebar = {}

local TITLE = "Agents"
local ABOUT = "Lists the coding agents of every Tern session. A click on a row focuses that agent."
-- `tern.kv` keys, shared by every window and kept across restarts: whether the user hid the sidebar, the shared
-- width, and the copies a window closed itself in the last few seconds, by pane.
local HIDDEN_KEY, WIDTH_KEY, CLOSING_KEY = "hidden", "width", "closing"
-- How long (`os.time()` seconds) a window's own close of a copy stays known to the other windows.
local CLOSING_FOR = 5
-- How long (`tern.now()` milliseconds) a copy this VM opened counts as ours while `cx.canvas:list()` does not show
-- it yet. After that only the list says which panes are this plugin's canvases: a pane id can name another pane
-- later (a daemon restart).
local OPEN_GRACE = 1000

-- One sidebar canvas: its tab, what it shows (the view and the `tern.now()` it was built at), the width and tree
-- shape it had when this VM last looked or set it, the shared width this VM last resized it toward, and when this
-- VM opened it.
type Copy = {
	tab: number?,
	view: viewModel.Node?,
	now: number,
	width: number?,
	shape: string?,
	goal: number?,
	openedAt: number?,
}

-- This plugin's canvases, by pane.
local copies: { [number]: Copy } = {}
-- Canvases this VM closes, so that their `pane_closed` does not read as the user's ⌘W.
local closing: { [number]: boolean } = {}
-- The tab of each copy that left the canvas list before this VM heard its `pane_closed`.
local vanished: { [number]: number } = {}
-- The tab the last sync saw in front, to spot a width the user dragged there before switching.
local lastTab: number? = nil
-- Terminal cells across a tab, learnt from each resize (`cx.layout:resize` counts in cells); a first guess.
local tabCells = 150
-- Opening a copy failed once already: do not toast about each tab.
local openFailed = false
-- Drawing into a copy failed once already: do not toast on each refresh.
local setFailed = false
-- The status line segments and the tab titles (the main agent's name by tab id) the last build gave, for the
-- chrome formatters (which may not call Tern), and the input of that build, for the toasts.
local segments: { viewModel.Segment } = {}
local titles: { [number]: string } = {}
local latest: viewModel.Input? = nil
-- The pane the user last focused outside the sidebar: its agent's row shows selected, and "New tab here" opens in
-- its folder. A click on the sidebar focuses the sidebar, which keeps the last one.
local lastFocused: number? = nil

local function focusedPane(cx: WindowCx): number?
	local focused = cx.session:focused()
	if focused and not copies[focused] then
		lastFocused = focused
	end
	return lastFocused
end

local function str(value: any): string?
	if type(value) == "string" then
		return value
	end
	return nil
end

local function exists(path: string): boolean
	local ok, found = pcall(tern.fs.exists, path)
	return ok and found == true
end

-- The main git repo of each working directory, looked up once through `tern.fs` (which runs on the UI thread).
-- `read` caps the size, so that it never blocks on a FIFO and fails on a directory.
local repos = repoRoot.resolver({
	exists = exists,
	read = function(path: string): string?
		local ok, text = pcall(tern.fs.read, path, 65536)
		if ok then
			return text
		end
		return nil
	end,
})

local function home(): string?
	return tern.getenv("HOME")
end

-- The view-model input: every agent of every session, with its pane title and the name of its tab.
local function snapshot(cx: WindowCx): viewModel.Input
	local now = tern.now()
	local panes: { [number]: PaneInfo } = {}
	for _, info in cx.session:panes() do
		panes[info.pane] = info
	end
	local tabNames: { [number]: string? } = {}
	for _, tab in cx.session:tabs() do
		tabNames[tab.id] = str(tab.name)
	end
	local agents: { viewModel.Agent } = {}
	local reported = sessionReader.reported()
	for _, block in cx.agents:list() do
		local info = panes[block.pane]
		local tab: number? = nil
		if info and type(info.tab) == "number" then
			tab = info.tab
		end
		local cwd = str(block.cwd)
		table.insert(agents, {
			pane = block.pane,
			state = block.state,
			title = info and str(info.title),
			tab = tab,
			tabName = tab and tabNames[tab],
			cwd = cwd,
			model = str(block.model),
			effort = effortReader.level(block.pane),
			lastMessage = str(block.last_message),
			repo = repos.of(cwd),
			sessionFile = reported[block.pane],
		})
	end
	return store.fill({
		agents = agents,
		now = now,
		home = home(),
		subagents = subagentReader.subagents(),
		viewing = subagentReader.viewing(),
		sessions = sessionReader.sessions(),
		focused = focusedPane(cx),
		plugin = tern.plugin.id,
	})
end

local function hidden(): boolean
	return tern.kv.get(HIDDEN_KEY) == true
end

local function sharedWidth(): number
	return placement.sharedWidth(tern.kv.get(WIDTH_KEY))
end

-- This plugin's canvases in this window: the ones `cx.canvas:list()` names (also after a plugin reload), and the
-- ones this VM opened a moment ago that the list does not show yet. A copy that leaves the list is forgotten; its
-- `pane_closed` tells whether the user closed it (see `paneClosed`).
local function ours(cx: WindowCx): { number }
	local found: { [number]: boolean } = {}
	for _, info in cx.canvas:list() do
		if info.owner == tern.plugin.id and not closing[info.pane] then
			found[info.pane] = true
		end
	end
	local now = tern.now()
	for pane, copy in copies do
		local fresh = copy.openedAt ~= nil and now - copy.openedAt < OPEN_GRACE
		if not found[pane] and fresh and cx.session:tab_of(pane) then
			found[pane] = true
		end
	end
	for pane, copy in copies do
		if not found[pane] then
			copies[pane] = nil
			if copy.tab then
				vanished[pane] = copy.tab
			end
		end
	end
	local out: { number } = {}
	for pane in found do
		table.insert(out, pane)
		copies[pane] = copies[pane] or { now = 0 }
	end
	return out
end

-- The width of the sidebar `pane` in `tab` (its share of the tab's width) and the shape of the tree around it.
local function measure(cx: WindowCx, tab: number, pane: number): (number?, string?)
	local layout = cx.session:layout(tab)
	if not layout then
		return nil, nil
	end
	local width = placement.width(layout.root, pane)
	return width, if width then placement.shape(layout.root, pane) else nil
end

-- Takes the width of a copy the user dragged, in the tab in front or the one just left, as the shared width. A
-- width that changed with the tree's shape (a pane closed, another divider moved, the tabs arranged) is no drag:
-- the copy goes back to the shared width.
local function noteDraggedWidth(cx: WindowCx, tabs: { number })
	for _, tab in tabs do
		for pane, copy in copies do
			if copy.tab == tab then
				local width, shape = measure(cx, tab, pane)
				if width and copy.width and math.abs(width - copy.width) > placement.TOLERANCE then
					local dragged = shape == copy.shape
					copy.width, copy.shape = width, shape
					if dragged then
						tern.kv.set(WIDTH_KEY, width)
						copy.goal = width
						return
					end
					copy.goal = nil
				elseif shape then
					copy.shape = shape
				end
			end
		end
	end
end

-- Whether `pane` is a canvas of this plugin: Tern says so, or this VM opened it a moment ago.
local function owned(cx: WindowCx, pane: number): boolean
	local info = cx.canvas:get(pane)
	if info then
		return info.owner == tern.plugin.id
	end
	local copy = copies[pane]
	return copy ~= nil and copy.openedAt ~= nil and tern.now() - copy.openedAt < OPEN_GRACE
end

-- Drags the divider of copy `pane` until it takes `want` of its tab's width, in at most four steps.
local function resize(cx: WindowCx, pane: number, tab: number, want: number)
	local copy = copies[pane]
	copy.goal = want
	local width = measure(cx, tab, pane)
	for _ = 1, 4 do
		if not width or math.abs(want - width) <= placement.TOLERANCE then
			break
		end
		local cells = math.round((want - width) * tabCells)
		if cells == 0 then
			cells = if want > width then 1 else -1
		end
		-- The sidebar sits on the right edge: it grows by moving its left divider.
		if not cx.layout:resize(pane, "left", cells) then
			break
		end
		local after = measure(cx, tab, pane)
		if after and after ~= width then
			tabCells = math.abs(cells / (after - width))
		end
		width = after
	end
	copy.width, copy.shape = measure(cx, tab, pane)
end

-- The copies the windows closed themselves in the last few seconds, by pane, as `tern.kv` keeps them.
local function closedByWindows(): { [string]: number }
	local out: { [string]: number } = {}
	local stored = tern.kv.get(CLOSING_KEY)
	if type(stored) ~= "table" then
		return out
	end
	local time = os.time()
	for key, at in stored do
		if type(key) == "string" and type(at) == "number" and time - at <= CLOSING_FOR then
			out[key] = at
		end
	end
	return out
end

local function paneKey(pane: number): string
	return string.format("%.0f", pane)
end

-- Closes copy `pane`, only when Tern says it is this plugin's canvas, and tells every window that the plugin
-- closed it.
local function close(cx: WindowCx, pane: number)
	copies[pane] = nil
	local info = cx.canvas:get(pane)
	if not info or info.owner ~= tern.plugin.id then
		return
	end
	closing[pane] = true
	local closed = closedByWindows()
	closed[paneKey(pane)] = os.time()
	tern.kv.set(CLOSING_KEY, closed)
	cx.layout:close(pane)
end

local function sameSegments(a: { viewModel.Segment }, b: { viewModel.Segment }): boolean
	if #a ~= #b then
		return false
	end
	for i, segment in a do
		local other = b[i]
		if segment.text ~= other.text or segment.icon ~= other.icon or segment.tone ~= other.tone
			or segment.command ~= other.command
		then
			return false
		end
	end
	return true
end

local function sameTitles(a: { [number]: string }, b: { [number]: string }): boolean
	for tab, title in a do
		if b[tab] ~= title then
			return false
		end
	end
	for tab in b do
		if a[tab] == nil then
			return false
		end
	end
	return true
end

-- Builds the view model from Tern's agent list, and redraws the window chrome when the status line counts or the
-- tab titles changed. Also gives the input, for the time the view was built at.
local function build(cx: WindowCx): (viewModel.Output, viewModel.Input)
	local input = snapshot(cx)
	local out = viewModel.build(input)
	latest = input
	local redraw = false
	if not sameSegments(out.status, segments) then
		segments = out.status
		redraw = true
	end
	local named = viewModel.tabTitles(input.agents)
	if not sameTitles(named, titles) then
		titles = named
		redraw = true
	end
	if redraw then
		tern.chrome.refresh()
	end
	return out, input
end

--- Puts one sidebar copy in every tab of the window (none while hidden), closes extra copies and copies alone
--- in their tab, and brings every copy to the shared width. `front` is the tab in front, when the caller knows.
function sidebar.sync(cx: WindowCx, front: number?)
	local panes = ours(cx)
	local tabs: { placement.Tab } = {}
	for _, info in cx.session:tabs() do
		local layout = cx.session:layout(info.id)
		table.insert(tabs, { id = info.id, root = layout and layout.root, floats = layout and #layout.floats })
	end
	for _, pane in panes do
		local copy = copies[pane]
		copy.tab = cx.session:tab_of(pane)
		if copy.width == nil and copy.tab then
			copy.width, copy.shape = measure(cx, copy.tab, pane)
		end
	end
	if not front then
		local focused = cx.session:focused()
		front = focused and cx.session:tab_of(focused)
	end
	local seen: { number } = {}
	if lastTab then
		table.insert(seen, lastTab)
	end
	if front and front ~= lastTab then
		table.insert(seen, front)
	end
	lastTab = front
	noteDraggedWidth(cx, seen)
	local width = sharedWidth()
	local plan = placement.plan({ tabs = tabs, sidebars = panes, hidden = hidden(), width = width })
	for _, pane in plan.close do
		close(cx, pane)
	end
	local view: viewModel.Node? = nil
	local now = 0
	for _, place in plan.open do
		if not view then
			local out, input = build(cx)
			view, now = out.view, input.now
		end
		local pane, err = cx.canvas:open({
			title = TITLE,
			about = ABOUT,
			view = view,
			focus = false,
			target = place.target,
			dir = "right",
			ratio = place.ratio,
		})
		if pane then
			local measured, shape = measure(cx, place.tab, pane)
			copies[pane] = {
				tab = place.tab,
				view = view,
				now = now,
				width = measured,
				shape = shape,
				goal = width,
				openedAt = tern.now(),
			}
		elseif not openFailed then
			openFailed = true
			cx:toast("error", "Could not open the Agents sidebar", err)
		end
	end
	for _, change in plan.resize do
		-- A copy that cannot reach the width (its pane beside is at the minimum size) is tried once per width.
		if copies[change.pane].goal ~= width and owned(cx, change.pane) then
			resize(cx, change.pane, change.tab, width)
		end
	end
end

-- `tern.now()` when the redraw that folds the next idle agent into "Older" runs; nil when none waits.
local olderAt: number? = nil

-- An idle agent folds into "Older" a day after its last turn, and no event says so: redraw then.
local function redrawForOlder(input: viewModel.Input)
	local due = viewModel.olderDue(input)
	if not due then
		return
	end
	local ms = due * 1000 + 1000
	local at = input.now + ms
	if olderAt and olderAt <= at then
		return
	end
	olderAt = at
	tern.timer(ms, function(later: WindowCx?)
		if olderAt == at then
			olderAt = nil
		end
		if later then
			sidebar.refresh(later)
		end
	end)
end

--- Rebuilds the view model: updates the status line, and draws the agent list in every copy whose content
--- changed, with a keyed patch of the changed rows.
function sidebar.refresh(cx: WindowCx): viewModel.Output
	local panes = ours(cx)
	local out, input = build(cx)
	if hidden() then
		if #panes > 0 then
			-- The user just closed a copy: close the others.
			sidebar.sync(cx)
		end
		return out
	end
	if #panes > 0 then
		redrawForOlder(input)
	end
	for _, pane in panes do
		local copy = copies[pane]
		local change = patch.diff(copy.view, copy.now, out.view, input.now)
		if change then
			local ok, err = pcall(function()
				cx.canvas:set(pane, change :: any)
			end)
			if ok then
				copy.view, copy.now = out.view, input.now
			elseif cx.canvas:get(pane) == nil then
				-- The canvas closed without a `pane_closed` this VM heard (a plugin reload in between).
				copies[pane] = nil
			elseif not setFailed then
				-- The canvas is there and refused the change (a canvas limit, for example): say so once.
				setFailed = true
				cx:toast("error", "Could not update the Agents sidebar", tostring(err))
			end
		end
	end
	return out
end

--- Whether the user hid the sidebar, in any window.
function sidebar.hidden(): boolean
	return hidden()
end

--- Whether `pane` ran an agent at the last refresh.
function sidebar.runsAgent(pane: number): boolean
	if not latest then
		return false
	end
	for _, agent in latest.agents do
		if agent.pane == pane then
			return true
		end
	end
	return false
end

--- Shows the sidebar in every tab, or hides it everywhere (in every window and after a restart) when it shows.
function sidebar.toggle(cx: WindowCx)
	tern.kv.set(HIDDEN_KEY, not hidden())
	sidebar.sync(cx)
	if not hidden() then
		sidebar.refresh(cx)
	end
end

--- Reacts to a closed pane. A copy that this window heard close, that no window closed itself and whose tab stays
--- is the user's ⌘W on it: that hides the sidebar everywhere. A copy that went away with its tab (or session)
--- hides nothing. Any other close may leave a tab that holds only the sidebar.
function sidebar.paneClosed(pane: number)
	if closing[pane] then
		closing[pane] = nil
		vanished[pane] = nil
		return
	end
	local copy = copies[pane]
	local tab = (copy and copy.tab) or vanished[pane]
	vanished[pane] = nil
	local byWindow = closedByWindows()[paneKey(pane)] ~= nil
	-- Tern updates the tabs after the close: look a moment later.
	tern.timer(100, function(later: WindowCx?)
		if not later then
			return
		end
		if tab and not byWindow and later.session:layout(tab) then
			tern.kv.set(HIDDEN_KEY, true)
		end
		sidebar.sync(later)
	end)
end

--- Shows the agent in `pane`: switches to its session, or deals it out of the deck when parked, then focuses it.
function sidebar.focusAgent(cx: WindowCx, pane: number)
	local info = cx.session:pane(pane)
	if not info then
		cx:toast("info", "That agent is gone")
		sidebar.refresh(cx)
		return
	end
	if info.parked == true then
		local ok, why = cx.layout:unpark(pane)
		if not ok then
			cx:toast("error", "Could not unpark the agent", why)
			return
		end
	else
		local tab = cx.session:tab_of(pane)
		for _, session in cx.session:sessions() do
			if tab and table.find(session.tabs, tab) then
				if not session.current then
					cx.sessions:switch(session.id)
				end
				break
			end
		end
	end
	cx.layout:focus(pane)
end

--- Opens a new tab in `folder` that runs what Tern's own New tab runs, by the user's "New tabs and splits open"
--- preference: a shell, or an agent through the user's agent command (see `new_tab.luau`).
function sidebar.newTab(cx: WindowCx, folder: string)
	local launch = newTab.launch(folder, cx.settings:get("new_blocks"), cx.settings:get("agent_command"))
	local ok, err = pcall(function()
		return cx.layout:new_tab(launch)
	end)
	if not ok then
		cx:toast("error", "Could not open a new tab", tostring(err))
	end
end

-- `text` as one shell word.
local function shellQuote(text: string): string
	return "'" .. string.gsub(text, "'", "'\\''") .. "'"
end

--- Opens a new tab in the working directory of the omp session in `file` that runs `omp --resume <file>`.
function sidebar.resume(cx: WindowCx, file: string)
	local session = sessionReader.find(file)
	local cwd = (session and session.cwd) or home()
	local ok, err = pcall(function()
		return cx.layout:new_tab({ cwd = cwd, command = "omp --resume " .. shellQuote(file) })
	end)
	if not ok then
		cx:toast("error", "Could not resume the session", tostring(err))
	end
end

--- Reads the omp sessions again (at most once a minute unless `force`) and the session file each pane's omp
--- reported, and redraws when they changed.
function sidebar.scanSessions(force: boolean)
	if hidden() then
		return
	end
	sessionReader.scan(home(), force, { exists = exists, repoOf = repos.of }, function(later: WindowCx)
		sidebar.refresh(later)
	end)
	sidebar.readReported()
end

--- Reads which session file each pane's omp reported, and redraws when that changed. omp reports a new one when it
--- starts, on a new session, a resume and a working-directory switch.
function sidebar.readReported()
	if hidden() then
		return
	end
	sessionReader.readReported(function(later: WindowCx)
		sidebar.refresh(later)
	end)
end

--- Copies the ID or the path of the omp session in `file` (`act`, from a row's right-click menu) and says so in a
--- toast. The start of the file is read off the UI thread first: the ID comes from its header, and a file that is
--- not there copies nothing.
function sidebar.copySession(cx: WindowCx, act: sessionCopy.Act, file: string)
	local ok, err = pcall(function()
		tern.process.run(
			{ "/usr/bin/head", "-c", "4096", "--", file },
			{ timeout_ms = 5000 },
			function(result: ProcessResult, later: WindowCx?)
				if not later then
					return
				end
				local head = if result.status == 0 and not result.timed_out then result.stdout else nil
				local out = sessionCopy.resolve(act, file, head)
				if out.text then
					later:copy(out.text)
				end
				later:toast(out.level, out.toast, out.sub)
			end
		)
	end)
	if not ok then
		cx:toast("error", "Could not read the session file", tostring(err))
	end
end

--- A click on the row of the agent in `pane`: when omp shows one of its subagents, runs omp's own "Back to the main
--- session" action from the pane's dock first (a read scoped to the dock: a full read of the chat can pass the
--- 50 ms budget), then focuses the agent. A pane with no TSP surface (an agent other than omp) only gets the focus.
function sidebar.agentClick(cx: WindowCx, pane: number)
	pcall(function()
		local exit = backToMain.find(cx.session:surface(pane, { root = "dock", nodes = 800 }))
		if exit then
			cx.session:event(pane, { ev = "action", sf = exit.surface, id = exit.id, act = exit.act })
		end
	end)
	sidebar.focusAgent(cx, pane)
end

--- "Rename" on the row of the agent in `pane`: asks for the new title in Tern's text field, prefilled with the
--- current one, and submits omp's `/rename <title>` in the agent's composer with one TSP `send` event on its field
--- (`viewing.send`), as the user's Enter does; omp runs it as a command, also during a turn. `cx.agents:ask` sends
--- the same event, but keeps the text as a prompt that never starts a turn, so Tern showed the agent as working and
--- refused the next `ask` ("agent already has a pending prompt"). omp sets the title and retitles its pane, so the
--- row and the tab title follow on the `title` event. A blank title, the same title or a dismissed field sends
--- nothing; while omp shows a subagent (whose chat box the composer is then) nothing is sent either.
function sidebar.rename(cx: WindowCx, pane: number)
	local info = cx.session:pane(pane)
	if not info then
		cx:toast("info", "That agent is gone")
		return
	end
	local current = rename.current(info.title)
	cx:prompt({ value = current, placeholder = "Session title", icon = "pencil", action = "rename" })
		:next(function(text: string?, _err: string?, fresh: WindowCx?)
			local now = fresh or cx
			local command = rename.command(text, current)
			if not command then
				return
			end
			local ok, err = pcall(function()
				local send = viewing.send(now.session:surface(pane, { root = "dock", nodes = 800 }), command)
				if send then
					now.session:event(pane, { ev = "send", sf = send.surface, id = send.id, text = send.text })
				else
					now:toast("info", "Could not rename the session", "Go back to omp's main session, then try again.")
				end
			end)
			if not ok then
				now:toast("error", "Could not rename the session", tostring(err))
			end
		end)
end

--- A click on the row of subagent `id` of the agent in `pane`: focuses the agent, and asks its omp to show the
--- subagent (`viewing.show`, from a read scoped to the pane's dock), also straight from another subagent omp shows.
--- A subagent that has finished since, or the one omp shows already, only focuses the agent.
function sidebar.subagentClick(cx: WindowCx, pane: number, id: string)
	sidebar.focusAgent(cx, pane)
	local sub = subagents.find(subagentReader.subagents()[pane], id)
	if not sub then
		return
	end
	local ok, err = pcall(function()
		local show = viewing.show(cx.session:surface(pane, { root = "dock", nodes = 800 }), sub)
		if show then
			cx.session:event(pane, { ev = "action", sf = show.surface, id = show.id, act = show.act })
		end
	end)
	if not ok then
		cx:toast("error", "Could not show the subagent", tostring(err))
	end
end

--- Opens a new tab in the repo of the focused agent (or of the focused pane's folder when it runs no agent); the
--- sidebar's own pane counts as the pane focused before it. With no folder known, Tern's own New tab runs.
function sidebar.newTabHere(cx: WindowCx)
	local focused = focusedPane(cx)
	local cwd: string? = nil
	for _, block in cx.agents:list() do
		if block.pane == focused then
			cwd = str(block.cwd)
			break
		end
	end
	if not cwd and focused then
		local info = cx.session:pane(focused)
		cwd = info and str(info.cwd)
	end
	if not cwd or cwd == "" then
		cx:command("new_tab")
		return
	end
	sidebar.newTab(cx, repos.of(cwd) or cwd)
end

--- Moves the agent panes of each session into one tab per sidebar section (a repo, or the working directory of
--- agents outside a repo), named after its folder. Parked agents stay parked, and other panes stay where they are.
--- Runs only from the palette command: the plugin never arranges tabs by itself.
function sidebar.arrangeByRepo(cx: WindowCx)
	local sessionOfTab: { [number]: number } = {}
	local sessions: { number } = {}
	for _, session in cx.session:sessions() do
		table.insert(sessions, session.id)
		for _, tab in session.tabs do
			sessionOfTab[tab] = session.id
		end
	end
	local bySession: { [number]: { viewModel.Agent } } = {}
	local input = snapshot(cx)
	for _, agent in input.agents do
		local session = agent.tab and sessionOfTab[agent.tab]
		if session then
			local list = bySession[session] or {}
			bySession[session] = list
			table.insert(list, agent)
		end
	end
	local moved, tabs = 0, 0
	for _, session in sessions do
		local agents = bySession[session]
		if agents then
			local groups: { TabGroup } = {}
			for _, group in viewModel.groups(agents, input.home) do
				local blocks: { number | string } = {}
				for _, agent in group.agents do
					table.insert(blocks, agent.pane)
				end
				table.insert(groups, { name = group.name, blocks = blocks })
			end
			local result, err = cx.layout:arrange({ session = session, tabs = groups, rest = "keep" })
			if not result then
				cx:toast("error", "Could not arrange the tabs", err)
				return
			end
			moved += #agents
			tabs += #groups
		end
	end
	if moved == 0 then
		cx:toast("info", "No agent panes to arrange")
		return
	end
	cx:toast("success", string.format("Arranged %d agents into %d tabs by repo", moved, tabs))
end

--- The status line segments of the last refresh: the working and waiting counts. Pure, for the status formatter.
function sidebar.status(): { viewModel.Segment }
	return segments
end

--- The tab titles of the last refresh: the main agent's name by tab id. Pure, for the tab title formatter.
function sidebar.tabTitles(): { [number]: string }
	return titles
end

--- Focuses the agent that has waited longest, in any session.
function sidebar.nextWaiting(cx: WindowCx)
	local pane = sidebar.refresh(cx).waiting[1]
	if not pane then
		cx:toast("info", "No agent waits for you")
		return
	end
	sidebar.focusAgent(cx, pane)
end

-- Whether the user sees `pane` now: it sits, not parked, in the tab of the focused pane, that tab belongs to the
-- session the window shows, and no other block of the tab is zoomed. When any of this is unknown, the answer is no,
-- so that a doubt costs a toast rather than a missed agent. Tern does not say whether the window itself is on
-- screen (behind another app, minimized), so that case counts as seen.
local function onScreen(cx: WindowCx, pane: number): boolean
	local info = cx.session:pane(pane)
	if not info or info.parked == true then
		return false
	end
	local focused = cx.session:focused()
	local tab = cx.session:tab_of(pane)
	if not focused or not tab or cx.session:tab_of(focused) ~= tab then
		return false
	end
	local shown = false
	for _, session in cx.session:sessions() do
		if session.current then
			shown = table.find(session.tabs, tab) ~= nil
			break
		end
	end
	if not shown then
		return false
	end
	local layout = cx.session:layout(tab)
	return layout ~= nil and (not layout.zoomed or layout.focus == pane)
end

--- Toasts that the agent in `pane` began to wait or ended its turn, unless its pane is on screen. Names the agent
--- from the last refresh, so call it after `refresh`.
function sidebar.notify(cx: WindowCx, pane: number, what: "waiting" | "done" | "failed")
	if not latest or onScreen(cx, pane) then
		return
	end
	local notice = viewModel.notice(latest, pane, what)
	if notice then
		cx:toast(notice.level, notice.text, notice.sub)
	end
end

return sidebar
