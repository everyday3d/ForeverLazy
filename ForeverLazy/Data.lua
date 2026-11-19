-- The one door to quest and world data (quests, NPCs, objects, items, XP, zones).
-- Every other file asks for data here and never reaches for Questie itself. See docs/QUESTIE-INDEPENDENCE.md.
--
--   ns.data.Module(name)      a module of the data source ("QuestXP", "ZoneDB", "AvailableQuests", "Townsfolk", ...) or nil
--   ns.data.QuestXP(id)       the XP a quest gives me now, 0 when unknown
--   ns.data.Available()       table whose keys are the ids of quests I may pick up, or nil
--   ns.data.Source()          name of the source in use, for messages
--   ns.data.Record(kind, id)  a record of our own data set (data\*.lua), kind = quests | npcs | objects | items
--   ns.data.Field(kind, id, field)
local ADDON, ns = ...

local data = {}
ns.data = data

-- Our own data set: the data\*.lua files fill this. Each record is kept as text and parsed when asked for.
ns.dataset = { quests = {}, npcs = {}, objects = {}, items = {}, fields = {}, count = {} }
local DS = ns.dataset

local function Loader()
    -- db.noQuestie pretends the source is not installed (to test that the addon works without it)
    local db = ns.addon and ns.addon.GetDB and ns.addon.GetDB()
    if db and db.noQuestie then return nil end
    return _G.QuestieLoader
end

local DataFirst   -- defined below: true when our own data set is asked before the source

-- our own zone module: the two things the addon asks the source's zone data (area id -> map id, and the dungeon list)
local ownZone = {
    GetUiMapIdByAreaId = function(_, areaId)
        local z = DS.zones
        return z and z.areaToMap and z.areaToMap[areaId] or nil
    end,
    GetDungeons = function()
        local z = DS.zones
        return z and z.dungeons or nil
    end,
}

function data.Module(name)
    local ql = Loader()
    local real
    if ql and name then
        local ok, m = pcall(ql.ImportModule, ql, name)
        real = ok and m or nil
    end
    if name == "ZoneDB" and DS.zones and (DataFirst() or not real) then return ownZone end
    if name == "QuestiePlayer" and not real then return data.OwnPlayer() end
    if name == "QuestXP" and not real then return data.OwnXPModule() end
    if name == "QuestieDB" and not real and next(DS.quests) then return data.Database() end
    if name == "Townsfolk" and DS.townsfolk and (DataFirst() or not real) then return DS.townsfolk end
    if name == "QuestieProfessions" and DS.townsfolk and (DataFirst() or not real) then
        return { professionKeys = DS.townsfolk.professionKeys }
    end
    return real
end

function data.Present()
    return Loader() ~= nil
end

-- Temporary XP bonuses on me, added to the base amount (the game shows them in the quest reward). Like the source, it is not
-- worked out in combat or in an instance, where the game hides aura details from addons.
local XP_BUFFS = { [377749] = 0.5, [46668] = 0.1, [95987] = 0.1, [24705] = 0.1 }   -- Joyous Journeys, Darkmoon Faire, Hallow's End
local SLEEPING_BAG = 429959                                                      -- Well-Rested from the sleeping bag: 1% a stack
local function BuffMultiplier()
    if (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) then return 0 end
    local sum = 0
    for i = 1, 40 do
        local stacks, spellId
        if UnitAura then
            local _, _, count, _, _, _, _, _, _, id = UnitAura("player", i, "HELPFUL")
            stacks, spellId = count, id
        elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if a then stacks, spellId = a.applications, a.spellId end
        end
        if not spellId then break end
        if XP_BUFFS[spellId] then sum = sum + XP_BUFFS[spellId]
        elseif spellId == SLEEPING_BAG then sum = sum + 0.01 * (stacks or 1) end
    end
    return sum
end

