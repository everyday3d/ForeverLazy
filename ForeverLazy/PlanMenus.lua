-- The right-click menu on the plan arrow (skip, come back later, do next), profile and friend switching, and the base command handler.
-- Split out of Extras.lua.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local hbd = api.hbd
local state = addon.state
local Print = addon.Print
local X = ns.extras          -- what Extras.lua shares with the files split out of it

local function DB() return addon.GetDB() end
local mine = X.mine
local MatchesOpen, ApplyFocus, Dist, RenumberPlan, ScrubQuest, UnfinishedTexts = X.MatchesOpen, X.ApplyFocus, X.Dist, X.RenumberPlan, X.ScrubQuest, X.UnfinishedTexts
local PlainTitle = X.PlainTitle
local ReadQuestLog = api.ReadQuestLog

--------------------------------------------------------------------------------
-- Right-click the plan arrow to skip a quest (or just this stop)
--------------------------------------------------------------------------------
local function SkippedCount()
    local n = 0
    for _ in pairs(DB().planSkip or {}) do n = n + 1 end
    return n
end

local function ReplanAfterSkip()
    local db = DB()
    addon.planWhy = "the quest you skipped (or brought back) changed the plan"
    addon:PlanRoute(X.LastPlanAll() and true or false, true)
    local wps = db.waypoints
    if wps and wps[1] and wps[1].label then
        Print(L("plan updated. Next: ") .. ns.LocalizeLabel(wps[1].name))
    else
        Print(L("nothing left in the plan"))
    end
end

local function SkipQuest(id, label)
    local db = DB()
    db.planSkip = db.planSkip or {}
    db.planSkip[id] = PlainTitle(label)
    Print(L("skipping ") .. PlainTitle(label) .. L(" (/lazy skip clear brings skipped quests back)"))
    -- take it out of the plan I have right now, so it is gone even before (or if) the plan is rebuilt
    pcall(addon.ScrubQuest, id)
    if db.waypoints[1] and db.waypoints[1].label then ReplanAfterSkip() else addon:RefreshPins() end
end

addon.SkipQuest = SkipQuest

-- Come back to a quest later (a crowded spot, say). The plan simply goes on with its next stop, in its own order. The quest
-- waits; when I am near where it was (or its time is up) it is put back into the plan where it costs the least walking.
local function QuestSpotsInPlan(id)
    local recs = {}
    for _, w in ipairs(DB().waypoints or {}) do
        for _, q in ipairs(w.quests or {}) do
            if q.id == id then
                recs[#recs + 1] = { q = { id = q.id, label = q.label, src = q.src, grp = q.grp, tier = q.tier },
                                    instance = w.instance, x = w.x, y = w.y, uiMapId = w.uiMapId, zx = w.zx, zy = w.zy }
            end
        end
    end
    return recs
end

function addon.PlanLater(id, label, minutes)
    local db = DB()
    if not id then return end
    minutes = minutes or 10
    local due = (time and time() or 0) + minutes * 60
    db.planLater = db.planLater or {}
    db.planLaterStops = db.planLaterStops or {}
    local recs = QuestSpotsInPlan(id)
    db.planLater[id] = due
    db.planLaterStops[id] = { recs = recs, label = label }
    if addon.PlanLog then addon.PlanLog("plan", string.format("%s put off (come back to it later): the plan goes on with its next stop", PlainTitle(label))) end
    pcall(addon.ScrubQuest, id)                 -- out of the plan, nothing else rearranged
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    local nxt = db.waypoints[1]
    Print(string.format(L("%s put off. I will fit it back in when you are near it again (or in %d minutes). Next: %s"),
        PlainTitle(label), minutes, nxt and tostring(nxt.name or nxt.label) or "nothing left in the plan"))
end

