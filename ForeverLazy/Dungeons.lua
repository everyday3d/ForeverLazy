-- Dungeons: which of your quests need a dungeon, where its entrance is, and which dungeons suit your level.
-- It also gives the corpse arrow the dungeon entrance after you die inside one (the corpse run).
--   /lrxp dungeons              quests that need a dungeon, and dungeons for your level
--   /lrxp dungeons go [n|name]  put a waypoint on a dungeon entrance
-- Dungeon names, entrances and quest locations come from Questie's database.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

-- level ranges (from Questie's meeting stones, a few from memory)
local LEVELS = {
    ["Ragefire Chasm"] = { 13, 18 }, ["The Deadmines"] = { 16, 24 }, ["Wailing Caverns"] = { 16, 24 },
    ["Shadowfang Keep"] = { 17, 25 }, ["Blackfathom Deeps"] = { 20, 28 }, ["The Stockade"] = { 22, 30 },
    ["Razorfen Kraul"] = { 23, 31 }, ["Gnomeregan"] = { 24, 32 }, ["Scarlet Monastery"] = { 28, 44 },
    ["Razorfen Downs"] = { 33, 41 }, ["Uldaman"] = { 36, 44 }, ["Maraudon"] = { 40, 52 },
    ["Zul'Farrak"] = { 42, 50 }, ["The Temple of Atal'Hakkar"] = { 45, 54 }, ["Blackrock Depths"] = { 48, 61 },
    ["Blackrock Spire"] = { 55, 61 }, ["Dire Maul"] = { 54, 61 }, ["Scholomance"] = { 56, 61 },
    ["Stratholme"] = { 56, 61 },
}

local function Zone()
    local ql = _G.QuestieLoader
    if not ql then return nil end
    local ok, m = pcall(ql.ImportModule, ql, "ZoneDB")
    return ok and m or nil
end

local function Key(name)
    local k = (name or ""):lower():gsub("^the%s+", "")
    return k
end

--------------------------------------------------------------------------------
-- The dungeon list, built from Questie's data the first time it is needed
--------------------------------------------------------------------------------
local byKey, areaTo
local function Build()
    if byKey then return true end
    local Z = Zone()
    local list = Z and Z.GetDungeons and Z:GetDungeons()
    if type(list) ~= "table" then return false end
    byKey, areaTo = {}, {}
    for areaId, e in pairs(list) do
        local name = e[1]
        local rec = byKey[Key(name)]
        if not rec then
            rec = { name = name, entrances = {}, levels = LEVELS[name] }
            byKey[Key(name)] = rec
        end
        areaTo[areaId] = rec
        if e[2] then for _, alt in ipairs(e[2]) do areaTo[alt] = areaTo[alt] or rec end end
        for _, loc in ipairs(e[4] or {}) do
            local uiMapId = Z:GetUiMapIdByAreaId(loc[1])
            if uiMapId then
                local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(loc[2] / 100, loc[3] / 100, uiMapId)
                if wx then
                    local dup
                    for _, o in ipairs(rec.entrances) do
                        if o.uiMapId == uiMapId and math.abs(o.zx - loc[2] / 100) < 0.005 and math.abs(o.zy - loc[3] / 100) < 0.005 then dup = true end
                    end
                    if not dup then
                        rec.entrances[#rec.entrances + 1] = { uiMapId = uiMapId, zx = loc[2] / 100, zy = loc[3] / 100,
                                                              instance = inst, x = wx, y = wy }
                    end
                end
            end
        end
    end
    return true
end

local function MapName(id)
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or "?"
end

-- the entrance closest to me (or the first one)
local function Nearest(rec)
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local best, bd
    for _, e in ipairs(rec.entrances) do
        local d = (px and e.instance == pinst) and math.sqrt((e.x - px) ^ 2 + (e.y - py) ^ 2) or nil
        if not best or (d and (not bd or d < bd)) then best, bd = e, d end
    end
    return best, bd
end

-- used by the corpse arrow: where to run to after dying in this dungeon
function api.DungeonEntrance(name)
    if not Build() then return nil end
    local rec = byKey[Key(name)]
    if not rec then return nil end
    local e = Nearest(rec)
    if not e then return nil end
    return e.instance, e.x, e.y, "Your corpse (" .. rec.name .. " entrance)"
end

--------------------------------------------------------------------------------
-- Which of my quests need a dungeon
--------------------------------------------------------------------------------
local function AddAreas(set, spawns)
    if type(spawns) == "table" then for areaId in pairs(spawns) do set[areaId] = true end end
end

local function QuestAreas(QDB, q)
    local set = {}
    local function npcs(ids) if type(ids) == "table" then for _, id in pairs(ids) do AddAreas(set, QDB.QueryNPCSingle(id, "spawns")) end end end
    local function objs(ids) if type(ids) == "table" then for _, id in pairs(ids) do AddAreas(set, QDB.QueryObjectSingle(id, "spawns")) end end end
    if q.complete then
        local by = QDB.QueryQuestSingle(q.id, "finishedBy")
        if by then npcs(by[1]); objs(by[2]) end
    else
        local obj = QDB.QueryQuestSingle(q.id, "objectives")
        if type(obj) == "table" then
            if obj[1] then for _, c in pairs(obj[1]) do if c[1] then npcs({ c[1] }) end end end
            if obj[2] then for _, c in pairs(obj[2]) do if c[1] then objs({ c[1] }) end end end
            if obj[3] then
                for _, c in pairs(obj[3]) do
                    if c[1] then
                        local n = 0
                        local drops = QDB.QueryItemSingle(c[1], "npcDrops")
                        if type(drops) == "table" then
                            for _, id in pairs(drops) do
                                n = n + 1
                                if n > 40 then break end
                                AddAreas(set, QDB.QueryNPCSingle(id, "spawns"))
                            end
                        end
                        objs(QDB.QueryItemSingle(c[1], "objectDrops"))
                    end
                end
            end
        end
        local te = QDB.QueryQuestSingle(q.id, "triggerEnd")
        if type(te) == "table" then AddAreas(set, te[2]) end
    end
    return set
end

-- list of { rec, quests = {titles} }, the dungeon with most quests first
local function DungeonQuests()
    local out = {}
    if not (Build() and api.QuestieReady and api.QuestieReady() and api.ReadQuestLog) then return out end
    local QDB = api.GetQuestie()
    local per = {}
    for _, q in ipairs(api.ReadQuestLog()) do
        local level = q.level
        if not level or level == 0 then level = QDB.QueryQuestSingle(q.id, "questLevel") end
        local grey = false
        if QDB.IsTrivial and level and level > 0 then
            local ok, r = pcall(QDB.IsTrivial, level)
            grey = ok and r and true or false
        end
        if not grey then
            local inRec, outside
            for areaId in pairs(QuestAreas(QDB, q)) do
                local rec = areaTo[areaId]
                if rec then inRec = inRec or rec else outside = true end
            end
            if inRec and not outside then            -- only doable inside the dungeon
                per[inRec] = per[inRec] or { rec = inRec, quests = {} }
                table.insert(per[inRec].quests, q.title)
            end
        end
    end
    for _, v in pairs(per) do out[#out + 1] = v end
    table.sort(out, function(a, b) return #a.quests > #b.quests end)
    return out
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
local listing = {}

local function Where(rec)
    local e, d = Nearest(rec)
    if not e then return "entrance unknown" end
    return string.format("%s %.0f, %.0f%s", MapName(e.uiMapId), e.zx * 100, e.zy * 100,
        d and string.format(" (about %d yards)", d) or "")
end

local function ForMyLevel()
    local lvl = UnitLevel("player") or 1
    local out = {}
    for _, rec in pairs(byKey or {}) do
        local r = rec.levels
        if r and lvl >= r[1] - 2 and lvl <= r[2] and #rec.entrances > 0 then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b) return a.levels[1] < b.levels[1] end)
    return out
end

local function Summary()
    if not Build() then Print("dungeon data needs Questie loaded and ready"); return end
    listing = {}
    local dq = DungeonQuests()
    if #dq == 0 then
        Print("none of your quests need a dungeon right now")
    else
        Print("your quests that need a dungeon:")
        for _, v in ipairs(dq) do
            listing[#listing + 1] = v.rec
            local titles = {}
            for i = 1, math.min(#v.quests, 4) do titles[i] = v.quests[i] end
            Print(string.format("  %d. %s%s: %d quest%s (%s%s) - %s", #listing, v.rec.name,
                v.rec.levels and string.format(" (level %d-%d)", v.rec.levels[1], v.rec.levels[2]) or "",
                #v.quests, #v.quests == 1 and "" or "s", table.concat(titles, ", "),
                #v.quests > 4 and ", ..." or "", Where(v.rec)))
        end
    end
    local fit = ForMyLevel()
    if #fit > 0 then
        Print("dungeons for your level:")
        for _, rec in ipairs(fit) do
            listing[#listing + 1] = rec
            Print(string.format("  %d. %s (level %d-%d) - %s", #listing, rec.name, rec.levels[1], rec.levels[2], Where(rec)))
        end
    end
    if #listing > 0 then Print("/lrxp dungeons go 1  puts a waypoint on the first entrance") end
end

local function Go(arg)
    if not Build() then Print("dungeon data needs Questie loaded and ready"); return end
    if #listing == 0 then Summary() end
    local rec
    local n = tonumber(arg)
    if n then
        rec = listing[n]
    elseif arg and arg ~= "" then
        local k = arg:lower()
        for _, r in pairs(byKey) do
            if r.name:lower():find(k, 1, true) then rec = r; break end
        end
    else
        rec = listing[1]
    end
    if not rec then Print("no such dungeon, try /lrxp dungeons first"); return end
    local e = Nearest(rec)
    if not e then Print(rec.name .. ": entrance position unknown"); return end
    addon:AddWaypointZone(e.uiMapId, e.zx, e.zy, rec.name .. " entrance")
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd == "dungeons" or cmd == "dungeon" then
        local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
        if sub == "go" then Go(arg) else Summary() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

--------------------------------------------------------------------------------
-- A hint when I walk into the zone of an entrance my quests need
--------------------------------------------------------------------------------
local hinted = {}
local ev = CreateFrame("Frame")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(4, function()
        pcall(function()
            local db = DB()
            if not db or db.dungeonHint == false then return end
            if IsInInstance and IsInInstance() then return end
            local here = hbd:GetPlayerZone()
            if not here then return end
            for _, v in ipairs(DungeonQuests()) do
                for _, e in ipairs(v.rec.entrances) do
                    if e.uiMapId == here and not hinted[v.rec.name] then
                        hinted[v.rec.name] = true
                        Print(string.format("%d of your quests are inside %s, the entrance is here (%s). /lrxp dungeons go %s",
                            #v.quests, v.rec.name, Where(v.rec), v.rec.name))
                    end
                end
            end
        end)
    end)
end)
