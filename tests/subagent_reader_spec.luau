--!strict
-- The subagent reader against a fake window: omp runs `task` subagents in the background, so its agent can end its
-- turn and go idle while they work. The reader reads them from omp's tray in the pane's dock.
local t = require("./harness")

local clock = 0

local reader = require("../lib/subagent_reader")

local function card(ref: string, status: string): any
	return { id = "tray/" .. ref, k = "col", p = { role = "omp.tray.card", item = "agent", ref = ref, status = status } }
end

-- A dock read holding a tray with `cards`; no tray when `cards` is nil. `shown` adds omp's viewing header.
local function dockRead(cards: { any }?, shown: string?): any
	local c: { any } = {}
	if shown then
		table.insert(c, {
			id = "3.focus",
			k = "row",
			p = { role = "omp.composer.focus" },
			c = {
				{ id = "3.focus/agent", k = "text", p = { role = "omp.composer.agent", text = shown } } :: any,
				{ id = "3.focus/exit", k = "row", p = { actions = { click = "focus:Main" } } },
			},
		})
	end
	if cards then
		table.insert(c, { id = "tray", k = "col", p = { role = "omp.tray" }, c = cards })
	end
	return { surface = { id = "s" }, main = { id = "dock", k = "col", c = c } }
end

-- A window with one omp agent in pane 7, in `state`, whose dock holds a tray with `cards`; counts the dock reads.
local function window(state: string, cards: { any }?, shown: string?): any
	local cx: any = { reads = 0 }
	cx.agents = {
		list = function(_self: any)
			return { { pane = 7, state = state } }
		end,
	}
	cx.session = {
		surface = function(_self: any, _pane: number, opts: any)
			assert(opts.root == "dock", "only the dock is read")
			cx.reads += 1
			return dockRead(cx.cards, cx.shown)
		end,
	}
	cx.cards = cards
	cx.shown = shown
	return cx
end

local function names(): { string }
	local out = {}
	local subs = reader.subagents()[7]
	for _, sub in (if subs then subs.agents else {}) :: { any } do
		table.insert(out, sub.name .. " " .. sub.status)
	end
	return out
end

local function step(cx: any, after: number?): boolean
	clock += after or 1000
	local _, polling = reader.step(cx, clock)
	return polling
end

-- Leaves the reader with no polled or checked pane.
local function reset()
	step(window("exited"))
end

t.test("an agent that goes idle while its subagent runs keeps its subagent rows, and the reader keeps polling", function()
	reset()
	t.eq(step(window("working", { card("Copy", "running") })), true)
	t.eq(names(), { "Copy running" })
	t.eq(step(window("idle", { card("Copy", "running") })), true)
	t.eq(names(), { "Copy running" })
	reset()
end)

t.test("a queued subagent keeps an idle agent polled", function()
	reset()
	step(window("working", { card("Copy", "queued") }))
	t.eq(step(window("idle", { card("Copy", "queued") })), true)
	t.eq(names(), { "Copy pending" })
	reset()
end)

t.test("once nothing runs, an idle agent drops its rows and the reader stops polling", function()
	reset()
	step(window("working", { card("Copy", "done"), card("Scan", "running") }))
	t.eq(names(), { "Copy done", "Scan running" })
	local cx = window("idle", { card("Copy", "done"), card("Scan", "done") })
	step(cx)
	t.eq(names(), {})
	t.eq(step(cx, 1), false, "checked once, then left alone")
	reset()
end)

t.test("a working agent shows no rows for finished subagents of earlier turns while none runs", function()
	reset()
	step(window("working", { card("Copy", "done"), card("Scan", "failed") }))
	t.eq(names(), {})
	reset()
end)

t.test("an agent that exits drops its subagent rows", function()
	reset()
	step(window("working", { card("Copy", "running") }))
	t.eq(step(window("exited", { card("Copy", "running") })), false)
	t.eq(names(), {})
end)

t.test("an unpolled idle agent is found by its dock check, which runs again only after the interval", function()
	reset()
	local cx = window("idle", { card("Copy", "done") })
	step(cx, 5000)
	t.eq(cx.reads, 1)
	t.eq(names(), {})
	cx.cards = { card("Copy", "done"), card("Copy2", "running") }
	step(cx, 1000)
	t.eq(cx.reads, 1, "no check before the interval")
	t.eq(names(), {})
	step(cx, 4000)
	t.eq(names(), { "Copy done", "Copy2 running" })
	t.eq(step(cx), true, "polled from now on")
	reset()
end)

t.test("while omp shows a subagent and the read has no tray, the last rows stay, frozen", function()
	reset()
	local cx = window("working", { card("Copy", "running"), card("Scan", "running") })
	step(cx)
	cx.cards = nil
	cx.shown = "Scan"
	step(cx)
	t.eq(names(), { "Copy running", "Scan running" })
	t.eq(reader.subagents()[7].frozen, true)
	t.eq(reader.viewing()[7], "Scan")
	cx.shown = nil
	step(cx)
	t.eq(names(), {}, "no tray and no view: no rows")
	reset()
end)

return nil
