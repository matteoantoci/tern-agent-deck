--!strict
-- The window half: the plugin's only entry. It wires Tern events and commands to the sidebar manager.

local effortReader = require("./lib/effort_reader")
local sessionCopy = require("./lib/session_copy")
local sidebar = require("./lib/sidebar")
local store = require("./lib/store")
local subagentReader = require("./lib/subagent_reader")
local viewModel = require("./lib/view_model")

-- The 1-second tick that reads the subagents of one polled agent; nil while none is polled (no agent works or has
-- running subagents) or the sidebar is hidden
-- (the status line does not show subagents). Showing the sidebar starts it again.
local ticking: TimerHandle? = nil
-- Whether a tick has refreshed once: the first tick after the plugin loads fills the status line.
local primed = false

local function tick(cx: WindowCx?)
	ticking = nil
	if not cx then
		return
	end
	if sidebar.hidden() then
		if not primed then
			primed = true
			sidebar.refresh(cx)
		end
		return
	end
	local changed, polling = subagentReader.step(cx, tern.now())
	if changed or not primed then
		primed = true
		sidebar.refresh(cx)
	end
	if polling then
		ticking = tern.timer(1000, tick)
	end
end

local function startTicking()
	if not ticking then
		ticking = tern.timer(1000, tick)
	end
end

-- Agents may already work when the plugin loads; the first tick stops the timer when none does.
startTicking()

-- The omp sessions for the Recent view: read again every minute while the sidebar shows (the reader skips a scan
-- that comes sooner), and at once when an agent ends a turn or exits.
local function scanTick(_cx: WindowCx?)
	sidebar.scanSessions(false)
	tern.timer(60 * 1000, scanTick)
end

-- Shows or hides the sidebar everywhere: the palette command, its key, and the head's ⋯ menu and hide button.
local function toggleSidebar(cx: WindowCx)
	sidebar.toggle(cx)
	startTicking()
	sidebar.scanSessions(false)
end

tern.command({
	id = "toggle-sidebar",
	title = "Toggle Agents sidebar",
	icon = "sidebar",
	keys = { "cmd+alt+a" },
	run = toggleSidebar,
})

tern.command({
	id = "new-tab-here",
	title = "New tab in the focused agent's folder",
	icon = "plus",
	run = function(cx: WindowCx)
		sidebar.newTabHere(cx)
	end,
})