-- XP a quest gives me now, from our own table (quest level and XP at that level, scaled for my level the way the game does)
local function OwnQuestXP(id)
    local row = DS.xp and DS.xp[id]
    if not row then return nil end
    local qLevel, xp = row[1], row[2]
    if not (qLevel and xp and qLevel > 0 and xp > 0) then return 0 end
    local me = UnitLevel and UnitLevel("player") or 1
    if GetMaxPlayerLevel and me >= GetMaxPlayerLevel() then return 0 end
    local mult = 2 * (qLevel - me) + 20
    if mult < 1 then mult = 1 elseif mult > 10 then mult = 10 end
    xp = xp * mult / 10
    local floor = math.floor
    if xp <= 100 then xp = 5 * floor((xp + 2) / 5)
    elseif xp <= 500 then xp = 10 * floor((xp + 5) / 10)
    elseif xp <= 1000 then xp = 25 * floor((xp + 12) / 25)
    else xp = 50 * floor((xp + 25) / 50) end
    return floor(xp * (1 + BuffMultiplier()))
end
data.OwnQuestXP = OwnQuestXP

local function SourceQuestXP(id)
    local mod = data.Module("QuestXP")
    if not (mod and mod.GetQuestLogRewardXP) then return nil end
    local ok, xp = pcall(mod.GetQuestLogRewardXP, mod, id, false)
    return ok and tonumber(xp) or nil
end

function data.QuestXP(id)
    if DataFirst() then
        local v = OwnQuestXP(id)
        if v and v > 0 then return v end
    end
    local v = SourceQuestXP(id)
    if v and v > 0 then return v end
    return OwnQuestXP(id) or v or 0
end

function data.Available()
    local aq = data.Module("AvailableQuests")
    local avail = aq and aq.__availableQuests
    -- our own list when the data set is asked first, or when the source has none
    if (DataFirst() or type(avail) ~= "table") and data.ComputeAvailable then
        local ok, mine = pcall(data.ComputeAvailable)
        if ok and type(mine) == "table" then return mine end
    end
    if type(avail) == "table" then return avail end
    return nil
end

--------------------------------------------------------------------------------
-- Our own data set
--------------------------------------------------------------------------------
local parsed = { quests = {}, npcs = {}, objects = {}, items = {} }
local fieldIndex = {}

local function Index(kind)
    local idx = fieldIndex[kind]
    if idx then return idx end
    idx = {}
    for i, name in ipairs(DS.fields[kind] or {}) do idx[name] = i end
    fieldIndex[kind] = idx
    return idx
end

function data.Record(kind, id)
    local cache = parsed[kind]
    if not (cache and id) then return nil end
    local rec = cache[id]
    if rec ~= nil then return rec or nil end
    local text = DS[kind][id]
    if not text then cache[id] = false; return nil end
    local fn = (loadstring or load)("return " .. text)
    if not fn then cache[id] = false; return nil end
    local ok, r = pcall(fn)
    rec = ok and type(r) == "table" and r or false
    cache[id] = rec
    return rec or nil
end

-- true when the data set has this field at all (a field it does not carry is left to the source)
function data.HasField(kind, field)
    return Index(kind)[field] ~= nil
end

function data.Field(kind, id, field)
    local i = Index(kind)[field]
    if not i then return nil end
    local rec = data.Record(kind, id)
    return rec and rec[i]
end

function data.DatasetSize()
    return DS.count.quests or 0, DS.count.npcs or 0, DS.count.objects or 0, DS.count.items or 0
end

