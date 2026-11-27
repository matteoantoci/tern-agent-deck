--!strict
-- The quota reader's query and its answer: `sqlite3` opens omp's `agent.db` read-only, and a failed or odd answer
-- shows no quota line.
local t = require("./harness")
local reader = require("../lib/quota_reader")

local NOW = 1_800_000_000_000
local DAY = 24 * 60 * 60 * 1000

local function result(fields: { [string]: any }): any
	local r: { [string]: any } = { status = 0, stdout = "", stderr = "", timed_out = false }
	for k, v in fields do
		r[k] = v
	end
	return r
end

t.test("the query opens omp's database read-only, and it reads the quota rows", function()
	local argv = reader.command("/Users/me")
	t.eq(argv[1], "/usr/bin/sqlite3")
	t.eq(argv[2], "-readonly")
	t.eq(argv[#argv - 1], "/Users/me/.omp/agent/agent.db")
	local sql = argv[#argv]
	t.eq(string.find(sql, "usage_history", 1, true) ~= nil, true)
	-- Only the row filter selects; neither the outer nor the inner select takes a secret column.
	local selected = string.sub(sql, 1, (string.find(sql, "FROM (", 1, true) or 0) - 1)
	t.eq(string.find(selected, "account_key", 1, true), nil)
	t.eq(string.find(selected, "*", 1, true), nil)
	t.eq(string.find(selected, " data", 1, true), nil)
end)

t.test("a quota row comes back as a quota", function()
	local out = table.concat(
		{ "anthropic", "work@example.com", "7 Day", "Claude 7 Day", "0.97", "warning", tostring(NOW + DAY) },
		"\t"
	)
	t.eq(reader.quotasOf(result({ stdout = out .. "\n" }), NOW), {
		{ provider = "Claude", account = "work", label = "7d", used = 0.97, status = "warning", resetsAt = NOW + DAY },
	})
end)

t.test("a query that failed, timed out or printed another shape shows no quota line", function()
	t.eq(reader.quotasOf(result({ status = 1, stdout = "", stderr = "Error: unable to open database file" }), NOW), nil)
	t.eq(reader.quotasOf(result({ status = 1, stdout = "Error: no such table: usage_history" }), NOW), nil)
	t.eq(reader.quotasOf(result({ timed_out = true }), NOW), nil)
	t.eq(reader.quotasOf(result({ stdout = "provider\temail\n" }), NOW), nil)
	t.eq(reader.quotasOf(result({ status = 0, stdout = "" }), NOW), {})
end)

t.test("with no database path, the reader reads nothing and keeps no quota", function()
	reader.read(nil, function() end)
	t.eq(reader.quotas(), nil)
end)

return nil