-- Only this command (and the same item of the sidebar's ⋯ menu) arranges tabs; the plugin never moves panes by
-- itself.
tern.command({
	id = "arrange-by-repo",
	title = "Arrange tabs by project",
	icon = "folder",
	run = function(cx: WindowCx)
		sidebar.arrangeByRepo(cx)
	end,
})

-- Pins the focused agent, or unpins it when it is pinned.
tern.command({
	id = "pin-agent",
	title = "Pin this agent",
	icon = "pin",
	run = function(cx: WindowCx)
		local pane = cx.session:focused()
		if pane and store.pinned(cx, pane) then
			store.unpin(cx, pane)
			cx:toast("info", "Unpinned the agent")
		elseif pane and store.pin(cx, pane) then
			cx:toast("success", "Pinned the agent")
		else
			cx:toast("info", "Focus an agent first", "Pin this agent pins the agent in the focused pane.")
			return
		end
		sidebar.refresh(cx)
	end,
})

-- One copy in every tab. `window_start` runs when the window opens; a plugin reload runs no `window_start`, so
-- the entry also syncs once it has loaded. The copies that exist already are found, not reopened.
local function start(cx: WindowCx)
	sidebar.sync(cx)
	-- The agents that run already: one effort read each; later reads come with their state changes.
	for _, block in cx.agents:list() do
		effortReader.read(cx, block.pane)
	end
	sidebar.refresh(cx)
end

tern.timer(0, scanTick)

tern.on("window_start", start)

tern.timer(0, function(cx: WindowCx?)
	if cx then
		start(cx)
	end
end)

-- A tab switch, also to a tab restored from the daemon (which fires no `tab_created`), and pane titles.
tern.on("focus", function(ev: FocusEvent, cx: WindowCx)
	sidebar.sync(cx, ev.tab)
	sidebar.refresh(cx)
end)

-- A pane renamed itself (omp titles its pane after the chat): its row shows the new title. omp also retitles its
-- pane on a new session or a resume, which reports another session file. Shells and other programs retitle their
-- panes often; those show no row.
tern.on("title", function(ev: TitleEvent, cx: WindowCx)
	if sidebar.runsAgent(ev.pane) then
		sidebar.readReported()
		sidebar.refresh(cx)
	end
end)

tern.on("tab_created", function(_ev: TabEvent, cx: WindowCx)
	sidebar.sync(cx)
	-- A tab can arrive before Tern knows its layout: look again a moment later.
	tern.timer(150, function(later: WindowCx?)
		if later then
			sidebar.sync(later)
		end
	end)
end)

tern.on("agent_state", function(ev: AgentStateEvent, cx: WindowCx)
	store.noteTurn(ev)
	-- A turn starts, asks the user, or ends: the agent is active now. A change from nothing (a new agent, a
	-- restart) or to exited is not activity.
	if ev.new == "working" or ev.new == "waiting_input" or ev.old == "working" then
		store.noteActivity(ev.pane)
	end
	-- The user may have changed the thinking effort at the prompt: one scoped read of the composer's glyph.
	effortReader.read(cx, ev.pane)
	sidebar.refresh(cx)
	-- An agent that begins to wait gets a toast; one that the plugin sees for the first time (a new agent, a
	-- restart) does not, so that a restart does not toast every waiting agent.
	if ev.new == "waiting_input" and ev.old ~= nil then
		sidebar.notify(cx, ev.pane, "waiting")
	end
	if ev.new == "working" then
		startTicking()
	end
	if ev.new == "exited" then
		sidebar.scanSessions(true)
	elseif ev.old == nil then
		-- A new agent: an omp reports its session file as it starts.
		sidebar.readReported()
	end
end)

tern.on("agent_finished", function(ev: AgentFinishedEvent, cx: WindowCx)
	if ev.result == "done" or ev.result == "failed" then
		store.noteActivity(ev.pane)
	end
	effortReader.read(cx, ev.pane)
	-- The turn ended, but omp runs `task` subagents in the background: the reader keeps polling the pane while its
	-- last read found a running `task` call, and drops its rows once a read finds none.
	startTicking()
	sidebar.refresh(cx)
	sidebar.scanSessions(true)
	if ev.result == "done" or ev.result == "failed" then
		sidebar.notify(cx, ev.pane, ev.result)
	end
end)

-- The working and waiting counts, from the last refresh: a status formatter may not call Tern.
tern.chrome.status(function(_pane: StatusPaneInfo): { StatusSegment }?
	local shown = sidebar.status()
	if #shown == 0 then
		return nil
	end
	return shown
end)

-- Each tab takes the name of its main agent (the first in start order), from the last refresh; a tab the user named
-- keeps its name, and a tab without an agent keeps Tern's own title. A formatter may not call Tern.
tern.chrome.tab_title(function(tab: TabInfo): string?
	return viewModel.tabTitle(tab, sidebar.tabTitles())
end)

-- The status segment's click runs this command too.
tern.command({
	id = "next-waiting",
	title = "Next waiting agent",
	icon = "bell",
	run = function(cx: WindowCx)
		sidebar.nextWaiting(cx)
	end,
})

tern.on("pane_closed", function(ev: PaneEvent, cx: WindowCx)
	effortReader.forget(ev.pane)
	sidebar.paneClosed(ev.pane)
end)

-- A row click sends `focus=<pane>`; the row of a pinned agent that is gone sends `gone=<pin index>`; a subagent row
-- sends `subagent=<pane> <node id>`.
tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean
	if ev.act == "gone" then
		cx:toast("info", "That agent is gone")
		return true
	end
	if ev.act == "subagent" and type(ev.value) == "string" then
		local pane, id = string.match(ev.value, "^(%d+) (.+)$")
		if pane and id then
			sidebar.subagentClick(cx, tonumber(pane) :: number, id)
			return true
		end
		return false
	end
	local pane = tonumber(ev.value)
	if ev.act ~= "focus" or not pane then
		return false
	end
	sidebar.agentClick(cx, pane)
	return true
end)

