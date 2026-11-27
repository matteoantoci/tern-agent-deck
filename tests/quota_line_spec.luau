--!strict
-- The quota line under the Live/Recent switch: shown only while a subscription quota is near or at its limit.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")
local quotas = require("../lib/quotas")

local MINUTE, HOUR, DAY = 60, 60 * 60, 24 * 60 * 60
-- Sunday 29 November 2026, 12:00 UTC (a Sunday in every time zone from UTC-11 to UTC+11), in seconds.
local SUNDAY = 1_795_953_600
-- Two days and six hours before it.
local NOW = SUNDAY - 2 * DAY - 6 * HOUR

-- A quota whose window resets `left` seconds from now (two days and six hours unless given).
local function quota(fields: { [string]: any }): { [string]: any }
	local left = fields.left or (SUNDAY - NOW)
	local q: { [string]: any } = {
		provider = "Claude",
		account = "work",
		label = "7d",
		used = 0.5,
		status = "ok",
		resetsAt = (NOW + left) * 1000,
	}
	for k, v in fields do
		if k ~= "left" then
			q[k] = v
		end
	end
	return q
end

local function view(quotas: { any }?, extra: { [string]: any }?): any
	local input: { [string]: any } = { agents = {}, now = 0, time = NOW, home = "/Users/me", quotas = quotas }
	for k, v in (extra or {}) :: { [string]: any } do
		input[k] = v
	end
	return viewModel.build(input :: any).view
end

local SWITCH = "[Live] [Recent]"

t.test("while every quota is fine, or none is known, the head shows only the Live/Recent switch", function()
	t.eq(visible.chrome(view({ quota({ used = 0.73 }), quota({ account = "home", used = 0.4 }) })), { SWITCH })
	t.eq(visible.chrome(view({})), { SWITCH })
	t.eq(visible.chrome(view(nil)), { SWITCH })
end)

t.test("a quota near its limit shows one line under the switch, with a warning square", function()
	local out = view({ quota({ used = 0.73 }), quota({ used = 0.97, status = "warning" }) })
	t.eq(visible.chrome(out), { SWITCH, "■ Claude · work · 7d 97% · resets Sun" })
	t.eq(visible.state(out, "Claude · work · 7d 97%"), "waiting")
	t.eq(visible.titles(out, "Claude · work · 7d 97%"), { "Claude · work · 7d 97% · resets Sun" })
end)

t.test("a quota at its limit shows an error square", function()
	local out = view({ quota({ label = "5h", used = 1.0, status = "exhausted", left = 38 * MINUTE }) })
	t.eq(visible.chrome(out), { SWITCH, "■ Claude · work · 5h 100% · resets in 38m" })
	t.eq(visible.state(out, "Claude · work · 5h 100%"), "failed")
end)

t.test("the qualifier shows on the line and in the tooltip, and the reset is the part cut first", function()
	local out = view({
		quota({ label = "7d Fable", used = 0.97, status = "warning" }),
		quota({ label = "7d", used = 0.95, status = "warning" }),
	})
	t.eq(visible.chrome(out), { SWITCH, "■ Claude · work · 7d Fable 97% · resets Sun +1" })
	t.eq(visible.titles(out, "7d Fable 97%"), {
		"Claude · work · 7d Fable 97% · resets Sun\nClaude · work · 7d 95% · resets Sun",
	})
	t.eq(visible.secondary(out, "· resets Sun"), true)
end)

t.test("the worst quota shows first, exhausted before warning and then the higher use, with +N for the others", function()
	local out = view({
		quota({ account = "home", used = 0.91, status = "warning", left = 3 * HOUR }),
		quota({ used = 0.4 }),
		quota({ provider = "Grok", account = "me", label = "Weekly", used = 0.98, status = "warning", left = SUNDAY - NOW + 4 * DAY }),
		quota({ label = "5h", used = 1.0, status = "exhausted", left = 38 * MINUTE }),
	})
	t.eq(visible.chrome(out), { SWITCH, "■ Claude · work · 5h 100% · resets in 38m +2" })
	t.eq(visible.state(out, "Claude · work · 5h 100%"), "failed")
	t.eq(visible.titles(out, "Claude · work · 5h 100%"), {
		"Claude · work · 5h 100% · resets in 38m\nGrok · me · Weekly 98% · resets Thu\nClaude · home · 7d 91% · resets in 3h",
	})
end)

