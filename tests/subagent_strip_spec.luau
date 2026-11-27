--!strict
-- The subagent strip at the end of an agent's row (one bar per running subagent, or "N subagents" while some only wait
-- or are queued) and the subagent lines it shows or hides under the row. A finished subagent gets no line: only the
-- hover card counts it; a failed one always gets a line.
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
	t.eq(visible.agentRows(out), { ":terminal(Working) Lead [▮ ▮] 0s" })
	t.eq(visible.bars(out, "Lead"), { "running", "running" })
end)

t.test("the strip shows at most 8 bars, then +N", function()
	local subs: { any } = {}
	for i = 1, 11 do
		table.insert(subs, sub("S" .. i, "running"))
	end
	local out = view("working", subs)
	t.eq(visible.agentRows(out), { ":terminal(Working) Lead [▮ ▮ ▮ ▮ ▮ ▮ ▮ ▮ +3] 0s" })
	t.eq(#visible.bars(out, "Lead"), 8)
end)

t.test("an agent whose subagents all finished has no strip and no toggle; a failed one still shows its line", function()
	local done = view("idle", { sub("A", "done"), sub("B", "done"), sub("C", "aborted") })
	t.eq(visible.agentRows(done), { ":terminal(Idle) Lead" })
	t.eq(visible.button(done, "Lead"), nil)
	local failed = view("idle", { sub("A", "done"), sub("B", "failed"), sub("C", "aborted") }, { open = OPEN })
	t.eq(visible.agentRows(failed), { ":terminal(Idle) Lead", "■(Failed) B failed" })
	t.eq(visible.button(failed, "Lead"), nil)
	t.eq(string.find(visible.hover(done, "Lead") or "", "Subagents: 2 done · 1 stopped", 1, true) ~= nil, true)
end)

t.test("an agent with subagents that wait or are queued but none running shows N subagents in the strip's place", function()
	local queued = view("working", { sub("A", "pending"), sub("B", "running", 1, { waiting = true }), sub("C", "done") })
	t.eq(visible.agentRows(queued), { ":terminal(Working) Lead [2 subagents] 0s" })
	t.eq(visible.bars(queued, "Lead"), {})
	t.eq(visible.button(queued, "Lead"), "subs=7 open")
	t.eq(visible.agentRows(view("working", { sub("A", "pending") }))[1], ":terminal(Working) Lead [1 subagent] 0s")
end)

t.test("an agent with no subagents has no strip", function()
	t.eq(visible.agentRows(view("working", {})), { ":terminal(Working) Lead 0s" })
	t.eq(visible.button(view("working", {}), "Lead"), nil)
	t.eq(visible.agentRows(viewModel.build({
		agents = { { pane = 7, state = "working", cwd = "/repo", title = "Lead", workingSince = 0 } },
		now = 0,
		subagents = {},
	}).view), { ":terminal(Working) Lead 0s" })
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

t.test("a click on the strip shows the closed lines, and a click on open lines hides them; done ones get no line", function()
	local closed = view("working", { sub("A", "running"), sub("B", "done") })
	t.eq(visible.agentRows(closed), { ":terminal(Working) Lead [▮] 0s" })
	t.eq(visible.button(closed, "Lead"), "subs=7 open")
	local open = view("working", { sub("A", "running"), sub("B", "done"), sub("C", "aborted") }, { open = OPEN })
	t.eq(visible.agentRows(open), { ":terminal(Working) Lead [▮] 0s", "■(Running) A" })
	t.eq(visible.button(open, "Lead"), "subs=7 closed")
end)

t.test("this tab's agent shows its subagent lines open until the user closes them", function()
	local subs = { sub("A", "running") }
	t.eq(visible.agentRows(view("working", subs, { focused = 7 })), { ":terminal(Working) Lead [▮] 0s", "■(Running) A" })
	t.eq(visible.button(view("working", subs, { focused = 7 }), "Lead"), "subs=7 closed")
	t.eq(visible.agentRows(view("working", subs, { focused = 7, open = { [7] = false } })), { ":terminal(Working) Lead [▮] 0s" })
end)

t.test("this tab's agent shows its lines closed while only queued subagents wait, unless the user opened them", function()
	local subs = { sub("A", "done"), sub("B", "pending"), sub("C", "failed") }
	t.eq(visible.agentRows(view("idle", subs, { focused = 7 })), { ":terminal(Idle) Lead [1 subagent]", "■(Failed) C failed" })
	t.eq(visible.button(view("idle", subs, { focused = 7 }), "Lead"), "subs=7 open")
	t.eq(visible.agentRows(view("idle", subs, { focused = 7, open = OPEN })), {
		":terminal(Idle) Lead [1 subagent]",
		"■(Queued) B",
		"■(Failed) C failed",
	})
	local waiting = { sub("A", "done"), sub("B", "running", 1, { waiting = true }) }
	t.eq(visible.button(view("working", waiting, { focused = 7 }), "Lead"), "subs=7 closed")
end)

-- The zone head and the project label above Lead's row, as `visible.tree` shows them.
local HEAD = { "■ Working 1 busy", "repo [:plus](New tab in this folder)" }

t.test("a failed subagent shows as its own line while the lines are closed, one step under its agent", function()
	local subs = {
		sub("A", "running"),
		sub("A>B", "failed", 2, { parent = "A" }),
		sub("C", "done"),
	}
	t.eq(visible.tree(view("working", subs)), { HEAD[1], HEAD[2], ":terminal(Working) Lead [▮] 0s", "  ■(Failed) B failed" })
	t.eq(visible.tree(view("working", subs, { open = OPEN })), {
		HEAD[1],
		HEAD[2],
		":terminal(Working) Lead [▮] 0s",
		"  ■(Running) A",
		"    ■(Failed) B failed",
	})
end)

t.test("a subagent line shows its mark, its name, what it does now with a long path cut to its file name, and its time", function()
	local out = view("working", {
		sub("Ticket07", "running", 1, { intent = "read /Users/me/repo/lib/view_model.luau", since = -12000 }),
		sub("Edit", "running", 1, { intent = "edit lib/x.luau", since = -4 * 60000 }),
		sub("Probe", "running", 1, { role = "scout" }),
		sub("Copy", "failed", 1, { since = -3 * 3600000 }),
	}, { open = OPEN })
	t.eq(visible.agentRows(out), {
		":terminal(Working) Lead [▮ ▮ ▮] 0s",
		"■(Running) Ticket07 read …/view_model.luau 12s",
		"■(Running) Edit edit lib/x.luau 4m",
		"■(Running) Probe scout",
		"■(Failed) Copy failed 3h",
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
		"working: :terminal(Working) Lead [▮] 0s",
		"running: ■(Running) A",
		"waiting: ■(Waiting on its subagents) B",
		"idle: ■(Queued) C",
		"failed: ■(Failed) E failed",
	})
end)

t.test("open lines indent one step per level down to omp's limit; a deeper level folds into one +N deeper line", function()
	local subs: { any } = {}
	for depth = 1, 11 do
		table.insert(subs, sub("L" .. depth, "running", depth, { parent = if depth > 1 then "L" .. (depth - 1) else nil }))
	end
	local tree = visible.tree(view("working", subs, { open = OPEN }))
	t.eq(#tree, #HEAD + 1 + 9 + 1)
	t.eq(tree[4], "  ■(Running) L1")
	t.eq(tree[5], "    ■(Running) L2")
	t.eq(tree[12], string.rep("  ", 9) .. "■(Running) L9")
	t.eq(tree[13], "  :more +2 deeper")
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

t.test("a subagent line's hover card shows what it does, its role, parent, model and effort", function()
	local out = view("working", {
		sub("Ticket07", "running", 1, { intent = "Running probe", model = "claude-opus-5-5", role = "scout", effort = "high" }),
		sub("Ticket07>Fix", "failed", 2, { parent = "Ticket07" }),
	}, { open = OPEN })
	t.eq(
		visible.hover(out, "Ticket07"),
		"■ Running\nTicket07\nRunning probe\nscout · claude-opus-5-5 high\nClick: show it in omp"
	)
	t.eq(visible.hover(out, "Fix"), "■ Failed\nFix\nunder Ticket07\nClick: show it in omp")
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
	local hint = "Click: show it in omp · Right-click: Copy session ID or path"
	t.eq(visible.hover(out, "(Running) Lead"), "■ Running\nLead\nanthropic/claude-opus-5-5\n" .. hint)
	t.eq(visible.hover(out, "(Running) Fix"), "■ Running\nFix\nunder Lead · gpt-5.1\n" .. hint)
end)

t.test("open lines from a read that Tern cut say that the subagents may be incomplete", function()
	t.eq(visible.agentRows(view("working", { sub("B", "running") }, { open = OPEN, incomplete = true })), {
		":terminal(Working) Lead [▮] 0s",
		"■(Running) B",
		":warn subagents may be incomplete",
	})
end)

t.test("an idle agent whose background subagents still run shows its bars", function()
	t.eq(visible.agentRows(view("idle", { sub("A", "done"), sub("B", "running") })), { ":terminal(Idle) Lead [▮]" })
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
		":terminal(Working) Lead [▮] 0s",
		"■(Running) Ticket07",
		"■ Idle 2 idle",
		"beta [:plus](New tab in this repo)",
		":terminal(Idle) Docs",
		"tmp [:plus](New tab in this folder)",
		":terminal(Idle) Notes",
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

t.test("open lines show at most 20 subagents: the failed ones, then the newest of the others, then +N more", function()
	-- A canvas update holds at most 2000 nodes and 256 KiB. Done subagents get no line, so they take none of the 20.
	local subs: { any } = { sub("Run", "running", 1, { since = 300 }), sub("Bad", "failed", 1, { since = 2 }) }
	for i = 1, 150 do
		local intent = "Read /Users/me/Personal/tern-agent-deck/lib/view_model.luau and report what the code does " .. i
		table.insert(subs, sub("Queued" .. i, "pending", 1, { since = 10 + i, role = "task", model = "claude-opus-5-5", intent = intent }))
		table.insert(subs, sub("Done" .. i, "done", 1, { since = 400 + i }))
	end
	local shown = view("idle", subs, { focused = 7, now = 600 })
	local rows = visible.agentRows(shown)
	t.eq(#rows, 1 + 20 + 1)
	t.eq(string.find(rows[2], "Run", 1, true) ~= nil, true)
	t.eq(string.find(rows[3], "Bad", 1, true) ~= nil, true)
	t.eq(string.find(rows[4], "Queued133", 1, true) ~= nil, true)
	t.eq(string.find(rows[21], "Queued150", 1, true) ~= nil, true)
	t.eq(rows[22], ":more +132 more")
	local nodes, bytes = visible.size(shown)
	t.eq(nodes < 2000, true)
	t.eq(bytes < 256 * 1024, true)
end)

return nil
