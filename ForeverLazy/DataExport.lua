-- Developer tool for phase 4 of docs/QUESTIE-INDEPENDENCE.md: dump the quest, creature, object and item data of the installed
-- source (Questie) into a compact form, so a data file of our own can be made from it offline.
--   /lazy data export         dump everything into ForeverLazyDB.exportDump (a few seconds, in small steps); /reload afterwards
--   /lazy data export clear   delete the dump (do this once the file is made, it is large)
-- Each record is saved as one Lua-literal string, { field values in a fixed order }, so no decoding is needed later.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

-- field order for each kind (the offline converter reads this list back from the dump)
local FIELDS = {
    quests = { "name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "objectivesText",
        "triggerEnd", "objectives", "sourceItemId", "preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo",
        "zoneOrSort", "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSourceItems", "nextQuestInChain", "questFlags",
        "specialFlags", "parentQuest", "reputationReward", "breadcrumbForQuestId", "breadcrumbs", "requiredSpell",
        "requiredSpecialization", "requiredMaxLevel", "availableUntilCompleted", "availableStartingWith", "requiredRanks", "disabledByQuest" },
    npcs = { "name", "minLevel", "maxLevel", "rank", "spawns", "zoneID", "questStarts", "questEnds", "factionID", "friendlyToFaction", "subName", "npcFlags" },
    objects = { "name", "questStarts", "questEnds", "spawns", "zoneID", "factionID" },
    items = { "name", "npcDrops", "objectDrops", "itemDrops", "startQuest", "questRewards", "flags", "itemLevel", "requiredLevel", "class", "subClass", "vendors", "relatedQuests" },
}
local QUERY = { quests = "QueryQuestSingle", npcs = "QueryNPCSingle", objects = "QueryObjectSingle", items = "QueryItemSingle" }
local POINTERS = { quests = "QuestPointers", npcs = "NPCPointers", objects = "ObjectPointers", items = "ItemPointers" }

