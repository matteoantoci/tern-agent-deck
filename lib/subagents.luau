--!strict
-- The subagents of an omp agent, read from the tray in the dock of its surface (`cx.session:surface(pane, {root =
-- "dock"})`): omp puts one card (`omp.tray.card`, `item = "agent"`) for each of its subagents there, at every nesting
-- level, from its own agent registry, so an agent that runs again after its `task` call ended (a message revived or
-- woke it) shows as running. Tern draws the tray while its "agents tray" setting is on (the default); omp then hides
-- its HUD counter.
-- A card carries the agent's omp id (`ref`): name-based, a `.` between nesting levels (`Anna.Bob`), so the id gives the
-- depth and the parent. Its status, whether it only waits on its own subagents (`waiting`), its accessible name
-- (`aria`: name, type, status, what it does, its tool count) and, as children, its model with the thinking level
-- (`omp.tray.model`: `claude-opus-5-5 · high`) and what it does now (`omp.tray.call`).
-- Checked live 2026-11-27 (omp 19.2.1, Tern 0.9.36).
-- Pure: it takes the surface trees the reader got from Tern and calls no Tern API, so the `luau` CLI tests it.
-- It uses no `if … then … else` expression, so a Carly probe can `loadstring` it against a live surface.

local subagents = {}

local REGIONS = { "main", "dock", "layer" }

