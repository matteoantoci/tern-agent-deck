--!strict
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local REPO = "/Users/me/Personal/tern-agents"
local NOW = 1_800_000_000

-- An agent in REPO unless `fields` names another working directory (then outside any repo, unless it names one).
local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = REPO, title = "Fix login" }
	if fields.cwd == nil then
		a.repo = REPO
	end
	for k, v in fields do
		a[k] = v
	end
	return a
end

local function build(input: { [string]: any }): any
	local full: { [string]: any } = { agents = {}, now = 0, time = NOW, home = HOME, plugin = "agent-deck" }
	for k, v in input do
		full[k] = v
	end
	return viewModel.build(full :: any)
end

-- A running subagent `name` whose call is `intent`, started `ago` seconds before the build's `now` (0 ms).
local function sub(name: string, intent: string?, ago: number?, extra: { [string]: any }?): { [string]: any }
	local s: { [string]: any } = {
		id = name,
		name = name,
		status = "running",
		depth = 1,
		role = "task",
		intent = intent,
		since = -(ago or 0) * 1000,
	}
	for k, v in (extra or {}) :: { [string]: any } do
		s[k] = v
	end
	return s
end

t.test("Needs you shows each waiting agent as a card: title icon, title, wait time, question and footer", function()
	local out = build({
		agents = {
			agent({ pane = 1, title = "plan" }),
			agent({
				pane = 2,
				title = "\u{F0E7} ask",
				state = "waiting_input",
				activeAt = NOW - 90,
				tab = 2,
				lastMessage = "Which branch should I rebase onto?",
			}),
		},
	}).view
	t.eq(visible.zones(out), { "■ Needs you 1", "■ Idle 1" })
	t.eq(visible.cards(out), {
		"\u{F0E7}(Waiting for you) ask 1m | Which branch should I rebase onto? | tern-agents · tab 2",
	})
	t.eq(visible.cardStates(out, "ask"), { "waiting", "waiting" })
	t.eq(visible.cardFooterFace(out, "ask"), "mono")
	t.eq(visible.zone(out, "Idle"), { "tern-agents [:plus](New tab in this repo)", ":sparkle(Idle) plan" })
end)

t.test("a pinned waiting agent is a card too, in no other zone", function()
	local out = build({
		agents = { agent({ pane = 3, title = "pinned ask", state = "waiting_input", activeAt = NOW - 30, tab = 1 }) },
		pins = { { pane = 3, cwd = REPO, title = "pinned ask" } },
	}).view
	t.eq(visible.zones(out), { "■ Needs you 1" })
	t.eq(visible.cards(out), { ":sparkle(Waiting for you) pinned ask 30s | tern-agents · tab 1" })
end)

t.test("a card's footer leaves out the tab or the project it does not know", function()
	local out = build({
		agents = { agent({ pane = 2, title = "loose", state = "waiting_input", activeAt = NOW - 5, cwd = "/tmp/x" }) },
	}).view
	t.eq(visible.cards(out), { ":sparkle(Waiting for you) loose 5s | x" })
end)

t.test("Needs you hides when no agent waits", function()
	local out = build({ agents = { agent({ pane = 1, title = "plan", state = "working", workingSince = 0 }) } }).view
	t.eq(visible.zones(out), { "■ Working 1 busy" })
	t.eq(visible.cards(out), {})
end)

t.test("a subagent that asks the user is a card named after itself in its agent, with its type in the footer", function()
	local out = build({
		agents = { agent({ pane = 7, title = "Lead", state = "working", workingSince = 0, tab = 3 }) },
		subagents = {
			[7] = {
				agents = {
					sub("Anna", "Ask Which database should I use?", 120),
					sub("Bob", "Edit view.luau", 300),
					sub("Cleo", "Ask Done?", 60, { status = "done" }),
				},
				incomplete = false,
			},
		},
	}).view
	t.eq(visible.zones(out), { "■ Needs you 1", "■ Working 1 busy" })
	t.eq(visible.cards(out), {
		"■(Waiting for you) Anna in Lead 2m | Which database should I use? | tern-agents · tab 3 · task",
	})
	t.eq(visible.cardStates(out, "Anna"), { "waiting", "waiting" })
end)

t.test("Needs you orders the cards of agents and subagents by wait time, longest first", function()
	t.eq(visible.cards(build({
		agents = {
			agent({ pane = 1, title = "late", state = "waiting_input", activeAt = NOW - 100 }),
			agent({ pane = 2, title = "early", state = "waiting_input", activeAt = NOW - 300, cwd = "/tmp" }),
			agent({ pane = 3, title = "middle", state = "waiting_input", activeAt = NOW - 200 }),
			agent({ pane = 7, title = "Lead", state = "working", workingSince = 0 }),
		},
		subagents = { [7] = { agents = { sub("Anna", "Ask Why?", 150) }, incomplete = false } },
	}).view), {
		":sparkle(Waiting for you) early 5m | tmp",
		":sparkle(Waiting for you) middle 3m | tern-agents",
		"■(Waiting for you) Anna in Lead 2m | Why? | tern-agents · task",
		":sparkle(Waiting for you) late 1m | tern-agents",
	})
end)

