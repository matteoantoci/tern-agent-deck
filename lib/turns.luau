--!strict
-- When each working agent began its turn, as `tern.kv` keeps it, so that a plugin reload (which empties the VM)
-- does not reset the timers. Pure: the store reads and writes `tern.kv` and hands the table here.

local viewModel = require("./view_model")

local turns = {}

--- When a turn began: `tern.now()` (monotonic milliseconds, exact while Tern runs) and `os.time()` (wall-clock
--- seconds, for after a Tern restart, when the monotonic clock starts again).
export type Start = { now: number, time: number }
--- The turn starts, by pane id written as a string (`tern.kv` keeps JSON objects).
export type Starts = { [string]: Start }

-- How far apart, in milliseconds, the two clocks may say a turn began before the monotonic one counts as restarted
-- (the wall clock counts whole seconds).
local SKEW = 2000

local function paneKey(pane: number): string
	return string.format("%.0f", pane)
end

--- The turn starts in `stored` (what `tern.kv` gave), leaving out anything malformed.
function turns.decode(stored: any): Starts
	local out: Starts = {}
	if type(stored) ~= "table" then
		return out
	end
	for key, start in stored do
		if type(key) == "string" and type(start) == "table" and type(start.now) == "number"
			and type(start.time) == "number"
		then
			out[key] = { now = start.now, time = start.time }
		end
	end
	return out
end

--- Records an `agent_state` change of the agent in `pane` from `old` to `new`: a turn starts when it enters
--- `working`, and ends when it leaves. An agent this VM sees for the first time (`old` nil, as after a plugin reload)
--- keeps a stored start. Returns whether `starts` changed.
function turns.note(starts: Starts, pane: number, old: string?, new: string, now: number, time: number): boolean
	local key = paneKey(pane)
	if new == "working" then
		if (old == "working" or old == nil) and starts[key] then
			return false
		end
		starts[key] = { now = now, time = time }
		return true
	end
	if starts[key] == nil then
		return false
	end
	starts[key] = nil
	return true
end

-- The `tern.now()` a stored turn began at: the stored one while the monotonic clock agrees with the wall clock,
-- else (Tern restarted) the wall-clock time passed since, counted back from `now`.
local function resolve(start: Start, now: number, time: number): number
	local passed = math.max(0, time - start.time) * 1000
	if math.abs((now - start.now) - passed) <= SKEW then
		return start.now
	end
	return now - passed
end

--- The `tern.now()` each working agent of `agents` began its turn at, by pane. Brings `starts` up to date: a working
--- agent with no start counts from now (the plugin first sees it), and the start of an agent that does not work or
--- is gone is dropped. Also returns whether `starts` changed.
function turns.since(starts: Starts, agents: { viewModel.Agent }, now: number, time: number): ({ [number]: number }, boolean)
	local out: { [number]: number } = {}
	local working: { [string]: boolean } = {}
	local changed = false
	for _, agent in agents do
		if agent.state == "working" then
			local key = paneKey(agent.pane)
			working[key] = true
			local start = starts[key]
			if not start then
				start = { now = now, time = time }
				starts[key] = start
				changed = true
			end
			out[agent.pane] = resolve(start, now, time)
		end
	end
	for key in starts do
		if not working[key] then
			starts[key] = nil
			changed = true
		end
	end
	return out, changed
end

return turns
