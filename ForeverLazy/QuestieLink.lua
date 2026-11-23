-- Talking to people who run Questie: in a party or raid, Questie users send each other their quest progress. This file reads those
-- messages (so a mob or item tooltip can show what a Questie user in your group still needs), and, when Questie is not running on
-- this computer, sends our own progress in the same format, so they see ours.
--
-- The wire format (a small binary serializer) is ported from Questie (https://github.com/Questie/Questie, GPL-3.0, Modules/Libs/
-- QuestieSerializer.lua and Modules/QuestieStream.lua; the packet layouts are from Modules/Network/QuestieComms.lua).
-- It only talks to the group you are in, never to strangers, and every step is guarded so a bad message is dropped.
--   /lazy questie            status: who we have heard from, what we sent
--   /lazy questie off|on     stop or resume (default: on)
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local data = ns.data
local DS = ns.dataset
local Print = addon.Print

local PREFIX = "questie"
local MSG_VER = 5                     -- Questie compares the whole-number part
local FAKE_VER = "5.0.0"              -- what we call ourselves (an old number, so nobody is told to update because of us)
local ID_UPDATE, ID_REMOVE, ID_FULL, ID_REQUEST, ID_FULL_V2, ID_UPDATE_V2 = 1, 2, 10, 11, 12, 14

local function DB() return addon.GetDB() end

--------------------------------------------------------------------------------
-- Bytes: the "1short" stream (a zero byte is sent as 238, and 237/238 are escaped)
--------------------------------------------------------------------------------
local CONTROL, ZERO = 237, 238

