-- Offline tests for the pedometer (no game needed).
--   lua tests/pedometer.lua
local root = (arg and arg[0] or "tests/pedometer.lua"):gsub("[/\\]tests[/\\]pedometer%.lua$", ""):gsub("^tests[/\\]pedometer%.lua$", ".")

local db = { units = "yd" }
local said, shown = {}, nil
local addon = { Print = function(m) said[#said + 1] = m end, GetDB = function() return db end, ReportWindow = function(t, l) shown = { title = t, text = table.concat(l, "\n") } end }
local ns = { addon = addon, api = { hbd = { GetPlayerWorldPosition = function() return nil end, GetPlayerZone = function() return 1 end } }, L = function(x) return x end }

local scripts = {}
function CreateFrame()
    local f = setmetatable({}, { __index = function() return function() end end })
    f.SetScript = function(_, name, fn) scripts[#scripts + 1] = { name = name, fn = fn } end
    return f
end
local today = "2026-11-23"
function date() return today end
function UnitLevel() return 30 end
function IsMounted() return false end
function UnitOnTaxi() return false end
function IsFlying() return false end
C_Map = { GetMapInfo = function(id) return { name = "Wetlands" } end }

assert(loadfile(root .. "/ForeverLazy/Pedometer.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function near(a, b, msg) if math.abs(a - b) > 0.001 then error((msg or "not close") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end
local function reset() db.pedo = nil; addon:HandleExtraCommand("steps", "reset"); addon.PedometerFeed(nil) end

test("walking adds up the distance", function()
    reset()
    addon.PedometerFeed(0, 0, 1, true, 100)
    near(addon.PedometerFeed(3, 4, 1, true, 100), 5)
    near(addon.PedometerFeed(3, 14, 1, true, 100), 10)
    near(db.pedo.total, 15); near(db.pedo.level, 15); near(db.pedo.days[today], 15); near(db.pedo.zones[100], 15)
end)

test("a jump (teleport, loading screen, fast ride) is not counted", function()
    reset()
    addon.PedometerFeed(0, 0, 1, true, 1)
    near(addon.PedometerFeed(500, 0, 1, true, 1), 0)
    near(db.pedo and db.pedo.total or 0, 0)
    near(addon.PedometerFeed(505, 0, 1, true, 1), 5, "counting goes on from the new place")
end)

test("a different instance (continent) starts a fresh reading", function()
    reset()
    addon.PedometerFeed(0, 0, 1, true, 1)
    near(addon.PedometerFeed(10, 0, 530, true, 1), 0)
    near(addon.PedometerFeed(14, 3, 530, true, 1), 5)
end)

test("not on foot is not counted (mounted, flight)", function()
    reset()
    addon.PedometerFeed(0, 0, 1, false, 1)
    near(addon.PedometerFeed(6, 8, 1, false, 1), 0)
    near(db.pedo and db.pedo.total or 0, 0)
end)

test("standing still adds nothing", function()
    reset()
    addon.PedometerFeed(0, 0, 1, true, 1)
    near(addon.PedometerFeed(0, 0, 1, true, 1), 0)
end)

test("a level up keeps the old level's distance and starts again", function()
    reset()
    addon.PedometerFeed(0, 0, 1, true, 1)
    addon.PedometerFeed(0, 20, 1, true, 1)
    for _, s in ipairs(scripts) do if s.name == "OnEvent" then s.fn(nil, "PLAYER_LEVEL_UP", 31) end end
    near(db.pedo.lastLevel, 20); near(db.pedo.level, 0); assert(db.pedo.levelNo == 31, "the level number")
    addon.PedometerFeed(0, 30, 1, true, 1)
    near(db.pedo.level, 10); near(db.pedo.total, 30)
end)

test("the unit follows the options", function()
    db.units = "yd"
    assert(addon.PedometerFormat(1234) == "1,234 yd", addon.PedometerFormat(1234))
    assert(addon.PedometerFormat(3520) == "2.00 miles", addon.PedometerFormat(3520))
    db.units = "m"
    assert(addon.PedometerFormat(100) == "91 m", addon.PedometerFormat(100))
    assert(addon.PedometerFormat(2000):find("km"), addon.PedometerFormat(2000))
    db.units = "steps"
    assert(addon.PedometerFormat(100):find("steps"), addon.PedometerFormat(100))
    db.units = "yd"
end)

test("the report names the numbers and the busiest zone", function()
    reset()
    addon.PedometerFeed(0, 0, 1, true, 100)
    addon.PedometerFeed(0, 25, 1, true, 100)
    addon:HandleExtraCommand("steps", "")
    assert(shown and shown.text:find("This session:"), "session line")
    assert(shown.text:find("Wetlands"), "zone name")
    assert(shown.text:find("25 yd"), "distance")
end)

test("off stops the counting and reset clears it", function()
    reset()
    addon:HandleExtraCommand("steps", "off")
    assert(db.pedometer == false)
    addon:HandleExtraCommand("steps", "on")
    assert(db.pedometer == nil)
    addon.PedometerFeed(0, 0, 1, true, 1); addon.PedometerFeed(0, 12, 1, true, 1)
    addon:HandleExtraCommand("steps", "reset")
    assert(db.pedo == nil, "reset clears the saved numbers")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end