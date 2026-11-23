-- Offline tests for the plan rules (no game needed).
--   lua tests/run.lua
-- They load ForeverLazy/PlanGuard.lua with a few stand-ins for the game's functions and test the rule layer: which plan stops
-- break a rule, and what the plan looks like after they are taken out.
local root = (arg and arg[0] or "tests/run.lua"):gsub("[/\\]tests[/\\]run%.lua$", ""):gsub("^tests[/\\]run%.lua$", ".")

-- stand-ins ------------------------------------------------------------------
local function noop() end
local frameMT = { __index = function(t, k) return noop end }
function CreateFrame() return setmetatable({}, frameMT) end
UIParent = setmetatable({}, frameMT)
UISpecialFrames = {}
local db = { waypoints = {}, planSkip = {} }
local addon = { Print = noop, GetDB = function() return db end, RefreshPins = noop, RefreshOptions = noop }
local ns = { addon = addon, api = { hbd = { GetPlayerWorldPosition = function() return 0, 0, 1 end } } }
ns.L = function(t) return t end

local chunk = assert(loadfile(root .. "/ForeverLazy/PlanGuard.lua"))
chunk("ForeverLazy", ns)

-- tiny test runner -----------------------------------------------------------
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name)
    else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "values differ") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end
end

local function stop(label, instance, quests)
    return { label = label, name = label, instance = instance or 1, x = 100, y = 100, quests = quests }
end
local function q(id, label) return { id = id, label = label } end

-- facts about my quests, set per test
local facts
local function env()
    return {
        inLog = function(id) local f = facts.inLog; if f == nil then return nil end; return f[id] end,
        isComplete = function(id) local f = facts.complete; if f == nil then return nil end; return f[id] end,
        isDungeon = function(id) return facts.dungeon and facts.dungeon[id] or false end,
        isSkipped = function(id) return facts.skipped and facts.skipped[id] or false end,
        instance = 1,
    }
end
local function check(stops)
    local problems, removals = addon.PlanCheckStops(stops, env())
    local out, changed = addon.PlanApplyRemovals(stops, removals)
    return problems, out, changed
end

