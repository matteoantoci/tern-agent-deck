--!strict
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local function sub(name: string, status: string, depth: number?, extra: { [string]: any }?): { [string]: any }
	local s: { [string]: any } = { id = "dx." .. name, name = name, status = status, depth = depth or 1 }
	for k, v in (extra or {}) :: { [string]: any } do
		s[k] = v
	end
	return s
end

local function lead(state: string): { [string]: any }
	return { pane = 7, state = state, cwd = "/repo", title = "Lead", workingSince = 0 }
end

local function view(state: string, agents: { any }, incomplete: boolean?): any
	return viewModel.build({
		agents = { lead(state) },
		now = 0,
		subagents = { [7] = { agents = agents, incomplete = incomplete == true } },
	}).view
end

t.test("a subagent row shows the dot, the name and its role, with no model chip, no tool text and no end mark", function()
	t.eq(visible.agentRows(view("working", {
		sub("Ticket03", "running", 1, { model = "anthropic/claude-opus-5-5", role = "task" }),
		sub("Ticket07", "running", 1, { tool = "bash", intent = "Running probe", model = "GPT-5.1", role = "scout" }),
		sub("Bare", "running", 1),
	})), {
		"●(Working) Lead",
		"●(Running) Ticket03 task",
		"●(Running) Ticket07 scout",
		"●(Running) Bare",
	})
end)

t.test("a subagent row's hover card shows its role, model, effort, current tool and intent, and the row has no tooltip", function()
	local out = view("working", {
		sub("Ticket07", "running", 1, {
			tool = "bash",
			intent = "Running probe",
			model = "anthropic/claude-opus-5-5",
			role = "scout",
			effort = "high",
		}),
		sub("Quiet", "running", 1),
	})
	t.eq(
		visible.hover(out, "Ticket07"),
		"Ticket07 · Running\nRole scout\nModel claude-opus-5-5\n◔high Effort high\nTool bash\nIntent Running probe"
	)
	t.eq(visible.titles(out, "Ticket07"), {})
	t.eq(visible.hover(out, "Quiet"), "Quiet · Running")
	t.eq(visible.titles(out, "Quiet"), {})
end)

t.test("subagent names render in the sans face", function()
	t.eq(visible.face(view("working", { sub("Ticket07", "running", 1, { role = "task" }) }), "Ticket07"), "sans")
end)

t.test("a subagent row draws its role and parent as secondary text after the name, which stays primary", function()
	local out = view("working", {
		sub("CopyItems", "running", 1, { role = "task" }),
		sub("Probe", "running", 2, { role = "scout", parent = "CopyItems" }),
	})
	t.eq(visible.secondary(out, "task"), true)
	t.eq(visible.secondary(out, "scout · in CopyItems"), true)
	t.eq(visible.secondary(out, "CopyItems"), false)
end)

t.test("nested subagents show in the same flat list, each naming the subagent it runs under", function()
	local out = view("working", {
		sub("Merge0407", "running", 1, { role = "task" }),
		sub("Ticket04", "running", 2, { role = "task", parent = "Merge0407" }),
		sub("Probe", "running", 3, { parent = "Ticket04" }),
		sub("Other", "running", 1),
	})
	t.eq(visible.agentRows(out), {
		"●(Working) Lead",
		"●(Running) Merge0407 task",
		"●(Running) Ticket04 task · in Merge0407",
		"●(Running) Probe in Ticket04",
		"●(Running) Other",
	})
	t.eq(visible.hover(out, "Probe"), "Probe · Running\nUnder Ticket04")
end)

