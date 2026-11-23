-- Dungeons: which of your quests need a dungeon, where its entrance is, and which dungeons suit your level.
-- It also gives the corpse arrow the dungeon entrance after you die inside one (the corpse run).
--   /lazy dungeons              quests that need a dungeon, and dungeons for your level
--   /lazy dungeons go [n|name]  put a waypoint on a dungeon entrance
-- Dungeon names, entrances and quest locations come from Questie's database.
local ADDON, ns = ...
local L = ns.L
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

api.DungeonLevels = LEVELS

local function Zone()
    return ns.data.Module("ZoneDB")
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

-- Is this a quest that can only be done inside a dungeon? (plans leave these out: they are for a group, inside)
local dungeonQuestCache = {}
function api.IsDungeonQuest(id, complete, noTitle)
    if not id then return false end
    local key = id .. (complete and "c" or "o") .. (noTitle and "n" or "")
    local c = dungeonQuestCache[key]
    if c == true then return true end
    if c and GetTime() - c < 30 then return false end      -- a "no" is only trusted for a while (tags load late)
    if not (Build() and api.QuestieReady and api.QuestieReady()) then return false end   -- not known yet: do not cache
    local QDB = api.GetQuestie()
    local result = false
    -- 0. the quest is tagged Dungeon or Raid: by the game itself (quests in my log), or by Questie's own tag data
    local DUNGEON_TAGS = { [81] = true, [62] = true, [88] = true, [89] = true, [85] = true }
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local okT, info = pcall(C_QuestLog.GetQuestTagInfo, id)
        if okT and type(info) == "table" and DUNGEON_TAGS[info.tagID or -1] then result = true end
    end
    if not result and QDB.GetQuestTagInfo then
        local okT, tagId = pcall(QDB.GetQuestTagInfo, id)
        if okT and DUNGEON_TAGS[tagId or -1] then result = true end
    end
    -- 1. the quest is filed under a dungeon
    local okZ, zone = pcall(QDB.QueryQuestSingle, id, "zoneOrSort")
    if not result and okZ and type(zone) == "number" and zone > 0 and areaTo[zone] then result = true end
    -- 2. everything I would have to do is inside a dungeon
    if not result then
        local ok, set = pcall(QuestAreas, QDB, { id = id, complete = complete and true or false })
        if ok and type(set) == "table" then
            local inRec, outside = false, false
            for areaId in pairs(set) do
                if areaTo[areaId] then inRec = true else outside = true end
            end
            result = inRec and not outside
        end
    end
    -- 3. it is given inside a dungeon, so it cannot be started out here
    if not result then
        local by = QDB.QueryQuestSingle(id, "startedBy")
        if type(by) == "table" then
            local set = {}
            if type(by[1]) == "table" then
                for _, npc in pairs(by[1]) do
                    local sp = QDB.QueryNPCSingle(npc, "spawns")
                    if type(sp) == "table" then for areaId in pairs(sp) do set[areaId] = true end end
                end
            end
            local inRec, outside = false, false
            for areaId in pairs(set) do
                if areaTo[areaId] then inRec = true else outside = true end
            end
            result = inRec and not outside
        end
    end
    -- 4. another quest with exactly this title is a dungeon quest (the same quest under a second id, such as a Forever copy)
    if not result and not noTitle and api.DungeonTitle then
        local name = QDB.QueryQuestSingle(id, "name")
        if not name and C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local okN, n = pcall(C_QuestLog.GetTitleForQuestID, id)
            if okN then name = n end
        end
        if name and api.DungeonTitle(name) then result = true end
    end
    dungeonQuestCache[key] = result and true or GetTime()
    return result
end

