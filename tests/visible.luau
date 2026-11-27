--!strict
-- Reads a canvas node tree the way a user sees it: the text of every node, the rows as one line each,
-- what a row's hover card shows and what a click on it does.

local visible = {}

type Node = { k: string, p: { [string]: any }?, c: { Node }? }

local function spanText(spans: any): string
	if type(spans) == "string" then
		return spans
	end
	if type(spans) ~= "table" then
		return ""
	end
	if type(spans.t) == "string" then
		return spans.t
	end
	local out = {}
	for _, span in spans do
		table.insert(out, spanText(span))
	end
	return table.concat(out)
end

local function nodeText(n: Node): string
	local p = n.p
	if not p then
		return ""
	end
	if p.spans ~= nil then
		return spanText(p.spans)
	elseif type(p.text) == "string" then
		if n.k == "empty" and type(p.title) == "string" then
			return p.title .. "\n" .. p.text
		end
		return p.text
	end
	return ""
end

-- The sidebar's own head and view strip: they sit above the list, so the list helpers skip them.
local CHROME = "agents.chrome"

local function isChrome(n: Node): boolean
	return n.p ~= nil and n.p.role == CHROME
end

--- Every non-empty text line of `node` and its children, in order, the head and view strip left out.
function visible.lines(node: Node): { string }
	local out: { string } = {}
	local function walk(n: Node)
		if isChrome(n) then
			return
		end
		local line = nodeText(n)
		if line ~= "" then
			table.insert(out, line)
		end
		if n.c then
			for _, child in n.c do
				walk(child)
			end
		end
	end
	walk(node)
	return out
end

local function props(n: Node): { [string]: any }
	return n.p or {}
end

local function kids(n: Node): { Node }
	return n.c or {}
end

-- One part of a row as the user sees it: text as written, an icon as `:name`, a badge as its text, a live
-- timer as `⏱` and the whole seconds it shows when it arrives, a thinking-effort glyph as `◔` and its level, a
-- button as its label or icon in brackets. A node's accessible name (`aria`) or tooltip follows it in parentheses.
local function part(n: Node): string?
	local p = props(n)
	local shown: string?
	if n.k == "icon" then
		shown = ":" .. tostring(p.name)
	elseif n.k == "elapsed" then
		shown = "⏱" .. tostring(math.floor((tonumber(p.age) or 0) / 1000)) .. "s"
	elseif n.k == "effort" then
		shown = "◔" .. tostring(p.level)
	elseif n.k == "spinner" then
		shown = "…"
	elseif n.k == "button" then
		local label = if type(p.text) == "string" and p.text ~= "" then p.text else ":" .. tostring(p.icon)
		shown = "[" .. label .. "]"
	elseif n.k == "menu" then
		shown = "[⋯]"
	else
		local text = nodeText(n)
		if text ~= "" then
			shown = text
		end
	end
	local named = if type(p.aria) == "string" then p.aria elseif type(p.title) == "string" then p.title else nil
	if shown and named then
		shown ..= "(" .. named .. ")"
	end
	return shown
end

-- A row inside a row that takes a click and is no list row (no `agents.<kind>.<depth>` role): a control of its row,
-- as a button is (the subagent strip), not a row of its own.
local function isControl(n: Node): boolean
	local p = props(n)
	local role = p.role
	return n.k == "row"
		and p.actions ~= nil
		and p.actions.click ~= nil
		and not (type(role) == "string" and string.match(role, "^agents%.%a+%.%d+$"))
end

local function hasRow(n: Node): boolean
	for _, child in kids(n) do
		if (child.k == "row" and not isControl(child)) or hasRow(child) then
			return true
		end
	end
	return false
end

-- A control shows as its parts in brackets, as a button does; its tooltip is left out (`titles` reads it).
local function render(n: Node, out: { string })
	if isControl(n) then
		local inner: { string } = {}
		for _, child in kids(n) do
			render(child, inner)
		end
		table.insert(out, "[" .. table.concat(inner, " ") .. "]")
		return
	end
	local shown = part(n)
	if shown then
		table.insert(out, shown)
	end
	for _, child in kids(n) do
		render(child, out)
	end
