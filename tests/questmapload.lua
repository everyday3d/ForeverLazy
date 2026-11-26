-- How much work the quest map does (no game needed): lua tests/questmapload.lua
-- A made-up hunting quest with many spots. It counts lookups and redraws; it cannot say how long they take in the game.
unpack = table.unpack
local now = 1000
GetTime = function() return now end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers() while #timers > 0 do table.remove(timers, 1)() end end
local onUpdate
local function Stub()
    local f = {}
    f.SetScript = function(_, what, fn) if what == "OnUpdate" then onUpdate = onUpdate or fn end end
    f.CreateTexture = function() return Stub() end
    return setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
end
CreateFrame = function() return Stub() end
UIParent = Stub()
UnitLevel = function() return 40 end

local pins, draws = {}, 0
local hbdp = {
    RemoveAllWorldMapIcons = function() draws = draws + 1; pins = {} end,
    RemoveAllMinimapIcons = function() end,
    AddWorldMapIconMap = function(_, _, f) pins[#pins + 1] = f end,
    AddMinimapIconMap = function() end,
}
LibStub = function() return hbdp end
local at = { 0, 0, 1 }
local hbd = { GetPlayerWorldPosition = function() return at[1], at[2], at[3] end, GetPlayerZone = function() return 10 end }

C_QuestLog = {
    GetNumQuestLogEntries = function() return 1 end,
    GetInfo = function() return { questID = 1, title = "The Hunt", level = 35 } end,
    IsComplete = function() return false end,
    GetQuestObjectives = function() return { { text = "Fang: 0/10" } } end,
}
local droppers = {}
for i = 1, 40 do droppers[i] = 100 + i end
local lookups = 0
local data = { Field = function(store, id, key)
    lookups = lookups + 1
    if store == "quests" and key == "objectives" then return { nil, nil, { { 500 } } } end
    if store == "quests" and key == "questLevel" then return 35 end
    if store == "items" and key == "npcDrops" then return droppers end
    if store == "items" and key == "name" then return "Fang" end
    if store == "npcs" and key == "minLevel" then return 34 end
    if store == "npcs" and key == "maxLevel" then return 36 end
end }
local api = { hbd = hbd, AddNpcs = function(list)
    for i = 1, 400 do list[#list + 1] = { uiMapId = 10, zx = (i % 20) / 20, zy = math.floor(i / 20) / 25, x = i * 5, y = 0, instance = 1 } end
end }
local db = { waypoints = {} }
local addon = { GetDB = function() return db end, Print = function() end }
assert(loadfile("ForeverLazy/QuestMap.lua"))("ForeverLazy", { L = function(s) return s end, addon = addon, api = api, data = data })

local passed, failed = 0, 0
local function test(label, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. label) else failed = failed + 1; print("FAIL  " .. label .. "\n      " .. tostring(err)) end
end

test("the tooltip words are worked out once for an objective, not once for every spot", function()
    addon.QuestMapRefresh(); RunTimers()
    assert(#pins > 20, "too few spots drawn: " .. #pins)
    assert(lookups < 150, "lookups: " .. lookups)
    local info = table.concat(pins[1].info, " / ")
    assert(info == "The Hunt / Quest level 35 / Mob levels 34-36 / Fang: 0/10", info)
end)
local function Tick() onUpdate(nil, 15); RunTimers() end
test("standing still does not draw it all again every 15 seconds", function()
    local before = draws
    now = now + 15; Tick()
    now = now + 15; at[1] = 40; Tick()
    assert(draws == before, "redrew without moving")
end)
test("moving on, or a minute passing, draws it again", function()
    local before = draws
    at[1] = 200; now = now + 5; Tick()
    assert(draws == before + 1, "no redraw after moving")
    now = now + 61; Tick()
    assert(draws == before + 2, "no redraw after a minute")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