t.test("the reset reads as a weekday when more than a day away, else as the time left", function()
	local function line(left: number): string
		return visible.chrome(view({ quota({ used = 0.95, status = "warning", left = left }) }))[2]
	end
	t.eq(line(SUNDAY - NOW), "■ Claude · work · 7d 95% · resets Sun")
	t.eq(line(23 * HOUR + 59 * MINUTE), "■ Claude · work · 7d 95% · resets in 23h")
	t.eq(line(45), "■ Claude · work · 7d 95% · resets in 45s")
end)

t.test("a quota without an account name shows the provider and the window only", function()
	local alone = quota({ provider = "opencode-go", label = "Monthly", used = 0.91, status = "warning" })
	alone.account = nil
	local out = view({ alone })
	t.eq(visible.chrome(out)[2], "■ opencode-go · Monthly 91% · resets Sun")
end)

-- The quotas the parser reads from `rows` (provider, email, window, limit, used, status), each reset on Sunday.
local function parsed(rows: { { any } }): { any }
	local lines: { string } = {}
	for _, r in rows do
		table.insert(lines, table.concat({ r[1], r[2], r[3], r[4], tostring(r[5]), r[6], tostring((SUNDAY - 1) * 1000) }, "\t"))
	end
	return quotas.parse(table.concat(lines, "\n"), NOW * 1000) :: any
end

t.test("an account named as its provider shows no name in the line", function()
	local out = view(parsed({ { "anthropic", "claude@home.it", "5 Hour", "Claude 5 Hour", 1.0, "exhausted" } }))
	t.eq(visible.chrome(out)[2], "■ Claude · 5h 100% · resets Sun")
end)

t.test("two accounts named as their provider show their email's domains in the line and the tooltip", function()
	local out = view(parsed({
		{ "anthropic", "claude@home.it", "5 Hour", "Claude 5 Hour", 1.0, "exhausted" },
		{ "anthropic", "claude@work.com", "5 Hour", "Claude 5 Hour", 0.9, "warning" },
	}))
	t.eq(visible.chrome(out)[2], "■ Claude · home.it · 5h 100% · resets Sun +1")
	t.eq(visible.titles(out, "Claude · home.it · 5h 100%"), {
		"Claude · home.it · 5h 100% · resets Sun\nClaude · work.com · 5h 90% · resets Sun",
	})
end)

t.test("a quota whose window reset since the last read shows no line", function()
	t.eq(visible.chrome(view({ quota({ used = 1.0, status = "exhausted", left = 0 }) })), { SWITCH })
end)

t.test("the quota line shows in the Recent view too", function()
	local out = view({ quota({ used = 0.97, status = "warning" }) }, { view = "recent", sessions = {} })
	t.eq(visible.chrome(out), { SWITCH, "■ Claude · work · 7d 97% · resets Sun" })
end)

t.test("the sidebar redraws when the reset shows another text, and when the window resets", function()
	local function due(left: number, status: string?): number?
		local q = quota({ used = 0.95, status = status or "warning", left = left })
		return viewModel.redrawDue({ agents = {}, now = 0, time = NOW, quotas = { q } } :: any)
	end
	t.eq(due(38 * MINUTE + 30), 30 * 1000)
	t.eq(due(3 * HOUR + 20 * MINUTE), 20 * MINUTE * 1000)
	-- A reset's millisecond fraction rounds up to a whole second, so a redraw never comes before `time` ticks.
	t.eq(due(0.25), 1000)
	t.eq(due(38 * MINUTE + 0.164), 1000)
	t.eq(due(38 * MINUTE + 30.001), 31 * 1000)
	t.eq(due(42.164), 1000)
	t.eq(due(DAY + 2 * HOUR), 2 * HOUR * 1000)
	t.eq(due(38 * MINUTE + 30, "ok"), nil)
	t.eq(due(38 * MINUTE), 1000)
	t.eq(due(DAY), 1000)
end)

return nil
