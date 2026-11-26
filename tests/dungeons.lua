-- Dungeon entrances (no game needed): lua tests/dungeons.lua
local function Frame() return setmetatable({}, { __index = function() return function() return Frame() end end }) end
CreateFrame = function() return Frame() end
UIParent, UISpecialFrames, SlashCmdList, GameTooltip = Frame(), {}, {}, Frame()
tinsert = table.insert
local addon = { GetDB = function() return {} end, Print = function() end, ModuleOn = function() return true end, RegisterComm = function() end }
-- the world position is made from the map and the spot, so a test can see which entrance was used
local hbd = { GetWorldCoordinatesFromZone = function(_, x, y, map) return map + x, y, map == 1434 and 0 or 1 end,
    GetPlayerWorldPosition = function() return nil end }
local ns = { L = function(s) return s end, addon = addon, api = { hbd = hbd }, dataset = {}, data = {} }
assert(loadfile("ForeverLazy/data/Zones.lua"))("ForeverLazy", ns)
local zones = ns.dataset.zones
ns.data.Module = function(name)
    if name ~= "ZoneDB" then return nil end
    return { GetDungeons = function() return zones.dungeons end, GetUiMapIdByAreaId = function(_, a) return (zones.areaToMap or {})[a] or a end }
end
assert(loadfile("ForeverLazy/Dungeons.lua"))("ForeverLazy", ns)
local api = ns.api

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

test("each of the five from OpenMap has its entrance", function()
    for _, d in ipairs({ { "Alcaz Prison", 1445.753 }, { "Blackmaw Hold", 1447.386 }, { "The Drowned City", 1434.213 },
        { "Krol'dok Stronghold", 2548.375 }, { "Shaper's Terrace", 1449.481 } }) do
        local inst, x, _, label = api.DungeonEntrance(d[1])
        assert(inst, "no entrance: " .. d[1])
        assert(math.abs(x - d[2]) < 0.0001, d[1] .. " is at " .. tostring(x))
        assert(label:find("entrance"))
        assert(api.DungeonLevels[d[1]], "no level range: " .. d[1])
    end
end)
test("the names without 'The' work too", function()
    assert(api.DungeonEntrance("Drowned City"))
end)
test("Sunken Temple and Ahn'Qiraj Temple find the ones we already have", function()
    local _, a = api.DungeonEntrance("Sunken Temple")
    local _, b = api.DungeonEntrance("The Temple of Atal'Hakkar")
    assert(a and a == b, "sunken temple: " .. tostring(a) .. " / " .. tostring(b))
    local _, c = api.DungeonEntrance("Ahn'Qiraj Temple")
    local _, d = api.DungeonEntrance("Temple of Ahn'Qiraj")
    assert(c and c == d)
end)
test("an old dungeon is still found, and a made-up one is not", function()
    assert(api.DungeonEntrance("The Deadmines"))
    assert(api.DungeonEntrance("Cave of Nothing") == nil)
end)

test("the name the game shows in the Stockade finds its entrance", function()
    local _, a = api.DungeonEntrance("Stormwind Stockade")
    local _, b = api.DungeonEntrance("The Stockade")
    assert(a and a == b, "stockade: " .. tostring(a) .. " / " .. tostring(b))
end)
-- every dungeon and wing name OpenMap lists (Data\Forever\Places.lua, version 0.8.13)
local OPENMAP_NAMES = { "Shadowfang Keep", "Stormwind Stockade", "Deadmines", "Wailing Caverns", "Razorfen Kraul", "Blackfathom Deeps", "Uldaman", "Gnomeregan", "Sunken Temple", "Razorfen Downs", "Scarlet Monastery - Graveyard", "Scarlet Monastery - Library", "Scarlet Monastery - Armory", "Scarlet Monastery - Cathedral", "Zul'Farrak", "Lower Blackrock Spire", "Upper Blackrock Spire", "Molten Core", "Blackwing Lair", "Blackrock Depths", "Onyxia's Lair", "Scholomance", "Zul'Gurub", "Stratholme", "Maraudon", "Ragefire Chasm", "Dire Maul - East", "Dire Maul - West", "Dire Maul - North", "Ruins of Ahn'Qiraj", "Ahn'Qiraj Temple", "City of Dalaran", "The Drowned City", "Blackmaw Hold", "Alcaz Prison", "Excavation Site: Wetlands", "Ruins of Lordaeron", "Shaper's Terrace", "Krol'dok Stronghold", "The Hall of Thanes" }
test("every name OpenMap uses finds an entrance", function()
    local missing = {}
    for _, n in ipairs(OPENMAP_NAMES) do if not api.DungeonEntrance(n) then missing[#missing + 1] = n end end
    assert(#missing == 0, table.concat(missing, ", "))
    assert(#OPENMAP_NAMES >= 40)
end)
test("dungeons are shown with OpenMap's names, and the old names still work", function()
    for _, p in ipairs({ { "The Deadmines", "Deadmines" }, { "The Stockade", "Stormwind Stockade" },
        { "The Temple of Atal'Hakkar", "Sunken Temple" }, { "Temple of Ahn'Qiraj", "Ahn'Qiraj Temple" } }) do
        local _, _, _, label = api.DungeonEntrance(p[1])
        assert(label == "Your corpse (" .. p[2] .. " entrance)", p[1] .. " shows as " .. tostring(label))
        assert(not api.DungeonLevels[p[1]] or p[1] == p[2], "old name still in the level list: " .. p[1])
    end
    for _, n in ipairs({ "Deadmines", "Stormwind Stockade", "Sunken Temple" }) do assert(api.DungeonLevels[n], "no levels: " .. n) end
end)
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
