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

local function hasRow(n: Node): boolean
	for _, child in kids(n) do
		if child.k == "row" or hasRow(child) then
			return true
		end
	end
	return false
end

local function render(n: Node, out: { string })
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

-- The kind of a list row (`item`, `on`, `folder`, `fold`, `head`, `info`) and its depth in the tree, from its
-- role `agents.<kind>.<depth>`.
local function kindOf(row: Node): (string?, number?)
	local role = props(row).role
	if type(role) ~= "string" then
		return nil, nil
	end
	local kind, depth = string.match(role, "^agents%.(%a+)%.(%d+)$")
	return kind, tonumber(depth)
end

--- Like `rows`, without the section heads and folder rows: the agent, subagent, info and Older rows.
function visible.agentRows(view: Node): { string }
	local out: { string } = {}
	for _, row in rowNodes(view) do
		local kind = kindOf(row)
		if kind ~= "head" and kind ~= "folder" then
			table.insert(out, line(row))
		end
	end
	return out
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
--- writes a row), or nil when it has no card.
function visible.hover(view: Node, text: string): string?
	local card = props(findRow(view, text)).hovercard
	if card == nil then
		return nil
	end
	local out: { string } = {}
	for _, child in kids(card) do
		table.insert(out, line(child))
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

-- Whether the state dot of `row` takes Tern's `pulse` effect.
local function dotPulses(row: Node): boolean
	for _, child in kids(row) do
		local p = props(child)
		if p.role == "agents.dot" and type(p.spans) == "table" then
			for _, span in p.spans do
				if type(span) == "table" and span.fx == "pulse" then
					return true
				end
			end
		end
	end
	return false
end

--- The rows whose state dot pulses (a live agent or subagent), one line each.
function visible.pulsing(view: Node): { string }
	local out: { string } = {}
	for _, row in rowNodes(view) do
		if dotPulses(row) then
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

--- The action a click on the first button in the row that shows `text` sends, or nil when it has no button.
function visible.button(view: Node, text: string): string?
	for _, child in kids(findRow(view, text)) do
		if child.k == "button" then
			local actions = props(child).actions
			return actions and actions.click
		end
	end
	return nil
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

--- What the dropdown `menu` node of `view` offers when clicked, one line per item as `menu` writes them.
function visible.dropdown(view: Node): { string }
	local node = visible.find(view, "menu")
	if not node then
		error("the view has no dropdown menu", 2)
	end
	return menuLines(props(node).items or {})
end

--- The action a click on the button with tooltip `title` anywhere in `view` sends.
function visible.press(view: Node, title: string): string?
	local function walk(n: Node): string?
		local p = props(n)
		if n.k == "button" and p.title == title then
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

--- The tooltip of the view button drawn as the one shown (role `agents.view.on`), or nil.
function visible.shownView(view: Node): string?
	local function walk(n: Node): string?
		local p = props(n)
		if p.role == "agents.view.on" then
			return p.title
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

--- Whether the row that shows `text` draws that text dimmed.
function visible.dimmed(view: Node, text: string): boolean
	local found = false
	local function walk(n: Node)
		local spans = props(n).spans
		if type(spans) == "table" then
			for _, span in spans do
				if type(span) == "table" and type(span.t) == "string" and string.find(span.t, text, 1, true) then
					found = found or string.find(" " .. tostring(span.s) .. " ", " dim ", 1, true) ~= nil
				end
			end
		end
		for _, child in kids(n) do
			walk(child)
		end
	end
	walk(findRow(view, text))
	return found
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
