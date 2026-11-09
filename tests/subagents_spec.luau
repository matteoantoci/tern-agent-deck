--!strict
local t = require("./harness")
local subagents = require("../lib/subagents")
local viewModel = require("../lib/view_model")
local visible = require("./visible")

-- Fixture trees shaped like the live `cx.session:surface()` reads (2026-11-09): `task` tool nodes are children of
-- `main`; each holds a context text and one `agent` node per subagent; an agent node holds its assignment and, when
-- it runs a `task` call of its own, the nested agent nodes.
local function agent(id: string, status: string, extra: { [string]: any }?, children: { any }?): any
	local p: { [string]: any } = { name = id, status = status }
	for k, v in (extra or {}) :: { [string]: any } do
		p[k] = v
	end
	local c: { any } = { { id = id .. ".a", k = "md", p = { text = "assignment" } } }
	for _, child in (children or {}) :: { any } do
		table.insert(c, child)
	end
	return { id = "dx." .. id, k = "agent", p = p, c = c }
end

local function task(id: string, status: string, agents: { any }): any
	local c: { any } = { { id = id .. ".ctx", k = "text", p = { text = "context" } } }
	for _, a in agents do
		table.insert(c, a)
	end
	return { id = id, k = "tool", p = { name = "task", status = status }, c = c }
end

local function chat(children: { any }): any
	return { surface = { id = "s", mode = "flow" }, main = { id = "m", k = "col", c = children } }
end

t.test("every running task call is found among finished ones and other tools, in tree order", function()
	local tree = chat({
		task("5h", "done", {}),
		task("ab", "running", {}),
		{ id = "b1", k = "tool", p = { name = "bash", status = "running" } },
		task("dx", "running", {}),
	})
	t.eq(subagents.runningTasks(tree), { "ab", "dx" })
end)

t.test("a chat without a running task call has no task to read", function()
	t.eq(subagents.runningTasks(chat({ task("5h", "done", {}) })), {})
	t.eq(subagents.runningTasks("not a tree"), {})
end)

-- A read with `root` set to the task node: `main` is that node, and Tern leaves out the top-level `more`.
local function scoped(node: any): any
	return { surface = { id = "s", mode = "flow" }, main = node }
end

t.test("a tool node whose props are null does not hide the running task calls beside it", function()
	local tree = chat({ { id = "n", k = "tool", p = newproxy() }, task("dx", "running", {}) })
	t.eq(subagents.runningTasks(tree), { "dx" })
end)

t.test("a scoped read shows each running subagent with its model, current tool and intent, and the done ones folded", function()
	local null = newproxy()
	local tree = scoped(task("dx", "running", {
		agent("Ticket03", "running", { model = "anthropic/claude-opus-5-5", tool = null }),
		agent("Ticket07", "running", {
			model = "openai/gpt-5.1",
			tool = { name = "bash", intent = { { t = "Running " }, { t = "probe", s = "accent" } }, age = 300 },
		}),
		agent("Scout", "done", { tool = { name = "read", intent = "Reading spec" } }),
	}))
	local view = viewModel.build({
		agents = { { pane = 7, state = "working", cwd = "/repo", title = "Lead", workingSince = 0 } },
		now = 0,
		subagents = { [7] = subagents.extract(tree) :: any },
	}).view
	t.eq(visible.agentRows(view), {
		"●(Working) Lead …",
		"●(Running) Ticket03 …",
		"●(Running) Ticket07 …",
		":check 1 subagent done",
	})
	t.eq(visible.hover(view, "Ticket03"), "Ticket03 · Running\nModel claude-opus-5-5")
	t.eq(visible.hover(view, "Ticket07"), "Ticket07 · Running\nModel gpt-5.1\nTool bash\nIntent Running probe")
end)

t.test("a subagent's type and thinking level come from its agent and thinking props", function()
	local tree = scoped(task("dx", "running", {
		agent("Scout", "running", { agent = "scout", thinking = "thinkingHigh" }),
		agent("Max", "running", { agent = "task", thinking = "thinkingXhigh" }),
		agent("Plain", "running", { thinking = "low" }),
		agent("Odd", "running", { agent = "", thinking = "accent" }),
	}))
	local shown = {}
	for _, a in (subagents.extract(tree) :: any).agents do
		table.insert(shown, a.name .. "|" .. tostring(a.role) .. "|" .. tostring(a.effort))
	end
	t.eq(shown, { "Scout|scout|high", "Max|task|xhigh", "Plain|nil|low", "Odd|nil|nil" })
end)