end

-- Every innermost row below `view`, in order; with `chrome`, the rows of the head and view strip instead.
local function rowNodes(view: Node, chrome: boolean?): { Node }
	local out: { Node } = {}
	local function walk(n: Node, inChrome: boolean)
		inChrome = inChrome or isChrome(n)
		if n.k == "row" and not hasRow(n) then
			if inChrome == (chrome == true) then
				table.insert(out, n)
			end
			return
		end
		for _, child in kids(n) do
			walk(child, inChrome)
		end
	end
	walk(view, false)
	return out
end

local function line(row: Node): string
	local parts: { string } = {}
	render(row, parts)
	return table.concat(parts, " ")
end

--- Every innermost row, in order, as one line of its parts joined by spaces.
function visible.rows(view: Node): { string }
	local out: { string } = {}
	for _, row in rowNodes(view) do
		table.insert(out, line(row))
	end
	return out
end

-- The kind of a list row (`item`, `on`, `head`, `label`, `folder`, `fold`, `info`) and its depth in the tree, from
-- its role `agents.<kind>.<depth>`.
local function kindOf(row: Node): (string?, number?)
	local role = props(row).role
	if type(role) ~= "string" then
		return nil, nil
	end
	local kind, depth = string.match(role, "^agents%.(%a+)%.(%d+)$")
	return kind, tonumber(depth)
end

--- Like `rows`, without the zone heads, project labels and folder rows: the agent, subagent, info and Older rows.
function visible.agentRows(view: Node): { string }
	local out: { string } = {}
	for _, row in rowNodes(view) do
		local kind = kindOf(row)
		if kind ~= "head" and kind ~= "label" and kind ~= "folder" then
			table.insert(out, line(row))
		end
	end
	return out
end

-- The Live view's zones (Needs you, Working, Idle): each a block whose first row is its head.
local ZONE = "agents.zone"

local function zoneNodes(view: Node): { Node }
	local out: { Node } = {}
	local function walk(n: Node)
		if props(n).role == ZONE then
			table.insert(out, n)
			return
		end
		for _, child in kids(n) do
			walk(child)
		end
	end
	walk(view)
	return out
end

--- The heads of the Live view's zones, in order, one line each.
function visible.zones(view: Node): { string }
	local out: { string } = {}
	for _, zone in zoneNodes(view) do
		table.insert(out, line(rowNodes(zone)[1]))
	end
	return out
end

--- The rows of the zone whose head shows `name`, its head left out, one line each as `rows` writes them.
function visible.zone(view: Node, name: string): { string }
	for _, zone in zoneNodes(view) do
		local rows = rowNodes(zone)
		if string.find(line(rows[1]), name, 1, true) then
			local out: { string } = {}
			for i = 2, #rows do
				table.insert(out, line(rows[i]))
			end
			return out
		end
	end
	error("no zone shows " .. string.format("%q", name), 2)
end

--- Like `rows`, each line indented two spaces per level of the tree the row sits at.
function visible.tree(view: Node): { string }
	local out: { string } = {}
	for _, row in rowNodes(view) do
		local _, depth = kindOf(row)
		table.insert(out, string.rep("  ", depth or 0) .. line(row))
	end
	return out
end

--- The rows of the sidebar's head and view strip, one line each.
function visible.chrome(view: Node): { string }
	local out: { string } = {}
	for _, row in rowNodes(view, true) do
		table.insert(out, line(row))
	end
	return out
end

local function findRow(view: Node, text: string): Node
	for _, row in rowNodes(view) do
		if string.find(line(row), text, 1, true) then
			return row
		end
	end
	error("no row shows " .. string.format("%q", text), 3)
end

--- What the hover card of the row that shows `text` holds, one line per part of the card (each line as `rows`
--- writes a row; each item of a key/value grid as its key and value), or nil when it has no card.
function visible.hover(view: Node, text: string): string?
	local card = props(findRow(view, text)).hovercard
	if card == nil then
		return nil
	end
	local out: { string } = {}
	for _, child in kids(card) do
		if child.k == "kv" then
			for _, item in props(child).items or {} do
				table.insert(out, spanText(item.k) .. " " .. spanText(item.v))
			end
		else
			table.insert(out, line(child))
		end
	end
	return table.concat(out, "\n")