--------------------------------------------------------------------------------
-- The database every other file queries (api.GetQuestie() returns this). Lookups go through the Query* functions below:
--   * what I saw in the game myself (ForeverLazyDB.own, written by Learn.lua) is used first for a few facts the game is the
--     authority on (a quest's or creature's name and level);
--   * then the data source (Questie), or our own data set first when db.dataFirst is on (to try it out);
--   * what I learned and our data set fill the gaps when the source has nothing.
-- Everything else (pointer tables, IsTrivial, ...) passes straight through to the source. /lazy data shows the counts.
--------------------------------------------------------------------------------
local stats = { own = 0, source = 0, filled = 0, set = 0, setfill = 0, none = 0 }
-- ids neither side knew, by kind, with the field asked: { quests = { [id] = { count, field } }, npcs = ... } (capped)
local misses = { quests = {}, npcs = {}, nq = 0, nn = 0 }
function data.Misses() return misses end
local function Miss(bucket, id, field)
    local m = misses[bucket]
    if not m then return end
    local r = m[id]
    if r then r[1] = r[1] + 1; return end
    local cnt = bucket == "quests" and "nq" or "nn"
    if misses[cnt] >= 3000 then return end
    misses[cnt] = misses[cnt] + 1
    m[id] = { 1, field }
end
function data.Stats() return stats end

local function OwnOn()
    local root = _G.ForeverLazyDB
    if type(root) ~= "table" or not root.own then return nil end
    local db = ns.addon and ns.addon.GetDB and ns.addon.GetDB()
    if db and db.useOwnData == false then return nil end
    return root.own
end

function DataFirst()
    local db = ns.addon and ns.addon.GetDB and ns.addon.GetDB()
    return db and db.dataFirst == true
end

-- how my own record looks in the shape the source uses
local OWN_QUEST = {
    name = function(q) return q.name end,
    questLevel = function(q) return q.level end,
    groupSize = function(q) return q.group end,
    suggestedGroup = function(q) return q.group end,
    startedBy = function(q) return q.startedBy and { q.startedBy } or nil end,
    finishedBy = function(q) return q.finishedBy and { q.finishedBy } or nil end,
}
local OWN_NPC = {
    name = function(n) return n.name end,
    minLevel = function(n) return n.minLevel end,
    maxLevel = function(n) return n.maxLevel end,
    questStarts = function(n) return n.gives end,
    questEnds = function(n) return n.takes end,
}
local NO_SHAPES = {}
-- facts where what I saw in the game wins over the source
local OWN_FIRST = { name = true, questLevel = true, minLevel = true, maxLevel = true }

local function Wrap(fn, bucket, shapes)
    shapes = shapes or NO_SHAPES
    return function(id, field, ...)
        local own = OwnOn()
        local rec, shape = own and own[bucket] and own[bucket][id], shapes[field]
        if rec and shape and OWN_FIRST[field] then
            local v = shape(rec)
            if v ~= nil then stats.own = stats.own + 1; return v end
        end
        if DataFirst() then
            local v = data.Field(bucket, id, field)
            if v ~= nil then stats.set = stats.set + 1; return v end
        end
        local v = fn(id, field, ...)
        if v ~= nil then stats.source = stats.source + 1; return v end
        if rec and shape then
            local o = shape(rec)
            if o ~= nil then stats.filled = stats.filled + 1; return o end
        end
        local d = data.Field(bucket, id, field)
        if d ~= nil then stats.setfill = stats.setfill + 1; return d end
        stats.none = stats.none + 1
        if type(id) == "number" then Miss(bucket, id, field) end
        return nil
    end
end

-- the player's race and class against a requirement mask
local function MaskHas(mask, n)
    if not mask or mask == 0 then return true end
    if not n then return true end
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end
local ownPlayer = {
    HasRequiredRace = function(mask) return MaskHas(mask, select(3, UnitRace("player"))) end,
    HasRequiredClass = function(mask) return MaskHas(mask, select(3, UnitClass("player"))) end,
}
function data.OwnPlayer() return ownPlayer end
local ownXP = { GetQuestLogRewardXP = function(_, id) return OwnQuestXP(id) or 0 end }
function data.OwnXPModule() return ownXP end

