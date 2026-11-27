--!strict
-- The cost lines of an omp agent's hover card: the real money spent through API-key accounts, then the subscription
-- use at list price, muted; none for an agent with no cost or that is not omp. Rows show no cost.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local ICON = "\u{F0E7}"
local NOW = 1_800_000_000
local FILE = "/Users/me/.omp/agent/sessions/a/1.jsonl"
local HINT = "Click: go to it · Right-click: Pin, Rename, Copy session ID or path"

-- An idle omp agent in pane 4 of tab 3 that ran two subagents.
local function build(cost: { [string]: any }?, fields: { [string]: any }?): any
	local agent: { [string]: any } = {
		pane = 4,
		tab = 3,
		state = "idle",
		cwd = "/Users/me/repo",
		repo = "/Users/me/repo",
		title = ICON .. " Fix login",
		activeAt = NOW - 60,
		sessionFile = FILE,
		route = "anthropic/claude-opus-5-5",
	}
	for k, v in (fields or {}) :: { [string]: any } do
		agent[k] = v
	end
	local input: { [string]: any } = {
		agents = { agent },
		now = 0,
		time = NOW,
		home = "/Users/me",
		subagents = { [4] = { agents = { { id = "A", name = "A", status = "done", depth = 1 } } } },
		cost = cost,
	}
	return viewModel.build(input :: any).view
end

local function card(lines: { string }): string
	local out = { ICON .. " Idle 1m tab 3", "Fix login", "omp · anthropic/claude-opus-5-5" }
	for _, line in lines do
		table.insert(out, line)
	end
	table.insert(out, "Subagents: 1 done")
	table.insert(out, HINT)
	return table.concat(out, "\n")
end

t.test("an agent on API-key accounts shows what it spent, after its facts and before its subagents", function()
	local out = build({ [FILE] = { apiUsd = 3.84, subUsd = 0 } })
	t.eq(visible.hover(out, "Fix login"), card({ "Spent $3.84" }))
	t.eq(table.find(visible.hoverMuted(out, "Fix login"), "Spent $3.84"), nil)
end)

t.test("an agent on subscription accounts shows its use at API prices, muted", function()
	local out = build({ [FILE] = { apiUsd = 0, subUsd = 33.61 } })
	t.eq(visible.hover(out, "Fix login"), card({ "≈ $33.61 at API prices" }))
	t.eq(table.find(visible.hoverMuted(out, "Fix login"), "≈ $33.61 at API prices") ~= nil, true)
end)

t.test("an agent on both kinds of account shows both lines, the money spent first", function()
	local out = build({ [FILE] = { apiUsd = 0.4249, subUsd = 21.4 } })
	t.eq(visible.hover(out, "Fix login"), card({ "Spent $0.42", "≈ $21.40 at API prices" }))
end)

t.test("an amount under one cent shows as <$0.01", function()
	local out = build({ [FILE] = { apiUsd = 0.004, subUsd = 0.0001 } })
	t.eq(visible.hover(out, "Fix login"), card({ "Spent <$0.01", "≈ <$0.01 at API prices" }))
end)

t.test("an agent with no cost, a zero cost, or that is not omp shows no cost line", function()
	t.eq(visible.hover(build(nil), "Fix login"), card({}))
	t.eq(visible.hover(build({ [FILE] = { apiUsd = 0, subUsd = 0 } }), "Fix login"), card({}))
	local other = build(
		{ [FILE] = { apiUsd = 3, subUsd = 4 } },
		{ sessionFile = false, route = false, command = "claude", model = "opus" }
	)
	t.eq(string.find(visible.hover(other, "Fix login") or "", "$", 1, true), nil)
end)

t.test("rows show no cost", function()
	local out = build({ [FILE] = { apiUsd = 3.84, subUsd = 33.61 } })
	for _, row in visible.rows(out) do
		t.eq(string.find(row, "$", 1, true), nil)
	end
end)

return nil
