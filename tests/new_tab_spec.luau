--!strict
-- A folder's `+` and the ⋯ menu's "New tab here" open a new tab in a folder that runs what Tern's own New tab runs:
-- the user's "New tabs and splits open" preference (`new_blocks`, a shell or an agent), the agent through the user's
-- agent command (`agent_command`).
local t = require("./harness")
local newTab = require("../lib/new_tab")

local FOLDER = "/Users/me/Personal/tern-agents"

t.test("with new tabs set to open a shell, the new tab runs a shell in the folder", function()
	t.eq(newTab.launch(FOLDER, "Shell", "omp"), { cwd = FOLDER })
end)

t.test("with new tabs set to open an agent, the new tab runs the agent command in the folder", function()
	t.eq(newTab.launch(FOLDER, "Agent", "omp --model opus"), { cwd = FOLDER, command = "omp --model opus" })
end)

t.test("the preference's letter case does not matter", function()
	t.eq(newTab.launch(FOLDER, "agent", "omp"), { cwd = FOLDER, command = "omp" })
end)

t.test("an agent preference without an agent command runs a shell, as an unknown preference does", function()
	t.eq(newTab.launch(FOLDER, "Agent", nil), { cwd = FOLDER })
	t.eq(newTab.launch(FOLDER, "Agent", "  "), { cwd = FOLDER })
	t.eq(newTab.launch(FOLDER, nil, "omp"), { cwd = FOLDER })
end)

return nil
