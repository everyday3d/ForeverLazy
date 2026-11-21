-- Quest sounds, all from the WoW client (no sound file ships with the addon):
--   the quest is ready to hand in: the voice, Alliance Peasant "Job's done!", Horde Peon "Work complete!"
--   all the items or kills a quest step needs are done: a different sound, an effect
--   /lazy sound on|off|try|next|next done     (also in the options, under Quest sounds)
local ADDON, ns = ...
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

-- the sounds to choose from: name, sound kit id.
--   a step done (all the items or kills a quest step needs): a sound effect
--   a quest ready to hand in: the voice, "Job's done!"
local STEP = {
    { "Quest list chime", 878 },
    { "Ready check", 8960 },
    { "Ding", 888 },
    { "Raid warning", 8959 },
}
local DONE = {
    { "Peasant: Job's done!", 6200 },
    { "Peon: Work complete!", 6199 },
}

local function Pick(list, key)
    local db = DB()
    local i = db and db[key]
    if list[i or 0] then return list[i] end
    return nil
end
local function StepVoice() return Pick(STEP, "questSoundStep") or STEP[1] end
local function DoneSound()
    local v = Pick(DONE, "questSoundDone")
    if v then return v end
    -- the default: the voice of my faction
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return faction == "Horde" and DONE[2] or DONE[1]
end

local lastStep, lastDone = 0, 0
local function PlayStep(force)
    if not force and GetTime() - lastStep < 1.5 then return end
    lastStep = GetTime()
    pcall(PlaySound, StepVoice()[2], "Master")
end
local function PlayDone(force)
    if not force and GetTime() - lastDone < 1.5 then return end
    lastDone = GetTime()
    pcall(PlaySound, DoneSound()[2], "Master")
end

function addon.QuestSoundTryStep() PlayStep(true); Print("step done sound: " .. StepVoice()[1]) end
function addon.QuestSoundTryDone() PlayDone(true); Print("ready to hand in sound: " .. DoneSound()[1]) end

local function Next(list, key, current)
    local db = DB()
    local idx = 1
    for i, v in ipairs(list) do if v == current then idx = i end end
    db[key] = idx % #list + 1