end

--- The parts of the row that shows `text` that show only while the pointer is on the row.
function visible.onHover(view: Node, text: string): { string }
	local out: { string } = {}
	for _, child in kids(findRow(view, text)) do
		local role = props(child).role
		if role == "agents.count" or role == "agents.hover" then
			table.insert(out, part(child) or "")
		end
	end
	return out
end

--- Every tooltip (`title`) the row that shows `text` and its parts carry, in order.
function visible.titles(view: Node, text: string): { string }
	local out: { string } = {}
	local function walk(n: Node)
		local title = props(n).title
		if type(title) == "string" then
			table.insert(out, title)
		end
		for _, child in kids(n) do
			walk(child)
		end
	end
	walk(findRow(view, text))
	return out
end

--- The rows drawn as selected (the focused agent's), one line each.
function visible.selected(view: Node): { string }
	local out: { string } = {}
	for _, row in rowNodes(view) do
		if kindOf(row) == "on" then
			table.insert(out, line(row))
		end
	end
	return out
end

-- The span styles that `agents.css` keeps in the mono face; every other text of the canvas is sans.
local MONO_STYLES = { "path", "mono", "num", "code", "key" }

local function monoSpans(spans: any): boolean
	if type(spans) ~= "table" then
		return false
	end
	for _, span in spans do
		local style = " " .. tostring(type(span) == "table" and span.s or "") .. " "
		for _, mono in MONO_STYLES do
			if string.find(style, " " .. mono .. " ", 1, true) then
				return true
			end
		end
	end
	return false
end

--- The face of the text node that shows exactly `text`: "sans" or "mono". `agents.css` sets the whole canvas
--- (role `agents.root`) in the sans face and keeps machine strings (`path`, `mono`, … spans) mono.
function visible.face(view: Node, text: string): string
	local found: string? = nil
	local function walk(n: Node)
		if found == nil and n.k == "text" and nodeText(n) == text then
			found = if monoSpans(props(n).spans) then "mono" else "sans"
		end
		for _, child in kids(n) do
			walk(child)
		end
		local card = props(n).hovercard
		if type(card) == "table" then
			walk(card)
		end
	end
	if props(view).role ~= "agents.root" then
		error("the view is not the sidebar's root", 2)
	end
	walk(view)
	if not found then
		error("no text shows " .. string.format("%q", text), 2)
	end
	return found :: string
end

--- The action a click on the row that shows `text` sends, or nil.
function visible.click(view: Node, text: string): string?
	local actions = props(findRow(view, text)).actions
	return actions and actions.click
end

-- The state that `role` carries (`agents.glyph.<state>` for a title icon, `agents.square.<state>` for a zone head's
-- or a subagent line's square, `agents.dot.<state>` for a state dot, `agents.mark.<state>` for a state icon,
-- `agents.bar.<state>` for a bar of the subagent strip), or nil.
local STATE_PARTS = { glyph = true, square = true, dot = true, mark = true, bar = true }

local function stateOf(role: any): string?
	if type(role) ~= "string" then
		return nil
	end
	local part, state = string.match(role, "^agents%.(%a+)%.(%a+)$")
	if part and STATE_PARTS[part] then
		return state
	end
	return nil
end

--- The state of the first state dot or state icon in the row that shows `text` (`working`, `done`, …), or nil.
function visible.state(view: Node, text: string): string?
	for _, child in kids(findRow(view, text)) do
		local state = stateOf(props(child).role)
		if state then
			return state
		end
	end
	return nil
end

--- Each row that has a state dot or state icon, as `<state>: <row line>`, in order.
function visible.states(view: Node): { string }
	local out: { string } = {}
	for _, row in rowNodes(view) do
		for _, child in kids(row) do
			local state = stateOf(props(child).role)
			if state then
				table.insert(out, state .. ": " .. line(row))
				break
			end
		end
	end
	return out
end

-- Collects into `out` each color a state dot, state icon or end mark in `n` takes from Tern: a `tone`, or a span style.
local function collectStateColors(n: Node, out: { string })
	local p = props(n)
	if stateOf(p.role) or p.role == "agents.status" then
		if p.tone then
			table.insert(out, p.role .. " tone=" .. tostring(p.tone))
		end
		if type(p.spans) == "table" then
			for _, span in p.spans do
				if type(span) == "table" and span.s then
					table.insert(out, p.role .. " s=" .. tostring(span.s))
				end
			end
		end
	end
	for _, child in kids(n) do
		collectStateColors(child, out)
	end
end

--- Every Tern color (a tone or a span style) on a state dot, state icon or end mark in `view`: empty when each state
--- gets its color from `agents.css` only.
function visible.stateColors(view: Node): { string }
	local out: { string } = {}
	collectStateColors(view, out)
	return out
end

--- The action a click on the first button or control (the subagent strip) in the row that shows `text` sends, or
--- nil when it has none.
function visible.button(view: Node, text: string): string?
	for _, child in kids(findRow(view, text)) do
		if child.k == "button" or isControl(child) then
			local actions = props(child).actions
			return actions and actions.click
		end
	end
	return nil
end

--- The state of each bar of the subagent strip in the row that shows `text`, in order; empty when it has none.
function visible.bars(view: Node, text: string): { string }
	local out: { string } = {}
	local function walk(n: Node)
		local role = props(n).role
		if type(role) == "string" and string.match(role, "^agents%.bar%.") then
			table.insert(out, stateOf(role) or "?")
		end
		for _, child in kids(n) do
			walk(child)
		end
	end
	walk(findRow(view, text))
	return out
end

-- Menu items, one line each: the label and the action, and why it is off when it is disabled.
local function menuLines(items: { any }): { string }
	local out: { string } = {}
	for _, item in items do
		if type(item) == "string" then
			table.insert(out, item)
		else
			local shown = tostring(item.label) .. " → " .. tostring(item.id)
			if item.disabled then
				shown ..= " (off: " .. tostring(item.disabled) .. ")"
			end
			table.insert(out, shown)
		end
	end
	return out
end

--- What a right-click on the row that shows `text` offers, one line per item.
function visible.menu(view: Node, text: string): { string }
	local actions = props(findRow(view, text)).actions
	return menuLines((actions and actions.menu or {}) :: { any })
end

--- The icon of the item labeled `label` in the right-click menu of the row that shows `text`, or nil.
function visible.menuIcon(view: Node, text: string, label: string): string?
	local actions = props(findRow(view, text)).actions
	for _, item in (actions and actions.menu or {}) :: { any } do
		if type(item) == "table" and item.label == label then
			return item.icon
		end
	end
	return nil
end

--- The first node of kind `kind` anywhere in `view`, or nil.
function visible.find(view: Node, kind: string): Node?
	if view.k == kind then
		return view
	end
	for _, child in kids(view) do
		local found = visible.find(child, kind)
		if found then
			return found
		end
	end
	return nil
end

--- The action a click on the button with tooltip or label `title` anywhere in `view` sends.
function visible.press(view: Node, title: string): string?
	local function walk(n: Node): string?
		local p = props(n)
		if n.k == "button" and (p.title == title or p.text == title) then
			return p.actions and p.actions.click
		end
		for _, child in kids(n) do
			local found = walk(child)
			if found then
				return found
			end
		end
		return nil
	end
	return walk(view)
end

--- The label of the view button drawn as the one shown (role `agents.view.on`), or nil.
function visible.shownView(view: Node): string?
	local function walk(n: Node): string?
		local p = props(n)
		if p.role == "agents.view.on" then
			return p.text
		end
		for _, child in kids(n) do
			local found = walk(child)
			if found then
				return found
			end
		end
		return nil
	end
	return walk(view)
end

--- Whether the row that shows `text` draws that text as its secondary part: in the detail (role `agents.detail`),
--- with no span style of its own, so that `agents.css` sets its color, size and weight.
function visible.secondary(view: Node, text: string): boolean
	for _, child in kids(findRow(view, text)) do
		local p = props(child)
		if p.role == "agents.detail" and p.spans == nil and nodeText(child) == text then
			return true
		end
	end
	return false
end

return visible
