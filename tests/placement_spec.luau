--!strict
-- Where the sidebar copies go: one on the right edge of every tab (Tern's Files pane takes the left edge), at one
-- shared width, none while hidden.
local t = require("./harness")
local placement = require("../lib/placement")

type Tree = { pane: number?, split: ("right" | "down")?, ratio: number?, [number]: Tree }

local function leaf(pane: number): Tree
	return { pane = pane }
end

-- A split's `ratio` is its first child's share, as `cx.session:layout` gives it.
local function right(ratio: number, a: Tree, b: Tree): Tree
	return { split = "right", ratio = ratio, [1] = a, [2] = b }
end

local function down(ratio: number, a: Tree, b: Tree): Tree
	return { split = "down", ratio = ratio, [1] = a, [2] = b }
end

local function plan(tabs: { any }, sidebars: { number }, fields: { [string]: any }?): placement.Plan
	local input: { [string]: any } = { tabs = tabs, sidebars = sidebars, hidden = false, width = 0.2 }
	for k, v in (fields or {}) :: { [string]: any } do
		input[k] = v
	end
	return placement.plan(input :: any)
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

local NOTHING = { open = {}, close = {}, resize = {} }

t.test("a tab without a sidebar gets one on the right of its pane, at the shared width", function()
	-- `cx.canvas:open`'s ratio is the canvas's own share of the split it opens in, whatever its side.
	t.eq(plan({ { id = 1, root = leaf(10) } }, {}), {
		open = { { tab = 1, target = 10, ratio = 0.2 } },
		close = {},
		resize = {},
	})
end)

t.test("in a tab of several panes the sidebar opens beside the top-right pane and still takes the shared width", function()
	-- The top-right pane 11 is half the tab wide: a fifth of the tab is two fifths of that pane.
	local root = right(0.5, leaf(10), down(0.5, leaf(11), leaf(12)))
	local out = plan({ { id = 1, root = root } }, {})
	t.eq(out.open[1].target, 11)
	t.eq(near(out.open[1].ratio, 0.4), true, "ratio 0.4")
end)

t.test("every tab without a sidebar gets one, and a tab that has one gets nothing", function()
	local out = plan({
		{ id = 1, root = right(0.8, leaf(10), leaf(90)) },
		{ id = 2, root = leaf(20) },
		{ id = 3, root = leaf(30) },
	}, { 90 })
	t.eq(out, {
		open = { { tab = 2, target = 20, ratio = 0.2 }, { tab = 3, target = 30, ratio = 0.2 } },
		close = {},
		resize = {},
	})
end)

t.test("a tab with two sidebars keeps the older one", function()
	local root = right(0.8, right(0.75, leaf(10), leaf(95)), leaf(90))
	local out = plan({ { id = 1, root = root } }, { 95, 90 })
	t.eq(out.close, { 95 })
	t.eq(out.open, {})
end)

t.test("a tab that holds only the sidebar closes it", function()
	t.eq(plan({ { id = 1, root = leaf(90) } }, { 90 }), { open = {}, close = { 90 }, resize = {} })
end)

t.test("a tab whose only tiled pane is the sidebar keeps it while a pane floats over it", function()
	t.eq(plan({ { id = 1, root = leaf(90), floats = 1 } }, { 90 }), NOTHING)
end)

t.test("a copy on the left edge (where the sidebar used to open) closes, and one opens on the right edge", function()
	t.eq(plan({ { id = 1, root = right(0.2, leaf(90), leaf(10)) } }, { 90 }), {
		open = { { tab = 1, target = 10, ratio = 0.2 } },
		close = { 90 },
		resize = {},
	})
	-- The new copy takes the shared width of the tab as it is once the old copy has gone: 11 then takes half of it.
	local out = plan({ { id = 1, root = right(0.5, right(0.3, leaf(90), leaf(10)), leaf(11)) } }, { 90 })
	t.eq(out.close, { 90 })
	t.eq(out.open[1].target, 11)
	t.eq(near(out.open[1].ratio, 0.4), true, "ratio 0.4")
end)

t.test("a copy the user moved between two panes stays where it is", function()
	t.eq(plan({ { id = 1, root = right(0.4, leaf(10), right(0.33, leaf(90), leaf(11))) } }, { 90 }, { width = 0.2 }), NOTHING)
end)

t.test("dragging the sidebar's own divider keeps the tree's shape; other layout changes do not", function()
	-- The sidebar 90 opened beside 11 when the tab was 10 | 11.
	local before = placement.shape(right(0.5, leaf(10), right(0.5, leaf(11), leaf(90))), 90)
	t.eq(placement.shape(right(0.5, leaf(10), right(0.7, leaf(11), leaf(90))), 90), before, "the sidebar edge dragged")
	t.eq(placement.shape(right(0.5, leaf(11), leaf(90)), 90) == before, false, "pane 10 closed")
	t.eq(placement.shape(right(0.3, leaf(10), right(0.5, leaf(11), leaf(90))), 90) == before, false, "10 | 11 dragged")
	t.eq(placement.shape(right(0.5, leaf(11), right(0.5, leaf(10), leaf(90))), 90) == before, false, "panes regrouped")
end)

t.test("while hidden, every sidebar closes and no tab gets one", function()
	local out = plan({ { id = 1, root = right(0.8, leaf(10), leaf(90)) }, { id = 2, root = leaf(20) } }, { 90, 77 }, {
		hidden = true,
	})
	t.eq(out, { open = {}, close = { 77, 90 }, resize = {} })
end)

t.test("a tab whose layout is not known yet is left alone", function()
	t.eq(plan({ { id = 1 } }, {}), NOTHING)
end)

t.test("a sidebar that is not at the shared width is resized to it", function()
	local out = plan({
		{ id = 1, root = right(0.7, leaf(10), leaf(90)) },
		{ id = 2, root = right(0.798, leaf(20), leaf(91)) },
	}, { 90, 91 })
	t.eq(#out.resize, 1, "only the tab off by more than a cell")
	t.eq(out.resize[1].pane, 90)
	t.eq(out.resize[1].tab, 1)
	t.eq(near(out.resize[1].width, 0.3), true, "the sidebar's own share, not its split's ratio")
end)

t.test("a sidebar's width is its share of the whole tab", function()
	-- The sidebar takes half of the right half.
	local root = right(0.5, leaf(11), right(0.5, leaf(10), leaf(90)))
	t.eq(placement.width(root, 90), 0.25)
	t.eq(placement.width(root, 11), 0.5)
	t.eq(placement.width(root, 42), nil)
end)

t.test("a sidebar that would need the whole pane opens at most nine tenths of it", function()
	local root = right(0.9, leaf(10), leaf(11))
	t.eq(plan({ { id = 1, root = root } }, {}).open[1].ratio, 0.9)
end)

t.test("until the user drags it, the sidebar takes 25% of its tab; a saved width wins", function()
	t.eq(placement.sharedWidth(nil), 0.25)
	t.eq(placement.sharedWidth(0.31), 0.31)
	t.eq(placement.sharedWidth(0), 0.25, "no share")
	t.eq(placement.sharedWidth(1), 0.25, "the whole tab")
	t.eq(placement.sharedWidth("0.3"), 0.25, "not a number")
end)

return nil
