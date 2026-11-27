--!strict
-- The output of the quota reader's query of omp's `agent.db`, parsed. Pure: the reader runs `sqlite3` with
-- `tern.process.run`, off the UI thread, and hands its output here, so the `luau` CLI tests it.
--
-- The query prints the latest `usage_history` row of each account and limit, one per line, tab-separated: the
-- provider, the account's email, the window (`7 Day`, `5 Hour`, `Weekly`), the limit's name, the fraction used, the
-- status (`ok`, `warning`, `exhausted`) and the reset (wall-clock milliseconds). A NULL prints as an empty field.

local viewModel = require("./view_model")

local quotas = {}

-- The display names of the providers the sidebar knows; another provider shows under its own name.
local PROVIDER: { [string]: string } = {
	anthropic = "Claude",
	xai = "Grok",
	["xai-oauth"] = "Grok",
	["google-antigravity"] = "Gemini",
}

type Status = "ok" | "warning" | "exhausted"

local STATUS: { [string]: Status } = { ok = "ok", warning = "warning", exhausted = "exhausted" }

-- How many fields each row has.
local FIELDS = 7

-- `7 Day` → `7d`, `5 Hour` → `5h`; another window (`Weekly`) stays as it is.
local function window(label: string): string
	local n, unit = string.match(label, "^(%d+)%s*(%a+)$")
	if n and unit then
		local word = string.lower(unit)
		if word == "hour" or word == "hours" then
			return n .. "h"
		elseif word == "day" or word == "days" then
			return n .. "d"
		end
	end
	return label
end

-- The window as the line shows it, with the qualifier that ends the limit's name (`Claude 7 Day (Fable)` → `7d
-- Fable`), so that two limits of one window stay apart. When the parenthesis only repeats the window, the name
-- before it is the qualifier (`GrokChat (Weekly)` → `Weekly GrokChat`).
local function label(windowLabel: string, limit: string): string
	if windowLabel == "" then
		return window(limit)
	end
	local shown = window(windowLabel)
	local before, qualifier = string.match(limit, "^%s*(.-)%s*%(%s*(.-)%s*%)%s*$")
	if qualifier and string.lower(qualifier) == string.lower(windowLabel) then
		qualifier = before
	end
	if qualifier and qualifier ~= "" and string.lower(qualifier) ~= string.lower(windowLabel) then
		return shown .. " " .. qualifier
	end
	return shown
end

local function split(line: string): { string }
	local out: { string } = {}
	local start = 1
	while true do
		local tab = string.find(line, "\t", start, true)
		if not tab then
			table.insert(out, string.sub(line, start))
			return out
		end
		table.insert(out, string.sub(line, start, tab - 1))
		start = tab + 1
	end
end

--- The quotas in `output` whose window resets after `now` (wall-clock milliseconds), in the order of the output;
--- a row with a status the plugin does not know is left out. Nil when a line has another shape (another schema, or
--- an error message), so that the sidebar shows no quota line rather than a wrong one.
function quotas.parse(output: string, now: number): { viewModel.Quota }?
	local found: { viewModel.Quota } = {}
	for line in string.gmatch(output, "[^\n]+") do
		local fields = split(line)
		if #fields ~= FIELDS then
			return nil
		end
		local provider, email, windowLabel, limit, usedText, statusText, resetText = table.unpack(fields)
		local used = tonumber(usedText)
		local resetsAt = if resetText == "" then nil else tonumber(resetText)
		if provider == "" or not used or (resetText ~= "" and not resetsAt) then
			return nil
		end
		local status: Status? = STATUS[statusText]
		if status and resetsAt and resetsAt > now then
			local account = string.match(email, "^([^@]+)")
			local quota: viewModel.Quota = {
				provider = PROVIDER[provider] or provider,
				account = account,
				label = label(windowLabel, limit),
				used = used,
				status = status,
				resetsAt = resetsAt,
			}
			table.insert(found, quota)
		end
	end
	return found
end

return quotas
