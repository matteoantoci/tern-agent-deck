--!strict
-- The cost of omp sessions, from the cost reader's outputs (`lib/cost_reader.luau`). Pure: the reader runs the
-- commands with `tern.process.run`, off the UI thread, and hands their output here, so the `luau` CLI tests it.
--
-- Three outputs, each one record per line, tab-separated:
-- - the credential query of omp's `agent.db`: the id, the provider and the credential type (`api_key`, `oauth`);
-- - the listing: the size in bytes and the path of each session file;
-- - the read: for each file, `F <from> <size> <path>` (the read takes the bytes from `from` to `size`), then
--   `C <end> <credential id> <usd>` for each assistant message with a cost (`end` is the byte after its line), then
--   `E <end> <start>`: the byte after the last line read, as if a newline ended it, and the start of that line.

local viewModel = require("./view_model")

local costs = {}

--- The type of each credential, by id: `api_key` (real money) or `oauth` (a subscription).
export type Kinds = { [number]: "api_key" | "oauth" }

--- One session file as the reader knows it: how many bytes it read, and the cost of their messages by credential id.
export type File = { offset: number, totals: { [number]: number } }

--- The session files the reader knows, by path.
export type Files = { [string]: File }

--- What one read takes of a file: the bytes from `from` to `size`.
export type Read = { path: string, from: number, size: number }

--- What one read found in a file: where it started, where the next read starts (after the last whole line), and the
--- cost of the whole lines' messages by credential id.
export type Chunk = { path: string, from: number, offset: number, totals: { [number]: number } }

--- The credential types the query printed, by id; nil when the output has another shape (no table, an error). A
--- type other than `api_key` and `oauth` is left out.
function costs.credentials(output: string): Kinds?
	local out: Kinds = {}
	for line in string.gmatch(output, "[^\n]+") do
		local id, kind = string.match(line, "^(%d+)\t[^\t]*\t([^\t]*)$")
		if not id then
			return nil
		end
		if kind == "api_key" or kind == "oauth" then
			out[tonumber(id) :: number] = kind
		end
	end
	return out
end

--- The size in bytes of each file the listing printed, by path.
function costs.sizes(output: string): { [string]: number }
	local out: { [string]: number } = {}
	for line in string.gmatch(output, "[^\n]+") do
		local size, path = string.match(line, "^(%d+)\t(.+)$")
		if size and path then
			out[path] = tonumber(size) :: number
		end
	end
	return out
end

--- The reads that take the new bytes of the files in `sizes`, by path: a file read before starts at its offset; a
--- new file, or one shorter than its offset (omp wrote it anew), starts at byte 0. A file that did not grow is left
--- out.
function costs.plan(sizes: { [string]: number }, files: Files): { Read }
	local out: { Read } = {}
	for path, size in sizes do
		local known = files[path]
		local from = if known and known.offset <= size then known.offset else 0
		if size > from then
			table.insert(out, { path = path, from = from, size = size })
		end
	end
	table.sort(out, function(a, b)
		return a.path < b.path
	end)
	return out
end

--- What the read found in each file it read. A message whose line ends after the file's size was cut by the read
--- (omp was writing it): it counts on the next read, which starts at that line. A file without its end record is
--- left out, as are lines of another shape.
function costs.chunks(output: string): { Chunk }
	local out: { Chunk } = {}
	local path: string? = nil
	local from, size = 0, 0
	local found: { { at: number, id: number, usd: number } } = {}
	for line in string.gmatch(output, "[^\n]+") do
		local tag = string.sub(line, 1, 2)
		if tag == "F\t" then
			local a, b, p = string.match(line, "^F\t(%d+)\t(%d+)\t(.+)$")
			path = p
			from, size = tonumber(a) or 0, tonumber(b) or 0
			found = {}
		elseif tag == "C\t" and path then
			local at, id, usd = string.match(line, "^C\t(%d+)\t(%d+)\t(%S+)$")
			local n = tonumber(usd)
			if at and id and n then
				table.insert(found, { at = tonumber(at) :: number, id = tonumber(id) :: number, usd = n })
			end
		elseif tag == "E\t" and path then
			local last, start = string.match(line, "^E\t(%d+)\t(%d+)$")
			if last and start then
				local cut = tonumber(last) :: number > size
				local offset = if cut then tonumber(start) :: number else tonumber(last) :: number
				local totals: { [number]: number } = {}
				for _, message in found do
					if message.at <= offset then
						totals[message.id] = (totals[message.id] or 0) + message.usd
					end
				end
				table.insert(out, { path = path, from = from, offset = offset, totals = totals })
			end
			path = nil
		end
	end
	return out
end

--- Adds each chunk to its file in `files`: a chunk from byte 0 replaces the file's totals, a later one adds to them.
function costs.apply(files: Files, chunks: { Chunk })
	for _, chunk in chunks do
		local known = files[chunk.path]
		if chunk.from == 0 or not known then
			files[chunk.path] = { offset = chunk.offset, totals = chunk.totals }
		else
			known.offset = chunk.offset
			for id, usd in chunk.totals do
				known.totals[id] = (known.totals[id] or 0) + usd
			end
		end
	end
end

-- Whether `path` is the session file `main` or a file in its session folder (a subagent's, at any depth).
local function partOf(path: string, main: string): boolean
	if path == main then
		return true
	end
	local folder = string.match(main, "^(.*)%.jsonl$")
	return folder ~= nil and string.sub(path, 1, #folder + 1) == folder .. "/"
end

--- The cost of the session in `main`, its subagents' files included: `api_key` credentials add to `apiUsd`, `oauth`
--- ones to `subUsd`, other ids to neither. Nil when there is no cost (no credential types, or no message of a known
--- credential with a cost).
function costs.total(main: string, files: Files, kinds: Kinds?): viewModel.Cost?
	if not kinds then
		return nil
	end
	local apiUsd, subUsd = 0, 0
	for path, file in files do
		if partOf(path, main) then
			for id, usd in file.totals do
				local kind = kinds[id]
				if kind == "api_key" then
					apiUsd += usd
				elseif kind == "oauth" then
					subUsd += usd
				end
			end
		end
	end
	if apiUsd <= 0 and subUsd <= 0 then
		return nil
	end
	return { apiUsd = apiUsd, subUsd = subUsd }
end

return costs
