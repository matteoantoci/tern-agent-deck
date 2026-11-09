--!strict
-- Works out what a canvas must receive to go from the view it shows to a new one: nothing when both look the
-- same, else a keyed `cx.canvas:set` patch of the changed nodes, or the whole view when a patch cannot say it.
-- Pure: no Tern calls.

local patch = {}

export type Node = { k: string, p: { [string]: any }?, c: { Node }? }

export type Change = { view: Node?, set: { [string]: Node | false }? }

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- The `now` each view was built at: an `elapsed` node counts from `now - age`, so two timers that started at
-- the same moment look the same although their `age` differs.
type Clocks = { old: number, new: number }

-- Whether two values look the same: tables key by key, and an `elapsed` node by the moment it started rather
-- than by its `age`, also inside a prop (the turn timer lives in an agent row's hover card).
local function same(a: any, b: any, clocks: Clocks): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	local timer = a.k == "elapsed" and b.k == "elapsed" and type(a.p) == "table" and type(b.p) == "table"
	for k, v in a do
		if not (timer and k == "p") and not same(v, b[k], clocks) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	if not timer then
		return true
	end
	local pa: { [string]: any }, pb: { [string]: any } = a.p, b.p
	for k, v in pa do
		if k ~= "age" and not same(v, pb[k], clocks) then
			return false
		end
	end
	for k in pb do
		if k ~= "age" and pa[k] == nil then
			return false
		end
	end
	local ageA, ageB = tonumber(pa.age), tonumber(pb.age)
	if ageA == nil or ageB == nil then
		return ageA == ageB
	end
	return math.abs((clocks.old - ageA) - (clocks.new - ageB)) < 1
end

-- Whether the node's own kind and props (not its children) look the same in both views.
local function sameHead(a: Node, b: Node, clocks: Clocks): boolean
	return a.k == b.k and same({ k = a.k, p = a.p or {} }, { k = b.k, p = b.p or {} }, clocks)
end

local function sameNode(a: Node, b: Node, clocks: Clocks): boolean
	if not sameHead(a, b, clocks) then
		return false
	end
	local ca: { Node }, cb: { Node } = a.c or {}, b.c or {}
	if #ca ~= #cb then
		return false
	end
	for i, child in ca do
		if not sameNode(child, cb[i], clocks) then
			return false
		end
	end
	return true
end

-- The path segment of each child: its key, or its zero-based index when it has none. Nil when a segment
-- cannot name the child (a key with a `.`, or a key used twice); `keyed` is false when one child has no key.
local function segments(children: { Node }): ({ string }?, boolean)
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local keyed = true
	for i, child in children do
		local key = child.p and child.p.key
		local segment: string
		if key == nil then
			keyed = false
			segment = tostring(i - 1)
		elseif type(key) == "string" and not string.find(key, ".", 1, true) then
			segment = key
		else
			return nil, false
		end
		if seen[segment] then
			return nil, false
		end
		seen[segment] = true
		table.insert(out, segment)
	end
	return out, keyed
end

-- Adds to `set` the patches that turn `old`'s children into `new`'s, below `prefix`. False, with nothing written,
-- when a patch cannot express the change: a moved child, a child inserted before an old one, more than one new
-- child (Tern appends each new key of a `set`, and a `set` is a table, so their order would be lost), or unkeyed
-- children that shift. Below the root, only containers whose children all have keys are patched inside (a row
-- goes whole).
local function diffChildren(old: Node, new: Node, prefix: string, set: { [string]: Node | false }, clocks: Clocks): boolean
	local oldChildren: { Node }, newChildren: { Node } = old.c or {}, new.c or {}
	local oldIds, oldKeyed = segments(oldChildren)
	local newIds, newKeyed = segments(newChildren)
	if not oldIds or not newIds then
		return false
	end
	if prefix ~= "" and (not oldKeyed or not newKeyed) then
		return false
	end
	if (not oldKeyed or not newKeyed) and not deepEqual(oldIds, newIds) then
		return false
	end
	local oldAt: { [string]: number } = {}
	for i, segment in oldIds do
		oldAt[segment] = i
	end
	local newAt: { [string]: number } = {}
	-- Kept children must stay in their old order, and one new child at most may follow the last kept one.
	local lastOld, added = 0, 0
	for i, segment in newIds do
		newAt[segment] = i
		local at = oldAt[segment]
		if at then
			if added > 0 or at < lastOld then
				return false
			end
			lastOld = at
		else
			added += 1
			if added > 1 then
				return false
			end
		end
	end
	for _, segment in oldIds do
		if not newAt[segment] then
			set[prefix .. segment] = false
		end
	end
	for i, child in newChildren do
		local segment = newIds[i]
		local at = oldAt[segment]
		local path = prefix .. segment
		if not at then
			set[path] = child
		else
			local was = oldChildren[at]
			if not sameNode(was, child, clocks) then
				-- A level that cannot be patched returns before it writes to `set`.
				if not (sameHead(was, child, clocks) and diffChildren(was, child, path .. ".", set, clocks)) then
					set[path] = child
				end
			end
		end
	end
	return true
end

--- The change that takes a canvas from `old` (built at `oldNow`, nil when nothing was sent yet) to `new` (built
--- at `newNow`): nil when it looks the same, else `{set = …}` with only the changed nodes, or `{view = new}`.
function patch.diff(old: Node?, oldNow: number, new: Node, newNow: number): Change?
	if old == nil then
		return { view = new }
	end
	local clocks = { old = oldNow, new = newNow }
	if not sameHead(old, new, clocks) then
		return { view = new }
	end
	local set: { [string]: Node | false } = {}
	if not diffChildren(old, new, "", set, clocks) then
		return { view = new }
	end
	if next(set) == nil then
		return nil
	end
	return { set = set }
end

return patch
