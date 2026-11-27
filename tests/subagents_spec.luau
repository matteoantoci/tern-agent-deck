--!strict
local t = require("./harness")
local subagents = require("../lib/subagents")
local viewModel = require("../lib/view_model")
local visible = require("./visible")

-- Fixture trees shaped like a live `cx.session:surface(pane, {root = "dock"})` read (2026-11-27): the dock node under
-- `main`, holding omp's tray (`omp.tray`), one card (`omp.tray.card`) per subagent at every level, each with its
-- name, its model with the thinking level and what it does now as child text nodes.
local function card(ref: string, status: string, extra: { [string]: any }?): any
	local p: { [string]: any } = { role = "omp.tray.card", item = "agent", ref = ref, status = status }
	local model: string? = nil
	local call: string? = nil
	for k, v in (extra or {}) :: { [string]: any } do
		if k == "model" then
			model = v
		elseif k == "call" then
			call = v
		else
			p[k] = v
		end
	end
	local c: { any } = { { id = ref .. "/name", k = "text", p = { role = "omp.tray.name", text = ref } } }
	if call then
		table.insert(c, { id = ref .. "/call", k = "text", p = { role = "omp.tray.call", text = call } })
	end
	if model then
		table.insert(c, { id = ref .. "/model", k = "text", p = { role = "omp.tray.model", text = model } })
	end
	return { id = "tray/" .. ref, k = "col", p = p, c = c }
end

local function dock(cards: { any }): any
	local tray = { id = "tray", k = "col", p = { role = "omp.tray" }, c = cards }
	return { surface = { id = "s", mode = "flow" }, main = { id = "dock", k = "col", c = { tray } } }
end

local function summary(subs: any): { string }
	local out = {}
	for _, a in subs.agents do
		table.insert(out, a.name .. "|" .. a.status .. "@" .. a.depth .. " under " .. tostring(a.parent))
	end
	return out
end

t.test("the live tray card gives the subagent's id, type, model, effort and what it does", function()
	local subs = subagents.fromTray(dock({
		card("ProbeParent.FnLister", "done", {
			aria = "ProbeParent.FnLister, scout, done, Read view_model..., 6 tools",
			model = "claude-sonnet-5-5 · medium",
			call = "Read view_model...",
		}),
	})) :: any
	t.eq(subs.incomplete, false)
	local a = subs.agents[1]
	t.eq({ a.id, a.name, a.status, a.depth, a.parent, a.role, a.model, a.effort, a.intent, a.waiting } :: { any }, {
		"ProbeParent.FnLister",
		"ProbeParent>FnLister",
		"done",
		2,
		"ProbeParent",
		"scout",
		"claude-sonnet-5-5",
		"medium",
		"Read view_model...",
		false,
	} :: { any })
end)

t.test("nested cards sort into tree order from their dotted ids, each before its own subagents", function()
	local subs = subagents.fromTray(dock({
		card("Lead.Helper.Deep", "running"),
		card("Lead", "running", { waiting = true }),
		card("Other", "running"),
		card("Lead.Helper", "running"),
	}))
	t.eq(summary(subs), {
		"Lead|running@1 under nil",
		"Lead>Helper|running@2 under Lead",
		"Lead>Helper>Deep|running@3 under Lead>Helper",
		"Other|running@1 under nil",
	})
	t.eq(((subs :: any).agents[1]).waiting, true)
end)

t.test("statuses map to the sidebar's: queued is pending, stopped is aborted", function()
	local subs = subagents.fromTray(dock({
		card("A", "queued"),
		card("B", "stopped"),
		card("C", "failed"),
		card("D", "weird"),
	}))
	t.eq(summary(subs), {
		"A|pending@1 under nil",
		"B|aborted@1 under nil",
		"C|failed@1 under nil",
		"D|pending@1 under nil",
	})
end)

t.test("an agent revived after a done sibling shows as running", function()
	local subs = subagents.fromTray(dock({ card("Copy", "done"), card("Scan", "running") }))
	t.eq(summary(subs), { "Copy|done@1 under nil", "Scan|running@1 under nil" })
	t.eq(subagents.anyRunning(subs), true)
	local view = viewModel.build({
		agents = { { pane = 7, state = "idle", cwd = "/repo", title = "Lead" } },
		now = 0,
		focused = 7,
		subagents = { [7] = subs :: any },
	}).view
	t.eq(visible.agentRows(view), { ":terminal(Idle) Lead [▮]", "■(Running) Scan" })
end)

t.test("the main agent's helper cards and cards of other items are no subagents", function()
	local other = card("Job1", "running")
	other.p.item = "job"
	local subs = subagents.fromTray(dock({ card("Main/advisor", "running"), other, card("Real", "running") }))
	t.eq(summary(subs), { "Real|running@1 under nil" })
end)

t.test("a read without a tray gives no subagents; an empty tray gives none running", function()
	t.eq(subagents.fromTray({ surface = { id = "s" }, main = { id = "dock", k = "col", c = {} } }), nil)
	t.eq(subagents.fromTray(nil), nil)
	t.eq(subagents.fromTray("not a tree"), nil)
	local empty = subagents.fromTray(dock({}))
	t.eq(summary(empty), {})
	t.eq(subagents.anyRunning(empty), false)
	t.eq(subagents.anyRunning(nil), false)
end)

