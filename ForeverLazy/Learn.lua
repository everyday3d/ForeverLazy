-- Our own data, learned while you play (phase 2 of docs/QUESTIE-INDEPENDENCE.md). Nothing here changes what the planner does yet;
-- it only fills a store, so we can measure how much we know and later ask it before Questie.
--
--   quests  id -> { name, level, zone, group, xp, objectives = { text... }, startedBy = { npcId... }, finishedBy = { npcId... } }
--   npcs    id -> { name, minLevel, maxLevel, zone, spots = { { map, x, y, n } ... }, gives = { questId... }, takes = { questId... } }
-- Stored account-wide (ForeverLazyDB.own). Positions are rounded to about 1.5% of the zone map and capped, so it stays small.
--   /lazy data           what we know so far
--   /lazy data clear     forget it
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local GRID = 0.015
local MAX_SPOTS = 10

local function Own()
    local root = addon.GetRoot and addon.GetRoot()
    if not root then return nil end
    root.own = root.own or {}
    local o = root.own
    o.quests = o.quests or {}
    o.npcs = o.npcs or {}
    return o
end

local function Pos()
    local hbd = api and api.hbd
    if not (hbd and hbd.GetPlayerZonePosition) then return nil end
    local ok, x, y, map = pcall(hbd.GetPlayerZonePosition, hbd)
    if ok and x and y and map then return map, x, y end
end

