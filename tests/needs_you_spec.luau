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

t.test("Needs you lists the waiting agents first, each in no other zone, pinned ones too", function()
	local out = build({
		agents = {
			agent({ pane = 1, title = "plan" }),
			agent({ pane = 2, title = "ask", state = "waiting_input", activeAt = NOW - 90 }),
			agent({ pane = 3, title = "pinned ask", state = "waiting_input", activeAt = NOW - 30 }),
		},
		pins = { { pane = 3, cwd = REPO, title = "pinned ask" } },
	}).view
	t.eq(visible.zones(out), { "■ Needs you 2", "■ Idle 1" })
	t.eq(visible.zone(out, "Needs you"), { ":sparkle(Waiting for you) ask 1m", ":sparkle(Waiting for you) pinned ask 30s" })
	t.eq(visible.zone(out, "Idle"), { "tern-agents [:plus](New tab in this repo)", ":sparkle(Idle) plan" })
	t.eq(visible.click(out, ") ask"), "focus=2")
end)

t.test("Needs you hides when no agent waits", function()
	local out = build({ agents = { agent({ pane = 1, title = "plan", state = "working", workingSince = 0 }) } }).view
	t.eq(visible.zones(out), { "■ Working 1 busy" })
end)

t.test("Needs you lists the agent that has waited longest first", function()
	t.eq(visible.zone(build({
		agents = {
			agent({ pane = 1, title = "late", state = "waiting_input", activeAt = NOW - 100 }),
			agent({ pane = 2, title = "early", state = "waiting_input", activeAt = NOW - 300, cwd = "/tmp" }),
			agent({ pane = 3, title = "middle", state = "waiting_input", activeAt = NOW - 200 }),
		},
	}).view, "Needs you"), {
		":sparkle(Waiting for you) early 5m",
		":sparkle(Waiting for you) middle 3m",
		":sparkle(Waiting for you) late 1m",
	})
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