-- a value as Lua source, as short as possible
local function Lit(v, depth)
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "number" then
        if v == math.floor(v) then return string.format(math.abs(v) < 2147483648 and "%d" or "%.0f", v) end   -- big bitmasks overflow %d
        return string.format("%.4g", v)
    end
    if t == "boolean" then return v and "true" or "false" end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        depth = (depth or 0) + 1
        if depth > 8 then return "nil" end
        local parts, n = {}, 0
        local isArray = true
        for k in pairs(v) do n = n + 1 end
        for i = 1, n do if v[i] == nil then isArray = false; break end end
        if isArray then
            for i = 1, n do parts[i] = Lit(v[i], depth) end
        else
            for k, x in pairs(v) do
                local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
                parts[#parts + 1] = key .. "=" .. Lit(x, depth)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

local running
local function Export()
    if running then Print(L("an export is already running")) return end
    local QDB = ns.data and ns.data.Module and ns.data.Module("QuestieDB")
    local root = addon.GetRoot and addon.GetRoot()
    if not (QDB and root) then Print(L("the data source is not loaded yet")) return end
    running = true
    local dump = { version = 1, fields = FIELDS, count = {} }
    root.exportDump = dump
    local kinds = { "quests", "npcs", "objects", "items" }
    local ki, ids, pos = 1, nil, 1
    local started = debugprofilestop()

    local function Step()
        local t0 = debugprofilestop()
        while ki <= #kinds do
            local kind = kinds[ki]
            if not ids then
                ids = {}
                local ptr = QDB[POINTERS[kind]]
                if type(ptr) == "table" then for id in pairs(ptr) do ids[#ids + 1] = id end end
                table.sort(ids)
                dump[kind] = {}
                dump.count[kind] = #ids
                pos = 1
            end
            local query, list, store = QDB[QUERY[kind]], FIELDS[kind], dump[kind]
            while pos <= #ids do
                local id = ids[pos]
                local vals, last = {}, 0
                for i, f in ipairs(list) do
                    local ok, v = pcall(query, id, f)
                    if ok and v ~= nil then vals[i] = Lit(v); last = i end
                end
                local parts = {}
                for i = 1, last do parts[i] = vals[i] or "nil" end
                store[id] = "{" .. table.concat(parts, ",") .. "}"
                pos = pos + 1
                if debugprofilestop() - t0 > 8 then break end
            end
            if pos > #ids then ki = ki + 1; ids = nil else break end
        end
        if ki <= #kinds then
            C_Timer.After(0, Step)
        else
            running = false
            dump.seconds = (debugprofilestop() - started) / 1000
            Print(string.format(L("export done: %d quests, %d creatures, %d objects, %d items. Type /reload to save it to disk."),
                dump.count.quests or 0, dump.count.npcs or 0, dump.count.objects or 0, dump.count.items or 0))
        end
    end
    Print(L("exporting the data source in small steps, it takes a few seconds..."))
    Step()
end

-- zones: the area id -> map id table as the source answers it, for every area id the data set mentions, and the dungeon list
local function ExportZones()
    local Z = ns.data and ns.data.Module and ns.data.Module("ZoneDB")
    local root = addon.GetRoot and addon.GetRoot()
    if not (Z and root and Z.GetUiMapIdByAreaId) then Print(L("the zone data is not loaded yet")) return end
    local ids = {}
    local function Add(id) if type(id) == "number" and id > 0 then ids[id] = true end end
    local DS = ns.dataset
    for _, kind in ipairs({ "npcs", "objects" }) do
        local fields = DS.fields[kind] or {}
        local spawnsAt, zoneAt
        for i, name in ipairs(fields) do if name == "spawns" then spawnsAt = i end end
        for id, text in pairs(DS[kind]) do
            local rec = ns.data.Record(kind, id)
            if rec and spawnsAt and type(rec[spawnsAt]) == "table" then
                for areaId in pairs(rec[spawnsAt]) do Add(areaId) end
            end
        end
    end
    local zAt
    for i, name in ipairs(DS.fields.quests or {}) do if name == "zoneOrSort" then zAt = i end end
    if zAt then for id in pairs(DS.quests) do local r = ns.data.Record("quests", id); if r then Add(r[zAt]) end end end
    -- and every area the zone module knows by itself
    local priv = Z.private
    if type(priv) == "table" then
        for _, name in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
            local tbl = priv[name]
            if type(tbl) == "string" then local fn = loadstring and loadstring(tbl); tbl = fn and fn() end
            if type(tbl) == "table" then for id in pairs(tbl) do Add(id) end end
        end
    end
    local map, n = {}, 0
    for id in pairs(ids) do
        local ok, ui = pcall(Z.GetUiMapIdByAreaId, Z, id)
        if ok and ui then map[id] = ui; n = n + 1 end
    end
    local zones = { areaToMap = map }
    if Z.GetDungeons then
        local ok, list = pcall(Z.GetDungeons, Z)
        if ok and type(list) == "table" then zones.dungeons = Lit(list) end
    end
    local pieces = {}
    for id, ui in pairs(map) do pieces[#pieces + 1] = "[" .. id .. "]=" .. ui end
    zones.areaToMap = table.concat(pieces, ",")
    root.exportZones = zones
    Print(string.format(L("zones exported: %d areas with a map id%s. Type /reload to save it."), n, zones.dungeons and ", and the dungeon list" or ""))
end

-- service lists: vendors, trainers, innkeepers ... as the source built them from the creature flags this session
local function ExportTownsfolk()
    local T = ns.data and ns.data.Module and ns.data.Module("Townsfolk")
    local P = ns.data and ns.data.Module and ns.data.Module("QuestieProfessions")
    local root = addon.GetRoot and addon.GetRoot()
    if not (T and root and T.townsfolk) then Print(L("the service lists are not loaded yet (they fill in about a minute after login)")) return end
    if not next(T.townsfolk) then Print(L("the service lists are still empty, wait a minute and try again")) return end
    local out = {
        townsfolk = Lit(T.townsfolk),
        professionTrainers = Lit(T.professionTrainers or {}),
        classSpecificTownsfolk = Lit(T.classSpecificTownsfolk or {}),
        factionSpecificTownsfolk = Lit(T.factionSpecificTownsfolk or {}),
        petFoodVendorTypes = Lit(T.petFoodVendorTypes or {}),
        professionKeys = Lit(P and P.professionKeys or {}),
    }
    root.exportTownsfolk = out
    local cats = 0
    for _ in pairs(T.townsfolk) do cats = cats + 1 end
    Print(string.format(L("service lists exported: %d categories, %d characters of data. Type /reload to save it."), cats, #out.townsfolk + #out.professionTrainers + #out.classSpecificTownsfolk + #out.factionSpecificTownsfolk))
end

-- quests the source never offers (its blacklist), as a plain list of ids
local function ExportHidden()
    local C = ns.data and ns.data.Module and ns.data.Module("QuestieCorrections")
    local root = addon.GetRoot and addon.GetRoot()
    if not (C and root and type(C.hiddenQuests) == "table") then Print(L("the quest blacklist is not loaded yet")) return end
    local ids = {}
    for id, hide in pairs(C.hiddenQuests) do if hide and type(id) == "number" then ids[#ids + 1] = id end end
    table.sort(ids)
    root.exportHidden = table.concat(ids, ",")
    -- quests the source hides by its own settings (the Ahn'Qiraj war effort, event quests ...)
    local B = ns.data.Module("QuestieQuestBlacklist")
    local extra = {}
    if type(B) == "table" then
        for name, tbl in pairs(B) do
            if type(name) == "string" and type(tbl) == "table" and (name:find("AQ") or name:find("Invasion") or name:find("Event")) then
                local list = {}
                for id, v in pairs(tbl) do if v and type(id) == "number" then list[#list + 1] = id end end
                table.sort(list)
                extra[name] = table.concat(list, ",")
            end
        end
    end
    root.exportHiddenGroups = extra
    local names = {}
    for name, s in pairs(extra) do names[#names + 1] = name end
    Print(string.format(L("quest blacklist exported: %d quests, and the groups %s. Type /reload to save it."), #ids, #names > 0 and table.concat(names, ", ") or "(none found)"))
end

-- quest tags (dungeon, raid, elite, class ...) as the source answers them, for every quest in the data set
local function ExportTags()
    local QDB = ns.data and ns.data.Module and ns.data.Module("QuestieDB")
    local root = addon.GetRoot and addon.GetRoot()
    if not (QDB and QDB.GetQuestTagInfo and root) then Print(L("the data source is not loaded yet")) return end
    local parts, n = {}, 0
    for id in pairs(ns.dataset.quests) do
        local ok, tag = pcall(QDB.GetQuestTagInfo, id)
        if ok and tonumber(tag) then parts[#parts + 1] = id .. "=" .. tonumber(tag); n = n + 1 end
    end
    root.exportTags = table.concat(parts, ",")
    Print(string.format(L("quest tags exported: %d of %d quests have one. Type /reload to save it."), n, (ns.data.DatasetSize())))
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "data" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if a == "export" then Export(); return true end
        if a == "export zones" then ExportZones(); return true end
        if a == "export townsfolk" then ExportTownsfolk(); return true end
        if a == "export hidden" then ExportHidden(); return true end
        if a == "export tags" then ExportTags(); return true end
        if a == "export clear" then
            local root = addon.GetRoot and addon.GetRoot()
            if root then root.exportDump = nil end
            Print(L("export dump deleted. /reload to save the smaller file."))
            return true
        end
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["DataExport.lua"] = true end end
