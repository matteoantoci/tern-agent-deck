--!strict
-- Tab titles: each tab is titled with the name of the main agent in it.
local t = require("./harness")
local viewModel = require("../lib/view_model")

local ICON = "\u{F0001}"

local function agent(pane: number, tab: number?, title: string?, fields: { [string]: any }?): { [string]: any }
	local a: { [string]: any } = { pane = pane, tab = tab, state = "idle", cwd = "/Users/me/repo", title = title }
	for k, v in (fields or {}) :: { [string]: any } do
		a[k] = v
	end
	return a
end

-- The title Tern shows for tab `id` (named `name` by the user, or not) with `agents` running.
local function title(agents: { any }, id: number, name: string?): string?
	return viewModel.tabTitle({ id = id, name = name }, viewModel.tabTitles(agents :: any))
end

t.test("a tab with one agent shows that agent's name: its pane title without the leading icon", function()
	t.eq(title({ agent(5, 1, ICON .. " TERN: Build tern plugin") }, 1), "TERN: Build tern plugin")
end)

t.test("a tab with several agents shows the first one in start order", function()
	local agents = { agent(12, 2, ICON .. " Second"), agent(4, 2, ICON .. " First"), agent(8, 3, ICON .. " Other tab") }
	t.eq(title(agents, 2), "First")
	t.eq(title(agents, 3), "Other tab")
end)

t.test("a tab the user renamed keeps its name", function()
	t.eq(title({ agent(5, 1, ICON .. " Agent title") }, 1, "My tab"), "My tab")
	t.eq(title({ agent(5, 1, ICON .. " Agent title") }, 1, ""), "Agent title", "an empty name is no name")
end)

t.test("a tab without an agent keeps Tern's own title", function()
	t.eq(title({ agent(5, 1, ICON .. " Elsewhere") }, 2), nil)
	t.eq(title({ agent(5, nil, ICON .. " Parked") }, 1), nil, "a parked agent sits in no tab")
end)

t.test("an exited agent does not name its tab: the next agent in start order does", function()
	t.eq(title({ agent(3, 1, ICON .. " Done", { state = "exited" }), agent(6, 1, ICON .. " Running") }, 1), "Running")
	t.eq(title({ agent(3, 1, ICON .. " Done", { state = "exited" }) }, 1), nil)
end)

t.test("an agent with no title names its tab after its folder, as its row does", function()
	t.eq(title({ agent(5, 1, nil) }, 1), "repo")
end)

return nil
