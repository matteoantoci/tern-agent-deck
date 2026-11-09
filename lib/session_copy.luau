--!strict
-- What the "Copy session ID" and "Copy session path" items of a row's right-click menu copy. Pure: the sidebar reads
-- the start of the session file off the UI thread and hands it here, so the `luau` CLI tests it.

local sessions = require("./sessions")

local sessionCopy = {}

--- The menu item's action: `copy-id` or `copy-path`.
export type Act = "copy-id" | "copy-path"

--- The text to put on the clipboard (nil when nothing is copied) and the toast that says what happened.
export type Result = { text: string?, level: "success" | "error", toast: string, sub: string? }

local WHAT: { [Act]: string } = { ["copy-id"] = "session ID", ["copy-path"] = "session path" }

--- What a click on `act` for the omp session file `file` copies, given `head`, the file's first bytes (nil when it
--- could not be read). The ID is omp's session id from the file's header, the one `omp --resume <id>` takes; the path
--- is `file`. A file that is not there copies nothing.
function sessionCopy.resolve(act: Act, file: string, head: string?): Result
	local what = WHAT[act]
	if head == nil then
		return { level = "error", toast = "Could not copy the " .. what, sub = "No session file at " .. file }
	end
	local text = file
	if act == "copy-id" then
		local id = sessions.id(head)
		if not id or id == "" then
			return { level = "error", toast = "Could not copy the " .. what, sub = "The file has no omp session header" }
		end
		text = id
	end
	return { text = text, level = "success", toast = "Copied " .. what }
end

return sessionCopy
