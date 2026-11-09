--!strict
-- Compact rows (ticket 08, then the Files look): one line each, the name first and only the bell of a waiting agent
-- at the right end; the model, effort, timer and every other fact go to the hover card.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = "/repo", title = "Fix login" }
	for k, v in fields do
		a[k] = v
	end
	return a
end

local function view(agents: { any }, now: number?): any
	return viewModel.build({ agents = agents, now = now or 0 }).view
end

t.test("a working row shows the dot and the name only; the logo, effort and timer are in its card", function()
	local out = view({ agent({ state = "working", model = "Opus 5.5 \u{F0EB}", effort = "high", workingSince = 0 }) }, 12000)
	t.eq(visible.agentRows(out), { "●(Working) Fix login" })
	t.eq(visible.hover(out, "Fix login"), "Fix login · Working\n:provider-anthropic Model Opus 5.5\n◔high Effort high\nWorking for ⏱12s")
end)

t.test("a row shows no model text: an unknown model and an empty effort show nothing on the row", function()
	t.eq(visible.agentRows(view({
		agent({ pane = 1, title = "a", model = "Kimi K2" }),
		agent({ pane = 2, title = "b", effort = "" }),
	})), { "●(Idle) a", "●(Idle) b" })
end)

t.test("the hover card names the agent and its state, its model and its effort, then shows the last message", function()
	local out = view({ agent({ model = "Opus 5.5 \u{F0EB}", effort = "xhigh", lastMessage = "Tests pass." }) })
	t.eq(visible.hover(out, "Fix login"), "Fix login · Idle\n:provider-anthropic Model Opus 5.5\n◔xhigh Effort xhigh\nTests pass.")
end)

t.test("a hover card leaves out what the agent does not tell", function()
	t.eq(visible.hover(view({ agent({ model = "Kimi K2" }) }), "Fix login"), "Fix login · Idle\nModel Kimi K2")
	t.eq(visible.hover(view({ agent({ lastMessage = "Done." }) }), "Fix login"), "Fix login · Idle\nDone.")
end)

t.test("the turn timer counts in the hover card from the start of the turn", function()
	local function card(now: number): string?
		return visible.hover(view({ agent({ state = "working", workingSince = 1000 }) }, now), "Fix login")
	end
	t.eq(card(1000), "Fix login · Working\nWorking for ⏱0s")
	t.eq(card(66000), "Fix login · Working\nWorking for ⏱65s")
end)

t.test("agent names render in the sans face", function()
	t.eq(visible.face(view({ agent({}) }), "Fix login"), "sans")
end)

t.test("a row with a hover card carries no tooltip on itself or on its parts: every fact is in the card", function()
	local out = view({
		agent({ state = "working", model = "Opus 5.5 \u{F0EB}", effort = "high", workingSince = 0, lastMessage = "On it." }),
	}, 12000)
	t.eq(visible.titles(out, "Fix login"), {})
	t.eq(
		visible.hover(out, "Fix login"),
		"Fix login · Working\n:provider-anthropic Model Opus 5.5\n◔high Effort high\nWorking for ⏱12s\nOn it."
	)
	local idle = view({ agent({}) })
	t.eq(visible.titles(idle, "Fix login"), {})
	t.eq(visible.hover(idle, "Fix login"), "Fix login · Idle")
end)

t.test("the focused agent's row is drawn selected, and no other", function()
	local out = viewModel.build({
		agents = { agent({ pane = 1, title = "plan" }), agent({ pane = 2, title = "build" }) },
		now = 0,
		focused = 2,
	}).view
	t.eq(visible.selected(out), { "●(Idle) build" })
	t.eq(visible.selected(view({ agent({}) })), {})
end)

t.test("with no agents, the sidebar shows an empty state that offers a new tab here", function()
	local out = view({})
	t.eq(visible.lines(out), { "No agents running\nStart one here, or run omp in any pane", "New tab here" })
	local empty = visible.find(out, "empty") :: any
	t.eq(empty.c[1].p.actions.click, "new-here")
end)

t.test("a folder's name renders in the sans face, and the short path in its hover card in the mono face", function()
	local out = viewModel.build({
		agents = { agent({ repo = "/Users/me/alpha" }) },
		now = 0,
		home = "/Users/me",
	}).view
	t.eq(visible.face(out, "alpha"), "sans")
	t.eq(visible.face(out, "~/alpha"), "mono")
	t.eq(visible.face(out, "Fix login"), "sans")
end)

return nil
