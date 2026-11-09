--!strict
-- Turn timers survive a plugin reload: each agent's turn start lives in `tern.kv`, and a rebuild reads it back.
local t = require("./harness")
local visible = require("./visible")
local turns = require("../lib/turns")
local viewModel = require("../lib/view_model")

local T = 1_800_000_000

-- What `tern.kv` hands back: a JSON copy of what was stored.
local function stored(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out: { [any]: any } = {}
	for k, v in value do
		out[k] = stored(v)
	end
	return out
end

-- The turn timer each working agent's hover card shows at `now` ("Fix login ⏱29s"), each working agent's turn
-- start read from `starts`.
local function timers(starts: turns.Starts, agents: { { [string]: any } }, now: number, time: number): { string }
	local since = turns.since(starts, agents :: any, now, time)
	for _, agent in agents do
		agent.workingSince = since[agent.pane]
	end
	local view = viewModel.build({ agents = agents :: any, now = now }).view
	local out: { string } = {}
	for _, agent in agents do
		local card = visible.hover(view, "(Working) " .. agent.title) or ""
		table.insert(out, agent.title .. " " .. (string.match(card, "Working for (⏱%d+s)") or "no timer"))
	end
	return out
end

local function working(): { { [string]: any } }
	return {
		{ pane = 7, state = "working", cwd = "/repo", title = "Fix login" },
		{ pane = 9, state = "working", cwd = "/repo", title = "Add tests" },
	}
end

-- Two agents that began their turns 19 seconds apart.
local function twoTurns(): turns.Starts
	local starts: turns.Starts = {}
	turns.note(starts, 7, "idle", "working", 1000, T)
	turns.note(starts, 9, "idle", "working", 20000, T + 19)
	return stored(starts)
end

t.test("after a plugin reload each working agent's timer keeps the age of its own turn", function()
	t.eq(timers(turns.decode(twoTurns()), working(), 30400, T + 29), {
		"Fix login ⏱29s",
		"Add tests ⏱10s",
	})
end)

t.test("after a Tern restart, whose clock starts again, the timers count from the turn's wall-clock start", function()
	t.eq(timers(turns.decode(twoTurns()), working(), 2000, T + 29), {
		"Fix login ⏱29s",
		"Add tests ⏱10s",
	})
end)

t.test("an agent already working with no stored start counts from the first look, and a reload keeps that", function()
	local starts: turns.Starts = {}
	local agents = { { pane = 7, state = "working", cwd = "/repo", title = "Fix login" } }
	local since, changed = turns.since(starts, agents :: any, 5000, T)
	t.eq(since[7], 5000)
	t.eq(changed, true, "the first look is stored")
	t.eq(timers(turns.decode(stored(starts)), agents, 17000, T + 12), { "Fix login ⏱12s" })
end)

t.test("a turn that ends clears its start, and the start of a pane that is gone is dropped", function()
	local starts = turns.decode(twoTurns())
	t.eq(turns.note(starts, 7, "working", "idle", 30000, T + 29), true)
	t.eq(starts["7"], nil)
	local _, changed = turns.since(starts, {} :: any, 31000, T + 30)
	t.eq(changed, true)
	t.eq(starts, {})
end)

t.test("a state change inside a turn keeps its start", function()
	local starts = turns.decode(twoTurns())
	t.eq(turns.note(starts, 7, "working", "working", 9000, T + 8), false)
	t.eq(timers(starts, working(), 30400, T + 29)[1], "Fix login ⏱29s")
end)

t.test("an agent the reloaded plugin hears about as new keeps its stored turn start", function()
	local starts = turns.decode(twoTurns())
	t.eq(turns.note(starts, 7, nil, "working", 30000, T + 29), false)
	t.eq(timers(starts, working(), 30400, T + 29)[1], "Fix login ⏱29s")
end)

return nil
