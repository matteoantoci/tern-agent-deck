--!strict
-- The subagent reader: on each tick it reads the subagents of one polled agent (working, or idle with running subagents), in rotation, from the TSP `agent`
-- nodes of its surface. A find read lists the running `task` tool nodes, and the ended ones when omp's HUD counts more
-- running subagents than the running calls hold (an agent that runs again after its call ended); the reads in
-- between set `root` to each node found with a running subagent.
-- Measured 2026-11-09 on a chat of about 1400 nodes: the whole chat 11 to 19 ms, the find read 2.3 ms, a `root`
-- read 0.1 to 0.3 ms.

local hud = require("./hud")
local subagents = require("./subagents")
local viewing = require("./viewing")

local reader = {}

-- Tern's largest node budget for one read.
local NODES = 5000
-- The levels the find read walks below the regions: omp puts each `task` tool node right under `main`, so one
-- level finds it, props included, and leaves out every tool's body.
local FIND_DEPTH = 1
-- A pane's task calls are found again once this many milliseconds passed since its last find read, so that a
-- `task` call that starts beside a running one shows within a few seconds however many agents work; a call that
-- ends sends the next read to find them again at once.
local FIND_AFTER = 5000
-- The node budget of the dock read: the dock holds the composer and omp's HUD, well under it.
local DOCK_NODES = 800
-- A live agent that is not polled has its HUD checked once this many milliseconds, at most one such check a tick:
-- after a plugin reload `found` is empty, and an idle agent whose background `task` runs is found by its HUD.
-- Measured 2026-11-09 on pane 17179869199: the dock read took 0.37 to 0.57 ms.
local CHECK_AFTER = 5000

-- The subagents of each polled agent whose last read found a running subagent.
local found: { [number]: subagents.Subagents } = {}
-- The ids of the `task` nodes of each such agent that hold a running subagent, in the order of the calls.
local taskNodes: { [number]: { string } } = {}
-- The `tern.now()` of each pane's last find read.
local foundAt: { [number]: number } = {}
-- The omp id of the subagent each working agent's omp shows in its view, by pane.
local shown: { [number]: string } = {}
-- The number of running subagents that each pane's omp HUD counted at its last dock read, for the panes where it
-- counted some.
local counting: { [number]: number } = {}
-- The `tern.now()` of each unpolled live pane's last HUD check.
local checkedAt: { [number]: number } = {}
-- The agent the last tick read.
local last: number? = nil

-- The subagents of the `task` calls `ids`; nil when one of them no longer holds a running subagent.
local function scoped(cx: WindowCx, pane: number, ids: { string }): subagents.Subagents?
	local reads: { subagents.Subagents } = {}
	for _, id in ids do
		local subs = subagents.extract(cx.session:surface(pane, { root = id, nodes = NODES }))
		if not subs then
			return nil
		end
		table.insert(reads, subs)
	end
	return subagents.merge(reads)
end

-- Adds to `ids` and `reads` each of the `task` calls `candidates` that holds a running subagent.
local function collect(
	cx: WindowCx,
	pane: number,
	candidates: { string },
	ids: { string },
	reads: { subagents.Subagents }
)
	for _, id in candidates do
		local subs = subagents.extract(cx.session:surface(pane, { root = id, nodes = NODES }))
		if subs then
			table.insert(ids, id)
			table.insert(reads, subs)
		end
	end
end

local function read(cx: WindowCx, pane: number, now: number): subagents.Subagents?
	local known = taskNodes[pane]
	if known and now - (foundAt[pane] or 0) < FIND_AFTER then
		local subs = scoped(cx, pane, known)
		if subs then
			return subs
		end
	end
	taskNodes[pane] = nil
	foundAt[pane] = now
	local tree = cx.session:surface(pane, { nodes = NODES, depth = FIND_DEPTH })
	local ids: { string } = {}
	local reads: { subagents.Subagents } = {}
	collect(cx, pane, subagents.runningTasks(tree), ids, reads)
	-- An agent that runs again after its call ended shows in that call's card: read the ended calls only while the
	-- HUD counts more running subagents than the running calls hold.
	if subagents.runningCount(reads) < (counting[pane] or 0) then
		collect(cx, pane, subagents.settledTasks(tree), ids, reads)
	end
	if #ids == 0 then
		return nil
	end
	taskNodes[pane] = ids
	return subagents.merge(reads)
