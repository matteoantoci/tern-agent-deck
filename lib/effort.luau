--!strict
-- The thinking-effort level of an omp main agent, read from the `effort` node of its composer in the dock of its
-- surface (`cx.session:surface()`). Pure: it takes the tree the reader got from Tern and calls no Tern API.
-- It uses no `if … then … else` expression, so a Carly probe can `loadstring` it.

local effort = {}

-- The role omp gives the composer's effort glyph (inside the model row, `omp.composer.model`).
local ROLE = "omp.composer.model.effort"

local function find(node: any): any
	if type(node) ~= "table" then
		return nil
	end
	local p = node.p
	if node.k == "effort" and type(p) == "table" and p.role == ROLE then
		return node
	end
	if type(node.c) == "table" then
		for _, child in node.c do
			local found = find(child)
			if found then
				return found
			end
		end
	end
	return nil
end

--- The id of the composer's effort node in `tree` (a read of the dock, or one scoped to that node) and its level;
--- nothing when the tree holds no such node, and no level when the node has none.
function effort.find(tree: any): (string?, string?)
	if type(tree) ~= "table" then
		return nil, nil
	end
	local node = find(tree.main) or find(tree.dock)
	if not node then
		return nil, nil
	end
	local level = node.p.level
	if type(level) ~= "string" or not string.find(level, "%S") then
		return node.id, nil
	end
	return node.id, level
end

return effort
