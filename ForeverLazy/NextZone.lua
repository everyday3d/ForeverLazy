-- Next zone suggestion: when you have outgrown the zone you are in, it suggests where to go for your level.
--   /lazy nextzone        list the best zones for your level now
--   /lazy nextzone go [n] put a waypoint on suggestion n (default 1)
-- The level ranges and quest hub positions are from memory, so treat them as a guide.
local ADDON, ns = ...
local addon = ns.addon
local Print = addon.Print
local api = ns.api
local hbd = api.hbd

local function DB() return addon.GetDB() end

-- name, lowest level, highest level, quest hub (percent of the zone map) for Alliance / Horde
-- start = a race's first zone: never suggested, only used to notice that you have outgrown it
local ZONES = {
    { "Elwynn Forest", 1, 10, start = true }, { "Dun Morogh", 1, 10, start = true },
    { "Teldrassil", 1, 10, start = true }, { "Mulgore", 1, 10, start = true },
    { "Durotar", 1, 10, start = true }, { "Tirisfal Glades", 1, 10, start = true },
    { "Loch Modan", 10, 20, A = { 35, 48 } },
    { "Westfall", 10, 20, A = { 56, 47 } },
    { "Darkshore", 10, 20, A = { 37, 44 } },
    { "Silverpine Forest", 10, 20, H = { 45, 41 } },
    { "The Barrens", 10, 25, H = { 52, 31 } },
    { "Redridge Mountains", 15, 25, A = { 26, 46 } },
    { "Duskwood", 18, 30, A = { 74, 44 } },
    { "Ashenvale", 18, 30, A = { 36, 50 }, H = { 73, 61 } },
    { "Wetlands", 20, 30, A = { 10, 60 } },
    { "Hillsbrad Foothills", 20, 30, A = { 50, 59 }, H = { 62, 21 } },
    { "Stonetalon Mountains", 20, 30, A = { 47, 62 }, H = { 47, 62 } },
    { "Thousand Needles", 25, 35, A = { 46, 51 }, H = { 46, 51 } },
    { "Arathi Highlands", 30, 40, A = { 46, 47 }, H = { 73, 34 } },
    { "Desolace", 30, 40, A = { 66, 7 }, H = { 25, 68 } },
    { "Stranglethorn Vale", 30, 45, A = { 27, 77 }, H = { 27, 77 } },
    { "Badlands", 35, 45, H = { 3, 47 } },
    { "Swamp of Sorrows", 35, 45, H = { 45, 53 } },
    { "Dustwallow Marsh", 35, 45, A = { 66, 49 }, H = { 36, 31 } },
    { "Tanaris", 40, 50, A = { 52, 29 }, H = { 52, 29 } },
    { "Feralas", 40, 50, A = { 31, 43 }, H = { 75, 43 } },
    { "The Hinterlands", 40, 50, A = { 12, 46 }, H = { 78, 81 } },
    { "Searing Gorge", 43, 50, A = { 38, 28 }, H = { 38, 28 } },
    { "Azshara", 45, 55, A = { 11, 77 }, H = { 22, 52 } },
    { "Blasted Lands", 45, 55, A = { 66, 19 } },
    { "Un'Goro Crater", 48, 55, A = { 43, 8 }, H = { 43, 8 } },
    { "Felwood", 48, 55, A = { 51, 82 }, H = { 51, 82 } },
    { "Burning Steppes", 50, 58, A = { 84, 69 }, H = { 65, 24 } },
    { "Western Plaguelands", 51, 58, A = { 43, 84 }, H = { 43, 84 } },
    { "Winterspring", 53, 60, A = { 61, 39 }, H = { 61, 39 } },
    { "Eastern Plaguelands", 53, 60, A = { 81, 58 }, H = { 81, 58 } },
    { "Silithus", 55, 60, A = { 50, 35 }, H = { 50, 35 } },
}
local BY_NAME = {}
for _, z in ipairs(ZONES) do BY_NAME[z[1]] = z end

