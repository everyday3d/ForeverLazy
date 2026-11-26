-- Reaching a stop, with or without the arrow on screen (no game needed): lua tests/arrival.lua
-- The arrival code is taken out of ForeverLazy.lua as it stands and run against a pretend game.
local src = io.open("ForeverLazy/ForeverLazy.lua", "rb"):read("a"):gsub("\r\n", "\n")
local a = assert(src:find("local wpArrived\n", 1, true), "arrival code not found")
local b = assert(src:find("local function UpdateWaypointArrow", a, true))
local chunk = "local db, addon, hbd, PlayAlert, Print, L, C_Timer = ...\n" .. src:sub(a, b - 1)

local taxi, ghost = false, false
UnitOnTaxi = function() return taxi end
UnitIsGhost = function() return ghost end
local sounds, removed, open = 0, {}, false
local db = { arrival = 10, arrivalSound = true, waypointAutoClear = true, waypoints = {} }
local addon = { StopHasOpenObjectives = function() return open end }
function addon:RemoveWaypoint(i) removed[#removed + 1] = table.remove(db.waypoints, i).name end
local where = { 0, 0, 1 }
local hbd = { GetPlayerWorldPosition = function() return table.unpack(where) end }
assert(load(chunk))(db, addon, hbd, function() sounds = sounds + 1 end, function() end, function(s) return s end,
    { After = function(_, fn) fn() end })
local A = addon.Arrival

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function Stop(name, x) return { name = name, x = x, y = 0, instance = 1 } end

test("distance to a stop, and none on another continent", function()
    assert(A.DistanceTo(Stop("a", 30)) == 30)
    assert(A.DistanceTo({ x = 1, y = 1, instance = 2 }) == nil)
end)
test("reaching a stop sounds once and clears it", function()
    local s = Stop("Inn", 5)
    db.waypoints = { s, Stop("Next", 900) }
    A.Arrive(s, A.DistanceTo(s))
    assert(sounds == 1 and removed[1] == "Inn" and #db.waypoints == 1)
    A.Arrive(s, 5)
    assert(sounds == 1, "sounded twice")
end)
test("a stop with work left stays", function()
    open = true
    local s = Stop("Wolves", 3)
    db.waypoints = { s }
    A.Arrive(s, 3)
    assert(#db.waypoints == 1)
    open = false
end)
test("passing over a stop on a flight path or as a ghost is not arriving", function()
    local s = Stop("Under me", 2)
    db.waypoints = { s }
    taxi = true; A.Arrive(s, 2); taxi = false
    ghost = true; A.Arrive(s, 2); ghost = false
    assert(#db.waypoints == 1)
    A.Arrive(s, 2)
    assert(#db.waypoints == 0)
end)
test("a hidden arrow still counts arrival", function()
    local body = src:sub(b, src:find("\nlocal function ShouldHide", b, true))
    local hidden = body:match("if not show or addon%.ArrowHidden%(%) then(.-)\n    end")
    assert(hidden and hidden:find("Arrive(wp, DistanceTo(wp))", 1, true), "the hidden branch does not check arrival")
end)

test("the main arrow is off until it is turned on, and compass bar on", function()
    db.waypointArrowOff = nil; assert(addon.ArrowHidden())
    db.waypointArrowOff = true; assert(addon.ArrowHidden())
    db.waypointArrowOff = false; assert(not addon.ArrowHidden())
    assert(src:find("\n    compassBar = true,", 1, true), "the compass should start on")
end)
test("a hand-in has more room than other stops", function()
    local before = sounds
    local plain = Stop("3. Kill wolves", 15)
    db.waypoints = { plain }; A.Arrive(plain, 15)
    assert(sounds == before, "a plain stop counted from 15 yards")
    local turn = Stop("4. Turn in: Wolves", 15)
    open = true
    db.waypoints = { turn }; A.Arrive(turn, 15)
    assert(sounds == before + 1, "no sound at a hand-in 15 yards off")
    assert(#db.waypoints == 1, "a hand-in not handed in yet must stay")
    open = false
end)
test("walking well away and back sounds again, standing around does not", function()
    local before = sounds
    local s = Stop("Turn in: Bears", 10)
    open = true
    db.waypoints = { s }
    A.Arrive(s, 10); A.Arrive(s, 18); A.Arrive(s, 10)
    assert(sounds == before + 1)
    A.Arrive(s, 150); A.Arrive(s, 10)
    assert(sounds == before + 2)
    open = false
end)
test("the hand-in close by rule measures in yards", function()
    local ex = io.open("ForeverLazy/Extras.lua", "rb"):read("a"):gsub("\r\n", "\n")
    local i = assert(ex:find("local HANDIN_NEAR", 1, true))
    local j = assert(ex:find("function addon.ArrowTarget()", i, true))
    local code = "local ns, api, hbd = ...\n" .. ex:sub(i, j - 1) .. "\nreturn NearbyHandIn"
    local clock, npcAt = 100, 300
    GetTime = function() return clock end
    C_QuestLog = { GetNumQuestLogEntries = function() return 1 end, GetInfo = function() return { questID = 7, title = "Wolves" } end, IsComplete = function() return true end }
    local near = assert(load(code))({ data = { Field = function() return { { 1 }, {} } end } },
        { AddNpcs = function(l) l[#l + 1] = { instance = 1, x = npcAt, y = 0 } end, D2 = function(a, b, c, d) return (a - c) ^ 2 + (b - d) ^ 2 end },
        { GetPlayerWorldPosition = function() return 0, 0, 1 end })
    local spot = near()
    assert(spot and spot.name == "Turn in: Wolves", "300 yards away was not found")
    npcAt, clock = 600, 200
    assert(near() == nil, "600 yards is not close by")
    GetTime, C_QuestLog = nil, nil
end)
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
