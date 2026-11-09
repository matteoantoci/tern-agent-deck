--!strict
-- What a sidebar canvas receives when the view changes: nothing when it looks the same, else a keyed `set`
-- patch of the changed nodes, or the whole view when a patch cannot express the change.
local t = require("./harness")
local canvas = require("./canvas")
local patch = require("../lib/patch")

type Node = { k: string, p: { [string]: any }?, c: { Node }? }

local function row(key: string, text: string): Node
	return { k = "row", p = { key = key }, c = { { k = "text", p = { text = text } } } }
end

local function col(children: { Node }): Node
	return { k = "col", c = children }
end

t.test("a canvas with nothing sent yet gets the whole view", function()
	local view = col({ row("agent-1", "a") })
	t.eq(patch.diff(nil, 0, view, 0), { view = view })
end)

t.test("a view that looks the same sends nothing", function()
	t.eq(patch.diff(col({ row("agent-1", "a") }), 0, col({ row("agent-1", "a") }), 5000), nil)
end)

t.test("a changed row is patched into the view the canvas shows", function()
	local old = col({ row("agent-1", "a"), row("agent-2", "b"), row("agent-3", "c") })
	local new = col({ row("agent-1", "a"), row("agent-2", "B"), row("agent-3", "c") })
	local change = patch.diff(old, 0, new, 0)
	t.eq(canvas.apply(old, change), new)
end)

t.test("a row that left is removed, and a new row is appended, by a patch", function()
	local old = col({ row("agent-1", "a"), row("agent-2", "b") })
	local new = col({ row("agent-2", "b"), row("agent-3", "c") })
	local change = patch.diff(old, 0, new, 0)
	t.eq(canvas.apply(old, change), new)
end)

t.test("a row inserted before an old one sends the whole view", function()
	local old = col({ row("agent-1", "a"), row("agent-3", "c") })
	local new = col({ row("agent-1", "a"), row("agent-2", "b"), row("agent-3", "c") })
	t.eq(patch.diff(old, 0, new, 0), { view = new })
end)

t.test("rows that swap places send the whole view", function()
	local old = col({ row("agent-1", "a"), row("agent-2", "b") })
	local new = col({ row("agent-2", "b"), row("agent-1", "a") })
	t.eq(patch.diff(old, 0, new, 0), { view = new })
end)

t.test("two rows that arrive at once send the whole view: a patch cannot say their order", function()
	local old = col({ row("agent-1", "a") })
	local new = col({ row("agent-1", "a"), row("agent-2", "b"), row("agent-3", "c") })
	t.eq(patch.diff(old, 0, new, 0), { view = new })
	local empty = col({ row("empty", "No recent sessions") })
	local folders = col({ row("repo-b", "b"), row("repo-a", "a") })
	t.eq(patch.diff(empty, 0, folders, 0), { view = folders })
end)

t.test("unkeyed nodes that change into rows send the whole view", function()
	local old = col({ { k = "text", p = { text = "No agents running" } } })
	local new = col({ row("agent-1", "a") })
	t.eq(patch.diff(old, 0, new, 0), { view = new })
end)

t.test("a changed unkeyed node is sent by its index", function()
	local old = col({ { k = "text", p = { text = "x" } }, { k = "text", p = { text = "y" } } })
	local new = col({ { k = "text", p = { text = "x" } }, { k = "text", p = { text = "z" } } })
	local change = patch.diff(old, 0, new, 0)
	t.eq(canvas.apply(old, change), new)
end)

local function timer(key: string, age: number): Node
	return { k = "row", p = { key = key }, c = { { k = "elapsed", p = { age = age } } } }
end

t.test("a timer that keeps counting from the same start sends nothing", function()
	-- Built at 10 s with 4 s elapsed, then at 15 s with 9 s elapsed: both started at 6 s.
	t.eq(patch.diff(col({ timer("agent-1", 4000) }), 10000, col({ timer("agent-1", 9000) }), 15000), nil)
end)

t.test("a timer that starts again is sent", function()
	local new = col({ timer("agent-1", 0) })
	t.eq(patch.diff(col({ timer("agent-1", 4000) }), 10000, new, 15000), { set = { ["agent-1"] = timer("agent-1", 0) } })
end)

local function section(key: string, rows: { Node }): Node
	return { k = "section", p = { key = key, head = key }, c = rows }
end

-- A row whose hover card holds the timer (the row itself shows none).
local function carded(key: string, age: number): Node
	local parts: { Node } = { { k = "text", p = { text = "Working for" } }, { k = "elapsed", p = { age = age } } }
	local card: Node = { k = "row", c = parts }
	return { k = "row", p = { key = key, hovercard = card }, c = { { k = "text", p = { text = "a" } } } }
end

t.test("a timer in a hover card that keeps counting from the same start sends nothing", function()
	t.eq(patch.diff(col({ carded("agent-1", 4000) }), 10000, col({ carded("agent-1", 9000) }), 15000), nil)
end)

t.test("a timer in a hover card that starts again sends its row", function()
	local new = col({ carded("agent-1", 0) })
	t.eq(patch.diff(col({ carded("agent-1", 4000) }), 10000, new, 15000), { set = { ["agent-1"] = carded("agent-1", 0) } })
end)

t.test("a row inside a section is sent by its path", function()
	local old = col({ section("repo-a", { row("agent-1", "a"), row("agent-2", "b") }) })
	local new = col({ section("repo-a", { row("agent-1", "a"), row("agent-2", "B") }) })
	local change = patch.diff(old, 0, new, 0)
	t.eq(canvas.apply(old, change), new)
end)

t.test("a section whose head changes is sent whole", function()
	local old = col({ section("repo-a", { row("agent-1", "a") }) })
	local renamed = section("repo-a", { row("agent-1", "a") })
	renamed.p = { key = "repo-a", head = "repo-a (1)" }
	local change = patch.diff(old, 0, col({ renamed }), 0)
	t.eq(change, { set = { ["repo-a"] = renamed } })
end)

t.test("a key with a dot, which a path cannot name, sends its parent whole", function()
	local old = col({ section("repo-a", { row("agent.1", "a") }) })
	local new = col({ section("repo-a", { row("agent.1", "A") }) })
	t.eq(patch.diff(old, 0, new, 0), { set = { ["repo-a"] = (new.c :: { Node })[1] } })
end)

t.test("a change of the root itself sends the whole view", function()
	local new: Node = { k = "lines", c = { row("agent-1", "a") } }
	t.eq(patch.diff(col({ row("agent-1", "a") }), 0, new, 0), { view = new })
end)
return nil

