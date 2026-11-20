-- New zones for the levelling guide and the coach.
-- The zone list in NextZone.lua is the classic one, written by hand. This file looks at the quest data for zones that are NOT in
-- that list (zones this server added) and adds them: their level range from the levels of their quests, their quest hub from where
-- those quests start. It then adds them to the same list, so the journey, the coach and /lazy nextzone use them.
--   /lazy zones     what it found
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local data = ns.data
local DS = ns.dataset
local Print = addon.Print

local found = {}                 -- the zones added: { name, from, to, mapId }
local foundDungeons = {}        -- the dungeons given a level range: { name, from, to }
local extraMaps = {}            -- zone name -> map id
api.ExtraZoneMaps = extraMaps

local function Percentile(sorted, p)
    local n = #sorted
    if n == 0 then return nil end
    return sorted[math.max(1, math.min(n, math.floor(n * p + 0.5)))]
end

local function Scan(index)
    local NZ = api.NextZone
    if not (NZ and NZ.zones and DS.zones and DS.zones.areaToMap) then return end
    local known = {}
    for _, z in ipairs(NZ.zones) do known[z[1]] = true end

    -- the quests of each map (sub-areas fold into the zone they are in)
    local byMap = {}
    for _, e in ipairs(index) do
        if e.mine and e.zone and e.zone > 0 and e.level and e.level > 0 then
            local mapId = DS.zones.areaToMap[e.zone]
            if mapId then
                local m = byMap[mapId]
                if not m then m = { levels = {}, ids = {} }; byMap[mapId] = m end
                m.levels[#m.levels + 1] = e.level
                m.ids[#m.ids + 1] = e.id
            end
        end
    end

    -- dungeons this server added: the classic level table only knows the old ones, so work the range out from the dungeon's quests
    local lv = api.DungeonLevels
    local dg = DS.zones.dungeons
    if type(lv) == "table" and type(dg) == "table" then
        local nameOfArea = {}
        for areaId, e in pairs(dg) do
            if type(e) == "table" and e[1] then
                nameOfArea[areaId] = e[1]
                if type(e[2]) == "table" then for _, alt in ipairs(e[2]) do nameOfArea[alt] = nameOfArea[alt] or e[1] end end
            end
        end
        local levels = {}
        for _, e in ipairs(index) do
            local nm = e.zone and nameOfArea[e.zone]
            if nm and e.level and e.level > 0 and not lv[nm] then
                levels[nm] = levels[nm] or {}
                table.insert(levels[nm], e.level)
            end
        end
        for nm, list in pairs(levels) do
            if #list >= 3 then
                table.sort(list)
                local from, to = Percentile(list, 0.10), Percentile(list, 0.90)
                if from and to then
                    lv[nm] = { math.max(1, from - 2), to + 3 }
                    foundDungeons[#foundDungeons + 1] = { name = nm, from = lv[nm][1], to = lv[nm][2] }
                end
            end
        end
    end

    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local todo = {}
    for mapId, m in pairs(byMap) do
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
        if info and info.mapType == zoneType and info.name and not known[info.name] and #m.levels >= 15 then
            todo[#todo + 1] = { mapId = mapId, name = info.name, m = m }
        end
    end

    -- the hub of a zone: the middle of where its quests start (a few at a time, so the game does not stutter)
    local pos = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        local stop = math.min(#todo, pos + 2)
        while pos < stop do
            pos = pos + 1
            local z = todo[pos]
            table.sort(z.m.levels)
            local from, to = Percentile(z.m.levels, 0.10), Percentile(z.m.levels, 0.90)
            local sx, sy, n = 0, 0, 0
            for i, id in ipairs(z.m.ids) do
                if i > 60 then break end
                local by = data.Field("quests", id, "startedBy")
                if type(by) == "table" and api.AddNpcs then
                    local list = {}
                    pcall(api.AddNpcs, list, by[1])
                    for _, s in ipairs(list) do
                        if s.uiMapId == z.mapId then sx, sy, n = sx + s.zx, sy + s.zy, n + 1; break end
                    end
                end
            end
            if from and to and n >= 3 and to > from then
                local hub = { math.floor(sx / n * 100 + 0.5), math.floor(sy / n * 100 + 0.5) }
                local entry = { z.name, from, to, A = hub, H = hub }
                if from <= 4 then entry.start = true end
                table.insert(NZ.zones, entry)
                extraMaps[z.name] = z.mapId
                found[#found + 1] = { name = z.name, from = from, to = to, mapId = z.mapId, start = entry.start }
            end
        end
        if pos >= #todo then self:SetScript("OnUpdate", nil) end
    end)
end

-- a map id for any zone name: the ones found here first, then the classic lookup
do
    local NZ = api.NextZone
    if NZ and NZ.mapId then
        local original = NZ.mapId
        NZ.mapId = function(name)
            if extraMaps[name] then return extraMaps[name] end
            return original(name)
        end
    end
end

-- start once the quest list has been read
local acc, started = 0, false
local ev = CreateFrame("Frame")
ev:SetScript("OnUpdate", function(self, dt)
    acc = acc + dt
    if acc < 3 then return end
    acc = 0
    if started or not addon.QuestIndex then return end
    local index, done = addon.QuestIndex()
    if done and #index > 0 then
        started = true
        self:SetScript("OnUpdate", nil)
        pcall(Scan, index)
    end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "zones" then
        local lines = { "zones added from the quest data (not in the classic list): " .. #found }
        for _, z in ipairs(found) do
            lines[#lines + 1] = string.format("  %s: levels %d-%d%s", z.name, z.from, z.to, z.start and " (a starting zone)" or "")
        end
        if #found == 0 then lines[#lines + 1] = "  none found (or the quest list is still being read, try again in a minute)" end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "dungeons given a level range from their quests (not in the classic table): " .. #foundDungeons
        for _, d in ipairs(foundDungeons) do lines[#lines + 1] = string.format("  %s: levels %d-%d", d.name, d.from, d.to) end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Rebuild the levelling guide (the Rebuild button) to use them."
        if addon.ReportWindow then addon.ReportWindow("New zones", lines) else for _, l in ipairs(lines) do Print(l) end end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["NewZones.lua"] = true end end
