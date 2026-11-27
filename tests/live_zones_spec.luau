--!strict
-- The Live view: the zones Needs you, Working and Idle, the project groups inside them, and the one-line agent rows.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local ICON = "\u{F0E7}"
local HOME = "/Users/me"
local DECK = "/Users/me/Personal/tern-agent-deck"
local PI = "/Users/me/Personal/oh-my-pi"
local NOW = 1_800_000_000
local DAY = 24 * 60 * 60

-- An agent in the repo `DECK`; one given a `cwd` works outside any repo unless it is given a `repo` too.
local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = DECK, repo = DECK, title = ICON .. " Fix login" }
	if fields.cwd ~= nil then
		a.repo = nil
	end
	for k, v in fields do
		a[k] = v
	end
	return a
end

local function build(agents: { any }, extra: { [string]: any }?): any
	local input: { [string]: any } = { agents = agents, now = 0, time = NOW, home = HOME }
	for k, v in (extra or {}) :: { [string]: any } do
		input[k] = v
	end
	return viewModel.build(input :: any)
end

local function view(agents: { any }, extra: { [string]: any }?): any
	return build(agents, extra).view
end

local DECK_LABEL = "tern-agent-deck [:plus](New tab in this repo)"
local PI_LABEL = "oh-my-pi [:plus](New tab in this repo)"

t.test("Live shows the zones Needs you, Working and Idle in that order, each with its square and its status", function()
	local out = view({
		agent({ pane = 1, state = "idle", title = ICON .. " a" }),
		agent({ pane = 2, state = "working", title = ICON .. " b" }),
		agent({ pane = 3, state = "waiting_input", title = ICON .. " c" }),
		agent({ pane = 4, state = "working", title = ICON .. " d" }),
	})
	t.eq(visible.zones(out), { "■ Needs you 1", "■ Working 2 busy", "■ Idle 1" })
	t.eq(visible.states(out)[1], "waiting: ■ Needs you 1")
	t.eq(visible.state(out, "Working 2 busy"), "working")
	t.eq(visible.state(out, "Idle 1"), "idle")
end)

t.test("a zone with no agents hides", function()
	t.eq(visible.zones(view({ agent({ state = "working", title = ICON .. " a" }) })), { "■ Working 1 busy" })
	t.eq(visible.zones(view({ agent({ state = "idle", title = ICON .. " a" }) })), { "■ Idle 1" })
end)

t.test("with no agent, Live shows one calm line", function()
	local out = view({})
	t.eq(visible.zones(out), {})
	t.eq(visible.lines(out), { "No agent runs. Open Recent to resume a session" })
end)

t.test("an exited agent that is not pinned leaves the list", function()
	t.eq(visible.lines(view({ agent({ state = "exited" }) })), { "No agent runs. Open Recent to resume a session" })
end)

t.test("inside a zone, agents group under their project's label, projects by name, agents with no folder last", function()
	local loose = agent({ pane = 4, title = ICON .. " loose" })
	loose.cwd, loose.repo = nil, nil
	t.eq(visible.zone(view({
		agent({ pane = 1, title = ICON .. " deck one" }),
		agent({ pane = 2, title = ICON .. " pi", cwd = PI, repo = PI }),
		agent({ pane = 3, title = ICON .. " scratch", cwd = "/tmp" }),
		loose,
	}), "Idle"), {
		PI_LABEL,
		ICON .. "(Idle) pi",
		DECK_LABEL,
		ICON .. "(Idle) deck one",
		"tmp [:plus](New tab in this folder)",
		ICON .. "(Idle) scratch",
		"No folder",
		ICON .. "(Idle) loose",
	})
end)

t.test("a worktree groups under its main repo", function()
	t.eq(visible.zone(view({
		agent({ pane = 1, title = ICON .. " main" }),
		agent({ pane = 2, title = ICON .. " tree", cwd = "/Users/me/checkouts/sr-t02", repo = DECK }),
	}), "Idle"), { DECK_LABEL, ICON .. "(Idle) main", ICON .. "(Idle) tree" })
end)