end

--- The subagents of each working agent's running `task` calls, by pane: the view model's `subagents` input.
function reader.subagents(): { [number]: subagents.Subagents }
	return found
end

--- The omp id of the subagent each working agent's omp shows ("Viewing <name>"), by pane: the view model's
--- `viewing` input.
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

-- Notes how many running subagents `tree`, a read of `pane`'s dock, shows omp's HUD counting.
local function count(pane: number, tree: any)
	local n = hud.running(tree)
	if n > 0 then
		counting[pane] = n
	else
		counting[pane] = nil
	end
end

--- Reads the next polled agent in turn: every working agent, and every other live agent whose last read found a
--- running `task` call or whose omp HUD counts running subagents (omp runs `task` subagents in the background, so its
--- agent can end its turn and go idle while they work; it stays polled until a read finds none). An unpolled live
--- agent has its HUD checked every `CHECK_AFTER`, in turn, one a tick. Returns whether the subagents changed, and
--- whether the timer must keep ticking: any agent polled, or an unpolled one not checked yet. `clock` is `tern.now()`.
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
			or (
				block.state ~= "exited"
				and (found[block.pane] ~= nil or shown[block.pane] ~= nil or counting[block.pane] ~= nil)
			)
		then
			table.insert(polled, block.pane)
			isPolled[block.pane] = true
		end
	end
	local changed = false
	for pane in found do
		if not isPolled[pane] then
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
	for pane in taskNodes do
		if not isPolled[pane] then
			taskNodes[pane] = nil
			foundAt[pane] = nil
		end
	end
	for pane in counting do
		if not live[pane] then
			counting[pane] = nil
		end
	end
	-- One HUD check of the unpolled live pane checked longest ago, once its interval passed.
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
		count(due, dock(cx, due))
	end
	-- The timer keeps ticking while an unpolled pane waits for its first check or its HUD counts running subagents.
	local pending = false
	for pane in live do
		if not isPolled[pane] and (checkedAt[pane] == nil or counting[pane]) then
			pending = true
		end
	end
	local pane = subagents.nextPane(polled, last)
	last = pane
	if not pane then
		return changed, pending
	end
	-- While omp shows a subagent, the chat region holds that subagent's transcript, not the agent's `task` calls:
	-- the agent keeps the subagents its last read found, and its chat is not read.
	local tree = dock(cx, pane)
	count(pane, tree)
	local viewed = if tree then viewing.agent(tree) else nil
	if shown[pane] ~= viewed then
		if viewed then
			shown[pane] = viewed
		else
			shown[pane] = nil
		end
		changed = true
	end
	-- A pane that closed or shows no TSP surface (Claude Code, Codex) raises or reads nothing: no subagents.
	local ok, subs = true, nil
	if not viewed then
		ok, subs = pcall(read, cx, pane, clock)
	end
	local now: subagents.Subagents? = viewing.keep(found[pane], if ok then subs else nil, viewed)
	if not subagents.same(found[pane], now) then
		if now then
			found[pane] = now
		else
			found[pane] = nil
		end
		changed = true
	end
	-- The pane stays polled while it works, its read found a running `task` call or its HUD counts running
	-- subagents; the others stay polled anyway.
	return changed,
		#polled > 1
			or working[pane] == true
			or found[pane] ~= nil
			or shown[pane] ~= nil
			or counting[pane] ~= nil
			or pending
end

return reader
