--!strict
-- The subagent strip at the end of an agent's row (one bar per running subagent, or "N done") and the subagent lines
-- it shows or hides under the row.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local function sub(name: string, status: string, depth: number?, extra: { [string]: any }?): { [string]: any }
	local s: { [string]: any } = { id = (string.gsub(name, ">", ".")), name = name, status = status, depth = depth or 1 }
	for k, v in (extra or {}) :: { [string]: any } do
		s[k] = v
	end
	return s
end

type Opts = { focused: number?, open: { [number]: boolean }?, incomplete: boolean?, now: number?, file: string? }

-- The sidebar with one agent, Lead in pane 7, in `state`, whose subagents are `subs`.
local function view(state: string, subs: { any }, opts: Opts?): any
	local o: Opts = opts or {}
	return viewModel.build({
		agents = { { pane = 7, state = state, cwd = "/repo", title = "Lead", workingSince = 0, sessionFile = o.file } :: any },
		now = o.now or 0,
		focused = o.focused,
		subsOpen = o.open,
		subagents = { [7] = { agents = subs, incomplete = o.incomplete == true } :: any },
	}).view
end

local OPEN = { [7] = true }

t.test("the strip shows one bar per running subagent at every level; waiting, queued and finished ones get none", function()
	local out = view("working", {
		sub("A", "running"),
		sub("A>B", "running", 2, { parent = "A" }),
		sub("C", "done"),
		sub("D", "aborted"),
		sub("E", "running", 1, { waiting = true }),
		sub("F", "pending"),
	})
	t.eq(visible.agentRows(out), { ":bot(Working) Lead [▮ ▮] 0s" })
	t.eq(visible.bars(out, "Lead"), { "running", "running" })
end)

