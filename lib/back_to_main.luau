--!strict
-- omp's way back from a subagent to the main session. While omp shows a subagent ("Viewing <name>"), its dock holds a
-- row with an id ending in `focus/exit` (`3.focus/exit`) whose click action is `focus:<main>` ("Back to the main
-- session"). A click on a main agent's row runs that action, so that omp shows the main session again.
-- Pure: it takes a scoped read of the pane's dock (`cx.session:surface(pane, {root = "dock"})`) and calls no Tern API.
-- It uses no `if … then … else` expression, so a Carly probe can `loadstring` it.

local backToMain = {}

--- The action event that brings omp back to the main session: the surface id (`sf`), the node id and the action.
export type Exit = { surface: string, id: string, act: string }

local function find(node: any): (string?, string?)
	if type(node) ~= "table" then
		return nil, nil
	end
	local id = node.id
	if type(id) == "string" and string.sub(id, -#"focus/exit") == "focus/exit" then
		local p = node.p
		local actions = type(p) == "table" and p.actions
		local click = type(actions) == "table" and actions.click
		if type(click) == "string" and string.sub(click, 1, #"focus:") == "focus:" then
			return id, click
		end
	end
	if type(node.c) == "table" then
		for _, child in node.c do
			local found, act = find(child)
			if found then
				return found, act
			end
		end
	end
	return nil, nil
end

--- omp's way back to the main session in `tree` (a read of the pane's dock); nil when omp shows the main session.
function backToMain.find(tree: any): Exit?
	if type(tree) ~= "table" or type(tree.surface) ~= "table" or type(tree.surface.id) ~= "string" then
		return nil
	end
	local id, act = find(tree.main)
	if not id then
		id, act = find(tree.dock)
	end
	if not id or not act then
		return nil
	end
	return { surface = tree.surface.id, id = id, act = act }
end

return backToMain
