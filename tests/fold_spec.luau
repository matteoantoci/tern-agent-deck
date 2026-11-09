--!strict
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local REPO = "/Users/me/Personal/tern-agents"
local KEY = "repo-_2FUsers_2Fme_2FPersonal_2Ftern-agents"
local DAY = 24 * 60 * 60
local NOW = 1_800_000_000

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = REPO, repo = REPO, title = "Fix login" }
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

t.test("an open folder row shows an open chevron and folder, and a click on it asks to fold it", function()
	local shown = view({ agent({}) })
	t.eq(visible.rows(shown), {
		":chev :mi-folder-open tern-agents 1 [:plus](New tab in this repo)",
		"●(Idle) Fix login",
	})
	t.eq(visible.click(shown, "tern-agents"), "fold=" .. KEY)
end)

t.test("a folded folder shows only its row, with a closed chevron and folder and the agent count", function()
	t.eq(visible.rows(view({
		agent({ pane = 1 }),
		agent({ pane = 2, title = "old", activeAt = NOW - 2 * DAY }),
	}, { folded = { [KEY] = true } })), {
		":chev-r :mi-folder tern-agents 2 [:plus](New tab in this repo)",
	})
end)

t.test("folding one folder leaves the others open", function()
	local scratch = agent({ pane = 2, title = "scratch", cwd = "/tmp" })
	scratch.repo = nil
	t.eq(visible.rows(view({ agent({ pane = 1 }), scratch }, { folded = { [KEY] = true } })), {
		":chev-r :mi-folder tern-agents 1 [:plus](New tab in this repo)",
		":chev :mi-folder-open tmp 1 [:plus](New tab in this folder)",
		"●(Idle) scratch",
	})
end)

t.test("a folded folder still lists its waiting agents in Needs you", function()
	t.eq(visible.rows(view({ agent({ state = "waiting_input" }) }, { folded = { [KEY] = true } })), {
		":bell Needs you 1",
		"●(Waiting for you) Fix login tern-agents :bell",
		":chev-r :mi-folder tern-agents 1 [:plus](New tab in this repo)",
	})
end)

return nil
