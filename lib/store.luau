--!strict
-- The plugin's shared state in `tern.kv`: the pins, the view the strip shows (Live or Recent), the open "Older" rows,
-- the folded sections, the folders open in the Recent view, whether the Recent view shows every folder, when each
-- agent was last in a turn and when each working agent began its turn. `tern.kv` is one file for every window and
-- survives restarts and plugin reloads, so every tab and window shows the same view, pins, rows and timers, and they
-- stay after a reload or a Tern restart.

local turns = require("./turns")
local viewModel = require("./view_model")

local store = {}

local PINS = "pins"
local ACTIVITY = "activity"
-- When each working agent began its turn (`lib/turns.luau`).
local TURNS = "turns"
-- The sets of group keys, by what they record: the open "Older" rows, the sections folded in the Live view, and the
-- folders whose sessions show in the Recent view.
export type KeySet = "older" | "folded" | "recent"
-- `true` while the Recent view shows every folder, rather than only the first few.
local RECENT_ALL = "recent-all"
-- The view the strip shows: `"recent"`, or nothing for Live.
local VIEW = "view"

-- An activity record for a pane that no longer runs an agent is dropped after this many seconds. Records are not
-- dropped at once, because the agent list can be short for a moment while the daemon restarts.
local FORGET_AFTER = 30 * 24 * 60 * 60

-- When the agent in a pane last ended or started a turn (`os.time()`), and its working directory: a record whose
-- directory differs belongs to an earlier agent that had the same pane id.
type Activity = { at: number, cwd: string? }

local function get(key: string): any
	local ok, value = pcall(tern.kv.get, key)
	if ok then
		return value
	end
	return nil
end

local function str(value: any): string?
	if type(value) == "string" then
		return value
	end
	return nil
end

local function paneKey(pane: number): string
	return string.format("%.0f", pane)
end

local function pins(): { viewModel.Pin }
	local out: { viewModel.Pin } = {}
	local stored = get(PINS)
	if type(stored) ~= "table" then
		return out
	end
	for _, pin in stored do
		if type(pin) == "table" and type(pin.pane) == "number" then
			table.insert(out, { pane = pin.pane, cwd = str(pin.cwd), title = str(pin.title) })
		end
	end
	return out
end

local function setPins(list: { viewModel.Pin })
	if #list == 0 then
		tern.kv.set(PINS, nil)
	else
		tern.kv.set(PINS, list)
	end
end

local function samePins(a: { viewModel.Pin }, b: { viewModel.Pin }): boolean
	if #a ~= #b then
		return false
	end
	for i, pin in a do
		local other = b[i]
		if pin.pane ~= other.pane or pin.cwd ~= other.cwd or pin.title ~= other.title then
			return false
		end
	end
	return true
end

local function activity(): { [string]: Activity }
	local out: { [string]: Activity } = {}
	local stored = get(ACTIVITY)
	if type(stored) ~= "table" then
		return out
	end
	for pane, record in stored do
		if type(pane) == "string" and type(record) == "table" and type(record.at) == "number" then
			out[pane] = { at = record.at, cwd = str(record.cwd) }
		end
	end
	return out
end

local function keySet(name: KeySet): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local stored = get(name)
	if type(stored) ~= "table" then
		return out
	end
	for key, on in stored do
		if type(key) == "string" and on == true then
			out[key] = true
		end
	end
	return out
end

local function recentAll(): boolean
	return get(RECENT_ALL) == true
end

local function setTurns(starts: turns.Starts)
	if next(starts) == nil then
		tern.kv.set(TURNS, nil)
	else
		tern.kv.set(TURNS, starts)
	end
end