end
function addon.QuestSoundNextStep() Next(STEP, "questSoundStep", StepVoice()); addon.QuestSoundTryStep() end
function addon.QuestSoundNextDone() Next(DONE, "questSoundDone", DoneSound()); addon.QuestSoundTryDone() end
--------------------------------------------------------------------------------
-- Watch the quest log: an objective finished, or a quest ready to hand in
--------------------------------------------------------------------------------
local before = nil          -- questId -> { done = objectives finished, complete = bool }
local function Snapshot()
    local now = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives) then return now end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local done = 0
            local texts = {}
            local okO, objs = pcall(C_QuestLog.GetQuestObjectives, info.questID)
            if okO and type(objs) == "table" then
                for _, o in ipairs(objs) do
                    if o.finished then done = done + 1 end
                    texts[#texts + 1] = o.text or ""
                end
            end
            local okC, complete = pcall(C_QuestLog.IsComplete, info.questID)
            now[info.questID] = { done = done, complete = okC and complete and true or false, title = info.title, texts = texts }
        end
    end
    return now
end

local function Check()
    local db = DB()
    if not db or (db.questSound == false and db.questAnnounce == false) then before = nil; return end
    local now = Snapshot()
    if before then
        local stepDone, questDone = false, false
        local finished = {}
        for qid, s in pairs(now) do
            local b = before[qid]
            -- only quests I already had: a quest just accepted, or one found at login, does not ring
            if b then
                if s.done > b.done then stepDone = true end
                if s.complete and not b.complete then
                    questDone = true
                    -- the objective that completed it: the one whose text changed, else the last one
                    local what
                    for i, t in ipairs(s.texts or {}) do
                        if t ~= "" and (b.texts or {})[i] ~= t then what = t end
                    end
                    if not what then
                        for i = #(s.texts or {}), 1, -1 do if s.texts[i] ~= "" then what = s.texts[i]; break end end
                    end
                    -- a plain "go talk to X" quest (nothing to kill or collect) is not worth announcing,
                    -- unless it is the end of its chain
                    local announce = what ~= nil
                    if not announce then
                        local nextQ = ns.data and ns.data.Field and ns.data.Field("quests", qid, "nextQuestInChain")
                        announce = not (tonumber(nextQ) and tonumber(nextQ) > 0)
                    end
                    if announce then finished[#finished + 1] = { title = s.title or ("quest " .. qid), what = what } end
                end
            end
        end
        -- tell the party: a whole quest is complete (not a single step)
        if #finished > 0 and db.questAnnounce ~= false then
            local channel
            if IsInRaid and IsInRaid() then channel = "RAID"
            elseif IsInGroup and IsInGroup() then channel = "PARTY" end
            if channel and SendChatMessage then
                for _, f in ipairs(finished) do
                    local msg = "[Forever Lazy] Completed quest " .. tostring(f.title)
                    if f.what then msg = msg .. " - " .. f.what end
                    pcall(SendChatMessage, msg, channel)
                end
            end
        end
        if db.questSound == false then stepDone, questDone = false, false end
        if stepDone then PlayStep(false) end
        if questDone then
            -- the effect first, then "Job's done!" a moment later
            if stepDone and C_Timer then C_Timer.After(1.2, function() PlayDone(false) end) else PlayDone(false) end
        end
    end
    before = now
end

local pending
local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function()
    if pending or not C_Timer then return end
    pending = true
    C_Timer.After(0.4, function() pending = false; pcall(Check) end)
end)

-- a quest I just picked up from an item that dropped: tell the party (same switch as the completed-quest message)
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "QUEST_ACCEPTED")
    f:SetScript("OnEvent", function(_, _, index, questId)
        local db = DB()
        if not db or db.questAnnounce == false then return end
        local qid = tonumber(questId)
        if not qid and index and C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then qid = C_QuestLog.GetQuestIDForLogIndex(index) end
        if not qid then return end
        local by = ns.data and ns.data.Field and ns.data.Field("quests", qid, "startedBy")
        local items = type(by) == "table" and by[3]
        if type(items) ~= "table" or not next(items) then return end
        local channel
        if IsInRaid and IsInRaid() then channel = "RAID" elseif IsInGroup and IsInGroup() then channel = "PARTY" end
        if not (channel and SendChatMessage) then return end
        local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid) or ("quest " .. qid)
        local item
        for _, id in pairs(items) do
            if type(id) == "number" then item = GetItemInfo and GetItemInfo(id); break end
        end
        pcall(SendChatMessage, "[Forever Lazy] New quest from a drop: " .. tostring(title) .. (item and (" (" .. item .. ")") or ""), channel)
    end)
end

--------------------------------------------------------------------------------
-- /lazy sound
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "announce" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local db = DB()
        if a == "off" then db.questAnnounce = false elseif a == "on" then db.questAnnounce = nil end
        Print("telling my party when I complete a quest: " .. (db.questAnnounce == false and "OFF" or "on") .. "  (/lazy announce on|off)")
        return true
    end
    if (cmd or ""):lower() == "sound" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local db = DB()
        if a == "off" then db.questSound = false; before = nil
        elseif a == "on" then db.questSound = nil
        elseif a == "next" or a == "next step" then addon.QuestSoundNextStep(); return true
        elseif a == "next done" then addon.QuestSoundNextDone(); return true
        elseif a == "try" or a == "" then addon.QuestSoundTryStep(); C_Timer.After(1.4, addon.QuestSoundTryDone); return true end
        Print("quest sounds: " .. (db.questSound == false and "OFF" or "on") .. " (step done: " .. StepVoice()[1] .. ", ready to hand in: " .. DoneSound()[1] .. ")")
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestSounds.lua"] = true end end
