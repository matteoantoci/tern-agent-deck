--!strict
-- omp's HUD agents counter. omp's dock holds a row (id `…running/agents`, click `agents.open`) that counts the running
-- subagents of the session (`agentsSegment` in omp's `modes/interactive-mode.ts`): while some run, it holds a `count`
-- text node and its `aria` reads `1 agent running` / `2 agents running` (`describeRunningSegment`); while none run, it
-- holds no `count` node and reads `No agents running · 2 in this session` (`describeIdleAgentsSegment`).
-- Pure: it takes a scoped read of the pane's dock (`cx.session:surface(pane, {root = "dock"})`) and calls no Tern API.

local hud = {}

local function isCounter(node: any): boolean
	local id = node.id
	local p = node.p
	return type(id) == "string"
		and string.sub(id, -#"running/agents") == "running/agents"
		and type(p) == "table"
		and type(p.actions) == "table"
		and p.actions.click == "agents.open"
end

local function counter(node: any): any
	if type(node) ~= "table" then
		return nil
	end
	if isCounter(node) then
		return node
	end
	if type(node.c) == "table" then
		for _, child in node.c do
			local found = counter(child)
			if found then
				return found
			end
		end
	end
	return nil
end

--- The number of subagents omp's HUD counts as running, from a read of the pane's dock; 0 when it shows none or
--- the dock has no counter.
function hud.running(tree: any): number
	if type(tree) ~= "table" then
		return 0
	end
	local row = counter(tree.dock) or counter(tree.main)
	if not row or type(row.c) ~= "table" then
		return 0
	end
	for _, child in row.c do
		if type(child) == "table" and type(child.id) == "string" and string.sub(child.id, -#"/count") == "/count" then
			local aria = row.p.aria
			local n = if type(aria) == "string" then tonumber(string.match(aria, "^(%d+) agents? running")) else nil
			return n or 1
		end
	end
	return 0
end

return hud
