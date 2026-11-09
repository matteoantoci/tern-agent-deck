--!strict
-- While omp shows one of its subagents ("Viewing <name>" in the dock), its chat region holds that subagent's
-- transcript, so a read finds no running `task` call of the agent. The sidebar then keeps the agent's last subagent
-- rows and draws the shown subagent's row selected.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")
local viewing = require("../lib/viewing")

local function sub(name: string, depth: number?, extra: { [string]: any }?): { [string]: any }
	local s: { [string]: any } = { id = "dx." .. name, name = name, status = "running", depth = depth or 1, role = "task" }
	for k, v in (extra or {}) :: { [string]: any } do
		s[k] = v
	end
	return s
end

local LAST_READ: any = {
	agents = { sub("Ticket03"), sub("Ticket07"), sub("Merge0407>Ticket04", 2, { parent = "Ticket07" }) },
	incomplete = false,
}

-- A scoped read of the pane's dock (`root = "dock"`); `shown` is omp's lineage of the shown subagent, outermost
-- first, or nil while omp shows the main session.
local function dock(shown: { string }?): any
	local rows: { any } = {}
	if shown then
		local focus: { any } = { { id = "3.focus/label", k = "text", p = { text = "Viewing" } } }
		for i, id in shown do
			if i < #shown then
				table.insert(focus, { id = "3.focus/crumb:" .. id, k = "text", p = { text = id, actions = { click = "focus:" .. id } } })
			end
		end
		table.insert(focus, { id = "3.focus/agent", k = "text", p = { role = "omp.composer.agent", text = shown[#shown] } })
		table.insert(focus, {
			id = "3.focus/exit",
			k = "row",
			p = { title = "Back to the main session  esc", actions = { click = "focus:Main" } },
		})
		table.insert(rows, { id = "3.focus", k = "row", p = { role = "omp.composer.focus" }, c = focus })
	end
	table.insert(rows, { id = "3.line", k = "row", c = { { id = "3.line/input", k = "editor", p = { text = "" } } } })
	return { surface = { id = "s:1" }, main = { id = "dock", k = "col", c = rows } }
end

-- The sidebar after a read of pane 7 that found `read` (nil: no running `task` call) and a read of its dock.
local function after(read: any, dockRead: any, focused: number?): any
	local shown = viewing.agent(dockRead)
	local subs: { [number]: any } = {}
	subs[7] = viewing.keep(LAST_READ, read, shown)
	local views: { [number]: string } = {}
	if shown then
		views[7] = shown
	end
	return viewModel.build({
		agents = {
			{ pane = 7, state = "working", cwd = "/repo", title = "Lead", workingSince = 0 },
			{ pane = 9, state = "working", cwd = "/repo", title = "Other", workingSince = 0 },
		},
		now = 0,
		subagents = subs,
		viewing = views,
		focused = focused,
	}).view
end

t.test("while omp shows a subagent, its agent keeps the subagent rows and the shown one is selected", function()
	local out = after(nil, dock({ "Ticket07" }), 7)
	t.eq(visible.agentRows(out), {
		"●(Working) Lead …",
		"○(Not live) Ticket03 task",
		"●(Running) Ticket07 task …",
		"○(Not live) Merge0407>Ticket04 task · in Ticket07",
		"●(Working) Other …",
	})
	t.eq(visible.selected(out), { "●(Running) Ticket07 task …" })
	t.eq(visible.hover(out, "Ticket03"), "Ticket03 · Not live\nRole task\nNot updated while omp shows another subagent")
end)

t.test("a sibling that finished while omp showed another subagent shows as done once the view ends", function()
	local whileViewing = after(nil, dock({ "Ticket07" }), 7)
	t.eq(visible.agentRows(whileViewing)[2], "○(Not live) Ticket03 task")
	local read: any = {
		agents = { sub("Ticket03", 1, { status = "done" }), sub("Ticket07") },
		incomplete = false,
	}
	t.eq(visible.agentRows(after(read, dock(nil), 7)), {
		"●(Working) Lead …",
		"●(Running) Ticket07 task …",
		":check 1 subagent done",
		"●(Working) Other …",
	})
end)

t.test("once omp shows the main session again, the rows follow the reads and the agent's row is selected", function()
	local out = after(nil, dock(nil), 7)
	t.eq(visible.agentRows(out), { "●(Working) Lead …", "●(Working) Other …" })
	t.eq(visible.selected(out), { "●(Working) Lead …" })
	local read: any = { agents = { sub("Ticket03") }, incomplete = false }
	t.eq(visible.agentRows(after(read, dock(nil), 7)), { "●(Working) Lead …", "●(Running) Ticket03 task …", "●(Working) Other …" })
end)

t.test("a nested subagent omp shows is selected by its full id", function()
	t.eq(
		visible.selected(after(nil, dock({ "Merge0407", "Merge0407.Ticket04" }), 7)),
		{ "●(Running) Merge0407>Ticket04 task · in Ticket07 …" }
	)
end)

t.test("while another agent is focused, its row stays the selected one", function()
	local out = after(nil, dock({ "Ticket07" }), 9)
	t.eq(visible.selected(out), { "●(Working) Other …" })
	t.eq(#visible.agentRows(out), 5)
end)

t.test("a shown subagent the last read did not list leaves the agent's row selected", function()
	t.eq(visible.selected(after(nil, dock({ "Gone" }), 7)), { "●(Working) Lead …" })
end)

return nil
