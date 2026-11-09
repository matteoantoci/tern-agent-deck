--!strict
local t = require("./harness")
local effort = require("../lib/effort")

-- The dock as a live read showed it (2026-11-09): the composer's model row holds the model text and the effort
-- glyph, five levels below the dock.
local function dock(level: any): any
	local glyph: any = { id = "3.bar/model/effort", k = "effort", p = { level = level, role = "omp.composer.model.effort" } }
	local model: any = {
		id = "3.bar/model",
		k = "row",
		p = { role = "omp.composer.model" },
		c = { { id = "3.bar/model/name", k = "text", p = { text = "Opus 5.5" } }, glyph },
	}
	local children: { any } = {
		{ id = "6", k = "row", p = { role = "omp.hud" } },
		{ id = "3", k = "col", c = { { id = "3.bar", k = "row", c = { model } } } },
	}
	return { surface = { id = "s" }, main = { id = "dock", k = "col", c = children } }
end

t.test("the composer's effort glyph in the dock gives the agent's effort level and the node to read next time", function()
	t.eq({ effort.find(dock("high")) }, { "3.bar/model/effort", "high" })
end)

t.test("a read scoped to the effort node gives its level", function()
	local scoped = { surface = { id = "s" }, main = { id = "3.bar/model/effort", k = "effort", p = { level = "xhigh", role = "omp.composer.model.effort" } } }
	t.eq({ effort.find(scoped) }, { "3.bar/model/effort", "xhigh" })
end)

t.test("a dock without the composer's effort glyph, or one with no level, gives no level", function()
	t.eq({ effort.find({ surface = { id = "s" }, main = { id = "dock", k = "col", c = {} } }) }, {})
	t.eq({ effort.find(nil) }, {})
	local null = newproxy()
	t.eq({ effort.find(dock(null)) }, { "3.bar/model/effort" })
	t.eq({ effort.find(dock("")) }, { "3.bar/model/effort" })
end)

t.test("another plugin's effort node is not the composer's", function()
	local tree = { surface = { id = "s" }, main = { id = "x", k = "effort", p = { level = "low" } } }
	t.eq({ effort.find(tree) }, {})
end)

return nil
