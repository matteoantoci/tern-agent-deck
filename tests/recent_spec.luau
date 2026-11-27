--!strict
-- The Recent view lists the closed omp sessions by day (Today, Yesterday, This week, then Earlier folded with its
-- count), and inside each day by project, with the same project labels as Live. Each session is one line: its title
-- icon, its title, its age and, on hover, the resume icon.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local DECK = "/Users/me/Personal/tern-agent-deck"
local PI = "/Users/me/Personal/oh-my-pi"
local SESSIONS = "/Users/me/.omp/agent/sessions/-Personal-tern-agent-deck/"
local ICON = "\u{F0403}"
-- Local noon, so that 12 hours back is the start of today and 36 hours back the start of yesterday.
local NOW = os.time({ year = 2026, month = 11, day = 25, hour = 12, min = 0, sec = 0 })
local MIN, HOUR, DAY = 60, 60 * 60, 24 * 60 * 60

local DECK_LABEL = "tern-agent-deck [:plus](New tab in this repo)"
local PI_LABEL = "oh-my-pi [:plus](New tab in this repo)"

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = DECK, repo = DECK, title = ICON .. " Live chat" }
	for k, v in fields do
		a[k] = v
	end
	return a
end

local function file(n: number): string
	return SESSIONS .. string.format("2026-11-0%dT08-00-00-000Z_%d.jsonl", n, n)
end

-- A closed omp session of `DECK`, `ago` seconds since its last write.
local function session(n: number, title: string?, ago: number, fields: { [string]: any }?): { [string]: any }
	local s: { [string]: any } = { file = file(n), id = "s" .. n, cwd = DECK, repo = DECK, title = title, at = NOW - ago }
	for k, v in (fields or {}) :: { [string]: any } do
		s[k] = v
	end
	if s.repo == false then
		s.repo = nil
	end
	return s
end

-- A closed session's line: its title icon, its title, its age and the resume icon.
local function line(title: string, age: string, glyph: boolean?): string
	return (if glyph == false then ":sparkle" else ICON) .. "(Closed) " .. title .. " " .. age .. " :play"
end

local function view(agents: { any }, sessions: { any }, extra: { [string]: any }?): any
	local input: { [string]: any } = { agents = agents, sessions = sessions, now = 0, time = NOW, home = HOME, view = "recent" }
	for k, v in (extra or {}) :: { [string]: any } do
		input[k] = v
	end
	return viewModel.build(input :: any).view
end

t.test("closed sessions group by day: Today, Yesterday, This week, then Earlier folded with its count", function()
	local shown = view({}, {
		session(1, ICON .. " Plan", 2 * HOUR),
		session(2, ICON .. " Fix login", 20 * HOUR),
		session(3, ICON .. " Old", 3 * DAY),
		session(4, ICON .. " Older", 8 * DAY),
		session(5, ICON .. " Oldest", 40 * DAY),
	})
	t.eq(visible.zones(shown), { "Today 1", "Yesterday 1", "This week 1", ":chev-r Earlier 2" })
	t.eq(visible.zone(shown, "Today"), { DECK_LABEL, line("Plan", "2h") })
	t.eq(visible.zone(shown, "Yesterday"), { DECK_LABEL, line("Fix login", "20h") })
	t.eq(visible.zone(shown, "This week"), { DECK_LABEL, line("Old", "3d") })
	t.eq(visible.zone(shown, "Earlier"), {})
	t.eq(visible.click(shown, "Earlier"), "earlier")
end)

t.test("the days follow local midnights, not 24-hour spans", function()
	local shown = view({}, {
		session(1, "a", 12 * HOUR - MIN),
		session(2, "b", 12 * HOUR + MIN),
		session(3, "c", 36 * HOUR + MIN),
		session(4, "d", 6 * DAY + 12 * HOUR - MIN),
		session(5, "e", 6 * DAY + 12 * HOUR + MIN),
	})
	t.eq(visible.zones(shown), { "Today 1", "Yesterday 1", "This week 2", ":chev-r Earlier 1" })
end)

t.test("an open Earlier lists its sessions by project", function()
	local shown = view({}, { session(1, "Old", 9 * DAY), session(2, "Older", 10 * DAY, { cwd = PI, repo = PI }) }, {
		earlierOpen = true,
	})
	t.eq(visible.zones(shown), { ":chev Earlier 2" })
	t.eq(visible.zone(shown, "Earlier"), { DECK_LABEL, line("Old", "9d", false), PI_LABEL, line("Older", "10d", false) })
end)

t.test("inside a day, the project with the newest session comes first, and its sessions newest first", function()
	local shown = view({}, {
		session(1, "deck old", 5 * HOUR),
		session(2, "pi new", 1 * HOUR, { cwd = PI, repo = PI }),
		session(3, "deck new", 2 * HOUR),
		session(4, "loose", 3 * HOUR, { cwd = "", repo = false }),
	})
	t.eq(visible.zone(shown, "Today"), {
		PI_LABEL,
		line("pi new", "1h", false),
		DECK_LABEL,
		line("deck new", "2h", false),
		line("deck old", "5h", false),
		"No folder",
		line("loose", "3h", false),
	})
end)

t.test("a session in a subfolder or outside any repo shows under its project's label", function()
	local shown = view({}, {
		session(1, "In lib", HOUR, { cwd = DECK .. "/lib" }),
		session(2, "Plain", 2 * HOUR, { cwd = "/Users/me/notes/", repo = false }),
	})
	t.eq(visible.zone(shown, "Today"), {
		DECK_LABEL,
		line("In lib", "1h", false),
		"notes [:plus](New tab in this folder)",
		line("Plain", "2h", false),
	})
	t.eq(visible.hover(shown, "notes"), "~/notes")
end)