t.test("the strip shows at most 8 bars, then +N", function()
	local subs: { any } = {}
	for i = 1, 11 do
		table.insert(subs, sub("S" .. i, "running"))
	end
	local out = view("working", subs)
	t.eq(visible.agentRows(out), { ":bot(Working) Lead [▮ ▮ ▮ ▮ ▮ ▮ ▮ ▮ +3] 0s" })
	t.eq(#visible.bars(out, "Lead"), 8)
end)

t.test("an agent with subagents but none running shows N done in the strip's place", function()
	local out = view("idle", { sub("A", "done"), sub("B", "done"), sub("C", "aborted") })
	t.eq(visible.agentRows(out), { ":bot(Idle) Lead [2 done]" })
	t.eq(visible.bars(out, "Lead"), {})
end)

t.test("an agent with no subagents has no strip", function()
	t.eq(visible.agentRows(view("working", {})), { ":bot(Working) Lead 0s" })
	t.eq(visible.button(view("working", {}), "Lead"), nil)
	t.eq(visible.agentRows(viewModel.build({
		agents = { { pane = 7, state = "working", cwd = "/repo", title = "Lead", workingSince = 0 } },
		now = 0,
		subagents = {},
	}).view), { ":bot(Working) Lead 0s" })
end)

t.test("the strip's tooltip lists every count and what a click does", function()
	local subs = {
		sub("A", "running"),
		sub("B", "running"),
		sub("C", "running"),
		sub("D", "running", 1, { waiting = true }),
		sub("E", "done"),
		sub("F", "failed"),
	}
	t.eq(visible.titles(view("working", subs), "Lead"), { "3 running · 1 waiting · 1 done · 1 failed. Click: show them" })
	t.eq(visible.titles(view("working", subs, { open = OPEN }), "Lead"), {
		"3 running · 1 waiting · 1 done · 1 failed. Click: hide them",
	})
	t.eq(visible.titles(view("idle", { sub("A", "pending"), sub("B", "done"), sub("C", "aborted") }), "Lead"), {
		"1 queued · 1 done · 1 stopped. Click: show them",
	})
end)

t.test("a click on the strip or on N done shows the closed lines, and a click on open lines hides them", function()
	local closed = view("working", { sub("A", "running"), sub("B", "done") })
	t.eq(visible.agentRows(closed), { ":bot(Working) Lead [▮] 0s" })
	t.eq(visible.button(closed, "Lead"), "subs=7 open")
	local open = view("working", { sub("A", "running"), sub("B", "done") }, { open = OPEN })
	t.eq(visible.agentRows(open), { ":bot(Working) Lead [▮] 0s", "■(Running) A", "■(Done) B" })
	t.eq(visible.button(open, "Lead"), "subs=7 closed")
	t.eq(visible.button(view("idle", { sub("B", "done") }), "Lead"), "subs=7 open")
end)

t.test("this tab's agent shows its subagent lines open until the user closes them", function()
	local subs = { sub("A", "running") }
	t.eq(visible.agentRows(view("working", subs, { focused = 7 })), { ":bot(Working) Lead [▮] 0s", "■(Running) A" })
	t.eq(visible.button(view("working", subs, { focused = 7 }), "Lead"), "subs=7 closed")
	t.eq(visible.agentRows(view("working", subs, { focused = 7, open = { [7] = false } })), { ":bot(Working) Lead [▮] 0s" })
end)

t.test("a failed subagent shows as its own line while the lines are closed, one step under its agent", function()
	local subs = {
		sub("A", "running"),
		sub("A>B", "failed", 2, { parent = "A" }),
		sub("C", "done"),
	}
	t.eq(visible.tree(view("working", subs)), { ":bot(Working) Lead [▮] 0s", "  ■(Failed) B failed" })
	t.eq(visible.tree(view("working", subs, { open = OPEN })), {
		":bot(Working) Lead [▮] 0s",
		"  ■(Running) A",
		"    ■(Failed) B failed",
		"  ■(Done) C",
	})
end)

t.test("a subagent line shows its mark, its name, what it does now with a long path cut to its file name, and its time", function()
	local out = view("working", {
		sub("Ticket07", "running", 1, { intent = "read /Users/me/repo/lib/view_model.luau", since = -12000 }),
		sub("Edit", "running", 1, { intent = "edit lib/x.luau", since = -4 * 60000 }),
		sub("Probe", "running", 1, { role = "scout" }),
		sub("Copy", "done", 1, { since = -3 * 3600000 }),
	}, { open = OPEN })
	t.eq(visible.agentRows(out), {
		":bot(Working) Lead [▮ ▮ ▮] 0s",
		"■(Running) Ticket07 read …/view_model.luau 12s",
		"■(Running) Edit edit lib/x.luau 4m",
		"■(Running) Probe scout",
		"■(Done) Copy 3h",
	})
	t.eq(visible.secondary(out, "read …/view_model.luau"), true)
	t.eq(visible.face(out, "Ticket07"), "sans")
end)

t.test("each subagent line's square carries its state", function()
	t.eq(visible.states(view("working", {
		sub("A", "running"),
		sub("B", "running", 1, { waiting = true }),
		sub("C", "pending"),
		sub("D", "done"),
		sub("E", "failed"),
		sub("F", "aborted"),
	}, { open = OPEN })), {
		"working: ■ Working 1 busy",
		"working: :bot(Working) Lead [▮] 0s",
		"running: ■(Running) A",
		"waiting: ■(Waiting on its subagents) B",
		"idle: ■(Queued) C",
		"done: ■(Done) D",
		"failed: ■(Failed) E failed",
		"stopped: ■(Stopped) F",
	})
end)

t.test("open lines indent one step per level down to omp's limit; a deeper level folds into one +N deeper line", function()
	local subs: { any } = {}
	for depth = 1, 11 do
		table.insert(subs, sub("L" .. depth, "running", depth, { parent = if depth > 1 then "L" .. (depth - 1) else nil }))
	end
	local tree = visible.tree(view("working", subs, { open = OPEN }))
	t.eq(#tree, 1 + 9 + 1)
	t.eq(tree[2], "  ■(Running) L1")
	t.eq(tree[3], "    ■(Running) L2")
	t.eq(tree[10], string.rep("  ", 9) .. "■(Running) L9")
	t.eq(tree[11], "  :more +2 deeper")
end)

t.test("a click on a subagent line asks to show that subagent in omp's view, at every level", function()
	local out = view("working", { sub("Ticket07", "running"), sub("Top>Mid>Deep", "running", 3, { parent = "Top>Mid" }) }, {
		open = OPEN,
	})
	t.eq(visible.click(out, "Ticket07"), "subagent=7 Ticket07")
	t.eq(visible.click(out, "Deep"), "subagent=7 Top.Mid.Deep")
	local closed = view("working", { sub("Gone", "failed") })
	t.eq(visible.click(closed, "Gone"), "subagent=7 Gone")
end)

t.test("a subagent line's hover card shows its role, parent, model, effort and what it does", function()
	local out = view("working", {
		sub("Ticket07", "running", 1, { intent = "Running probe", model = "claude-opus-5-5", role = "scout", effort = "high" }),
		sub("Ticket07>Fix", "done", 2, { parent = "Ticket07" }),
	}, { open = OPEN })
	t.eq(
		visible.hover(out, "Ticket07"),
		"Ticket07 · Running\nRole scout\nModel claude-opus-5-5\nEffort high\nDoing Running probe"
	)
	t.eq(visible.hover(out, "Fix"), "Fix · Done\nUnder Ticket07")
	t.eq(visible.titles(out, "Ticket07"), {})
end)

t.test("a subagent's model comes from its session file's route when known, else from the tray's model id", function()
	local out = viewModel.build({
		agents = { { pane = 7, state = "working", cwd = "/repo", title = "Lead", workingSince = 0, sessionFile = "/s/main.jsonl" } },
		now = 0,
		focused = 7,
		subagents = {
			[7] = {
				agents = {
					{ id = "Lead", name = "Lead", status = "running", depth = 1, model = "claude-opus-5-5" },
					{ id = "Lead.Fix", name = "Lead>Fix", status = "running", depth = 2, parent = "Lead", model = "gpt-5.1" },
				},
				incomplete = false,
			},
		},
		routes = { ["/s/main/Lead.jsonl"] = "anthropic/claude-opus-5-5" },
	}).view
	t.eq(visible.hover(out, "(Running) Lead"), "Lead · Running\nModel anthropic/claude-opus-5-5")
	t.eq(visible.hover(out, "(Running) Fix"), "Fix · Running\nUnder Lead\nModel gpt-5.1")
end)

t.test("open lines from a read that Tern cut say that the subagents may be incomplete", function()
	t.eq(visible.agentRows(view("working", { sub("B", "running") }, { open = OPEN, incomplete = true })), {
		":bot(Working) Lead [▮] 0s",
		"■(Running) B",
		":warn subagents may be incomplete",
	})
end)

t.test("an idle agent whose background subagents still run shows its bars", function()
	t.eq(visible.agentRows(view("idle", { sub("A", "done"), sub("B", "running") })), { ":bot(Idle) Lead [▮]" })
end)

t.test("a working agent in a project shows its open subagent lines inside that project, under its row", function()
	local out = viewModel.build({
		agents = {
			{ pane = 3, state = "idle", title = "Notes", cwd = "/tmp" },
			{ pane = 7, state = "working", title = "Lead", repo = "/Users/me/alpha", workingSince = 0 },
			{ pane = 9, state = "idle", title = "Docs", repo = "/Users/me/beta" },
		},
		now = 0,
		home = "/Users/me",
		focused = 7,
		subagents = { [7] = { agents = { sub("Ticket07", "running", 1), sub("A", "done") }, incomplete = false } :: any },
	}).view
	t.eq(visible.rows(out), {
		"■ Working 1 busy",
		"alpha [:plus](New tab in this repo)",
		":bot(Working) Lead [▮] 0s",
		"■(Running) Ticket07",
		"■(Done) A",
		"■ Idle 2",
		"beta [:plus](New tab in this repo)",
		":bot(Idle) Docs",
		"tmp [:plus](New tab in this folder)",
		":bot(Idle) Notes",
	})
	t.eq(visible.click(out, "Ticket07"), "subagent=7 Ticket07")
end)

t.test("a shown subagent line's time changes on its own, so the sidebar redraws when it does", function()
	t.eq(viewModel.redrawDue({
		agents = { { pane = 7, state = "idle", cwd = "/repo", title = "Lead" } },
		now = 0,
		subagents = { [7] = { agents = { sub("A", "running", 1, { since = -1500 }) }, incomplete = false } :: any },
	}), 500)
end)

return nil
