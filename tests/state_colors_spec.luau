--!strict
-- Each state reaches the canvas as data (the state in the role of its title icon, square, dot or icon), and
-- `agents.css` gives it its color. No state takes a Tern tone, so the accent marks only this tab's agent.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local function agent(pane: number, state: string, title: string): { [string]: any }
	return { pane = pane, state = state, cwd = "/repo", title = title, workingSince = 0 }
end

local function sub(name: string, status: string, extra: { [string]: any }?): { [string]: any }
	local s: { [string]: any } = { id = name, name = name, status = status, depth = 1 }
	for k, v in (extra or {}) :: { [string]: any } do
		s[k] = v
	end
	return s
end

t.test("each agent state puts its own state on the title icon, and each zone its state on its square", function()
	local out = viewModel.build({
		agents = { agent(1, "working", "a"), agent(2, "waiting_input", "b"), agent(3, "idle", "c") },
		now = 0,
	}).view
	t.eq(visible.states(out), {
		"waiting: ■ Needs you 1",
		"waiting: :terminal(Waiting for you) b",
		"working: ■ Working 1 busy",
		"working: :terminal(Working) a 0s",
		"idle: ■ Idle 1",
		"idle: :terminal(Idle) c",
	})
end)

t.test("a stopped pinned agent puts the stopped state on its title icon", function()
	local out = viewModel.build({
		agents = {},
		pins = { { pane = 9, title = "Done", cwd = "/repo" } },
		now = 0,
	}).view
	t.eq(visible.state(out, ") Done"), "stopped")
end)

t.test("each subagent state puts its own state on its line's square", function()
	local live = viewModel.build({
		agents = { agent(7, "working", "Lead") },
		now = 0,
		focused = 7,
		subagents = { [7] = { agents = { sub("A", "running"), sub("B", "running", { waiting = true }), sub("C", "running", { intent = "Ask Which one?" }) }, incomplete = false } },
	}).view
	t.eq(visible.states(live), {
		"waiting: ■ Needs you 1",
		"waiting: ■(Waiting for you) C in Lead",
		"working: ■ Working 1 busy",
		"working: :terminal(Working) Lead 0s [:chev]",
		"running: ■(Running) A",
		"running: ■(Running) B",
		"waiting: ■(Waiting for you) C Ask Which one?",
	})
end)

t.test("no title icon, square or strip bar takes a Tern tone or span style, so no state uses the accent", function()
	local out = viewModel.build({
		agents = { agent(1, "working", "a"), agent(2, "waiting_input", "b"), agent(3, "idle", "c"), agent(7, "working", "Lead") },
		pins = { { pane = 9, title = "d", cwd = "/repo" } },
		now = 0,
		subagents = {
			[7] = {
				agents = { sub("A", "running"), sub("B", "running", { waiting = true }), sub("C", "done"), sub("D", "failed") },
				incomplete = false,
			},
		},
	}).view
	t.eq(visible.stateColors(out), {})
end)

return nil
