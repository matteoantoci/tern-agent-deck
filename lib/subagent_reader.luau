--!strict
-- The subagent reader: on each tick it reads the dock of one polled agent (working, or idle with running subagents),
-- in rotation, and takes its subagents from omp's tray there (`subagents.fromTray`). One read scoped to the dock
-- also tells which subagent omp shows (`viewing.agent`). An agent that is not polled has its dock checked every
-- `CHECK_AFTER`, one a tick, so that an idle agent whose subagents still run (omp runs them in the background) is
-- found, also after a plugin reload. A live agent keeps the subagents of its last read when none runs, so that its
-- row can show how many are done and its failed ones.

local subagents = require("./subagents")
local viewing = require("./viewing")

local reader = {}

-- The node budget of a dock read: the composer and the tray, with room for many cards.
local DOCK_NODES = 3000
-- A live agent that is not polled has its dock checked once this many milliseconds, at most one such check a tick.
local CHECK_AFTER = 5000

-- The subagents of each live agent, as its last read found them, with the time each one's state began.
local found: { [number]: subagents.Subagents } = {}
-- The omp id of the subagent each agent's omp shows in its view, by pane.
local shown: { [number]: string } = {}
-- The `tern.now()` of each unpolled live pane's last dock check.
local checkedAt: { [number]: number } = {}
-- The agent the last tick read.
local last: number? = nil

--- The subagents of each live agent that has any, by pane: the view model's `subagents` input.
function reader.subagents(): { [number]: subagents.Subagents }
	return found
end

--- The omp id of the subagent each agent's omp shows ("Viewing <name>"), by pane: the view model's `viewing` input.
function reader.viewing(): { [number]: string }
	return shown
end

-- A read scoped to `pane`'s dock; nil when the pane has no TSP surface.
local function dock(cx: WindowCx, pane: number): any
	local ok, tree = pcall(function()
		return cx.session:surface(pane, { root = "dock", nodes = DOCK_NODES })
	end)
	return if ok then tree else nil
end

-- Stores `subs` as `pane`'s subagents (none when nil), each with the time its state began (`clock` for a change since
-- the last read); returns whether that changed them.
local function store(pane: number, subs: subagents.Subagents?, clock: number): boolean
	subs = subagents.stamp(found[pane], subs, clock)
	if subagents.same(found[pane], subs) then
		return false
	end
	if subs then
		found[pane] = subs
	else
		found[pane] = nil
	end
	return true
end

--- Reads the next polled agent in turn: every working agent, and every other live agent whose last read found a
--- running subagent or whose omp shows a subagent. An unpolled live agent has its dock checked every `CHECK_AFTER`,
--- in turn, one a tick. Returns whether the subagents changed, and whether the timer must keep ticking: any agent
--- polled, or an unpolled one not checked yet. `clock` is `tern.now()`.
function reader.step(cx: WindowCx, clock: number): (boolean, boolean)
	local polled: { number } = {}
	local isPolled: { [number]: boolean } = {}
	local working: { [number]: boolean } = {}
	local live: { [number]: boolean } = {}
	for _, block in cx.agents:list() do
		working[block.pane] = block.state == "working"
		if block.state ~= "exited" then
			live[block.pane] = true
		end
		if
			block.state == "working"
			or (block.state ~= "exited" and (subagents.anyRunning(found[block.pane]) or shown[block.pane] ~= nil))
		then
			table.insert(polled, block.pane)
			isPolled[block.pane] = true
		end
	end
	local changed = false
	for pane in found do
		if not live[pane] then
			found[pane] = nil
			changed = true
		end
	end
	for pane in shown do
		if not isPolled[pane] then
			shown[pane] = nil
			changed = true
		end
	end
	-- One dock check of the unpolled live pane checked longest ago, once its interval passed: it is polled from now
	-- on when one of its subagents runs.
	local due: number? = nil
	for pane in live do
		if isPolled[pane] then
			checkedAt[pane] = nil
		else
			local at = checkedAt[pane] or -math.huge
			if clock - at >= CHECK_AFTER and (due == nil or at < (checkedAt[due] or -math.huge)) then
				due = pane
			end
		end
	end
	for pane in checkedAt do
		if not live[pane] then
			checkedAt[pane] = nil
		end
	end
	if due then
		checkedAt[due] = clock
		changed = store(due, subagents.fromTray(dock(cx, due)), clock) or changed
	end
	local pending = false
	for pane in live do
		if not isPolled[pane] and checkedAt[pane] == nil then
			pending = true
		end
	end
	local pane = subagents.nextPane(polled, last)
	last = pane
	if not pane then
		return changed, pending
	end
	local tree = dock(cx, pane)
	local viewed = if tree then viewing.agent(tree) else nil
	if shown[pane] ~= viewed then
		if viewed then
			shown[pane] = viewed
		else
			shown[pane] = nil
		end
		changed = true
	end
	-- A pane that closed or shows no TSP surface (Claude Code, Codex) reads no tray: no subagents, except that while
	-- omp shows a subagent the last ones read stay, frozen. With none running, omp's tray lists every finished agent
	-- of the session as its own card, also those of earlier turns; while one runs, older ones fold into one `done`
	-- card (no subagent).
	local subs = subagents.fromTray(tree)
	local now = if subs then subs else viewing.keep(found[pane], nil, viewed)
	changed = store(pane, now, clock) or changed
	local more = #polled > 1 or working[pane] == true or subagents.anyRunning(found[pane]) or shown[pane] ~= nil
	return changed, more or pending
end

return reader