local function IdFromGuid(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if (kind == "Creature" or kind == "Vehicle") and id then return tonumber(id), "npc" end
    if kind == "GameObject" and id then return tonumber(id), "object" end
end

local function AddUnique(list, v)
    for _, x in ipairs(list) do if x == v then return end end
    list[#list + 1] = v
end

local function Npc(o, id, name)
    local n = o.npcs[id]
    if not n then n = {}; o.npcs[id] = n end
    if name and name ~= "" then n.name = name end
    return n
end

-- note that this npc was seen about where I am now
local function NoteSpot(n, close)
    if not close then return end
    local map, x, y = Pos()
    if not map then return end
    n.zone = GetRealZoneText and GetRealZoneText() or n.zone
    n.spots = n.spots or {}
    local gx, gy = math.floor(x / GRID + 0.5) * GRID, math.floor(y / GRID + 0.5) * GRID
    for _, s in ipairs(n.spots) do
        if s.map == map and math.abs(s.x - gx) < 0.0001 and math.abs(s.y - gy) < 0.0001 then s.n = (s.n or 1) + 1; return end
    end
    if #n.spots < MAX_SPOTS then
        n.spots[#n.spots + 1] = { map = map, x = gx, y = gy, n = 1 }
    else
        -- full: count it on the nearest known spot
        local best, bd
        for _, s in ipairs(n.spots) do
            local d = (s.x - gx) ^ 2 + (s.y - gy) ^ 2
            if s.map == map and (not bd or d < bd) then best, bd = s, d end
        end
        if best then best.n = (best.n or 1) + 1 end
    end
end

--------------------------------------------------------------------------------
-- Creatures I see (hostile or not): name, level, and about where
--------------------------------------------------------------------------------
local function SeenUnit(unit)
    if not (unit and UnitExists(unit)) or UnitIsPlayer(unit) then return end
    if UnitPlayerControlled and UnitPlayerControlled(unit) then return end
    local id, kind = IdFromGuid(UnitGUID(unit))
    if not id or kind ~= "npc" then return end
    local o = Own()
    if not o then return end
    local n = Npc(o, id, UnitName(unit))
    local lvl = UnitLevel and UnitLevel(unit)
    if lvl and lvl > 0 then
        n.minLevel = n.minLevel and math.min(n.minLevel, lvl) or lvl
        n.maxLevel = n.maxLevel and math.max(n.maxLevel, lvl) or lvl
    end
    -- only count a position when the creature is close to me (about 28 yards), so the spot is about where it stands
    local close = CheckInteractDistance and CheckInteractDistance(unit, 4)
    NoteSpot(n, close)
end

--------------------------------------------------------------------------------
-- Quest givers and takers (the quest window knows who I am talking to)
--------------------------------------------------------------------------------
local function GiverNpc(o)
    local id, kind
    for _, u in ipairs({ "questnpc", "npc", "target" }) do
        if UnitExists(u) then
            id, kind = IdFromGuid(UnitGUID(u))
            if id then
                local n = Npc(o, id, UnitName(u))
                NoteSpot(n, true)         -- I am talking to it, so I am next to it
                return id, n, kind
            end
        end
    end
end

local function QuestRec(o, qid)
    local q = o.quests[qid]
    if not q then q = {}; o.quests[qid] = q end
    return q
end

local function Detail()
    local qid = GetQuestID and GetQuestID()
    local o = Own()
    if not (qid and qid > 0 and o) then return end
    local npcId, npc = GiverNpc(o)
    local q = QuestRec(o, qid)
    local title = GetTitleText and GetTitleText()
    if title and title ~= "" then q.name = title end
    if npcId then
        q.startedBy = q.startedBy or {}
        AddUnique(q.startedBy, npcId)
        npc.gives = npc.gives or {}
        AddUnique(npc.gives, qid)
    end
end

local function Complete()
    local qid = GetQuestID and GetQuestID()
    local o = Own()
    if not (qid and qid > 0 and o) then return end
    local npcId, npc = GiverNpc(o)
    local q = QuestRec(o, qid)
    local title = GetTitleText and GetTitleText()
    if title and title ~= "" then q.name = title end
    if npcId then
        q.finishedBy = q.finishedBy or {}
        AddUnique(q.finishedBy, npcId)
        npc.takes = npc.takes or {}
        AddUnique(npc.takes, qid)
    end
end

-- once a quest is in my log: level, zone, group size, objectives and the XP it gives
local function ReadLogEntry(qid)
    local o = Own()
    if not (o and qid and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo) then return end
    local okI, idx = pcall(C_QuestLog.GetLogIndexForQuestID, qid)
    if not okI or not idx or idx == 0 then return end
    local okG, info = pcall(C_QuestLog.GetInfo, idx)
    if not okG or type(info) ~= "table" then return end
    local q = QuestRec(o, qid)
    if info.title then q.name = info.title end
    if info.level and info.level > 0 then q.level = info.level end
    if info.suggestedGroup and info.suggestedGroup > 0 then q.group = info.suggestedGroup end
    -- the zone is the header above it in the log
    for i = idx - 1, 1, -1 do
        local okH, h = pcall(C_QuestLog.GetInfo, i)
        if okH and type(h) == "table" and h.isHeader then q.zone = h.title; break end
    end
    if GetQuestLogRewardXP then
        local okX, xp = pcall(GetQuestLogRewardXP, qid)
        if okX and tonumber(xp) and tonumber(xp) > 0 then q.xp = tonumber(xp); q.xpLevel = UnitLevel("player") end
    end
    if C_QuestLog.GetQuestObjectives then
        local okO, objs = pcall(C_QuestLog.GetQuestObjectives, qid)
        if okO and type(objs) == "table" and #objs > 0 then
            local list = {}
            for _, ob in ipairs(objs) do
                if ob.text and ob.text ~= "" then list[#list + 1] = (ob.type or "?") .. ": " .. ob.text:gsub("%s*%d+/%d+%s*$", "") end
            end
            if #list > 0 then q.objectives = list end
        end
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_ACCEPTED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a, b)
    if event == "QUEST_DETAIL" then pcall(Detail)
    elseif event == "QUEST_COMPLETE" then pcall(Complete)
    elseif event == "QUEST_ACCEPTED" then
        local qid = tonumber(b) or tonumber(a)
        if C_Timer and C_Timer.After then C_Timer.After(1.5, function() pcall(ReadLogEntry, qid) end) end
    elseif event == "PLAYER_TARGET_CHANGED" then pcall(SeenUnit, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then pcall(SeenUnit, "mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then pcall(SeenUnit, a)
    end
end)

-- quests already in my log when I log in: read them once, a few at a time
local function ReadWholeLog()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return end
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    local ids = {}
    for i = 1, n do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then ids[#ids + 1] = info.questID end
    end
    local i = 0
    local function Step()
        i = i + 1
        if ids[i] then pcall(ReadLogEntry, ids[i]); C_Timer.After(0.2, Step) end
    end
    if C_Timer and #ids > 0 then Step() end
end
local boot = CreateFrame("Frame")
pcall(boot.RegisterEvent, boot, "PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if C_Timer then C_Timer.After(20, function() pcall(ReadWholeLog) end) end
end)

--------------------------------------------------------------------------------
-- /lazy data: what we know, next to what Questie knows
--------------------------------------------------------------------------------
local function Count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

function addon.DataReport()
    local o = Own()
    if not o then return end
    local quests, npcs = Count(o.quests), Count(o.npcs)
    local withGiver, withTaker, withXp, withSpot = 0, 0, 0, 0
    for _, q in pairs(o.quests) do
        if q.startedBy then withGiver = withGiver + 1 end
        if q.finishedBy then withTaker = withTaker + 1 end
        if q.xp then withXp = withXp + 1 end
    end
    for _, n in pairs(o.npcs) do if n.spots and #n.spots > 0 then withSpot = withSpot + 1 end end
    Print(string.format(L("our own data: %d quests (%d with a giver, %d with a hand-in npc, %d with their XP), %d creatures (%d with a position)"),
        quests, withGiver, withTaker, withXp, npcs, withSpot))
    local QDB = api.GetQuestie and api.GetQuestie()
    if QDB and QDB.QuestPointers and QDB.NPCPointers then
        local qq, nn = Count(QDB.QuestPointers), Count(QDB.NPCPointers)
        local both = 0
        for id in pairs(o.quests) do if QDB.QuestPointers[id] then both = both + 1 end end
        Print(string.format(L("%s knows %d quests and %d creatures. We have %d of its quests (%.1f%%), plus %d it does not have"),
            ns.data and ns.data.Source() or "the source", qq, nn, both, qq > 0 and (both / qq * 100) or 0, quests - both))
    end
    local s = ns.data and ns.data.Stats and ns.data.Stats()
    if s then
        local total = s.own + s.source + s.filled + s.set + s.setfill + s.none
        Print(string.format(L("lookups since login: %d total - %d from what I saw myself, %d from %s, %d where only my data knew it, %d from our data set (first), %d where only the data set knew it, %d unknown"),
            total, s.own, s.source, ns.data.Source(), s.filled, s.set, s.setfill, s.none))
        local q, n, o, i = ns.data.DatasetSize()
        Print(string.format(L("our data set holds %d quests, %d creatures, %d objects and %d items. It is asked %s the source."), q, n, o, i,
            addon.GetDB().dataFirst and "BEFORE" or "after"))
    end
end

-- ids the source did not know when something asked about them, and whether our own data holds them
function addon.DataMisses()
    local m = ns.data and ns.data.Misses and ns.data.Misses()
    local o = Own()
    if not (m and o) then return end
    local QDB = api.GetQuestie and api.GetQuestie()
    local function Report(bucket, label, store)
        local list, held = {}, 0
        for id, r in pairs(m[bucket]) do
            -- only ids the source really does not have (a missing field on a known id is normal)
            local known = QDB and ((bucket == "quests" and QDB.QuestPointers and QDB.QuestPointers[id]) or (bucket == "npcs" and QDB.NPCPointers and QDB.NPCPointers[id]))
            if not known then
                list[#list + 1] = { id = id, n = r[1], field = r[2], rec = store[id] }
                if store[id] then held = held + 1 end
            end
        end
        table.sort(list, function(a, b) return a.n > b.n end)
        Print(string.format(L("%s the source does not have: %d asked about, %d of them in our own data"), label, #list, held))
        for i = 1, math.min(8, #list) do
            local x = list[i]
            Print(string.format(L("   %d  %s  (asked %d times for '%s')%s"), x.id, x.rec and x.rec.name or "?", x.n, tostring(x.field), x.rec and "  ours" or ""))
        end
    end
    Report("quests", "quests", o.quests)
    Report("npcs", "creatures", o.npcs)
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "data" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if a == "questie off" or a == "questie on" then
            addon.GetDB().noQuestie = (a == "questie off")
            Print(L("pretending the data source is ") .. (a == "questie off" and "NOT installed" or "installed") .. L(". Type /reload to apply."))
        elseif a == "verify" then
            addon.capture = addon.capture
            for _, l in ipairs(ns.data.Verify(300)) do Print(l) end
        elseif a == "first on" or a == "first off" then
            addon.GetDB().dataFirst = (a == "first on")
            Print(L("our own data set is asked ") .. (a == "first on" and "BEFORE" or "after") .. L(" the source (Questie). /lazy data verify compares the two."))
        elseif a == "misses" or a == "missing" then
            addon.DataMisses()
        elseif a == "off" or a == "on" then
            local db = addon.GetDB()
            db.useOwnData = (a == "on")
            Print(L("using our own data ") .. (a == "on" and "on: it is asked first for names and levels, and fills what the source does not know" or "off: only the source is used"))
        elseif a == "clear" or a == "reset" then
            local root = addon.GetRoot and addon.GetRoot()
            if root then root.own = nil end
            Print(L("our own data forgotten"))
        else
            addon.DataReport()
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Learn.lua"] = true end end