t.test("every zone orders its projects by name, whatever the focus", function()
	local agents = {
		agent({ pane = 1, state = "working", title = ICON .. " deck busy" }),
		agent({ pane = 2, state = "working", title = ICON .. " pi busy", cwd = PI, repo = PI }),
		agent({ pane = 3, title = ICON .. " deck idle" }),
		agent({ pane = 4, title = ICON .. " pi idle", cwd = PI, repo = PI }),
		agent({ pane = 5, title = ICON .. " zeta idle", cwd = "/Users/me/zeta", repo = "/Users/me/zeta" }),
	}
	local working = { PI_LABEL, ICON .. "(Working) pi busy 0s", DECK_LABEL, ICON .. "(Working) deck busy 0s" }
	local idle = {
		PI_LABEL,
		ICON .. "(Idle) pi idle",
		DECK_LABEL,
		ICON .. "(Idle) deck idle",
		"zeta [:plus](New tab in this repo)",
		ICON .. "(Idle) zeta idle",
	}
	for _, extra in { {}, { focused = 1 }, { focused = 3 }, { focused = 5 } } do
		local out = view(agents, extra)
		t.eq(visible.zone(out, "Working"), working)
		t.eq(visible.zone(out, "Idle"), idle)
	end
end)

t.test("a project label's + asks for a new tab in that project, and its hover card gives the short path", function()
	local out = view({ agent({}), agent({ pane = 2, title = ICON .. " x", cwd = "/opt/src/app" }) })
	t.eq(visible.button(out, "tern-agent-deck"), "new=" .. DECK)
	t.eq(visible.button(out, "app"), "new=/opt/src/app")
	t.eq(visible.onHover(out, "tern-agent-deck"), { "[:plus](New tab in this repo)" })
	t.eq(visible.hover(out, "tern-agent-deck"), "~/Personal/tern-agent-deck")
	t.eq(visible.hover(out, "app"), "/opt/src/app")
end)

t.test("an agent row shows only omp's title icon, the title without the icon, and one time", function()
	local out = view({ agent({ activeAt = NOW - 4 * 60 }) })
	t.eq(visible.agentRows(out), { ICON .. "(Idle) Fix login 4m" })
	t.eq(visible.titles(out, "Fix login"), {})
end)