--- One subagent: its omp id, its name as omp shows it (the id with `>` between levels: `Anna>Bob`), how many agents
--- it sits under (1: one of the main agent's own), and the name of the subagent it runs under (nil at the first level).
export type Subagent = {
	id: string,
	name: string,
	--- `pending | running | done | failed | aborted`.
	status: string,
	depth: number,
	parent: string?,
	--- The model id, without its provider (`claude-opus-5-5`).
	model: string?,
	--- The subagent type (`task`, `scout`, `reviewer`), when omp names one.
	role: string?,
	--- The thinking-effort level (`low` … `xhigh`), when the model thinks.
	effort: string?,
	--- What it does now: its current call's intent, or its last line.
	intent: string?,
	--- Running, but only waiting on its own subagents.
	waiting: boolean?,
	--- `tern.now()` when its state began, as the reader saw it (`subagents.stamp`): when it started, while it runs
	--- or is queued; when it ended, once it finished. Nil when the reader saw it only finished.
	since: number?,
}

--- The subagents of one agent, in tree order (each one before the subagents it runs); `incomplete` when the node
--- budget left part of the tray out; `frozen` when they are the last ones read, kept while the dock could not be read
--- (see `viewing.luau`).
export type Subagents = { agents: { Subagent }, incomplete: boolean, frozen: boolean? }

-- The tray's statuses, as the sidebar names them.
local STATUS: { [string]: string } = {
	queued = "pending",
	running = "running",
	done = "done",
	failed = "failed",
	stopped = "aborted",
}

-- The words of the `aria` name that are the status, not the type.
local STATE_WORDS: { [string]: boolean } = { queued = true, running = true, waiting = true, done = true, failed = true, stopped = true }

local LEVELS: { [string]: boolean } = { off = true, minimal = true, low = true, medium = true, high = true, xhigh = true, max = true }

-- TSP text: one string or a list of `{t, s?}` spans. Anything else (`tern.json.null`) is no text.
local function plain(node: any): string?
	local p = node.p
	if type(p) ~= "table" then
		return nil
	end
	if type(p.text) == "string" then
		return p.text
	end
	if type(p.spans) ~= "table" then
		return nil
	end
	local parts: { string } = {}
	for _, span in p.spans do
		if type(span) == "table" and type(span.t) == "string" then
			table.insert(parts, span.t)
		end
	end
	return table.concat(parts)
end

-- A non-empty string, else nil.
local function word(value: any): string?
	if type(value) == "string" and string.find(value, "%S") then
		return value
	end
	return nil
end

-- The text of the first node under `node` (itself included) whose role is `role`.
local function roleText(node: any, role: string): string?
	if type(node) ~= "table" then
		return nil
	end
	if type(node.p) == "table" and node.p.role == role then
		return word(plain(node))
	end
	if type(node.c) == "table" then
		for _, child in node.c do
			local found = roleText(child, role)
			if found then
				return found
			end
		end
	end
	return nil
end

-- Whether `id` is an omp subagent id: levels of letters, digits, `_` and `-`, joined by `.` (the main agent's helpers,
-- such as `Main/advisor`, are none).
local function isAgentId(id: string): boolean
	for _, level in string.split(id, ".") do
		if not string.match(level, "^[%w_%-]+$") then
			return false
		end
	end
	return true
end

-- One card's subagent; nil for a card that is no subagent's.
local function card(node: any): Subagent?
	local p = node.p
	local id = word(p.ref)
	if p.item ~= "agent" or not id or not isAgentId(id) then
		return nil
	end
	local levels = string.split(id, ".")
	local parent: string? = nil
	if #levels > 1 then
		parent = table.concat(levels, ">", 1, #levels - 1)
	end
	local name = table.concat(levels, ">")
	-- `aria`: name, then the type when it says more than the name, then the status.
	local role: string? = nil
	if type(p.aria) == "string" then
		local parts = string.split(p.aria, ", ")
		local second = parts[2]
		if second and second ~= "" and not STATE_WORDS[second] then
			role = second
		end
	end
	local model: string? = nil
	local effort: string? = nil
	local text = roleText(node, "omp.tray.model")
	if text then
		local id_, level = string.match(text, "^(.-)%s*·%s*(%a+)$")
		if id_ and LEVELS[string.lower(level :: string)] then
			model = word(id_)
			effort = string.lower(level :: string)
		else
			model = text
		end
	end
	return {
		id = id,
		name = name,
		status = STATUS[p.status] or "pending",
		depth = #levels,
		parent = parent,
		model = model,
		role = role,
		effort = effort,
		intent = roleText(node, "omp.tray.call"),
		waiting = p.waiting == true,
	}
end

-- Every subagent card under `node`, in tray order; `tray` notes that the tray was found.
local function collect(node: any, out: { Subagent }, seen: { tray: boolean, more: boolean })
	if type(node) ~= "table" then
		return
	end
	if (tonumber(node.more) or 0) > 0 then
		seen.more = true
	end
	local p = node.p
	if type(p) == "table" then
		if p.role == "omp.tray" then
			seen.tray = true
		elseif p.role == "omp.tray.card" then
			seen.tray = true
			local sub = card(node)
			if sub then
				table.insert(out, sub)
			end
			return
		end
	end
	if type(node.c) == "table" then
		for _, child in node.c do
			collect(child, out, seen)
		end
	end
end

--- The subagents in `tree`, a read of an agent's dock, in tree order: each subagent before the ones it runs, siblings
--- in tray order. Nil when the read holds no tray (no TSP surface, or Tern's agents tray is off).
function subagents.fromTray(tree: any): Subagents?
	if type(tree) ~= "table" then
		return nil
	end
	local found: { Subagent } = {}
	local seen = { tray = false, more = (tonumber(tree.more) or 0) > 0 }
	for _, region in REGIONS do
		collect(tree[region], found, seen)
	end
	if not seen.tray then
		return nil
	end
	-- Tree order: sort by the tray position of each level's id (an ancestor missing from the tray takes its child's).
	local position: { [string]: number } = {}
	for i, sub in found do
		position[sub.id] = i
	end
	local function path(sub: Subagent): { number }
		local out: { number } = {}
		local levels = string.split(sub.id, ".")
		for i = 1, #levels do
			local prefix = table.concat(levels, ".", 1, i)
			table.insert(out, position[prefix] or position[sub.id])
		end
		return out
	end
	local paths: { [Subagent]: { number } } = {}
	for _, sub in found do
		paths[sub] = path(sub)
	end
	table.sort(found, function(a, b)
		local x, y = paths[a], paths[b]
		for i = 1, math.min(#x, #y) do
			if x[i] ~= y[i] then
				return x[i] < y[i]
			end
		end
		return #x < #y
	end)
	return { agents = found, incomplete = seen.more }
end

-- Whether `sub` runs or waits in the queue.
local function active(sub: Subagent): boolean
	return sub.status == "running" or sub.status == "pending"
end

--- Whether any of `subs` runs.
function subagents.anyRunning(subs: Subagents?): boolean
	if subs == nil then
		return false
	end
	for _, sub in subs.agents do
		if active(sub) then
			return true
		end
	end
	return false
end

--- Sets on each subagent of `read` the time its state began (`since`), from `last`, the read before it: a subagent
--- that still runs, or that had finished already, keeps its time; one that started or finished since `last` gets
--- `clock`; one that `last` did not list and that has finished has no time (its end is not known). Returns `read`.
function subagents.stamp(last: Subagents?, read: Subagents?, clock: number): Subagents?
	if read == nil then
		return nil
	end
	local before: { [string]: Subagent } = {}
	if last then
		for _, sub in last.agents do
			before[sub.id] = sub
		end
	end
	for _, sub in read.agents do
		local prev = before[sub.id]
		if prev and active(prev) == active(sub) then
			sub.since = prev.since
		elseif prev or active(sub) then
			sub.since = clock
		else
			sub.since = nil
		end
	end
	return read
end

--- The subagent with omp id `id` among `subs`; nil when none has it.
function subagents.find(subs: Subagents?, id: string): Subagent?
	if subs == nil then
		return nil
	end
	for _, agent in subs.agents do
		if agent.id == id then
			return agent
		end
	end
	return nil
end

--- The agent to read on this tick: the lowest pane after `last`, wrapping round; nil when none is polled.
function subagents.nextPane(working: { number }, last: number?): number?
	local first: number? = nil
	local after: number? = nil
	for _, pane in working do
		if first == nil or pane < first then
			first = pane
		end
		if last ~= nil and pane > last and (after == nil or pane < after) then
			after = pane
		end
	end
	return after or first
end

--- Whether two reads show the same subagents, so that an unchanged read does not redraw the sidebar.
function subagents.same(a: Subagents?, b: Subagents?): boolean
	if a == nil or b == nil then
		return a == b
	end
	if a.incomplete ~= b.incomplete or a.frozen ~= b.frozen or #a.agents ~= #b.agents then
		return false
	end
	for i, x in a.agents do
		local y = b.agents[i]
		if
			x.id ~= y.id
			or x.name ~= y.name
			or x.status ~= y.status
			or x.depth ~= y.depth
			or x.parent ~= y.parent
			or x.model ~= y.model
			or x.role ~= y.role
			or x.effort ~= y.effort
			or x.intent ~= y.intent
			or x.waiting ~= y.waiting
		then
			return false
		end
	end
	return true
end

return subagents
