--!strict
-- A click on a main agent's row brings omp back to the main session when omp shows a subagent ("Viewing <name>"):
-- the dock then holds omp's own way back, a row `…focus/exit` whose click action is `focus:<main>`.
local t = require("./harness")
local backToMain = require("../lib/back_to_main")

-- A surface node: TSP nodes differ in their props.
local function node(fields: { [string]: any }): any
	return fields
end

-- A scoped read of a pane's dock (`root = "dock"`) while omp shows the subagent `Round3`.
local function viewing(): any
	return {
		surface = { id = "omp.session" },
		main = node({
			id = "dock",
			k = "col",
			c = {
				node({
					id = "3.focus",
					k = "row",
					c = {
						node({ id = "3.focus/label", k = "text", p = { text = "Viewing" } }),
						node({ id = "3.focus/name", k = "text", p = { text = "Round3" } }),
						node({
							id = "3.focus/exit",
							k = "row",
							p = { title = "Back to the main session  esc", actions = { click = "focus:Main" } },
						}),
					},
				}),
				node({ id = "3.bar", k = "row", c = { node({ id = "3.bar/model/effort", k = "effort", p = { level = "high" } }) } }),
			},
		}),
	}
end

t.test("while omp shows a subagent, the row click runs omp's way back to the main session", function()
	t.eq(backToMain.find(viewing()), { surface = "omp.session", id = "3.focus/exit", act = "focus:Main" })
end)

t.test("while omp shows the main session, the row click only focuses the pane", function()
	local tree = viewing()
	table.remove(tree.main.c, 1)
	t.eq(backToMain.find(tree), nil)
end)

t.test("a focus/exit node whose click is no focus action is not the way back", function()
	local tree = viewing()
	tree.main.c[1].c[3].p.actions.click = "close"
	t.eq(backToMain.find(tree), nil)
end)

t.test("a node with another id is not the way back, whatever its action", function()
	local tree = viewing()
	tree.main.c[1].c[3].id = "3.focus/exit-hint"
	t.eq(backToMain.find(tree), nil)
end)

t.test("no read, or a read without a surface id, finds nothing", function()
	t.eq(backToMain.find(nil), nil)
	local tree = viewing()
	tree.surface = nil
	t.eq(backToMain.find(tree), nil)
end)

return nil
