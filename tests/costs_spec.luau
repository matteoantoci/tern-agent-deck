--!strict
-- The cost reader's outputs, parsed: the credential types from omp's `agent.db`, the session files and their sizes,
-- and the cost of the assistant messages in the bytes each read added.
local t = require("./harness")
local costs = require("../lib/costs")

local MAIN = "/Users/me/.omp/agent/sessions/-repo/2026-11-27T08-00-00-000Z_01a2.jsonl"
local SUB = "/Users/me/.omp/agent/sessions/-repo/2026-11-27T08-00-00-000Z_01a2/Explore.jsonl"
local DEEP = "/Users/me/.omp/agent/sessions/-repo/2026-11-27T08-00-00-000Z_01a2/Explore/Explore.Slice.jsonl"
local OTHER = "/Users/me/.omp/agent/sessions/-repo/2026-11-27T08-00-00-000Z_01a20.jsonl"

-- Credential 58 is a subscription (oauth), 2 an API key; 7 is not in the database.
local KINDS = costs.credentials("2\topencode-go\tapi_key\n58\tanthropic\toauth\n")

local function lines(list: { string }): string
	return table.concat(list, "\n") .. "\n"
end

-- Reads `output` into `files` and gives the cost of the session in `main`.
local function read(files: any, output: string, main: string?): any
	costs.apply(files, costs.chunks(output))
	return costs.total(main or MAIN, files, KINDS :: any)
end

t.test("credential types come back by id; other types are left out", function()
	t.eq(KINDS, { [2] = "api_key", [58] = "oauth" })
	t.eq(costs.credentials("3\tx\tservice_account\n"), {})
	t.eq(costs.credentials(""), {})
end)

t.test("credential output of another shape gives no credential types", function()
	t.eq(costs.credentials("Error: no such table: auth_credentials\n"), nil)
	t.eq(costs.credentials("2\tapi_key\n"), nil)
	t.eq(costs.credentials("x\topenai\tapi_key\n"), nil)
end)

t.test("api_key messages add to real spend, oauth messages to subscription use, unknown ids to neither", function()
	local files = {}
	local cost = read(
		files,
		lines({
			"F\t0\t400\t" .. MAIN,
			"C\t100\t2\t0.25",
			"C\t200\t58\t1.5",
			"C\t300\t7\t9",
			"C\t350\t2\t0.125",
			"E\t400\t350",
		})
	)
	t.eq(cost, { apiUsd = 0.375, subUsd = 1.5 })
	t.eq(files[MAIN].offset, 400)
end)

t.test("a chunk that ends mid-line keeps its offset at that line's start and counts the line on the next read", function()
	local files = {}
	-- The read stopped at byte 250, inside the line that starts at 200: that line's cost is not whole yet.
	local first = read(files, lines({ "F\t0\t250\t" .. MAIN, "C\t200\t2\t1", "C\t251\t2\t5", "E\t251\t200" }))
	t.eq(first, { apiUsd = 1, subUsd = 0 })
	t.eq(files[MAIN].offset, 200)
	local second = read(files, lines({ "F\t200\t320\t" .. MAIN, "C\t300\t2\t5", "E\t320\t300" }))
	t.eq(second, { apiUsd = 6, subUsd = 0 })
	t.eq(files[MAIN].offset, 320)
end)

t.test("totals add across chunks, and a file read again from its start replaces its totals", function()
	local files = {}
	read(files, lines({ "F\t0\t100\t" .. MAIN, "C\t100\t58\t2", "E\t100\t0" }))
	t.eq(read(files, lines({ "F\t100\t200\t" .. MAIN, "C\t200\t58\t3", "E\t200\t100" })), { apiUsd = 0, subUsd = 5 })
	-- omp wrote the file anew: the reader reads it from byte 0.
	t.eq(read(files, lines({ "F\t0\t50\t" .. MAIN, "C\t50\t58\t0.5", "E\t50\t0" })), { apiUsd = 0, subUsd = 0.5 })
end)

t.test("a chunk with no end line, or with an odd line, adds nothing it cannot read", function()
	local files = {}
	t.eq(read(files, lines({ "F\t0\t100\t" .. MAIN, "C\t100\t2\t1" })), nil)
	t.eq(files[MAIN], nil)
	t.eq(read(files, lines({ "F\t0\t100\t" .. MAIN, "C\t50\t2\tlots", "garbage", "C\t100\t2\t1", "E\t100\t50" })), {
		apiUsd = 1,
		subUsd = 0,
	})
end)

t.test("the subagents' files, at any depth, count toward their agent; another session's do not", function()
	local files = {}
	local cost = read(
		files,
		lines({
			"F\t0\t10\t" .. MAIN,
			"C\t10\t58\t1",
			"E\t10\t0",
			"F\t0\t10\t" .. SUB,
			"C\t10\t2\t0.5",
			"E\t10\t0",
			"F\t0\t10\t" .. DEEP,
			"C\t10\t58\t2",
			"E\t10\t0",
			"F\t0\t10\t" .. OTHER,
			"C\t10\t2\t100",
			"E\t10\t0",
		})
	)
	t.eq(cost, { apiUsd = 0.5, subUsd = 3 })
end)

t.test("a session with no cost yet, or without credential types, has no cost", function()
	local files = {}
	t.eq(read(files, lines({ "F\t0\t10\t" .. MAIN, "E\t10\t0" })), nil)
	t.eq(read(files, lines({ "F\t10\t20\t" .. MAIN, "C\t20\t7\t4", "E\t20\t10" })), nil)
	read(files, lines({ "F\t20\t30\t" .. MAIN, "C\t30\t2\t4", "E\t30\t20" }))
	t.eq(costs.total(MAIN, files, nil), nil)
end)

t.test("the listing gives each file's size", function()
	t.eq(costs.sizes(lines({ "120\t" .. MAIN, "0\t" .. SUB, "odd line" })), { [MAIN] = 120, [SUB] = 0 })
end)

t.test("each read takes only the bytes after the stored offset of each file", function()
	local files = {
		[MAIN] = { offset = 100, totals = {} },
		[SUB] = { offset = 40, totals = {} },
		[DEEP] = { offset = 500, totals = {} },
	}
	-- MAIN grew, SUB did not, DEEP is shorter than its offset (written anew), OTHER is new.
	t.eq(costs.plan({ [MAIN] = 160, [SUB] = 40, [DEEP] = 30, [OTHER] = 10 }, files), {
		{ path = MAIN, from = 100, size = 160 },
		{ path = DEEP, from = 0, size = 30 },
		{ path = OTHER, from = 0, size = 10 },
	})
end)

return nil
