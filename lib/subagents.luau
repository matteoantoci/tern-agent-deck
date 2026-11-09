--!strict
-- The subagents of an omp agent, read from the TSP `agent` nodes of its surface (`cx.session:surface()`).
-- Pure: it takes the surface trees the reader got from Tern and calls no Tern API, so the `luau` CLI tests it.
-- It uses no `if … then … else` expression, so a Carly probe can `loadstring` it against a live surface.

local subagents = {}

local REGIONS = { "main", "dock", "layer" }

local function isTask(node: TspNode): boolean
	local p = node.p
	return node.k == "tool" and type(p) == "table" and p.name == "task"
end

local function walk(node: TspNode?, visit: (TspNode) -> ())
	if type(node) ~= "table" then
		return
	end
	visit(node)
	if type(node.c) == "table" then
		for _, child in node.c do
			walk(child, visit)
		end
	end
end

--- The ids of every running `task` tool node in `tree`, in tree order (oldest call first); empty when none runs.
function subagents.runningTasks(tree: any): { string }
	local found: { string } = {}
	if type(tree) ~= "table" then
		return found
	end
	for _, region in REGIONS do
		walk(tree[region], function(node)
			if isTask(node) and (node.p :: any).status == "running" then
				table.insert(found, node.id)
			end
		end)
	end
	return found
end

--- One subagent: its `agent` node's id and props, how many agents it sits under (1: the task call's own), and the
--- name of the subagent it runs under (nil at the first level).
export type Subagent = {
	id: string,
	name: string,
	--- `pending | running | done | failed | aborted | idle | parked`.
	status: string,
	depth: number,
	parent: string?,
	model: string?,
	--- The subagent type (`task`, `scout`, `reviewer`, `explore`): the `agent` prop.
	role: string?,
	--- The thinking-effort level (`low` … `xhigh`), from the `thinking` prop's theme token (`thinkingHigh`).
	effort: string?,
	--- The tool the subagent runs now and its intent line.
	tool: string?,
	intent: string?,
}

--- The subagents of one running `task` call; `incomplete` when the node budget left part of the tree out; `frozen`
--- when they are the last ones read, kept while omp shows one of them and cannot be read (see `viewing.luau`).
export type Subagents = { agents: { Subagent }, incomplete: boolean, frozen: boolean? }

-- TSP text: one string or a list of `{t, s?}` spans. Anything else (`tern.json.null`) is no text.
local function plain(text: any): string?
	if type(text) == "string" then
		return text
	end
	if type(text) ~= "table" then
		return nil
	end
	local parts: { string } = {}
	for _, span in text do
		if type(span) == "table" and type(span.t) == "string" then
			table.insert(parts, span.t)
		end
	end
	return table.concat(parts)
end

local function str(value: any): string?
	if type(value) == "string" then
		return value
	end
	return nil
end

-- A non-empty string, else nil.
local function word(value: any): string?
	if type(value) == "string" and string.find(value, "%S") then
		return value
	end
	return nil
end

local LEVELS = { off = true, minimal = true, low = true, medium = true, high = true, xhigh = true, max = true }

-- The thinking level of an agent node's `thinking` prop: omp sends the theme token of its model chip's dot
-- (`thinkingHigh`; `max` also sends `thinkingXhigh`), and a plain level is taken as it is.
local function level(thinking: any): string?
	if type(thinking) ~= "string" then
		return nil
	end
	local name = string.lower(string.match(thinking, "^thinking(%a+)$") or thinking)
	if LEVELS[name] then
		return name
	end
	return nil
end

--- The subagents in a read with `root` set to a `task` node, in tree order, at every level: omp puts a subagent's
--- own subagents as `agent` children of its node. Nil when that node is no longer a running `task` call (it ended,
--- or the id now names another node).
function subagents.extract(tree: any): Subagents?
	if type(tree) ~= "table" or type(tree.main) ~= "table" then
		return nil
	end
	local root: TspNode = tree.main
	if not isTask(root) or (root.p :: any).status ~= "running" then
		return nil
	end
	local out: Subagents = { agents = {}, incomplete = (tonumber(tree.more) or 0) > 0 }
	local function visit(node: TspNode, depth: number, parent: string?)
		if (tonumber(node.more) or 0) > 0 then
			out.incomplete = true
		end
		local p = node.p
		local below = depth
		local under = parent
		if node.k == "agent" and type(p) == "table" then
			below = depth + 1
			-- `tool` is `tern.json.null` while no tool runs.
			local tool: { [string]: any } = p.tool
			if type(tool) ~= "table" then
				tool = {}
			end
			local name = str(p.name) or node.id
			table.insert(out.agents, {
				id = node.id,
				name = name,
				status = str(p.status) or "pending",
				depth = below,
				parent = parent,
				model = str(p.model),
				role = word(p.agent),
				effort = level(p.thinking),
				tool = str(tool.name),
				intent = plain(tool.intent),
			})
			under = name
		end
		if type(node.c) == "table" then
			for _, child in node.c do
				visit(child, below, under)
			end
		end
	end
	visit(root, 0, nil)
	return out
end

--- The subagent with node id `id` among `subs`; nil when none has it.
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

--- The subagents of all the running `task` calls of one agent, in the order of the calls; nil when none runs.
function subagents.merge(reads: { Subagents }): Subagents?
	if #reads == 0 then
		return nil
	end
	local out: Subagents = { agents = {}, incomplete = false }
	for _, read in reads do
		for _, agent in read.agents do
			table.insert(out.agents, agent)
		end
		out.incomplete = out.incomplete or read.incomplete
	end
	return out
end

--- The working agent to read on this tick: the lowest pane after `last`, wrapping round; nil when none works.
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
			or x.tool ~= y.tool
			or x.intent ~= y.intent
		then
			return false
		end
	end
	return true
end

return subagents
