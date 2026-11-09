--!strict
-- The effort reader: the thinking-effort level of each omp main agent, from the effort glyph of its composer in
-- the dock of its surface. It reads only when the entry asks (an agent's state changes or a turn ends, and once at
-- start), never on the 1-second tick, and keeps the level of each pane.
-- Measured 2026-11-09 (Tern 0.9.13, omp chat): a read scoped to the effort node 0.012 ms; a read scoped to the
-- dock (`root = "dock"`, 49 nodes) 0.27 ms; the node id was `3.bar/model/effort`.

local effort = require("./effort")

local reader = {}

-- The id of each pane's dock region: a `root` read of it holds the composer, and nothing of the chat.
local DOCK = "dock"
local NODES = 5000

-- The effort level of each pane whose last read found one.
local levels: { [number]: string } = {}
-- The id of each pane's effort node, so that the next read takes that node alone.
local nodes: { [number]: string } = {}

local function scoped(cx: WindowCx, pane: number, root: string): (string?, string?)
	return effort.find(cx.session:surface(pane, { root = root, nodes = NODES }))
end

local function read(cx: WindowCx, pane: number): string?
	local known = nodes[pane]
	if known then
		local id, level = scoped(cx, pane, known)
		if id == known then
			return level
		end
		nodes[pane] = nil
	end
	local id, level = scoped(cx, pane, DOCK)
	if id then
		nodes[pane] = id
	end
	return level
end

--- Reads the effort level of the agent in `pane` again.
function reader.read(cx: WindowCx, pane: number)
	-- A pane that closed or shows no TSP surface (Claude Code, Codex) raises or reads nothing: no level.
	local ok, level = pcall(read, cx, pane)
	if ok and level then
		levels[pane] = level
	else
		levels[pane] = nil
	end
end

--- The effort level of the agent in `pane`, as its last read found it; nil when none.
function reader.level(pane: number): string?
	return levels[pane]
end

--- Forgets a closed pane.
function reader.forget(pane: number)
	levels[pane] = nil
	nodes[pane] = nil
end

return reader