t.test("a click finds its subagent by the node id its row names, and none once the node is gone", function()
	local subs = subagents.extract(scoped(task("dx", "running", { agent("Ticket07", "running") }))) :: any
	t.eq((subagents.find(subs, "dx.Ticket07") :: any).name, "Ticket07")
	t.eq(subagents.find(subs, "dx.Gone"), nil)
end)

t.test("the subagents of all running task calls of an agent show together, in tree order", function()
	local first = subagents.extract(scoped(task("ab", "running", { agent("MergeIntoInteg", "running") })))
	local cut = task("dx", "running", { agent("Ticket06", "running"), agent("Ticket05", "done") })
	cut.more = 1
	local second = subagents.extract(scoped(cut))
	local merged = subagents.merge({ first :: any, second :: any })
	local names = {}
	for _, a in (merged :: any).agents do
		table.insert(names, a.name .. "|" .. a.status)
	end
	t.eq(names, { "MergeIntoInteg|running", "Ticket06|running", "Ticket05|done" })
	t.eq((merged :: any).incomplete, true)
	t.eq(subagents.merge({}), nil, "no running task call")
end)

t.test("a subagent's own subagents sit one level deeper, in tree order", function()
	local tree = scoped(task("dx", "running", {
		agent("Lead", "running", nil, {
			agent("Helper", "running", { depth = 1 }, { agent("Deep", "running", { depth = 2 }) }),
		}),
		agent("Other", "running"),
	}))
	local shown = {}
	for _, a in (subagents.extract(tree) :: any).agents do
		table.insert(shown, a.name .. "@" .. a.depth .. " under " .. tostring(a.parent))
	end
	t.eq(shown, { "Lead@1 under nil", "Helper@2 under Lead", "Deep@3 under Helper", "Other@1 under nil" })
end)

t.test("subagents at every level show in one flat list under their agent, each naming the agent it runs under", function()
	-- Three levels as omp sends them: a nested agent node is a direct child of its parent's agent node, beside the
	-- assignment, with `p.depth` counting from 0 at the first level.
	local tree = scoped(task("dx", "running", {
		agent("Merge0407", "running", { agent = "task" }, {
			agent("Ticket04", "running", { agent = "task", depth = 1 }, {
				agent("Probe", "running", { agent = "scout", depth = 2 }),
				agent("Lint", "done", { depth = 2 }),
			}),
		}),
		agent("Docs", "running", { agent = "task" }),
	}))
	local view = viewModel.build({
		agents = { { pane = 7, state = "working", cwd = "/repo", title = "Lead", workingSince = 0 } },
		now = 0,
		subagents = { [7] = subagents.extract(tree) :: any },
	}).view
	t.eq(visible.agentRows(view), {
		"●(Working) Lead …",
		"●(Running) Merge0407 task …",
		"●(Running) Ticket04 task · in Merge0407 …",
		"●(Running) Probe scout · in Ticket04 …",
		"●(Running) Docs task …",
		":check 1 subagent done",
	})
	t.eq(visible.hover(view, "Probe"), "Probe · Running\nRole scout\nUnder Ticket04")
end)

t.test("a read that the node budget cut is incomplete", function()
	local cut = task("dx", "running", { agent("Lead", "running") })
	cut.more = 2
	t.eq((subagents.extract(scoped(cut)) :: any).incomplete, true)
	local whole = scoped(task("dx", "running", { agent("Lead", "running") }))
	whole.more = 5
	t.eq((subagents.extract(whole) :: any).incomplete, true)
	t.eq((subagents.extract(scoped(task("dx", "running", {}))) :: any).incomplete, false)
end)

t.test("a scoped read whose task call has ended gives no subagents", function()
	t.eq(subagents.extract(scoped(task("dx", "done", { agent("Lead", "done") }))), nil)
	t.eq(subagents.extract(scoped({ id = "dx", k = "text", p = { text = "reused id" } })), nil)
	t.eq(subagents.extract(nil), nil)
end)

return nil
