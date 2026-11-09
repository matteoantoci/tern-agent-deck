--!strict
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

t.test("with no agents, the sidebar says so", function()
	local out = viewModel.build({ agents = {}, now = 0 })
	t.eq(visible.lines(out.view), { "No agents running\nStart one here, or run omp in any pane.", "New tab here" })
end)

local ICON = "\u{F0E7} "

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = "/repo", title = ICON .. "Fix login" }
	for k, v in fields do
		a[k] = v
	end
	return a
end

-- The folder row of a section, a repo's or the working directory's of agents outside any repo: it shows the
-- folder's name (the last part of `path`).
local function folder(path: string, count: number): string
	return string.format(":chev :mi-folder-open %s %d [:plus](New tab in this folder)", string.match(path, "([^/]+)/*$") :: string, count)
end

local function repo(path: string, count: number): string
	return string.format(":chev :mi-folder-open %s %d [:plus](New tab in this repo)", string.match(path, "([^/]+)/*$") :: string, count)
end

-- The rows below the first header (all the agents here share the working directory `/repo`).
local function rows(agents: { any }, now: number?): { string }
	local shown = visible.rows(viewModel.build({ agents = agents, now = now or 0 }).view)
	t.eq(shown[1], folder("/repo", #agents))
	table.remove(shown, 1)
	return shown
end

t.test("an idle agent shows as one row with the idle dot and its pane title without the icon", function()
	t.eq(rows({ agent({}) }), { "●(Idle) Fix login" })
end)

t.test("each state has its own dot", function()
	t.eq(
		visible.rows(viewModel.build({
			agents = {
				agent({ pane = 1, state = "working", title = "a" }),
				agent({ pane = 2, state = "waiting_input", title = "b" }),
				agent({ pane = 3, state = "idle", title = "c" }),
			},
			now = 0,
		}).view),
		{
			":bell Needs you 1",
			"●(Waiting for you) b repo :bell",
			folder("/repo", 3),
			"●(Working) a …",
			"●(Waiting for you) b :bell",
			"●(Idle) c",
		}
	)
end)

t.test("a working row's hover card counts the turn from its start", function()
	local view = viewModel.build({ agents = { agent({ state = "working", workingSince = 1000 }) }, now = 66000 }).view
	t.eq(visible.hover(view, "Fix login"), "Fix login · Working\nWorking for ⏱65s")
end)

t.test("a tab name the user set replaces the pane title", function()
	t.eq(rows({ agent({ tab = 7, tabName = "Auth rewrite" }) }), { "●(Idle) Auth rewrite" })
end)

t.test("agents that share a named tab keep their pane titles", function()
	t.eq(rows({
		agent({ pane = 1, tab = 7, tabName = "Auth rewrite", title = ICON .. "Plan" }),
		agent({ pane = 2, tab = 7, tabName = "Auth rewrite", title = ICON .. "Build" }),
	}), { "●(Idle) Plan", "●(Idle) Build" })
end)

t.test("an agent without a title shows its folder name", function()
	local view = viewModel.build({ agents = { agent({ title = ICON, cwd = "/Users/me/Personal/tern-agents" }) }, now = 0 }).view
	t.eq(visible.rows(view), { folder("/Users/me/Personal/tern-agents", 1), "●(Idle) tern-agents" })
end)

t.test("the hover card shows the provider logo of a known model and names the model without its glyph", function()
	local view = viewModel.build({ agents = { agent({ model = "Opus 5.5 \u{F0EB}" }) }, now = 0 }).view
	t.eq(visible.rows(view)[2], "●(Idle) Fix login")
	t.eq(visible.hover(view, "Fix login"), "Fix login · Idle\n:provider-anthropic Model Opus 5.5")
end)

t.test("the hover card shows the agent's state and its last message", function()
	local view = viewModel.build({ agents = { agent({ lastMessage = "Tests pass. **Ready** to merge." }) }, now = 0 }).view
	t.eq(visible.hover(view, "Fix login"), "Fix login · Idle\nTests pass. **Ready** to merge.")
end)

t.test("a click on a row asks to focus that agent's pane", function()
	local view = viewModel.build({ agents = { agent({ pane = 17179869199 }) }, now = 0 }).view
	t.eq(visible.click(view, "Fix login"), "focus=17179869199")
end)

t.test("rows keep the order in which the agents started, whatever their state", function()
	t.eq(rows({
		agent({ pane = 30, title = "third" }),
		agent({ pane = 10, title = "first", state = "working" }),
		agent({ pane = 20, title = "second" }),
	}), {
		"●(Working) first …",
		"●(Idle) second",
		"●(Idle) third",
	})
end)

local HOME = "/Users/me"

local function grouped(agents: { any }): { string }
	return visible.rows(viewModel.build({ agents = agents, now = 0, home = HOME }).view)
end

t.test("agents group under one header per repo, and agents outside a repo under their working directory, in alphabetical order of the folder names", function()
	t.eq(grouped({
		agent({ pane = 1, title = "scratch", repo = nil, cwd = "/tmp" }),
		agent({ pane = 2, title = "tern plugin", repo = "/Users/me/Personal/tern-agents" }),
		agent({ pane = 3, title = "tsp nodes", repo = "/Users/me/Personal/oh-my-pi" }),
		agent({ pane = 4, title = "plugin tests", repo = "/Users/me/Personal/tern-agents" }),
		agent({ pane = 5, title = "triage", repo = nil, cwd = "/Users/me/Work/" }),
	}), {
		repo("~/Personal/oh-my-pi", 1),
		"●(Idle) tsp nodes",
		repo("~/Personal/tern-agents", 2),
		"●(Idle) tern plugin",
		"●(Idle) plugin tests",
		folder("/tmp", 1),
		"●(Idle) scratch",
		folder("~/Work", 1),
		"●(Idle) triage",
	})
end)

t.test("folders with the same name keep the order of their full paths", function()
	t.eq(grouped({
		agent({ pane = 1, title = "b", repo = "/Users/me/b/app" }),
		agent({ pane = 2, title = "a", repo = "/Users/me/a/app" }),
		agent({ pane = 3, title = "z", repo = "/Users/me/Apps" }),
	}), {
		repo("~/a/app", 1),
		"●(Idle) a",
		repo("~/b/app", 1),
		"●(Idle) b",
		repo("~/Apps", 1),
		"●(Idle) z",
	})
end)

t.test("the order of repos ignores letter case", function()
	t.eq(grouped({
		agent({ pane = 1, title = "b", repo = "/Users/me/Work/beta" }),
		agent({ pane = 2, title = "a", repo = "/Users/me/Work/Alpha" }),
	}), {
		repo("~/Work/Alpha", 1),
		"●(Idle) a",
		repo("~/Work/beta", 1),
		"●(Idle) b",
	})
end)

t.test("sections and rows stay in place when agent states change", function()
	local before = grouped({
		agent({ pane = 1, title = "x", repo = "/Users/me/zeta", state = "idle" }),
		agent({ pane = 2, title = "y", repo = "/Users/me/alpha", state = "idle" }),
		agent({ pane = 3, title = "z", repo = "/Users/me/alpha", state = "idle" }),
	})
	local after = grouped({
		agent({ pane = 1, title = "x", repo = "/Users/me/zeta", state = "waiting_input" }),
		agent({ pane = 2, title = "y", repo = "/Users/me/alpha", state = "working" }),
		agent({ pane = 3, title = "z", repo = "/Users/me/alpha", state = "working" }),
	})
	t.eq(before, {
		repo("~/alpha", 2),
		"●(Idle) y",
		"●(Idle) z",
		repo("~/zeta", 1),
		"●(Idle) x",
	})
	t.eq(after, {
		":bell Needs you 1",
		"●(Waiting for you) x zeta :bell",
		repo("~/alpha", 2),
		"●(Working) y …",
		"●(Working) z …",
		repo("~/zeta", 1),
		"●(Waiting for you) x :bell",
	})
end)

t.test("a folder row's hover card gives its short path, or the full path outside the home folder", function()
	local view = viewModel.build({
		agents = { agent({ pane = 1, title = "build", repo = "/opt/src/app" }), agent({ pane = 2, title = "x", repo = "/Users/me/zeta" }) },
		now = 0,
		home = HOME,
	}).view
	t.eq(visible.hover(view, "app"), "/opt/src/app")
	t.eq(visible.hover(view, "zeta"), "~/zeta")
end)

t.test("the + button on a header asks for a new tab in that repo or folder", function()
	local view = viewModel.build({
		agents = {
			agent({ pane = 1, title = "tsp nodes", repo = "/Users/me/Personal/oh-my-pi" }),
			agent({ pane = 2, title = "triage", cwd = "/Users/me/Work" }),
		},
		now = 0,
		home = HOME,
	}).view
	t.eq(visible.button(view, "oh-my-pi"), "new=/Users/me/Personal/oh-my-pi")
	t.eq(visible.button(view, ":mi-folder-open Work"), "new=/Users/me/Work")
end)

t.test("groups list the folders in header order, agents with no folder at all last", function()
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
