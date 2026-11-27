--!strict
-- The summary reader: a short summary of each main agent's long last message, for its hover card. omp's light model
-- role (`@smol`) writes it: one `omp -p` run, off the UI thread, with no tools, extensions, skills, rules, context
-- files or session, so that it costs one small request. The summaries live in `tern.kv` with a hash of the message
-- they summarize, so every window shares them and a reload or a restart keeps them: each message is summarized once.
-- Measured 2026-11-27 (omp 19.2.1, smol = claude-haiku-5-5): one run takes about 4 s.

local viewModel = require("./view_model")

local summaries = {}

-- The `tern.kv` key: by pane id, the hash of the message and its summary, or the time a window started its run.
local KEY = "summaries"
-- A run that takes longer is killed; that message gets no summary.
local TIMEOUT = 30 * 1000
-- A run another window started this many seconds ago or less is still going on: this window waits for it.
local PENDING_FOR = 60
-- A failed run is tried again for the same message once this many seconds passed.
local RETRY_AFTER = 10 * 60
-- The run gets at most this many bytes of the message.
local INPUT_BYTES = 8000

-- The card shows about 50 characters a line (measured 2026-11-27 on a 300 px card), and a summary should take at
-- most 3 or 4 lines: it must stay within `MAX_CHARS`, which leaves room for word wrap. The model aims at 100
-- characters and overshoots now and then; a longer answer goes back to it once to be shortened, and only an answer
-- still too long after that is cut at a word.
local SYSTEM = "You summarize the last message of a coding agent for a small hover card. Write one sentence of at most "
	.. "12 words and at most 100 characters, in plain text: no Markdown, no lists, no preamble. Keep the outcome and "
	.. "any question or next step the agent asks the user for. Count the characters: never exceed 100."
local SHORTEN = "Shorten the message to one sentence of at most 10 words and at most 90 characters, in plain text, with "
	.. "no preamble. Keep its main point. Count the characters: never exceed 90."
local MAX_CHARS = 170
-- Changes when the prompt changes, so that summaries written under an older prompt are written again.
local PROMPT_VERSION = "4"

