-- Party progress: your group sees how far you are on a quest, and you see theirs ("Alex: Redridge Brute slain 3/10"), so a
-- mob or item tooltip can show what each of you still needs. Only the quest id and the unfinished objective lines are sent, to
-- your own party or raid, over this addon's own message. It works between players who both have Forever Lazy; people who run
-- Questie instead already share with each other through Questie.
--   addon.PartyProgress()   { [name] = { [questId] = { "Redridge Brute slain: 3/10", ... } } }
local ADDON, ns = ...
local addon = ns.addon
local Print = addon.Print

local PREFIX = "FLPROG"
local theirs = {}              -- name -> { t = time, quests = { [id] = { text... } } }

local function Channel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end
local function Short(name) return (name or "?"):match("^([^%-]+)") or name end

function addon.PartyProgress()
    local out = {}
    for who, t in pairs(theirs) do out[who] = t.quests end
    -- people in the group who run Questie send their progress too (read in QuestieLink.lua)
    if addon.QuestieProgress then
        local okQ, q = pcall(addon.QuestieProgress)
        if okQ and type(q) == "table" then
            for who, quests in pairs(q) do
                out[who] = out[who] or {}
                for qid, texts in pairs(quests) do if not out[who][qid] then out[who][qid] = texts end end
            end
        end
    end
    return out
end

-- my unfinished objectives, per quest
local function Mine()
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives) then return out end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local okO, objs = pcall(C_QuestLog.GetQuestObjectives, info.questID)
            if okO and type(objs) == "table" then
                local lines = {}
                for _, o in ipairs(objs) do
                    if o.text and o.text ~= "" and not o.finished then lines[#lines + 1] = o.text:sub(1, 80) end
                end
                if #lines > 0 then out[info.questID] = lines end
            end
        end
    end
    return out
end

local lastSent, lastAt = "", 0
local function Send(force)
    local ch = Channel()
    local db = addon.GetDB()
    if not ch or not (db and db.partyProgress ~= false) or not addon.Serialize then return end
    if not force and GetTime() - lastAt < 4 then return end
    local quests = Mine()
    local ids = {}
    for id in pairs(quests) do ids[#ids + 1] = id end
    table.sort(ids)
    local key = {}
    for _, id in ipairs(ids) do key[#key + 1] = id .. ":" .. table.concat(quests[id], "|") end
    local sig = table.concat(key, ";")
    if not force and sig == lastSent then return end
    lastSent, lastAt = sig, GetTime()
    addon:SendCommMessage(PREFIX, addon:Serialize({ q = quests }), ch)
end

function addon:OnPartyProgress(prefix, message, distribution, sender)
    if prefix ~= PREFIX then return end
    local who = Short(sender)
    if who == UnitName("player") then return end
    local ok, t = self:Deserialize(message)
    if not ok or type(t) ~= "table" or type(t.q) ~= "table" then return end
    local quests = {}
    for id, lines in pairs(t.q) do
        if type(id) == "number" and type(lines) == "table" then
            local list = {}
            for _, l in ipairs(lines) do if type(l) == "string" then list[#list + 1] = l:sub(1, 80) end end
            quests[id] = list
        end
    end
    theirs[who] = { t = GetTime(), quests = quests }
    -- a new group member: send mine back so they see mine too
    if not theirs[who].answered then theirs[who].answered = true; Send(true) end
end
addon:RegisterComm(PREFIX, "OnPartyProgress")

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end
local pending
ev:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" then
        -- forget people who left, and tell the new ones where I am
        for who in pairs(theirs) do if not UnitInParty(who) and not UnitInRaid(who) then theirs[who] = nil end end
        if not Channel() then lastSent = ""; return end
        if C_Timer then C_Timer.After(6, function() Send(true) end) end
        return
    end
    if pending or not C_Timer or not Channel() then return end
    pending = true
    C_Timer.After(2, function() pending = false; pcall(Send, false) end)
end)

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["PartyProgress.lua"] = true end end