t.test("the time shows in one format, the largest whole unit: 45s, 4m, 3h, 2d", function()
	local function shown(seconds: number): string
		return visible.agentRows(view({ agent({ activeAt = NOW - seconds }) }))[1]
	end
	t.eq(shown(45), ICON .. "(Idle) Fix login 45s")
	t.eq(shown(4 * 60 + 59), ICON .. "(Idle) Fix login 4m")
	t.eq(shown(3 * 3600 + 59 * 60), ICON .. "(Idle) Fix login 3h")
	local old = visible.agentRows(view({ agent({ activeAt = NOW - 2 * DAY - 5 }) }, { olderOpen = true }))
	t.eq(old[#old], ICON .. "(Idle) Fix login 2d")
end)

t.test("a working agent's time is its turn timer; a waiting agent's is its wait", function()
	local out = view({
		agent({ pane = 1, state = "working", workingSince = 10_000, activeAt = NOW - 3 * DAY }),
		agent({ pane = 2, state = "waiting_input", title = ICON .. " asks", activeAt = NOW - 7 * 60 }),
	}, { now = 55_000 })
	t.eq(visible.zone(out, "Working"), { DECK_LABEL, ICON .. "(Working) Fix login 45s" })
	t.eq(visible.zone(out, "Needs you"), { ICON .. "(Waiting for you) asks 7m" })
end)

t.test("a row shows no time when the agent's last turn is unknown", function()
	t.eq(visible.agentRows(build({ agent({}) }, { time = nil }).view), { ICON .. "(Idle) Fix login" })
	t.eq(visible.agentRows(view({ agent({}) })), { ICON .. "(Idle) Fix login" })
end)

t.test("an agent whose title has no omp icon shows Tern's agent icon in its state's color", function()
	local out = view({
		agent({ pane = 1, state = "working", title = "claude", workingSince = 0 }),
		agent({ pane = 2, title = "", cwd = "/Users/me/codex-work" }),
	})
	t.eq(visible.agentRows(out), { ":terminal(Working) claude 0s", ":terminal(Idle) codex-work" })
	t.eq(visible.state(out, "claude"), "working")
	t.eq(visible.state(out, ") codex-work"), "idle")
end)

t.test("a tab name the user set names an agent alone in its tab, after omp's icon", function()
	t.eq(visible.agentRows(view({ agent({ tab = 7, tabName = "Auth rewrite" }) })), { ICON .. "(Idle) Auth rewrite" })
	t.eq(visible.agentRows(view({
		agent({ pane = 1, tab = 7, tabName = "Auth rewrite", title = ICON .. " Plan" }),
		agent({ pane = 2, tab = 7, tabName = "Auth rewrite", title = ICON .. " Build" }),
	})), { ICON .. "(Idle) Plan", ICON .. "(Idle) Build" })
end)

t.test("the title icon carries the agent's state, and no state uses a Tern tone or the accent", function()
	local out = view({
		agent({ pane = 1, state = "working", title = ICON .. " a", workingSince = 0 }),
		agent({ pane = 2, state = "waiting_input", title = ICON .. " b" }),
		agent({ pane = 3, state = "idle", title = ICON .. " c" }),
	}, { pins = { { pane = 9, title = ICON .. " d", cwd = DECK, sessionFile = "/s/d.jsonl" } } })
	t.eq(visible.state(out, "a 0s"), "working")
	t.eq(visible.state(out, ") b"), "waiting")
	t.eq(visible.state(out, ") c"), "idle")
	t.eq(visible.state(out, ") d"), "stopped")
	t.eq(visible.stateColors(out), {})
end)

t.test("a click on a row focuses its agent, and its right-click menu is unchanged", function()
	local out = view({ agent({ pane = 17179869199, sessionFile = "/s/a.jsonl" }) })
	t.eq(visible.click(out, "Fix login"), "focus=17179869199")
	t.eq(visible.menu(out, "Fix login"), {
		"Pin → pin=17179869199",
		"Rename → rename=17179869199",
		"Copy session ID → copy-id=/s/a.jsonl",
		"Copy session path → copy-path=/s/a.jsonl",
		"Interrupt → interrupt=17179869199 (off: The agent is not in a turn)",
	})
end)

t.test("this tab's agent is drawn selected and keeps its place in its zone and project", function()
	local agents = {
		agent({ pane = 1, title = ICON .. " first", activeAt = NOW - 60 }),
		agent({ pane = 2, title = ICON .. " second", activeAt = NOW - 30 }),
		agent({ pane = 3, title = ICON .. " mine", activeAt = NOW - 3600 }),
	}
	local out = view(agents, { focused = 3 })
	t.eq(visible.selected(out), { ICON .. "(Idle) mine 1h" })
	local order = { DECK_LABEL, ICON .. "(Idle) first 1m", ICON .. "(Idle) second 30s", ICON .. "(Idle) mine 1h" }
	t.eq(visible.zone(out, "Idle"), order)
	t.eq(visible.zone(view(agents, { focused = 1 }), "Idle"), order)
	t.eq(visible.zone(view(agents), "Idle"), order)
end)

t.test("inside a zone and project, agents keep their start order whatever their turn times", function()
	local function zones(early: number, late: number, fresh: number, stale: number): ({ string }, { string })
		local out = view({
			agent({ pane = 1, state = "working", title = ICON .. " one", workingSince = early }),
			agent({ pane = 2, state = "working", title = ICON .. " two", workingSince = late }),
			agent({ pane = 3, title = ICON .. " three", activeAt = NOW - fresh }),
			agent({ pane = 4, title = ICON .. " four", activeAt = NOW - stale }),
		}, { now = 70_000 })
		local working, idle = {}, {}
		for _, line in visible.zone(out, "Working") do
			table.insert(working, (string.gsub(line, " %d+%a$", "")))
		end
		for _, line in visible.zone(out, "Idle") do
			table.insert(idle, (string.gsub(line, " %d+%a$", "")))
		end
		return working, idle
	end
	local working, idle = zones(10_000, 50_000, 60, 7200)
	t.eq(working, { DECK_LABEL, ICON .. "(Working) one", ICON .. "(Working) two" })
	t.eq(idle, { DECK_LABEL, ICON .. "(Idle) three", ICON .. "(Idle) four" })
	local swappedWorking, swappedIdle = zones(50_000, 10_000, 7200, 60)
	t.eq(swappedWorking, working)
	t.eq(swappedIdle, idle)
end)

t.test("an agent that leaves a zone and comes back takes its old place", function()
	local function idle(state: string): { string }
		return visible.zone(view({
			agent({ pane = 1, title = ICON .. " one" }),
			agent({ pane = 2, state = state, title = ICON .. " two" }),
			agent({ pane = 3, title = ICON .. " three" }),
		}), "Idle")
	end
	local before = idle("idle")
	t.eq(before, { DECK_LABEL, ICON .. "(Idle) one", ICON .. "(Idle) two", ICON .. "(Idle) three" })
	t.eq(idle("working"), { DECK_LABEL, ICON .. "(Idle) one", ICON .. "(Idle) three" })
	t.eq(idle("idle"), before)
end)

t.test("pinned agents come first in their zone and project, in the order they were pinned, whatever the focus", function()
	local agents = {
		agent({ pane = 1, title = ICON .. " plain", activeAt = NOW - 10 }),
		agent({ pane = 2, title = ICON .. " second pin", activeAt = NOW - 300 }),
		agent({ pane = 3, title = ICON .. " first pin", activeAt = NOW - 900 }),
		agent({ pane = 4, title = ICON .. " mine", activeAt = NOW - 5000 }),
	}
	local pins = {
		{ pane = 3, cwd = DECK, title = ICON .. " first pin" },
		{ pane = 2, cwd = DECK, title = ICON .. " second pin" },
	}
	local order = {
		DECK_LABEL,
		ICON .. "(Idle) first pin 15m",
		ICON .. "(Idle) second pin 5m",
		ICON .. "(Idle) plain 10s",
		ICON .. "(Idle) mine 1h",
	}
	t.eq(visible.zone(view(agents, { focused = 4, pins = pins }), "Idle"), order)
	t.eq(visible.zone(view(agents, { focused = 1, pins = pins }), "Idle"), order)
end)

t.test("a pinned agent that stopped is one line in Idle under its project, with a resume icon on hover", function()
	local out = view({
		agent({ pane = 1, title = ICON .. " live", activeAt = NOW - 60 }),
		agent({ pane = 2, state = "exited", title = ICON .. " Done", sessionFile = "/s/done.jsonl", activeAt = NOW - 3 * 3600 }),
	}, { pins = { { pane = 2, cwd = DECK, title = ICON .. " Done" } } })
	t.eq(visible.zones(out), { "■ Idle 1 idle · 1 stopped" })
	t.eq(visible.zone(out, "Idle"), { DECK_LABEL, ICON .. "(Idle) live 1m", ICON .. "(Stopped) Done 3h :play" })
	t.eq(visible.onHover(out, "Done"), { ":play" })
	t.eq(visible.state(out, "Done"), "stopped")
	t.eq(visible.click(out, "Done"), "resume=/s/done.jsonl")
end)

t.test("a pinned agent whose pane is gone shows in Idle under its folder; Unpin forgets the pin", function()
	local out = view({}, {
		pins = { { pane = 9, cwd = "/tmp", title = ICON .. " Gone", sessionFile = "/s/gone.jsonl" } },
	})
	t.eq(visible.zone(out, "Idle"), { "tmp [:plus](New tab in this folder)", ICON .. "(Stopped) Gone :play" })
	t.eq(visible.click(out, "Gone"), "resume=/s/gone.jsonl")
	t.eq(visible.menu(out, "Gone")[1], "Unpin → forget=1")
end)

t.test("a gone pin with no session file says so on a click", function()
	local out = view({}, { pins = { { pane = 9, cwd = "/tmp", title = ICON .. " Lost" } } })
	t.eq(visible.click(out, "Lost"), "gone=1")
end)

t.test("idle agents whose last turn ended a day ago or more fold under a closed Older than a day, with their count", function()
	local out = view({
		agent({ pane = 1, title = ICON .. " old plan", activeAt = NOW - 2 * DAY }),
		agent({ pane = 2, title = ICON .. " today", activeAt = NOW - 3600 }),
		agent({ pane = 3, title = ICON .. " old review", activeAt = NOW - DAY }),
	})
	t.eq(visible.zones(out), { "■ Idle 3" })
	t.eq(visible.zone(out, "Idle"), { DECK_LABEL, ICON .. "(Idle) today 1h", ":chev-r Older than a day 2" })
	t.eq(visible.click(out, "Older than a day"), "older")
end)

t.test("an open Older than a day lists its agents by project, in start order", function()
	local out = view({
		agent({ pane = 1, title = ICON .. " old plan", activeAt = NOW - 2 * DAY }),
		agent({ pane = 2, title = ICON .. " today", activeAt = NOW - 3600 }),
		agent({ pane = 3, title = ICON .. " old review", activeAt = NOW - DAY }),
		agent({ pane = 4, title = ICON .. " old pi", cwd = PI, repo = PI, activeAt = NOW - 3 * DAY }),
	}, { olderOpen = true })
	t.eq(visible.zone(out, "Idle"), {
		DECK_LABEL,
		ICON .. "(Idle) today 1h",
		":chev Older than a day 3",
		PI_LABEL,
		ICON .. "(Idle) old pi 3d",
		DECK_LABEL,
		ICON .. "(Idle) old plan 2d",
		ICON .. "(Idle) old review 1d",
	})
end)

t.test("pins never fold under Older than a day, nor do working or waiting agents", function()
	local out = view({
		agent({ pane = 1, title = ICON .. " pinned", activeAt = NOW - 9 * DAY }),
		agent({ pane = 2, title = ICON .. " old", activeAt = NOW - 9 * DAY }),
		agent({ pane = 3, state = "working", title = ICON .. " busy", workingSince = 0, activeAt = NOW - 5 * DAY }),
		agent({ pane = 4, state = "waiting_input", title = ICON .. " asks", activeAt = NOW - 5 * DAY }),
	}, { pins = { { pane = 1, cwd = DECK, title = ICON .. " pinned" } } })
	t.eq(visible.zone(out, "Idle"), { DECK_LABEL, ICON .. "(Idle) pinned 9d", ":chev-r Older than a day 1" })
end)

t.test("the focus never moves an old idle agent out of Older than a day", function()
	local agents = {
		agent({ pane = 1, title = ICON .. " today", activeAt = NOW - 3600 }),
		agent({ pane = 2, title = ICON .. " old", activeAt = NOW - 2 * DAY }),
	}
	for _, olderOpen in { false, true } do
		local unfocused = visible.zone(view(agents, { olderOpen = olderOpen }), "Idle")
		t.eq(visible.zone(view(agents, { olderOpen = olderOpen, focused = 2 }), "Idle"), unfocused)
		t.eq(visible.zone(view(agents, { olderOpen = olderOpen, focused = 1 }), "Idle"), unfocused)
	end
end)

t.test("a closed Older than a day that holds this tab's agent carries the accent; an open one leaves it to the row", function()
	local agents = {
		agent({ pane = 1, title = ICON .. " today", activeAt = NOW - 3600 }),
		agent({ pane = 2, title = ICON .. " old", activeAt = NOW - 2 * DAY }),
	}
	t.eq(visible.accented(view(agents, { focused = 2 })), { ":chev-r Older than a day 1" })
	t.eq(visible.accented(view(agents, { focused = 2, olderOpen = true })), { ICON .. "(Idle) old 2d" })
	t.eq(visible.accented(view(agents, { focused = 1 })), { ICON .. "(Idle) today 1h" })
end)

t.test("the sidebar redraws when a row's time shows another text or an idle agent reaches a day", function()
	local function due(agents: { any }, extra: { [string]: any }?): number?
		local input: { [string]: any } = { agents = agents, now = 100_000, time = NOW }
		for k, v in (extra or {}) :: { [string]: any } do
			input[k] = v
		end
		return viewModel.redrawDue(input :: any)
	end
	t.eq(due({ agent({ state = "working", workingSince = 99_600 }) }), 600)
	t.eq(due({ agent({ state = "working", workingSince = 100_000 - 90_000 }) }), 30_000)
	t.eq(due({ agent({ activeAt = NOW - 2 * 3600 - 600 }) }), 3000 * 1000)
	t.eq(due({ agent({ activeAt = NOW - DAY + 60 }) }), 60 * 1000)
	t.eq(due({ agent({ activeAt = NOW - 3 * DAY }) }), DAY * 1000)
	t.eq(due({ agent({}) }), nil)
	t.eq(due({ agent({ state = "exited", activeAt = NOW - 30 }) }), nil)
end)

t.test("the head holds only the Live/Recent switch, Live by default; a click shows the view", function()
	local live = view({ agent({}) })
	t.eq(visible.chrome(live), { "[Live] [Recent]" })
	t.eq(visible.shownView(live), "Live")
	t.eq(visible.shownView(view({ agent({}) }, { view = "recent" })), "Recent")
	t.eq(visible.find(live, "menu"), nil)
	t.eq(visible.press(live, "Recent"), "view=recent")
	t.eq(visible.press(live, "Live"), "view=live")
end)

t.test("a full Live view of 10 agents with open crews and cards fits one canvas update", function()
	-- A canvas update holds at most 2000 nodes, hover-card nodes included, and 256 KiB.
	local states = { "waiting_input", "waiting_input", "waiting_input", "working", "working", "working", "working", "idle", "idle", "idle" }
	local message = string.rep("The change touches lib/view_model.luau and tests/live_zones_spec.luau; ", 30)
	local agents: { any } = {}
	local subs: { [number]: any } = {}
	for pane = 1, 10 do
		local project = "/Users/me/Personal/project-with-a-long-name-" .. (pane % 4)
		table.insert(agents, agent({
			pane = pane,
			state = states[pane],
			cwd = project,
			repo = project,
			title = ICON .. " Agent " .. pane .. " with a title of usual length",
			tab = 944892805168 + pane,
			tabNumber = pane,
			tabName = "Tab " .. pane,
			model = "claude-opus-5-5",
			route = "anthropic/claude-opus-5-5",
			effort = "high",
			lastMessage = message,
			summary = "It changed the view model and its tests; both pass.",
			workingSince = 0,
			activeAt = NOW - 60,
			sessionFile = "/Users/me/.omp/agent/sessions/-Personal-project/2026-11-27T08-21-12-853Z_01a1bf65-95ef-77f9-baad-ec9dc64f" .. pane .. ".jsonl",
		}))
		local crew: { any } = {}
		for i = 1, 40 do
			local status = if i <= 6 then "running" elseif i == 7 then "failed" else "pending"
			table.insert(crew, {
				id = "Sub" .. i,
				name = "Sub" .. i,
				status = status,
				depth = 1,
				waiting = i == 1,
				role = "task",
				model = "claude-opus-5-5",
				effort = "high",
				intent = "Read /Users/me/Personal/tern-agent-deck/lib/view_model.luau and report what it does " .. i,
				since = i,
			})
		end
		subs[pane] = { agents = crew, incomplete = false }
	end
	local out = view(agents, { subagents = subs, focused = 4 })
	t.eq(#visible.cards(out) >= 3, true)
	local nodes, bytes = visible.size(out)
	t.eq(nodes < 2000, true)
	t.eq(bytes < 256 * 1024, true)
end)

return nil
