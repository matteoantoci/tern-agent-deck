--!strict
-- The sidebar looks like Tern's Files pane: a head with the title and its tools, a strip of view buttons (Live and
-- Recent), and a tree of folder rows with their agents one level in and the subagents one more.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local REPO = "/Users/me/Personal/tern-agents"
local KEY = "repo-_2FUsers_2Fme_2FPersonal_2Ftern-agents"
local NOW = 1_800_000_000
local HOUR, DAY = 60 * 60, 24 * 60 * 60
local FOLDER = ":chev :mi-folder-open tern-agents %d [:plus](New tab in this repo)"

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = REPO, repo = REPO, title = "Fix login" }
	for k, v in fields do
		a[k] = v
	end
	return a
end

local function session(n: number, folder: string, title: string, ago: number): { [string]: any }
	return { file = string.format("/s/%d.jsonl", n), id = "s" .. n, cwd = folder, repo = folder, title = title, at = NOW - ago }
end

local function view(input: { [string]: any }): any
	local full: { [string]: any } = { agents = {}, now = 0, time = NOW, home = HOME }
	for k, v in input do
		full[k] = v
	end
	return viewModel.build(full :: any).view
end

t.test("the head shows the Agents title, a ⋯ menu and a button that hides the sidebar, over the view strip", function()
	local out = view({ agents = { agent({}) } })
	t.eq(visible.chrome(out), {
		":users Agents [⋯](More) [:sidebar](Hide sidebar)",
		"[:activity](Live) [:history](Recent)",
	})
	t.eq(visible.press(out, "Hide sidebar"), "toggle-sidebar")
end)

t.test("the ⋯ menu offers a new tab here, arranging the tabs by project and the sidebar toggle", function()
	t.eq(visible.dropdown(view({})), {
		"New tab here → new-here",
		"Arrange tabs by project → arrange-by-repo",
		"-",
		"Toggle sidebar → toggle-sidebar",
	})
end)

t.test("the view strip shows Live by default and Recent when chosen; a click on a view asks to show it", function()
	t.eq(visible.shownView(view({})), "Live")
	t.eq(visible.shownView(view({ view = "recent" })), "Recent")
	t.eq(visible.press(view({}), "Recent"), "view=recent")
	t.eq(visible.press(view({ view = "recent" }), "Live"), "view=live")
end)

t.test("a folder row shows a chevron, a folder and the folder's name; the count and + show on hover, the path in the card", function()
	local out = view({ agents = { agent({}) } })
	t.eq(visible.rows(out)[1], string.format(FOLDER, 1))
	t.eq(visible.onHover(out, "tern-agents"), { "1", "[:plus](New tab in this repo)" })
	t.eq(visible.hover(out, "tern-agents"), "~/Personal/tern-agents")
	t.eq(visible.face(out, "tern-agents"), "sans")
	t.eq(visible.rows(view({ agents = { agent({}) }, folded = { [KEY] = true } }))[1], ":chev-r :mi-folder tern-agents 1 [:plus](New tab in this repo)")
end)

t.test("agents sit one level under their folder, subagents and their lines one more, old agents under Older", function()
	local out = view({
		agents = {
			agent({ pane = 7, state = "working", title = "Lead", workingSince = 0 }),
			agent({ pane = 8, title = "old", activeAt = NOW - 2 * DAY }),
		},
		subagents = {
			[7] = {
				agents = {
					{ id = "dx.A", name = "A", status = "running", depth = 1 },
					{ id = "dx.B", name = "B", status = "running", depth = 2, parent = "A" },
					{ id = "dx.C", name = "C", status = "done", depth = 1 },
				},
				incomplete = false,
			},
		},
		olderOpen = { [KEY] = true },
	})
	t.eq(visible.tree(out), {
		string.format(FOLDER, 2),
		"  ●(Working) Lead …",
		"    ●(Running) A …",
		"    ●(Running) B in A …",
		"    :check 1 subagent done",
		"  :chev Older 1",
		"    ●(Idle) old",
	})
end)

t.test("Needs you and Pinned list their agents one level under their head", function()
	t.eq(visible.tree(view({
		agents = { agent({ pane = 1, title = "ask", state = "waiting_input" }), agent({ pane = 2, title = "keep" }) },
		pins = { { pane = 2, cwd = REPO, title = "keep" } },
	})), {
		":bell Needs you 1",
		"  ●(Waiting for you) ask tern-agents :bell",
		":pin Pinned 1",
		"  ●(Idle) keep",
		string.format(FOLDER, 1),
		"  ●(Waiting for you) ask :bell",
	})
end)

t.test("an agent row ends in a spinner while it works and a bell while it waits; model, effort and timer are in its card", function()
	local out = view({
		agents = {
			agent({ pane = 1, title = "a", state = "working", model = "Opus 5.5 \u{F0EB}", effort = "high", workingSince = 0 }),
			agent({ pane = 2, title = "b", state = "waiting_input", model = "GPT-5.1" }),
			agent({ pane = 3, title = "c", model = "Kimi K2" }),
		},
		now = 12000,
	})
	t.eq(visible.agentRows(out), {
		"●(Waiting for you) b tern-agents :bell",
		"●(Working) a …",
		"●(Waiting for you) b :bell",
		"●(Idle) c",
	})
	t.eq(visible.hover(out, "a …"), "a · Working\n:provider-anthropic Model Opus 5.5\n◔high Effort high\nWorking for ⏱12s")
	t.eq(visible.hover(out, "(Idle) c"), "c · Idle\nModel Kimi K2")
end)

t.test("the Live view leaves closed sessions out", function()
	t.eq(visible.rows(view({
		agents = { agent({ title = "live" }) },
		sessions = { session(1, REPO, "Plan", HOUR), session(2, "/Users/me/alpha", "a", HOUR) },
	})), { string.format(FOLDER, 1), "●(Idle) live" })
end)

t.test("the Recent view lists its folders at the top level, the one with the newest closed session first", function()
	local out = view({
		view = "recent",
		agents = { agent({ title = "live" }) },
		sessions = { session(1, REPO, "Plan", HOUR), session(2, "/Users/me/alpha", "a", 2 * HOUR) },
		recentOpen = { [KEY] = true },
	})
	t.eq(visible.tree(out), {
		string.format(FOLDER, 1),
		"  ●(Closed) Plan 1h",
		":chev-r :mi-folder alpha 1 [:plus](New tab in this repo)",
	})
	t.eq(visible.click(out, "tern-agents"), "recent=" .. KEY)
	t.eq(visible.hover(out, "tern-agents"), "~/Personal/tern-agents\nLast session 1h ago")
end)

t.test("the Recent view says so when there is no closed session", function()
	t.eq(visible.lines(view({ view = "recent", agents = { agent({}) } })), {
		"No recent sessions\nClosed omp sessions of the last 7 days show here.",
	})
end)

return nil
