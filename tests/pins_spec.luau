--!strict
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local REPO = "/Users/me/Personal/tern-agents"
local SESSION = "/Users/me/.omp/agent/sessions/-Personal-tern-agents/2026-11-01T08-00-00-000Z_1.jsonl"
local LABEL = "tern-agents [:plus](New tab in this repo)"

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

t.test("a pinned agent shows once, first in its zone and project", function()
	t.eq(visible.rows(view({
		agents = {
			agent({ pane = 1, title = "plan" }),
			agent({ pane = 2, title = "build" }),
		},
		pins = { { pane = 2, cwd = REPO, title = "build" } },
	})), { "■ Idle 2", LABEL, ":sparkle(Idle) build", ":sparkle(Idle) plan" })
end)

t.test("pinned agents keep the order they were pinned in", function()
	t.eq(visible.zone(view({
		agents = { agent({ pane = 1, title = "plan" }), agent({ pane = 2, title = "build" }), agent({ pane = 3, title = "free" }) },
		pins = { { pane = 2, cwd = REPO, title = "build" }, { pane = 1, cwd = REPO, title = "plan" } },
	}), "Idle"), { LABEL, ":sparkle(Idle) build", ":sparkle(Idle) plan", ":sparkle(Idle) free" })
end)

t.test("a pinned working agent keeps its subagent rows", function()
	t.eq(visible.zone(view({
		agents = { agent({ pane = 7, title = "Lead", state = "working", workingSince = 0 }) },
		pins = { { pane = 7, cwd = REPO, title = "Lead" } },
		subsOpen = { [7] = true },
		subagents = { [7] = { agents = { { id = "dx.A", name = "A", status = "running", depth = 1 } }, incomplete = false } },
	}), "Working"), { LABEL, ":sparkle(Working) Lead [▮] 0s", "■(Running) A" })
end)

t.test("when the pane id changed, a pin finds its agent by working directory and title", function()
	local agents = {
		agent({ pane = 40, title = "plan" }),
		agent({ pane = 41, title = "build" }),
	}
	local pins = { { pane = 2, cwd = REPO, title = "build" } }
	t.eq(visible.zone(view({ agents = agents, pins = pins }), "Idle"), { LABEL, ":sparkle(Idle) build", ":sparkle(Idle) plan" })
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
	t.eq(visible.zone(v, "Idle"), {
		"tern-agents [:plus](New tab in this folder)",
		":sparkle(Stopped) build :play",
		"tmp [:plus](New tab in this folder)",
		":sparkle(Idle) other work",
	})
	t.eq(visible.click(v, ") build"), "gone=1", "a click on the gone agent does not focus the other one")
	t.eq(visible.menu(v, ") build")[1], "Unpin → forget=1")
	t.eq(visible.menu(v, "other work")[1], "Pin → pin=2")
	t.eq(viewModel.pinOf(agents :: any, pins, 2), nil, "Pin this agent pins the other agent")
end)

t.test("Pin this agent finds the pin of an agent whose pane id changed", function()
	local agents = { agent({ pane = 41, title = "build" }) }
	t.eq(viewModel.pinOf(agents :: any, { { pane = 2, cwd = REPO, title = "build" } }, 41), 1)
end)

t.test("a pinned agent that exited stays in Idle as stopped", function()
	local v = view({
		agents = { agent({ pane = 2, title = "build", state = "exited" }) },
		pins = { { pane = 2, cwd = REPO, title = "build" } },
	})
	t.eq(visible.rows(v), { "■ Idle 1 · 1 stopped", LABEL, ":sparkle(Stopped) build :play" })
	t.eq(visible.state(v, ") build"), "stopped")
end)

