--!strict
-- The cost reader's credential query and its answer: `sqlite3` opens omp's `agent.db` read-only and selects no
-- secret column, and a failed or odd answer shows no cost line.
local t = require("./harness")
local reader = require("../lib/cost_reader")

local function result(fields: { [string]: any }): any
	local r: { [string]: any } = { status = 0, stdout = "", stderr = "", timed_out = false }
	for k, v in fields do
		r[k] = v
	end
	return r
end

t.test("the credential query opens omp's database read-only and selects only the id, provider and type", function()
	local argv = reader.command("/Users/me")
	t.eq(argv[1], "/usr/bin/sqlite3")
	t.eq(argv[2], "-readonly")
	t.eq(argv[#argv - 1], "/Users/me/.omp/agent/agent.db")
	local columns = string.match(argv[#argv], "^SELECT (.-) FROM auth_credentials")
	t.eq(columns, "id, provider, credential_type")
end)

t.test("a credential row comes back as its type", function()
	t.eq(reader.kindsOf(result({ stdout = "2\topencode-go\tapi_key\n55\tanthropic\toauth\n" })), {
		[2] = "api_key",
		[55] = "oauth",
	})
end)

t.test("a query that failed, timed out or printed another shape gives no credential types", function()
	t.eq(reader.kindsOf(result({ status = 1, stderr = "Error: unable to open database file" })), nil)
	t.eq(reader.kindsOf(result({ status = 1, stdout = "Error: no such table: auth_credentials" })), nil)
	t.eq(reader.kindsOf(result({ timed_out = true, stdout = "2\topencode-go\tapi_key\n" })), nil)
	t.eq(reader.kindsOf(result({ stdout = "id\tprovider\n" })), nil)
end)

t.test("with no database path or no live session, the reader reads nothing and has no cost", function()
	reader.readCredentials(nil, function() end)
	reader.read({}, function() end)
	t.eq(reader.costs(), {})
end)

return nil
