--!strict
-- The quota reader's output: what one query of omp's `usage_history` tells about each subscription quota.
local t = require("./harness")
local quotas = require("../lib/quotas")

-- Wall-clock milliseconds when the query ran.
local NOW = 1_800_000_000_000
local HOUR = 60 * 60 * 1000
local DAY = 24 * HOUR

-- One row as the query prints it: provider, email, window, limit name, used fraction, status, reset (ms).
local function row(fields: { any }): string
	local out: { string } = {}
	for _, field in fields do
		table.insert(out, tostring(field))
	end
	return table.concat(out, "\t")
end

local function parse(rows: { string }): any
	return quotas.parse(table.concat(rows, "\n") .. "\n", NOW)
end

t.test("a row gives the provider's and the account's names, the window, the use, the status and the reset", function()
	t.eq(parse({ row({ "anthropic", "work@example.com", "7 Day", "Claude 7 Day", 0.97, "warning", NOW + 2 * DAY }) }), {
		{ provider = "Claude", account = "work", label = "7d", used = 0.97, status = "warning", resetsAt = NOW + 2 * DAY },
	})
end)

t.test("hour and day windows shorten, other windows stay as they are, and a row with no window names its limit", function()
	local found = parse({
		row({ "anthropic", "a@x.com", "5 Hour", "Claude 5 Hour", 0.5, "ok", NOW + HOUR }),
		row({ "xai-oauth", "a@x.com", "Weekly", "GrokChat (Weekly)", 0.5, "ok", NOW + HOUR }),
		row({ "deepai", "", "", "Theos", 0.5, "ok", NOW + HOUR }),
	})
	t.eq({ found[1].label, found[2].label, found[3].label }, { "5h", "Weekly GrokChat", "Theos" })
end)

t.test("a limit's qualifier follows its window, so two limits of one window stay apart", function()
	local found = parse({
		row({ "anthropic", "a@x.com", "7 Day", "Claude 7 Day", 0.5, "ok", NOW + HOUR }),
		row({ "anthropic", "a@x.com", "7 Day", "Claude 7 Day (Fable)", 0.9, "warning", NOW + HOUR }),
		row({ "xai-oauth", "a@x.com", "Weekly", "GrokChat (Weekly)", 0.5, "ok", NOW + HOUR }),
	})
	t.eq({ found[1].label, found[2].label, found[3].label }, { "7d", "7d Fable", "Weekly GrokChat" })
end)

t.test("when the parenthesis only repeats the window, the limit's name before it is the qualifier", function()
	local found = parse({
		row({ "xai-oauth", "a@x.com", "Weekly", "API (Weekly)", 0.97, "warning", NOW + HOUR }),
		row({ "xai-oauth", "a@x.com", "Weekly", "GrokChat (Weekly)", 0.98, "warning", NOW + HOUR }),
		row({ "xai-oauth", "a@x.com", "Weekly", "(Weekly)", 0.5, "ok", NOW + HOUR }),
	})
	t.eq({ found[1].label, found[2].label, found[3].label }, { "Weekly API", "Weekly GrokChat", "Weekly" })
end)

t.test("a quota whose window reset already, or that names no reset, is left out", function()
	t.eq(
		parse({
			row({ "anthropic", "a@x.com", "7 Day", "Claude 7 Day", 1.0, "exhausted", NOW - 1 }),
			row({ "anthropic", "a@x.com", "5 Hour", "Claude 5 Hour", 0.9, "warning", NOW }),
			row({ "google-antigravity", "a@x.com", "Daily", "Usage (Google)", 0.0, "ok", 0 }),
			row({ "opencode-go", "", "Weekly", "Weekly limit", 0.95, "warning", "" }),
		}),
		{}
	)
end)

t.test("two accounts of one provider stay two quotas", function()
	local found = parse({
		row({ "anthropic", "matteo@work.com", "7 Day", "Claude 7 Day", 1.0, "exhausted", NOW + DAY }),
		row({ "anthropic", "claude@home.it", "7 Day", "Claude 7 Day", 0.47, "ok", NOW + 3 * DAY }),
	})
	t.eq(#found, 2)
	t.eq({ found[1].provider, found[1].account, found[1].status }, { "Claude", "matteo", "exhausted" })
	t.eq({ found[2].provider, found[2].status }, { "Claude", "ok" })
	t.eq(found[2].account, nil)
end)

t.test("an account named as its provider shows no name, in any case", function()
	local found = parse({
		row({ "anthropic", "Claude@home.it", "5 Hour", "Claude 5 Hour", 1.0, "exhausted", NOW + DAY }),
		row({ "anthropic", "claude@home.it", "7 Day", "Claude 7 Day", 0.5, "ok", NOW + DAY }),
	})
	t.eq({ found[1].account, found[2].account }, { nil, nil })
end)

t.test("an account named as its provider shows its email's domain when another account would read the same", function()
	local found = parse({
		row({ "anthropic", "claude@work.com", "7 Day", "Claude 7 Day", 1.0, "exhausted", NOW + DAY }),
		row({ "anthropic", "claude@home.it", "7 Day", "Claude 7 Day", 0.47, "ok", NOW + DAY }),
		row({ "xai", "grok@x.com", "Weekly", "Weekly", 0.1, "ok", NOW + DAY }),
	})
	t.eq({ found[1].account, found[2].account }, { "work.com", "home.it" })
	t.eq(found[3].account, nil)
end)

t.test("each provider in omp's usage history takes its display name, and an unknown one keeps its own", function()
	local found = parse({
		row({ "anthropic", "a@x.com", "5 Hour", "Claude 5 Hour", 0.1, "ok", NOW + DAY }),
		row({ "xai", "a@x.com", "Weekly", "Weekly", 0.1, "ok", NOW + DAY }),
		row({ "xai-oauth", "a@x.com", "Weekly", "GrokChat (Weekly)", 0.1, "ok", NOW + DAY }),
		row({ "google-antigravity", "a@x.com", "Weekly", "Gemini", 0.1, "ok", NOW + DAY }),
		row({ "opencode-go", "a@x.com", "Monthly", "Monthly limit", 0.91, "warning", NOW + DAY }),
		row({ "deepai", "", "", "Theos", 0.1, "ok", NOW + DAY }),
		row({ "acme", "", "Monthly", "Monthly limit", 0.91, "warning", NOW + DAY }),
	})
	local names: { string } = {}
	for _, q in found do
		table.insert(names, q.provider)
	end
	t.eq(names, { "Claude", "Grok", "Grok", "Gemini", "OpenCode Go", "DeepAI", "acme" })
	t.eq(found[7].account, nil)
end)

t.test("a row with a status the plugin does not know is left out", function()
	t.eq(parse({ row({ "anthropic", "a@x.com", "7 Day", "Claude 7 Day", 0.5, "throttled", NOW + DAY }) }), {})
end)

t.test("no rows give no quotas", function()
	t.eq(quotas.parse("", NOW), {})
end)

t.test("output of an unknown shape gives nothing, so that the sidebar shows no quota line", function()
	t.eq(parse({ row({ "anthropic", "a@x.com", "7 Day", 0.97, "warning", NOW + DAY }) }), nil)
	t.eq(parse({ row({ "anthropic", "a@x.com", "7 Day", "Claude 7 Day", "lots", "warning", NOW + DAY }) }), nil)
	t.eq(parse({ row({ "anthropic", "a@x.com", "7 Day", "Claude 7 Day", 0.5, "ok", "soon" }) }), nil)
	t.eq(quotas.parse("Error: no such table: usage_history\n", NOW), nil)
end)

return nil
