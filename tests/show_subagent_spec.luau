--!strict
-- A click on a subagent row shows that subagent in omp's view: the plugin sends omp's composer the action its
-- viewing header's links send (`focus:<agent id>`), which omp runs whichever composer node it names. It works while
-- omp shows the main session and while it shows another subagent, which then switches straight to the clicked one.
local t = require("./harness")
local viewing = require("../lib/viewing")

local function sub(name: string): any
	return { id = "dx." .. name, name = name, status = "running", depth = 1 }
end

-- A scoped read of the pane's dock (`root = "dock"`) shaped like the live one (2026-11-09): omp's HUD, then the
-- composer (`omp.editor`, `omp.editor.<shell>` in shell mode) with its line and bar. `shown` is omp's lineage of the
-- shown subagent, outermost first, or nil while omp shows the main session: the composer then starts with the
-- viewing header.
local function dock(shown: { string }?, editorRole: string?): any
	local composer: { any } = {}
	if shown then
		local focus: { any } = { { id = "3.focus/label", k = "text", p = { text = "Viewing" } } }
		for i, id in shown do
			if i < #shown then
				table.insert(focus, {
					id = "3.focus/crumb:" .. id,
					k = "text",
					p = { role = "omp.composer.crumb", text = id, actions = { click = "focus:" .. id } },
				})
			end
		end
		table.insert(focus, { id = "3.focus/agent", k = "text", p = { role = "omp.composer.agent", text = shown[#shown] } })
		table.insert(focus, {
			id = "3.focus/exit",
			k = "row",
			p = { role = "omp.composer.exit", actions = { click = "focus:Main" } },
		})
		table.insert(composer, { id = "3.focus", k = "row", p = { role = "omp.composer.focus" }, c = focus })
	end
	table.insert(composer, { id = "3.line", k = "row", p = { role = "omp.composer.line" } })
	table.insert(composer, { id = "3.bar", k = "row", p = { role = "omp.composer.bar" } })
	local hud: any = { id = "6", k = "row", p = { role = "omp.hud" } }
	local editor: any = { id = "3", k = "col", p = { role = editorRole or "omp.editor" }, c = composer }
	return {
		surface = { id = "s:1" },
		main = { id = "dock", k = "col", c = { hud, { id = "h", k = "col", c = { editor } } } },
	}
end

t.test("while omp shows the main session, a subagent click asks omp's composer to view that subagent", function()
	t.eq(viewing.show(dock(nil), sub("Ticket07")), { surface = "s:1", id = "3", act = "focus:Ticket07" })
end)

t.test("while omp shows another subagent, a click switches the view straight to the clicked one", function()
	t.eq(viewing.show(dock({ "Ticket03" }), sub("Ticket07")), { surface = "s:1", id = "3", act = "focus:Ticket07" })
end)

t.test("a nested subagent is asked for by its omp id, its levels joined by dots", function()
	t.eq(viewing.show(dock(nil), sub("Merge0407>Ticket04")), { surface = "s:1", id = "3", act = "focus:Merge0407.Ticket04" })
end)

t.test("a click on the subagent omp shows already sends nothing", function()
	t.eq(viewing.show(dock({ "Ticket07" }), sub("Ticket07")), nil)
	t.eq(viewing.show(dock({ "Merge0407", "Merge0407.Ticket04" }), sub("Merge0407>Ticket04")), nil)
end)

t.test("the composer in shell mode takes the click as well", function()
	t.eq(viewing.show(dock(nil, "omp.editor.bash"), sub("Ticket07")), { surface = "s:1", id = "3", act = "focus:Ticket07" })
end)

t.test("a read without omp's composer or without a surface id, or no read, sends nothing", function()
	t.eq(viewing.show(dock(nil, "omp.editorial"), sub("Ticket07")), nil)
	local noSurface = dock(nil)
	noSurface.surface = nil
	t.eq(viewing.show(noSurface, sub("Ticket07")), nil)
	t.eq(viewing.show(nil, sub("Ticket07")), nil)
end)

return nil