-- put a quest I put off back into the plan, where it adds the least walking
function addon.PlanLaterReturn(id, why)
    local db = DB()
    local rec = db.planLaterStops and db.planLaterStops[id]
    if db.planLater then db.planLater[id] = nil end
    if db.planLaterStops then db.planLaterStops[id] = nil end
    if not rec then return end
    local wps = db.waypoints
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local placed = 0
    for _, r in ipairs(rec.recs or {}) do
        if r.x and r.instance then
            local start = { x = px or r.x, y = py or r.y }
            local function pt(i) return i == 0 and start or wps[i] end
            local n = #wps
            local bestPos, bestCost
            for pos = 0, n do
                local a = pt(pos)
                local b = pos < n and wps[pos + 1] or nil
                local okA = pos == 0 or (a and a.instance == r.instance and a.x)
                local okB = not b or (b.instance == r.instance and b.x)
                if okA and okB then
                    local cost = Dist(a, r) + (b and (Dist(r, b) - Dist(a, b)) or 0)
                    if not bestCost or cost < bestCost then bestPos, bestCost = pos, cost end
                end
            end
            table.insert(wps, (bestPos or 0) + 1, { name = "", label = r.q.label, instance = r.instance, x = r.x, y = r.y,
                uiMapId = r.uiMapId, zx = r.zx, zy = r.zy, quests = { r.q } })
            placed = placed + 1
        end
    end
    if placed > 0 then
        RenumberPlan(wps)
        addon:RefreshPins()
        if addon.RefreshOptions then addon.RefreshOptions() end
        Print(string.format(L("%s is back in your plan (%s)"), PlainTitle(rec.label), why or "back"))
        if addon.PlanLog then addon.PlanLog("plan", string.format("%s fitted back into the plan (%s)", PlainTitle(rec.label), why or "back")) end
    elseif addon.PlanRoute then
        addon.planWhy = "a quest you put off came back"
        pcall(addon.PlanRoute, addon, X.LastPlanAll() and true or false, true)
    end
end

-- do this quest next (the plan window and the right-click menu both use it)
function addon:FocusQuest(id, label)
    local db = DB()
    db.planFocus = { id = id, label = PlainTitle(label) }
    ApplyFocus(db.waypoints)
    -- the quest has no stop in the plan (skipped, put off, another zone...): rebuild so it gets one, it then goes first
    local has = false
    for _, q in ipairs(db.waypoints[1] and db.waypoints[1].quests or {}) do if q.id == id then has = true end end
    if not has then
        if db.planSkip and db.planSkip[id] then db.planSkip[id] = nil end
        addon.planWhy = "you picked a quest to do next"
        pcall(addon.PlanRoute, addon, X.LastPlanAll() and true or false, true)
        ApplyFocus(db.waypoints)
    end
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    local first = db.waypoints[1]
    Print(L("doing ") .. PlainTitle(label) .. L(" first, then back to the plan") .. (first and (". Next: " .. ns.LocalizeLabel(first.name)) or ""))
end

