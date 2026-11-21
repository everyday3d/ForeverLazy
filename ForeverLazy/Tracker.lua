-- Forever Lazy's own quest tracker. It can take the place of WoW's.
--   quests in the order of my plan (the one I am on first), then the rest of my log
--   each with its level colour, XP, live objectives, and what to do when it is finished (turn it in to whom, where)
--   left-click: do this quest next (the arrow follows)   shift-click: link it in chat   right-click: more
--   a quest item button sits on the quest row
-- Options: use it (and hide WoW's tracker), no background, text size (A- / A+), drag the corner to resize.
-- Questie's tracker is another addon: turn it off in Questie's own options.
--   /lazy tracker [on|off]
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local MAXROWS = 24
local win, rows = nil, {}
local rowQuest = {}                 -- row index -> quest id it shows (only changed out of combat: the item buttons are secure)
local dirty, dirtyAfterCombat = true, false
local built = false

--------------------------------------------------------------------------------
-- What to show
--------------------------------------------------------------------------------
local function Questie() return api.GetQuestie and api.GetQuestie() end

local function NpcName(QDB, id, field)
    local by = QDB and QDB.QueryQuestSingle(id, field)
    local npc = by and by[1] and by[1][1] and QDB.QueryNPCSingle(by[1][1], "name")
    if not npc and by and by[2] and by[2][1] then npc = QDB.QueryObjectSingle(by[2][1], "name") end
    return npc
end

local function QuestXP(id)
    return ns.data.QuestXP(id)

end

-- Inside a dungeon: the quests that have something to do in it, found from where their objectives are (so a class quest that
-- needs this dungeon counts even when it is not tagged as a dungeon quest).
local dcache = { name = nil, t = 0, ids = {} }
local function DungeonIds()
    local name, itype = GetInstanceInfo and GetInstanceInfo()
    if not name or (itype ~= "party" and itype ~= "raid") then return nil end
    if dcache.name == name and GetTime() - dcache.t < 10 then return dcache.ids end
    local ids = {}
    if addon.DungeonQuestsHere then
        for _, dq in ipairs(addon.DungeonQuestsHere(name)) do ids[dq.id] = true end
    end
    dcache = { name = name, t = GetTime(), ids = ids }
    return ids
end

-- quests in plan order, then the rest of the log
-- Outside a dungeon its quests stay out of sight (apart from one that is finished and waits for its hand-in); inside, only
-- the quests that have something to do in THIS dungeon are shown.
local function QuestList()
    local out, seen = {}, {}
    if not api.ReadQuestLog then return out end
    local log = api.ReadQuestLog()
    local byId = {}
    for _, q in ipairs(log) do if q.id then byId[q.id] = q end end
    local db = DB()
    if db and not db.planPaused then
        for _, w in ipairs(db.waypoints or {}) do
            for _, qe in ipairs(w.quests or {}) do
                local q = qe.id and byId[qe.id]
                if q and not seen[q.id] then seen[q.id] = true; out[#out + 1] = { q = q, inPlan = true } end
            end
        end
    end
    for _, q in ipairs(log) do
        if q.id and not seen[q.id] then seen[q.id] = true; out[#out + 1] = { q = q, inPlan = false } end
    end
    local here = DungeonIds()
    local kept = {}
    for _, e in ipairs(out) do
        local q = e.q
        local isDungeon = api.IsDungeonQuest and api.IsDungeonQuest(q.id, q.complete) or false
        local show
        if here then
            -- only this dungeon's quests (not the ones for other dungeons)
            show = here[q.id] and true or false
        else
            show = q.complete or not isDungeon
        end
        if show then kept[#kept + 1] = e end
    end
    return kept
end

local function LevelColour(level)
    if GetQuestDifficultyColor and level and level > 0 then
        local c = GetQuestDifficultyColor(level)
        if c then return string.format("|cff%02x%02x%02x", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255) end
    end
    return "|cffffffff"
end

-- title text and body text of one quest
local function Describe(e, first)
    local q = e.q
    local QDB = Questie()
    local dungeon = api.IsDungeonQuest and api.IsDungeonQuest(q.id, q.complete)
    local xp = QuestXP(q.id)
    local lvl = q.level or 0
    local head = string.format("%s%s[%s]|r %s%s%s", first and "|cffffd100> |r" or "", LevelColour(lvl), lvl > 0 and lvl or "?",
        dungeon and "|cff999999" or "|cffffffff", tostring(q.title or ("quest " .. q.id)), "|r")
    if xp > 0 then head = head .. "  |cff80c0ff" .. xp .. " xp|r" end
    if dungeon then head = head .. "  |cff999999(dungeon)|r" end
    local db = DB()
    if db and db.planLater and db.planLater[q.id] and db.planLater[q.id] > (time and time() or 0) then head = head .. "  |cffff9933(later)|r" end
    local lines = {}
    if q.complete then
        local npc = QDB and NpcName(QDB, q.id, "finishedBy")
        -- the whole line in green, so a quest you can hand in stands out
        lines[#lines + 1] = "|cff55ff55Ready: turn in" .. (npc and (" to " .. npc) or "") .. "|r"
    else
        local added = false
        if C_QuestLog and C_QuestLog.GetQuestObjectives then
            local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q.id)
            if ok and type(objs) == "table" then
                for _, o in ipairs(objs) do
                    if o.text and o.text ~= "" then
                        added = true
                        lines[#lines + 1] = (o.finished and "|cff55ff55" or "|cffffffff") .. "- " .. o.text .. "|r"
                    end
                end
            end
        end
        if not added then lines[#lines + 1] = "|cff999999- (no objective text)|r" end
    end
    return head, table.concat(lines, "\n")
end

local function LogIndex(id)
    if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return nil end
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    return ok and idx and idx > 0 and idx or nil
end

local function SpecialItem(id)
    local idx = LogIndex(id)
    if not (idx and GetQuestLogSpecialItemInfo) then return nil end
    local ok, link = pcall(GetQuestLogSpecialItemInfo, idx)
    if not (ok and link) then return nil end
    local itemStr = link:match("item:%d+")
    if not itemStr then return nil end
    -- an item that only started the quest (it is in the quest's "started by" and is not one of its objectives) has done its job
    local itemId = tonumber(itemStr:match("%d+"))
    local data = ns and ns.data
    if itemId and data and data.Field then
        local okS, by = pcall(data.Field, "quests", id, "startedBy")
        if okS and type(by) == "table" and type(by[3]) == "table" then
            local starter = false
            for _, v in pairs(by[3]) do if v == itemId then starter = true; break end end
            if starter then
                local needed = false
                local okO, o = pcall(data.Field, "quests", id, "objectives")
                if okO and type(o) == "table" then
                    for _, e in ipairs(o[3] or {}) do if e[1] == itemId then needed = true; break end end
                end
                local okR, req = pcall(data.Field, "quests", id, "requiredSourceItems")
                if okR and type(req) == "table" then
                    for _, v in pairs(req) do if v == itemId then needed = true; break end end
                end
                if not needed then return nil end
            end
        end
    end
    return link, itemStr, (GetItemIcon and GetItemIcon(itemStr)) or select(10, GetItemInfo(link))
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------
local function Select(id) if C_QuestLog and C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, id) end end

local function OpenMenu(q)
    local items = {
        { text = "Do this quest next", fn = function() if addon.FocusQuest then addon:FocusQuest(q.id, q.title) end end },
        { text = "Come back to this quest later (too crowded?)", fn = function() if addon.PlanLater then addon.PlanLater(q.id, q.title) end end },
        { text = "Skip this quest (keep it out of the plan)", fn = function() if addon.SkipQuest then addon.SkipQuest(q.id, q.title) end end },
        { text = "Show in the quest log", fn = function()
            Select(q.id)
            if QuestMapFrame_OpenToQuestDetails then pcall(QuestMapFrame_OpenToQuestDetails, q.id)
            elseif ToggleQuestLog then pcall(ToggleQuestLog) end
        end },
        { text = "Share with my group", fn = function() Select(q.id); if QuestLogPushQuest then pcall(QuestLogPushQuest) end end },
        { text = "Abandon the quest...", fn = function()
            Select(q.id)
            if C_QuestLog and C_QuestLog.SetAbandonQuest then pcall(C_QuestLog.SetAbandonQuest) end
            if StaticPopup_Show then StaticPopup_Show("ABANDON_QUEST", q.title) end
        end },
    }
    if addon.ShowMenu then addon.ShowMenu(items, tostring(q.title or "Quest")) end
end

local function RowClick(self, button)
    local q = self.quest
    if not q then return end
    if button == "RightButton" then OpenMenu(q); return end
    if IsShiftKeyDown() then
        local link = GetQuestLink and GetQuestLink(q.id)
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        return
    end
    -- ctrl-click: do this quest next; a plain click opens the quest in the quest log
    if IsControlKeyDown and IsControlKeyDown() then
        if addon.FocusQuest then addon:FocusQuest(q.id, q.title) end
        dirty = true
        return
    end
    Select(q.id)
    if QuestMapFrame_OpenToQuestDetails then pcall(QuestMapFrame_OpenToQuestDetails, q.id)
    elseif ToggleQuestLog then
        if not (QuestLogFrame and QuestLogFrame:IsShown()) then pcall(ToggleQuestLog) end
    end
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local function Scale()
    local db = DB()
    return math.min(2.6, math.max(0.7, tonumber(db.trackerScale) or tonumber(db.guideScale) or 1))
end

local function ApplyLook()
    if not win then return end
    local db = DB()
    local noBg = db.trackerNoBg == true
    win.bg:SetShown(not noBg)
    win.border:SetShown(not noBg)
    -- without a background the text needs an outline to stay readable
    local flags = noBg and "OUTLINE" or ""
    for _, fs in ipairs({ win.title }) do
        local font, size = fs:GetFont()
        if font then fs:SetFont(font, size, flags) end
    end
    for _, r in ipairs(rows) do
        for _, fs in ipairs({ r.title, r.body }) do
            local font, size = fs:GetFont()
            if font then fs:SetFont(font, size, flags) end
        end
    end
end

local function UpdateBar()
    if not (win and win.bar and win.scroll) then return end
    local range = win.scroll:GetVerticalScrollRange() or 0
    if range <= 1 or win.collapsedNow then win.bar:Hide(); return end
    local viewH = win.scroll:GetHeight() or 1
    local barH = math.max(16, viewH * viewH / (viewH + range))
    local off = ((win.scroll:GetVerticalScroll() or 0) / range) * (viewH - barH)
    win.bar:ClearAllPoints()
    win.bar:SetPoint("TOPRIGHT", win.scroll, "TOPRIGHT", 5, -off)
    win.bar:SetSize(3, barH)
    win.bar:Show()
end

local function SaveSize(f)
    local db = DB()
    if db then db.pos = db.pos or {}; db.pos.trackerSize = { w = f:GetWidth(), h = f:GetHeight() } end
end

local function BuildRow(i)
    local r = CreateFrame("Button", nil, win.content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", RowClick)
    -- the whole list drags the window too (a button does not hand a drag on by itself)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function() if not DB().locked then win:StartMoving() end end)
    r:SetScript("OnDragStop", function() local h = win:GetScript("OnDragStop"); if h then h(win) end end)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetJustifyH("LEFT")
    r.title:SetPoint("TOPLEFT", 0, 0)
    r.body = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.body:SetJustifyH("LEFT"); r.body:SetJustifyV("TOP")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    -- the quest item button (secure: set up only out of combat)
    local b = CreateFrame("Button", "ForeverLazy_TrackerItem" .. i, r, "SecureActionButtonTemplate")
    b:SetSize(30, 30)
    b:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    b:SetFrameLevel(r:GetFrameLevel() + 3)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "item")
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    local bhl = b:CreateTexture(nil, "HIGHLIGHT"); bhl:SetAllPoints(); bhl:SetColorTexture(1, 1, 1, 0.25)
    b:SetScript("OnEnter", function(self)
        if self.link then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    r.item = b
    r:Hide()
    rows[i] = r
    return r
end

local function Build()
    if built then return end
    local f = CreateFrame("Frame", "ForeverLazy_Tracker", UIParent)
    local size = DB() and DB().pos and DB().pos.trackerSize
    f:SetSize(size and size.w or 280, size and size.h or 240)
    local saved = DB() and DB().pos and DB().pos.tracker
    if saved then f:SetPoint(saved.point or "TOPRIGHT", UIParent, saved.rel or "TOPRIGHT", saved.x or 0, saved.y or 0)
    else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -220) end
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetResizable(true)
    pcall(f.SetResizeBounds, f, 180, 70, 800, 1200)
    pcall(f.SetMinResize, f, 180, 70)
    f:SetScript("OnDragStart", function(self) if not DB().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        local db = DB()
        if db then db.pos = db.pos or {}; db.pos.tracker = { point = point, rel = rel, x = x, y = y } end
    end)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(); f.bg:SetColorTexture(0.04, 0.04, 0.07, 0.8)
    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetPoint("TOPLEFT", 0, 0); f.border:SetPoint("TOPRIGHT", 0, 0); f.border:SetHeight(24)
    f.border:SetColorTexture(1, 1, 1, 0.06)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 8, -5)
    -- the title strip: click to fold the list away, right-click for the options; drag to move
    local strip = CreateFrame("Button", nil, f)
    strip:SetPoint("TOPLEFT", 0, 0); strip:SetPoint("TOPRIGHT", -52, 0); strip:SetHeight(24)
    strip:SetFrameLevel(f:GetFrameLevel() + 5)
    strip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", function() if not DB().locked then f:StartMoving() end end)
    strip:SetScript("OnDragStop", function() local h = f:GetScript("OnDragStop"); if h then h(f) end end)
    strip:SetScript("OnClick", function(_, button)
        local db = DB()
        if button == "RightButton" then
            if IsShiftKeyDown() then
                if db.pos then db.pos.trackerSize = nil end
                f:SetSize(280, 240)
                dirty = true
            elseif addon.ShowMenu then
                addon.ShowMenu({
                    { text = (db.trackerCollapsed and "Restore the tracker" or "Minimize the tracker"), fn = function() db.trackerCollapsed = not db.trackerCollapsed; dirty = true; if addon.RefreshOptions then addon.RefreshOptions() end end },
                    { text = (db.trackerNoBg and "Show the background" or "No background"), fn = function() db.trackerNoBg = not db.trackerNoBg; ApplyLook(); if addon.RefreshOptions then addon.RefreshOptions() end end },
                    { text = (db.trackerCompact and "Show every quest's objectives" or "Compact: objectives only for the quest I am on"), fn = function() db.trackerCompact = not db.trackerCompact; dirty = true; if addon.RefreshOptions then addon.RefreshOptions() end end },
                    { text = "Hide WoW's own tracker: " .. ((db.trackerHideBlizzard ~= false) and "on" or "off"), fn = function() addon.TrackerSet(true, db.trackerHideBlizzard == false) end },
                    { text = "Size and place back to the default", fn = function() addon:HandleExtraCommand("tracker", "reset") end },
                    { text = "Switch this tracker off", fn = function() addon.TrackerSet(false) end },
                }, "Quest tracker")
            end
        else
            db.trackerCollapsed = not db.trackerCollapsed
            dirty = true
        end
    end)
    local function SizeButton(text, anchor, delta)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(24, 18); b:SetText(text); b:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
        b:SetFrameLevel(f:GetFrameLevel() + 6)
        b:SetScript("OnClick", function()
            DB().trackerScale = math.min(2.6, math.max(0.7, Scale() + delta))
            dirty = true
        end)
        return b
    end
    local anchor = CreateFrame("Frame", nil, f)
    anchor:SetSize(1, 1); anchor:SetPoint("TOPRIGHT", -4, -6)
    local bigger = SizeButton("A+", anchor, 0.15)
    local smaller = SizeButton("A-", bigger, -0.15)

    -- the list scrolls (mouse wheel) when it is taller than the window
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 8, -28); scroll:SetPoint("BOTTOMRIGHT", -8, 20)       -- the width is set to fit the text
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 40)))
    end)
    f.scroll = scroll
    f.bar = f:CreateTexture(nil, "OVERLAY")
    f.bar:SetColorTexture(1, 1, 1, 0.35)
    f.bar:Hide()
    scroll:SetScript("OnVerticalScroll", function() UpdateBar() end)
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(260, 10)
    scroll:SetScrollChild(f.content)
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.empty:SetPoint("TOPLEFT", 8, -32); f.empty:SetJustifyH("LEFT")
    f.empty:SetText("No quests in your log.")

    -- resize from the corner, the right edge or the bottom edge
    local function Sizer(point, w, h, ...)
        local g = CreateFrame("Button", nil, f)
        g:SetSize(w, h)
        g:SetPoint(...)
        g:SetFrameLevel(f:GetFrameLevel() + 20)
        g:SetScript("OnMouseDown", function() f.sizing = true; f:StartSizing(point) end)
        g:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); f.sizing = false; SaveSize(f); dirty = true end)
        return g
    end
    local grip = Sizer("BOTTOMRIGHT", 22, 22, "BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    -- the text size buttons and the corner grip only show while the mouse is over the window
    local mini = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    mini:SetSize(22, 18); mini:SetText("_"); mini:SetPoint("RIGHT", smaller, "LEFT", -2, 0)
    mini:SetFrameLevel(f:GetFrameLevel() + 6)
    mini:SetScript("OnClick", function()
        DB().trackerCollapsed = not DB().trackerCollapsed
        dirty = true
        if addon.RefreshOptions then addon.RefreshOptions() end
    end)
    local hoverItems = { bigger, smaller, mini, grip }
    local overAcc = 0
    local function ShowTools(on)
        for _, b in ipairs(hoverItems) do if b:IsShown() ~= on then b:SetShown(on) end end
    end
    ShowTools(false)
    f:SetScript("OnUpdate", function(self, dt)
        overAcc = overAcc + dt
        if overAcc < 0.1 then return end
        overAcc = 0
        ShowTools(self:IsMouseOver() or self.sizing == true)
    end)
    local right = Sizer("RIGHT", 6, 10, "TOPRIGHT", 0, -26)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 24)
    local bottom = Sizer("BOTTOM", 10, 6, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 0)
    f:SetScript("OnSizeChanged", function(self) if self.sizing then dirty = true end end)
    win = f
    built = true
    for i = 1, MAXROWS do BuildRow(i) end
    ApplyLook()
    f:Hide()
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
-- a zone heading: click to fold the zone's quests away (or open them again)
local headers = {}
local function Header(i)
    local h = headers[i]
    if h then return h end
    h = CreateFrame("Button", nil, win.content)
    h:RegisterForClicks("LeftButtonUp")
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function() if not DB().locked then win:StartMoving() end end)
    h:SetScript("OnDragStop", function() local f = win:GetScript("OnDragStop"); if f then f(win) end end)
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.text:SetPoint("LEFT", 0, 0); h.text:SetJustifyH("LEFT")
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    h:SetScript("OnClick", function(self)
        local db = DB()
        db.trackerZoneOff = db.trackerZoneOff or {}
        db.trackerZoneOff[self.zone] = (not db.trackerZoneOff[self.zone]) or nil
        dirty = true
    end)
    h:Hide()
    headers[i] = h
    return h
