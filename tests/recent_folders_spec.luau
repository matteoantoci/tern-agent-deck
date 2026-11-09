--!strict
-- The Recent view lists folders at its top level, newest session first: each folder with a live agent and closed
-- sessions, and each folder with a closed session from the last week and no live agent, each folder once.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local NOW = 1_800_000_000
local MIN, HOUR, DAY = 60, 60 * 60, 24 * 60 * 60

local function key(folder: string): string
	return "repo-" .. (string.gsub(folder, "[^%w%-]", function(c: string): string
		return string.format("_%02X", string.byte(c))
	end))
end

local count = 0
-- A closed omp session in `repo` (or, with `repo` false, in the folder `cwd` outside any repo).
local function session(repo: string, title: string?, ago: number, fields: { [string]: any }?): { [string]: any }
	count += 1
	local s: { [string]: any } = {
		file = string.format("/Users/me/.omp/agent/sessions/b/%d.jsonl", count),
		id = "s" .. count,
		cwd = repo,
		repo = repo,
		title = title,
		at = NOW - ago,
	}
	for k, v in (fields or {}) :: { [string]: any } do
		s[k] = v
	end
	if s.repo == false then
		s.repo = nil
	end
	return s
end

-- The Recent view, unless `extra` names another.
local function view(agents: { any }, sessions: { any }, extra: { [string]: any }?): any
	local input: { [string]: any } = { agents = agents, sessions = sessions, now = 0, time = NOW, home = HOME, view = "recent" }
	for k, v in (extra or {}) :: { [string]: any } do
		input[k] = v
	end
	return viewModel.build(input :: any).view
end

-- A closed folder row at the top level of the Recent view, with the count of the sessions it lists.
local function repoRow(name: string, sessions: number): string
	return string.format(":chev-r :mi-folder %s %d [:plus](New tab in this repo)", name, sessions)
end

local EMPTY = "No recent sessions\nClosed omp sessions of the last 7 days show here."

t.test("the Recent view lists its folders at the top level, newest session first, live or not", function()
	local shown = view({
		{ pane = 1, state = "idle", cwd = "/Users/me/live", repo = "/Users/me/live", title = "busy" },
	}, {
		session("/Users/me/alpha", "a", 3 * DAY),
		session("/Users/me/beta", "b", 2 * HOUR),
		session("/Users/me/live", "old chat", HOUR),
		session("/Users/me/stale", "c", 8 * DAY),
		session("/Users/me/alpha", "a2", 5 * MIN),
	})
	t.eq(visible.tree(shown), {
		repoRow("alpha", 2),
		repoRow("live", 1),
		repoRow("beta", 1),
	})
	t.eq(visible.hover(shown, "alpha"), "~/alpha\nLast session 5m ago")
	t.eq(visible.titles(shown, "alpha"), { "New tab in this repo" })
end)

t.test("a folder with a live agent lists its closed sessions however old they are", function()
	local shown = view({
		{ pane = 1, state = "idle", cwd = "/Users/me/live", repo = "/Users/me/live", title = "busy" },
	}, {
		session("/Users/me/live", "old chat", 30 * DAY),
		session("/Users/me/alpha", "a", HOUR),
	})
	t.eq(visible.tree(shown), { repoRow("alpha", 1), repoRow("live", 1) })
end)

t.test("with no recent folder, the Recent view shows its empty state", function()
	t.eq(visible.lines(view({}, { session("/Users/me/stale", "c", 8 * DAY) })), { EMPTY })
end)

t.test("the Recent view lists folders while no agent runs, and the Live view shows its empty state", function()
	local sessions = { session("/Users/me/alpha", "a", HOUR) }
	t.eq(visible.rows(view({}, sessions)), { repoRow("alpha", 1) })
	t.eq(visible.rows(view({}, sessions, { view = "live" })), {})
	t.eq(visible.lines(view({}, sessions, { view = "live" }))[1], "No agents running\nStart one here, or run omp in any pane.")
end)

t.test("a session a process holds open does not make its folder recent", function()
	t.eq(visible.lines(view({}, { session("/Users/me/alpha", "a", HOUR, { open = true }) })), { EMPTY })
end)

t.test("a folder outside git shows its folder name and a + for that folder", function()
	t.eq(visible.rows(view({}, { session("/tmp/scratch", "a", HOUR, { repo = false }) })), {
		":chev-r :mi-folder scratch 1 [:plus](New tab in this folder)",
	})
end)

t.test("5 folders show, and an N more row at the end asks to show the rest", function()
	local sessions = {}
	for n = 1, 7 do
		table.insert(sessions, session("/Users/me/r" .. n, "x", n * HOUR))
	end
	local shown = view({}, sessions)
	t.eq(visible.tree(shown), {
		repoRow("r1", 1),
		repoRow("r2", 1),
		repoRow("r3", 1),
		repoRow("r4", 1),
		repoRow("r5", 1),
		":more 2 more",
	})
	t.eq(visible.click(shown, "2 more"), "recent-more")
	local all = view({}, sessions, { recentAll = true })
	t.eq(#visible.rows(all), 8)
	t.eq(visible.tree(all)[8], ":chev Show fewer")
	t.eq(visible.click(all, "Show fewer"), "recent-more")
end)

t.test("the view has no Recent repos head", function()
	local shown = view({}, { session("/Users/me/alpha", "a", HOUR) })
	for _, line in visible.lines(shown) do
		t.eq(string.find(line, "Recent repos", 1, true), nil)
	end
end)

t.test("a click on a folder opens it to show its last 5 sessions one level under it; a click on a session resumes it", function()
	local sessions = {}
	for n = 1, 6 do
		table.insert(sessions, session("/Users/me/alpha", "chat " .. n, n * DAY))
	end
	local closed = view({}, sessions)
	t.eq(visible.click(closed, "alpha"), "recent=" .. key("/Users/me/alpha"))
	t.eq(visible.button(closed, "alpha"), "new=/Users/me/alpha")
	local opened = view({}, sessions, { recentOpen = { [key("/Users/me/alpha")] = true } })
	t.eq(visible.tree(opened), {
		":chev :mi-folder-open alpha 5 [:plus](New tab in this repo)",
		"  ●(Closed) chat 1 1d",
		"  ●(Closed) chat 2 2d",
		"  ●(Closed) chat 3 3d",
		"  ●(Closed) chat 4 4d",
		"  ●(Closed) chat 5 5d",
	})
	t.eq(visible.click(opened, "chat 2 2d"), "resume=" .. sessions[2].file)
end)

t.test("when an agent starts in a recent folder, the folder still shows once", function()
	local sessions = { session("/Users/me/alpha", "a", HOUR) }
	local agents = {
		{ pane = 1, state = "working", cwd = "/Users/me/alpha", repo = "/Users/me/alpha", title = "new", workingSince = 0 },
	}
	t.eq(visible.rows(view(agents, sessions)), { repoRow("alpha", 1) })
	t.eq(visible.rows(view(agents, sessions, { view = "live" })), {
		":chev :mi-folder-open alpha 1 [:plus](New tab in this repo)",
		"●(Working) new …",
	})
end)

return nil
