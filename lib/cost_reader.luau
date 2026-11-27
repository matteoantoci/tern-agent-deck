--!strict
-- The cost reader: what each live omp session cost, its subagents included. All reads run off the UI thread with
-- `tern.process.run`; their callbacks parse the output (`lib/costs.luau`) and keep the result.
-- - The credential types come from a read-only query of omp's `agent.db` (`sqlite3 -readonly`, no secret column),
--   once per session scan.
-- - The session files come from the session reader's pass that reads the models: the live agents' files and every
--   file in their session folders (one per subagent, at any depth). The reader keeps a byte offset and the running
--   totals per file, and each read takes only the bytes after the offset, so a file of 50 MB is read whole once.

local costs = require("./costs")
local viewModel = require("./view_model")

local reader = {}

-- The credential types. Only columns without secrets: never `data`.
local SQL = "SELECT id, provider, credential_type FROM auth_credentials;"

-- A credential query that takes longer is killed, and no cost shows.
local CREDENTIALS_TIMEOUT = 5 * 1000

-- `$@` the live agents' session files. For each, its size and path, then those of every `.jsonl` file in its
-- session folder (a missing folder prints nothing).
local LIST = [[
for main; do
	/usr/bin/find "$main" "${main%.jsonl}" -name '*.jsonl' -type f -exec /usr/bin/stat -f '%z%t%N' {} + 2>/dev/null
done
]]
-- A listing that takes longer is killed, and the last costs stay.
local LIST_TIMEOUT = 5 * 1000

