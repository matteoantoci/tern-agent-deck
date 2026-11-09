--!strict
-- omp's subagent view. While omp shows one of its subagents ("Viewing <name>"), its chat region holds that
-- subagent's transcript, so a read of the pane finds no running `task` call of the agent: its subagents would drop
-- out of the sidebar. The dock then holds the viewing header (`omp.composer.focus` in omp's `custom-editor.ts`): the
-- shown agent's id in a text node with id `…focus/agent` (`omp.composer.agent`), and omp's way back, `…focus/exit`.
-- A subagent click asks omp's composer to show that subagent (`viewing.show`).
-- Pure: it takes a scoped read of the pane's dock (`cx.session:surface(pane, {root = "dock"})`) and calls no Tern API.

local backToMain = require("./back_to_main")
local subagents = require("./subagents")

local viewing = {}

local function agentText(node: any): string?
	if type(node) ~= "table" then
		return nil
	end
	local id = node.id
	local p = node.p
	if type(id) == "string" and string.sub(id, -#"focus/agent") == "focus/agent" and type(p) == "table" then
		if type(p.text) == "string" and p.text ~= "" then
			return p.text
		end
	end
	if type(node.c) == "table" then
		for _, child in node.c do
			local found = agentText(child)
			if found then
				return found
			end
		end
	end
	return nil
end

--- The omp id of the subagent the pane shows (`Anna`, nested `Anna.Bob`), from a read of its dock; nil while omp
--- shows the main session (the dock has no way back to it).
function viewing.agent(tree: any): string?
	if not backToMain.find(tree) then
		return nil
	end
	return agentText(tree.main) or agentText(tree.dock)
end

--- The subagents to list for an agent: this read while omp shows the main session; while it shows a subagent
--- (`shown`), the last ones listed, marked `frozen`: the reader cannot see them, so their state is the last one read.
function viewing.keep(kept: subagents.Subagents?, read: subagents.Subagents?, shown: string?): subagents.Subagents?
	if not shown then
		return read
	end
	if not kept or kept.frozen then
		return kept
	end
	return { agents = kept.agents, incomplete = kept.incomplete, frozen = true }
end

--- Whether `sub` is the subagent omp shows (`shown`, its omp id). omp names an `agent` node with the id, its nesting
--- levels joined by `>` instead of `.` (`formatTaskId` in omp's `task.ts`).
function viewing.shows(sub: subagents.Subagent, shown: string?): boolean
	if not shown then
		return false
	end
	return sub.name == shown or sub.name == (string.gsub(shown, "%.", ">"))
end

--- The action event that asks omp to show a subagent: the surface id (`sf`), the node id and the action.
export type Show = { surface: string, id: string, act: string }

-- omp's composer node (`omp.editor`; `omp.editor.<shell>` in shell mode) in a read of the dock.
local function composerNode(node: any): any
	if type(node) ~= "table" then
		return nil
	end
	local p = node.p
	local role = type(p) == "table" and p.role
	if type(node.id) == "string" and (role == "omp.editor" or (type(role) == "string" and string.find(role, "^omp%.editor%."))) then
		return node
	end
	if type(node.c) == "table" then
		for _, child in node.c do
			local found = composerNode(child)
			if found then
				return found
			end
		end
	end
	return nil
end

-- The id of omp's composer node in a read of the dock.
local function composer(node: any): string?
	local found = composerNode(node)
	return found and found.id
end

-- The id of the first `editor` node under `node`: the composer's field, the only node omp takes a `send` event on
-- (`#routeUiEvent` in omp's `native/backend.ts` drops one that names another id).
local function field(node: any): string?
	if type(node) ~= "table" then
		return nil
	end
	if node.k == "editor" and type(node.id) == "string" then
		return node.id
	end
	if type(node.c) == "table" then
		for _, child in node.c do
			local found = field(child)
			if found then
				return found
			end
		end
	end
	return nil
end

--- A `send` event for omp's composer: the surface id (`sf`), the composer field's id and the text.
export type Send = { surface: string, id: string, text: string }

--- The `send` event that submits `text` in the composer of the main session, from a read of the pane's dock, as
--- the user's Enter does: omp's composer runs a `/` command as a command, also during a turn. Nil while omp shows a
--- subagent (the composer is that subagent's chat box then) or when the read has no composer field.
function viewing.send(tree: any, text: string): Send?
	if type(tree) ~= "table" or type(tree.surface) ~= "table" or type(tree.surface.id) ~= "string" then
		return nil
	end
	if backToMain.find(tree) then
		return nil
	end
	local id = field(composerNode(tree.main) or composerNode(tree.dock))
	if not id then
		return nil
	end
	return { surface = tree.surface.id, id = id, text = text }
end

--- What a click on `sub`'s row sends to its agent's omp, from a read of the pane's dock: the action of the viewing
--- header's links, `focus:<omp id>`, on the composer node. omp's composer runs a `focus:` action whichever of its
--- nodes it names (`handleNativeEvent` in omp's `custom-editor.ts`) and views that agent, from the main session or
--- straight from another subagent. Nil while omp shows `sub` already, or when the read has no composer.
function viewing.show(tree: any, sub: subagents.Subagent): Show?
	if type(tree) ~= "table" or type(tree.surface) ~= "table" or type(tree.surface.id) ~= "string" then
		return nil
	end
	local id = composer(tree.main) or composer(tree.dock)
	if not id or viewing.shows(sub, viewing.agent(tree)) then
		return nil
	end
	return { surface = tree.surface.id, id = id, act = "focus:" .. string.gsub(sub.name, ">", ".") }
end

return viewing
