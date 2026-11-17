-- The journey: which zones to level in, in order, from your level up to 60, with the dungeons that fit on the way.
-- It is made once and kept for each character, so it is the same plan from day to day. Rebuild it any time.
--   /lazy journey                 show it (makes it the first time)
--   /lazy journey generate        make it
--   /lazy journey regenerate      throw it away and make it again from my level now
--   /lazy journey go [n]          waypoint on the quest hub of that stop
-- The level ranges are rough (from community guides), so treat it as a good guide rather than a rule.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end
local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

--------------------------------------------------------------------------------
-- Working the journey out
--------------------------------------------------------------------------------
local function Build()
    local NZ = api.NextZone
    if not (NZ and NZ.zones) then return nil end
    local faction = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
    local level = UnitLevel("player") or 1
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local prev = px and { x = px, y = py, instance = pinst } or nil
    local withDungeons = DB().journeyDungeons ~= false

    local used, out = {}, {}

    local function hubFor(z)
        local hub = z[faction]
        if not hub then return nil end
        local mapId = NZ.mapId(z[1])
        if not mapId then return nil end
        local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(hub[1] / 100, hub[2] / 100, mapId)
        if not wx then return nil end
        return { x = wx, y = wy, instance = inst, mapId = mapId, zx = hub[1] / 100, zy = hub[2] / 100 }
    end

    local L = level
    -- the zone I am standing in comes first while it still has levels in it
    local zoneId = hbd:GetPlayerZone()
    local info = zoneId and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zoneId)
    if info then
        for _, z in ipairs(NZ.zones) do
            if z[1] == info.name and L < z[3] and L >= z[2] - 2 then
                used[z[1]] = true
                local hub = hubFor(z)
                out[#out + 1] = { zone = z[1], from = L, to = z[3], hub = hub }
                L = z[3]
                if hub then prev = hub end
            end
        end
    end

    while L < 60 and #out < 12 do
        local best, bestScore, bestHub
        for _, z in ipairs(NZ.zones) do
            if not z.start and not used[z[1]] and z[2] <= L + 2 and z[3] > L then
                local hub = hubFor(z)
                if hub then
                    local score = math.abs(L - (z[2] + z[3]) / 2)
                    if prev and prev.instance == hub.instance then score = score + Dist(prev, hub) / 800 else score = score + 4 end
                    if not bestScore or score < bestScore then best, bestScore, bestHub = z, score, hub end
                end
            end
        end
        if not best then break end
        used[best[1]] = true
        out[#out + 1] = { zone = best[1], from = math.max(L, best[2]), to = math.min(best[3], 60), hub = bestHub }
        if best[3] <= L then break end
        L = best[3]
        prev = bestHub
    end

    -- dungeons that fit each stretch
    local lv = api.DungeonLevels or {}
    for _, seg in ipairs(out) do
        local names = {}
        if withDungeons then
            for name, r in pairs(lv) do
                if r[1] <= seg.to and r[2] >= seg.from and r[1] >= seg.from - 6 then names[#names + 1] = name end
            end
            table.sort(names, function(a, b) return lv[a][1] < lv[b][1] end)
        end
        seg.dungeons = names
    end
    return out
end

--------------------------------------------------------------------------------
-- Keeping it (per character)
--------------------------------------------------------------------------------
local function Key() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end

local function Saved()
    local root = addon.GetRoot()
    root.journeys = root.journeys or {}
    return root.journeys[Key()]
end

local function Save(segs)
    local root = addon.GetRoot()
    root.journeys = root.journeys or {}
    local store = {}
    for i, s in ipairs(segs) do
        store[i] = { zone = s.zone, from = s.from, to = s.to, dungeons = s.dungeons,
                     map = s.hub and s.hub.mapId, zx = s.hub and s.hub.zx, zy = s.hub and s.hub.zy }
    end
    root.journeys[Key()] = { level = UnitLevel("player"), segs = store }
end

local function Segments()
    local j = Saved()
    return j and j.segs or nil
end

local function Status(seg, level)
    if level >= seg.to then return "done" end
    if level >= seg.from then return "now" end
    return "next"
end

local function Show()
    local segs = Segments()
    if not segs or #segs == 0 then Print("you have no journey yet: /lazy journey generate"); return end
    local level = UnitLevel("player") or 1
    Print("your journey (made at level " .. tostring(Saved().level or "?") .. "):")
    for i, s in ipairs(segs) do
        local st = Status(s, level)
        local mark = st == "done" and "|cff888888done|r" or (st == "now" and "|cff55ff55<- you are here|r" or "")
        local d = ""
        if s.dungeons and #s.dungeons > 0 then
            d = "  |cffaaaaaa(dungeons: " .. table.concat(s.dungeons, ", ", 1, math.min(#s.dungeons, 3)) .. ")|r"
        end
        Print(string.format("  %d. level %d-%d: %s  %s%s", i, s.from, s.to, s.zone, mark, d))
    end
    Print("/lazy journey go 2 puts a waypoint on the quest hub of stop 2")
end

local function Generate(force)
    if Saved() and not force then
        Print("you already have a journey. /lazy journey shows it, /lazy journey regenerate makes a new one from your level now.")
        return
    end
    local segs = Build()
    if not segs or #segs == 0 then
        Print("I could not make a journey from level " .. tostring(UnitLevel("player")) .. ", the zone data is not ready yet")
        return
    end
    Save(segs)
    Print(force and "journey rebuilt from your level now" or "journey made")
    Show()
end

function addon.JourneyGenerate() Generate(false) end
function addon.JourneyRegenerate() Generate(true) end
function addon.JourneyShow() if Saved() then Show() else Generate(false) end end

-- used by Lazy Mode: the stretch I should be in now (made if I have none yet)
function addon.JourneyNext()
    if not Segments() then
        local segs = Build()
        if not segs or #segs == 0 then return nil end
        Save(segs)
    end
    local level = UnitLevel("player") or 1
    for _, s in ipairs(Segments() or {}) do
        if level < s.to and s.map then return s end
    end
end

local function Go(n)
    local segs = Segments()
    if not segs then Print("no journey yet: /lazy journey generate"); return end
    local s = segs[tonumber(n) or 1]
    if not (s and s.map) then Print("no such stop, try /lazy journey first"); return end
    addon:AddWaypointZone(s.map, s.zx, s.zy, string.format("%s (level %d-%d)", s.zone, s.from, s.to))
end

--------------------------------------------------------------------------------
-- A word when a stretch is finished
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, _, newLevel)
    local db = DB()
    if not db or db.journeyHint == false or not addon.ModuleOn("zones") then return end
    local segs = Segments()
    local level = tonumber(newLevel)
    if not segs or not level then return end
    for i, s in ipairs(segs) do
        if level == s.to then
            local nxt = segs[i + 1]
            if nxt then
                Print(string.format("journey: you have outgrown %s. Next: %s (level %d-%d). /lazy journey go %d", s.zone, nxt.zone, nxt.from, nxt.to, i + 1))
            else
                Print("journey: you have reached the end of it, nice. /lazy journey regenerate plans the rest")
            end
            return
        end
    end
    local last = segs[#segs]
    if last and level > last.to and level < 60 then
        Print("journey: you are past the end of it. /lazy journey regenerate makes a new one from your level.")
    end
end)

local prevHandler = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "journey" then
        local arg = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local n = arg:match("^go%s*(%d*)")
        if n ~= nil then
            Go(n)
        elseif arg == "generate" or arg == "make" or arg == "new" then
            Generate(false)
        elseif arg == "regenerate" or arg == "rebuild" or arg == "redo" then
            Generate(true)
        else
            addon.JourneyShow()
        end
        return true
    end
    if prevHandler then return prevHandler(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Journey.lua"] = true end end