-- Is there a dungeon quest with exactly this title? (for plan stops that only carry a name). Reads Questie's quest names once.
local nameIndex
function api.DungeonTitle(title)
    if not title or title == "" then return false end
    local QDB = api.GetQuestie()
    if not (QDB and QDB.QuestPointers and api.QuestieReady and api.QuestieReady()) then return false end
    if not nameIndex then
        nameIndex = {}
        for id in pairs(QDB.QuestPointers) do
            local n = QDB.QueryQuestSingle(id, "name")
            if n then
                local k = n:lower()
                local l = nameIndex[k]
                if not l then l = {}; nameIndex[k] = l end
                l[#l + 1] = id
            end
        end
    end
    for _, id in ipairs(nameIndex[title:lower()] or {}) do
        if api.IsDungeonQuest(id, false, true) then return true, id end
    end
    return false
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
    if not Build() then Print(L("dungeon data needs Questie loaded and ready")); return end
    listing = {}
    local dq = DungeonQuests()
    if #dq == 0 then
        Print(L("none of your quests need a dungeon right now"))
    else
        Print(L("your quests that need a dungeon:"))
        for _, v in ipairs(dq) do
            listing[#listing + 1] = v.rec
            local titles = {}
            for i = 1, math.min(#v.quests, 4) do titles[i] = v.quests[i] end
            Print(string.format(L("  %d. %s%s: %d quest%s (%s%s) - %s"), #listing, v.rec.name,
                v.rec.levels and string.format(" (level %d-%d)", v.rec.levels[1], v.rec.levels[2]) or "",
                #v.quests, #v.quests == 1 and "" or "s", table.concat(titles, ", "),
                #v.quests > 4 and ", ..." or "", Where(v.rec)))
        end
    end
    local fit = ForMyLevel()
    if #fit > 0 then
        Print(L("dungeons for your level:"))
        for _, rec in ipairs(fit) do
            listing[#listing + 1] = rec
            Print(string.format(L("  %d. %s (level %d-%d) - %s"), #listing, rec.name, rec.levels[1], rec.levels[2], Where(rec)))
        end
    end
    if #listing > 0 then Print(L("/lazy dungeons go 1  puts a waypoint on the first entrance")) end
end

local function Go(arg)
    if not Build() then Print(L("dungeon data needs Questie loaded and ready")); return end
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
    if not rec then Print(L("no such dungeon, try /lazy dungeons first")); return end
    local e = Nearest(rec)
    if not e then Print(rec.name .. L(": entrance position unknown")); return end
    addon:AddWaypointZone(e.uiMapId, e.zx, e.zy, rec.name .. " entrance")
end

--------------------------------------------------------------------------------
-- In a dungeon with a group: what my quests need in here, exactly
--------------------------------------------------------------------------------
local function ObjectiveLinesHere(QDB, id, rec)
    local lines = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
        if ok and type(objs) == "table" then
            for _, o in ipairs(objs) do
                if not o.finished and o.text and o.text ~= "" then lines[#lines + 1] = o.text end
            end
        end
    end
    -- where each wanted item drops, inside this dungeon
    local obj = QDB.QueryQuestSingle(id, "objectives")
    if type(obj) == "table" and type(obj[3]) == "table" then
        for _, c in pairs(obj[3]) do
            local itemId = c[1]
            if itemId then
                local itemName = QDB.QueryItemSingle(itemId, "name") or "item"
                local from, n = {}, 0
                local drops = QDB.QueryItemSingle(itemId, "npcDrops")
                if type(drops) == "table" then
                    for _, npc in pairs(drops) do
                        local sp = QDB.QueryNPCSingle(npc, "spawns")
                        local here = false
                        if type(sp) == "table" then for areaId in pairs(sp) do if areaTo[areaId] == rec then here = true; break end end end
                        if here then
                            n = n + 1
                            if n <= 4 then from[#from + 1] = QDB.QueryNPCSingle(npc, "name") or "?" end
                        end
                    end
                end
                if #from > 0 then lines[#lines + 1] = "   " .. itemName .. " drops from: " .. table.concat(from, ", ") .. (n > 4 and ", ..." or "") end
            end
        end
    end
    return lines
end

-- my quests that have something to do in this dungeon: { title, class, lines }
function addon.DungeonQuestsHere(instanceName)
    local out = {}
    if not (instanceName and Build() and api.QuestieReady and api.QuestieReady() and api.ReadQuestLog) then return out end
    local rec = byKey[Key(instanceName)]
    if not rec then return out end
    local QDB = api.GetQuestie()
    for _, q in ipairs(api.ReadQuestLog()) do
        if not q.complete then
            local inside = false
            local ok, set = pcall(QuestAreas, QDB, q)
            if ok and type(set) == "table" then
                for areaId in pairs(set) do if areaTo[areaId] == rec then inside = true; break end end
            end
            if inside then
                local lines = ObjectiveLinesHere(QDB, q.id, rec)
                out[#out + 1] = { id = q.id, title = q.title or ("quest " .. q.id), lines = lines,
                                  class = addon.IsClassQuestId and addon.IsClassQuestId(q.id) or false }
            end
        end
    end
    table.sort(out, function(a, b) if a.class ~= b.class then return a.class end return a.title < b.title end)
    return out
end

local dToast
local function ShowDungeonToast(name, quests)
    if not dToast then
        local f = CreateFrame("Frame", "ForeverLazy_DungeonToast", UIParent)
        f:SetSize(460, 200)
        f:SetPoint("TOP", 0, -140)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -12); f.title:SetWidth(420)
        f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.body:SetPoint("TOP", f.title, "BOTTOM", 0, -8); f.body:SetWidth(424); f.body:SetJustifyH("LEFT")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(100, 22); btn:SetPoint("BOTTOM", 0, 10); btn:SetText(L("Close"))
        btn:SetScript("OnClick", function() f:Hide() end)
        table.insert(UISpecialFrames, "ForeverLazy_DungeonToast")
        f:Hide()
        dToast = f
    end
    dToast.title:SetText("Your quests in " .. name)
    local lines = {}
    for _, q in ipairs(quests) do
        lines[#lines + 1] = "|cffffd100" .. q.title .. "|r" .. (q.class and "  |cff80c0ff(class quest)|r" or "")
        if #q.lines == 0 then lines[#lines + 1] = "   (no objective text found)" end
        for _, l in ipairs(q.lines) do lines[#lines + 1] = "   " .. l end
        lines[#lines + 1] = ""
    end
    dToast.body:SetText(table.concat(lines, "\n"))
    dToast:SetHeight(math.max(120, 90 + dToast.body:GetStringHeight()))
    dToast:Show()
end

-- /lazy dungeons here: what my quests need in the dungeon I am in (any time, group or not)
function addon.DungeonHere(auto)
    local name, itype = GetInstanceInfo and GetInstanceInfo()
    if not name or (itype ~= "party" and itype ~= "raid") then
        if not auto then Print(L("you are not inside a dungeon")) end
        return
    end
    local quests = addon.DungeonQuestsHere(name)
    if #quests == 0 then
        if not auto then Print(L("none of your quests need anything in ") .. name) end
        return
    end
    ShowDungeonToast(name, quests)
end

--------------------------------------------------------------------------------
-- Inside a dungeon: the arrow takes me to what my quests need, spot by spot
--------------------------------------------------------------------------------
-- where the things a quest still needs are inside this dungeon, in world coordinates of the dungeon's own map
local function DungeonSpotsFor(QDB, id, rec, pinst)
    local spots, grid = {}, {}
    local texts = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
        if ok and type(objs) == "table" then
            for _, o in ipairs(objs) do
                if not o.finished and o.text then texts[#texts + 1] = o.text:lower() end
            end
        end
    end
    -- an objective is still open when its name is in the text of an unfinished objective
    local function wanted(name)
        if not name then return true end
        local n = name:lower()
        for _, tx in ipairs(texts) do if tx:find(n, 1, true) then return true end end
        return #texts == 0
    end
    local Z = Zone()
    local function addSpawns(spawns)
        if type(spawns) ~= "table" or not Z then return end
        for areaId, list in pairs(spawns) do
            if areaTo[areaId] == rec and type(list) == "table" then
                local uiMapId = Z:GetUiMapIdByAreaId(areaId)
                if uiMapId then
                    for _, c in ipairs(list) do
                        local zx, zy = (c[1] or 0) / 100, (c[2] or 0) / 100
                        local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(zx, zy, uiMapId)
                        if wx and inst == pinst then
                            local key = math.floor(wx / 25) .. ":" .. math.floor(wy / 25)
                            if not grid[key] then
                                grid[key] = true
                                spots[#spots + 1] = { x = wx, y = wy, instance = inst, uiMapId = uiMapId, zx = zx, zy = zy, key = key }
                            end
                        end
                    end
                end
            end
        end
    end
    local obj = QDB.QueryQuestSingle(id, "objectives")
    if type(obj) == "table" then
        for _, c in pairs(obj[1] or {}) do
            if c[1] and wanted(QDB.QueryNPCSingle(c[1], "name")) then addSpawns(QDB.QueryNPCSingle(c[1], "spawns")) end
        end
        for _, c in pairs(obj[2] or {}) do
            if c[1] and wanted(QDB.QueryObjectSingle(c[1], "name")) then addSpawns(QDB.QueryObjectSingle(c[1], "spawns")) end
        end
        for _, c in pairs(obj[3] or {}) do
            if c[1] and wanted(QDB.QueryItemSingle(c[1], "name")) then
                local n = 0
                local drops = QDB.QueryItemSingle(c[1], "npcDrops")
                if type(drops) == "table" then
                    for _, npc in pairs(drops) do
                        n = n + 1
                        if n > 40 then break end
                        addSpawns(QDB.QueryNPCSingle(npc, "spawns"))
                    end
                end
                local odrops = QDB.QueryItemSingle(c[1], "objectDrops")
                if type(odrops) == "table" then
                    for _, o in pairs(odrops) do addSpawns(QDB.QueryObjectSingle(o, "spawns")) end
                end
            end
        end
    end
    return spots
end

local dungeonKey = {}
local daCache = { name = nil, t = 0, ids = {} }

local function InDungeonName()
    local name, itype = GetInstanceInfo and GetInstanceInfo()
    if name and (itype == "party" or itype == "raid") then return name end
end

-- the arrow's target while I am inside a dungeon with quests that need something here (nil otherwise)
function addon.DungeonArrowTarget()
    local db = addon.GetDB()
    if not db or db.dungeonArrow == false or not addon.PickObjectiveSpot then return nil end
    local name = InDungeonName()
    if not name then return nil end
    local now = GetTime()
    if daCache.name ~= name or now - daCache.t > 5 then
        local ids = {}
        for _, q in ipairs(addon.DungeonQuestsHere(name)) do ids[#ids + 1] = q.id end
        daCache = { name = name, t = now, ids = ids }
    end
    -- only the quests that are not finished
    local open = {}
    for _, id in ipairs(daCache.ids) do
        local okC, done = pcall(C_QuestLog.IsComplete, id)
        if okC and not done then open[#open + 1] = id end
    end
    if #open == 0 then return nil end
    local rec = byKey and byKey[Key(name)]
    if not rec then return nil end
    local QDB = api.GetQuestie()
    return addon.PickObjectiveSpot(dungeonKey, open, "Dungeon: " .. name, {}, function(ids, pinst)
        local out, grid = {}, {}
        for _, id in ipairs(ids) do
            for _, s in ipairs(DungeonSpotsFor(QDB, id, rec, pinst)) do
                if not grid[s.key] then grid[s.key] = true; out[#out + 1] = s end
            end
        end
        return out
    end)
end

-- the arrows are normally hidden inside a dungeon; this one is not, while it has somewhere to point
function addon.DungeonArrowActive()
    return addon.DungeonArrowTarget() ~= nil
end
local shownIn = {}
local dEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do pcall(dEv.RegisterEvent, dEv, e) end
dEv:SetScript("OnEvent", function()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(4, function()
        local db = addon.GetDB()
        if not db or db.dungeonQuestPopup == false then return end
        if not (IsInGroup and IsInGroup()) then return end                      -- only with a group
        local name, itype, _, _, _, _, _, instanceId = GetInstanceInfo and GetInstanceInfo()
        if not name or (itype ~= "party" and itype ~= "raid") then return end
        local key = tostring(instanceId or name)
        if shownIn[key] and GetTime() - shownIn[key] < 900 then return end      -- once per visit
        shownIn[key] = GetTime()
        pcall(addon.DungeonHere, true)
    end)
end)

-- /lazy dungeons why <part of a quest title>: why a quest in my plan or log is, or is not, counted as a dungeon quest
function addon.DungeonWhy(text)
    text = (text or ""):lower()
    if not Build() then Print(L("dungeon data needs Questie loaded and ready")); return end
    local QDB = api.GetQuestie()
    local seen, n = {}, 0
    local function Report(id, title)
        if seen[id] then return end
        seen[id] = true
        n = n + 1
        local gameTag = "none"
        if C_QuestLog and C_QuestLog.GetQuestTagInfo then
            local ok, info = pcall(C_QuestLog.GetQuestTagInfo, id)
            if ok and type(info) == "table" then gameTag = tostring(info.tagID) .. " " .. tostring(info.tagName) end
        end
        local qTag = QDB.GetQuestTagInfo and select(2, pcall(QDB.GetQuestTagInfo, id))
        local zone = QDB.QueryQuestSingle(id, "zoneOrSort")
        local group = QDB.QueryQuestSingle(id, "groupSize") or QDB.QueryQuestSingle(id, "suggestedGroup")
        dungeonQuestCache[id .. "o"] = nil; dungeonQuestCache[id .. "c"] = nil
        local verdict = api.IsDungeonQuest(id, false)
        Print(string.format(L("%s (id %d): dungeon = %s | game tag: %s | Questie tag: %s | zoneOrSort: %s (dungeon area: %s) | group: %s"),
            tostring(title), id, tostring(verdict), gameTag, tostring(qTag), tostring(zone),
            tostring(type(zone) == "number" and areaTo[zone] and true or false), tostring(group)))
    end
    for _, w in ipairs(addon.GetDB().waypoints or {}) do
        for _, q in ipairs(w.quests or {}) do
            local title = q.label or ""
            if q.id and (text == "" or title:lower():find(text, 1, true)) then Report(q.id, title) end
        end
    end
    if api.ReadQuestLog then
        for _, q in ipairs(api.ReadQuestLog()) do
            if q.id and (text == "" or (q.title or ""):lower():find(text, 1, true)) then Report(q.id, q.title) end
        end
    end
    if n == 0 then Print(L("no quest in your plan or log matches '") .. text .. "'") end
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd == "dungeons" or cmd == "dungeon" then
        local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
        if sub == "go" then Go(arg)
        elseif sub == "why" then addon.DungeonWhy(arg)
        elseif sub == "here" then addon.DungeonHere()
        elseif sub == "purge" then
            if addon.PurgeDungeonStops then addon.PurgeDungeonStops(true) end
        else Summary() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

--------------------------------------------------------------------------------
-- A hint when I walk into the zone of an entrance my quests need
--------------------------------------------------------------------------------
local hinted = {}
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(4, function()
        pcall(function()
            local db = DB()
            if not db or db.dungeonHint == false or not addon.ModuleOn("dungeons") then return end
            if IsInInstance and IsInInstance() then return end
            local here = hbd:GetPlayerZone()
            if not here then return end
            for _, v in ipairs(DungeonQuests()) do
                for _, e in ipairs(v.rec.entrances) do
                    if e.uiMapId == here and not hinted[v.rec.name] then
                        hinted[v.rec.name] = true
                        Print(string.format(L("%d of your quests are inside %s, the entrance is here (%s). /lazy dungeons go %s"),
                            #v.quests, v.rec.name, Where(v.rec), v.rec.name))
                    end
                end
            end
        end)
    end)
end)

-- used by the trip planner: the dungeon whose name contains this text
function api.DungeonFind(text)
    if not Build() then return nil end
    local k = Key(text)
    if k == "" then return nil end
    for key, rec in pairs(byKey) do
        if key:find(k, 1, true) and #rec.entrances > 0 then return rec end
    end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Dungeons.lua"] = true end end
