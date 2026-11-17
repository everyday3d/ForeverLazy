-- Flight master positions in WoW Forever: name, zone, and the position on the zone map in percent.
-- Source: the community flight path guide on wowforever.be (read from the live game files, build 1.60.1.70862).
-- With this the addon knows where every flight point is, so it only has to learn which ones you have opened.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api

local DATA = {
    A = {
        -- Eastern Kingdoms
        { "Aerie Peak", "The Hinterlands", 11.0, 46.0 }, { "Booty Bay", "Stranglethorn Vale", 27.4, 77.8 },
        { "Chillwind Camp", "Western Plaguelands", 42.8, 85.0 }, { "Darkshire", "Duskwood", 77.4, 44.4 },
        { "Farholde Keep", "The Riverglades", 60.6, 81.4 }, { "Ironforge", "Ironforge", 55.8, 48.0 },
        { "Lakeshire", "Redridge Mountains", 30.6, 59.4 }, { "Light's Hope Chapel", "Eastern Plaguelands", 81.6, 59.2 },
        { "Menethil Harbor", "Wetlands", 9.4, 59.6 }, { "Morgan's Vigil", "Burning Steppes", 84.4, 68.2 },
        { "Nethergarde Keep", "Blasted Lands", 65.4, 24.4 }, { "Refuge Pointe", "Arathi Highlands", 45.6, 46.0 },
        { "Sentinel Hill", "Westfall", 56.4, 52.6 }, { "Southshore", "Hillsbrad Foothills", 49.4, 52.2 },
        { "Stormwind", "Stormwind City", 66.2, 62.4 }, { "Thelsamar", "Loch Modan", 33.8, 50.8 },
        { "Thorium Point", "Searing Gorge", 37.8, 30.6 },
        -- Kalimdor
        { "Astranaar", "Ashenvale", 34.4, 48.0 }, { "Auberdine", "Darkshore", 36.4, 45.6 },
        { "Cenarion Hold", "Silithus", 50.6, 34.4 }, { "Everlook", "Winterspring", 62.2, 36.6 },
        { "Feathermoon", "Feralas", 30.2, 43.2 }, { "Gadgetzan", "Tanaris", 51.0, 29.2 },
        { "Marshal's Refuge", "Un'Goro Crater", 45.2, 5.8 }, { "Moonglade", "Moonglade", 48.0, 67.2 },
        { "Nijel's Point", "Desolace", 64.6, 10.4 }, { "Ratchet", "The Barrens", 63.0, 37.2 },
        { "Rut'theran Village", "Teldrassil", 58.4, 94.0 }, { "Stonetalon Peak", "Stonetalon Mountains", 36.4, 7.2 },
        { "Summit of Eternity", "Mount Hyjal", 68.6, 44.0 }, { "Tainted Foothills", "Mount Hyjal", 55.0, 82.8 },
        { "Talonbranch Glade", "Felwood", 62.4, 24.2 }, { "Talrendis Point", "Azshara", 11.8, 77.4 },
        { "Thalanaar", "Feralas", 89.4, 45.8 }, { "Theramore", "Dustwallow Marsh", 67.4, 51.2 },
    },
    H = {
        -- Eastern Kingdoms
        { "Booty Bay", "Stranglethorn Vale", 26.8, 77.0 }, { "Flame Crest", "Burning Steppes", 65.6, 24.2 },
        { "Grom'gol", "Stranglethorn Vale", 32.4, 29.2 }, { "Hammerfall", "Arathi Highlands", 73.0, 32.6 },
        { "Kargath", "Badlands", 4.0, 44.8 }, { "Light's Hope Chapel", "Eastern Plaguelands", 80.2, 57.0 },
        { "Revantusk Village", "The Hinterlands", 81.6, 81.8 }, { "Rog'mar", "The Riverglades", 59.6, 45.2 },
        { "Stonard", "Swamp of Sorrows", 46.0, 54.6 }, { "Tarren Mill", "Hillsbrad Foothills", 60.2, 18.6 },
        { "The Sepulcher", "Silverpine Forest", 45.6, 42.4 }, { "Thorium Point", "Searing Gorge", 34.8, 30.8 },
        { "Undercity", "Undercity", 63.4, 48.6 },
        -- Kalimdor
        { "Bloodvenom Post", "Felwood", 34.4, 53.8 }, { "Brackenwall Village", "Dustwallow Marsh", 35.6, 31.8 },
        { "Camp Mojache", "Feralas", 75.4, 44.2 }, { "Camp Taurajo", "The Barrens", 44.4, 59.0 },
        { "Cenarion Hold", "Silithus", 48.8, 36.6 }, { "Crossroads", "The Barrens", 51.4, 30.2 },
        { "Everlook", "Winterspring", 60.4, 36.4 }, { "Freewind Post", "Thousand Needles", 45.0, 49.2 },
        { "Gadgetzan", "Tanaris", 51.6, 25.4 }, { "Marshal's Refuge", "Un'Goro Crater", 45.2, 5.8 },
        { "Moonglade", "Moonglade", 32.2, 66.4 }, { "Orgrimmar", "Orgrimmar", 45.2, 63.8 },
        { "Ratchet", "The Barrens", 63.0, 37.2 }, { "Shadowprey Village", "Desolace", 21.6, 74.0 },
        { "Splintertree Post", "Ashenvale", 73.2, 61.6 }, { "Summit of Eternity", "Mount Hyjal", 68.6, 44.0 },
        { "Sun Rock Retreat", "Stonetalon Mountains", 45.2, 59.8 }, { "Tainted Foothills", "Mount Hyjal", 55.0, 82.8 },
        { "Thunder Bluff", "Thunder Bluff", 46.8, 50.0 }, { "Valormok", "Azshara", 22.0, 49.6 },
        { "Zoram'gar Outpost", "Ashenvale", 12.2, 33.8 },
    },
}

local mapCache = {}
local function MapId(zone)
    if mapCache[zone] ~= nil then return mapCache[zone] or nil end
    local found
    if C_Map and C_Map.GetMapInfo then
        for id = 1400, 1600 do
            local info = C_Map.GetMapInfo(id)
            if info and info.name == zone then found = id; break end
        end
    end
    mapCache[zone] = found or false
    return found
end

-- every flight point for my faction, with its map and position (skips a zone whose map I cannot find)
function api.FlightData()
    local side = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
    local out = {}
    for _, r in ipairs(DATA[side]) do
        local map = MapId(r[2])
        if map then out[#out + 1] = { name = r[1], zone = r[2], map = map, zx = r[3] / 100, zy = r[4] / 100 } end
    end
    return out
end

-- one flight point by its name (before any comma), for my faction
function api.FlightPointByName(name)
    local short = (name or ""):match("^[^,]+") or name or ""
    for _, f in ipairs(api.FlightData()) do
        if f.name:lower() == short:lower() then return f end
    end
end
