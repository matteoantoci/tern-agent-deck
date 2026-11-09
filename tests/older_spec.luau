--!strict
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local REPO = "/Users/me/Personal/tern-agents"
local KEY = "repo-_2FUsers_2Fme_2FPersonal_2Ftern-agents"
local function HEAD(count: number): string
	return string.format(":chev :mi-folder-open tern-agents %d [:plus](New tab in this repo)", count)
end

local DAY = 24 * 60 * 60
local NOW = 1_800_000_000

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = REPO, title = "Fix login" }
	if fields.cwd == nil then
		a.repo = REPO
	end
	for k, v in fields do
		a[k] = v
	end
	return a
end

local function view(agents: { any }, extra: { [string]: any }?): any
	local input: { [string]: any } = { agents = agents, now = 0, time = NOW, home = HOME }
	for k, v in (extra or {}) :: { [string]: any } do
		input[k] = v
	end
	return viewModel.build(input :: any).view
end

local function sample(): { any }
	return {
		agent({ pane = 1, title = "old plan", activeAt = NOW - 2 * DAY }),
		agent({ pane = 2, title = "today", activeAt = NOW - 3600 }),
		agent({ pane = 3, title = "old review", activeAt = NOW - DAY }),
	}
end

t.test("idle agents idle for a day or more fold into a closed Older row, with its count, after the group's other rows", function()
	t.eq(visible.rows(view(sample())), { HEAD(3), "●(Idle) today", ":chev-r Older 2" })
end)

t.test("the sidebar redraws when the next idle agent reaches a day, and not while none will", function()
	local input = { agents = sample(), now = 0, time = NOW, home = HOME }
	t.eq(viewModel.olderDue(input :: any), DAY - 3600)
	local working = { agents = { agent({ state = "working", activeAt = NOW - 3600 }) }, now = 0, time = NOW }
	t.eq(viewModel.olderDue(working :: any), nil)
end)

t.test("an open Older row shows its agents under it, in start order", function()
	t.eq(visible.rows(view(sample(), { olderOpen = { [KEY] = true } })), {
		HEAD(3),
		"●(Idle) today",
		":chev Older 2",
		"●(Idle) old plan",
		"●(Idle) old review",
	})
end)

t.test("a click on the Older row asks to open or close that group's Older row", function()
	t.eq(visible.click(view(sample()), "Older 2"), "older=" .. KEY)
end)

t.test("each folder has its own Older row and open state", function()
	local agents = sample()
	table.insert(agents, agent({ pane = 4, title = "old scratch", cwd = "/tmp", activeAt = NOW - 3 * DAY }))
	t.eq(visible.rows(view(agents, { olderOpen = { ["repo-_2Ftmp"] = true } })), {
		HEAD(3),
		"●(Idle) today",
		":chev-r Older 2",
		":chev :mi-folder-open tmp 1 [:plus](New tab in this folder)",
		":chev Older 1",
		"●(Idle) old scratch",
	})
end)

t.test("working and waiting agents never fold, however long ago their last turn ended", function()
	t.eq(visible.rows(view({
		agent({ pane = 1, title = "busy", state = "working", workingSince = 0, activeAt = NOW - 5 * DAY }),
		agent({ pane = 2, title = "asks", state = "waiting_input", activeAt = NOW - 5 * DAY }),
	})), { ":bell Needs you 1", "●(Waiting for you) asks tern-agents :bell", HEAD(2), "●(Working) busy …", "●(Waiting for you) asks :bell" })
end)

t.test("an agent never seen in a turn counts as new", function()
	t.eq(visible.rows(view({ agent({ title = "unknown age" }) })), { HEAD(1), "●(Idle) unknown age" })
end)

t.test("a pinned idle agent stays in Pinned however old it is", function()
	t.eq(visible.rows(view({ agent({ pane = 1, title = "keep", activeAt = NOW - 9 * DAY }) }, {
		pins = { { pane = 1, cwd = REPO, title = "keep" } },
	})), { ":pin Pinned 1", "●(Idle) keep" })
end)

t.test("agents outside any repo get their Older row in their working directory's section", function()
	t.eq(visible.rows(view({
		agent({ pane = 1, title = "old", cwd = "/tmp", activeAt = NOW - 2 * DAY }),
		agent({ pane = 2, title = "new", cwd = "/tmp", activeAt = NOW }),
	})), { ":chev :mi-folder-open tmp 2 [:plus](New tab in this folder)", "●(Idle) new", ":chev-r Older 1" })
end)

return nil
