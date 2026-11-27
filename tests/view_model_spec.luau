--!strict
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local ICON = "\u{F0E7}"

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = "/repo", title = ICON .. " Fix login" }
	for k, v in fields do
		a[k] = v
	end
	return a
end

local function rows(agents: { any }, now: number?): { string }
	return visible.agentRows(viewModel.build({ agents = agents, now = now or 0 }).view)
end

t.test("an idle agent shows as one row with omp's icon in the idle state and its title", function()
	t.eq(rows({ agent({}) }), { ICON .. "(Idle) Fix login" })
end)

t.test("a working row's hover card counts the turn from its start", function()
	local view = viewModel.build({ agents = { agent({ state = "working", workingSince = 1000 }) }, now = 66000 }).view
	t.eq(visible.hover(view, "Fix login"), ICON .. " Fix login · Working ⏱65s")
end)

t.test("an agent whose title holds only omp's icon shows its folder name", function()
	t.eq(rows({ agent({ title = ICON .. " ", cwd = "/Users/me/Personal/tern-agents" }) }), { ":sparkle(Idle) tern-agents" })
end)

t.test("the hover card names the model without its glyph and with no logo", function()
	local view = viewModel.build({ agents = { agent({ model = "Opus 5.5 \u{F0EB}" }) }, now = 0 }).view
	t.eq(visible.hover(view, "Fix login"), ICON .. " Fix login · Idle\nModel opus 5.5")
end)

t.test("the hover card names an omp agent's model as its session does, provider/model, rather than Tern's name", function()
	local view = viewModel.build({
		agents = { agent({ model = "Opus 5.5 \u{F0EB}", route = "anthropic/claude-opus-5-5@bedrock" }) },
		now = 0,
	}).view
	t.eq(visible.hover(view, "Fix login"), ICON .. " Fix login · Idle\nModel anthropic/claude-opus-5-5")
end)

t.test("the hover card shows the agent's state and its last message", function()
	local view = viewModel.build({ agents = { agent({ lastMessage = "Tests pass. **Ready** to merge." }) }, now = 0 }).view
	t.eq(visible.hover(view, "Fix login"), ICON .. " Fix login · Idle\nTests pass. **Ready** to merge.")
end)

local HOME = "/Users/me"

local function idle(agents: { any }): { string }
	return visible.zone(viewModel.build({ agents = agents, now = 0, home = HOME }).view, "Idle")
end

t.test("projects with the same name keep the order of their full paths", function()
	t.eq(idle({
		agent({ pane = 1, title = ICON .. " b", repo = "/Users/me/b/app" }),
		agent({ pane = 2, title = ICON .. " a", repo = "/Users/me/a/app" }),
		agent({ pane = 3, title = ICON .. " z", repo = "/Users/me/Apps" }),
	}), {
		"app [:plus](New tab in this repo)",
		ICON .. "(Idle) a",
		"app [:plus](New tab in this repo)",
		ICON .. "(Idle) b",
		"Apps [:plus](New tab in this repo)",
		ICON .. "(Idle) z",
	})
end)

t.test("the order of projects ignores letter case", function()
	t.eq(idle({
		agent({ pane = 1, title = ICON .. " b", repo = "/Users/me/Work/beta" }),
		agent({ pane = 2, title = ICON .. " a", repo = "/Users/me/Work/Alpha" }),
	}), {
		"Alpha [:plus](New tab in this repo)",
		ICON .. "(Idle) a",
		"beta [:plus](New tab in this repo)",
		ICON .. "(Idle) b",
	})
end)

t.test("groups list the folders in label order, agents with no folder at all last", function()
	local loose = agent({ pane = 5 })
	loose.cwd = nil
	local groups = viewModel.groups({
		agent({ pane = 1, repo = nil, cwd = "/Users/me/Work" }),
		agent({ pane = 2, repo = "/Users/me/b" }),
		agent({ pane = 3, repo = "/Users/me/a" }),
		agent({ pane = 4, repo = "/Users/me/b" }),
		loose,
	} :: any, HOME)
	local seen = {}
	for _, group in groups do
		local panes = {}
		for _, a in group.agents do
			table.insert(panes, a.pane)
		end
		table.insert(seen, { name = group.name, folder = group.folder or "-", panes = panes })
	end
	t.eq(seen, {
		{ name = "a", folder = "/Users/me/a", panes = { 3 } },
		{ name = "b", folder = "/Users/me/b", panes = { 2, 4 } },
		{ name = "Work", folder = "/Users/me/Work", panes = { 1 } },
		{ name = "No folder", folder = "-", panes = { 5 } },
	})
end)

return nil
