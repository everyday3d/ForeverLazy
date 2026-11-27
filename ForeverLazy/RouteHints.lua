-- Follow the levelling route (off until you turn it on). With it on, the arrow follows a 1-60 route's order of quests instead of
-- the plan's own XP-weighted order: pick up this quest, do it, hand it in, then the next one the route says.
--   /lazy route on|off   switch it on or off         /lazy route   show or hide the little panel
--   /lazy route list     the next pick-ups in chat   /lazy route skips   quests in your log that the route leaves out
-- The route is PoleStar's 1-60 guide (GPL-3.0, as converted for OpenXP 2.0): only the ORDER of its quests is used (data/Route.lua).
-- It finds how far along the route you are (the furthest route quest you have done or are doing), then takes the first step
-- you can do: pick up a quest (race, class, level and the quests before it all fit), finish one you are on, hand one in.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local data = ns.data
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On() local d = DB(); return d and d.routeHints == true end

local BEHIND, AHEAD = 30, 80          -- how far back (missed ones) and ahead in the route to look
local SHOW = 3                        -- how many to offer at once

--------------------------------------------------------------------------------
-- The route (pure logic: tests/route.lua)
--------------------------------------------------------------------------------
local function Norm(s) return (tostring(s or ""):lower():gsub("[%s_%-]", "")) end