-- `$@` triples of a start byte, a size and a path. For each file, the bytes from the start to the size go through
-- `awk` (bytes, not characters: `LC_ALL=C`), which prints the cost and the credential id of each assistant message
-- and, at the end, where its last line ends and starts (`lib/costs.luau` reads the records). A JSON string escapes
-- its quotes, so text that quotes the keys does not match.
local READ = [[
COST='{ start = n; n += length($0) + 1 }
substr($0, 1, 17) == "{\"type\":\"message\"" && index($0, "\"role\":\"assistant\"") && match($0, /"usage":\{[^{}]*"cost":\{[^{}]*"total":[-0-9.eE+]+/) {
	usd = substr($0, RSTART, RLENGTH)
	sub(/.*"total":/, "", usd)
	rest = substr($0, RSTART + RLENGTH)
	if (match(rest, /"credentialId":[0-9]+/)) print "C\t" from + n "\t" substr(rest, RSTART + 15, RLENGTH - 15) "\t" usd
}
END { print "E\t" from + n "\t" from + start }'
while [ $# -ge 3 ]; do
	from=$1 size=$2 file=$3
	shift 3
	printf 'F\t%s\t%s\t%s\n' "$from" "$size" "$file"
	/usr/bin/tail -c "+$((from + 1))" -- "$file" 2>/dev/null | /usr/bin/head -c "$((size - from))" |
		LC_ALL=C /usr/bin/awk -v from="$from" "$COST"
done
]]
-- A read that takes longer is killed; the files it read whole still count, and the next read goes on from there.
local READ_TIMEOUT = 15 * 1000

-- The credential types of the last query; nil before the first one ends, or when it failed.
local kinds: costs.Kinds? = nil
-- The session files read so far, with their offsets and totals.
local files: costs.Files = {}
-- The live agents' session files of the last read, sorted.
local mains: { string } = {}
-- The cost of each live session, by its file, from `kinds` and `files`.
local found: { [string]: viewModel.Cost } = {}
local running = false
-- The session files of a read asked for while one ran: it runs when that one ends.
local again: { string }? = nil

local function same(a: { [string]: viewModel.Cost }, b: { [string]: viewModel.Cost }): boolean
	for file, x in a do
		local y = b[file]
		if not y or x.apiUsd ~= y.apiUsd or x.subUsd ~= y.subUsd then
			return false
		end
	end
	for file in b do
		if a[file] == nil then
			return false
		end
	end
	return true
end

-- Sums the costs again; `changed` runs with `cx` when they differ from the last sum.
local function update(cx: WindowCx?, changed: (cx: WindowCx) -> ())
	local now: { [string]: viewModel.Cost } = {}
	for _, main in mains do
		local cost = costs.total(main, files, kinds)
		if cost then
			now[main] = cost
		end
	end
	if not same(found, now) then
		found = now
		if cx then
			changed(cx)
		end
	end
end

--- The cost of each live omp session, by session file, its subagents included; a session with no cost is absent.
function reader.costs(): { [string]: viewModel.Cost }
	return found
end

--- The command that reads the credential types of `home`'s omp: `sqlite3` opens `~/.omp/agent/agent.db` read-only,
--- and the query selects no secret column.
function reader.command(home: string): { string }
	return { "/usr/bin/sqlite3", "-readonly", "-separator", "\t", home .. "/.omp/agent/agent.db", SQL }
end

--- The credential types a query `result` holds, or nil when the query failed, timed out or printed something else.
function reader.kindsOf(result: ProcessResult): costs.Kinds?
	if result.status ~= 0 or result.timed_out then
		return nil
	end
	return costs.credentials(result.stdout)
end

--- Reads the credential types of `home`'s omp. `changed` runs, with a fresh `cx`, when the costs changed.
function reader.readCredentials(home: string?, changed: (cx: WindowCx) -> ())
	if not home then
		return
	end
	local ok, err = pcall(function()
		tern.process.run(reader.command(home), { timeout_ms = CREDENTIALS_TIMEOUT }, function(result: ProcessResult, cx: WindowCx?)
			kinds = reader.kindsOf(result)
			update(cx, changed)
		end)
	end)
	if not ok then
		kinds = nil
		update(nil, changed)
		print("agents: the credential read did not start: " .. tostring(err))
	end
end

-- Ends a read: sums the costs, then runs the read asked for meanwhile.
local function finish(cx: WindowCx?, changed: (cx: WindowCx) -> ())
	running = false
	update(cx, changed)
	local next = again
	if next then
		again = nil
		reader.read(next, changed)
	end
end

-- Reads the new bytes of the files in `sizes` (by path).
local function readNew(sizes: { [string]: number }, changed: (cx: WindowCx) -> ())
	local argv = { "/bin/sh", "-c", READ, "sh" }
	for _, read in costs.plan(sizes, files) do
		table.insert(argv, string.format("%.0f", read.from))
		table.insert(argv, string.format("%.0f", read.size))
		table.insert(argv, read.path)
	end
	if #argv == 4 then
		finish(nil, changed)
		return
	end
	tern.process.run(argv, { timeout_ms = READ_TIMEOUT }, function(result: ProcessResult, cx: WindowCx?)
		-- A read cut by the timeout still holds the files it read whole.
		costs.apply(files, costs.chunks(result.stdout))
		finish(cx, changed)
	end)
end

--- Reads the new bytes of the session files `reported` (by pane) and of the files in their session folders.
--- `changed` runs, with a fresh `cx`, when the costs changed.
function reader.read(reported: { [number]: string }, changed: (cx: WindowCx) -> ())
	local list: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, file in reported do
		if not seen[file] then
			seen[file] = true
			table.insert(list, file)
		end
	end
	table.sort(list)
	if running then
		again = list
		return
	end
	mains = list
	if #list == 0 then
		files = {}
		update(nil, changed)
		return
	end
	running = true
	local argv = { "/bin/sh", "-c", LIST, "sh" }
	for _, file in list do
		table.insert(argv, file)
	end
	local ok, err = pcall(function()
		tern.process.run(argv, { timeout_ms = LIST_TIMEOUT }, function(result: ProcessResult, cx: WindowCx?)
			if result.timed_out then
				finish(cx, changed)
				return
			end
			local sizes = costs.sizes(result.stdout)
			-- A file that is gone, or that no live session holds now, is forgotten.
			for path in files do
				if sizes[path] == nil then
					files[path] = nil
				end
			end
			local started, failure = pcall(function()
				readNew(sizes, changed)
			end)
			if not started then
				print("agents: the cost read did not start: " .. tostring(failure))
				finish(cx, changed)
			end
		end)
	end)
	if not ok then
		running = false
		print("agents: the session file listing did not start: " .. tostring(err))
	end
end

return reader
