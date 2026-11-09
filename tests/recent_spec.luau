--!strict
-- The Recent view lists, under each folder that has a live agent, its newest closed omp sessions.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local REPO = "/Users/me/Personal/tern-agents"
local KEY = "repo-_2FUsers_2Fme_2FPersonal_2Ftern-agents"
local SESSIONS = "/Users/me/.omp/agent/sessions/-Personal-tern-agents/"
local ICON = "\u{F0403} "
local NOW = 1_800_000_000
local MIN, HOUR, DAY = 60, 60 * 60, 24 * 60 * 60

-- The folder row of the repo in the Recent view, open or closed, with the count of the sessions it lists.
local function HEAD(count: number, open: boolean?): string
	if open == false then
		return string.format(":chev-r :mi-folder tern-agents %d [:plus](New tab in this repo)", count)
	end
	return string.format(":chev :mi-folder-open tern-agents %d [:plus](New tab in this repo)", count)
end

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = REPO, repo = REPO, title = ICON .. "Live chat" }
	for k, v in fields do
		a[k] = v
	end
	return a
end

-- A closed omp session of the repo, `ago` seconds since its last write.
local function session(n: number, title: string?, ago: number, fields: { [string]: any }?): { [string]: any }
	local s: { [string]: any } = {
		file = SESSIONS .. string.format("2026-11-0%dT08-00-00-000Z_%d.jsonl", n, n),
		id = "s" .. n,
		cwd = REPO,
		repo = REPO,
		title = title,
		at = NOW - ago,
	}
	for k, v in (fields or {}) :: { [string]: any } do
		s[k] = v
	end
	return s
end

-- The Recent view, with the repo's folder open unless `extra` says otherwise.
local function view(agents: { any }, sessions: { any }, extra: { [string]: any }?): any
	local input: { [string]: any } = {
		agents = agents,
		sessions = sessions,
		now = 0,
		time = NOW,
		home = HOME,
		view = "recent",
		recentOpen = { [KEY] = true },
	}
	for k, v in (extra or {}) :: { [string]: any } do
		input[k] = v
	end
	return viewModel.build(input :: any).view
end

-- The live agent's own session, which never shows in Recent.
local function live(): { [string]: any }
	return session(9, ICON .. "Live chat", 0)
end

local EMPTY = "No recent sessions\nClosed omp sessions of the last 7 days show here."

t.test("a closed folder with closed sessions shows only its row, with their count", function()
	t.eq(visible.rows(view({ agent({}) }, { live(), session(1, ICON .. "Plan", 2 * HOUR), session(2, nil, 5 * MIN) }, {
		recentOpen = {},
	})), { HEAD(2, false) })
end)

t.test("a live folder without closed sessions does not show", function()
	t.eq(visible.lines(view({ agent({}) }, {})), { EMPTY })
end)

t.test("an open folder lists its sessions newest first, with the title, or Untitled, and the age", function()
	t.eq(visible.rows(view({ agent({}) }, {
		live(),
		session(1, ICON .. "Plan the sidebar", 3 * DAY),
		session(2, nil, 5 * MIN),
		session(3, ICON .. "Fix login", 2 * HOUR + 10 * MIN),
		session(4, "", 30),
	})), {
		HEAD(4),
		"●(Closed) Untitled now",
		"●(Closed) Untitled 5m",
		"●(Closed) Fix login 2h",
		"●(Closed) Plan the sidebar 3d",
	})
end)

t.test("a folder lists at most the 5 newest sessions", function()
	local sessions = {}
	for n = 1, 7 do
		table.insert(sessions, session(n, "chat " .. n, n * HOUR))
	end
	t.eq(visible.rows(view({ agent({}) }, sessions)), {
		HEAD(5),
		"●(Closed) chat 1 1h",
		"●(Closed) chat 2 2h",
		"●(Closed) chat 3 3h",
		"●(Closed) chat 4 4h",
		"●(Closed) chat 5 5h",
	})
end)

t.test("a click on the folder row asks to open or close it, and a click on a session asks to resume its file", function()
	local shown = view({ agent({}) }, { session(1, "Plan", HOUR) })
	t.eq(visible.click(shown, "tern-agents"), "recent=" .. KEY)
	t.eq(visible.click(shown, "Plan 1h"), "resume=" .. SESSIONS .. "2026-11-01T08-00-00-000Z_1.jsonl")
end)

t.test("a session that a live process holds open does not show", function()
	t.eq(visible.rows(view({ agent({}) }, {
		session(1, "Plan", HOUR),
		session(2, "Still open", MIN, { open = true }),
	})), { HEAD(1), "●(Closed) Plan 1h" })
end)

t.test("the session of a live agent, found by its working directory and title, does not show", function()
	t.eq(visible.rows(view({ agent({ title = ICON .. "Live chat" }) }, {
		session(1, ICON .. "Live chat", MIN),
		session(2, ICON .. "Live chat", DAY),
		session(3, "Plan", HOUR),
	})), {
		HEAD(2),
		"●(Closed) Plan 1h",
		"●(Closed) Live chat 1d",
	})
end)

t.test("a live agent whose session has no title yet hides the newest untitled session of its folder", function()
	t.eq(visible.rows(view({ agent({ title = "omp" }) }, {
		session(1, nil, MIN),
		session(2, nil, DAY),
	})), { HEAD(1), "●(Closed) Untitled 1d" })
end)

t.test("an exited agent's session shows", function()
	t.eq(visible.rows(view({ agent({ pane = 1, title = "Other" }), agent({ pane = 2, state = "exited" }) }, {
		session(1, ICON .. "Live chat", MIN),
	})), { HEAD(1), "●(Closed) Live chat 1m" })
end)

t.test("a session started in a subfolder or worktree shows under its main repo", function()
	t.eq(visible.rows(view({ agent({}) }, {
		session(1, "In lib", HOUR, { cwd = REPO .. "/lib" }),
		session(2, "In a worktree", 2 * HOUR, { cwd = "/Users/me/checkouts/t09" }),
	})), {
		HEAD(2),
		"●(Closed) In lib 1h",
		"●(Closed) In a worktree 2h",
	})
end)

t.test("a pinned agent's folder lists its closed sessions too", function()
	t.eq(visible.rows(view({ agent({ title = "keep" }) }, { session(1, "Plan", HOUR) }, {
		pins = { { pane = 1, cwd = REPO, title = "keep" } },
	})), { HEAD(1), "●(Closed) Plan 1h" })
end)

t.test("the Live view lists no closed session, and a folded folder there shows only its row", function()
	local agents = { agent({ pane = 1 }), agent({ pane = 2, title = "old", activeAt = NOW - 2 * DAY }) }
	local sessions = { session(1, "Plan", HOUR) }
	t.eq(visible.rows(view(agents, sessions, { view = "live" })), {
		":chev :mi-folder-open tern-agents 2 [:plus](New tab in this repo)",
		"●(Idle) Live chat",
		":chev-r Older 1",
	})
	t.eq(visible.rows(view(agents, sessions, { view = "live", folded = { [KEY] = true } })), {
		":chev-r :mi-folder tern-agents 2 [:plus](New tab in this repo)",
	})
end)

return nil
