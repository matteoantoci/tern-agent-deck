--!strict
-- The output of the session reader's scan, parsed. Pure: the reader runs the scan with `tern.process.run`, off the
-- UI thread, and hands its output here, so the `luau` CLI tests it.
--
-- The scan prints one record per line, tab-separated, each path relative to the sessions folder (`./` in front or
-- not) or absolute under it:
-- - `M <mtime> <path>`: the file's last write (`os.time()` seconds);
-- - `F <path>`, then `L <line>` for each of the file's first two lines (cut at 4096 bytes);
-- - `O <path>`: a running process holds the file open.
-- omp's session file starts with a 256-byte title slot `{"type":"title","title":…}` (empty until omp names the
-- session) and then the header `{"type":"session","id","cwd","title"?,…}`; an older file starts with the header.

local viewModel = require("./view_model")

local sessions = {}

-- `\uXXXX` code units, a surrogate pair joined, as UTF-8.
local function codepoint(hex: string, low: string?): string
	local high = tonumber(hex, 16) :: number
	if low and high >= 0xD800 and high <= 0xDBFF then
		local second = tonumber(low, 16) :: number
		return utf8.char(0x10000 + (high - 0xD800) * 0x400 + (second - 0xDC00))
	end
	return utf8.char(high)
end

local ESCAPES: { [string]: string } = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

--- The string value of the first `"key":"…"` in the JSON text `line`, decoded; nil when absent or cut off.
local function field(line: string, key: string): string?
	local _, stop = string.find(line, '"' .. key .. '"%s*:%s*"')
	if not stop then
		return nil
	end
	local out: { string } = {}
	local i = stop + 1
	while i <= #line do
		local c = string.sub(line, i, i)
		if c == '"' then
			return table.concat(out)
		elseif c == "\\" then
			local e = string.sub(line, i + 1, i + 1)
			if e == "u" then
				local hex = string.match(line, "^%x%x%x%x", i + 2)
				if not hex then
					return nil
				end
				local low = string.match(line, "^\\u(%x%x%x%x)", i + 6)
				local high = tonumber(hex, 16) :: number
				if low and high >= 0xD800 and high <= 0xDBFF then
					table.insert(out, codepoint(hex, low))
					i += 12
				else
					table.insert(out, codepoint(hex))
					i += 6
				end
			elseif ESCAPES[e] then
				table.insert(out, ESCAPES[e])
				i += 2
			else
				return nil
			end
		else
			local run = string.match(line, '^[^"\\]+', i) :: string
			table.insert(out, run)
			i += #run
		end
	end
	return nil
end

local function kind(line: string): string?
	return field(line, "type")
end

type Found = { lines: { string }, at: number?, open: boolean }

--- The sessions in the scan `output` of the sessions folder `dir`, in no particular order. A file without a header
--- working directory or without a last write is left out.
function sessions.parse(output: string, dir: string): { viewModel.Session }
	local files: { [string]: Found } = {}
	local order: { string } = {}
	local prefix = dir .. "/"
	local function file(path: string): Found
		if string.sub(path, 1, #prefix) == prefix then
			path = string.sub(path, #prefix + 1)
		elseif string.sub(path, 1, 2) == "./" then
			path = string.sub(path, 3)
		end
		local found = files[path]
		if not found then
			found = { lines = {}, open = false }
			files[path] = found
			table.insert(order, path)
		end
		return found
	end
	local current: Found? = nil
	for line in string.gmatch(output, "[^\n]+") do
		local tag, rest = string.match(line, "^(%u)\t(.*)$")
		if tag == "F" and rest then
			current = file(rest)
		elseif tag == "L" and rest and current then
			table.insert(current.lines, rest)
		elseif tag == "M" and rest then
			local at, path = string.match(rest, "^(%d+)\t(.+)$")
			if at and path then
				file(path).at = tonumber(at)
			end
		elseif tag == "O" and rest then
			file(rest).open = true
		end
	end
	local out: { viewModel.Session } = {}
	for _, path in order do
		local found = files[path]
		local slot: string? = nil
		local header: string? = nil
		for _, line in found.lines do
			local what = kind(line)
			if what == "title" and not slot then
				slot = field(line, "title")
			elseif what == "session" and not header then
				header = line
			end
		end
		local cwd = header and field(header, "cwd")
		if header and cwd and cwd ~= "" and found.at then
			local title = if slot and slot ~= "" then slot else field(header, "title")
			table.insert(out, {
				file = prefix .. path,
				id = field(header, "id"),
				cwd = cwd,
				title = title,
				at = found.at :: number,
				open = if found.open then true else nil,
			})
		end
	end
	return out
end

--- The session id in the header among the first two lines of `head`, the start of an omp session file (line 1 the
--- title slot, line 2 the header; an older file starts with the header); nil when neither is a header with an id.
function sessions.id(head: string): string?
	local n = 0
	for line in string.gmatch(head, "[^\n]+") do
		if kind(line) == "session" then
			return field(line, "id")
		end
		n += 1
		if n == 2 then
			break
		end
	end
	return nil
end

--- The session file each pane's omp reported, by pane, from the decoded output of `tern inspect --json`: omp tells
--- Tern its live session file (OSC 1337 user variable `omp_session_file`, on start, a new session, a resume and a
--- working-directory switch), and Tern lists it in each pane's entry. Panes without one are absent.
function sessions.reported(inspect: any): { [number]: string }
	local out: { [number]: string } = {}
	local panes = type(inspect) == "table" and inspect.panes
	if type(panes) ~= "table" then
		return out
	end
	for _, entry in panes do
		if type(entry) == "table" and type(entry.pane) == "number" then
			local file = entry.omp_session_file
			if type(file) == "string" and file ~= "" then
				out[entry.pane] = file
			end
		end
	end
	return out
end

return sessions