t.test("a click on a pinned agent that exited resumes its session, from the pin when the agent no longer reports it", function()
	local v = view({
		agents = { agent({ pane = 2, title = "build", state = "exited", sessionFile = SESSION }) },
		pins = { { pane = 2, cwd = REPO, title = "build" } },
	})
	t.eq(visible.click(v, ") build"), "resume=" .. SESSION)
	v = view({
		agents = { agent({ pane = 2, title = "build", state = "exited" }) },
		pins = { { pane = 2, cwd = REPO, title = "build", sessionFile = SESSION } },
	})
	t.eq(visible.click(v, ") build"), "resume=" .. SESSION)
	t.eq(visible.menu(v, ") build"), {
		"Unpin → unpin=2",
		"Rename → rename (off: The agent is not running)",
		"Copy session ID → copy-id=" .. SESSION,
		"Copy session path → copy-path=" .. SESSION,
		"Interrupt → interrupt=2 (off: The agent is not in a turn)",
	})
end)

t.test("a pinned agent whose pane is gone stays in Idle as stopped, under its last title", function()
	local v = view({ agents = {}, pins = { { pane = 2, cwd = REPO, title = "\u{F0E7} build" } } })
	t.eq(visible.agentRows(v), { "\u{F0E7}(Stopped) build :play" })
	t.eq(visible.state(v, ") build"), "stopped")
	t.eq(visible.click(v, ") build"), "gone=1")
end)

t.test("a pinned agent whose pane is gone resumes its session on a click, and its menu has the copy items", function()
	local v = view({ agents = {}, pins = { { pane = 2, cwd = REPO, title = "build", sessionFile = SESSION } } })
	t.eq(visible.click(v, ") build"), "resume=" .. SESSION)
	t.eq(visible.menu(v, ") build"), {
		"Unpin → forget=1",
		"Rename → rename (off: The agent is not running)",
		"Copy session ID → copy-id=" .. SESSION,
		"Copy session path → copy-path=" .. SESSION,
		"Interrupt → interrupt=2 (off: The agent is not in a turn)",
	})
end)

t.test("a gone pin stored without a session file resumes the newest session of its folder with its title", function()
	local older = { file = "/s/old.jsonl", cwd = REPO, title = "\u{F0E7} build", at = 100 }
	local newer = { file = "/s/new.jsonl", cwd = REPO .. "/", title = "\u{F0E7} build", at = 200 }
	local other = { file = "/s/other.jsonl", cwd = REPO, title = "\u{F0E7} plan", at = 300 }
	local v = view({ agents = {}, pins = { { pane = 2, cwd = REPO, title = "\u{F0E7} build" } }, sessions = { older, newer, other } })
	t.eq(visible.click(v, ") build"), "resume=/s/new.jsonl")
end)

t.test("a pin follows its session to the agent that resumed it, and keeps the session file the agent reports", function()
	local agents = {
		agent({ pane = 2, title = "build", state = "exited", sessionFile = SESSION }),
		agent({ pane = 9, title = "build", sessionFile = SESSION }),
	}
	local pins = { { pane = 2, cwd = REPO, title = "build", sessionFile = SESSION } }
	t.eq(viewModel.resolvePins(agents :: any, pins), { { pane = 9, cwd = REPO, title = "build", sessionFile = SESSION } })
	t.eq(visible.rows(view({ agents = agents, pins = pins })), { "■ Idle 1", LABEL, ":sparkle(Idle) build" })
	t.eq(
		viewModel.resolvePins({ agent({ pane = 2, title = "build", sessionFile = SESSION }) } :: any, { { pane = 2, cwd = REPO, title = "build" } }),
		{ { pane = 2, cwd = REPO, title = "build", sessionFile = SESSION } }
	)
	t.eq(viewModel.pinOf(agents :: any, pins, 9), 1, "Unpin on the resumed agent finds the pin")
	t.eq(viewModel.pinOf(agents :: any, pins, 2), nil, "the exited pane no longer holds the pin")
end)

t.test("a live pinned agent is not drawn stopped", function()
	local v = view({ agents = { agent({ pane = 2, title = "build" }) }, pins = { { pane = 2, cwd = REPO } } })
	t.eq(visible.state(v, ") build"), "idle")
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

return nil
