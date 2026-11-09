--!strict
-- What a new tab in a given folder runs, so that it runs what Tern's own New tab (⌘T) runs.
--
-- Tern's `new_tab` command follows the "New tabs and splits open" preference (`new_blocks`: `Shell` or `Agent`) but
-- starts where the `new_tabs` preference says (the home folder, or the focused block's), and takes no folder.
-- `cx.layout:new_tab` takes the folder, but an empty launch always runs a shell. A tab whose launch `command` is the
-- user's `agent_command` is the agent block Tern's New tab opens (Tern 0.9.13, checked on a headless Tern: the pane's
-- kind is `agent`). Pure: the caller reads the two preferences from `cx.settings`.

local newTab = {}

--- The launch of a new tab in `folder`: the agent command when `newBlocks` (the `new_blocks` preference) says
--- `Agent` and `agentCommand` is not blank, else a shell.
function newTab.launch(folder: string, newBlocks: string?, agentCommand: string?): Launch
	local launch: Launch = { cwd = folder }
	if
		type(newBlocks) == "string"
		and string.lower(newBlocks) == "agent"
		and type(agentCommand) == "string"
		and string.match(agentCommand, "%S")
	then
		launch.command = agentCommand
	end
	return launch
end

return newTab
