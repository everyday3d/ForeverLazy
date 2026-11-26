-- Hand-in ping: walk up to the person who takes a finished quest and a message flashes, a sound plays and the minimap pings
-- where you stand, once for each visit.
--   /lazy ping on|off
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local data = ns.data
local Print = addon.Print

local function DB() return addon.GetDB() end
local NEAR, FAR = 45, 130           -- yards: ping inside NEAR, ready again after I have been farther than FAR

local spots = {}                     -- quest id -> spawns where it is handed in
local pinged = {}                    -- quest id -> true while I stay near

local function Spots(id)
    local s = spots[id]
    if s then return s end
    s = {}
    local by = data.Field("quests", id, "finishedBy")
    if type(by) == "table" then
        if api.AddNpcs then pcall(api.AddNpcs, s, by[1]) end
        if api.AddObjects then pcall(api.AddObjects, s, by[2]) end
    end
    spots[id] = s
    return s
end

local GAP = 8                        -- seconds: one signal for one hand-in, whoever notices it first
local lastSignal = -100
local report = "not run"             -- what the game answered the last time (shown by /lazy ping test)
local function Ping(title, who)
    local now = GetTime and GetTime() or 0
    if now - lastSignal < GAP then return end
    lastSignal = now
    local msg = "Hand in: " .. tostring(title) .. (who and (" to " .. who) or "")
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 0.3, 1, 0.3, 1, 4) end
    local id = (_G.SOUNDKIT and _G.SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) or 878
    local okS, will = pcall(PlaySound, id, "Master")
    local okP, whyP = false, "this client has no minimap ping"
    if Minimap and Minimap.PingLocation then okP, whyP = pcall(Minimap.PingLocation, Minimap, 0, 0) end
    report = string.format("sound %s: %s. Minimap ping: %s", tostring(id),
        okS and ("the game answered " .. tostring(will)) or ("failed, " .. tostring(will)),
        okP and "sent, the game gave no error" or ("failed, " .. tostring(whyP)))
end

-- the arrow or the compass reached a hand-in stop: the same message, sound and minimap ping. False when the ping is off
function addon.HandInSignal(stop)
    local db = DB()
    if not db or db.handInPing == false then return false end
    local title = tostring(stop and (stop.name or stop.label) or "?"):gsub("^%d+%.%s*", ""):gsub("^Turn in:%s*", "")
    Ping(title)
    return true
end

local acc = 0
local ev = CreateFrame("Frame")
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1.2 then return end
    acc = 0
    local db = DB()
    if not db or db.handInPing == false then return end
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and api.hbd) then return end
    local px, py, pinst = api.hbd:GetPlayerWorldPosition()
    if not px then return end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local id = info.questID
            local okC, complete = pcall(C_QuestLog.IsComplete, id)
            if okC and complete then
                local nearest
                for _, s in ipairs(Spots(id)) do
                    if s.instance == pinst then
                        local d = math.sqrt(api.D2(s.x, s.y, px, py))
                        if not nearest or d < nearest then nearest = d end
                    end
                end
                if nearest then
                    if nearest <= NEAR and not pinged[id] then
                        pinged[id] = true
                        local by = data.Field("quests", id, "finishedBy")
                        local who = addon.QuestWho and addon.QuestWho(by)
                        if who then who = who:gsub("%s*|c%x%x%x%x%x%x%x%x.-|r", "") end
                        Ping(info.title, who)
                    elseif nearest > FAR then
                        pinged[id] = nil
                    end
                end
            else
                pinged[id] = nil
            end
        end
    end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "ping" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local db = DB()
        if a == "test" then
            lastSignal = -100
            Print(L("playing the hand-in signal: a green message, a sound and a minimap ping"))
            Ping(L("this is a test"))
            Print(report)
            return true
        elseif a == "check" then
            local px, py, pinst = api.hbd:GetPlayerWorldPosition()
            Print(string.format("hand-in ping %s, your position %s", db.handInPing == false and "OFF" or "on", px and "known" or "NOT known"))
            local any = false
            for i = 1, (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0) do
                local ok, info = pcall(C_QuestLog.GetInfo, i)
                if ok and type(info) == "table" and not info.isHeader and info.questID then
                    local okC, complete = pcall(C_QuestLog.IsComplete, info.questID)
                    local ready = C_QuestLog.ReadyForTurnIn and select(2, pcall(C_QuestLog.ReadyForTurnIn, info.questID))
                    if (okC and complete) or ready == true then
                        any = true
                        local nearest, spotsHere = nil, 0
                        for _, s in ipairs(Spots(info.questID)) do
                            if px and s.instance == pinst then
                                spotsHere = spotsHere + 1
                                local d = math.sqrt(api.D2(s.x, s.y, px, py))
                                if not nearest or d < nearest then nearest = d end
                            end
                        end
                        Print(string.format("  %s (%s): complete %s, ready %s, places known %d, %d on this continent, nearest %s, already pinged %s",
                            tostring(info.title), tostring(info.questID), tostring(complete), tostring(ready), #Spots(info.questID), spotsHere,
                            nearest and string.format("%d yd", nearest) or "-", tostring(pinged[info.questID] == true)))
                    end
                end
            end
            if not any then Print("  the game reports no finished quest in your log") end
            return true
        end
        if a == "off" then db.handInPing = false elseif a == "on" then db.handInPing = nil end
        Print(L("hand-in ping: ") .. (db.handInPing == false and "OFF" or "on") .. L("  (/lazy ping on|off)"))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["HandInPing.lua"] = true end end