--- Completes the view-model input with the shared state: the wall-clock time, when each working agent began its
--- turn, when each agent was last in a turn, the pins, the view the strip shows, the open Older rows, the folded
--- sections, the folders open in the Recent view and whether it shows every folder. Records the agents it sees for
--- the first time as active now (an agent never seen in a turn counts as new), a working agent with no turn start as
--- working since now, and stores the pins with the pane ids and titles their agents have now. Drops the turn starts
--- of agents that do not work or are gone.
function store.fill(input: viewModel.Input): viewModel.Input
	local time = os.time()
	input.time = time

	local starts = turns.decode(get(TURNS))
	local since, moved = turns.since(starts, input.agents, input.now, time)
	for _, agent in input.agents do
		agent.workingSince = since[agent.pane]
	end
	if moved then
		setTurns(starts)
	end

	local records = activity()
	local listed: { [string]: boolean } = {}
	local changed = false
	for _, agent in input.agents do
		local key = paneKey(agent.pane)
		listed[key] = true
		local record: Activity? = records[key]
		if record and record.cwd ~= nil and record.cwd ~= agent.cwd then
			record = nil
		end
		if record == nil then
			records[key] = { at = time, cwd = agent.cwd }
			changed = true
			agent.activeAt = time
		else
			if record.cwd == nil and agent.cwd then
				record.cwd = agent.cwd
				changed = true
			end
			agent.activeAt = record.at
		end
	end
	for key, record in records do
		if not listed[key] and time - record.at > FORGET_AFTER then
			records[key] = nil
			changed = true
		end
	end
	if changed then
		tern.kv.set(ACTIVITY, records)
	end

	local stored = pins()
	local resolved = viewModel.resolvePins(input.agents, stored)
	if not samePins(resolved, stored) then
		setPins(resolved)
	end
	input.pins = resolved
	input.olderOpen = keySet("older")
	input.folded = keySet("folded")
	input.recentOpen = keySet("recent")
	input.recentAll = recentAll()
	input.view = if get(VIEW) == "recent" then "recent" else "live"
	return input
end

--- Records that the agent in `pane` is in a turn or just ended one: its idle time counts from now.
function store.noteActivity(pane: number)
	local records = activity()
	local key = paneKey(pane)
	local record = records[key]
	records[key] = { at = os.time(), cwd = record and record.cwd }
	tern.kv.set(ACTIVITY, records)
end

--- Records the turn start of the agent in `ev.pane` when it enters `working`, and clears it when it leaves.
function store.noteTurn(ev: AgentStateEvent)
	local starts = turns.decode(get(TURNS))
	if turns.note(starts, ev.pane, ev.old, ev.new, tern.now(), os.time()) then
		setTurns(starts)
	end
end

-- The agents Tern lists now, with the working directory and pane title the pins match them by.
local function agents(cx: WindowCx): { viewModel.Agent }
	local out: { viewModel.Agent } = {}
	for _, block in cx.agents:list() do
		local info = cx.session:pane(block.pane)
		table.insert(out, {
			pane = block.pane,
			state = block.state,
			cwd = str(block.cwd),
			title = info and str(info.title),
		})
	end
	return out
end

--- Removes the pin at `index` of the stored pins (what a pinned row whose agent is gone names).
function store.forget(index: number)
	local list = pins()
	if list[index] then
		table.remove(list, index)
		setPins(list)
	end
end

--- Removes the pin of the agent in `pane`, found the way the Pinned section finds it.
function store.unpin(cx: WindowCx, pane: number)
	local index = viewModel.pinOf(agents(cx), pins(), pane)
	if index then
		store.forget(index)
	end
end

--- Pins the agent in `pane` with its working directory and pane title as backup keys, at the bottom of Pinned.
--- Returns false when `pane` runs no agent.
function store.pin(cx: WindowCx, pane: number): boolean
	local listed = agents(cx)
	local agent: viewModel.Agent? = nil
	for _, each in listed do
		if each.pane == pane then
			agent = each
			break
		end
	end
	if not agent then
		return false
	end
	local list = pins()
	if viewModel.pinOf(listed, list, pane) then
		return true
	end
	table.insert(list, { pane = pane, cwd = agent.cwd, title = agent.title })
	setPins(list)
	return true
end

--- Whether a pin names the agent in `pane`, the way the Pinned section matches pins to agents: a pin whose agent
--- is gone does not name another agent that got its pane id.
function store.pinned(cx: WindowCx, pane: number): boolean
	return viewModel.pinOf(agents(cx), pins(), pane) ~= nil
end

--- Adds `key` to the set `name` (an Older or Recent row opens, a section folds) when it is not in it, and removes it
--- when it is.
function store.toggle(name: KeySet, key: string)
	local set = keySet(name)
	if set[key] then
		set[key] = nil
	else
		set[key] = true
	end
	if next(set) == nil then
		tern.kv.set(name, nil)
	else
		tern.kv.set(name, set)
	end
end

--- Shows every folder in the Recent view when it shows the first few, and the first few when it shows every one.
function store.toggleRecentAll()
	tern.kv.set(RECENT_ALL, if recentAll() then nil else true)
end

--- Shows `view` in every copy of the sidebar, in every window, and after a restart.
function store.setView(view: viewModel.View)
	tern.kv.set(VIEW, if view == "recent" then "recent" else nil)
end

return store