local function Reader(bytes)
    local pos = 1
    local r = {}
    function r.raw()
        local v = bytes[pos]
        if v == nil then error("end of data") end
        pos = pos + 1
        return v
    end
    function r.byte()
        local v = r.raw()
        if v == ZERO then return 0 end
        if v == CONTROL then
            v = r.raw()
            if v == 1 then return CONTROL elseif v == 2 then return ZERO end
            error("bad escape")
        end
        return v
    end
    function r.short() return r.byte() * 256 + r.byte() end
    function r.int() return ((r.byte() * 256 + r.byte()) * 256 + r.byte()) * 256 + r.byte() end
    function r.long()
        local n = 0
        for _ = 1, 8 do n = n * 256 + r.byte() end
        return n
    end
    function r.string(len)
        local parts = {}
        for i = 1, len do parts[#parts + 1] = string.char(r.byte()) end
        return table.concat(parts)
    end
    return r
end

local function Writer()
    local out = {}
    local w = {}
    function w.byte(e)
        if e == CONTROL then out[#out + 1] = string.char(CONTROL, 1)
        elseif e == ZERO then out[#out + 1] = string.char(CONTROL, 2)
        elseif e == 0 then out[#out + 1] = string.char(ZERO)
        else out[#out + 1] = string.char(e) end
    end
    function w.short(v) w.byte(math.floor(v / 256) % 256); w.byte(v % 256) end
    function w.int(v)
        w.byte(math.floor(v / 16777216) % 256); w.byte(math.floor(v / 65536) % 256)
        w.byte(math.floor(v / 256) % 256); w.byte(v % 256)
    end
    function w.long(v)
        for shift = 7, 0, -1 do w.byte(math.floor(v / 256 ^ shift) % 256) end
    end
    function w.string(s) for i = 1, #s do w.byte(s:byte(i)) end end
    function w.result() return table.concat(out) end
    return w
end

--------------------------------------------------------------------------------
-- The serializer
--------------------------------------------------------------------------------
local function Hash(value)
    if type(value) ~= "string" or #value <= 0 then return 0 end
    local h = 5381
    for i = 1, #value do h = (31 * h + value:byte(i)) % 4294967296 end
    return h
end

local function IntBitsToFloat(n)
    local sign = (n >= 2147483648) and -1 or 1
    local exp = math.floor(n / 8388608) % 256
    local mant = n % 8388608
    if exp == 0 then return sign * mant * 2 ^ -149 end
    if exp == 255 then return mant == 0 and sign * math.huge or 0 / 0 end
    return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end

-- text (a string of bytes) -> Lua value; nil when it does not parse
local function Deserialize(text)
    if type(text) ~= "string" or #text < 2 or #text > 4096 then return nil end
    local bytes = {}
    for i = 1, #text do bytes[i] = text:byte(i) end
    local r = Reader(bytes)
    local hashes = {}                         -- hash -> string, learned while reading, like the sender's
    local function Learn(s)
        if type(s) == "string" then
            local h = Hash(s)
            if hashes[h] == nil then hashes[h] = s end
        end
    end
    local ReadObject
    local function ReadTable(count)
        local t = {}
        for _ = 1, count do
            local k = ReadObject(); Learn(k)
            local v = ReadObject(); Learn(v)
            if k ~= nil then t[k] = v end
        end
        return t
    end
    local function ReadArray(count)
        local t = {}
        for i = 1, count do
            local v = ReadObject(); Learn(v)
            t[i] = v
        end
        return t
    end
    local readers = {
        [1] = function() return nil end,
        [2] = function() return r.int() end, [3] = function() return -r.int() end,
        [4] = function() return r.long() end, [5] = function() return -r.long() end,
        [6] = function() return IntBitsToFloat(r.int()) end,
        [7] = function() return r.string(r.byte()) end,
        [8] = function() return r.string(r.short()) end,
        [9] = function() return hashes[r.int()] end,
        [10] = function() return ReadTable(r.byte()) end,
        [11] = function() return ReadTable(r.short()) end,
        [12] = function() return r.byte() end, [13] = function() return -r.byte() end,
        [14] = function() return r.short() end, [15] = function() return -r.short() end,
        [16] = function() return false end, [17] = function() return true end,
        [18] = function() return nil end, [19] = function() return nil end,
        [20] = function() return ReadArray(r.byte()) end,
        [21] = function() return ReadArray(r.short()) end,
        [22] = function() return ReadArray(r.int()) end,
    }
    local depth = 0
    ReadObject = function()
        local typ = r.byte()
        if typ > 31 then return typ - 32 end
        local fn = readers[typ]
        if not fn then error("unknown type " .. tostring(typ)) end
        depth = depth + 1
        if depth > 40 then error("too deep") end
        local v = fn()
        depth = depth - 1
        return v
    end
    local ok, result = pcall(function() return ReadTable(1)[1] end)
    if ok and type(result) == "table" then return result end
    return nil
end

local function IsArray(t)
    local n = 0
    for k in pairs(t) do
        n = n + 1
        if k ~= n then return false end
    end
    return true
end

local function Serialize(tab)
    local w = Writer()
    local function WriteValue(v, depth)
        local t = type(v)
        if t == "number" then
            local sign = v < 0 and 1 or 0
            v = math.abs(v)
            if v % 1 ~= 0 then error("this writer sends whole numbers only") end
            if v > 2147483646 then w.byte(4 + sign); w.long(v)
            elseif v < 222 and sign == 0 then w.byte(32 + v)
            elseif v < 255 then w.byte(12 + sign); w.byte(v)
            elseif v < 65530 then w.byte(14 + sign); w.short(v)
            else w.byte(2 + sign); w.int(v) end
        elseif t == "string" then
            if #v > 254 then w.byte(8); w.short(#v) else w.byte(7); w.byte(#v) end
            w.string(v)
        elseif t == "boolean" then
            w.byte(v and 17 or 16)
        elseif t == "table" then
            if depth > 20 then error("too deep") end
            local count = 0
            for _ in pairs(v) do count = count + 1 end
            if IsArray(v) then
                if count > 65530 then w.byte(22); w.int(count)
                elseif count > 254 then w.byte(21); w.short(count)
                else w.byte(20); w.byte(count) end
                for i = 1, count do WriteValue(v[i], depth + 1) end
            else
                if count > 254 then w.byte(11); w.short(count) else w.byte(10); w.byte(count) end
                for k, x in pairs(v) do WriteValue(k, depth + 1); WriteValue(x, depth + 1) end
            end
        else
            w.byte(1)
        end
    end
    WriteValue(1, 0)           -- the outer key
    WriteValue(tab, 0)
    return w.result()
end

addon.QuestieWire = { Serialize = Serialize, Deserialize = Deserialize }   -- for the offline tests

--------------------------------------------------------------------------------
-- What I heard: remote[name][questId] = { { id, type, fulfilled, required, finished }, ... }
--------------------------------------------------------------------------------
local remote = {}
local heard = { packets = 0, bad = 0 }
local sentCount = 0

local function Short(name) return (name or "?"):match("^([^%-]+)") or name end

local function InMyGroup(name)
    if not name then return false end
    return (UnitInParty and UnitInParty(name)) or (UnitInRaid and UnitInRaid(name)) or false
end

local function SetQuest(who, qid, objectives)
    if type(qid) ~= "number" or type(objectives) ~= "table" then return end
    remote[who] = remote[who] or { t = GetTime(), quests = {} }
    remote[who].t = GetTime()
    remote[who].quests[qid] = objectives
end

-- a flat list from the newer messages: { questId, objectiveCount, id, type, have, need, id, type, have, need ... }
local function ReadFlat(arr, who, offset)
    if type(arr) ~= "table" or not arr[offset + 1] then return offset end
    local qid, n = arr[offset], arr[offset + 1]
    local objectives = {}
    offset = offset + 2
    local i = 0
    while i < n and arr[offset + 1] do
        i = i + 1
        local id, typ, have, need = arr[offset], arr[offset + 1], arr[offset + 2], arr[offset + 3]
        objectives[i] = { index = i, id = (id ~= 0) and id or nil, type = type(typ) == "number" and string.char(typ) or "?",
            fulfilled = have, required = need, finished = (have == need) }
        offset = offset + 4
    end
    SetQuest(who, qid, objectives)
    return offset
end

local function ReadV1(q, who)
    if type(q) ~= "table" or not q.id or type(q.objectives) ~= "table" then return end
    local objectives = {}
    for i, o in pairs(q.objectives) do
        if type(o) == "table" then
            objectives[i] = { index = i, id = o.id, type = o.typ, fulfilled = o.ful, required = o.req, finished = o.fin }
        end
    end
    SetQuest(who, q.id, objectives)
end

local function Handle(packet, who)
    local id = packet.msgId
    if id == ID_UPDATE then ReadV1(packet.quest, who)
    elseif id == ID_REMOVE then
        if remote[who] and packet.id then remote[who].quests[packet.id] = nil end
    elseif id == ID_FULL then
        for _, q in pairs(packet.rawQuestList or {}) do ReadV1(q, who) end
    elseif id == ID_FULL_V2 then
        local arr = packet[1]
        if type(arr) == "table" then
            local offset, count = 2, tonumber(arr[1]) or 0
            for _ = 1, math.min(count, 60) do offset = ReadFlat(arr, who, offset) end
        end
    elseif id == ID_UPDATE_V2 then ReadFlat(packet[1], who, 1)
    elseif id == ID_REQUEST then
        if addon.QuestieLinkAnswer then addon.QuestieLinkAnswer(who) end
    end
end

local GROUP_DIST = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }

function addon:OnQuestieMessage(prefix, message, distribution, sender)
    if prefix ~= PREFIX or not GROUP_DIST[distribution] then return end
    local db = DB()
    if not db or db.questieLink == false then return end
    local who = Short(sender)
    if who == UnitName("player") or not InMyGroup(sender) then return end
    heard.packets = heard.packets + 1
    local ok, packet = pcall(Deserialize, message)
    if not ok or type(packet) ~= "table" then heard.bad = heard.bad + 1; return end
    if math.floor(tonumber(packet.msgVer) or 0) ~= MSG_VER then return end
    local okH = pcall(Handle, packet, who)
    if not okH then heard.bad = heard.bad + 1 end
end
addon:RegisterComm(PREFIX, "OnQuestieMessage")

-- what the Questie users in my group still need, in the same shape as addon.PartyProgress():
-- { [name] = { [questId] = { "Redridge Brute slain: 3/10", ... } } }
function addon.QuestieProgress()
    local out = {}
    for who, rec in pairs(remote) do
        for qid, objectives in pairs(rec.quests) do
            local texts = {}
            for _, o in pairs(objectives) do
                if o.id and not o.finished and o.required and o.required > 0 then
                    local store = (o.type == "m" and "npcs") or (o.type == "o" and "objects") or (o.type == "i" and "items") or nil
                    local name = store and data.Field(store, o.id, "name")
                    if name then
                        local label = (o.type == "m") and (name .. " slain") or name
                        texts[#texts + 1] = string.format("%s: %d/%d", label, o.fulfilled or 0, o.required)
                    end
                end
            end
            if #texts > 0 then
                out[who] = out[who] or {}
                out[who][qid] = texts
            end
        end
    end
    return out
end
function addon.QuestieRemote() return remote end

--------------------------------------------------------------------------------
-- Sending (only when Questie is not running here: when it is, it already sends for me)
--------------------------------------------------------------------------------
local function QuestieAddonLoaded()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not isLoaded then return false end
    local ok, v = pcall(isLoaded, "Questie")
    return ok and v and true or false
end

local function GroupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function CanSend()
    local db = DB()
    return db and db.questieLink ~= false and GroupChannel() and not QuestieAddonLoaded() and next(DS.quests) ~= nil
end

-- the ids of a quest's objectives, in the order Questie lists them (creatures, objects, items, reputation, kill credit)
local function ObjectiveIds(qid)
    local list = {}
    local o = data.Field("quests", qid, "objectives")
    if type(o) == "table" then
        for _, e in ipairs(o[1] or {}) do list[#list + 1] = e[1] or 0 end
        for _, e in ipairs(o[2] or {}) do list[#list + 1] = e[1] or 0 end
        for _, e in ipairs(o[3] or {}) do list[#list + 1] = e[1] or 0 end
        if o[4] then list[#list + 1] = o[4][1] or 0 end
        for _ in ipairs(o[5] or {}) do list[#list + 1] = 0 end
    end
    return list
end

-- my quests with their objectives: { [questId] = { { type, have, need }, ... } }
local function MyLog()
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives) then return out end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local okO, objs = pcall(C_QuestLog.GetQuestObjectives, info.questID)
            if okO and type(objs) == "table" and #objs > 0 then
                local list = {}
                for _, o in ipairs(objs) do
                    list[#list + 1] = { type = (o.type or "?"):sub(1, 1), have = o.numFulfilled or 0, need = o.numRequired or 0 }
                end
                out[info.questID] = list
            end
        end
    end
    return out
end

-- one quest as the flat list: { questId, count, id, type, have, need, ... }
local function FlatQuest(qid, objectives, arr)
    local ids = ObjectiveIds(qid)
    arr[#arr + 1] = qid
    arr[#arr + 1] = #objectives
    for i, o in ipairs(objectives) do
        arr[#arr + 1] = ids[i] or 0
        arr[#arr + 1] = o.type:byte(1)
        arr[#arr + 1] = o.have
        arr[#arr + 1] = o.need
    end
    return arr
end
addon.QuestieFlatQuest = FlatQuest

local function Send(packet, dist, target)
    packet.ver = FAKE_VER
    packet.msgVer = MSG_VER
    local ok, text = pcall(Serialize, packet)
    if not ok or #text > 760 then return false end
    addon:SendCommMessage(PREFIX, text, dist, target, "NORMAL")
    sentCount = sentCount + 1
    return true
end

local lastSig, sentIds = {}, {}
local function Sig(list)
    local p = {}
    for _, o in ipairs(list) do p[#p + 1] = o.type .. o.have .. "/" .. o.need end
    return table.concat(p, ",")
end

-- send what changed since last time (one small packet per changed quest) and tell them about quests I dropped
local function SendChanges()
    if not CanSend() then return end
    local dist = GroupChannel()
    local log = MyLog()
    for qid, list in pairs(log) do
        local sig = Sig(list)
        if lastSig[qid] ~= sig then
            lastSig[qid] = sig
            sentIds[qid] = true
            Send({ msgId = ID_UPDATE_V2, [1] = FlatQuest(qid, list, {}) }, dist)
        end
    end
    for qid in pairs(sentIds) do
        if not log[qid] then
            sentIds[qid] = nil; lastSig[qid] = nil
            Send({ msgId = ID_REMOVE, id = qid }, dist)
        end
    end
end

-- my whole log, a few quests to a packet (to a new group member, or to someone who asked)
local function SendAll(dist, target)
    local log = MyLog()
    local ids = {}
    for qid in pairs(log) do ids[#ids + 1] = qid end
    table.sort(ids)
    local i = 1
    local function Block()
        local arr, count = { 0 }, 0
        while i <= #ids and count < 6 do
            FlatQuest(ids[i], log[ids[i]], arr)
            count = count + 1
            i = i + 1
        end
        if count == 0 then return end
        arr[1] = count
        Send({ msgId = ID_FULL_V2, [1] = arr }, dist, target)
        if i <= #ids and C_Timer then C_Timer.After(1.5, Block) end
    end
    Block()
end

function addon.QuestieLinkAnswer(who)
    if not CanSend() then return end
    -- a Questie user joined or reloaded and asked for everyone's quests: answer to them only
    local log = MyLog()
    for qid, list in pairs(log) do lastSig[qid] = Sig(list); sentIds[qid] = true end
    SendAll("WHISPER", who)
end

-- say hello to a new group: ask for their quests (Questie users answer), and send mine
local function Hello()
    if not CanSend() then return end
    local dist = GroupChannel()
    Send({ msgId = ID_REQUEST }, dist)
    SendAll(dist)
    for qid, list in pairs(MyLog()) do lastSig[qid] = Sig(list); sentIds[qid] = true end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "GROUP_ROSTER_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end
local pending, lastGroup = false, 0
ev:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" then
        for who in pairs(remote) do if not InMyGroup(who) then remote[who] = nil end end
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        if n <= 1 then lastSig, sentIds = {}, {}; lastGroup = n; return end
        if n > lastGroup and C_Timer then C_Timer.After(8, function() pcall(Hello) end) end
        lastGroup = n
        return
    end
    if pending or not C_Timer or not GroupChannel() then return end
    pending = true
    C_Timer.After(2, function() pending = false; pcall(SendChanges) end)
end)

--------------------------------------------------------------------------------
-- /lazy questie
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "questie" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local db = DB()
        if a == "off" then db.questieLink = false elseif a == "on" then db.questieLink = nil end
        Print(L("talking to Questie users in your group: ") .. (db.questieLink == false and "OFF" or "on"))
        Print(string.format(L("  heard %d messages (%d unreadable). Sending my own progress: %s (%d packets sent)"),
            heard.packets, heard.bad, QuestieAddonLoaded() and "no, Questie is running here and does it" or (CanSend() and "yes" or "not in a group"), sentCount))
        local any = false
        for who, rec in pairs(remote) do
            any = true
            local n = 0
            for _ in pairs(rec.quests) do n = n + 1 end
            Print(string.format(L("  %s: %d quests"), who, n))
        end
        if not any then Print(L("  nobody running Questie has sent anything yet")) end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestieLink.lua"] = true end end