t.test("every level omp renders shows; a level past omp's limit folds into one +N deeper line", function()
	local subs: { any } = {}
	for depth = 1, 11 do
		table.insert(subs, sub("L" .. depth, "running", depth, { parent = if depth > 1 then "L" .. (depth - 1) else nil }))
	end
	local rows = visible.agentRows(view("working", subs))
	t.eq(#rows, 1 + 9 + 1)
	t.eq(rows[10], "●(Running) L9 in L8")
	t.eq(rows[11], ":more +2 deeper")
end)

t.test("a click on a subagent row asks to show that subagent in omp's view, at every level", function()
	local out = view("working", { sub("Ticket07", "running"), sub("Deep", "running", 3, { parent = "Mid" }) })
	t.eq(visible.click(out, "Ticket07"), "subagent=7 dx.Ticket07")
	t.eq(visible.click(out, "Deep"), "subagent=7 dx.Deep")
end)

t.test("finished subagents at every level fold into one line that counts each result; pending ones show nothing yet", function()
	t.eq(visible.agentRows(view("working", {
		sub("A", "done"),
		sub("B", "running"),
		sub("C", "failed"),
		sub("D", "aborted", 2),
		sub("E", "pending"),
		sub("F", "done", 3),
	})), {
		"●(Working) Lead",
		"●(Running) B",
		":x 2 subagents done, 1 failed, 1 stopped",
	})
	t.eq(visible.agentRows(view("working", { sub("A", "done") })), { "●(Working) Lead", ":check 1 subagent done" })
	t.eq(visible.agentRows(view("working", { sub("A", "failed") })), { "●(Working) Lead", ":x 1 subagent failed" })
end)

t.test("the finished line takes its tone from the worst result: green when all succeed, red on a failure, muted on a stop", function()
	local allDone = view("working", { sub("A", "done"), sub("B", "done") })
	t.eq(visible.iconTone(allDone, "2 subagents done"), "success")
	local oneFailed = view("working", { sub("A", "done"), sub("B", "failed"), sub("C", "aborted") })
	t.eq(visible.iconTone(oneFailed, "1 subagent done, 1 failed, 1 stopped"), "error")
	local oneStopped = view("working", { sub("A", "done"), sub("B", "aborted") })
	t.eq(visible.agentRows(oneStopped), { "●(Working) Lead", ":check 1 subagent done, 1 stopped" })
	t.eq(visible.iconTone(oneStopped, "1 subagent done, 1 stopped"), "muted")
end)

t.test("when the agent becomes idle with every subagent finished, its done line disappears", function()
	t.eq(visible.agentRows(view("idle", { sub("A", "done"), sub("B", "failed") }, true)), { "●(Idle) Lead" })
end)

t.test("an idle agent whose background subagents still run keeps their rows under its idle row", function()
	t.eq(visible.agentRows(view("idle", { sub("A", "done"), sub("B", "running") })), {
		"●(Idle) Lead",
		"●(Running) B",
		":check 1 subagent done",
	})
end)

t.test("a read that Tern cut shows that the subagents may be incomplete", function()
	t.eq(visible.agentRows(view("working", { sub("B", "running") }, true)), {
		"●(Working) Lead",
		"●(Running) B",
		":warn subagents may be incomplete",
	})
	t.eq(visible.agentRows(view("working", {}, true)), { "●(Working) Lead", ":warn subagents may be incomplete" })
end)

t.test("an agent with no subagent data (Claude Code, Codex, omp without a task call) shows only its row", function()
	t.eq(visible.agentRows(viewModel.build({ agents = { lead("working") }, now = 0, subagents = {} }).view), {
		"●(Working) Lead",
	})
end)

t.test("a working agent in a repo group shows its subagent rows inside that group, under its row", function()
	local out = viewModel.build({
		agents = {
			{ pane = 3, state = "idle", title = "Notes", cwd = "/tmp" },
			{ pane = 7, state = "working", title = "Lead", repo = "/Users/me/alpha", workingSince = 0 },
			{ pane = 9, state = "idle", title = "Docs", repo = "/Users/me/beta" },
		},
		now = 0,
		home = "/Users/me",
		subagents = { [7] = { agents = { sub("Ticket07", "running", 1, { tool = "bash" }), sub("A", "done") }, incomplete = false } },
	}).view
	t.eq(visible.rows(out), {
		":chev :mi-folder-open alpha 1 [:plus](New tab in this repo)",
		"●(Working) Lead",
		"●(Running) Ticket07",
		":check 1 subagent done",
		":chev :mi-folder-open beta 1 [:plus](New tab in this repo)",
		"●(Idle) Docs",
		":chev :mi-folder-open tmp 1 [:plus](New tab in this folder)",
		"●(Idle) Notes",
	})
	t.eq(visible.click(out, "Ticket07"), "subagent=7 dx.Ticket07")
end)

return nil
