--!strict
-- Each state reaches the canvas as data (the state in the role of its dot or icon), and `agents.css` gives it its
-- color. No state takes a Tern tone, so the accent marks only the selected row.
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

t.test("each agent state puts its own state on the dot", function()
	local out = viewModel.build({
		agents = { agent(1, "working", "a"), agent(2, "waiting_input", "b"), agent(3, "idle", "c") },
		now = 0,
	}).view
	t.eq(visible.states(out), {
		"waiting: :bell Needs you 1",
		"waiting: ●(Waiting for you) b repo :bell",
		"working: ●(Working) a",
		"waiting: ●(Waiting for you) b :bell",
		"idle: ●(Idle) c",
	})
end)

t.test("an exited pinned agent puts the exited state on its dot", function()
	local out = viewModel.build({
		agents = {},
		pins = { { pane = 9, title = "Done", cwd = "/repo" } },
		now = 0,
	}).view
	local exited = false
	for _, shown in visible.states(out) do
		if string.find(shown, "^exited: ○%(Exited%)") then
			exited = true
		end
	end
	t.eq(exited, true)
end)

t.test("each subagent state puts its own state on its dot or on the finished line's icon", function()
	local function view(subs: { any }): any
		return viewModel.build({
			agents = { agent(7, "working", "Lead") },
			now = 0,
			subagents = { [7] = { agents = subs, incomplete = false } },
		}).view
	end
	local live = view({ sub("A", "running"), sub("B", "running", { waiting = true }) })
	t.eq(visible.states(live), {
		"working: ●(Working) Lead",
		"running: ●(Running) A",
		"waiting: ●(Waiting on its subagents) B",
	})
	t.eq(visible.state(view({ sub("A", "done") }), "1 subagent done"), "done")
	t.eq(visible.state(view({ sub("A", "done"), sub("B", "failed") }), "1 subagent done, 1 failed"), "failed")
	t.eq(visible.state(view({ sub("A", "done"), sub("B", "aborted") }), "1 subagent done, 1 stopped"), "stopped")
end)

t.test("no state dot, state icon or end mark takes a Tern tone or span style, so no state uses the accent", function()
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