-- how often a creature drops an item, from our own table (the same answer shape as the source: { percent, where from })
function data.DropRate(itemId, npcId)
    local d = DS.drops and DS.drops[itemId]
    local r = d and d[npcId]
    if r then return { r, "data" } end
    return nil
end

-- The database object when the source is not there: the same Query* calls and pointer tables, answered from our data set.
local ownDB
function data.Database()
    if ownDB then return ownDB end
    local none = function() return nil end
    ownDB = {
        isOwnDatabase = true,
        QuestPointers = DS.quests, NPCPointers = DS.npcs, ObjectPointers = DS.objects, ItemPointers = DS.items,
        QueryQuestSingle = Wrap(none, "quests", OWN_QUEST),
        QueryNPCSingle = Wrap(none, "npcs", OWN_NPC),
        QueryObjectSingle = Wrap(none, "objects"),
        QueryItemSingle = Wrap(none, "items"),
        -- grey quest: more than the green range below my level
        IsTrivial = function(level)
            if level == nil or level == -1 then return false end
            local diff = level - (UnitLevel and UnitLevel("player") or 1)
            if diff >= -2 then return false end
            local green = 8
            if C_QuestLog and C_QuestLog.GetTrivialRange then
                local ok, v = pcall(C_QuestLog.GetTrivialRange)
                if ok and tonumber(v) then green = tonumber(v) end
            elseif GetQuestGreenRange then
                green = tonumber(GetQuestGreenRange("player")) or green
            end
            return -diff > green
        end,
        IsFriendlyToPlayer = function(f)
            if not f or f == "AH" then return true end
            local faction = UnitFactionGroup and UnitFactionGroup("player")
            if f == "H" then return faction == "Horde" end
            if f == "A" then return faction == "Alliance" end
            return false
        end,
        IsDoable = function(id) return data.WhyNotNow and data.WhyNotNow(id) == nil end,
        GetItemDroprate = function(itemId, npcId) return data.DropRate(itemId, npcId) end,
        GetQuestTagInfo = function(id)
            local tags = DS.tags
            return tags and tags[id] or nil
        end,
    }
    return ownDB
end
function data.HaveDataset() return next(DS.quests) ~= nil end

local facade, facadeFor
function data.Facade(src)
    if not src then return nil end
    if src.isOwnDatabase then return src end
    if facade and facadeFor == src then return facade end
    local f = setmetatable({}, { __index = src })
    if src.QueryQuestSingle then f.QueryQuestSingle = Wrap(src.QueryQuestSingle, "quests", OWN_QUEST) end
    if src.QueryNPCSingle then f.QueryNPCSingle = Wrap(src.QueryNPCSingle, "npcs", OWN_NPC) end
    if src.QueryObjectSingle then f.QueryObjectSingle = Wrap(src.QueryObjectSingle, "objects") end
    if src.QueryItemSingle then f.QueryItemSingle = Wrap(src.QueryItemSingle, "items") end
    if src.GetItemDroprate then
        local fn = src.GetItemDroprate
        f.GetItemDroprate = function(itemId, npcId)
            local ok, r = pcall(fn, itemId, npcId)
            if ok and r then return r end
            return data.DropRate(itemId, npcId)
        end
    end
    facade, facadeFor = f, src
    return f
end

