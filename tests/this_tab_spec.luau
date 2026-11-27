--!strict
-- This tab's agent: the focused agent, else (the sidebar, a shell or nothing has the focus) the stored agent when it
-- sits in the active tab, the active tab's main agent, then the stored agent.
local t = require("./harness")
local viewModel = require("../lib/view_model")

local function agent(pane: number, tab: number?, state: string?): any
	return { pane = pane, tab = tab, state = state or "idle" }
end

local AGENTS = { agent(12, 2), agent(4, 2), agent(8, 3), agent(3, 3, "exited") }
-- A sidebar canvas or a shell: not an agent pane.
local SIDEBAR = 99

t.test("a focused agent is this tab's agent", function()
	t.eq(viewModel.thisTabAgent(AGENTS, 12, 2, 8), 12)
end)

t.test("with the sidebar focused, the stored agent wins when it sits in the active tab", function()
	t.eq(viewModel.thisTabAgent(AGENTS, SIDEBAR, 2, 12), 12)
end)

t.test("with the sidebar focused after a reload, the active tab's main agent is this tab's agent", function()
	t.eq(viewModel.thisTabAgent(AGENTS, SIDEBAR, 2, nil), 4)
	t.eq(viewModel.thisTabAgent(AGENTS, SIDEBAR, 2, 8), 4)
end)

t.test("the main agent skips exited agents", function()
	t.eq(viewModel.thisTabAgent(AGENTS, SIDEBAR, 3, nil), 8)
end)

t.test("with no agent in the active tab, or no focus, the stored agent is kept", function()
	t.eq(viewModel.thisTabAgent(AGENTS, SIDEBAR, 7, 8), 8)
	t.eq(viewModel.thisTabAgent(AGENTS, nil, nil, 8), 8)
	t.eq(viewModel.thisTabAgent(AGENTS, nil, nil, nil), nil)
end)

return nil
