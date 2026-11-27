-- Offline tests for following the levelling route (no game needed).   lua tests/route.lua
local root = (arg and arg[0] or "tests/route.lua"):gsub("[/\\]tests[/\\]route%.lua$", ""):gsub("^tests[/\\]route%.lua$", ".")

local db = {}
local said = {}
local addon = { Print = function(m) said[#said + 1] = m end, GetDB = function() return db end, RefreshOptions = function() end }
local ns = { addon = addon, L = function(x) return x end, data = { Field = function() return nil end }, dataset = {} }
function CreateFrame()
    local f = setmetatable({}, { __index = function() return function() end end })
    return f
end
assert(loadfile(root .. "/ForeverLazy/RouteHints.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "differs") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end

local route = {
    Alliance = {
        { name = "1-11 Elwynn Forest", only = "Human", steps = "a783 t783 a7 a5261 t5261 a33 a1598!Warlock a18 a91741? t7 t33 t18" },
        { name = "1-14 Dun Morogh", only = "Dwarf", steps = "a179 t179" },
        { name = "11-17 Westfall", only = "Alliance", steps = "a65 a36 t65 t36" },
    },
    Horde = { { name = "1-12 Durotar", only = "Orc", steps = "a4641" } },
}

test("a human gets the human start, then the shared guides, not the dwarf one", function()
    local st = addon.RouteSteps(route, "Alliance", "Human", "Human")
    local ids = {}
    for _, s in ipairs(st) do ids[#ids + 1] = s.kind .. s.id end
    local text = table.concat(ids, " ")
    assert(text:find("^a783 t783 a7"), text)
    assert(text:find("a65 a36 t65 t36$"), text)
    assert(not text:find("a179"), "no dwarf steps: " .. text)
end)

test("class limits and optional marks are kept", function()
    local st = addon.RouteSteps(route, "Alliance", "Human", "Human")
    local warlock, optional
    for _, s in ipairs(st) do
        if s.id == 1598 then warlock = s.class end
        if s.id == 91741 then optional = s.optional end
    end
    eq(warlock, "warlock"); eq(optional, true)
end)

test("a night elf's race name matches with spaces and capitals ignored", function()
    local r = { Alliance = { { name = "x", only = "NightElf", steps = "a456" } } }
    eq(#addon.RouteSteps(r, "Alliance", "NightElf", "Night Elf"), 1)
    eq(#addon.RouteSteps(r, "Alliance", "Human", "Human"), 0)
end)

-- a little world: what is done, in the log, complete, and available
local function World(t)
    local w = { done = {}, log = {}, complete = {}, blocked = {}, class = "warrior" }
    for k, v in pairs(t or {}) do w[k] = v end
    return {
        class = w.class,
        done = function(id) return w.done[id] == true end,
        inLog = function(id) return w.log[id] == true end,
        complete = function(id) return w.complete[id] == true end,
        available = function(id) return not w.blocked[id] end,
    }, w
end

test("a new character: the first step is to pick up the first quest", function()
    local st = addon.RouteSteps(route, "Alliance", "Human", "Human")
    local ctx = World()
    local step = addon.RouteCurrentStep(st, ctx)
    eq(step.act, "pickup"); eq(step.id, 783)
end)

test("the route goes pick up, do, hand in, next", function()
    local st = addon.RouteSteps(route, "Alliance", "Human", "Human")
    local ctx, w = World({ log = { [783] = true } })
    local step = addon.RouteCurrentStep(st, ctx)
    eq(step.act, "objectives", "quest 783 is in the log, not finished: do it"); eq(step.id, 783)
    w.complete[783] = true
    step = addon.RouteCurrentStep(st, ctx)
    eq(step.act, "turnin"); eq(step.id, 783)
    w.log[783] = nil; w.complete[783] = nil; w.done[783] = true
    step = addon.RouteCurrentStep(st, ctx)
    eq(step.act, "pickup"); eq(step.id, 7, "then the next quest")
end)

test("a quest for another class, an optional one and one I cannot take yet are passed over", function()
    local st = addon.RouteSteps(route, "Alliance", "Human", "Human")
    local ctx, w = World({ done = { [783] = true, [7] = true, [5261] = true, [33] = true }, blocked = { [18] = true } })
    local step = addon.RouteCurrentStep(st, ctx)
    -- 1598 is the warlock's, 18 is blocked, 91741 is optional: the next real thing is Westfall
    eq(step.id, 65, "got " .. tostring(step and step.id))
    ctx = World({ class = "warlock", done = { [783] = true, [7] = true, [5261] = true, [33] = true } })
    eq(addon.RouteCurrentStep(st, ctx).id, 1598, "a warlock does get it")
end)

test("the next pick-ups skip what is done or in the log, and stop at the limit", function()
    local st = addon.RouteSteps(route, "Alliance", "Human", "Human")
    local ctx = World({ done = { [783] = true }, log = { [7] = true } })
    local ids = addon.RouteNextPickups(st, ctx, 2)
    eq(#ids, 2); eq(ids[1], 5261); eq(ids[2], 33)
end)

test("quests in my log that the route leaves out are listed", function()
    local st = addon.RouteSteps(route, "Alliance", "Human", "Human")
    local skips = addon.RouteSkips(st, { 783, 99999, 7, 88888 })
    eq(#skips, 2); eq(skips[1], 99999); eq(skips[2], 88888)
end)

test("nothing left on the route: no step", function()
    local st = addon.RouteSteps({ Alliance = { { name = "x", only = "Alliance", steps = "a1 t1" } } }, "Alliance", "Human", "Human")
    local ctx = World({ done = { [1] = true } })
    eq(addon.RouteCurrentStep(st, ctx), nil)
end)

test("/lazy route on and off", function()
    addon:HandleExtraCommand("route", "on"); eq(db.routeHints, true)
    addon:HandleExtraCommand("route", "off"); eq(db.routeHints, nil)
end)

test("saved waypoint routes keep their commands", function()
    local passedOn = {}
    local ns2 = { addon = { Print = function() end, GetDB = function() return db end, HandleExtraCommand = function(_, _, rest) passedOn[#passedOn + 1] = rest; return true end },
                  L = ns.L, data = ns.data, dataset = {} }
    assert(loadfile(root .. "/ForeverLazy/RouteHints.lua"))("ForeverLazy", ns2)
    db.routeHints = nil
    for _, rest in ipairs({ "save Home Run", "load Home Run", "delete Home Run", "list" }) do ns2.addon:HandleExtraCommand("route", rest) end
    eq(#passedOn, 4); eq(passedOn[1], "save Home Run", "the name keeps its capitals")
    eq(db.routeHints, nil, "none of them switched the route on")
    ns2.addon:HandleExtraCommand("route", "on"); eq(db.routeHints, true); eq(#passedOn, 4)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
