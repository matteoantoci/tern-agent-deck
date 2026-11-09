--!strict
-- The session reader: finds the omp sessions for the Recent view. One `tern.process.run` call scans
-- `~/.omp/agent/sessions` off the UI thread; its callback parses the output (`lib/sessions.luau`, about 3 ms for 357
-- files) and keeps the result. The scan runs at most once a minute, and again when an agent finishes a turn.
-- It also reads the session file each pane's omp reported to Tern, from `tern inspect --json` (about 30 ms, off the
-- UI thread too): the session of a live agent.

local sessions = require("./sessions")
local viewModel = require("./view_model")

local reader = {}

-- How many of the newest files of each folder the scan reads: a folder's sessions sort by the `<ISO time>_` prefix
-- of their names, and the sidebar shows at most 5 of a repo, some of them live.
local PER_FOLDER = 10
-- The scan runs again only once this many milliseconds passed, unless forced.
local EVERY = 60 * 1000
-- A scan that takes longer is killed, and the last result stays.
local TIMEOUT = 15 * 1000

-- `$1` the sessions folder, `$2` the files to read per folder. For each folder, the newest `$2` top-level `.jsonl`
-- files (subagent sessions sit one folder deeper and stay out); for them, in batches: each file's last write, its
-- first two lines cut at 4096 bytes (omp's own read size), and the files a process holds open. Paths start with
-- `./`, because a folder name can start with `-`.
local SCRIPT = [[
dir=$1 keep=$2
cd "$dir" 2>/dev/null || exit 0
HEADS='FNR == 1 { print "F\t" FILENAME } FNR <= 2 { print "L\t" substr($0, 1, 4096) } FNR == 2 { nextfile }'
OPEN='/^n/ { print "O\t" substr($0, 2) }'
export HEADS OPEN
for d in ./*/; do
	set -- "$d"*.jsonl
	[ -e "$1" ] || continue
	while [ $# -gt "$keep" ]; do shift; done
	printf '%s\0' "$@"
done | /usr/bin/xargs -0 /bin/sh -c '/usr/bin/stat -f "M%t%m%t%N" "$@"; /usr/bin/awk "$HEADS" "$@"; /usr/sbin/lsof -nP -Fn -- "$@" 2>/dev/null | /usr/bin/awk "$OPEN"' sh
]]

-- `tern inspect --json`, run with the Tern app that runs the plugin (its path from `TERN_EXE`, else the parent
-- process, the app itself), else with the default install.
local INSPECT = [[
exe=${TERN_EXE:-}
[ -x "$exe" ] || exe=$(/bin/ps -o comm= -p "$PPID" 2>/dev/null)
case $exe in */tern) ;; *) exe=/Applications/Tern.app/Contents/MacOS/tern ;; esac
exec "$exe" inspect --json
]]
-- A `tern inspect` that takes longer is killed, and the last answer stays.
local INSPECT_TIMEOUT = 5 * 1000

-- The sessions of the last scan; nil before the first one ends.
local found: { viewModel.Session }? = nil
local running = false
-- A forced scan asked for while one ran: it runs when that one ends.
local again = false
-- `tern.now()` when the last scan started.
local startedAt: number? = nil

-- The session file each pane's omp reported, by pane, from the last `tern inspect`.
local reported: { [number]: string } = {}
local inspecting = false
-- A read asked for while one ran: it runs when that one ends.
local inspectAgain = false

local function same(a: { viewModel.Session }?, b: { viewModel.Session }): boolean
	if a == nil or #a ~= #b then
		return false
	end
	for i, x in a do
		local y = b[i]
		if x.file ~= y.file or x.at ~= y.at or x.title ~= y.title or x.cwd ~= y.cwd or x.repo ~= y.repo
			or x.open ~= y.open
		then
			return false
		end
	end
	return true
end

--- The sessions of the last scan, with their repos; nil before the first scan ends.
function reader.sessions(): { viewModel.Session }?
	return found
end

--- The session whose file is `file`, from the last scan.
function reader.find(file: string): viewModel.Session?
	if found then
		for _, session in found do
			if session.file == file then
				return session
			end
		end
	end
	return nil
end

--- What the reader asks about a session's working directory: whether the folder is still there (a session in a
--- folder that is gone cannot resume there, and temporary folders would fill the Recent view), and its main repo.
export type Places = {
	exists: (path: string) -> boolean,
	repoOf: (cwd: string?) -> string?,
}

--- Scans the sessions folder of `home` unless a scan ran in the last minute (`force` scans anyway, after the one that
--- runs ends). Keeps the sessions whose folder is still there, with their repos. `changed` runs, with a fresh `cx`,
--- when a scan found other sessions than the last one.
function reader.scan(home: string?, force: boolean, places: Places, changed: (cx: WindowCx) -> ())
	if not home then
		return
	end
	if running then
		again = again or force
		return
	end
	local now = tern.now()
	if not force and startedAt and now - startedAt < EVERY then
		return
	end
	running, startedAt = true, now
	local dir = home .. "/.omp/agent/sessions"
	local ok, err = pcall(function()
		tern.process.run({ "/bin/sh", "-c", SCRIPT, "sh", dir, tostring(PER_FOLDER) }, { timeout_ms = TIMEOUT }, function(result: ProcessResult, cx: WindowCx?)
			running = false
			if not result.timed_out then
				local list: { viewModel.Session } = {}
				local there: { [string]: boolean } = {}
				for _, session in sessions.parse(result.stdout, dir) do
					local cwd = session.cwd
					if there[cwd] == nil then
						there[cwd] = places.exists(cwd)
					end
					if there[cwd] then
						session.repo = places.repoOf(cwd)
						table.insert(list, session)
					end
				end
				table.sort(list, function(a, b)
					return a.file < b.file
				end)
				if not same(found, list) then
					found = list
					if cx then
						changed(cx)
					end
				end
			end
			if again then
				again = false
				reader.scan(home, true, places, changed)
			end
		end)
	end)
	if not ok then
		running = false
		print("agents: the session scan did not start: " .. tostring(err))
	end
end

local function sameFiles(a: { [number]: string }, b: { [number]: string }): boolean
	for pane, file in a do
		if b[pane] ~= file then
			return false
		end
	end
	for pane in b do
		if a[pane] == nil then
			return false
		end
	end
	return true
end

--- The session file each pane's omp reported to Tern, by pane, from the last read; empty before the first one.
function reader.reported(): { [number]: string }
	return reported
end

--- Reads which session file each pane's omp reported (`omp_session_file` in `tern inspect --json`). `changed` runs,
--- with a fresh `cx`, when the answer differs from the last one.
function reader.readReported(changed: (cx: WindowCx) -> ())
	if inspecting then
		inspectAgain = true
		return
	end
	inspecting = true
	local ok, err = pcall(function()
		tern.process.run({ "/bin/sh", "-c", INSPECT }, { timeout_ms = INSPECT_TIMEOUT }, function(result: ProcessResult, cx: WindowCx?)
			inspecting = false
			if result.status == 0 and not result.timed_out then
				local decoded, data = pcall(tern.json.decode, result.stdout)
				if decoded then
					local files = sessions.reported(data)
					if not sameFiles(reported, files) then
						reported = files
						if cx then
							changed(cx)
						end
					end
				end
			end
			if inspectAgain then
				inspectAgain = false
				reader.readReported(changed)
			end
		end)
	end)
	if not ok then
		inspecting = false
		print("agents: the session file read did not start: " .. tostring(err))
	end
end

return reader