-- The `+` button on a folder row sends `new=<folder>`; the empty state's "New tab here" button and the ⋯ menu's
-- "New tab here" send `new-here`.
tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean
	if ev.act == "new-here" then
		sidebar.newTabHere(cx)
		return true
	end
	if ev.act ~= "new" or type(ev.value) ~= "string" or ev.value == "" then
		return false
	end
	sidebar.newTab(cx, ev.value)
	return true
end)

-- The head: the ⋯ menu's "Arrange tabs by project" sends `arrange-by-repo`, its "Toggle sidebar" and the hide button
-- `toggle-sidebar`. The view strip sends `view=live` or `view=recent`.
tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean
	if ev.act == "arrange-by-repo" then
		sidebar.arrangeByRepo(cx)
	elseif ev.act == "toggle-sidebar" then
		toggleSidebar(cx)
	elseif ev.act == "view" and (ev.value == "live" or ev.value == "recent") then
		store.setView(ev.value :: viewModel.View)
		sidebar.refresh(cx)
		if ev.value == "recent" then
			sidebar.scanSessions(false)
		end
	else
		return false
	end
	return true
end)

-- A Live folder row sends `fold=<group key>`, the Older row of a group `older=<group key>`, a Recent folder row
-- `recent=<group key>`; the Recent view's last row `recent-more`.
local KEY_SETS: { [string]: store.KeySet } = { fold = "folded", older = "older", recent = "recent" }

tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean
	local set: store.KeySet? = KEY_SETS[ev.act]
	if set and type(ev.value) == "string" and ev.value ~= "" then
		store.toggle(set, ev.value)
	elseif ev.act == "recent-more" then
		store.toggleRecentAll()
	else
		return false
	end
	sidebar.refresh(cx)
	return true
end)

-- A closed session's row sends `resume=<session file>`.
tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean
	if ev.act ~= "resume" or type(ev.value) ~= "string" or ev.value == "" then
		return false
	end
	sidebar.resume(cx, ev.value)
	return true
end)

-- A session row's right-click menu (a live agent's, a subagent's, a closed session's) sends `copy-id=<session file>`
-- or `copy-path=<session file>`.
tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean
	if (ev.act ~= "copy-id" and ev.act ~= "copy-path") or type(ev.value) ~= "string" or ev.value == "" then
		return false
	end
	sidebar.copySession(cx, ev.act :: sessionCopy.Act, ev.value)
	return true
end)

-- A row's right-click menu sends `pin=<pane>`, `unpin=<pane>`, `rename=<pane>` or `interrupt=<pane>`, and that of
-- a pinned agent that is gone `forget=<pin index>`.
tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean
	local pane = tonumber(ev.value)
	if not pane then
		return false
	end
	if ev.act == "forget" then
		store.forget(pane)
		sidebar.refresh(cx)
		return true
	end
	if ev.act == "rename" then
		sidebar.rename(cx, pane)
		return true
	end
	if ev.act == "interrupt" then
		-- Ctrl-C ends the turn and keeps the agent's block.
		local ok, err = pcall(function()
			cx.agents:interrupt(pane)
		end)
		if not ok then
			cx:toast("error", "Could not interrupt the agent", tostring(err))
		end
		return true
	end
	if ev.act == "pin" then
		if not store.pin(cx, pane) then
			cx:toast("info", "That agent is gone")
		end
	elseif ev.act == "unpin" then
		store.unpin(cx, pane)
	else
		return false
	end
	sidebar.refresh(cx)
	return true
end)
