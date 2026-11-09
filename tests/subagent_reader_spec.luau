--!strict
-- The subagent reader against a fake window: omp runs `task` subagents in the background, so its agent can end its
-- turn and go idle while they work.
local t = require("./harness")

local clock = 0

local reader = require("../lib/subagent_reader")

local function agentNode(name: string, status: string): any
	return { id = "dx." .. name, k = "agent", p = { name = name, status = status }, c = {} }
end

local function taskNode(status: string, agents: { any }): any
	return { id = "5mt", k = "tool", p = { name = "task", status = status }, c = agents }
end

-- omp's HUD agents counter as the dock holds it (`agentsSegment` in omp's `interactive-mode.ts`): with a `count`
-- node while `running` > 0.
local function counter(running: number): any
	local label = if running > 0 then running .. (if running == 1 then " agent" else " agents") .. " running"
		else "No agents running · 2 in this session"
	local c: { any } = { { id = "6.running/agents/icon", k = "icon", p = { name = "agent" } } }
	if running > 0 then
		table.insert(c, { id = "6.running/agents/count", k = "text", p = {} })
	end
	return { id = "6.running/agents", k = "row", p = { aria = label, actions = { click = "agents.open" } }, c = c }
end

-- A window with one omp agent in pane 7, in `state`, whose chat holds `task`, and whose dock holds `hud`.
local function window(state: string, task: any, hud: any?): any
	local cx: any = {}
	cx.agents = {
		list = function(_self: any)
			return { { pane = 7, state = state } }
		end,
	}
	cx.session = {
		surface = function(_self: any, _pane: number, opts: any)
			if opts.root == "dock" then
				return { surface = { id = "s" }, dock = { id = "d", k = "col", c = { hud } } } :: any
			elseif opts.root then
				return { surface = { id = "s" }, main = task }
			end
			return { surface = { id = "s" }, main = { id = "m", k = "col", c = { task } } }
		end,
	}
	return cx
end

local function names(): { string }
	local out = {}
	local subs = reader.subagents()[7]
	for _, sub in (if subs then subs.agents else {}) :: { any } do
		table.insert(out, sub.name .. " " .. sub.status)
	end
	return out
end

local function step(cx: any, after: number?): boolean
	clock += after or 1000
	local _, polling = reader.step(cx, clock)
	return polling
end

t.test("an agent that goes idle while its task runs keeps its subagent rows, and the reader keeps polling", function()
	t.eq(step(window("working", taskNode("running", { agentNode("Copy", "running") }))), true)
	t.eq(names(), { "Copy running" })
	t.eq(step(window("idle", taskNode("running", { agentNode("Copy", "running") }))), true)
	t.eq(names(), { "Copy running" })
end)

t.test("a task that ends while its agent is idle drops the rows, and the reader stops polling", function()
	t.eq(step(window("idle", taskNode("running", { agentNode("Copy", "done"), agentNode("Scan", "running") }))), true)
	t.eq(names(), { "Copy done", "Scan running" })
	t.eq(step(window("idle", taskNode("done", { agentNode("Copy", "done"), agentNode("Scan", "done") }))), false)
	t.eq(names(), {})
end)

t.test("an idle agent with no subagents is not polled", function()
	t.eq(step(window("idle", taskNode("running", { agentNode("Copy", "running") }))), false)
	t.eq(names(), {})
end)

t.test("an agent that exits drops its subagent rows", function()
	step(window("working", taskNode("running", { agentNode("Copy", "running") })))
	t.eq(step(window("exited", taskNode("running", { agentNode("Copy", "running") }))), false)
	t.eq(names(), {})
end)

t.test("after a reload, an idle agent whose HUD counts a running subagent gets its rows back", function()
	local cx = window("idle", taskNode("running", { agentNode("Copy", "running") }), counter(1))
	t.eq(names(), {})
	t.eq(step(cx), true)
	t.eq(step(cx), true)
	t.eq(names(), { "Copy running" })
end)

t.test("an idle agent stays polled while its HUD counts running subagents", function()
	local cx = window("idle", taskNode("done", {}), counter(1))
	t.eq(step(cx), true)
	t.eq(step(cx), true)
	t.eq(names(), {})
	t.eq(step(window("idle", taskNode("done", {}), counter(0))), false)
end)

t.test("an unpolled idle agent is checked again only after the interval", function()
	local checks = 0
	local count = 0
	local cx = window("idle", taskNode("running", { agentNode("Copy", "running") }), counter(0))
	local surface = cx.session.surface
	cx.session.surface = function(self: any, pane: number, opts: any)
		if opts.root == "dock" then
			checks += 1
			if count > 0 then
				return { surface = { id = "s" }, dock = { id = "d", k = "col", c = { counter(count) } } }
			end
		end
		return surface(self, pane, opts)
	end
	step(cx, 5000)
	t.eq(checks, 1)
	count = 1
	step(cx, 1000)
	t.eq(checks, 1)
	t.eq(names(), {})
	step(cx, 4000)
	t.eq(checks, 2)
	step(cx)
	t.eq(names(), { "Copy running" })
	t.eq(step(window("exited", taskNode("done", {}))), false)
end)

return nil
