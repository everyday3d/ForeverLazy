-- Offline reader for the QuestieDB data file (the "baked" TOC store), so the quest data can be rebuilt without the game.
-- It loads QuestieDB's own Lua files in the order its TOC lists them, with stand-ins for the few game functions it needs,
-- and answers the same way Questie does (QuestieDB.QueryQuestSingle is LibQuestieDB.Quest.Get).
--   lua qdb_offline.lua <QuestieDB folder> <ForeverLazy folder> <out file>
local DBDIR, FLDIR, OUT = arg[1], arg[2], arg[3]
assert(DBDIR and FLDIR and OUT, "usage: lua qdb_offline.lua <QuestieDB folder> <ForeverLazy folder> <out file>")
DBDIR = DBDIR:gsub("\\", "/"):gsub("/$", "")
FLDIR = FLDIR:gsub("\\", "/"):gsub("/$", "")

-- LibStub + LibDeflate (ours) for the decompression
dofile(FLDIR .. "/libs/LibStub/LibStub.lua")
dofile(FLDIR .. "/libs/LibDeflate/LibDeflate.lua")
local LD = LibStub("LibDeflate")

-- the TOC: metadata (key -> value) and the file list -------------------------------------------------
local meta, files = {}, {}
for line in io.lines(DBDIR .. "/QuestieDB_Forever.toc") do
    line = line:gsub("\r$", "")
    local k, v = line:match("^## ([^:]+):%s?(.*)$")
    if k then meta[k] = v
    elseif line ~= "" and not line:find("^#") then files[#files + 1] = line end
end

-- base64 ---------------------------------------------------------------------------------------------
local b64 = {}
do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #chars do b64[chars:byte(i)] = i - 1 end
end
local function DecodeBase64(s)
    local out, n = {}, 0
    local bits, nbits = 0, 0
    for i = 1, #s do
        local v = b64[s:byte(i)]
        if v then
            bits = (bits << 6) | v; nbits = nbits + 6
            if nbits >= 8 then
                nbits = nbits - 8
                n = n + 1; out[n] = string.char((bits >> nbits) & 0xFF)
                bits = bits & ((1 << nbits) - 1)
            end
        end
    end
    return table.concat(out)
end

-- CBOR -----------------------------------------------------------------------------------------------
local function DeserializeCBOR(s)
    local pos = 1
    local function need(n) assert(pos + n - 1 <= #s, "cbor: short data") end
    local function uint(info)
        if info < 24 then return info end
        local n = ({ [24] = 1, [25] = 2, [26] = 4, [27] = 8 })[info]
        assert(n, "cbor: bad length " .. tostring(info))
        need(n)
        local v = 0
        for i = 1, n do v = v * 256 + s:byte(pos + i - 1) end
        pos = pos + n
        return v
    end
    local decode
    function decode()
        need(1)
        local b = s:byte(pos); pos = pos + 1
        local major, info = b >> 5, b & 31
        if major == 0 then return uint(info)
        elseif major == 1 then return -1 - uint(info)
        elseif major == 2 or major == 3 then
            local n = uint(info); need(n)
            local str = s:sub(pos, pos + n - 1); pos = pos + n
            return str
        elseif major == 4 then
            local n = uint(info); local t = {}
            for i = 1, n do t[i] = decode() end
            return t
        elseif major == 5 then
            local n = uint(info); local t = {}
            for _ = 1, n do local k = decode(); t[k] = decode() end
            return t
        elseif major == 6 then
            uint(info); return decode()
        else
            if info == 20 then return false elseif info == 21 then return true elseif info == 22 or info == 23 then return nil end
            if info == 25 then
                need(2); local h = s:byte(pos) * 256 + s:byte(pos + 1); pos = pos + 2
                local sign, e, f = (h >> 15), (h >> 10) & 31, h & 1023
                local v
                if e == 0 then v = f * 2 ^ -24 elseif e == 31 then v = (f == 0) and math.huge or 0 / 0 else v = (1 + f / 1024) * 2 ^ (e - 15) end
                return sign == 1 and -v or v
            elseif info == 26 then need(4); local v = string.unpack(">f", s, pos); pos = pos + 4; return v
            elseif info == 27 then need(8); local v = string.unpack(">d", s, pos); pos = pos + 8; return v end
            error("cbor: unsupported simple value " .. info)
        end
    end
    return decode()
end

-- the game's functions that QuestieDB touches --------------------------------------------------------
local function DecompressString(data, method)
    local out = LD:DecompressZlib(data)
    if out then return out end
    out = LD:DecompressDeflate(data)
    assert(out, "could not decompress")
    return out
end
C_EncodingUtil = { DecodeBase64 = DecodeBase64, DecompressString = DecompressString, DeserializeCBOR = DeserializeCBOR }
C_AddOns = { GetAddOnMetadata = function(_, key) return meta[key] end }
GetAddOnMetadata = C_AddOns.GetAddOnMetadata
GetLocale = function() return "enUS" end
GetBuildInfo = function() return "1.15.0", "0", "Jan 1 2025", 16001 end
UnitFactionGroup = function() return "Alliance" end
-- anything else asked for is a harmless stand-in (tables that answer every call), so loading never stops on a game function
local standIn
standIn = setmetatable({}, { __index = function() return standIn end, __call = function() return standIn end })
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" and (k:find("^C_") or k:find("^Enum$") or k:find("^Create") or k:find("^Get") or k:find("^Unit") or k:find("^Is")) then return standIn end
end })
strsplit = strsplit or function(sep, s, n) local r = {}; for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do r[#r + 1] = p end return table.unpack(r) end
wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert; tremove = table.remove
format = string.format; strfind = string.find; strmatch = string.match; gsub = string.gsub; strsub = string.sub; strlen = string.len
strlower = string.lower; strupper = string.upper; strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
floor = math.floor; max = math.max; min = math.min; abs = math.abs
issecretvalue = function() return false end
debugprofilestop = function() return os.clock() * 1000 end
hooksecurefunc = function() end

-- load QuestieDB's files, in the TOC's order ---------------------------------------------------------
local LibQuestieDB = {}
for _, f in ipairs(files) do
    local path = DBDIR .. "/" .. f:gsub("\\", "/")
    local chunk, err = loadfile(path)
    if not chunk then error("could not load " .. f .. ": " .. tostring(err)) end
    local ok, e = pcall(chunk, "QuestieDB", LibQuestieDB)
    if not ok then error("error in " .. f .. ": " .. tostring(e)) end
end
_G.LibQuestieDB = LibQuestieDB

-- another script can use this one as a library: set QDB_LIBRARY_ONLY first, and dofile returns LibQuestieDB
if rawget(_G, "QDB_LIBRARY_ONLY") then return LibQuestieDB end

-- the dump, in the same shape as the in-game /lazy data export --------------------------------------
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
local ENTITY = { quests = "Quest", npcs = "Npc", objects = "Object", items = "Item" }

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

local dump = { version = 1, fields = FIELDS, count = {}, source = "offline" }
for _, kind in ipairs({ "quests", "npcs", "objects", "items" }) do
    local E = assert(LibQuestieDB[ENTITY[kind]], "no entity " .. ENTITY[kind])
    local idList = E.GetAllIds()
    local ids = {}
    for _, id in ipairs(idList) do ids[#ids + 1] = id end
    table.sort(ids)
    dump[kind] = {}
    dump.count[kind] = #ids
    local store, list = dump[kind], FIELDS[kind]
    for _, id in ipairs(ids) do
        local vals, last = {}, 0
        for i, f in ipairs(list) do
            local ok, v = pcall(E.Get, id, f)
            if ok and v ~= nil then vals[i] = Lit(v); last = i end
        end
        local parts = {}
        for i = 1, last do parts[i] = vals[i] or "nil" end
        store[id] = "{" .. table.concat(parts, ",") .. "}"
    end
    io.stderr:write(string.format("%s: %d\n", kind, #ids))
end

-- written as the saved-variables file the converter already reads: ForeverLazyDB = { exportDump = ... }
local function Ser(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then
        local parts = {}
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local ks = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
            parts[#parts + 1] = ks .. "=" .. Ser(v[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end
local f = assert(io.open(OUT, "wb"))
f:write("ForeverLazyDB = { exportDump = ", Ser(dump), " }\n")
f:close()
print("written " .. OUT)
