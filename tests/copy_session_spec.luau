--!strict
-- The right-click menu of every session row (a live agent, a subagent, a closed session) copies the omp session's ID
-- or the absolute path of its `.jsonl` file.
local t = require("./harness")
local visible = require("./visible")
local sessionCopy = require("../lib/session_copy")
local sessions = require("../lib/sessions")
local viewModel = require("../lib/view_model")

local HOME = "/Users/me"
local REPO = "/Users/me/Personal/tern-agents"
local SESSION = "/Users/me/.omp/agent/sessions/-Personal-tern-agents/2026-11-09T08-21-12-853Z_01a1bf65.jsonl"

local function agent(fields: { [string]: any }): { [string]: any }
	local a: { [string]: any } = { pane = 1, state = "idle", cwd = REPO, repo = REPO, title = "Fix login" }
	for k, v in fields do
		a[k] = v
	end
	return a
end

local function view(input: { [string]: any }): any
	local full: { [string]: any } = { agents = {}, now = 0, home = HOME }
	for k, v in input do
		full[k] = v
	end
	return viewModel.build(full :: any).view
end

t.test("a live agent's right-click menu copies its session ID and path, between Rename and Interrupt", function()
	local v = view({ agents = { agent({ pane = 2, title = "build", state = "working", sessionFile = SESSION }) } })
	t.eq(visible.menu(v, "build"), {
		"Pin → pin=2",
		"Rename → rename=2",
		"Copy session ID → copy-id=" .. SESSION,
		"Copy session path → copy-path=" .. SESSION,
		"Interrupt → interrupt=2",
	})
end)

t.test("an agent whose omp reported no session file has both copy items off, with the reason", function()
	local v = view({ agents = { agent({ pane = 2, title = "build", state = "working" }) } })
	local off = " (off: omp has not reported a session file for this agent)"
	t.eq(visible.menu(v, "build"), {
		"Pin → pin=2",
		"Rename → rename (off: Only an omp session can be renamed, and this agent reported none)",
		"Copy session ID → copy-id" .. off,
		"Copy session path → copy-path" .. off,
		"Interrupt → interrupt=2",
	})
end)

t.test("a closed session's right-click menu copies its session ID and path", function()
	local closed = "/Users/me/.omp/agent/sessions/-Personal-tern-agents/2026-11-08T10-00-00-000Z_01a1b0.jsonl"
	local v = view({
		agents = { agent({ pane = 2, title = "build" }) },
		sessions = { { file = closed, id = "01a1b0", cwd = REPO, repo = REPO, title = "Old chat", at = 100 } },
		time = 200,
		view = "recent",
		recentOpen = { ["repo-_2FUsers_2Fme_2FPersonal_2Ftern-agents"] = true },
	})
	t.eq(visible.menu(v, "Old chat"), {
		"Copy session ID → copy-id=" .. closed,
		"Copy session path → copy-path=" .. closed,
	})
end)

-- A working agent with one first-level subagent and one nested under it, as the subagent reader gives them.
local function withSubagents(sessionFile: string?): any
	return view({
		agents = { agent({ pane = 7, title = "Lead", state = "working", workingSince = 0, sessionFile = sessionFile }) },
		subagents = {
			[7] = {
				agents = {
					{ id = "dx.Ticket07", name = "Ticket07", status = "running", depth = 1 },
					{ id = "dy.Ticket07.Fix", name = "Ticket07>Fix", status = "running", depth = 2, parent = "Ticket07" },
				},
				incomplete = false,
			},
		},
	})
end

t.test("a subagent's right-click menu copies its own session file, in its agent's session folder", function()
	local folder = string.sub(SESSION, 1, -#".jsonl" - 1)
	local v = withSubagents(SESSION)
	t.eq(visible.menu(v, "(Running) Ticket07"), {
		"Copy session ID → copy-id=" .. folder .. "/Ticket07.jsonl",
		"Copy session path → copy-path=" .. folder .. "/Ticket07.jsonl",
	})
	t.eq(visible.menu(v, "Ticket07>Fix"), {
		"Copy session ID → copy-id=" .. folder .. "/Ticket07/Ticket07.Fix.jsonl",
		"Copy session path → copy-path=" .. folder .. "/Ticket07/Ticket07.Fix.jsonl",
	}, "a nested subagent's file sits in its parent's folder, named by its omp id")
end)

t.test("a subagent's copy items are off while its agent's session file is unknown", function()
	local off = " (off: omp has not reported a session file for this agent)"
	t.eq(visible.menu(withSubagents(nil), "Ticket07>Fix"), {
		"Copy session ID → copy-id" .. off,
		"Copy session path → copy-path" .. off,
	})
end)

-- The start of a session file as the click reads it: omp's 256-byte title slot, then the header.
local HEAD = '{"type":"title","v":1,"title":"\u{F0403} TERN: Build plugin","pad":"    "}\n'
	.. '{"type":"session","version":3,"id":"01a1bf65-a815-71bf-9b92-9ddf1bf78e82","timestamp":"2026-11-09T08:21:12.853Z",'
	.. '"cwd":"/Users/me/Personal/tern-agents"}\n'
	.. '{"type":"model_change","id":"x1"'

t.test("Copy session ID copies the id of the file's header and says so", function()
	t.eq(sessionCopy.resolve("copy-id", SESSION, HEAD), {
		text = "01a1bf65-a815-71bf-9b92-9ddf1bf78e82",
		level = "success",
		toast = "Copied session ID",
	})
end)

t.test("Copy session path copies the absolute path of the session file and says so", function()
	t.eq(sessionCopy.resolve("copy-path", SESSION, HEAD), { text = SESSION, level = "success", toast = "Copied session path" })
end)

t.test("an older session file that starts with its header gives its id too", function()
	local older = '{"type":"session","id":"01a0","cwd":"/tmp"}\n{"type":"message"}'
	t.eq(sessionCopy.resolve("copy-id", SESSION, older).text, "01a0")
end)

t.test("a session file that is not there copies nothing and says why", function()
	local missing = { level = "error", toast = "Could not copy the session ID", sub = "No session file at " .. SESSION }
	t.eq(sessionCopy.resolve("copy-id", SESSION, nil), missing)
	t.eq(sessionCopy.resolve("copy-path", SESSION, nil), {
		level = "error",
		toast = "Could not copy the session path",
		sub = "No session file at " .. SESSION,
	})
end)

t.test("a file whose start holds no session header has no ID to copy", function()
	t.eq(sessionCopy.resolve("copy-id", SESSION, '{"type":"title","title":""}\n{"type":"message"}'), {
		level = "error",
		toast = "Could not copy the session ID",
		sub = "The file has no omp session header",
	})
end)

t.test("the session file each pane's omp reported comes from `tern inspect --json`", function()
	-- Shaped like Tern 0.9.13's output on 2026-11-09 (other fields cut); a null member is dropped by `tern.json.decode`.
	local inspect: any = {
		sessions = { { id = 4, name = "Default" } },
		panes = {
			{ pane = 17179869199, program = "/bin/zsh", omp_session_file = SESSION, working = true } :: any,
			{ pane = 17179869279, program = "tern.canvas", working = false } :: any,
			{ pane = 17179869300, program = "/bin/zsh", omp_session_file = "" } :: any,
		},
	}
	t.eq(sessions.reported(inspect), { [17179869199] = SESSION })
	t.eq(sessions.reported({}), {}, "an answer without panes")
	t.eq(sessions.reported(nil), {}, "no answer")
end)

return nil
