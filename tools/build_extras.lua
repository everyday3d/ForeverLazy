-- Rebuild Zones.lua, Extra1.lua (hidden quests + drop chances), Extra2.lua (hidden groups + quest tags) and Townsfolk.lua offline,
-- from the QuestieDB and Questie add-on files. Run:  lua build_extras.lua <QuestieDB> <ForeverLazy> <new dump file> <out dir>
local DBDIR, FLDIR, DUMP, OUTDIR = arg[1], arg[2], arg[3], arg[4]
assert(OUTDIR, "usage: lua build_extras.lua <QuestieDB folder> <ForeverLazy folder> <new-export.lua> <out dir>")
local ADDONS = DBDIR:gsub("\\", "/"):gsub("/QuestieDB/?$", "")
local Q = ADDONS .. "/Questie/"
OUTDIR = OUTDIR:gsub("\\", "/"):gsub("/$", "") .. "/"

QDB_LIBRARY_ONLY = true
local here = arg[0]:gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local Lib = dofile(here .. "/qdb_offline.lua")
QDB_LIBRARY_ONLY = nil

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function W(name, text) local f = assert(io.open(OUTDIR .. name, "wb")); f:write(text); f:close() end

-- the new dump (for the ids the data set mentions) ------------------------------------------------------
ForeverLazyDB = nil
dofile(DUMP)
local dump = ForeverLazyDB.exportDump
ForeverLazyDB = nil
local function fieldIndex(kind, name) for i, n in ipairs(dump.fields[kind]) do if n == name then return i end end end

-- the Questie flavor: the Forever client counts as Era content ------------------------------------------
WOW_PROJECT_ID = 18; WOW_PROJECT_CLASSIC = 2; WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5; WOW_PROJECT_WRATH_CLASSIC = 11
WOW_PROJECT_CATACLYSM_CLASSIC = 14; WOW_PROJECT_MISTS_CLASSIC = 19
Questie = { IsForever = true, IsSoD = false, IsHardcore = false, IsAnniversary = false, IsWotlk = false, IsTBC = false, IsEra = true,
            IsClassic = true, IsTitanReforged = false, IsMoP = false }
-- QuestieDB's own support loader replaced QuestieLoader; Questie brings its own
_G.QuestieLoader = nil
dofile(Q .. "Modules/Libs/QuestieLoader.lua")
dofile(Q .. "Modules/Expansions.lua")
dofile(Q .. "Database/Corrections/ContentPhases/ContentPhases.lua")
dofile(Q .. "Database/Corrections/BlacklistFilter.lua")
dofile(Q .. "Database/Corrections/QuestieQuestBlacklist.lua")
local Blacklist = QuestieLoader:ImportModule("QuestieQuestBlacklist")
local Filter = QuestieLoader:ImportModule("BlacklistFilter")