--------------------------------------------------------------------------------
-- Does our data set agree with the source? Looks at a sample and returns lines to print.
--------------------------------------------------------------------------------
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) == "number" then return math.abs(a - b) <= math.max(0.011, math.abs(a) * 1e-3) end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function Show(v, depth)
    depth = depth or 0
    if type(v) == "table" then
        if depth > 1 then return "{...}" end
        local parts, n = {}, 0
        for k, x in pairs(v) do
            n = n + 1
            if n > 4 then parts[#parts + 1] = "..."; break end
            parts[#parts + 1] = tostring(k) .. "=" .. Show(x, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

function data.Verify(perKind)
    local out = {}
    local src = data.Module("QuestieDB")
    if not src then out[1] = "the data source is not loaded, nothing to compare with"; return out end
    perKind = perKind or 300
    local QUERY = { quests = "QueryQuestSingle", npcs = "QueryNPCSingle", objects = "QueryObjectSingle", items = "QueryItemSingle" }
    local POINTERS = { quests = "QuestPointers", npcs = "NPCPointers", objects = "ObjectPointers", items = "ItemPointers" }
    for _, kind in ipairs({ "quests", "npcs", "objects", "items" }) do
        local have = DS.count[kind] or 0
        local srcCount = 0
        local ptr = src[POINTERS[kind]]
        if type(ptr) == "table" then for _ in pairs(ptr) do srcCount = srcCount + 1 end end
        -- ids the source has that the data set does not
        local missing = 0
        if type(ptr) == "table" then for id in pairs(ptr) do if not DS[kind][id] then missing = missing + 1 end end end
        local ids = {}
        for id in pairs(DS[kind]) do ids[#ids + 1] = id end
        local sample, same, diff, examples = math.min(perKind, #ids), 0, 0, {}
        for _ = 1, sample do
            local id = ids[math.random(#ids)]
            for _, field in ipairs(DS.fields[kind] or {}) do
                local okS, sv = pcall(src[QUERY[kind]], id, field)
                local dv = data.Field(kind, id, field)
                if okS and Same(sv, dv) then same = same + 1
                elseif okS and sv == nil and dv == nil then same = same + 1
                else
                    diff = diff + 1
                    if #examples < 3 then examples[#examples + 1] = string.format("   %s %s.%s: source %s, ours %s", kind, tostring(id), field, Show(sv), Show(dv)) end
                end
            end
        end
        out[#out + 1] = string.format("%s: ours %d, source %d (%d the source has that we lack). Compared %d records: %d fields equal, %d differ",
            kind, have, srcCount, missing, sample, same, diff)
        for _, e in ipairs(examples) do out[#out + 1] = e end
    end
    -- zones: area id -> map id, and the dungeon list
    local ql = Loader()
    local okZ, realZ = false, nil
    if ql then okZ, realZ = pcall(ql.ImportModule, ql, "ZoneDB") end
    if okZ and realZ and realZ.GetUiMapIdByAreaId and DS.zones then
        local n, bad, ex = 0, 0, {}
        for areaId, ui in pairs(DS.zones.areaToMap or {}) do
            local ok, sv = pcall(realZ.GetUiMapIdByAreaId, realZ, areaId)
            n = n + 1
            if not ok or sv ~= ui then
                bad = bad + 1
                if #ex < 3 then ex[#ex + 1] = string.format("   area %d: source %s, ours %s", areaId, tostring(sv), tostring(ui)) end
            end
        end
        local sd, od = 0, 0
        local okD, list = pcall(realZ.GetDungeons, realZ)
        if okD and type(list) == "table" then for _ in pairs(list) do sd = sd + 1 end end
        for _ in pairs(DS.zones.dungeons or {}) do od = od + 1 end
        out[#out + 1] = string.format("zones: %d areas compared, %d differ. Dungeons: source %d, ours %d", n, bad, sd, od)
        for _, e in ipairs(ex) do out[#out + 1] = e end
    end
    if data.VerifyAvailable then
        local okA, lines = pcall(data.VerifyAvailable)
        if okA and type(lines) == "table" then for _, l in ipairs(lines) do out[#out + 1] = l end end
    end
    -- drop chances: a sample of pairs against the source
    if src.GetItemDroprate and DS.drops then
        local pairsList = {}
        for item, npcs in pairs(DS.drops) do for npc in pairs(npcs) do pairsList[#pairsList + 1] = { item, npc } end end
        local n, bad, ex = 0, 0, {}
        for _ = 1, math.min(400, #pairsList) do
            local pr = pairsList[math.random(#pairsList)]
            local okD, sv = pcall(src.GetItemDroprate, pr[1], pr[2])
            local ov = data.DropRate(pr[1], pr[2])
            n = n + 1
            local s = okD and type(sv) == "table" and tonumber(sv[1]) or nil
            local o = ov and tonumber(ov[1]) or nil
            if not (s and o and math.abs(s - o) <= 0.011) then
                bad = bad + 1
                if #ex < 3 then ex[#ex + 1] = string.format("   item %d from creature %d: source %s, ours %s", pr[1], pr[2], tostring(s), tostring(o)) end
            end
        end
        out[#out + 1] = string.format("drop chances: %d pairs compared, %d differ", n, bad)
        for _, e in ipairs(ex) do out[#out + 1] = e end
    end
    -- service lists: the same ids in each list (the order differs from run to run, so lists are compared as sets)
    local okT, realT = false, nil
    if ql then okT, realT = pcall(ql.ImportModule, ql, "Townsfolk") end
    if okT and realT and realT.townsfolk and next(realT.townsfolk) and DS.townsfolk then
        local function Set(v)
            local s = {}
            if type(v) == "table" then for _, id in ipairs(v) do s[id] = true end end
            return s
        end
        local function SameSet(a, b)
            local x, y = Set(a), Set(b)
            for id in pairs(x) do if not y[id] then return false end end
            for id in pairs(y) do if not x[id] then return false end end
            return true
        end
        local lists, bad, ex = 0, 0, {}
        local function Cmp(label, a, b)
            lists = lists + 1
            if not SameSet(a, b) then
                bad = bad + 1
                if #ex < 3 then ex[#ex + 1] = string.format("   %s: source %d ids, ours %d", label, type(a) == "table" and #a or 0, type(b) == "table" and #b or 0) end
            end
        end
        for cat, ids in pairs(realT.townsfolk) do Cmp(cat, ids, DS.townsfolk.townsfolk[cat]) end
        for key, ids in pairs(realT.professionTrainers or {}) do Cmp("profession " .. tostring(key), ids, DS.townsfolk.professionTrainers[key]) end
        for cls, cats in pairs(realT.classSpecificTownsfolk or {}) do
            for cat, ids in pairs(cats) do Cmp(cls .. " " .. cat, ids, DS.townsfolk.classSpecificTownsfolk[cls] and DS.townsfolk.classSpecificTownsfolk[cls][cat]) end
        end
        for fac, cats in pairs(realT.factionSpecificTownsfolk or {}) do
            for cat, ids in pairs(cats) do Cmp(fac .. " " .. cat, ids, DS.townsfolk.factionSpecificTownsfolk[fac] and DS.townsfolk.factionSpecificTownsfolk[fac][cat]) end
        end
        out[#out + 1] = string.format("service lists: %d lists compared, %d differ", lists, bad)
        for _, e in ipairs(ex) do out[#out + 1] = e end
    end
    -- quest XP: our table against the source, for every quest the table has
    local mod = data.Module("QuestXP")
    if mod and mod.GetQuestLogRewardXP and DS.xp then
        local n, bad, ex = 0, 0, {}
        for id in pairs(DS.xp) do
            local ok, sv = pcall(mod.GetQuestLogRewardXP, mod, id, false)
            local ov = OwnQuestXP(id)
            n = n + 1
            if ok and tonumber(sv) ~= ov then
                bad = bad + 1
                if #ex < 3 then ex[#ex + 1] = string.format("   quest xp %d: source %s, ours %s", id, tostring(sv), tostring(ov)) end
            end
        end
        out[#out + 1] = string.format("quest XP at my level: %d quests compared, %d differ", n, bad)
        for _, e in ipairs(ex) do out[#out + 1] = e end
    end
    return out
end

function data.Source()
    return "Questie"
end

-- reached the end of the file without an error (used by /lazy check)
do
    local ns2 = select(2, ...)
    if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Data.lua"] = true end
end