-- the steps of the route for this faction, race and class, in order: { kind = "a"|"t", id =, class = "warlock" or nil, optional = bool }
function addon.RouteSteps(route, faction, raceToken, raceName)
    local out = {}
    local fac, tok, nam = Norm(faction), Norm(raceToken), Norm(raceName)
    for _, g in ipairs((route and route[faction]) or {}) do
        local only = Norm(g.only)
        local mine = only == "" or only == fac or only == tok or only == nam
        if not mine and only:find("skyborne", 1, true) and (tok:find("skyborne", 1, true) or nam:find("skyborne", 1, true)) then mine = true end
        if mine then
            for token in tostring(g.steps or ""):gmatch("%S+") do
                local kind, id = token:match("^(%a)(%d+)")
                if kind == "a" or kind == "t" then
                    out[#out + 1] = { kind = kind, id = tonumber(id), class = (token:match("!(%a+)") or ""):lower(), optional = token:find("?", 1, true) ~= nil }
                end
            end
        end
    end
    return out
end

-- ctx: { done(id), inLog(id), available(id) (my race, class, level and the quests before it), class = "warlock" }
-- returns the next quests to pick up (ids, at most max) and how far along the route I am (a step number)
function addon.RouteNextPickups(steps, ctx, max)
    local function Mine(s) return s.class == "" or s.class == ctx.class end
    local progress = 0
    for i, s in ipairs(steps) do
        if s.kind == "a" and Mine(s) and (ctx.done(s.id) or ctx.inLog(s.id)) then progress = i end
    end
    local out, seen = {}, {}
    for i = math.max(1, progress - BEHIND), math.min(#steps, progress + AHEAD) do
        local s = steps[i]
        if s.kind == "a" and not s.optional and Mine(s) and not seen[s.id] and not ctx.done(s.id) and not ctx.inLog(s.id) and ctx.available(s.id) then
            seen[s.id] = true
            out[#out + 1] = s.id
            if #out >= (max or SHOW) then break end
        end
    end
    return out, progress
end

-- the step to do now: { act = "pickup"|"objectives"|"turnin", id = quest, index = step number } or nil
--   ctx adds: complete(id) (a quest in my log that is finished)
function addon.RouteCurrentStep(steps, ctx)
    local function Mine(s) return s.class == "" or s.class == ctx.class end
    local progress = 0
    for i, s in ipairs(steps) do
        if s.kind == "a" and Mine(s) and (ctx.done(s.id) or ctx.inLog(s.id)) then progress = i end
    end
    for i = math.max(1, progress - BEHIND), math.min(#steps, progress + AHEAD) do
        local s = steps[i]
        if Mine(s) then
            if s.kind == "a" then
                if not s.optional and not ctx.done(s.id) and not ctx.inLog(s.id) and ctx.available(s.id) then return { act = "pickup", id = s.id, index = i } end
            elseif ctx.inLog(s.id) and not ctx.done(s.id) then
                return { act = (ctx.complete and ctx.complete(s.id)) and "turnin" or "objectives", id = s.id, index = i }
            end
        end
    end
    return nil
end

-- quests in my log that no step of the route mentions
function addon.RouteSkips(steps, logIds)
    local inRoute = {}
    for _, s in ipairs(steps) do inRoute[s.id] = true end
    local out = {}
    for _, id in ipairs(logIds) do if not inRoute[id] then out[#out + 1] = id end end
    return out
end

--------------------------------------------------------------------------------
-- Reading my character and my quests
--------------------------------------------------------------------------------
local function Field(kind, id, name)
    local ok, v = pcall(data.Field, kind, id, name)
    if ok then return v end
end

local function Mask(mask, n)
    mask = tonumber(mask)
    if not mask or mask == 0 or not n then return true end
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

local cache = {}
local function Context()
    local raceName, raceToken, raceId = UnitRace("player")
    local _, classToken, classId = UnitClass("player")
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local level = UnitLevel("player") or 1
    local function Done(id) return addon.QuestCompleted and addon.QuestCompleted(id) or false end
    local function Available(id)
        if Field("quests", id, "name") == nil then return false end                               -- not in our data: not offered
        if not (Mask(Field("quests", id, "requiredRaces"), raceId) and Mask(Field("quests", id, "requiredClasses"), classId)) then return false end
        if (tonumber(Field("quests", id, "requiredLevel")) or 0) > level then return false end
        if (tonumber(Field("quests", id, "questLevel")) or 0) > level + 5 then return false end
        -- the quests that must be done first
        local group = Field("quests", id, "preQuestGroup")
        if type(group) == "table" then for _, q in ipairs(group) do if not Done(q) then return false end end end
        local single = Field("quests", id, "preQuestSingle")
        if type(single) == "table" and #single > 0 then
            local any = false
            for _, q in ipairs(single) do if Done(q) then any = true; break end end
            if not any then return false end
        end
        return true
    end
    return { faction = faction, raceToken = raceToken, raceName = raceName, class = Norm(classToken), done = Done,
             inLog = function(id) return addon.QuestInLog and addon.QuestInLog(id) or false end, available = Available, level = level,
             complete = function(id) local ok, c = pcall(C_QuestLog.IsComplete, id); return ok and c == true end }
end

local steps, stepsFor
local function MySteps(ctx)
    local key = tostring(ctx.faction) .. "|" .. tostring(ctx.raceToken)
    if stepsFor ~= key then
        stepsFor = key
        steps = addon.RouteSteps(ns.dataset and ns.dataset.route, ctx.faction, ctx.raceToken, ctx.raceName)
    end
    return steps
end

local function LogIds()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
            local ok, info = pcall(C_QuestLog.GetInfo, i)
            if ok and type(info) == "table" and not info.isHeader and info.questID then out[#out + 1] = info.questID end
        end
    end
    return out
end

-- what the route offers now: { ids = {...}, progress = n, skips = {...}, total = n }
function addon.RouteNow()
    local ctx = Context()
    if not ctx.faction then return { ids = {}, skips = {}, progress = 0, total = 0 } end
    local st = MySteps(ctx)
    local step = addon.RouteCurrentStep(st, ctx)
    local ids, progress = addon.RouteNextPickups(st, ctx, SHOW + 1)
    -- the next pick-ups after the one being done now
    local later = {}
    for _, id in ipairs(ids) do if not (step and step.act == "pickup" and step.id == id) and #later < SHOW - 1 then later[#later + 1] = id end end
    return { step = step, ids = later, progress = progress, total = #st, skips = addon.RouteSkips(st, LogIds()) }
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------
local frame

local function Scale()
    local db = DB()
    return math.min(2.6, math.max(0.7, tonumber(db and db.routeScale) or 1))
end
local function SavedSize()
    local db = DB()
    return db and db.pos and db.pos.routeSize
end

local function Giver(id)
    local by = Field("quests", id, "startedBy")
    local npc = type(by) == "table" and type(by[1]) == "table" and by[1][1]
    return npc and Field("npcs", npc, "name") or nil
end

local function ZoneOf(id)
    local z = tonumber(Field("quests", id, "zoneOrSort")) or 0
    if z > 0 and addon.AreaLabel then return addon.AreaLabel(z) end
end

local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_Route", UIParent)
    local size = SavedSize()
    f:SetSize(size and size.w or 250, 22)
    f:SetResizable(true)
    pcall(f.SetResizeBounds, f, 200, 40, 800, 500)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
    local head = CreateFrame("Button", nil, f)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(16)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() if not DB().locked then f:StartMoving() end end)
    head:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        DB().pos = DB().pos or {}
        DB().pos.route = { point = point, x = x, y = y }
    end)
    -- text size (the whole panel scales, like the quest tracker): A- smaller, A+ bigger
    local function SizeButton(text, anchor, delta)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(24, 14); b:SetText(text)
        b:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
        b:SetFrameLevel(f:GetFrameLevel() + 6)
        b:SetScript("OnClick", function()
            DB().routeScale = math.min(2.6, math.max(0.7, Scale() + delta))
            f:SetScale(Scale())
        end)
        return b
    end
    local anchor = CreateFrame("Frame", nil, f)
    anchor:SetSize(1, 1); anchor:SetPoint("TOPRIGHT", -4, -1)
    local bigger = SizeButton("A+", anchor, 0.15)
    SizeButton("A-", bigger, -0.15)
    -- resize from the corner
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f.sizing = true; f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing(); f.sizing = false
        DB().pos = DB().pos or {}
        DB().pos.routeSize = { w = f:GetWidth(), h = f:GetHeight() }
    end)
    f.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("LEFT", 6, 0)
    f.title:SetText(L("Route: pick up next"))
    f.rows = {}
    for i = 1, SHOW do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(16)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -17 - (i - 1) * 17)
        r:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        r:RegisterForClicks("LeftButtonUp")
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 2, 0); r.text:SetPoint("RIGHT", -2, 0); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
            if not self.id then return end
            if self.act == "objectives" and addon.FocusQuest then addon:FocusQuest(self.id, self.qname)
            elseif addon.QuestPointAt then addon.QuestPointAt(self.id, self.qname) end
        end)
        r:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self.qname or "?", 1, 0.82, 0)
            local giver, zone = Giver(self.id), ZoneOf(self.id)
            if giver then GameTooltip:AddLine(L("From: ") .. giver, 1, 1, 1) end
            if zone then GameTooltip:AddLine(zone, 0.7, 0.7, 0.7) end
            GameTooltip:AddLine(self.act == "pickup" and L("Click: point the arrow at where to pick it up.") or L("Click: point the arrow here."), 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = r
    end
    f.foot = CreateFrame("Button", nil, f)
    f.foot:SetHeight(14)
    f.foot.text = f.foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.foot.text:SetPoint("LEFT", 2, 0)
    f.foot:SetScript("OnEnter", function(self)
        if not self.skips or #self.skips == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L("In your log, but not on the route:"), 1, 0.82, 0)
        for i = 1, math.min(12, #self.skips) do
            GameTooltip:AddLine(tostring(Field("quests", self.skips[i], "name") or ("quest " .. self.skips[i])), 0.8, 0.8, 0.8)
        end
        if #self.skips > 12 then GameTooltip:AddLine(string.format(L("... and %d more"), #self.skips - 12), 0.5, 0.5, 0.5) end
        GameTooltip:AddLine(L("The route may leave them out because they are slow or optional: your call."), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    f.foot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local pos = DB() and DB().pos and DB().pos.route or { point = "TOP", x = 0, y = -100 }          -- top centre: clear of the tracker and the minimap
    f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    f:Hide()
    return f
end

local Follow                 -- defined below Refresh (Refresh calls it)

local function Refresh()
    local db = DB()
    if not db then return end
    if not On() then if frame then frame:Hide() end; return end
    frame = frame or Build()
    local now = addon.RouteNow()
    Follow(now.step)
    if db.routePanel == false then frame:Hide(); return end
    -- the step being done now first, then the next pick-ups
    local entries = {}
    if now.step then entries[1] = { id = now.step.id, act = now.step.act, now = true } end
    for _, id in ipairs(now.ids) do entries[#entries + 1] = { id = id, act = "pickup" } end
    local VERB = { pickup = L("Pick up"), objectives = L("Do"), turnin = L("Hand in") }
    local shown = 0
    for i = 1, SHOW do
        local r, e = frame.rows[i], entries[i]
        if e then
            local name = Field("quests", e.id, "name") or ("quest " .. e.id)
            local lvl = tonumber(Field("quests", e.id, "questLevel")) or 0
            local zone = ZoneOf(e.id)
            r.id, r.qname, r.act = e.id, name, e.act
            r.text:SetText(string.format("%s%s|r |cffcccccc[%d]|r %s%s", e.now and "|cff55ff55" or "|cff999999", VERB[e.act] or "", lvl, name, zone and ("  |cff888888" .. zone .. "|r") or ""))
            r:Show(); shown = shown + 1
        else
            r.id = nil; r:Hide()
        end
    end
    local footer = ""
    if #now.skips > 0 then footer = string.format(L("%d in your log are not on the route"), #now.skips) end
    if shown == 0 then
        frame.rows[1].id = nil; frame.rows[1]:Show()
        frame.rows[1].text:SetText("|cff888888" .. ((now.total == 0) and L("no route for your faction") or L("nothing to do on the route right now")) .. "|r")
        shown = 1
    end
    frame.foot:ClearAllPoints()
    frame.foot:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -17 - shown * 17)
    frame.foot:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    frame.foot.text:SetText("|cff777777" .. footer .. "|r")
    frame.foot.skips = now.skips
    frame.foot:SetShown(footer ~= "")
    frame:SetScale(Scale())
    if not frame.sizing then
        local content = 20 + shown * 17 + (footer ~= "" and 14 or 0)
        local size = SavedSize()
        frame:SetHeight(math.max(content, size and size.h or 0))
    end
    frame:Show()
end
-- With the route on, the arrow goes where the route's current step says. It moves only when the step changes.
local lastStep, lastAt = nil, 0
function Follow(step)
    if not On() then return end
    local key = step and (step.act .. ":" .. step.id) or "none"
    if key == lastStep then return end
    if GetTime() - lastAt < 2 then return end                                   -- not twice in a breath
    lastStep, lastAt = key, GetTime()
    if not step then return end
    local name = Field("quests", step.id, "name") or ("quest " .. step.id)
    if step.act == "objectives" then
        if addon.FocusQuest then pcall(addon.FocusQuest, addon, step.id, name) end
    else
        if addon.QuestPointAt then pcall(addon.QuestPointAt, step.id, name) end
        local giver = Giver(step.id)
        Print(string.format(L("route: %s %s%s"), step.act == "pickup" and L("pick up") or L("hand in"), name, giver and (" (" .. giver .. ")") or ""))
    end
end

addon.RouteRefresh = Refresh

-- a refresh that never fails silently: the first error is said in chat (once)
local lastErr
local function SafeRefresh()
    local ok, err = pcall(Refresh)
    if not ok and tostring(err) ~= lastErr then lastErr = tostring(err); Print(L("route: an error stopped the panel: ") .. lastErr) end
end

local pending
local function Soon()
    if not On() then return end
    if pending or not (C_Timer and C_Timer.After) then SafeRefresh(); return end
    pending = true
    C_Timer.After(1.0, function() pending = false; SafeRefresh() end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED",
                     "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if C_Timer then C_Timer.After(6, SafeRefresh) end                               -- the quest list is read in the background first
        return
    end
    Soon()
end)

--------------------------------------------------------------------------------
-- /lazy route
--------------------------------------------------------------------------------
-- Switching the route off: forget what the route pointed at and rebuild the plan, so the arrow goes back to the plan's next stop.
local function ToPlan()
    local db = DB()
    if not db then return end
    lastStep = nil
    db.planFocus = nil
    for i = #(db.waypoints or {}), 1, -1 do
        if db.waypoints[i].questMapPin then table.remove(db.waypoints, i) end
    end
    local X = ns.extras
    addon.planWhy = "the levelling route was switched off"
    local ok = addon.PlanRoute and pcall(addon.PlanRoute, addon, (X and X.LastPlanAll and X.LastPlanAll()) and true or false, true)
    local wp = db.waypoints and db.waypoints[1]
    if ok and wp and wp.name then
        Print(L("route: off, back to the plan. Next: ") .. tostring(ns.LocalizeLabel and ns.LocalizeLabel(wp.name) or wp.name))
    else
        Print(L("route: off, the plan's own order is back"))
    end
    if addon.RefreshPins then pcall(addon.RefreshPins, addon) end
end

addon.RouteToPlan = ToPlan

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "route" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        -- my saved waypoint routes use this word too: save, load and delete are theirs, and so is list while the route is off
        local word = a:match("^%S*")
        if prev and (word == "save" or word == "load" or word == "delete" or (a == "list" and not On())) then return prev(self, cmd, rest) end
        if a == "on" then db.routeHints = true; db.routePanel = nil; Print(L("route: on. The arrow now follows the levelling route (pick up, do, hand in, next quest) instead of the plan's own order. /lazy route off switches it off."))
        elseif a == "off" then db.routeHints = nil; ToPlan()
        elseif a == "list" or a == "skips" then
            if not On() then Print(L("the route is off: /lazy route on")); return true end
            local now = addon.RouteNow()
            if a == "list" then
                local ctx = Context()
                local st = MySteps(ctx)
                local ids = addon.RouteNextPickups(st, ctx, 10)
                if #ids == 0 then Print(L("route: nothing new to pick up (step ") .. now.progress .. "/" .. now.total .. ")") end
                for i, id in ipairs(ids) do Print(string.format("route %d: [%s] %s%s", i, tostring(Field("quests", id, "questLevel") or "?"),
                    tostring(Field("quests", id, "name") or id), Giver(id) and (" - " .. Giver(id)) or "")) end
            else
                if #now.skips == 0 then Print(L("route: every quest in your log is on the route")) end
                for _, id in ipairs(now.skips) do Print("route skip: " .. tostring(Field("quests", id, "name") or id)) end
            end
            return true
        elseif a == "reset" then
            if db.pos then db.pos.route = nil; db.pos.routeSize = nil end
            db.routeScale = nil
            db.routeHints = true; db.routePanel = nil
            if frame then frame:SetSize(250, 22); frame:SetScale(1) end
            if frame then frame:ClearAllPoints(); frame:SetPoint("TOP", UIParent, "TOP", 0, -100) end
            Print(L("route: panel put back at the top centre of the screen"))
        else
            -- plain /lazy route: show or hide the panel (turns the feature on first time)
            if not On() then db.routeHints = true; db.routePanel = nil; Print(L("route: on. The arrow now follows the levelling route (pick up, do, hand in, next quest) instead of the plan's own order. /lazy route off switches it off."))
            else db.routePanel = (db.routePanel == false) and nil or false end
        end
        if addon.RefreshOptions then addon.RefreshOptions() end
        local okR, errR = pcall(Refresh)
        if not okR then Print(L("route: an error stopped the panel: ") .. tostring(errR))
        elseif On() then
            Print(frame and frame:IsShown() and L("route: the panel is showing (top centre of the screen; /lazy route reset puts it there)") or L("route: on, but the panel is hidden (/lazy route shows it)"))
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["RouteHints.lua"] = true end end