-- the tests ------------------------------------------------------------------
test("a dungeon quest is taken out, the others stay", function()
    facts = { inLog = { [1] = true, [2] = true }, complete = { [1] = false, [2] = false }, dungeon = { [2] = true } }
    local stops = { stop("A + B", 1, { q(1, "A"), q(2, "B") }) }
    local problems, out = check(stops)
    eq(#problems, 1)
    eq(problems[1].rule, "dungeon")
    eq(#out, 1)
    eq(#out[1].quests, 1)
    eq(out[1].label, "A")
end)

test("a stop that only held a dungeon quest disappears", function()
    facts = { inLog = { [2] = true }, complete = { [2] = false }, dungeon = { [2] = true } }
    local _, out = check({ stop("B", 1, { q(2, "B") }), stop("C", 1, { q(3, "C") }) })
    eq(#out, 1)
    eq(out[1].label, "C")
end)

test("a finished dungeon quest can still be handed in", function()
    facts = { inLog = { [2] = true }, complete = { [2] = true }, dungeon = { [2] = true } }
    local problems, out = check({ stop("Turn in: B", 1, { q(2, "Turn in: B") }) })
    eq(#problems, 0)
    eq(#out, 1)
end)

test("a hand-in for a quest that is not finished is taken out", function()
    facts = { inLog = { [1] = true }, complete = { [1] = false } }
    local problems, out = check({ stop("Turn in: A", 1, { q(1, "Turn in: A") }) })
    eq(problems[1].rule, "hand-in-early")
    eq(#out, 0)
end)

test("a hand-in for a quest that is gone from my log is taken out", function()
    facts = { inLog = { [1] = false } }
    local problems, out = check({ stop("Turn in: A", 1, { q(1, "Turn in: A") }) })
    eq(problems[1].rule, "handed-in")
    eq(#out, 0)
end)

test("a finished quest's hand-in stays", function()
    facts = { inLog = { [1] = true }, complete = { [1] = true } }
    local problems, out = check({ stop("Turn in: A", 1, { q(1, "Turn in: A") }) })
    eq(#problems, 0)
    eq(#out, 1)
end)

test("an accept step for a quest already accepted is taken out", function()
    facts = { inLog = { [1] = true }, complete = { [1] = false } }
    local problems, out = check({ stop("Pick up: A", 1, { q(1, "Pick up: A") }) })
    eq(problems[1].rule, "accepted")
    eq(#out, 0)
end)

test("an accept step for a quest not yet accepted stays", function()
    facts = { inLog = { [1] = false } }
    local problems, out = check({ stop("Pick up: A", 1, { q(1, "Pick up: A") }) })
    eq(#problems, 0)
    eq(#out, 1)
end)

test("a class quest accept step counts as an accept step", function()
    facts = { inLog = { [1] = true }, complete = { [1] = false } }
    local problems = check({ stop("Class quest: A", 1, { q(1, "Class quest: A") }) })
    eq(problems[1].rule, "accepted")
end)

test("objectives for a quest that is not in my log are taken out", function()
    facts = { inLog = { [1] = false } }
    local problems, out = check({ stop("A", 1, { q(1, "A") }) })
    eq(problems[1].rule, "not-in-log")
    eq(#out, 0)
end)

test("a skipped quest is taken out", function()
    facts = { inLog = { [1] = true }, complete = { [1] = false }, skipped = { [1] = true } }
    local problems, out = check({ stop("A", 1, { q(1, "A") }) })
    eq(problems[1].rule, "skipped")
    eq(#out, 0)
end)

test("the same step twice is taken out once", function()
    facts = { inLog = { [1] = true }, complete = { [1] = false } }
    local problems, out = check({ stop("A", 1, { q(1, "A") }), stop("A", 1, { q(1, "A") }) })
    eq(problems[1].rule, "duplicate")
    eq(#out, 1)
end)

test("when nothing is known about the quests, nothing changes", function()
    facts = {}
    local problems, out, changed = check({ stop("Turn in: A", 1, { q(1, "Turn in: A") }), stop("B", 1, { q(2, "B") }) })
    eq(#problems, 0)
    eq(#out, 2)
    eq(changed, false)
end)

test("a stop on another continent is reported but not removed", function()
    facts = { inLog = { [1] = true }, complete = { [1] = false } }
    local problems, out = check({ stop("A", 2, { q(1, "A") }) })
    eq(problems[1].rule, "other-continent")
    eq(problems[1].fix, false)
    eq(#out, 1)
end)

test("stops are renumbered after a removal", function()
    facts = { inLog = { [1] = true, [2] = true, [3] = true }, complete = { [1] = false, [2] = false, [3] = false }, dungeon = { [1] = true } }
    local _, out = check({ stop("A", 1, { q(1, "A") }), stop("B", 1, { q(2, "B") }), stop("C", 1, { q(3, "C") }) })
    eq(#out, 2)
    eq(out[1].name, "1. B")
    eq(out[2].name, "2. C")
end)

test("waypoints that are not plan stops are left alone", function()
    facts = { inLog = { [1] = false } }
    local trip = { name = "Trip: Stormwind", go = true, instance = 1, x = 1, y = 1 }
    local vendor = { name = "Vendor", instance = 1, x = 1, y = 1 }
    local problems, out = check({ trip, vendor })
    eq(#problems, 0)
    eq(#out, 2)
end)

test("quest kinds are read from the label", function()
    eq(addon.PlanQuestKind({ label = "Turn in: X" }), "turn")
    eq(addon.PlanQuestKind({ label = "Pick up: X" }), "pick")
    eq(addon.PlanQuestKind({ label = "Class quest: X" }), "pick")
    eq(addon.PlanQuestKind({ label = "X" }), "do")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
