--!strict
-- Where the sidebar copies go: one on the right edge of every tab (Tern's Files pane takes the left edge of the
-- window), all at one shared width, none while hidden.
-- Pure: it reads tab split trees and returns what to open, close and resize; the sidebar manager does it.

local placement = {}

--- A tab's split tree, as `cx.session:layout(tab).root` gives it.
export type Tree = { pane: number?, split: ("right" | "down")?, ratio: number?, [number]: Tree }

export type Tab = {
	id: number,
	--- Nil while Tern does not know the tab's layout yet (a tab that opened in this same call).
	root: Tree?,
	--- How many panes float over the tiled tree.
	floats: number?,
}

export type Input = {
	tabs: { Tab },
	--- This plugin's canvases.
	sidebars: { number },
	--- The user hid the sidebar.
	hidden: boolean,
	--- The shared width: the sidebar's share of its tab's width.
	width: number,
}

export type Plan = {
	--- Open a sidebar on the right of `target`, taking `ratio` of the split (`cx.canvas:open`'s ratio is the canvas's
	--- own share of the split, whatever side it takes).
	open: { { tab: number, target: number, ratio: number } },
	--- Close these sidebars, in pane order.
	close: { number },
	--- Bring these sidebars from `width` to the shared width.
	resize: { { pane: number, tab: number, width: number } },
}

--- A sidebar this close to the shared width stays as it is: about one terminal cell of a 100-to-150-column tab,
--- the smallest step a divider moves.
placement.TOLERANCE = 0.008
-- The sidebar's share of the pane it opens beside stays in this range, so that the pane stays usable.
local MIN_RATIO, MAX_RATIO = 0.05, 0.9

-- The sidebar's share of its tab's width until the user drags it.
local DEFAULT_WIDTH = 0.25

--- The shared width: `saved` (the width the user last dragged, as `tern.kv` keeps it) when it is a share of the
--- tab, else the default of 25%.
function placement.sharedWidth(saved: any): number
	if type(saved) == "number" and saved > 0 and saved < 1 then
		return saved
	end
	return DEFAULT_WIDTH
end

--- The share of the tab's width that leaf `pane` takes, or nil when the tree does not hold it.
function placement.width(root: Tree, pane: number): number?
	if root.pane ~= nil then
		return if root.pane == pane then 1 else nil
	end
	local first, second = root[1], root[2]
	if not first or not second then
		return nil
	end
	local ratio = root.ratio or 0.5
	local inFirst = placement.width(first, pane)
	if inFirst then
		return if root.split == "right" then inFirst * ratio else inFirst
	end
	local inSecond = placement.width(second, pane)
	if inSecond then
		return if root.split == "right" then inSecond * (1 - ratio) else inSecond
	end
	return nil
end

--- The tree around sidebar `pane`, as a string: the splits, their ratios and the leaves, with the ratio of the split
--- that holds `pane` itself left out. Two trees with the same shape differ only in where the sidebar's own divider
--- sits, so a change of the sidebar's width between them is the user dragging that divider; any other change
--- (a pane closed, another divider moved, the panes regrouped) gives another shape.
function placement.shape(root: Tree, pane: number): string
	local parts: { string } = {}
	local function walk(node: Tree)
		if node.pane ~= nil then
			table.insert(parts, string.format("%.0f", node.pane))
			return
		end
		local first, second = node[1], node[2]
		local holds = (first and first.pane == pane) or (second and second.pane == pane)
		table.insert(parts, "(" .. tostring(node.split) .. " " .. (if holds then "*" else tostring(node.ratio or 0.5)))
		for _, child in ipairs(node) do
			walk(child)
		end
		table.insert(parts, ")")
	end
	walk(root)
	return table.concat(parts, " ")
end

-- The pane at the top of the tab's right edge: the sidebar opens beside it.
local function topRight(root: Tree): number?
	local node = root
	while node.pane == nil and node[1] do
		node = if node.split == "right" and node[2] then node[2] else node[1]
	end
	return node.pane
end

local function leaves(root: Tree, out: { [number]: boolean })
	if root.pane ~= nil then
		out[root.pane] = true
		return
	end
	for _, child in ipairs(root) do
		leaves(child, out)
	end
end

-- Whether `pane` touches the tab's left edge and not its right one: in every side-by-side split on its way it is
-- the left side, and there is one. Ticket 03 opened the sidebar there, beside the top-left pane.
local function onLeftEdge(root: Tree, pane: number): boolean
	local found, left, sideBySide = false, true, false
	local function walk(node: Tree, onLeft: boolean, split: boolean)
		if node.pane ~= nil then
			if node.pane == pane then
				found, left, sideBySide = true, onLeft, split
			end
			return
		end
		for i, child in ipairs(node) do
			local right = node.split == "right"
			walk(child, onLeft and not (right and i == 2), split or right)
		end
	end
	walk(root, true, false)
	return found and left and sideBySide
end

-- `root` without leaf `pane`: the split that holds it gives its room to the other side.
local function without(root: Tree, pane: number): Tree?
	if root.pane ~= nil then
		return if root.pane == pane then nil else root
	end
	local first, second = root[1], root[2]
	if not first or not second then
		return root
	end
	local a, b = without(first, pane), without(second, pane)
	if not a then
		return b
	elseif not b then
		return a
	end
	return { split = root.split, ratio = root.ratio, [1] = a, [2] = b }
end

function placement.plan(input: Input): Plan
	local out: Plan = { open = {}, close = {}, resize = {} }
	local sidebars = table.clone(input.sidebars)
	table.sort(sidebars)
	if input.hidden then
		out.close = sidebars
		return out
	end
	for _, tab in input.tabs do
		local root = tab.root
		if root then
			local inTab: { [number]: boolean } = {}
			leaves(root, inTab)
			local kept: number? = nil
			for _, pane in sidebars do
				if inTab[pane] then
					if kept then
						table.insert(out.close, pane)
					else
						kept = pane
					end
				end
			end
			if kept and root.pane ~= kept and onLeftEdge(root, kept) then
				-- A copy where the sidebar used to open: it moves to the right edge, in the room it leaves.
				table.insert(out.close, kept)
				root = without(root, kept) :: Tree
				kept = nil
			end
			if kept and root.pane == kept and (tab.floats or 0) == 0 then
				-- The tab holds only the sidebar.
				table.insert(out.close, kept)
			elseif kept and root.pane == kept then
				-- Only the sidebar is tiled, and a pane floats over it: leave the tab as it is.
			elseif kept then
				local width = placement.width(root, kept) or input.width
				if math.abs(width - input.width) > placement.TOLERANCE then
					table.insert(out.resize, { pane = kept, tab = tab.id, width = width })
				end
			else
				local target = topRight(root)
				local share = target and placement.width(root, target)
				if target and share then
					local ratio = math.clamp(input.width / share, MIN_RATIO, MAX_RATIO)
					table.insert(out.open, { tab = tab.id, target = target, ratio = ratio })
				end
			end
		end
	end
	table.sort(out.close)
	return out
end

return placement