-- `$1` the message, `$2` the system prompt, `$3` the longest answer kept, `$4` the system prompt that shortens a
-- longer one. Both model calls run in this one process. The omp that Tern installs, else the one on the PATH.
local SCRIPT = [[
omp="$HOME/Library/Application Support/Tern/omp/bin/omp"
[ -x "$omp" ] || omp=$(command -v omp) || exit 127
ask() {
	"$omp" -p --no-session --model @smol --no-tools --no-extensions --no-skills --no-rules --no-context-files \
		--no-lsp --system-prompt "$1" "$2" 2>/dev/null
}
s=$(ask "$2" "Summarize the message between the tags.
<message>
$1
</message>") || exit 1
if [ "${#s}" -gt "$3" ]; then
	t=$(ask "$4" "Shorten the message between the tags.
<message>
$s
</message>") && [ -n "$t" ] && s=$t
fi
printf '%s' "$s"
]]

-- One pane's record: `hash` names the message; `summary` is its summary, `failed` (`os.time()`) says when a run gave
-- none and `why` says what went wrong, and `started` (`os.time()`) says a run is going on. `previous` is the summary
-- of the pane's message before, shown until the new one arrives.
type Entry = { hash: string, summary: string?, failed: number?, why: string?, started: number?, previous: string? }

-- A working agent's last message still grows: it is summarized once it stayed the same this many seconds.
local STILL_FOR = 15
-- When this window first saw each pane's current message, by pane: `{hash, at}` (`os.time()`).
local seen: { [string]: { hash: string, at: number } } = {}

-- `os.time()` when this window's run started, while one is going on: one at a time. A run whose callback never came
-- stops blocking the next ones once `PENDING_FOR` passed.
local runningSince: number? = nil

local function paneKey(pane: number): string
	return string.format("%.0f", pane)
end

-- `text` cut to at most `MAX_CHARS` bytes at the last space before, with `…`; whole when it fits.
local function fit(text: string): string
	if #text <= MAX_CHARS then
		return text
	end
	local cut = string.match(string.sub(text, 1, MAX_CHARS - 3), "^(.*%S)%s") or string.sub(text, 1, MAX_CHARS - 3)
	return cut .. "…"
end

-- The 32-bit FNV-1a hash of `text`, with its length: enough to tell one message from the next in the same pane.
local function hash(text: string): string
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		h = (h * 16777619) % 4294967296
	end
	return string.format("%08x-%d-v%s", h, #text, PROMPT_VERSION)
end

local function load(): { [string]: Entry }
	local ok, stored = pcall(tern.kv.get, KEY)
	if ok and type(stored) == "table" then
		return stored
	end
	return {}
end

local function save(entries: { [string]: Entry })
	tern.kv.set(KEY, if next(entries) == nil then nil else entries)
end

--- The summary of `text`, the last message of the agent in `pane`; while none was made for that message, the summary
--- of the pane's message before it, if any; nil else.
function summaries.get(pane: number, text: string?): string?
	if not text or not viewModel.needsSummary(text) then
		return nil
	end
	local entry = load()[paneKey(pane)]
	if type(entry) ~= "table" then
		return nil
	end
	if entry.hash == hash(text) and type(entry.summary) == "string" then
		return entry.summary
	end
	if type(entry.previous) == "string" then
		return entry.previous
	end
	return nil
end

--- Starts a summary of `text`, the last message of the agent in `pane`, when it is long enough to need one and no
--- window made one, failed to, or is making one for it. A message of an agent that still works (`settled` false)
--- waits until it stayed the same `STILL_FOR` seconds. `changed` runs, with a fresh `cx`, when the run ends.
function summaries.request(pane: number, text: string?, settled: boolean, changed: (cx: WindowCx) -> ())
	if runningSince and os.time() - runningSince <= PENDING_FOR then
		return
	end
	if not text or not viewModel.needsSummary(text) then
		return
	end
	local key = paneKey(pane)
	local h = hash(text)
	if not settled then
		local look = seen[key]
		if not look or look.hash ~= h then
			seen[key] = { hash = h, at = os.time() }
			return
		end
		if os.time() - look.at < STILL_FOR then
			return
		end
	end
	local entries = load()
	local entry = entries[key]
	if type(entry) == "table" and entry.hash == h then
		local failed = entry.failed
		-- A record from an older build may hold `failed = true`: it counts as expired.
		if entry.summary or (type(failed) == "number" and os.time() - failed < RETRY_AFTER) then
			return
		end
		if entry.started and os.time() - entry.started <= PENDING_FOR then
			return
		end
	end
	local previous: string? = nil
	if type(entry) == "table" then
		previous = if entry.hash ~= h and type(entry.summary) == "string" then entry.summary else entry.previous
	end
	entries[key] = { hash = h, started = os.time(), previous = previous }
	save(entries)
	runningSince = os.time()
	local function finish(summary: string?, why: string?)
		runningSince = nil
		local now = load()
		local current = now[key]
		-- A newer message of the pane may have taken the record meanwhile: keep it.
		if type(current) ~= "table" or current.hash == h then
			if summary then
				now[key] = { hash = h, summary = summary }
			else
				now[key] = { hash = h, failed = os.time(), why = why or "no answer", previous = previous }
			end
			save(now)
		end
	end
	local argv = { "/bin/sh", "-c", SCRIPT, "sh", string.sub(text, 1, INPUT_BYTES), SYSTEM, tostring(MAX_CHARS), SHORTEN }
	local ok, err = pcall(function()
		tern.process.run(argv, { timeout_ms = TIMEOUT }, function(result: ProcessResult, cx: WindowCx?)
			local done: boolean, problem: any = pcall(function(): ()
				if result.timed_out then
					finish(nil, "timed out")
					return
				end
				local trimmed = string.match(result.stdout, "^%s*(.-)%s*$")
				if result.status ~= 0 or not trimmed or trimmed == "" then
					finish(nil, string.format("exit %s: %s", tostring(result.status), string.sub(result.stderr or "", 1, 200)))
					return
				end
				finish(fit(trimmed))
			end)
			if not done then
				finish(nil, "callback error: " .. tostring(problem))
			end
			if cx then
				changed(cx)
			end
		end)
	end)
	if not ok then
		finish(nil, "did not start: " .. tostring(err))
		print("agents: the message summary did not start: " .. tostring(err))
	end
end

--- Whether a run is making the summary of `text`, the last message of the agent in `pane`, in any window.
function summaries.pending(pane: number, text: string?): boolean
	if not text or not viewModel.needsSummary(text) then
		return false
	end
	local entry = load()[paneKey(pane)]
	return type(entry) == "table"
		and entry.hash == hash(text)
		and entry.summary == nil
		and type(entry.started) == "number"
		and os.time() - entry.started <= PENDING_FOR
end

--- Drops the records of every pane that `live` does not hold (closed panes, and pane ids from before a daemon
--- restart).
function summaries.keep(live: { [number]: boolean })
	local entries = load()
	local changed = false
	for key in entries do
		local pane = tonumber(key)
		if not pane or not live[pane] then
			entries[key] = nil
			changed = true
		end
	end
	if changed then
		save(entries)
	end
end

return summaries
