-- Couch mode: playing on the TV with a controller.
--   big text everywhere (the tracker, the step window and the guide get a bigger size, and go back when it is switched off)
--   quests accept and hand in by themselves, so there is less to click
--       - dungeon quests, skipped quests and grey (too easy) quests are not accepted
--       - when a quest offers a choice of rewards it is NOT picked for me: the best one for my class and spec is starred and
--         read out, and I choose
--       - hold Shift while talking to someone to do it by hand
--   the steps are read aloud as they change ("Turn in X to Y"), and a key repeats the current one
--   /lazy couch on|off     /lazy couch say (repeat the step)
-- The pieces can also be switched on one by one in Options.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function DB() return addon.GetDB() end

local BIG = 1.6

--------------------------------------------------------------------------------
-- Which quests to take by myself
--------------------------------------------------------------------------------
local function Worth(questId, trivial)
    local db = DB()
    if trivial then return false end
    if questId then
        if api.IsDungeonQuest and api.IsDungeonQuest(questId, false) then return false end
        if db.planSkip and db.planSkip[questId] then return false end
    end
    return true
end

local function LogFull()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
        if numQuests and numQuests >= 25 then return true end
    end
    return false
end

local function AutoOn()
    local db = DB()
    return db and db.couchAuto == true and not (IsShiftKeyDown and IsShiftKeyDown())
end

local function Later(fn)
    if C_Timer and C_Timer.After then C_Timer.After(0.15, function() pcall(fn) end) else pcall(fn) end
end

-- talking to someone who has quests (the newer gossip window)
local function GossipQuests()
    if not (C_GossipInfo and C_GossipInfo.GetActiveQuests) then return false end
    -- hand in what is finished first
    for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
        if q.isComplete and q.questID then
            C_GossipInfo.SelectActiveQuest(q.questID)
            return true
        end
    end
    if LogFull() then return false end
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if q.questID and Worth(q.questID, q.isTrivial) then
            C_GossipInfo.SelectAvailableQuest(q.questID)
            return true
        end
    end
    return false
end

-- the older greeting window (a list of quests, no gossip)
local function GreetingQuests()
    if GetNumActiveQuests then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then SelectActiveQuest(i); return true end
        end
    end
    if LogFull() then return false end
    if GetNumAvailableQuests then
        for i = 1, GetNumAvailableQuests() do
            local isTrivial, _, _, _, questId = GetAvailableQuestInfo(i)
            if Worth(questId, isTrivial) then SelectAvailableQuest(i); return true end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Reading things aloud
--------------------------------------------------------------------------------
local lastSpoken = 0
local function Speak(text)
    local db = DB()
    if not (text and text ~= "" and C_VoiceChat and C_VoiceChat.SpeakText) then return false end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("%(%d+, %d+%)", "")
    local voice = db.couchVoice
    if not voice and C_VoiceChat.GetTtsVoices then
        local v = C_VoiceChat.GetTtsVoices()
        voice = v and v[1] and v[1].voiceID
    end
    local dest = (Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback) or 1
    local ok = pcall(C_VoiceChat.SpeakText, voice or 0, text, dest, tonumber(db.couchRate) or 0, tonumber(db.couchVolume) or 100)
    if ok then lastSpoken = GetTime() end
    return ok
end
addon.CouchSpeak = Speak

local function CurrentStep()
    if not addon.StepList then return nil end
    for _, s in ipairs(addon.StepList(6)) do
        if not s.done then return s end
    end
end

local lastKey
local function SayStep(force)
    local s = CurrentStep()
    if not s then return end
    if force or s.key ~= lastKey then
        lastKey = s.key
        Speak(s.text)
    end
end

function _G.ForeverLazy_SpeakStep()
    local s = CurrentStep()
    if s then lastKey = s.key; Speak(s.text) else Speak("Nothing to do right now") end
end
_G.BINDING_NAME_FOREVERLAZY_SPEAK = "Read the current step aloud"

local acc = 0
local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1.5 then return end
    acc = 0
    local db = DB()
    if not (db and db.couchSpeak) or db.planPaused then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if GetTime() - lastSpoken < 3 then return end
    pcall(SayStep, false)
end)

--------------------------------------------------------------------------------
-- The quest windows
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    local db = DB()
    if not db then return end
    if event == "QUEST_COMPLETE" then
        local n = GetNumQuestChoices and GetNumQuestChoices() or 0
        if n > 1 then
            -- a choice: never picked for me. The star and the chat line come from the reward chooser; here it is read out too.
            if db.couchSpeak then Later(function() Speak("Choose your reward. The best one for you has a star.") end) end
            return
        end
        if AutoOn() and GetQuestReward then
            Later(function() GetQuestReward(n == 1 and 1 or nil) end)
        end
        return
    end
    if not AutoOn() then return end
    if event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        if not LogFull() and Worth(id, false) then Later(AcceptQuest) end
    elseif event == "QUEST_PROGRESS" then
        if IsQuestCompletable and IsQuestCompletable() then Later(CompleteQuest) end
    elseif event == "GOSSIP_SHOW" then
        Later(GossipQuests)
    elseif event == "QUEST_GREETING" then
        Later(GreetingQuests)
    end
end)

--------------------------------------------------------------------------------
-- Couch mode as a whole
--------------------------------------------------------------------------------
function addon.CouchSet(on)
    local db = DB()
    if not db then return end
    if on and not db.couch then
        db.couchPrev = { guide = db.guideScale, tracker = db.trackerScale, steps = db.stepsScale }
        db.guideScale, db.trackerScale, db.stepsScale = BIG, BIG, BIG
        db.couchAuto, db.couchSpeak = true, true
        db.couch = true
    elseif not on and db.couch then
        local p = db.couchPrev or {}
        db.guideScale, db.trackerScale, db.stepsScale = p.guide, p.tracker, p.steps
        db.couchAuto, db.couchSpeak = false, false
        db.couch = false
        db.couchPrev = nil
    end
    if addon.TrackerSet and db.couch and db.trackerOn == nil then addon.TrackerSet(true) end
    if addon.ToggleSteps and db.couch then addon.ToggleSteps(true) end
    if addon.RefreshOptions then addon.RefreshOptions() end
    if on then
        Print(L("couch mode on: big text, quests accept and hand in by themselves (hold Shift to do it by hand), steps read aloud. ") ..
            L("Rewards are not picked for you: the best one is starred."))
        lastKey = nil
    else
        Print(L("couch mode off"))
    end
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "couch" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if a == "say" or a == "repeat" then _G.ForeverLazy_SpeakStep()
        elseif a == "on" then addon.CouchSet(true)
        elseif a == "off" then addon.CouchSet(false)
        else addon.CouchSet(not DB().couch) end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Couch.lua"] = true end end
