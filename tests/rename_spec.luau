--!strict
-- A live omp agent's right-click menu renames its session: Rename asks for the new title and sends omp's
-- `/rename <title>`.
local t = require("./harness")
local visible = require("./visible")
local rename = require("../lib/rename")
local viewModel = require("../lib/view_model")
local viewing = require("../lib/viewing")

local REPO = "/Users/me/Personal/tern-agents"
local SESSION = "/Users/me/.omp/agent/sessions/-Personal-tern-agents/2026-11-09T08-21-12-853Z_01a1bf65.jsonl"
local ICON = "\u{F0403} "

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } =
		{ pane = 2, state = "idle", cwd = REPO, repo = REPO, title = ICON .. "build", sessionFile = SESSION }
	for k, v in fields do
		a[k] = v
	end
	return a
end

local function view(input: { [string]: any }): any
	local full: { [string]: any } = { agents = {}, now = 0, home = "/Users/me" }
	for k, v in input do
		full[k] = v
	end
	return viewModel.build(full :: any).view
end

t.test("a live agent's right-click menu offers Rename between Pin and the copy items", function()
	local menu = visible.menu(view({ agents = { agent({}) } }), "build")
	t.eq({ menu[1], menu[2], menu[3] }, { "Pin → pin=2", "Rename → rename=2", "Copy session ID → copy-id=" .. SESSION })
end)

t.test("Rename shows the pencil icon", function()
	t.eq(visible.menuIcon(view({ agents = { agent({}) } }), "build", "Rename"), "pencil")
end)

t.test("Rename is off, with the reason, for an agent whose omp reported no session file", function()
	local bare = agent({})
	bare.sessionFile = nil
	local menu = visible.menu(view({ agents = { bare } }), "build")
	t.eq(menu[2], "Rename → rename (off: Only an omp session can be renamed, and this agent reported none)")
end)

t.test("Rename is off while omp shows a subagent, whose chat would take the command as a message", function()
	local menu = visible.menu(view({ agents = { agent({}) }, viewing = { [2] = "Ticket07" } }), "build")
	t.eq(menu[2], "Rename → rename (off: omp shows a subagent: go back to the main session first)")
end)

t.test("Rename is off while the agent waits for an answer, which the command would give", function()
	local menu = visible.menu(view({ agents = { agent({ state = "waiting_input" }) } }), "build")
	t.eq(menu[2], "Rename → rename (off: The agent waits for your answer)")
end)

t.test("a working agent can be renamed", function()
	local menu = visible.menu(view({ agents = { agent({ state = "working", workingSince = 0 }) } }), "build")
	t.eq(menu[2], "Rename → rename=2")
end)

t.test("subagent rows, closed session rows and a gone pin offer no Rename", function()
	local v = view({
		agents = { agent({ state = "working", workingSince = 0 }) },
		subagents = { [2] = { agents = { { id = "dx.Ticket07", name = "Ticket07", status = "running", depth = 1 } } } },
		pins = { { pane = 9, cwd = REPO, title = "gone" } },
	})
	for _, line in visible.menu(v, "Ticket07") do
		t.eq(string.find(line, "Rename", 1, true), nil)
	end
	for _, line in visible.menu(v, "gone") do
		t.eq(string.find(line, "Rename", 1, true), nil)
	end
end)

t.test("the field starts with the title without omp's icon", function()
	t.eq(rename.current(ICON .. "Fix login"), "Fix login")
	t.eq(rename.current("omp"), "omp")
	t.eq(rename.current(nil), nil)
end)

t.test("a new title becomes omp's /rename command, trimmed, on one line", function()
	t.eq(rename.command("  Plan the sidebar  ", "Fix login"), "/rename Plan the sidebar")
	t.eq(rename.command("Two\nlines\tand  tabs", nil), "/rename Two lines and tabs")
end)

t.test("a blank title, a dismissed field or the same title sends nothing", function()
	t.eq(rename.command("   ", "Fix login"), nil, "a blank /rename would make omp generate a title")
	t.eq(rename.command(nil, "Fix login"), nil)
	t.eq(rename.command(" Fix login ", "Fix login"), nil)
end)

-- A scoped read of omp's dock shaped like the live one (2026-11-09, omp 18.18.3): the composer (`omp.editor`) holds
-- its line with the field (`3.line/input`, kind `editor`), and, while omp shows a subagent, the viewing header.
local function dock(viewingSub: boolean?, editorKind: string?): any
	local composer: { any } = {}
	if viewingSub then
		table.insert(composer, {
			id = "3.focus",
			k = "row",
			c = { { id = "3.focus/exit", k = "row", p = { actions = { click = "focus:Main" } } } },
		})
	end
	table.insert(composer, {
		id = "3.line",
		k = "row",
		p = { role = "omp.composer.line" },
		c = { { id = "3.line/input", k = editorKind or "editor" } },
	})
	local editor = { id = "3", k = "col", p = { role = "omp.editor" }, c = composer }
	return { surface = { id = "s:1" }, main = { id = "dock", k = "col", c = { editor } } }
end

t.test("the command goes to omp's composer field as one send event, as the user's Enter sends it", function()
	t.eq(viewing.send(dock(), "/rename Plan"), { surface = "s:1", id = "3.line/input", text = "/rename Plan" })
end)

t.test("while omp shows a subagent, or without a composer field or a read, nothing is sent", function()
	t.eq(viewing.send(dock(true), "/rename Plan"), nil, "the composer is the subagent's chat box then")
	t.eq(viewing.send(dock(false, "text"), "/rename Plan"), nil)
	t.eq(viewing.send(nil, "/rename Plan"), nil)
end)

return nil
