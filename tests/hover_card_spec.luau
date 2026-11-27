--!strict
-- The hover card of each row: the state and its time, the tab, the title, the summary or last message, the kind, the
-- model and effort and whether it is pinned, the subagent counts, and a hint of what a click and a right-click do.
local t = require("./harness")
local visible = require("./visible")
local viewModel = require("../lib/view_model")

local ICON = "\u{F0E7}"
local HOME = "/Users/me"
local NOW = 1_800_000_000
local MIN, HOUR, DAY = 60, 60 * 60, 24 * 60 * 60
local FILE = "/Users/me/.omp/agent/sessions/a/1.jsonl"

-- A field set to NONE is left out of the agent.
local NONE = {}

-- An omp agent in pane 4 of tab 3, idle since a minute ago.
local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = {
		pane = 4,
		tab = 944892805171,
		tabNumber = 3,
		state = "idle",
		cwd = "/Users/me/repo",
		repo = "/Users/me/repo",
		title = ICON .. " Fix login",
		activeAt = NOW - MIN,
		sessionFile = FILE,
		route = "anthropic/claude-opus-5-5",
		effort = "high",
	}
	for k, v in fields do
		a[k] = if v == NONE then nil else v
	end
	return a
end

local function build(input: { [string]: any }): any
	local full: { [string]: any } = { agents = {}, now = 0, time = NOW, home = HOME }
	for k, v in input do
		full[k] = v
	end
	return viewModel.build(full :: any).view
end

local function sub(name: string, status: string, extra: { [string]: any }?): { [string]: any }
	local s: { [string]: any } = { id = (string.gsub(name, ">", ".")), name = name, status = status, depth = 1 }
	for k, v in (extra or {}) :: { [string]: any } do
		s[k] = v
	end
	return s
end

local LIVE_HINT = "Click: go to it · Right-click: Pin, Rename, Copy session ID or path"

t.test("a working agent's card: state with its live timer and the tab, title, message, kind and model, crew, hint", function()
	local out = build({
		agents = { agent({ state = "working", workingSince = 0, lastMessage = "Running the tests." }) },
		now = 12000,
		subagents = { [4] = { agents = { sub("A", "running"), sub("B", "running"), sub("C", "done") } } },
	})
	t.eq(
		visible.hover(out, "Fix login"),
		table.concat({
			ICON .. " Working ⏱12s tab 3",
			"Fix login",
			"Running the tests.",
			"omp · anthropic/claude-opus-5-5 high",
			"Subagents: 2 running · 1 done",
			"Click: go to it · Right-click: Pin, Rename, Copy session ID or path, Interrupt",
		}, "\n")
	)
end)

t.test("a waiting agent's card says how long it waits, that it is pinned, and that a click goes to answer it", function()
	local out = build({
		agents = { agent({ state = "waiting_input", activeAt = NOW - 3 * MIN, lastMessage = "Merge now?" }) },
		pins = { { pane = 4 } },
	})
	t.eq(
		visible.cardHover(out, "Fix login"),
		table.concat({
			ICON .. " Waiting for you 3m tab 3",
			"Fix login",
			"Merge now?",
			"omp · anthropic/claude-opus-5-5 high · pinned",
			"Click: go to it and answer · Right-click: Unpin, Copy session ID or path, Interrupt",
		}, "\n")
	)
end)

t.test("an idle agent's card says how long it idles; an agent with no subagents shows no counts", function()
	local out = build({ agents = { agent({ summary = "Pins resume.", lastMessage = string.rep("x", 400) }) } })
	t.eq(
		visible.hover(out, "Fix login"),
		table.concat({
			ICON .. " Idle 1m tab 3",
			"Fix login",
			"Pins resume.",
			"omp · anthropic/claude-opus-5-5 high",
			LIVE_HINT,
		}, "\n")
	)
end)

t.test("a stopped pinned agent's card says how long ago it stopped and that a click resumes it", function()
	local out = build({
		agents = { agent({ state = "exited", tab = NONE, tabNumber = NONE, activeAt = NOW - 2 * DAY }) },
		pins = { { pane = 4, sessionFile = FILE } },
	})
	t.eq(
		visible.hover(out, "Fix login"),
		table.concat({
			ICON .. " Stopped 2d",
			"Fix login",
			"omp · anthropic/claude-opus-5-5 high · pinned",
			"Click: resume in a new tab · Right-click: Unpin, Copy session ID or path",
		}, "\n")
	)
end)

t.test("the card names an agent that is not omp by its program and offers only what works for it", function()
	local function card(command: string): string?
		local out = build({
			agents = {
				agent({ command = command, sessionFile = NONE, route = NONE, effort = NONE, model = "Opus 5.5 \u{F0EB}" }),
			},
		})
		return visible.hover(out, "Fix login")
	end
	local claude = card("claude --resume")
	t.eq(claude, table.concat({ ICON .. " Idle 1m tab 3", "Fix login", "Claude Code · opus 5.5", "Click: go to it · Right-click: Pin" }, "\n"))
	t.eq(string.match(card("/opt/bin/codex") or "", "\n([^\n]*) · opus"), "Codex")
	t.eq(string.match(card("FOO=1 aider") or "", "\n([^\n]*) · opus"), "aider")
end)

t.test("a card leaves out what is not known: no tab, no message, no model, no kind", function()
	local out = build({
		agents = { agent({ tab = NONE, tabNumber = NONE, activeAt = NONE, sessionFile = NONE, route = NONE, effort = NONE }) },
	})
	t.eq(visible.hover(out, "Fix login"), ICON .. " Idle\nFix login\nClick: go to it · Right-click: Pin")
end)

t.test("a subagent line's card: its state and time, its name, what it does, its role, parent, model and a hint", function()
	local out = build({
		agents = { agent({ state = "working", workingSince = 0 }) },
		now = 90000,
		focused = 4,
		subagents = {
			[4] = {
				agents = {
					sub("Lead", "running", { since = 30000, role = "task" }),
					sub("Lead>Fix", "running", {
						depth = 2,
						parent = "Lead",
						role = "reviewer",
						since = 60000,
						model = "gpt-5.1",
						effort = "low",
						intent = "Edit /Users/me/repo/lib/view.luau",
					}),
				},
			},
		},
	})
	t.eq(
		visible.hover(out, "(Running) Fix"),
		table.concat({
			"■ Running 30s",
			"Fix",
			"Edit /Users/me/repo/lib/view.luau",
			"reviewer · under Lead · gpt-5.1 low",
			"Click: show it in omp · Right-click: Copy session ID or path",
		}, "\n")
	)
	t.eq(
		visible.hover(out, "(Running) Lead"),
		"■ Running 1m\nLead\ntask\nClick: show it in omp · Right-click: Copy session ID or path"
	)
end)

t.test("a closed session's card: how long ago it closed, its title, its folder and a hint", function()
	local out = build({
		view = "recent",
		sessions = { { file = FILE, id = "s1", cwd = "/Users/me/repo", repo = "/Users/me/repo", title = ICON .. " Old chat", at = NOW - 5 * HOUR } },
	})
	t.eq(
		visible.hover(out, "Old chat"),
		ICON .. " Closed 5h\nOld chat\n~/repo\nClick: resume in a new tab · Right-click: Copy session ID or path"
	)
end)

return nil
