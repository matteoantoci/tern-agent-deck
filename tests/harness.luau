--!strict
-- A minimal test harness for the plain `luau` CLI: `test` registers a case, `run` runs them all
-- and raises when one fails, so `luau tests/run.luau` exits non-zero.

local harness = {}

type Case = { name: string, fn: () -> () }

local cases: { Case } = {}

function harness.test(name: string, fn: () -> ())
	table.insert(cases, { name = name, fn = fn })
end

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	if type(value) ~= "table" then
		return tostring(value)
	end
	local parts = {}
	for k, v in value do
		table.insert(parts, tostring(k) .. " = " .. show(v))
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function harness.eq(actual: any, expected: any, label: string?)
	if not deepEqual(actual, expected) then
		local prefix = ""
		if label then
			prefix = label .. ": "
		end
		error(prefix .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
	end
end

function harness.run()
	local failed = 0
	for _, case in cases do
		local ok, err = pcall(case.fn :: () -> any)
		if ok then
			print("ok   " .. case.name)
		else
			failed += 1
			print("FAIL " .. case.name .. "\n     " .. tostring(err))
		end
	end
	print(string.format("%d passed, %d failed", #cases - failed, failed))
	if failed > 0 then
		error(string.format("%d test(s) failed", failed), 0)
	end
end

return harness
