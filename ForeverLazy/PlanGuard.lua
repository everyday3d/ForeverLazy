-- Making sure the plan is followed right.
--   1. a decision log: every change to the plan and why (/lazy plan log)
--   2. a self-check: rules that must always hold, broken ones are fixed and logged (/lazy plan check)
--   3. an audit: the check runs by itself, and quests in my log that the plan left out are noted with the reason
--   4. stuck detection: standing at a stop for minutes with no progress asks if I want to skip it
--   5. plan against reality: the XP per hour the plan promised, against what I really earned
-- The rules are written as plain functions of the plan and a few facts about my quests, so they can be tested outside the game
-- (see tests/ in the repository).
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local function Now() return (time and time()) or 0 end

--------------------------------------------------------------------------------
-- 1. The decision log
--------------------------------------------------------------------------------
local LOG_MAX = 200
local logWin, logText

local function LogLines(n)
    local db = DB()
    local log = db and db.planLog or {}
    local out = {}
    for i = #log, math.max(1, #log - (n or 120) + 1), -1 do
        local e = log[i]
        local stamp = (date and e.t and e.t > 0) and date("%H:%M:%S", e.t) or "--:--:--"
        out[#out + 1] = string.format("|cff888888%s|r |cff80c0ff%s|r  %s", stamp, tostring(e.who or "?"), tostring(e.text or ""))
    end
    return out
end

local function RefreshLogWindow()
    if not (logWin and logWin:IsShown()) then return end
    local lines = LogLines(120)
    logText:SetText(#lines > 0 and table.concat(lines, "\n") or "Nothing logged yet. Make a plan with /lazy plan and come back.")
    logWin.content:SetHeight(math.max(40, logText:GetStringHeight() + 8))
end

function addon.PlanLog(who, text)
    local db = DB()
    if not db then return end
    db.planLog = db.planLog or {}
    local log = db.planLog
    log[#log + 1] = { t = Now(), who = who, text = tostring(text) }
    while #log > LOG_MAX do table.remove(log, 1) end
    if logWin then RefreshLogWindow() end
end

function addon.ShowPlanLog()
    if not logWin then
        local f = CreateFrame("Frame", "ForeverLazy_PlanLog", UIParent)
        f:SetSize(620, 460)
        f:SetPoint("CENTER", 0, 20)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        title:SetPoint("TOPLEFT", 16, -14); title:SetText(L("Plan log"))
        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", 16, -44); sub:SetWidth(580); sub:SetJustifyH("LEFT")
        sub:SetText(L("Newest first. Every change to the plan and why. Send this when a stop looks wrong."))
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", "ForeverLazy_PlanLogScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -66); scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        f.content = CreateFrame("Frame", nil, scroll)
        f.content:SetSize(560, 10)
        scroll:SetScrollChild(f.content)
        logText = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        logText:SetPoint("TOPLEFT", 0, 0); logText:SetWidth(556); logText:SetJustifyH("LEFT"); logText:SetJustifyV("TOP")
        table.insert(UISpecialFrames, "ForeverLazy_PlanLog")
        f:Hide()
        logWin = f
    end
    local scale = math.min(2.6, math.max(0.8, tonumber(DB().guideScale) or 1))
    logWin:SetScale(scale)
    logWin:Show()
    RefreshLogWindow()
end

--------------------------------------------------------------------------------
-- 2. The rules (plain functions, testable outside the game)
--------------------------------------------------------------------------------
-- A plan stop is a waypoint with a label and a quests list. Each quest entry says what is to be done through its label:
--   "Pick up: X" / "Class quest: X"  accept it      "Turn in: X"  hand it in      anything else  do its objectives
local function KindOf(q)
    local l = q.label or ""
    if l:find("^Turn in:") then return "turn" end
    if l:find("^Pick up:") or l:find("^Class quest:") then return "pick" end
    return "do"
end
addon.PlanQuestKind = KindOf

local function IsPlanStop(w)
    return w and w.label and not w.go and not w.gather and not w.guard and not w.lazy and w.quests and #w.quests > 0
end

-- env (every function may return nil for "do not know", which is never a reason to change anything):
--   inLog(id)       is the quest in my log          isComplete(id)  are its objectives done
--   isDungeon(id)   is it a dungeon quest           isSkipped(id)   did I skip it
--   instance        the world instance I am in
-- returns: problems = { { rule, text, stop, qid, fix = true|false } }, removals = { [stopIndex] = { [questIndex] = reason } }
function addon.PlanCheckStops(stops, env)
    local problems, removals = {}, {}
    local seen = {}
    local function mark(si, qi, rule, text, qid)
        removals[si] = removals[si] or {}
        removals[si][qi] = rule
        problems[#problems + 1] = { rule = rule, text = text, stop = si, qid = qid, fix = true }
    end
    for si, w in ipairs(stops or {}) do
        if IsPlanStop(w) then
            for qi, q in ipairs(w.quests) do
                local kind, id = KindOf(q), q.id
                local title = (q.label or "?"):gsub("^Turn in: ", ""):gsub("^Pick up: ", ""):gsub("^Class quest: ", "")
                if id then
                    local key = tostring(id) .. ":" .. kind
                    local inLog = env.inLog and env.inLog(id)
                    local done = env.isComplete and env.isComplete(id)
                    if seen[key] then
                        mark(si, qi, "duplicate", title .. " is in the plan twice", id)
                    elseif env.isSkipped and env.isSkipped(id) and not (kind == "turn" and done == true) then
                        mark(si, qi, "skipped", title .. " was skipped by you", id)
                    elseif kind ~= "turn" and env.isDungeon and env.isDungeon(id) and not done then
                        mark(si, qi, "dungeon", title .. " is a dungeon quest", id)
                    elseif kind == "turn" and inLog == false then
                        mark(si, qi, "handed-in", title .. " is not in your log (handed in or dropped)", id)
                    elseif kind == "do" and inLog == false then
                        mark(si, qi, "not-in-log", title .. " is not in your log, so there is nothing to do for it", id)
                    elseif kind == "pick" and inLog == true then
                        mark(si, qi, "accepted", title .. " is already accepted", id)
                    elseif kind == "turn" and inLog == true and done == false then
                        mark(si, qi, "hand-in-early", "hand-in for " .. title .. " came up before it is finished", id)
                    end
                    seen[key] = true
                end
            end
            if env.instance and w.instance and w.instance ~= env.instance then
                problems[#problems + 1] = { rule = "other-continent", stop = si,
                    text = "stop " .. si .. " (" .. tostring(w.label) .. ") is on another continent", fix = false }
            end
        end
    end
    return problems, removals
end

-- the plan with the removals applied: quests taken out of their stops, stops with nothing left dropped, labels rebuilt
function addon.PlanApplyRemovals(stops, removals)
    local out, changed = {}, false
    for si, w in ipairs(stops) do
        local r = removals[si]
        if r and IsPlanStop(w) then
            local keep = {}
            for qi, q in ipairs(w.quests) do
                if r[qi] then changed = true else keep[#keep + 1] = q end
            end
            if #keep > 0 then
                if #keep < #w.quests then
                    w.quests = keep
                    local labels = {}
                    for _, q in ipairs(keep) do labels[#labels + 1] = q.label end
                    w.label = table.concat(labels, " + ")
                end
                out[#out + 1] = w
            end
        else
            out[#out + 1] = w
        end
    end
    for i, w in ipairs(out) do
        if IsPlanStop(w) then w.name = i .. ". " .. (w.label or "") end
    end
    return out, changed
end

local function InLogFact(id)
    if not (id and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return nil end
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    if not ok then return nil end
    return (idx and idx > 0) and true or false
end

local function CompleteFact(id)
    if not (id and C_QuestLog and C_QuestLog.IsComplete) then return nil end
    local ok, c = pcall(C_QuestLog.IsComplete, id)
    if not ok then return nil end
    return c and true or false
end

local function RealEnv()
    local _, _, inst = hbd:GetPlayerWorldPosition()
    return {
        inLog = InLogFact,
        isComplete = CompleteFact,
        isDungeon = function(id) return api.IsDungeonQuest and api.IsDungeonQuest(id, false) or false end,
        isSkipped = function(id) local db = DB(); return db and db.planSkip and db.planSkip[id] and true or false end,
        instance = inst,
    }
end

-- run the check on my plan. fix = take out what breaks a rule. verbose = say so in chat.
function addon.PlanCheck(fix, verbose)
    local db = DB()
    if not (db and db.waypoints) then return 0 end
    local problems, removals = addon.PlanCheckStops(db.waypoints, RealEnv())
    local fixed = 0
    for _, p in ipairs(problems) do if p.fix then fixed = fixed + 1 end end
    if verbose then
        if #problems == 0 then
            Print(L("plan check: no problems (") .. #db.waypoints .. L(" stops looked at)"))
        else
            for _, p in ipairs(problems) do Print(L("plan check: ") .. p.text .. (p.fix and (fix and " (fixed)" or "") or " (not fixable here)")) end
        end
    end
    if fix and fixed > 0 then
        for _, p in ipairs(problems) do
            if p.fix then addon.PlanLog("check", string.format("took %s out of the plan: %s", p.qid and ("quest " .. p.qid) or "a stop", p.text)) end
        end
        local out = addon.PlanApplyRemovals(db.waypoints, removals)
        db.waypoints = out
        addon:RefreshPins()
        if addon.RefreshOptions then addon.RefreshOptions() end
        if verbose then Print(L("plan check: ") .. fixed .. L(" problem") .. (fixed == 1 and "" or "s") .. L(" fixed")) end
    end
    return #problems, fixed
end

--------------------------------------------------------------------------------
-- 3. The audit: the check by itself, and the quests the plan left out
--------------------------------------------------------------------------------
local noted = {}          -- quests already noted as left out (once each)

local function ReasonLeftOut(g, env)
    if env.isSkipped(g.id) then return "skipped by you" end
    if env.isDungeon(g.id) then return "a dungeon quest" end
    if g.tier == "grey" or g.grey then return "grey (too easy)" end
    if g.tier == "red" then return "red (too hard for now)" end
    if g.group and g.group > 1 then return "a group quest" end
    return "left out by the planner (small for the time, or not near)"
end

local function Audit()
    local db = DB()
    if not (db and not db.planPaused) then return end
    addon.PlanCheck(true, false)
    if not addon.QuestLogSpawns then return end
    local inPlan = {}
    for _, w in ipairs(db.waypoints or {}) do
        for _, q in ipairs(w.quests or {}) do if q.id then inPlan[q.id] = true end end
    end
    local env = RealEnv()
    for _, g in ipairs(addon.QuestLogSpawns()) do
        if g.id and not inPlan[g.id] and not g.complete and not noted[g.id] then
            noted[g.id] = true
            addon.PlanLog("audit", string.format("%s is in your log but not in the plan: %s", tostring(g.label), ReasonLeftOut(g, env)))
        end
    end
end

--------------------------------------------------------------------------------
-- 4. Stuck detection
--------------------------------------------------------------------------------
local STUCK_SECS = 240        -- standing at a stop this long without any progress
local STUCK_YARDS = 150
local snooze = {}             -- stop -> time until which I do not ask again
local stuck = { stop = nil, since = 0, sig = nil }
local toast

local function Signature(w)
    local parts = {}
    for _, q in ipairs(w.quests or {}) do
        local n = 0
        if C_QuestLog and C_QuestLog.GetQuestObjectives and q.id then
            local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q.id)
            if ok and type(objs) == "table" then
                for _, o in ipairs(objs) do n = n + (tonumber(o.numFulfilled) or 0) end
            end
        end
        parts[#parts + 1] = tostring(q.id) .. ":" .. tostring(InLogFact(q.id)) .. ":" .. tostring(CompleteFact(q.id)) .. ":" .. n
    end
    return table.concat(parts, "|")
end

local function ShowStuck(w)
    if not toast then
        local f = CreateFrame("Frame", "ForeverLazy_StuckToast", UIParent)
        f:SetSize(420, 96)
        f:SetPoint("TOP", 0, -330)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.text:SetPoint("TOP", 0, -12); f.text:SetWidth(396)
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -4); f.sub:SetWidth(396)
        f.skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.skip:SetSize(150, 22); f.skip:SetPoint("BOTTOMLEFT", 20, 10); f.skip:SetText(L("Skip this quest"))
        f.keep = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.keep:SetSize(130, 22); f.keep:SetPoint("LEFT", f.skip, "RIGHT", 8, 0); f.keep:SetText(L("Keep trying"))
        f:Hide()
        toast = f
    end
    local q = w.quests and w.quests[1]
    toast.text:SetText(L("Stuck here?"))
    toast.sub:SetText(string.format("You have been at \"%s\" for a few minutes and nothing has moved. Skip it and carry on?", tostring((w.label or "this stop"):gsub("^Turn in: ", ""))))
    toast.skip:SetScript("OnClick", function()
        toast:Hide()
        if q and q.id and addon.SkipQuest then
            addon.PlanLog("stuck", "you chose to skip " .. tostring(q.label) .. " after being stuck")
            addon.SkipQuest(q.id, q.label)
        end
    end)
    toast.keep:SetScript("OnClick", function() toast:Hide(); snooze[w] = GetTime() + 600 end)
    toast:Show()
    addon.PlanLog("stuck", "asked about skipping " .. tostring(w.label) .. " (no progress for " .. STUCK_SECS .. " seconds at the stop)")
end

local function StuckCheck()
    local db = DB()
    local w = db and not db.planPaused and db.waypoints and db.waypoints[1]
    if not (IsPlanStop(w) and w.x and w.instance) then stuck.stop = nil; return end
    if (UnitOnTaxi and UnitOnTaxi("player")) or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then return end
    if InCombatLockdown and InCombatLockdown() then stuck.since = GetTime(); return end       -- fighting is progress
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px or pinst ~= w.instance then stuck.stop = nil; return end
    local d = math.sqrt((w.x - px) ^ 2 + (w.y - py) ^ 2)
    local sig = Signature(w)
    if stuck.stop ~= w or d > STUCK_YARDS or stuck.sig ~= sig then
        stuck.stop, stuck.since, stuck.sig = w, GetTime(), sig        -- a new stop, moved away, or something progressed
        return
    end
    if GetTime() - stuck.since > STUCK_SECS and not (snooze[w] and snooze[w] > GetTime()) and not (toast and toast:IsShown()) then
        ShowStuck(w)
        stuck.since = GetTime()
    end
end

--------------------------------------------------------------------------------
-- 5. The plan against reality
--------------------------------------------------------------------------------
local RUN = 7
local reality = { t0 = nil, xp0 = 0, est = nil, told = false, lastCheck = 0 }
local gainedXP, lastXP, lastMax = 0, nil, nil

local function QuestXPNow(id)
    return ns.data.QuestXP(id)

end

-- XP per hour this plan should give: the XP of its quests over the walking plus the time the quests take
local function EstimatePlan()
    local db = DB()
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not (db and px) then return nil end
    local avg = (addon.HiveAvgQuestSecs and addon.HiveAvgQuestSecs()) or 420
    local xp, secs, cur, counted = 0, 0, { x = px, y = py }, {}
    for _, w in ipairs(db.waypoints or {}) do
        if IsPlanStop(w) and w.instance == pinst and w.x then
            secs = secs + math.sqrt((w.x - cur.x) ^ 2 + (w.y - cur.y) ^ 2) / RUN
            cur = w
            for _, q in ipairs(w.quests) do
                if q.id and not counted[q.id] and KindOf(q) ~= "turn" then
                    counted[q.id] = true
                    xp = xp + QuestXPNow(q.id)
                    local rate = addon.HiveQuestRate and addon.HiveQuestRate(q.id)
                    local x = QuestXPNow(q.id)
                    secs = secs + ((rate and rate > 0 and x > 0) and math.min(1800, math.max(60, x / rate * 60)) or avg)
                end
            end
        end
    end
    if xp <= 0 or secs <= 0 then return nil end
    return xp / secs * 3600, xp, secs
end

local function PlanWasBuilt()
    reality.t0 = GetTime()
    reality.xp0 = gainedXP
    reality.told = false
    local est, xp, secs = EstimatePlan()
    reality.est = est
    if est then
        addon.PlanLog("reality", string.format("this plan should give about %d XP per hour (%d XP over about %d minutes)", math.floor(est + 0.5), xp, math.floor(secs / 60 + 0.5)))
    end
end

local function RealityCheck()
    if not (reality.t0 and reality.est) or reality.told then return end
    local secs = GetTime() - reality.t0
    if secs < 900 then return end                               -- at least 15 minutes of following it
    local gained = gainedXP - reality.xp0
    local actual = gained / secs * 3600
    addon.PlanLog("reality", string.format("after %d minutes: %d XP per hour earned, %d expected", math.floor(secs / 60), math.floor(actual + 0.5), math.floor(reality.est + 0.5)))
    if actual < reality.est * 0.5 then
        reality.told = true
        Print(string.format(L("the plan is earning about %d XP per hour against the %d it promised. /lazy coach compares your other options, /lazy plan log shows what the plan has been doing."), math.floor(actual + 0.5), math.floor(reality.est + 0.5)))
    end
end

local xpEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LOGIN" }) do pcall(xpEv.RegisterEvent, xpEv, e) end
xpEv:SetScript("OnEvent", function(_, event)
    local xp, mx = UnitXP and UnitXP("player"), UnitXPMax and UnitXPMax("player")
    if not xp then return end
    if lastXP then
        if mx and lastMax and mx ~= lastMax then gainedXP = gainedXP + (lastMax - lastXP) + xp     -- a level up
        elseif xp > lastXP then gainedXP = gainedXP + (xp - lastXP) end
    end
    lastXP, lastMax = xp, mx
end)

--------------------------------------------------------------------------------
-- Wiring: log the plan's own changes, run the audit, the stuck check and the reality check
--------------------------------------------------------------------------------
local function Wrap(name, fn)
    local orig = addon[name]
    if type(orig) ~= "function" then return end
    addon[name] = function(...) return fn(orig, ...) end
end

local function FirstStop()
    local w = DB() and DB().waypoints and DB().waypoints[1]
    return w and tostring(w.name or w.label) or "nothing"
end

Wrap("PlanRoute", function(orig, self, allZones, quiet, auto, ...)
    local why = addon.planWhy or (auto and "automatic" or (quiet and "quiet request" or "you asked"))
    addon.planWhy = nil
    local flag = addon.zonePlanFlag and " (zone plan)" or ""
    local before = DB() and DB().waypoints and #DB().waypoints or 0
    local r = orig(self, allZones, quiet, auto, ...)
    local after = DB() and DB().waypoints and #DB().waypoints or 0
    addon.PlanLog("plan", string.format("rebuilt%s: %s. %d stop%s before, %d now. First: %s", flag, why, before, before == 1 and "" or "s", after, FirstStop()))
    pcall(PlanWasBuilt)
    pcall(addon.PlanCheck, true, false)
    return r
end)
Wrap("RemoveWaypoint", function(orig, self, i, ...)
    local w = DB() and DB().waypoints and DB().waypoints[i]
    if w then addon.PlanLog("stop", string.format("removed stop %s: %s", tostring(i), tostring(w.name or w.label))) end
    return orig(self, i, ...)
end)
Wrap("ClearWaypoints", function(orig, self, ...)
    addon.PlanLog("stop", "all waypoints cleared")
    return orig(self, ...)
end)
Wrap("AddWaypointZone", function(orig, self, map, zx, zy, name, ...)
    addon.PlanLog("stop", "added a waypoint: " .. tostring(name))
    return orig(self, map, zx, zy, name, ...)
end)

for _, n in ipairs({ "PlanPause", "PlanResume", "PlanZone" }) do
    local orig = addon[n]
    if type(orig) == "function" then
        addon[n] = function(...)
            addon.PlanLog("plan", n .. (n == "PlanZone" and " (/lazy level)" or ""))
            return orig(...)
        end
    end
end
do
    local orig = addon.PickupDone
    if type(orig) == "function" then
        addon.PickupDone = function(id, ...)
            addon.PlanLog("quest", "accepted quest " .. tostring(id) .. ": its accept step is done")
            return orig(id, ...)
        end
    end
    local origScrub = addon.ScrubQuest
    if type(origScrub) == "function" then
        addon.ScrubQuest = function(id, ...)
            addon.PlanLog("quest", "quest " .. tostring(id) .. " taken out of every stop (handed in, dropped or skipped)")
            return origScrub(id, ...)
        end
    end
    local origPurge = addon.PurgeDungeonStops
    if type(origPurge) == "function" then
        addon.PurgeDungeonStops = function(...)
            local n = origPurge(...)
            if n and n > 0 then addon.PlanLog("dungeon", n .. " dungeon quest stop" .. (n == 1 and "" or "s") .. " taken out") end
            return n
        end
    end
end

local tickAcc, lastAudit = 0, 0
local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(_, dt)
    tickAcc = tickAcc + dt
    if tickAcc < 5 then return end
    tickAcc = 0
    pcall(StuckCheck)
    if GetTime() - lastAudit > 30 then
        lastAudit = GetTime()
        pcall(Audit)
        pcall(RealityCheck)
    end
end)

local auditEv = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do pcall(auditEv.RegisterEvent, auditEv, e) end
auditEv:SetScript("OnEvent", function(_, event, a, b)
    addon.PlanLog("event", event .. (event == "QUEST_ACCEPTED" and (" " .. tostring(tonumber(b) or a)) or (a and (" " .. tostring(a)) or "")))
    lastAudit = GetTime() - 27          -- audit about 3 seconds after the log has settled
end)

--------------------------------------------------------------------------------
-- Commands: /lazy plan log, /lazy plan check
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "plan" then
        local arg = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if arg == "log" then addon.ShowPlanLog(); return true end
        if arg == "log clear" then DB().planLog = {}; Print(L("plan log cleared")); return true end
        if arg == "check" then addon.PlanCheck(true, true); return true end
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["PlanGuard.lua"] = true end end