local skipMenu, skipCatcher
local function BuildSkipMenu()
    local f = CreateFrame("Frame", "ForeverLazy_SkipMenu", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetWidth(300); f.title:SetJustifyH("LEFT")
    f.rows = {}
    skipCatcher = CreateFrame("Button", nil, UIParent)
    skipCatcher:SetAllPoints(UIParent)
    skipCatcher:SetFrameStrata("FULLSCREEN")
    skipCatcher:Hide()
    skipCatcher:RegisterForClicks("AnyUp")
    skipCatcher:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnShow", function() skipCatcher:Show() end)
    f:SetScript("OnHide", function() skipCatcher:Hide() end)
    table.insert(UISpecialFrames, "ForeverLazy_SkipMenu")
    f:Hide()
    return f
end

local function MenuRow(f, i)
    local b = f.rows[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetSize(300, 20)
    b:SetPoint("TOPLEFT", 10, -26 - (i - 1) * 20)
    b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.fs:SetPoint("LEFT", 2, 0)
    b.fs:SetWidth(296); b.fs:SetJustifyH("LEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnClick", function(self)
        f:Hide()
        if self.fn then self.fn() end
    end)
    f.rows[i] = b
    return b
end

function addon:OpenSkipMenu()
    local db = DB()
    -- the first quest stop of the plan, even when something else (directions, a trip) is in front of it
    local wp, wpIndex
    for i, w in ipairs(db.waypoints) do if w.label then wp, wpIndex = w, i; break end end
    if not wp then Print(L("no plan stop to skip. /lazy plan builds a plan")); return end
    skipMenu = skipMenu or BuildSkipMenu()
    local f = skipMenu
    f.title:SetText(wp.name or wp.label)
    local items = {}
    for _, q in ipairs(wp.quests or {}) do
        local slow = addon.HiveQuestSlow and addon.HiveQuestSlow(q.id)
        items[#items + 1] = { text = "Come back to " .. PlainTitle(q.label) .. " later (too crowded?)",
                              fn = function() addon.PlanLater(q.id, q.label) end }
        items[#items + 1] = { text = "Skip quest: " .. PlainTitle(q.label) .. (slow and "  |cffff8800(slow for you)|r" or ""),
                              fn = function() SkipQuest(q.id, q.label) end }
    end
    items[#items + 1] = { text = "Do a quest from the plan now...", fn = function() addon:OpenQuestList() end }
    if db.planFocus then
        items[#items + 1] = { text = "Back to the plan (stop doing " .. tostring(db.planFocus.label) .. ")", fn = function()
            db.planFocus = nil
            Print(L("back to the plan"))
            ReplanAfterSkip()
        end }
    end
    items[#items + 1] = { text = "Skip this stop for now", fn = function()
        addon:RemoveWaypoint(wpIndex)
        local nxt = db.waypoints[1]
        Print(nxt and ("skipped. Next: " .. (ns.LocalizeLabel(nxt.name) or "?")) or "skipped. That was the last stop")
    end }
    if SkippedCount() > 0 then
        items[#items + 1] = { text = string.format("Bring back %d skipped quest%s", SkippedCount(), SkippedCount() == 1 and "" or "s"),
                              fn = function() db.planSkip = nil; Print(L("skipped quests are back in")); ReplanAfterSkip() end }
    end
    for i, it in ipairs(items) do
        local row = MenuRow(f, i)
        row.fn = it.fn
        row.fs:SetText(it.text)
        row:Show()
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(320, 36 + #items * 20)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 10, y / s + 10)
    f:Show()
end

-- pick any quest in the plan to do next, whatever its place in the order
function addon:OpenQuestList()
    local db = DB()
    skipMenu = skipMenu or BuildSkipMenu()
    local f = skipMenu
    local items, seen = {}, {}
    for _, w in ipairs(db.waypoints) do
        for _, q in ipairs(w.quests or {}) do
            if q.id and not seen[q.id] then
                seen[q.id] = true
                local lbl = q.label or ""
                local kind = lbl:find("^Turn in:") and "turn in" or ((lbl:find("^Pick up:") or lbl:find("^Class quest:")) and "pick up" or "do")
                local mark = (db.planFocus and db.planFocus.id == q.id) and "|cff55ff55> |r" or ""
                items[#items + 1] = { text = mark .. PlainTitle(lbl) .. "  |cffaaaaaa(" .. kind .. ")|r", fn = function()
                    db.planFocus = { id = q.id, label = PlainTitle(lbl) }
                    ApplyFocus(db.waypoints)
                    addon:RefreshPins()
                    if addon.RefreshOptions then addon.RefreshOptions() end
                    local first = db.waypoints[1]
                    Print(L("doing ") .. PlainTitle(lbl) .. L(" first, then back to the plan") .. (first and (". Next: " .. ns.LocalizeLabel(first.name)) or ""))
                end }
                if #items >= 14 then break end
            end
        end
        if #items >= 14 then break end
    end
    if #items == 0 then Print(L("no quests in the plan. /lazy plan builds one")); return end
    f.title:SetText(L("Do which quest now?"))
    for i, it in ipairs(items) do
        local row = MenuRow(f, i)
        row.fn = it.fn
        row.fs:SetText(it.text)
        row:Show()
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(320, 36 + #items * 20)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 10, y / s + 10)
    f:Show()
end

-- pick anyone in my party or raid for the friend arrow to follow
function addon:OpenFollowMenu()
    skipMenu = skipMenu or BuildSkipMenu()
    local f = skipMenu
    local items, seen = {}, {}
    local function add(unit)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local name = UnitName(unit)
            if name and not seen[name] then
                seen[name] = true
                local _, cls = UnitClass(unit)
                local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                local hex = c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
                items[#items + 1] = { text = hex .. name .. "|r", fn = function() addon:FollowMember(name) end }
            end
        end
    end
    for i = 1, 4 do add("party" .. i) end
    for i = 1, 40 do add("raid" .. i) end
    if #items == 0 then Print(L("you are not in a group")); return end
    items[#items + 1] = { text = "|cffaaaaaaStop pinning (follow whoever sends a step)|r", fn = function() addon:StopFollowing() end }
    f.title:SetText(L("Follow who?"))
    for i, it in ipairs(items) do
        local row = MenuRow(f, i)
        row.fn = it.fn
        row.fs:SetText(it.text)
        row:Show()
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(320, 36 + #items * 20)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 10, y / s + 10)
    f:Show()
end

-- right-click on the plan arrow
local skipHooked = CreateFrame("Frame")
pcall(skipHooked.RegisterEvent, skipHooked, "PLAYER_LOGIN")
skipHooked:SetScript("OnEvent", function()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(2, function()
        local f = api.arrows and api.arrows.waypoint
        if f then
            f:EnableMouse(true)
            f:SetScript("OnMouseUp", function(_, button)
                if button == "RightButton" then
                    if addon.OpenServicesMenu then addon:OpenServicesMenu() else addon:OpenSkipMenu() end
                end
            end)
        end
    end)
end)

local function ProfileNames()
    local names = {}
    for n in pairs(addon.GetRoot().profiles) do names[#names + 1] = n end
    table.sort(names)
    return names
end

local function SwitchProfile()
    addon:SelectProfile()
    addon:ApplyAll()
    if addon.RefreshOptions then addon.RefreshOptions() end
end

function addon:HandleExtraCommand(cmd, rest)
    local root = addon.GetRoot()
    if cmd == "selftest" or cmd == "test!" then
        addon:RunSelfTest(); return true

    elseif cmd == "own" then
        local db = DB()
        db.ownQuests = not db.ownQuests
        mine.dirty = true
        Print(L("my quest log arrow ") .. (db.ownQuests and "on" or "off"))
        return true

    elseif cmd == "follow" then
        local arg = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if arg:lower() == "off" then
            addon:StopFollowing()
        elseif arg ~= "" then
            addon:FollowMember(arg)
        elseif UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
            and (UnitInParty("target") or UnitInRaid("target")) then
            addon:FollowMember(UnitName("target"))
        else
            addon:OpenFollowMenu()
        end
        return true

    elseif cmd == "why" then
        -- explains where the plan's arrow comes from, for the quest at stop 1 (or "why all" for every quest in the log)
        local db = DB()
        local QDB = api.GetQuestie()
        if not (QDB and api.QuestieReady()) then Print(L("needs Questie loaded and ready")); return true end
        local zone = hbd:GetPlayerZone()
        local px, py = hbd:GetPlayerWorldPosition()
        local zi = zone and C_Map.GetMapInfo(zone)
        Print(string.format(L("you are in %s (map %s)"), zi and zi.name or "?", tostring(zone)))
        local ids = {}
        if (rest or ""):lower() == "all" then
            for _, q in ipairs(ReadQuestLog()) do ids[#ids + 1] = q.id end
        else
            local w = db.waypoints[1]
            if w then
                Print(string.format(L("stop 1: %s at %s %.1f, %.1f%s"), tostring(w.label or w.name), tostring(w.uiMapId and C_Map.GetMapInfo(w.uiMapId).name),
                    (w.zx or 0) * 100, (w.zy or 0) * 100, w.detail and (" - " .. w.detail) or ""))
                for _, q in ipairs(w.quests or {}) do ids[#ids + 1] = q.id end
            else
                Print(L("no stop 1, try /lazy why all"))
            end
        end
        for _, id in ipairs(ids) do
            local title = QDB.QueryQuestSingle(id, "name") or ("quest " .. id)
            local open = UnfinishedTexts(id)
            Print(string.format(L("%s (%d): open objectives: %s"), title, id, open and (#open > 0 and table.concat(open, " | ") or "none") or "unknown"))
            local obj = QDB.QueryQuestSingle(id, "objectives")
            local function show(kind, list, nameOf, spawnsOf)
                for _, c in pairs(list or {}) do
                    if c[1] then
                        local sp = {}
                        spawnsOf(sp, c[1])
                        local byMap = {}
                        for _, s in ipairs(sp) do
                            local n = s.uiMapId and C_Map.GetMapInfo(s.uiMapId) and C_Map.GetMapInfo(s.uiMapId).name or "?"
                            byMap[n] = (byMap[n] or 0) + 1
                        end
                        local parts = {}
                        for n, cnt in pairs(byMap) do parts[#parts + 1] = n .. " x" .. cnt end
                        Print(string.format("  %s %s: %s%s", kind, tostring(nameOf(c[1])), #parts > 0 and table.concat(parts, ", ") or "NO SPAWNS",
                            MatchesOpen(open, nameOf(c[1])) and "" or "  (not an open objective)"))
                    end
                end
            end
            if type(obj) == "table" then
                show("npc", obj[1], function(i) return QDB.QueryNPCSingle(i, "name") end, function(sp, i) api.AddNpcs(sp, { i }) end)
                show("object", obj[2], function(i) return QDB.QueryObjectSingle(i, "name") end, function(sp, i) api.AddObjects(sp, { i }) end)
            else
                Print(L("  Questie has no objectives for this quest"))
            end
        end
        return true

    elseif cmd == "macros" or cmd == "macro" then
        if (rest or ""):lower() == "remove" then addon.RemoveMacros() else addon.MakeMacros() end
        return true

    elseif cmd == "toggle" then
        -- one key: arrows off, and back to what they were
        local db = DB()
        if db.mode ~= "off" then
            db.lastMode = db.mode
            db.mode = "off"
        else
            db.mode = db.lastMode or "both"
        end
        Print(L("arrows ") .. (db.mode == "off" and "off" or ("on (" .. db.mode .. ")")))
        addon:RefreshPins()
        if addon.UpdateTomTom then addon:UpdateTomTom() end
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true

    elseif cmd == "skip" then
        local db = DB()
        if (rest or ""):lower() == "clear" then
            db.planSkip = nil
            Print(L("skipped quests are back in"))
            if db.waypoints[1] and db.waypoints[1].label then ReplanAfterSkip() end
        else
            local n = 0
            for _, title in pairs(db.planSkip or {}) do
                n = n + 1
                Print(L("  skipped: ") .. tostring(title))
            end
            Print(n == 0 and "no quests skipped. Right-click the plan arrow to skip one" or "/lazy skip clear brings them back")
        end
        return true

    elseif cmd == "later" or cmd == "comeback" then
        local db = DB()
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if a == "back" or a == "now" or a == "clear" then
            db.planLater = nil; db.planLaterStops = nil
            Print(L("the quests you put off are back in the plan"))
            if db.waypoints[1] and db.waypoints[1].label then ReplanAfterSkip() else addon:PlanRoute(false, true) end
        elseif a == "list" then
            local n = 0
            for id, due in pairs(db.planLater or {}) do
                n = n + 1
                local rec = db.planLaterStops and db.planLaterStops[id]
                Print(string.format(L("  %s: back when you are near it again, or in about %d minutes"), PlainTitle(rec and rec.label or ("quest " .. id)), math.max(0, math.ceil((due - time()) / 60))))
            end
            if n == 0 then Print(L("no quests put off")) end
        else
            -- put off the quests of the stop I am on
            local w = db.waypoints and db.waypoints[1]
            if w and w.quests and #w.quests > 0 then
                local list = {}
                for _, q in ipairs(w.quests) do list[#list + 1] = q end
                for _, q in ipairs(list) do addon.PlanLater(q.id, q.label) end
            else
                Print(L("nothing to put off: the arrow is not on a quest stop"))
            end
        end
        return true

    elseif cmd == "steps" or cmd == "step" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if a == "on" or a == "show" then addon.ToggleSteps(true)
        elseif a == "off" or a == "hide" then addon.ToggleSteps(false)
        elseif a == "auto" then DB().stepsAuto = DB().stepsAuto == false; Print(L("the step window shows by itself: ") .. tostring(DB().stepsAuto ~= false))
        else addon.ToggleSteps() end
        return true

    elseif cmd == "level" or cmd == "levelzone" then
        addon.PlanZone(rest)
        return true

    elseif cmd == "plan" or cmd == "route!" then
        local arg = (rest or ""):lower()
        if arg == "debug" then addon.PlanDebug(); return true end
        if arg == "zone" or arg == "level" then addon.PlanZone(); return true end
        if arg == "off" or arg == "pause" or arg == "stop" then addon.PlanPause(); return true end
        if arg == "on" or arg == "resume" or arg == "continue" then addon.PlanResume(); return true end
        addon:PlanRoute((rest or ""):lower() == "all"); return true

    elseif cmd == "compass" then
        local db = DB()
        db.compassBar = not db.compassBar
        Print(L("compass bar ") .. (db.compassBar and "on" or "off"))
        return true

    elseif cmd == "friend" then
        if rest == "" then
            local names = {}
            for n in pairs(state.friends) do names[#names + 1] = n end
            table.sort(names)
            Print(L("friends heard from: ") .. (#names > 0 and table.concat(names, ", ") or "none"))
            Print(L("following: ") .. tostring(state.friend) .. (state.pinned and " (pinned)" or " (latest sender)"))
            Print(L("/lazy friend <name> to pin, /lazy friend auto to follow whoever sent last"))
        elseif rest:lower() == "auto" then
            state.pinned = nil
            Print(L("following the latest sender"))
        else
            addon:SelectFriend(rest, true)
        end
        return true

    elseif cmd == "route" then
        local db = DB()
        local sub, name = rest:match("^(%S*)%s*(.*)$")
        sub = (sub or ""):lower()
        if sub == "save" and name ~= "" then
            db.routes[name] = api.DeepCopy(db.waypoints)
            Print(string.format(L("route '%s' saved (%d waypoints)"), name, #db.waypoints))
        elseif sub == "load" and name ~= "" then
            if db.routes[name] then
                db.waypoints = api.DeepCopy(db.routes[name])
                addon:RefreshPins()
                Print(string.format(L("route '%s' loaded (%d waypoints)"), name, #db.waypoints))
            else
                Print(L("no route named ") .. name)
            end
        elseif sub == "delete" and name ~= "" then
            db.routes[name] = nil
            Print(L("route '") .. name .. L("' deleted"))
        elseif sub == "list" or sub == "" then
            local any = false
            for n, r in pairs(db.routes) do any = true; Print(string.format(L("%s (%d waypoints)"), n, #r)) end
            if not any then Print(L("no routes. /lazy route save <name> stores your current waypoints")) end
        else
            Print(L("usage: /lazy route save|load|delete <name>  or  /lazy route list"))
        end
        return true

    elseif cmd == "profile" then
        local sub, name = rest:match("^(%S*)%s*(.*)$")
        sub = (sub or ""):lower()
        if sub == "" or sub == "list" then
            local names = ProfileNames()
            Print(L("active: ") .. (root.useChar and "this character" or (root.active or "default")))
            Print(L("profiles: default") .. (#names > 0 and (", " .. table.concat(names, ", ")) or ""))
        elseif sub == "new" and name ~= "" then
            root.profiles[name] = api.DeepCopy(DB())
            root.active = name
            root.useChar = false
            SwitchProfile()
            Print(L("created and switched to profile ") .. name)
        elseif (sub == "use" or sub == "switch") and name ~= "" then
            if name:lower() == "default" then root.active = nil
            elseif root.profiles[name] then root.active = name
            else Print(L("no profile named ") .. name); return true end
            root.useChar = false
            SwitchProfile()
            Print(L("using profile ") .. (root.active or "default"))
        elseif sub == "delete" and name ~= "" then
            root.profiles[name] = nil
            if root.active == name then root.active = nil end
            SwitchProfile()
            Print(L("deleted profile ") .. name)
        else
            Print(L("usage: /lazy profile list | new <name> | use <name> | delete <name>"))
        end
        return true
    end
    return false
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["PlanMenus.lua"] = true end end