local mapCache = {}
local function MapId(name)
    if mapCache[name] ~= nil then return mapCache[name] or nil end
    local found
    if C_Map and C_Map.GetMapInfo then
        for id = 1400, 1500 do
            local info = C_Map.GetMapInfo(id)
            if info and info.name == name then found = id; break end
        end
    end
    mapCache[name] = found or false
    return found
end

local function CurrentZoneName()
    local id = hbd:GetPlayerZone()
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name, id
end

local suggestions = {}

-- the best zones for this level, nearest and best matched first
local function Suggest(level, here)
    local faction = UnitFactionGroup and UnitFactionGroup("player") == "Horde" and "H" or "A"
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local list = {}
    for _, z in ipairs(ZONES) do
        local hub = z[faction]
        if hub and not z.start and z[1] ~= here and z[2] <= level + 2 and z[3] >= level then
            local mapId = MapId(z[1])
            if mapId then
                local zx, zy = hub[1] / 100, hub[2] / 100
                local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(zx, zy, mapId)
                if wx then
                    local score = math.abs(level - (z[2] + z[3]) / 2)
                    local far
                    if px and inst == pinst then
                        far = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
                        score = score + far / 500
                    else
                        score = score + 8
                    end
                    list[#list + 1] = { zone = z, score = score, mapId = mapId, zx = zx, zy = zy,
                                        far = far, otherContinent = not (px and inst == pinst) }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.score < b.score end)
    for i = #list, 4, -1 do list[i] = nil end
    return list
end

local function Describe(i, s)
    local where = s.otherContinent and "other continent" or string.format("about %d yards", s.far or 0)
    return string.format("  %d. %s (level %d-%d), %s", i, s.zone[1], s.zone[2], s.zone[3], where)
end

local function Show(level, header)
    local here = CurrentZoneName()
    suggestions = Suggest(level, here)
    if #suggestions == 0 then
        Print("no zone suggestions for your level")
        return
    end
    Print(header)
    for i, s in ipairs(suggestions) do Print(Describe(i, s)) end
    Print("/lazy nextzone go  puts a waypoint on the first one")
end

local lastHint
local function Check(level)
    local db = DB()
    if not db or db.nextZoneHint == false or not addon.ModuleOn("zones") then return end
    level = level or UnitLevel("player")
    local name = CurrentZoneName()
    local z = name and BY_NAME[name]
    if not z or level < z[3] then return end                 -- unknown zone, or still room to level here
    local key = name .. level
    if lastHint == key then return end
    lastHint = key
    Show(level, string.format("you have outgrown %s (level %d-%d). Good zones for level %d:", name, z[2], z[3], level))
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LEVEL_UP")
pcall(ev.RegisterEvent, ev, "QUEST_TURNED_IN")
ev:SetScript("OnEvent", function(_, event, newLevel)
    local level = event == "PLAYER_LEVEL_UP" and tonumber(newLevel) or nil
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function() pcall(Check, level) end)
    end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd == "nextzone" then
        rest = (rest or ""):lower()
        local go = rest:match("^go%s*(%d*)$")
        if go then
            if #suggestions == 0 then suggestions = Suggest(UnitLevel("player"), (CurrentZoneName())) end
            local s = suggestions[tonumber(go) or 1]
            if not s then Print("no such suggestion, try /lazy nextzone first"); return true end
            DB().waypoints = {}
            addon:AddWaypointZone(s.mapId, s.zx, s.zy, s.zone[1] .. " (level " .. s.zone[2] .. "-" .. s.zone[3] .. ")")
        else
            Show(UnitLevel("player"), "good zones for level " .. UnitLevel("player") .. ":")
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- used by the journey planner
api.NextZone = { zones = ZONES, mapId = MapId }

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["NextZone.lua"] = true end end
