-- Finding my body, and the dungeon entrance when I died inside (no game needed): lua tests/corpse.lua
-- The corpse code is taken out of Extras.lua as it stands and run against a pretend game.
local src = io.open("ForeverLazy/Extras.lua", "rb"):read("a"):gsub("\r\n", "\n")
local a = assert(src:find("local deathFrame = CreateFrame", 1, true))
local b = assert(src:find("function addon.CompassCorpse", a, true))
local chunk = "local CreateFrame, hbd, DB, api, addon = ...\n" .. src:sub(a, b - 1) .. "\nreturn CorpsePoint"

local handler
local frame = { RegisterEvent = function() end, SetScript = function(_, _, fn) handler = fn end }
local inside, kind, position, named = false, "none", { 50, 60, 1 }, nil
IsInInstance = function() return inside, kind end
GetInstanceInfo = function() return "The Deadmines" end
local hbd = { GetPlayerWorldPosition = function() if position then return table.unpack(position) end end, GetPlayerZone = function() return 1 end }
local db = {}
local api = { DungeonEntrance = function(name) if name == "The Deadmines" then return 1, 500, 600, "Your corpse (The Deadmines entrance)" end end }
local addon = { CurrentDungeon = function() return named end }
local CorpsePoint = assert(load(chunk))(function() return frame end, hbd, function() return db end, api, addon)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function Die(ins, k, pos, byName) inside, kind, position, named = ins, k, pos, byName; handler(); inside, kind = false, "none"; position = { 0, 0, 1 } end

test("died outside: the body is where I fell", function()
    Die(false, "none", { 50, 60, 1 })
    local i, x, y = CorpsePoint()
    assert(i == 1 and x == 50 and y == 60)
end)
test("died in a dungeon: the way to its entrance", function()
    Die(true, "party", nil)
    local _, x, _, label = CorpsePoint()
    assert(x == 500 and label:find("entrance"))
end)
test("a dungeon that does not say it is one is found by its name", function()
    Die(false, "none", nil, "The Deadmines")
    local _, x = CorpsePoint()
    assert(x == 500)
end)
test("in the cave outside, with a position, the zone's name is not trusted", function()
    Die(false, "none", { 70, 80, 1 }, "The Deadmines")
    local _, x = CorpsePoint()
    assert(x == 70, tostring(x))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