t.test("a click anywhere on a card focuses its agent or shows its subagent in omp, with no button", function()
	local out = build({
		agents = {
			agent({ pane = 2, title = "ask", state = "waiting_input", activeAt = NOW - 90 }),
			agent({ pane = 7, title = "Lead", state = "working", workingSince = 0 }),
		},
		subagents = { [7] = { agents = { sub("Anna", "Ask Why?", 10) }, incomplete = false } },
	}).view
	t.eq(visible.cardClick(out, ") ask"), "focus=2")
	t.eq(visible.cardClick(out, "Anna in Lead"), "subagent=7 Anna")
	t.eq(visible.cardHasButton(out, ") ask"), false)
	t.eq(visible.cardHasButton(out, "Anna in Lead"), false)
end)

t.test("a card's hover card holds the agent's facts and its last message", function()
	local out = build({
		agents = {
			agent({ pane = 2, title = "ask", state = "waiting_input", activeAt = NOW - 90, model = "Opus", lastMessage = "Go?" }),
		},
	}).view
	t.eq(visible.cardHover(out, ") ask"), "ask · Waiting for you\nModel opus\nGo?")
end)

t.test("the Live tab shows the waiting mark and how many cards need you, also while Recent is open", function()
	local agents = {
		agent({ pane = 1, title = "a", state = "waiting_input" }),
		agent({ pane = 2, title = "b", state = "waiting_input" }),
		agent({ pane = 7, title = "Lead", state = "working", workingSince = 0 }),
	}
	local subs = { [7] = { agents = { sub("Anna", "Ask Why?", 10) }, incomplete = false } }
	t.eq(visible.chrome(build({ agents = agents, subagents = subs }).view), { "[Live] ■(3 need you) 3 [Recent]" })
	t.eq(visible.chrome(build({ agents = agents, subagents = subs, view = "recent" }).view), {
		"[Live] ■(3 need you) 3 [Recent]",
	})
	t.eq(visible.chrome(build({ agents = { agents[3] } }).view), { "[Live] [Recent]" })
end)

t.test("the status segment counts the working and the waiting agents, pinned ones too, and a click runs the plugin's Next waiting agent", function()
	t.eq(build({
		agents = {
			agent({ pane = 1, state = "working" }),
			agent({ pane = 2, state = "working" }),
			agent({ pane = 3, state = "waiting_input" }),
			agent({ pane = 4, state = "waiting_input" }),
			agent({ pane = 5, state = "idle" }),
			agent({ pane = 6, state = "exited" }),
		},
		pins = { { pane = 4, cwd = REPO } },
	}).status, {
		{ text = "2 working · 2 waiting", icon = "bell", tone = "warn", command = "plugin.agent-deck.next-waiting" },
	})
end)

t.test("the status segment is muted while no agent waits, and hidden while none works or waits", function()
	t.eq(build({ agents = { agent({ pane = 1, state = "working" }), agent({ pane = 2 }) } }).status, {
		{ text = "1 working · 0 waiting", icon = "activity", tone = "muted", command = "plugin.agent-deck.next-waiting" },
	})
	t.eq(build({ agents = { agent({ pane = 1 }), agent({ pane = 2, state = "exited" }) } }).status, {})
end)

t.test("the segment's command names the plugin by the id it runs under", function()
	t.eq(build({ plugin = "my-fork", agents = { agent({ pane = 1, state = "working" }) } }).status[1].command, "plugin.my-fork.next-waiting")
end)

t.test("the next waiting agent is the one that has waited longest, pinned or not", function()
	t.eq(build({
		agents = {
			agent({ pane = 1, state = "waiting_input", activeAt = 300 }),
			agent({ pane = 2, state = "waiting_input", activeAt = 100 }),
			agent({ pane = 3, state = "working", activeAt = 50 }),
			agent({ pane = 4, state = "waiting_input", activeAt = 200 }),
		},
		pins = { { pane = 2, cwd = REPO } },
	}).waiting, { 2, 4, 1 })
	t.eq(build({ agents = { agent({ pane = 1, state = "working" }) } }).waiting, {})
end)

t.test("a toast names the agent, says what happened and where it works", function()
	local input: any = {
		agents = {
			agent({ pane = 1, title = "\u{F0E7} Fix login", tab = 3, tabName = "Auth" }),
			agent({ pane = 2, title = "scratch", cwd = "/tmp" }),
		},
		now = 0,
		home = HOME,
	}
	t.eq(viewModel.notice(input, 1, "waiting"), { level = "info", text = "Auth needs you", sub = "~/Personal/tern-agents" })
	t.eq(viewModel.notice(input, 1, "done"), { level = "success", text = "Auth finished", sub = "~/Personal/tern-agents" })
	t.eq(viewModel.notice(input, 2, "failed"), { level = "error", text = "scratch failed", sub = "/tmp" })
	t.eq(viewModel.notice(input, 9, "done"), nil)
end)

return nil
