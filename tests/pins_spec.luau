--!strict
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local REPO = "/Users/me/Personal/tern-agents"

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

local function view(input: { [string]: any }): any
	local full: { [string]: any } = { agents = {}, now = 0, home = HOME }
	for k, v in input do
		full[k] = v
	end
	return viewModel.build(full :: any).view
end

t.test("a pinned agent shows in Pinned at the top and not in its repo section", function()
	t.eq(visible.rows(view({
		agents = {
			agent({ pane = 1, title = "plan" }),
			agent({ pane = 2, title = "build" }),
		},
		pins = { { pane = 2, cwd = REPO, title = "build" } },
	})), {
		":pin Pinned 1",
		"●(Idle) build",
		":chev :mi-folder-open tern-agents 1 [:plus](New tab in this repo)",
		"●(Idle) plan",
	})
end)

t.test("Pinned lists the pinned agents in the order they were pinned", function()
	t.eq(visible.rows(view({
		agents = { agent({ pane = 1, title = "plan" }), agent({ pane = 2, title = "build" }) },
		pins = { { pane = 2, cwd = REPO, title = "build" }, { pane = 1, cwd = REPO, title = "plan" } },
	})), { ":pin Pinned 2", "●(Idle) build", "●(Idle) plan" })
end)

t.test("a pinned working agent keeps its subagent rows in Pinned", function()
	t.eq(visible.rows(view({
		agents = { agent({ pane = 7, title = "Lead", state = "working", workingSince = 0 }) },
		pins = { { pane = 7, cwd = REPO, title = "Lead" } },
		subagents = { [7] = { agents = { { id = "dx.A", name = "A", status = "running", depth = 1 } }, incomplete = false } },
	})), { ":pin Pinned 1", "●(Working) Lead …", "●(Running) A …" })
end)

t.test("when the pane id changed, a pin finds its agent by working directory and title", function()
	local agents = {
		agent({ pane = 40, title = "plan" }),
		agent({ pane = 41, title = "build" }),
	}
	local pins = { { pane = 2, cwd = REPO, title = "build" } }
	t.eq(visible.rows(view({ agents = agents, pins = pins })), {
		":pin Pinned 1",
		"●(Idle) build",
		":chev :mi-folder-open tern-agents 1 [:plus](New tab in this repo)",
		"●(Idle) plan",
	})
	t.eq(viewModel.resolvePins(agents :: any, pins), { { pane = 41, cwd = REPO, title = "build" } })
end)

t.test("a pin keeps the title its agent shows now, so that the backup key stays current", function()
	local agents = { agent({ pane = 2, title = "build v2" }) }
	t.eq(viewModel.resolvePins(agents :: any, { { pane = 2, cwd = REPO, title = "build" } }), {
		{ pane = 2, cwd = REPO, title = "build v2" },
	})
end)

t.test("a pin ignores another agent that got its old pane id in another folder", function()
	local agents = { agent({ pane = 2, title = "other work", cwd = "/tmp" }) }
	local pins = { { pane = 2, cwd = REPO, title = "build" } }
	local v = view({ agents = agents, pins = pins })
	t.eq(visible.rows(v), { ":pin Pinned 1", "○(Exited) build", ":chev :mi-folder-open tmp 1 [:plus](New tab in this folder)", "●(Idle) other work" })
	t.eq(visible.click(v, "build"), "gone=1", "a click on the gone agent does not focus the other one")
	t.eq(visible.menu(v, "build"), { "Unpin → forget=1" })
	t.eq(visible.menu(v, "other work")[1], "Pin → pin=2")
	t.eq(viewModel.pinOf(agents :: any, pins, 2), nil, "Pin this agent pins the other agent")
end)

t.test("Pin this agent finds the pin of an agent whose pane id changed", function()
	local agents = { agent({ pane = 41, title = "build" }) }
	t.eq(viewModel.pinOf(agents :: any, { { pane = 2, cwd = REPO, title = "build" } }, 41), 1)
end)

t.test("a pinned agent that exited stays in Pinned, dimmed", function()
	local v = view({
		agents = { agent({ pane = 2, title = "build", state = "exited" }) },
		pins = { { pane = 2, cwd = REPO, title = "build" } },
	})
	t.eq(visible.rows(v), { ":pin Pinned 1", "○(Exited) build" })
	t.eq(visible.dimmed(v, "build"), true)
end)

t.test("a pinned agent whose pane is gone stays in Pinned, dimmed, under its last title", function()
	local v = view({ agents = {}, pins = { { pane = 2, cwd = REPO, title = "\u{F0E7} build" } } })
	t.eq(visible.rows(v), { ":pin Pinned 1", "○(Exited) build" })
	t.eq(visible.dimmed(v, "build"), true)
	t.eq(visible.menu(v, "build"), { "Unpin → forget=1" })
	t.eq(visible.click(v, "build"), "gone=1")
end)

t.test("live agents are not dimmed", function()
	local v = view({ agents = { agent({ pane = 2, title = "build" }) }, pins = { { pane = 2, cwd = REPO } } })
	t.eq(visible.dimmed(v, "build"), false)
end)

t.test("an exited agent that is not pinned leaves the list", function()
	t.eq(visible.rows(view({
		agents = { agent({ pane = 1, title = "plan" }), agent({ pane = 2, title = "build", state = "exited" }) },
	})), { ":chev :mi-folder-open tern-agents 1 [:plus](New tab in this repo)", "●(Idle) plan" })
	t.eq(visible.lines(view({ agents = { agent({ state = "exited" }) } }))[1], "No agents running\nStart one here, or run omp in any pane")
end)

t.test("the right-click menu offers Pin and Interrupt, and Interrupt only while the agent is in a turn", function()
	local v = view({
		agents = {
			agent({ pane = 1, title = "plan" }),
			agent({ pane = 2, title = "build", state = "working" }),
			agent({ pane = 3, title = "ask", state = "waiting_input" }),
		},
	})
	local menu = visible.menu(v, "plan")
	t.eq({ menu[1], menu[#menu] }, {
		"Pin → pin=1",
		"Interrupt → interrupt=1 (off: The agent is not in a turn)",
	})
	menu = visible.menu(v, "build")
	t.eq({ menu[1], menu[#menu] }, { "Pin → pin=2", "Interrupt → interrupt=2" })
	menu = visible.menu(v, "ask")
	t.eq({ menu[1], menu[#menu] }, { "Pin → pin=3", "Interrupt → interrupt=3" })
end)

t.test("the right-click menu of a pinned agent offers Unpin", function()
	local v = view({
		agents = { agent({ pane = 2, title = "build", state = "working" }) },
		pins = { { pane = 2, cwd = REPO, title = "build" } },
	})
	local menu = visible.menu(v, "build")
	t.eq({ menu[1], menu[#menu] }, { "Unpin → unpin=2", "Interrupt → interrupt=2" })
end)

t.test("with a pin, agents outside any repo keep their folder's section", function()
	t.eq(visible.rows(view({
		agents = { agent({ pane = 1, title = "a", cwd = "/tmp" }), agent({ pane = 2, title = "b", cwd = "/tmp" }) },
		pins = { { pane = 1, cwd = "/tmp", title = "a" } },
	})), { ":pin Pinned 1", "●(Idle) a", ":chev :mi-folder-open tmp 1 [:plus](New tab in this folder)", "●(Idle) b" })
end)

return nil