end

local function Layout()
    local db = DB()
    if not (db and win) then return end
    win:SetScale(Scale())
    local width = math.max(140, win:GetWidth() - 16)
    local fixedHeight = db.pos and db.pos.trackerSize and db.pos.trackerSize.h
    local inCombat = InCombatLockdown and InCombatLockdown()
    local list = QuestList()
    local byId = {}
    for _, e in ipairs(list) do byId[e.q.id] = e end

    local maxQuests = 40        -- the quest log holds 40 (the game's own limit call says 145 here, which is wrong for this client)
    win.title:SetText(string.format("Quests |cffaaaaaa(%d/%d)|r", #list, maxQuests))
    win.empty:SetWidth(width)
    win.empty:SetShown(#list == 0 and not db.trackerCollapsed)

    -- by zone: the zone I am in first, then the others in the order their quests come
    local here = GetRealZoneText and GetRealZoneText() or ""
    local groups, byZone = {}, {}
    local curId
    for _, e in ipairs(list) do
        if e.inPlan and not curId then curId = e.q.id end
        local z = e.q.zone or "Other"
        local g = byZone[z]
        if not g then g = { zone = z, quests = {} }; byZone[z] = g; groups[#groups + 1] = g end
        g.quests[#g.quests + 1] = e
    end
    for i, g in ipairs(groups) do
        if g.zone == here and i > 1 then table.remove(groups, i); table.insert(groups, 1, g); break end
    end

    -- who sits in which row, in the order they are shown: only reassigned out of combat (the item buttons are secure)
    if not inCombat then
        local n = 0
        for i = 1, MAXROWS do rowQuest[i] = nil end
        for _, g in ipairs(groups) do
            for _, e in ipairs(g.quests) do
                n = n + 1
                if n <= MAXROWS then rowQuest[n] = e.q.id end
            end
        end
    else
        dirtyAfterCombat = true
    end
    local rowOf = {}
    for i = 1, MAXROWS do if rowQuest[i] then rowOf[rowQuest[i]] = i end end
    local off = db.trackerZoneOff or {}

    -- what each row says (worked out first, so the window can be as wide as the text needs and no wider)
    local desc = {}
    for _, g in ipairs(groups) do
        if not off[g.zone] then
            for _, e in ipairs(g.quests) do
                local i = rowOf[e.q.id]
                if i then
                    local cur = (e.q.id == curId)
                    local head, body = Describe(e, cur)
                    -- compact: only the quest I am on shows its objectives; the others are one line (finished ones keep their line)
                    if db.trackerCompact and not cur and not e.q.complete then body = "" end
                    desc[i] = { e = e, head = head, body = body, cur = cur }
                end
            end
        end
    end
    local fixedWidth = db.pos and db.pos.trackerSize and db.pos.trackerSize.w
    if not fixedWidth and not win.sizing then
        if not win.mT then
            win.mT = win:CreateFontString(nil, "OVERLAY", "GameFontNormal"); win.mT:SetAlpha(0); win.mT:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
            win.mB = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); win.mB:SetAlpha(0); win.mB:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
        end
        local need = 0
        for i, d in pairs(desc) do
            local hasItem = rows[i].item.link and true or false
            win.mT:SetText(d.head)
            local w1 = win.mT:GetStringWidth() + 8 + (hasItem and 34 or 0)
            local w2 = 0
            if d.body ~= "" then win.mB:SetText(d.body); w2 = win.mB:GetStringWidth() + 18 + (hasItem and 34 or 0) end
            need = math.max(need, w1, w2)
        end
        for _, g in ipairs(groups) do
            win.mT:SetText("[-] " .. g.zone .. " (" .. #g.quests .. ")")
            need = math.max(need, win.mT:GetStringWidth())
        end
        win.mT:SetText(win.title:GetText() or "")
        local maxW = math.min(460, UIParent:GetWidth() * 0.4 / math.max(0.5, win:GetScale()))
        win:SetWidth(math.max(170, math.min(maxW, need + 24)))
    end
    width = math.max(140, win:GetWidth() - 16)
    win.empty:SetWidth(width)

    -- every row starts hidden; the ones shown are laid out in order
    for i = 1, MAXROWS do
        if not (desc[i]) then
            rows[i]:Hide(); rows[i].quest = nil
            if not inCombat then rows[i].item:Hide(); rows[i].item.link = nil end
        end
    end
    for _, h in pairs(headers) do h:Hide() end

    local y, hdrIndex = 0, 0
    if not db.trackerCollapsed then
        for _, g in ipairs(groups) do
            hdrIndex = hdrIndex + 1
            local h = Header(hdrIndex)
            h.zone = g.zone
            h:ClearAllPoints(); h:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -y); h:SetSize(width, 18)
            h.text:SetText(string.format("%s %s |cffaaaaaa(%d)|r", off[g.zone] and "|cffffd100[+]|r" or "|cffffd100[-]|r",
                (g.zone == here and "|cffffffff" or "|cffffd100") .. g.zone .. "|r", #g.quests))
            h:Show()
            y = y + 20
            if not off[g.zone] then
                for _, e in ipairs(g.quests) do
                    local i = rowOf[e.q.id]
                    local d = i and desc[i]
                    if d then
                        local r = rows[i]
                        local head, body = d.head, d.body
                        r.quest = e.q
                        local link, itemStr, icon
                        if not inCombat then link, itemStr, icon = SpecialItem(e.q.id) end
                        local hasItem = (not inCombat and link) or (inCombat and r.item.link)
                        r.title:SetWidth(width - 8 - (hasItem and 34 or 0))
                        r.title:SetText(head)
                        r.body:ClearAllPoints()
                        r.body:SetPoint("TOPLEFT", r, "TOPLEFT", 18, -(r.title:GetStringHeight() + 2))
                        r.body:SetWidth(width - 18 - (hasItem and 34 or 0))
                        r.body:SetText(body)
                        local rh = r.title:GetStringHeight() + (body == "" and 6 or (2 + r.body:GetStringHeight() + 8))
                        r:ClearAllPoints()
                        r:SetPoint("TOPLEFT", win.content, "TOPLEFT", 8, -y)
                        r:SetSize(width - 8, rh)
                        r:Show()
                        if not inCombat then
                            if link then
                                r.item.link = link
                                r.item:SetAttribute("item", itemStr)
                                r.item.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                                r.item:Show()
                            else
                                r.item.link = nil; r.item:Hide()
                            end
                        end
                        y = y + rh
                    end
                end
            end
        end
    end
    win.content:SetSize(width, math.max(y, 10))
    -- no size of my own yet: fit the list, but never more than 40% of the screen's height; the rest scrolls
    if win.sizing then
        -- being resized by hand: leave the height alone
    elseif db.trackerCollapsed then
        win:SetHeight(26)                                           -- minimized: just the title
    elseif fixedHeight then
        win:SetHeight(fixedHeight)
    else
        local maxH = UIParent:GetHeight() * 0.4 / (win:GetScale() > 0 and win:GetScale() or 1)
        local want = 28 + 20 + y + (#list == 0 and 20 or 0)
        win:SetHeight(math.max(70, math.min(maxH, want)))
    end
    -- keep the scroll position inside the list when the list got shorter
    local range = win.scroll:GetVerticalScrollRange() or 0
    if (win.scroll:GetVerticalScroll() or 0) > range then win.scroll:SetVerticalScroll(range) end
    win.collapsedNow = db.trackerCollapsed
    UpdateBar()
    ApplyLook()
end
--------------------------------------------------------------------------------
-- WoW's own tracker
--------------------------------------------------------------------------------
local BLIZZ = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local hid, hooked = {}, {}

local function ApplyBlizzard(hide)
    for _, name in ipairs(BLIZZ) do
        local f = _G[name]
        if f and f.Hide then
            if hide then
                if f:IsShown() then hid[name] = true end
                pcall(f.Hide, f)
                if not hooked[name] and f.HookScript then
                    hooked[name] = true
                    pcall(f.HookScript, f, "OnShow", function(self)
                        local db = DB()
                        if db and db.trackerOn and db.trackerHideBlizzard ~= false then self:Hide() end
                    end)
                end
            elseif hid[name] then
                hid[name] = nil
                pcall(f.Show, f)
            end
        end
    end
end

function addon.TrackerSet(on, hideBlizzard)
    local db = DB()
    if not db then return end
    if on ~= nil then db.trackerOn = on and true or false end
    if hideBlizzard ~= nil then db.trackerHideBlizzard = hideBlizzard and true or false end
    if db.trackerOn then
        Build()
        win:Show()
        dirty = true
        ApplyBlizzard(db.trackerHideBlizzard ~= false)
    else
        if win then win:Hide() end
        ApplyBlizzard(false)
    end
    if addon.RefreshOptions then addon.RefreshOptions() end
    Print("Forever Lazy's quest tracker is " .. (db.trackerOn and "on" or "off") ..
        ((db.trackerOn and db.trackerHideBlizzard ~= false) and " (WoW's tracker is hidden)" or ""))
end

--------------------------------------------------------------------------------
-- Keeping it up to date
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
                     "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    local db = DB()
    if not db then return end
    if event == "PLAYER_REGEN_DISABLED" then
        -- out of the way in a fight (the window is a plain frame, so hiding it is allowed in combat)
        if db.trackerOn and db.trackerHideCombat ~= false and win and win:IsShown() then win:Hide(); win.hiddenByCombat = true end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if win and win.hiddenByCombat then
            win.hiddenByCombat = nil
            if db.trackerOn then win:Show() end
        end
        dirty = true
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if db.trackerOn and C_Timer then
            C_Timer.After(2, function()
                if DB().trackerOn then Build(); win:Show(); ApplyBlizzard(DB().trackerHideBlizzard ~= false); dirty = true end
            end)
        end
        return
    end
    dirty = true
end)

local acc = 0
local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    local db = DB()
    if not (db and db.trackerOn and win and win:IsShown()) then return end
    -- changes show within a third of a second; the plan changes quietly, so look every couple of seconds too
    if (dirty and acc > 0.3) or acc > 2 then
        acc = 0
        dirty = false
        if dirtyAfterCombat and not (InCombatLockdown and InCombatLockdown()) then dirtyAfterCombat = false end
        pcall(Layout)
    end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "tracker" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if a == "on" then addon.TrackerSet(true)
        elseif a == "off" then addon.TrackerSet(false)
        elseif a == "min" or a == "minimize" or a == "mini" then
            DB().trackerCollapsed = not DB().trackerCollapsed
            dirty = true
            Print("tracker " .. (DB().trackerCollapsed and "minimized" or "restored"))
        elseif a == "debug" then
            local name, itype, diff, _, _, _, _, instId = GetInstanceInfo()
            local L = { "instance: " .. tostring(name) .. "  type: " .. tostring(itype) .. "  id: " .. tostring(instId) }
            L[#L + 1] = "questie ready: " .. tostring(api.QuestieReady and api.QuestieReady())
            L[#L + 1] = "DungeonQuestsHere exists: " .. tostring(addon.DungeonQuestsHere ~= nil)
            local ids = DungeonIds()
            local n = 0
            if ids then for id in pairs(ids) do n = n + 1; L[#L + 1] = "  here: " .. id end end
            L[#L + 1] = "DungeonIds: " .. (ids and (n .. " quests") or "nil (not seen as a dungeon)")
            for _, q in ipairs(api.ReadQuestLog and api.ReadQuestLog() or {}) do
                L[#L + 1] = string.format("log: %s [%s] complete=%s dungeonQuest=%s here=%s", tostring(q.title), tostring(q.id), tostring(q.complete),
                    tostring(api.IsDungeonQuest and api.IsDungeonQuest(q.id, q.complete)), tostring(ids and ids[q.id]))
            end
            dcache = { name = nil, t = 0, ids = {} }
            if addon.ShowTextPopup then addon.ShowTextPopup("Tracker debug", table.concat(L, "\n")) else Print(table.concat(L, "\n")) end
        elseif a == "refresh" then
            ApplyLook(); dirty = true
        elseif a == "bg" or a == "background" then
            DB().trackerNoBg = not DB().trackerNoBg
            ApplyLook()
            Print("tracker background " .. (DB().trackerNoBg and "off" or "on"))
        elseif a == "reset" then
            local db = DB()
            if db.pos then db.pos.tracker = nil; db.pos.trackerSize = nil end
            if win then win:ClearAllPoints(); win:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -220); win:SetSize(300, 300) end
            dirty = true
            Print("tracker put back at the top right")
        else
            addon.TrackerSet(not DB().trackerOn)
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Tracker.lua"] = true end end
