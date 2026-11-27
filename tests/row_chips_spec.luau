--!strict
-- Quiet rows: one line each, the title icon, the title and one time; the model, effort, turn timer and every other
-- fact go to the hover card.
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

-- What a right-click offers an idle agent that reported no session file, as its hover card's hint says.
local HINT = "Click: go to it · Right-click: Pin"

t.test("a working row shows its icon, its name and its turn time only; the model and effort are in its card", function()
	local out = view({ agent({ state = "working", model = "Opus 5.5 \u{F0EB}", effort = "high", workingSince = 0 }) }, 12000)
	t.eq(visible.agentRows(out), { ":terminal(Working) Fix login 12s" })
	t.eq(visible.hover(out, "Fix login"), ":terminal Working ⏱12s\nFix login\nopus 5.5 high\nClick: go to it · Right-click: Pin, Interrupt")
end)

t.test("a row shows no model text: an unknown model and an empty effort show nothing on the row", function()
	t.eq(visible.agentRows(view({
		agent({ pane = 1, title = "a", model = "Kimi K2" }),
		agent({ pane = 2, title = "b", effort = "" }),
	})), { ":terminal(Idle) a", ":terminal(Idle) b" })
end)

t.test("the hover card names the agent and its state, shows the last message, then its model and its effort", function()
	local out = view({ agent({ model = "Opus 5.5 \u{F0EB}", effort = "xhigh", lastMessage = "Tests pass." }) })
	t.eq(visible.hover(out, "Fix login"), ":terminal Idle\nFix login\nTests pass.\nopus 5.5 xhigh\n" .. HINT)
end)

t.test("a hover card leaves out what the agent does not tell", function()
	t.eq(visible.hover(view({ agent({ model = "Kimi K2" }) }), "Fix login"), ":terminal Idle\nFix login\nkimi k2\n" .. HINT)
	t.eq(visible.hover(view({ agent({ lastMessage = "Done." }) }), "Fix login"), ":terminal Idle\nFix login\nDone.\n" .. HINT)
end)

t.test("the turn timer counts in the hover card from the start of the turn", function()
	local function top(now: number): string
		local card = visible.hover(view({ agent({ state = "working", workingSince = 1000 }) }, now), "Fix login") or ""
		return string.match(card, "^[^\n]*") :: string
	end
	t.eq(top(1000), ":terminal Working ⏱0s")
	t.eq(top(66000), ":terminal Working ⏱65s")
end)

t.test("a long last message shows its summary; before the summary arrives, its first 280 bytes", function()
	local long = string.rep("The sidebar now resumes pinned sessions and keeps omp's icon. ", 6) .. "Done."
	local waiting = view({ agent({ lastMessage = long }) })
	local function card(message: string): string
		return ":terminal Idle\nFix login\n" .. message .. "\n" .. HINT
	end
	t.eq(visible.hover(waiting, "Fix login"), card(string.sub(long, 1, 280) .. "…"))
	local pending = view({ agent({ lastMessage = long, summarizing = true }) })
	t.eq(visible.hover(pending, "Fix login"), card("Summarizing the last message…"))
	local summed = view({ agent({ lastMessage = long, summary = "Pins resume their sessions; titles keep omp's icon." }) })
	t.eq(visible.hover(summed, "Fix login"), card("Pins resume their sessions; titles keep omp's icon."))
	t.eq(viewModel.needsSummary(long), true)
	t.eq(viewModel.needsSummary("Tests pass."), false)
end)

t.test("agent names render in the sans face", function()
	t.eq(visible.face(view({ agent({}) }), "Fix login"), "sans")
end)

t.test("a row with a hover card carries no tooltip on itself or on its parts: every fact is in the card", function()
	local out = view({
		agent({ state = "working", model = "Opus 5.5 \u{F0EB}", effort = "high", workingSince = 0, lastMessage = "On it." }),
	}, 12000)
	t.eq(visible.titles(out, "Fix login"), {})
	local idle = view({ agent({}) })
	t.eq(visible.titles(idle, "Fix login"), {})
	t.eq(visible.hover(idle, "Fix login"), ":terminal Idle\nFix login\n" .. HINT)
end)

t.test("the focused agent's row is drawn selected, and no other", function()
	local out = viewModel.build({
		agents = { agent({ pane = 1, title = "plan" }), agent({ pane = 2, title = "build" }) },
		now = 0,
		focused = 2,
	}).view
	t.eq(visible.selected(out), { ":terminal(Idle) build" })
	t.eq(visible.selected(view({ agent({}) })), {})
end)

t.test("a project's name renders in the sans face, and the short path in its hover card in the mono face", function()
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