t.test("a tray under `dock` instead of `main` is read too", function()
	local tree = dock({ card("A", "running") })
	tree.dock, tree.main = tree.main, nil
	t.eq(summary(subagents.fromTray(tree)), { "A|running@1 under nil" })
end)

t.test("a queued subagent counts as running; finished ones do not", function()
	t.eq(subagents.anyRunning(subagents.fromTray(dock({ card("A", "queued") }))), true)
	t.eq(subagents.anyRunning(subagents.fromTray(dock({ card("A", "done"), card("B", "failed"), card("C", "stopped") }))), false)
end)

t.test("the type is the aria's second field unless that is a status word", function()
	local subs = subagents.fromTray(dock({
		card("A", "running", { aria = "A, reviewer, running, Reading" }),
		card("B", "running", { aria = "B, running, Reading" }),
		card("C", "running", { aria = "C, waiting" }),
		card("D", "running"),
	})) :: any
	local roles = {}
	for _, a in subs.agents do
		table.insert(roles, a.name .. "|" .. tostring(a.role))
	end
	t.eq(roles, { "A|reviewer", "B|nil", "C|nil", "D|nil" })
end)

t.test("the effort is the known level after the dot; any other model text is all model", function()
	local subs = subagents.fromTray(dock({
		card("A", "running", { model = "claude-opus-5-5 · xhigh" }),
		card("B", "running", { model = "gpt-5.1 · High" }),
		card("C", "running", { model = "gpt-5.1" }),
		card("D", "running", { model = "odd · banana" }),
	})) :: any
	local shown = {}
	for _, a in subs.agents do
		table.insert(shown, a.name .. "|" .. tostring(a.model) .. "|" .. tostring(a.effort))
	end
	t.eq(shown, { "A|claude-opus-5-5|xhigh", "B|gpt-5.1|high", "C|gpt-5.1|nil", "D|odd · banana|nil" })
end)

t.test("a read that the node budget cut is incomplete", function()
	local tree = dock({ card("A", "running") })
	tree.more = 2
	t.eq((subagents.fromTray(tree) :: any).incomplete, true)
	local inner = dock({ card("A", "running") })
	inner.main.c[1].more = 1
	t.eq((subagents.fromTray(inner) :: any).incomplete, true)
end)

t.test("a click finds its subagent by its omp id, and none once it is gone", function()
	local subs = subagents.fromTray(dock({ card("Lead", "running"), card("Lead.Fix", "running") }))
	t.eq((subagents.find(subs, "Lead.Fix") :: any).name, "Lead>Fix")
	t.eq(subagents.find(subs, "Gone"), nil)
	local view = viewModel.build({
		agents = { { pane = 7, state = "working", cwd = "/repo", title = "Lead", workingSince = 0 } },
		now = 0,
		focused = 7,
		subagents = { [7] = subs :: any },
	}).view
	t.eq(visible.click(view, "Fix"), "subagent=7 Lead.Fix")
end)

t.test("each subagent's time counts from when the reader saw its state begin", function()
	local function since(subs: any): { string }
		local out = {}
		for _, sub in subs.agents do
			table.insert(out, sub.name .. " " .. tostring(sub.since))
		end
		return out
	end
	local first = subagents.stamp(nil, subagents.fromTray(dock({ card("Old", "done"), card("Run", "running") })), 1000)
	t.eq(since(first), { "Old nil", "Run 1000" }, "a sub first seen finished has no time")
	local second = subagents.stamp(first, subagents.fromTray(dock({ card("Old", "done"), card("Run", "running") })), 2000)
	t.eq(since(second), { "Old nil", "Run 1000" }, "a sub in the same state keeps its time")
	local third = subagents.stamp(second, subagents.fromTray(dock({ card("Old", "done"), card("Run", "done") })), 3000)
	t.eq(since(third), { "Old nil", "Run 3000" }, "a sub that ended counts from its end")
	t.eq(subagents.stamp(third, nil, 4000), nil)
end)

t.test("each subagent keeps the time the reader first saw it while its id stays listed", function()
	local function seen(subs: any): { string }
		local out = {}
		for _, sub in subs.agents do
			table.insert(out, sub.name .. " " .. tostring(sub.firstSeen))
		end
		return out
	end
	local first = subagents.stamp(nil, subagents.fromTray(dock({ card("A", "running") })), 1000)
	t.eq(seen(first), { "A 1000" })
	local second = subagents.stamp(first, subagents.fromTray(dock({ card("B", "queued"), card("A", "done") })), 2000)
	t.eq(seen(second), { "B 2000", "A 1000" }, "a listed id keeps its time, a new one gets the clock")
	local third = subagents.stamp(second, subagents.fromTray(dock({ card("B", "running") })), 3000)
	t.eq(seen(third), { "B 2000" })
	local fourth = subagents.stamp(third, subagents.fromTray(dock({ card("A", "running"), card("B", "running") })), 4000)
	t.eq(seen(fourth), { "A 4000", "B 2000" }, "an id that left the tray starts again")
end)

return nil
