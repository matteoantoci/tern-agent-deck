--!strict
-- The session reader's output: what one scan of `~/.omp/agent/sessions` tells about each session file.
local t = require("./harness")
local sessions = require("../lib/sessions")

local DIR = "/Users/me/.omp/agent/sessions"
local FILE = "-Personal-tern-agents/2026-11-09T08-21-12-853Z_01a1.jsonl"
local PAD = string.rep(" ", 40)

local function scan(lines: { string }): { any }
	return sessions.parse(table.concat(lines, "\n") .. "\n", DIR)
end

local TITLE = '{"type":"title","v":1,"title":"\u{F0403} TERN: Build plugin","source":"auto","pad":"' .. PAD .. '"}'
local HEADER = '{"type":"session","version":3,"id":"01a1","timestamp":"2026-11-09T08:21:12.853Z",'
	.. '"cwd":"/Users/me/Personal/tern-agents","title":"\u{F0403} older name"}'

t.test("a session file gives its path, id, working directory, title and last write", function()
	t.eq(scan({ "M\t1800000000\t" .. FILE, "F\t" .. FILE, "L\t" .. TITLE, "L\t" .. HEADER }), {
		{
			file = DIR .. "/" .. FILE,
			id = "01a1",
			cwd = "/Users/me/Personal/tern-agents",
			title = "\u{F0403} TERN: Build plugin",
			at = 1800000000,
		},
	})
end)

t.test("an empty title slot falls back to the header's title", function()
	local empty = '{"type":"title","v":1,"title":"","pad":"' .. PAD .. '"}'
	t.eq(scan({ "M\t1\t" .. FILE, "F\t" .. FILE, "L\t" .. empty, "L\t" .. HEADER })[1].title, "\u{F0403} older name")
end)

t.test("an older file starts with the header, which may carry the title", function()
	local found = scan({ "F\t" .. FILE, "L\t" .. HEADER, "L\t" .. '{"type":"model_change","id":"x"}', "M\t5\t" .. FILE })
	t.eq(found[1].title, "\u{F0403} older name")
	t.eq(found[1].at, 5)
	local untitled = '{"type":"session","id":"02","cwd":"/tmp"}'
	t.eq(scan({ "F\t" .. FILE, "L\t" .. untitled, "M\t5\t" .. FILE })[1].title, nil)
end)

t.test("JSON escapes in titles and paths are decoded", function()
	local header = '{"type":"session","id":"03","cwd":"/Users/me/a \\"b\\"\\\\c","title":"caf\\u00e9 \\ud83d\\ude00 \\/ x"}'
	local found = scan({ "F\t" .. FILE, "L\t" .. header, "M\t5\t" .. FILE })[1]
	t.eq(found.cwd, '/Users/me/a "b"\\c')
	t.eq(found.title, "café 😀 / x")
end)

t.test("a header cut at the read limit still gives the fields before the cut", function()
	local cut = '{"type":"session","id":"04","cwd":"/repo","additionalDirectories":["/a","/b'
	t.eq(scan({ "F\t" .. FILE, "L\t" .. cut, "M\t5\t" .. FILE })[1].cwd, "/repo")
end)

t.test("a file without a working directory, or without a last write, is skipped", function()
	t.eq(scan({ "F\t" .. FILE, "L\t" .. '{"type":"session","id":"05"}', "M\t5\t" .. FILE }), {})
	t.eq(scan({ "F\t" .. FILE, "L\t" .. HEADER }), {})
end)

t.test("a file a process holds open is marked open", function()
	local found = scan({ "F\t" .. FILE, "L\t" .. HEADER, "M\t5\t" .. FILE, "O\t" .. DIR .. "/" .. FILE })
	t.eq(found[1].open, true)
end)

t.test("several files keep their own lines", function()
	local other = "-tmp/2026-11-08T00-00-00-000Z_02.jsonl"
	local found = scan({
		"M\t7\t" .. other,
		"M\t5\t" .. FILE,
		"F\t" .. FILE,
		"L\t" .. TITLE,
		"L\t" .. HEADER,
		"F\t" .. other,
		"L\t" .. '{"type":"session","id":"02","cwd":"/tmp"}',
	})
	t.eq(#found, 2)
	local byId: { [string]: any } = {}
	for _, s in found do
		byId[s.id] = s
	end
	t.eq(byId["01a1"].cwd, "/Users/me/Personal/tern-agents")
	t.eq(byId["02"].cwd, "/tmp")
	t.eq(byId["02"].at, 7)
end)

t.test("a path the scan writes as ./path names the same file in every record", function()
	local rel = "./" .. FILE
	local found = scan({ "M\t5\t" .. rel, "F\t" .. rel, "L\t" .. HEADER, "O\t" .. rel })
	t.eq(#found, 1)
	t.eq(found[1].file, DIR .. "/" .. FILE)
	t.eq(found[1].open, true)
end)

return nil