t.test("an untitled session shows as Untitled with Tern's agent icon", function()
	t.eq(visible.zone(view({}, { session(1, nil, 30), session(2, "", 5 * MIN) }), "Today"), {
		DECK_LABEL,
		line("Untitled", "30s", false),
		line("Untitled", "5m", false),
	})
end)

t.test("a click on a session resumes its file in a new tab; the resume icon shows on hover", function()
	local shown = view({}, { session(1, ICON .. " Plan", HOUR) })
	t.eq(visible.click(shown, "Plan"), "resume=" .. file(1))
	t.eq(visible.onHover(shown, "Plan"), { ":play" })
	t.eq(visible.menu(shown, "Plan"), {
		"Copy session ID → copy-id=" .. file(1),
		"Copy session path → copy-path=" .. file(1),
	})
end)

t.test("with no closed session, Recent shows one calm line", function()
	t.eq(visible.lines(view({}, {})), { "No closed omp sessions yet" })
end)

t.test("a session that a live process holds open does not show", function()
	t.eq(visible.zone(view({}, { session(1, "Plan", HOUR), session(2, "Still open", MIN, { open = true }) }), "Today"), {
		DECK_LABEL,
		line("Plan", "1h", false),
	})
end)

t.test("the session of a live agent, found by its working directory and title, does not show", function()
	local shown = view({ agent({}) }, {
		session(1, ICON .. " Live chat", MIN),
		session(2, ICON .. " Live chat", 2 * HOUR),
		session(3, "Plan", HOUR),
	})
	t.eq(visible.zone(shown, "Today"), { DECK_LABEL, line("Plan", "1h", false), line("Live chat", "2h") })
end)

t.test("a live agent whose session has no title yet hides the newest untitled session of its folder", function()
	t.eq(visible.zone(view({ agent({ title = "omp" }) }, { session(1, nil, MIN), session(2, nil, HOUR) }), "Today"), {
		DECK_LABEL,
		line("Untitled", "1h", false),
	})
end)

t.test("an exited agent's session shows", function()
	local shown = view({ agent({ pane = 1, title = "Other" }), agent({ pane = 2, state = "exited" }) }, {
		session(1, ICON .. " Live chat", MIN),
	})
	t.eq(visible.zone(shown, "Today"), { DECK_LABEL, line("Live chat", "1m") })
end)

t.test("the Live view lists no closed session", function()
	t.eq(visible.zones(view({ agent({}) }, { session(1, "Plan", HOUR) }, { view = "live" })), { "■ Idle 1" })
end)

-- A canvas update holds at most 2000 nodes and 256 KiB, so the whole view shows at most its 50 newest sessions and
-- then one muted "N more" line that takes no click.
t.test("an open Earlier with 500 sessions shows its 50 newest, then one line for the rest", function()
	local many: { any } = {}
	for n = 1, 500 do
		table.insert(many, session(n, "Old " .. n, 8 * DAY + n * HOUR, { file = SESSIONS .. n .. ".jsonl" }))
	end
	local shown = view({}, many, { earlierOpen = true })
	local nodes = visible.size(shown)
	t.eq(nodes < 1500, true)
	local lines = visible.zone(shown, "Earlier")
	t.eq(lines[#lines], ":more 450 more")
	t.eq(lines[2], line("Old 1", "8d", false))
	t.eq(lines[51], line("Old 50", "10d", false))
	t.eq(visible.click(shown, "450 more"), nil)
end)

t.test("a day with more than 50 sessions is capped the same way", function()
	local many: { any } = {}
	for n = 1, 60 do
		table.insert(many, session(n, "T" .. n, n * MIN, { file = SESSIONS .. n .. ".jsonl" }))
	end
	local lines = visible.zone(view({}, many), "Today")
	t.eq(#lines, 52)
	t.eq(lines[52], ":more 10 more")
end)

t.test("the cap counts the sessions of every day: the view with all days and Earlier open fits one canvas update", function()
	-- Real-length session paths in 8 projects, 30 sessions each in Today, Yesterday and This week, 500 in Earlier.
	local many: { any } = {}
	local n = 0
	local function add(title: string, ago: number)
		n += 1
		local project = "/Users/me/Personal/project-with-a-long-name-" .. (n % 8)
		local folder = "/Users/me/.omp/agent/sessions/-Personal-project-with-a-long-name-" .. (n % 8) .. "/"
		local path = folder .. string.format("2026-11-%02dT08-21-12-853Z_01a1bf65-95ef-77f9-baad-ec9dc64f%04d.jsonl", 1 + n % 28, n)
		table.insert(many, session(n, ICON .. " " .. title .. " with a title of usual length", ago, { file = path, cwd = project, repo = project }))
	end
	for i = 1, 30 do
		add("Today " .. i, i * MIN)
	end
	for i = 1, 30 do
		add("Yesterday " .. i, 13 * HOUR + i * MIN)
	end
	for i = 1, 30 do
		add("Week " .. i, 37 * HOUR + i * MIN)
	end
	for i = 1, 500 do
		add("Old " .. i, 8 * DAY + i * HOUR)
	end
	local shown = view({}, many, { earlierOpen = true })
	local nodes, bytes = visible.size(shown)
	t.eq(nodes < 1500, true)
	t.eq(bytes < 256 * 1024, true)
	t.eq(#visible.zone(shown, "Today") > 0, true)
	local yesterday = visible.zone(shown, "Yesterday")
	t.eq(yesterday[#yesterday], ":more 40 more")
	-- This week has no place left, so it does not show.
	t.eq(#visible.zones(shown), 3)
	t.eq(visible.zone(shown, "Earlier"), { ":more 500 more" })
end)

return nil
