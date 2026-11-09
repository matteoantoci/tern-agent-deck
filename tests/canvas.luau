--!strict
-- A stand-in for a Tern canvas: applies a `cx.canvas:set` change to a view as the API reference describes it.
-- `set` patches paths below the root: keyed children use their keys, unkeyed children their zero-based index,
-- joined by `.`; `false` removes a node; a new key appends below an existing parent; an unknown parent raises.

local canvas = {}

type Node = { k: string, p: { [string]: any }?, c: { Node }? }

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = copy(v)
	end
	return out
end

local function childIndex(parent: Node, segment: string): number?
	local children: { Node } = parent.c or {}
	for i, child in children do
		local key = child.p and child.p.key
		if key == segment or (key == nil and tostring(i - 1) == segment) then
			return i
		end
	end
	return nil
end

--- The view a canvas shows after `change` lands on `view`.
function canvas.apply(view: Node, change: any): Node
	if change.view then
		return copy(change.view)
	end
	local root = copy(view)
	local paths = {}
	for path in change.set or {} do
		table.insert(paths, path)
	end
	table.sort(paths)
	for _, path in paths do
		local segments = string.split(path, ".")
		local parent = root
		for i = 1, #segments - 1 do
			local index = childIndex(parent, segments[i])
			if not index then
				error("unknown parent in path " .. path, 2)
			end
			parent = (parent.c :: { Node })[index]
		end
		local last = segments[#segments]
		local node = change.set[path]
		local index = childIndex(parent, last)
		parent.c = parent.c or {}
		local children = parent.c :: { Node }
		if node == false then
			if index then
				table.remove(children, index)
			end
		elseif index then
			children[index] = copy(node)
		else
			table.insert(children, copy(node))
		end
	end
	return root
end

return canvas