--------------------------------------------------------------------------------
-- Hidden quests, and the groups the source hides by its own settings
--------------------------------------------------------------------------------
local hiddenList = Filter.filterExpansion(Blacklist:Load())
local hidden = {}
for id, hide in pairs(hiddenList) do if hide and type(id) == "number" then hidden[#hidden + 1] = id end end
table.sort(hidden)
local groups = {}
for name, tbl in pairs(Blacklist) do
    if type(name) == "string" and type(tbl) == "table" and (name:find("AQ") or name:find("Invasion") or name:find("Event")) then
        local list = {}
        for id, v in pairs(tbl) do if v and type(id) == "number" then list[#list + 1] = id end end
        table.sort(list)
        groups[name] = table.concat(list, ",")
    end
end
print("hidden", #hidden)

--------------------------------------------------------------------------------
-- Drops (as before: manual correction, then private-server data, then Wowhead)
--------------------------------------------------------------------------------
local DROPS = DBDIR:gsub("\\", "/"):gsub("/$", "") .. "/support/Forever/DropTables/"
local modules = {}
local DropDB = { correctionKeys = { WOWHEAD = -1, PSERVER = -2 } }
local saveLoader = QuestieLoader
QuestieLoader = {
    CreateModule = function(_, n) modules[n] = modules[n] or {} return modules[n] end,
    ImportModule = function(_, n) if n == "DropDB" then return DropDB end modules[n] = modules[n] or {} return modules[n] end,
}
assert(loadfile(DROPS .. "classicItemDrops.lua"))()
assert(loadfile(DROPS .. "itemDropCorrections.lua"))()
local drops = modules.QuestieClassicItemDrops
local wowhead = assert(load(drops.wowheadData))()
local pserver = assert(load(drops.cmangosData))()
local corr = modules.QuestieItemDropCorrections.Era or {}
QuestieLoader = saveLoader
local function rate(item, npc)
    local c = corr[item] and corr[item][npc]
    if c then
        if c >= 0 then return c end
        if c == -1 and wowhead[item] and wowhead[item][npc] then return wowhead[item][npc] end
        if c == -2 and pserver[item] and pserver[item][npc] then return pserver[item][npc] end
    end
    if pserver[item] and pserver[item][npc] then return pserver[item][npc] end
    if wowhead[item] and wowhead[item][npc] then return wowhead[item][npc] end
end
local items = {}
for _, t in ipairs({ wowhead, pserver, corr }) do
    for item, npcs in pairs(t) do for npc in pairs(npcs) do items[item] = items[item] or {}; items[item][npc] = true end end
end
local itemIds = {}
for item in pairs(items) do itemIds[#itemIds + 1] = item end
table.sort(itemIds)

do
    local o = {}
    o[#o + 1] = "-- Quests the game's data never offers (its blacklist), and how often creatures drop items. Generated, do not edit.\n"
    o[#o + 1] = "local ADDON, ns = ...\nns.dataset.hidden = {\n"
    local line = ""
    for _, id in ipairs(hidden) do
        line = line .. id .. ","
        if #line > 140 then o[#o + 1] = line .. "\n"; line = "" end
    end
    if #line > 0 then o[#o + 1] = line .. "\n" end
    o[#o + 1] = "}\n-- item id -> { [creature id] = chance in percent }: the chance a creature drops an item\n"
    o[#o + 1] = "ns.dataset.drops = {}\nlocal D = ns.dataset.drops\n"
    local written = 0
    for _, item in ipairs(itemIds) do
        local npcIds = {}
        for npc in pairs(items[item]) do npcIds[#npcIds + 1] = npc end
        table.sort(npcIds)
        local parts = {}
        for _, npc in ipairs(npcIds) do
            local r = rate(item, npc)
            if r then
                parts[#parts + 1] = string.format("[%d]=%s", npc, (r % 1 == 0) and string.format("%d", r) or string.format("%.2f", r))
                written = written + 1
            end
        end
        if #parts > 0 then o[#o + 1] = string.format("D[%d]={%s}\n", item, table.concat(parts, ",")) end
    end
    W("Extra1.lua", table.concat(o))
    print("drop pairs", written)
end

--------------------------------------------------------------------------------
-- Quest tags: Questie's own corrections, plus what the game itself said before for the few quests no correction covers
--------------------------------------------------------------------------------
do
    local QDBmod = QuestieLoader:CreateModule("QuestieDB"); QDBmod.private = {}
    local L10N = QuestieLoader:CreateModule("l10n"); setmetatable(L10N, { __call = function(_, s) return s end })
    local TR = QuestieLoader:CreateModule("TitanReforgedQuestTags")
    setmetatable(TR, { __index = function() return function() return {} end end })
    dofile(Q .. "Database/Corrections/questTagInfoCorrections.lua")
    QDBmod.private.InitializeQuestTagInfoCorrections()
    local tagFix = QDBmod.private.questTagCorrections
    -- tags the game's own answer gave in the last in-game export, where no correction exists
    local oldTags = {}
    local f = io.open(here .. "/../ForeverLazy-tags.lua", "rb")
    if f then
        f:close()
        ForeverLazyDB = nil; dofile(here .. "/../ForeverLazy-tags.lua")
        for id, tag in ForeverLazyDB.exportTags:gmatch("(%d+)=(%-?%d+)") do oldTags[tonumber(id)] = tonumber(tag) end
        ForeverLazyDB = nil
    end
    local tags, carried = {}, 0
    for id in pairs(dump.quests) do
        local c = tagFix[id]
        if c and tonumber(c[1]) then tags[id] = tonumber(c[1])
        elseif oldTags[id] then tags[id] = oldTags[id]; carried = carried + 1 end
    end
    local ids = {}
    for id in pairs(tags) do ids[#ids + 1] = id end
    table.sort(ids)
    local o = {}
    o[#o + 1] = "-- Quests the game's data hides by its own settings (Ahn'Qiraj war effort, invasion events), and quest tags. Generated, do not edit.\n"
    o[#o + 1] = "local ADDON, ns = ...\nns.dataset.hiddenGroups = {\n"
    local names = {}
    for name in pairs(groups) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do o[#o + 1] = "  " .. name .. " = {" .. groups[name] .. "},\n" end
    o[#o + 1] = "}\n-- quest id -> tag id (81 dungeon, 62 raid, 41 pvp, 1 group, 85 heroic ...)\n"
    o[#o + 1] = "ns.dataset.tags = {}\nlocal T = ns.dataset.tags\n"
    local line = ""
    for _, id in ipairs(ids) do
        line = line .. "T[" .. id .. "]=" .. tags[id] .. ";"
        if #line > 140 then o[#o + 1] = line .. "\n"; line = "" end
    end
    if #line > 0 then o[#o + 1] = line .. "\n" end
    W("Extra2.lua", table.concat(o))
    print("tags", #ids, "carried from the game's old answers", carried)
end

--------------------------------------------------------------------------------
-- Zones: area id -> map id for every area the data set mentions, and the dungeon list
--------------------------------------------------------------------------------
do
    local ZoneDB = Lib.Support.Get("ZoneDB")
    local priv = assert(ZoneDB and ZoneDB.private, "no zone support data")
    local function decode(v) if type(v) == "string" then return load(v)() or {} end return v or {} end
    local area = decode(priv.areaIdToUiMapId)
    for k, v in pairs(decode(priv.areaIdToUiMapIdOverride)) do area[k] = v end
    local ids = {}
    local function Add(id) if type(id) == "number" and id > 0 then ids[id] = true end end
    for _, kind in ipairs({ "npcs", "objects" }) do
        local at = fieldIndex(kind, "spawns")
        for _, text in pairs(dump[kind]) do
            local rec = load("return " .. text)()
            if type(rec[at]) == "table" then for areaId in pairs(rec[at]) do Add(areaId) end end
        end
    end
    local zAt = fieldIndex("quests", "zoneOrSort")
    for _, text in pairs(dump.quests) do local r = load("return " .. text)(); Add(r[zAt]) end
    for id in pairs(decode(priv.areaIdToUiMapId)) do Add(id) end
    for id in pairs(decode(priv.areaIdToUiMapIdOverride)) do Add(id) end
    local map, pieces = {}, {}
    for id in pairs(ids) do if area[id] then map[id] = area[id] end end
    local keys = {}
    for id in pairs(map) do keys[#keys + 1] = id end
    table.sort(keys)
    for _, id in ipairs(keys) do pieces[#pieces + 1] = "[" .. id .. "]=" .. map[id] end
    -- the dungeon list, as a Lua literal (the same writer the in-game export used)
    local function Lit(v, depth)
        local t = type(v)
        if t == "nil" then return "nil" end
        if t == "number" then
            if v == math.floor(v) then return string.format(math.abs(v) < 2147483648 and "%d" or "%.0f", v) end
            return string.format("%.4g", v)
        end
        if t == "boolean" then return v and "true" or "false" end
        if t == "string" then return string.format("%q", v) end
        if t == "table" then
            depth = (depth or 0) + 1
            if depth > 8 then return "nil" end
            local parts, n = {}, 0
            local isArray = true
            for _ in pairs(v) do n = n + 1 end
            for i = 1, n do if v[i] == nil then isArray = false; break end end
            if isArray then for i = 1, n do parts[i] = Lit(v[i], depth) end
            else
                local ks = {}
                for k in pairs(v) do ks[#ks + 1] = k end
                table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
                for _, k in ipairs(ks) do
                    local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
                    parts[#parts + 1] = key .. "=" .. Lit(v[k], depth)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        return "nil"
    end
    -- the dungeon table is built from dungeons.lua, which fixes a few entries by the player's side; the Alliance side is used
    local dungeons = priv.dungeons
    W("Zones.lua", "-- Area id -> map id, and the dungeon list, as the game's zone data answers them. Generated, do not edit.\n" ..
        "local ADDON, ns = ...\nns.dataset.zones = {\n  areaToMap = {" .. table.concat(pieces, ",") .. "},\n  dungeons = " ..
        (dungeons and Lit(dungeons) or "nil") .. ",\n}\n")
    print("areas", #keys, "dungeons", dungeons and count(dungeons) or 0)
end

--------------------------------------------------------------------------------
-- Townsfolk: the service lists, built the way Questie's Townsfolk module builds them
--------------------------------------------------------------------------------
do
    local QDBmod = QuestieLoader:ImportModule("QuestieDB")
    QDBmod.npcFlags = Lib.Enum.npcFlags
    QDBmod.NPCPointers = Lib.Npc.GetAllIds(true)
    QDBmod.ItemPointers = Lib.Item.GetAllIds(true)
    QDBmod.ObjectPointers = Lib.Object.GetAllIds(true)
    QDBmod.QueryNPCSingle = Lib.Npc.Get
    QDBmod.QueryItemSingle = Lib.Item.Get
    QDBmod.QueryObjectSingle = Lib.Object.Get
    QDBmod.factionTemplate = Lib.Support.Get("QuestieDB").factionTemplate
    -- the Lua 5.1 bit library
    bit = { band = function(a, b) return (math.floor(a) & math.floor(b)) end }
    UnitClassBase = function() return "MAGE" end          -- not a hunter: the pet food lists stay empty, as in the last export
    UnitFactionGroup = function() return "Alliance" end
    local prof = QuestieLoader:CreateModule("QuestieProfessions")
    -- the profession keys: Questie's own list, read from the module file's table
    local pf = io.open(Q .. "Modules/QuestieProfessions.lua", "rb"); local ptext = pf:read("*a"); pf:close()
    local keys = ptext:match("professionKeys%s*=%s*(%b{})")
    prof.professionKeys = keys and load("return " .. keys)() or {}
    setmetatable(QuestieLoader:CreateModule("QuestieCompat"), { __index = function() return function() end end })
    local T = QuestieLoader:CreateModule("Townsfolk")
    for _, f in ipairs({ "ClassTrainers", "Mailboxes", "MeetingStones", "WeaponTrainers" }) do
        local ok, e = pcall(dofile, Q .. "Modules/QuestieMenu/" .. f .. ".lua")
        if not ok then error("Townsfolk support file " .. f .. ": " .. tostring(e)) end
    end
    dofile(Q .. "Modules/QuestieMenu/Townsfolk.lua")
    for _, f in ipairs({ "Alchemy", "Archaeology", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "FirstAid", "Fishing",
                         "Herbalism", "Inscription", "Jewelcrafting", "Leatherworking", "Mining", "Riding", "Skinning", "Tailoring" }) do
        local ok, e = pcall(dofile, Q .. "Modules/QuestieMenu/ProfessionTrainers/" .. f .. "Trainers.lua")
        if not ok then error("profession trainers " .. f .. ": " .. tostring(e)) end
    end
    local co = coroutine.create(T.Initialize)
    repeat
        local ok, e = coroutine.resume(co)
        if not ok then error("Townsfolk.Initialize: " .. tostring(e)) end
    until coroutine.status(co) == "dead"
    local function Lit(v, depth)
        local t = type(v)
        if t == "nil" then return "nil" end
        if t == "number" then return string.format(v == math.floor(v) and "%d" or "%.4g", v) end
        if t == "boolean" then return v and "true" or "false" end
        if t == "string" then return string.format("%q", v) end
        if t == "table" then
            local parts, n = {}, 0
            local isArray = true
            for _ in pairs(v) do n = n + 1 end
            for i = 1, n do if v[i] == nil then isArray = false; break end end
            if isArray then for i = 1, n do parts[i] = Lit(v[i]) end
            else
                local ks = {}
                for k in pairs(v) do ks[#ks + 1] = k end
                table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
                for _, k in ipairs(ks) do
                    local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
                    parts[#parts + 1] = key .. "=" .. Lit(v[k])
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        return "nil"
    end
    local o = { "-- Service lists (vendors, trainers, innkeepers ...) as the game's data built them. Generated, do not edit.\n",
                "local ADDON, ns = ...\nns.dataset.townsfolk = {\n" }
    local set = { townsfolk = T.townsfolk, professionTrainers = T.professionTrainers, classSpecificTownsfolk = T.classSpecificTownsfolk,
                  factionSpecificTownsfolk = T.factionSpecificTownsfolk, petFoodVendorTypes = T.petFoodVendorTypes, professionKeys = prof.professionKeys }
    for _, k in ipairs({ "townsfolk", "professionTrainers", "classSpecificTownsfolk", "factionSpecificTownsfolk", "petFoodVendorTypes", "professionKeys" }) do
        o[#o + 1] = "  " .. k .. " = " .. Lit(set[k] or {}) .. ",\n"
    end
    o[#o + 1] = "}\n"
    W("Townsfolk.lua", table.concat(o))
    local cats = 0
    for _ in pairs(T.townsfolk) do cats = cats + 1 end
    print("townsfolk categories", cats)
end
