--!strict
-- The quota reader: reads the current subscription quotas from omp's `agent.db`. One `tern.process.run` call runs
-- `sqlite3` off the UI thread, with the database opened read-only (omp writes it in WAL mode); its callback parses
-- the output (`lib/quotas.luau`) and keeps the result. The sidebar reads the quotas with each session scan.

local quotas = require("./quotas")
local viewModel = require("./view_model")

local reader = {}

-- The latest `usage_history` row of each account and limit. Only columns without secrets: `account_key` (an api-key
-- account's key holds a fingerprint of the key) only groups the rows and is not printed.
local SQL = [[
SELECT provider, email, window_label, label, used_fraction, status, resets_at FROM (
	SELECT provider, email, window_label, label, used_fraction, status, resets_at,
		row_number() OVER (PARTITION BY provider, account_key, limit_id ORDER BY recorded_at DESC, id DESC) AS n
	FROM usage_history
) WHERE n = 1;
]]

-- A query that takes longer is killed, and no quotas show.
local TIMEOUT = 5 * 1000

-- The quotas of the last query; nil before the first one ends, or when it failed.
local found: { viewModel.Quota }? = nil
local running = false
-- A read asked for while one ran: it runs when that one ends.
local again = false

--- The command that reads the quotas of `home`'s omp: `sqlite3` opens `~/.omp/agent/agent.db` read-only, and the
--- query selects no secret column.
function reader.command(home: string): { string }
	return { "/usr/bin/sqlite3", "-readonly", "-separator", "\t", home .. "/.omp/agent/agent.db", SQL }
end

--- The quotas a query `result` holds: the rows `quotas.parse` reads, or nil when the query failed, timed out or
--- printed something else (`now` is wall-clock milliseconds, as for `quotas.parse`).
function reader.quotasOf(result: ProcessResult, now: number): { viewModel.Quota }?
	if result.status ~= 0 or result.timed_out then
		return nil
	end
	return quotas.parse(result.stdout, now)
end

local function same(a: { viewModel.Quota }?, b: { viewModel.Quota }?): boolean
	if a == nil or b == nil then
		return a == b
	end
	if #a ~= #b then
		return false
	end
	for i, x in a do
		local y = b[i]
		if x.provider ~= y.provider or x.account ~= y.account or x.label ~= y.label or x.used ~= y.used
			or x.status ~= y.status or x.resetsAt ~= y.resetsAt
		then
			return false
		end
	end
	return true
end

--- The quotas of the last read; nil before the first read ends, or when it failed (no `agent.db`, no `sqlite3`, or
--- output of an unknown shape).
function reader.quotas(): { viewModel.Quota }?
	return found
end

--- Reads the quotas of `home`'s omp. `changed` runs, with a fresh `cx`, when they differ from the last read.
function reader.read(home: string?, changed: (cx: WindowCx) -> ())
	if not home then
		return
	end
	if running then
		again = true
		return
	end
	running = true
	local ok, err = pcall(function()
		tern.process.run(reader.command(home), { timeout_ms = TIMEOUT }, function(result: ProcessResult, cx: WindowCx?)
			running = false
			local list = reader.quotasOf(result, os.time() * 1000)
			if not same(found, list) then
				found = list
				if cx then
					changed(cx)
				end
			end
			if again then
				again = false
				reader.read(home, changed)
			end
		end)
	end)
	if not ok then
		running = false
		found = nil
		print("agents: the quota read did not start: " .. tostring(err))
	end
end

return reader
