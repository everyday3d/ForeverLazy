-- Buttons and menus in the game's own windows, so most things are a click instead of a slash command.
--   minimap button: left-click = Lazy Mode, right-click = the menu, shift+left-click = options
--   world map: a search box ("go to ...") and a Lazy button
--   quest log: plan my route, do this quest next, skip it
--   profession window: a craft plan panel with the materials (bags and bank)
--   bank: the materials your craft plan needs are lit up
--   flight map: nearest new flight point, take me there
--   boat NPC chat: mark this dock
--   /lazy windows: which windows were found and what failed (for bug reports)
-- Everything sits beside or below the game's windows, never on top of their own buttons.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On() local d = DB(); return d and d.uiButtons ~= false end

-- errors are kept so /lazy windows can show them
local problems = {}
local built = {}
local function Try(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then problems[name] = nil else problems[name] = tostring(err) end
    return ok
end

local function Cmd(cmd, rest)
    if addon.HandleExtraCommand then addon:HandleExtraCommand(cmd, rest) end
end

-- the first window that exists, from a list of names this client might use
local function FirstFrame(names)
    for _, n in ipairs(names) do
        if _G[n] then return _G[n], n end
    end
end

--------------------------------------------------------------------------------
-- A text box to ask for a name
--------------------------------------------------------------------------------
StaticPopupDialogs["FOREVERLAZY_ASK"] = {
    text = "%s",
    button1 = ACCEPT or "OK",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 60,
    OnAccept = function(self, data)
        local eb = self.editBox or self.EditBox
        local text = eb and eb:GetText() or ""
        if data and text ~= "" then data(text) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local text = self:GetText()
        if p.data and text ~= "" then p.data(text) end
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function Ask(prompt, fn) StaticPopup_Show("FOREVERLAZY_ASK", prompt, nil, fn) end

--------------------------------------------------------------------------------
-- The menu
--------------------------------------------------------------------------------
local menu, catcher
local function BuildMenu()
    local f = CreateFrame("Frame", "ForeverLazy_Menu", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.rows = {}
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:Hide()
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnShow", function() catcher:Show() end)
    f:SetScript("OnHide", function() catcher:Hide() end)
    table.insert(UISpecialFrames, "ForeverLazy_Menu")
    f:Hide()
    return f
end

local function Row(f, i)
    local b = f.rows[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetSize(250, 20)
    b:SetPoint("TOPLEFT", 8, -26 - (i - 1) * 20)
    b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.fs:SetPoint("LEFT", 4, 0)
    b.fs:SetWidth(240); b.fs:SetJustifyH("LEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnClick", function(self)
        if self.sub then
            local items = self.sub()
            menu:Hide()
            addon.ShowMenu(items, self.subTitle)
        elseif self.fn then
            menu:Hide()
            pcall(self.fn)
        end
    end)
    f.rows[i] = b
    return b
end

-- items: { text, fn } or { text, sub = function() return items end } or { text, header = true }
function addon.ShowMenu(items, title)
    menu = menu or BuildMenu()
    local shown = {}
    for _, it in ipairs(items) do
        if not it.module or addon.ModuleOn(it.module) then shown[#shown + 1] = it end
    end
    menu.title:SetText(title or "Forever Lazy")
    for i, it in ipairs(shown) do
        local row = Row(menu, i)
        row.fn, row.sub, row.subTitle = it.fn, it.sub, it.text
        if it.header then
            row.fs:SetText("|cffffd100" .. it.text .. "|r")
        else
            row.fs:SetText(it.text .. (it.sub and "  |cff888888>|r" or ""))
        end
        row:Show()
    end
    for i = #shown + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetSize(266, 34 + #shown * 20)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 10, y / s + 10)
    menu:SetClampedToScreen(true)
    menu:Show()
end

local function Back() return { text = "< Back", fn = function() addon:OpenMenu() end } end

local function GoMenu()
    return {
        Back(),
        { text = "Search for a place...", fn = function() Ask("Where to? A zone, a city, a dungeon, a flight point, hearth or inn", function(t) Cmd("go", t) end) end, module = "go" },
        { text = "My hearthstone inn", fn = function() Cmd("go", "hearth") end, module = "go" },
        { text = "The next stop of my journey", fn = function() Cmd("journey", "go 1") end, module = "zones" },
        { text = "Nearest inn", fn = function() Cmd("inn") end, module = "services" },
        { text = "Nearest repair vendor", fn = function() Cmd("repair") end, module = "services" },
        { text = "Nearest flight master", fn = function() Cmd("flight") end, module = "services" },
        { text = "Nearest bank", fn = function() Cmd("bank") end, module = "services" },
        { text = "My class trainer", fn = function() Cmd("trainer") end, module = "services" },
        { text = "A profession trainer...", fn = function() Ask("Which profession? (cooking, mining, ...)", function(t) Cmd(t) end) end, module = "services" },
        { text = "A flight point I have not found", fn = function() Cmd("fp") end, module = "travel" },
        { text = "Stop the trip", fn = function() Cmd("go", "stop") end, module = "go" },
    }
end

local function JourneyMenu()
    return {
        Back(),
        { text = "Open the levelling guide", fn = function() Cmd("guide") end },
        { text = "Show my journey", fn = function() Cmd("journey") end },
        { text = "Generate it", fn = function() Cmd("journey", "generate") end },
        { text = "Regenerate from my level", fn = function() Cmd("journey", "regenerate") end },
    }
end

local function CraftMenu()
    return {
        Back(),
        { text = "Craft plan (open a profession window first)", fn = function() Cmd("craft") end },
        { text = "Go to where I can get the next material", fn = function() Cmd("craft", "go") end },
        { text = "Go to the bank", fn = function() Cmd("craft", "bank") end },
        { text = "Herb or ore route...", fn = function() Ask("Which node? (peacebloom, tin, ...)", function(t) Cmd("gather", t) end) end, module = "gather" },
        { text = "Nearest fishing spot", fn = function() Cmd("fish") end, module = "gather" },
        { text = "Fishing route", fn = function() Cmd("fish", "route") end, module = "gather" },
    }
end

local function GroupMenu()
    return {
        Back(),
        { text = "Follow someone in my group...", fn = function() addon:OpenFollowMenu() end, module = "follow" },
        { text = "Quests I share with my group", fn = function() Cmd("party") end, module = "party" },
        { text = "Share my plan with my group", fn = function() Cmd("shareplan") end, module = "party" },
        { text = "Duo mode status", fn = function() Cmd("duo") end, module = "party" },
    }
end

local function SettingsMenu()
    return {
        Back(),
        { text = "Open the options", fn = function() addon:OpenOptions() end },
        { text = "Preset: Minimal", fn = function() addon.ApplyPreset("minimal") end },
        { text = "Preset: Leveler", fn = function() addon.ApplyPreset("leveler") end },
        { text = "Preset: Duo", fn = function() addon.ApplyPreset("duo") end },
        { text = "Preset: Everything", fn = function() addon.ApplyPreset("full") end },
        { text = "Is everything working? (check)", fn = function() Cmd("check") end },
        { text = "Which windows did you find?", fn = function() Cmd("windows") end },
    }
end

-- Which target the one main arrow follows. The pick is kept, and the arrow switches at once.
local ARROW_SOURCES = {
    { "auto",    "What is next (automatic)" },
    { "plan",    "My plan or trip stop" },
    { "mine",    "My nearest quest objective" },
    { "partner", "My partner or friend" },
    { "books",   "The nearest library book" },
    { "nodes",   "The nearest ore or herb node I found" },
    { "rxp",     "My friend's quest target" },
}
local function ArrowLabel(key)
    for _, s in ipairs(ARROW_SOURCES) do if s[1] == key then return s[2] end end
    return ARROW_SOURCES[1][2]
end
local function SetArrowSource(key)
    local db = DB()
    db.arrowSource = key
    if key == "mine" then db.ownQuests = true end          -- needed to work out my nearest objective
    if key == "rxp" then db.rxpListen = true end           -- needed to hear my friend's target
    Print(L("the arrow now points at: ") .. ArrowLabel(key))
    if addon.RefreshOptions then addon.RefreshOptions() end
end
local function ArrowChoices(withBack)
    local cur = DB().arrowSource or "auto"
    local list = {}
    if withBack then list[#list + 1] = { text = "< Back", fn = function() addon:OpenMenu() end } end
    for _, s in ipairs(ARROW_SOURCES) do
        local key = s[1]
        list[#list + 1] = { text = (key == cur and "|cff55ff55> |r" or "   ") .. s[2], fn = function() SetArrowSource(key) end }
    end
    return list
end
-- right-click on the arrow: the services you are most likely to want, one click each.
-- Only the ones that exist on this continent and are within walking distance are listed.
-- out in the open world only services within a walk count; in a city every service in the city is offered
local OPEN_YARDS, CITY_MAX_YARDS = 900, 2500
local function WhereAmI()
    local mapId
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then mapId = id end
    end
    local inCity = IsResting and IsResting() or false
    if not inCity and mapId and C_Map.GetMapInfo and Enum and Enum.UIMapType and Enum.UIMapType.City then
        local info = C_Map.GetMapInfo(mapId)
        if info and info.mapType == Enum.UIMapType.City then inCity = true end
    end
    return inCity, mapId
end

-- is this result worth listing from where I stand?
local function IsClose(r, inCity, mapId)
    if not (r and r.d) then return false end
    if inCity then
        return (mapId and r.spawn and r.spawn.uiMapId == mapId) or r.d <= CITY_MAX_YARDS
    end
    return r.d <= OPEN_YARDS
end
function addon:OpenServicesMenu()
    local db = addon.GetDB and addon.GetDB()
    local wp = db and db.waypoints and db.waypoints[1]
    local wanted = {
        { "Repair vendor", "repair" }, { "Inn", "inn" }, { "Bank", "bank" }, { "Auction house", "ah" },
        { "Mailbox", "mailbox" }, { "Flight master", "flight" }, { "Class trainer", "classtrainer", "trainer" },
        { "Stable master", "stable" }, { "Battlemaster", "battlemaster" }, { "Spirit healer", "spirit" },
    }
    -- the services list only opens when you click "Services", and only holds what is close by
    local function ServicesList()
        local list = { { text = "< Back", fn = function() addon:OpenServicesMenu() end } }
        local find = api and api.FindService
        local inCity, mapId = WhereAmI()
        if find then
            for _, w in ipairs(wanted) do
                local ok, r = pcall(find, w[2])
                if ok and r and IsClose(r, inCity, mapId) then
                    local cmd = w[3] or w[2]
                    list[#list + 1] = { text = string.format("%s  |cff888888%d yd|r", w[1], r.d), fn = function() Cmd(cmd) end }
                end
            end
        end
        if #list == 1 then list[#list + 1] = { text = "Nothing close by (needs Questie loaded)", header = true } end
        list[#list + 1] = { text = "A profession trainer...", fn = function() Ask("Which profession? (cooking, mining, ...)", function(x) Cmd(x) end) end }
        return list
    end
    local items = { { text = "Point this arrow at:", header = true } }
    for _, it in ipairs(ArrowChoices(false)) do items[#items + 1] = it end
    items[#items + 1] = { text = " ", header = true }
    if addon.ModuleOn("services") then items[#items + 1] = { text = "Services near me", sub = ServicesList } end
    -- the plan's next quest stop may sit behind another stop (a guard's directions, a trip, a node): still offer to skip it
    local hasPlanStop = false
    for _, w in ipairs((db and db.waypoints) or {}) do if w.label then hasPlanStop = true; break end end
    if hasPlanStop and addon.OpenSkipMenu then
        items[#items + 1] = { text = "Skip this quest stop, or do it next...", fn = function() addon:OpenSkipMenu() end }
    end
    if wp and not wp.label then
        items[#items + 1] = { text = "Clear this stop: " .. tostring(wp.name or "arrow"), fn = function() addon:RemoveWaypoint(1) end }
    end
    items[#items + 1] = { text = "Ask the Coach: what should I do?", fn = function() Cmd("coach") end }
    items[#items + 1] = { text = "Do the next thing (Lazy Mode)", fn = function() Cmd("now") end, module = "lazymode" }
    items[#items + 1] = { text = "More (full menu)", fn = function() addon:OpenMenu() end }
    addon.ShowMenu(items, "Forever Lazy")
end
-- the same menu on every arrow you can see (the plan arrow does it in Extras.lua)
local hookedArrows = {}
local function HookArrows()
    for _, name in ipairs({ "ForeverLazy_QuestArrow", "ForeverLazy_FriendArrow", "ForeverLazy_MineArrow" }) do          -- the compass has its own menu
        local f = _G[name]
        if f and not hookedArrows[name] and f.HookScript then
            f:EnableMouse(true)
            f:HookScript("OnMouseUp", function(_, button)
                if button == "RightButton" then addon:OpenServicesMenu() end
            end)
            hookedArrows[name] = true
        end
    end
end
local arrowWatcher = CreateFrame("Frame")
pcall(arrowWatcher.RegisterEvent, arrowWatcher, "PLAYER_ENTERING_WORLD")
arrowWatcher:SetScript("OnEvent", function()
    if not C_Timer or not C_Timer.After then return end
    for _, secs in ipairs({ 3, 8, 15 }) do C_Timer.After(secs, function() pcall(HookArrows) end) end
end)

function addon:OpenMenu()
    addon.ShowMenu({
        { text = "Do the next thing (Lazy Mode)", fn = function() Cmd("now") end, module = "lazymode" },
        { text = "Plan this zone for the fastest levelling", fn = function() addon.PlanZone() end, module = "plan" },
        { text = "Step window (what to do, step by step)", fn = function() addon.ToggleSteps() end, module = "plan" },
        { text = "Quest tracker (Forever Lazy's own)", fn = function() Cmd("tracker") end },
        { text = "Plan my route", fn = function() addon:PlanRoute() end, module = "plan" },
        { text = (DB().planPaused and "Turn the plan back on (where I left it)" or "Turn the plan off (keeps my place)"),
          fn = function() if DB().planPaused then addon.PlanResume() else addon.PlanPause() end end, module = "plan" },
        { text = "Plan window", fn = function() Cmd("window") end, module = "plan" },
        { text = "Ask the Coach: what should I do?", fn = function() Cmd("coach") end },
        { text = "Levelling guide", fn = function() Cmd("guide") end, module = "zones" },
        { text = "XP hot spots on the map", fn = function() Cmd("xpmap") end, module = "plan" },
        { text = "What the arrow points at", sub = function() return ArrowChoices(true) end },
        { text = "Go somewhere", sub = GoMenu },
        { text = "Boats and zeppelins...", fn = function() Ask("Where to by boat? (darnassus, ratchet, ...)", function(t) Cmd("boat", t) end) end, module = "boats" },
        { text = "Mark this dock (stand on it)", fn = function() Cmd("boat", "mark") end, module = "boats" },
        { text = "Journey", sub = JourneyMenu, module = "zones" },
        { text = "Crafting and gathering", sub = CraftMenu, module = "crafting" },
        { text = "Group", sub = GroupMenu },
        { text = "Settings and presets", sub = SettingsMenu },
    }, "Forever Lazy")
end

--------------------------------------------------------------------------------
-- The minimap button
--------------------------------------------------------------------------------
local function HookMinimap()
    local b = _G.ForeverLazy_MinimapButton
    if not b then return false end
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            addon:OpenMenu()
        elseif IsShiftKeyDown() or not addon.ModuleOn("lazymode") then
            addon:OpenOptions()
        else
            Cmd("now")
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L("Forever Lazy"))
        GameTooltip:AddLine(L("Left-click: do the next thing"), 1, 1, 1)
        GameTooltip:AddLine(L("Right-click: the menu"), 1, 1, 1)
        GameTooltip:AddLine(L("Shift-click: options"), 1, 1, 1)
        GameTooltip:Show()
    end)
    built.minimap = "ForeverLazy_MinimapButton"
    return true
end

--------------------------------------------------------------------------------
-- Small helpers for buttons beside the game's windows
--------------------------------------------------------------------------------
local function MakeButton(parent, text, w, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

-- a row of buttons just under a window
local function BarUnder(frame, defs)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetSize(10, 24)
    bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 6, 4)
    local x = 0
    for _, d in ipairs(defs) do
        local b = MakeButton(bar, d[1], d[2], d[3])
        b:SetPoint("LEFT", bar, "LEFT", x, 0)
        x = x + d[2] + 4
    end
    bar:SetFrameStrata(frame:GetFrameStrata())
    return bar
end

--------------------------------------------------------------------------------
-- World map: search box and a Lazy button
--------------------------------------------------------------------------------
local mapBuilt
local function BuildMap()
    if mapBuilt or not On() then return end
    local wm = _G.WorldMapFrame
    if not wm then problems.map = "no world map window"; return end
    mapBuilt = true
    built.map = "WorldMapFrame"
    local host = wm.ScrollContainer or wm
    local box = CreateFrame("EditBox", nil, wm, "InputBoxTemplate")
    box:SetSize(150, 20)
    box:SetPoint("TOPRIGHT", host, "TOPRIGHT", -90, -8)
    box:SetAutoFocus(false)
    box:SetFrameStrata("HIGH")
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetText("Go to...")
    box:SetScript("OnEditFocusGained", function() hint:Hide() end)
    box:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then hint:Show() end end)
    box:SetScript("OnEnterPressed", function(self)
        local t = self:GetText()
        self:SetText(""); self:ClearFocus()
        if t ~= "" then Cmd("go", t) end
    end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    local btn = MakeButton(wm, "Lazy", 60, function() addon:OpenMenu() end)
    btn:SetPoint("LEFT", box, "RIGHT", 6, 0)
    btn:SetFrameStrata("HIGH")
    local xpb = MakeButton(wm, "XP", 40, function() Cmd("xpmap") end)
    xpb:SetPoint("RIGHT", box, "LEFT", -6, 0)
    xpb:SetFrameStrata("HIGH")
end

--------------------------------------------------------------------------------
-- Quest log
--------------------------------------------------------------------------------
local function SelectedQuest()
    if GetQuestLogSelection and GetQuestLogTitle then
        local i = GetQuestLogSelection()
        if i and i > 0 then
            local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not isHeader and id and id ~= 0 then return id, title end
        end
    end
    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        local id = C_QuestLog.GetSelectedQuest()
        if id and id ~= 0 then return id, (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)) or "this quest" end
    end
end

local questBar
local function BuildQuestLog()
    if questBar or not On() or not addon.ModuleOn("plan") then return end
    local f, name = FirstFrame({ "QuestLogFrame", "QuestLogPopupDetailFrame", "QuestMapFrame" })
    if not f then problems.quest = "no quest log window found"; return end
    built.quest = name
    questBar = BarUnder(f, {
        { "Plan my route", 110, function() addon:PlanRoute() end },
        { "Do this next", 100, function()
            local id, title = SelectedQuest()
            if id then addon:FocusQuest(id, title) else Print(L("select a quest in the log first")) end
        end },
        { "Skip this", 80, function()
            local id, title = SelectedQuest()
            if id and addon.SkipQuest then addon.SkipQuest(id, title) else Print(L("select a quest in the log first")) end
        end },
    })
end

--------------------------------------------------------------------------------
-- Profession window: the craft plan panel
--------------------------------------------------------------------------------
local HighlightRecipes          -- defined further down, used by the panel above it
local craftPanel
local craftClosed                -- set when I close the panel: { sel = the recipe that was selected }; cleared when it should come back

-- the recipe selected in whichever profession window is open (nil when I cannot tell)
local function CraftSelection()
    local id
    local pf = _G.ProfessionsFrame
    if pf and pf.CraftingPage and pf.CraftingPage.SchematicForm then
        local s = pf.CraftingPage.SchematicForm
        local rs = s.recipeSchematic
        id = rs and (rs.recipeID or rs.recipeId)
    end
    if not id and GetTradeSkillSelectionIndex then
        local ok, v = pcall(GetTradeSkillSelectionIndex)
        if ok then id = v end
    end
    if not id and GetCraftSelectionIndex then
        local ok, v = pcall(GetCraftSelectionIndex)
        if ok then id = v end
    end
    return id
end
local function RefreshCraftPanel()
    if not craftPanel or not craftPanel:IsShown() then return end
    local lines = addon.CraftPlanText and addon.CraftPlanText() or { "crafting is switched off" }
    local h = addon.HighlightDiag
    if h then
        lines = { unpack(lines) }
        lines[#lines + 1] = string.format("|cff888888list: %s, rows %s, plan pick %s, matched %s%s|r", tostring(h.scrollbox == "yes" and "found" or "NOT found"),
            tostring(h.rows), tostring(h.best), tostring(h.matched), h.note and (" - " .. h.note) or "")
    end
    craftPanel.text:SetText(table.concat(lines, "\n"))
    craftPanel:SetHeight(math.max(96, 84 + craftPanel.text:GetStringHeight()))
end

-- put the panel just right of the window and anything stuck to its right edge (profession tabs), unless I moved it
local function PlaceCraftPanel(p, frame)
    p:ClearAllPoints()
    local saved = DB() and DB().pos and DB().pos.craftPanel
    if saved then
        p:SetPoint(saved.point or "TOPLEFT", UIParent, saved.rel or "BOTTOMLEFT", saved.x or 0, saved.y or 0)
        return
    end
    local extra = 0
    local fr = frame.GetRight and frame:GetRight()
    if fr then
        local function Scan(f)
            if not (f and f.GetLeft and f.GetRight and f:IsShown()) then return end
            local l, r = f:GetLeft(), f:GetRight()
            if l and r and l >= fr - 10 and r > fr + extra then extra = r - fr end
        end
        for _, ch in ipairs({ frame:GetChildren() }) do
            Scan(ch)
            -- tabs hang off the window but may be children of the tab bar or of a sub frame
            for _, ch2 in ipairs({ ch:GetChildren() }) do Scan(ch2) end
        end
    end
    p:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4 + extra, -40)
end

local function BuildCraftPanel(frame)
    if craftPanel then
        craftPanel:SetParent(frame)
        PlaceCraftPanel(craftPanel, frame)
        craftPanel:Show()
        return
    end
    local p = CreateFrame("Frame", "ForeverLazy_CraftPanel", frame)
    p:SetSize(330, 120)
    PlaceCraftPanel(p, frame)
    p:SetFrameStrata("HIGH")
    -- drag it where it suits me; Shift + right-click puts it back
    p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
    p:SetClampedToScreen(true)
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetTop()
        local db = DB()
        if db then db.pos = db.pos or {}; db.pos.craftPanel = { point = "TOPLEFT", rel = "BOTTOMLEFT", x = x, y = y } end
    end)
    p:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and IsShiftKeyDown() then
            local db = DB()
            if db and db.pos then db.pos.craftPanel = nil end
            PlaceCraftPanel(self, self:GetParent())
        end
    end)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
    local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 10, -8); t:SetText(L("Forever Lazy: craft plan"))
    -- close it; it comes back the next time the crafting window opens, or when a different recipe is selected
    local closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22); closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        craftClosed = { sel = CraftSelection() }
        p:Hide()
    end)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.text:SetPoint("TOPLEFT", 10, -28)
    p.text:SetWidth(310); p.text:SetJustifyH("LEFT"); p.text:SetJustifyV("TOP")
    p.diag = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.diag:SetPoint("BOTTOMLEFT", 10, 36)
    p.diag:SetWidth(310); p.diag:SetJustifyH("LEFT")
    local b0 = MakeButton(p, "Plan it", 58, function()
        if addon.ReadProfession then addon.ReadProfession() end
        if C_Timer then C_Timer.After(0.5, RefreshCraftPanel) else RefreshCraftPanel() end
    end)
    b0:SetPoint("BOTTOMLEFT", 8, 8)
    -- opens the recommended recipe in the window itself: the game scrolls the list to it and shows it on the right
    local bS = MakeButton(p, "Show it", 58, function()
        local best = addon.CraftHighlights and addon.CraftHighlights()
        if not best then Print(L("click Plan it first, so I know which recipe to show")); return end
        local shown
        if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then shown = pcall(C_TradeSkillUI.OpenRecipe, best) end
        if not shown and _G.TradeSkillFrame and TradeSkillFrame.SelectRecipe then shown = pcall(TradeSkillFrame.SelectRecipe, TradeSkillFrame, best) end
        if not shown and _G.ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SelectRecipe then
            shown = pcall(ProfessionsFrame.CraftingPage.SelectRecipe, ProfessionsFrame.CraftingPage, best)
        end
        if not shown then Print(L("this window would not open that recipe for me")); return end
        -- put the planned number in the window's own quantity box (it stops at what you can make)
        local _, crafts = addon.CraftHighlights()
        if crafts and C_Timer then
            C_Timer.After(0.4, function()
                local boxes = {
                    _G.TradeSkillFrame and TradeSkillFrame.DetailsFrame and TradeSkillFrame.DetailsFrame.CreateMultipleInputBox,
                    _G.ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.CreateMultipleInputBox,
                }
                for _, box in pairs(boxes) do
                    if box and box.SetValue then pcall(box.SetValue, box, crafts) end
                end
            end)
        end
    end)
    bS:SetPoint("LEFT", b0, "RIGHT", 4, 0)
    local b1 = MakeButton(p, "Where to get it", 100, function() Cmd("craft", "go") end)
    b1:SetPoint("LEFT", bS, "RIGHT", 4, 0)
    local b2 = MakeButton(p, "Bank", 46, function() Cmd("craft", "bank") end)
    b2:SetPoint("LEFT", b1, "RIGHT", 4, 0)
    local b3 = MakeButton(p, "Clear", 46, function()
        if addon.ClearWaypoints then pcall(addon.ClearWaypoints, addon) end
        Print(L("arrow cleared"))
    end)
    b3:SetPoint("LEFT", b2, "RIGHT", 4, 0)
    local acc = 0
    p:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc > 0.4 then
            acc = 0
            Try("highlight", HighlightRecipes)
            local h = addon.HighlightDiag
            local msg
            if problems.highlight then
                msg = "recipe list: error " .. tostring(problems.highlight)
            elseif h then
                msg = string.format("recipe list: %s rows (%s), plan pick %s, matched %s%s", tostring(h.rows), tostring(h.source or "none found"),
                    tostring(h.best), tostring(h.matched), h.note and (" - " .. h.note) or "")
            else
                msg = "recipe list: not scanned yet"
            end
            p.diag:SetText("|cff888888" .. msg .. "|r")
        end
    end)
    craftPanel = p
end

addon.CraftPanelRefresh = function() if not (DB() and DB().craftPanel == true) and craftPanel then craftPanel:Hide() end end

local craftWarned = {}
local function CraftWarn(key, text)
    if craftWarned[key] then return end
    craftWarned[key] = true
    Print(L("craft panel: ") .. text)
end

local function ShowCraft(names)
    if not (DB() and DB().craftPanel == true) then return end          -- the craft planner is off unless I turn it on
    if not On() then CraftWarn("ui", "the buttons in the game windows are switched off (Options > Buttons in the game windows)"); return end
    if not addon.ModuleOn("crafting") then CraftWarn("module", "the Crafting module is switched off (Options > Modules)"); return end
    local f, name = FirstFrame(names)
    if not f then problems.craft = "no profession window found (tried " .. table.concat(names, ", ") .. ")"; return end
    built.craft = name
    BuildCraftPanel(f)
    if C_Timer then C_Timer.After(0.8, function() if addon.ReadProfession then addon.ReadProfession() end; RefreshCraftPanel() end) end
end

-- Do not depend on the window's events or on when it loads: while a profession window is open, make sure the panel is
-- there. (A different addon loading the professions window early made the one-time hook miss it.)
local craftWatch = CreateFrame("Frame")
local craftAcc = 0
craftWatch:SetScript("OnUpdate", function(_, dt)
    craftAcc = craftAcc + dt
    if craftAcc < 0.5 then return end
    craftAcc = 0
    if not (DB() and DB().craftPanel == true) then
        if craftPanel and craftPanel:IsShown() then craftPanel:Hide() end
        return
    end
    for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then
            -- I closed the panel: it stays closed for this recipe, and comes back when a different one is selected
            if craftClosed then
                local sel = CraftSelection()
                if sel == nil or sel == craftClosed.sel then return end
                craftClosed = nil
            end
            if not (craftPanel and craftPanel:IsShown() and craftPanel:GetParent() == f) then
                if not Try("craft", ShowCraft, { name }) then CraftWarn("error", "error building it: " .. tostring(problems.craft)) end
            end
            return
        end
    end
    craftClosed = nil           -- no profession window open: next time it opens the panel is back
end)

--------------------------------------------------------------------------------
-- Profession window: light up the recipes in its own list
--   gold row + "craft N" = the one to craft next, soft gold = other recipes that still give skill-ups
--------------------------------------------------------------------------------
local function Mark(frame, kind, text)
    if not frame.flMark then
        frame.flMark = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        frame.flMark:SetAllPoints()
        -- the count sits in its own small frame above the row's own parts, so nothing can cover it
        frame.flBadge = CreateFrame("Frame", nil, frame)
        frame.flBadge:SetFrameLevel(frame:GetFrameLevel() + 20)
        frame.flBadge:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        frame.flBadge.bg = frame.flBadge:CreateTexture(nil, "BACKGROUND")
        frame.flBadge.bg:SetAllPoints()
        frame.flBadge.bg:SetColorTexture(0, 0, 0, 0.75)
        frame.flBadge.text = frame.flBadge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.flBadge.text:SetPoint("CENTER")
    end
    if kind == "best" then
        frame.flMark:SetColorTexture(1, 0.82, 0, 0.35)
        frame.flBadge.text:SetText(text or "craft this")
        frame.flBadge.text:SetTextColor(1, 0.9, 0.3)
        frame.flBadge:SetSize(frame.flBadge.text:GetStringWidth() + 12, 18)
        frame.flBadge:Show()
    elseif kind == "useful" then
        frame.flMark:SetColorTexture(1, 0.82, 0, 0.10)
        frame.flBadge:Hide()
    else
        frame.flMark:SetColorTexture(0, 0, 0, 0)
        frame.flBadge:Hide()
    end
end
-- the recipe a list row stands for, from whichever way this client's rows keep it
local function RowRecipeId(frame, elementData)
    local d = frame.tradeSkillInfo or frame.recipeInfo
    if not d then
        local e = (frame.GetElementData and frame:GetElementData()) or elementData
        if type(e) == "table" and e.GetData then e = e:GetData() end
        if type(e) == "table" then
            d = e.recipeInfo or (type(e.data) == "table" and (e.data.recipeInfo or e.data)) or e
        end
    end
    if type(d) ~= "table" then return nil end
    local id = d.recipeID or d.recipeId
    if type(id) == "number" then return id end
    return nil
end

-- every row of the recipe list that is on screen: the newer scroll list, the older button list, or any row found by looking
local function Rows(diag)
    local out = {}
    local pf, tf = _G.ProfessionsFrame, _G.TradeSkillFrame
    -- 1. the newer window's scroll list
    local list = pf and pf.CraftingPage and pf.CraftingPage.RecipeList
    local sb = list and (list.ScrollBox or list.scrollBox)
    if sb and sb.ForEachFrame then
        sb:ForEachFrame(function(frame, ed) out[#out + 1] = { f = frame, id = RowRecipeId(frame, ed) } end)
        if #out > 0 then diag.source = "ProfessionsFrame scroll list" end
    end
    -- 2. the older window's buttons
    if #out == 0 and tf then
        local rl = tf.RecipeList
        local buttons = rl and rl.buttons
        if buttons then
            for _, b in ipairs(buttons) do
                if b:IsShown() then out[#out + 1] = { f = b, id = RowRecipeId(b) } end
            end
            if #out > 0 then diag.source = "TradeSkillFrame buttons" end
        end
    end
    -- 3. look through the window for anything that holds a recipe
    if #out == 0 then
        local root = pf or tf
        if root then
            local function walk(f, depth)
                if depth > 8 then return end
                for _, child in ipairs({ f:GetChildren() }) do
                    if child:IsShown() then
                        local id = RowRecipeId(child)
                        if id then out[#out + 1] = { f = child, id = id } end
                        walk(child, depth + 1)
                    end
                end
            end
            pcall(walk, root, 0)
            if #out > 0 then diag.source = "found by searching the window" end
        end
    end
    return out
end

function HighlightRecipes()
    local diag = {}
    addon.HighlightDiag = diag
    if not On() or not addon.ModuleOn("crafting") or not addon.CraftHighlights then diag.note = "off"; return end
    diag.window = (_G.ProfessionsFrame and "ProfessionsFrame") or (_G.TradeSkillFrame and "TradeSkillFrame") or "none"
    local rows = Rows(diag)
    local best, crafts, useful = addon.CraftHighlights()
    diag.best = best
    diag.rows = #rows
    local matched, ids = 0, {}
    for _, r in ipairs(rows) do
        if #ids < 3 then ids[#ids + 1] = tostring(r.id) end
        if r.id and r.id == best then
            matched = matched + 1
            Mark(r.f, "best", crafts and ("craft " .. crafts) or "craft this")
        elseif r.id and useful and useful[r.id] then
            Mark(r.f, "useful")
        else
            Mark(r.f, nil)
        end
    end
    diag.matched, diag.sampleIds = matched, table.concat(ids, ",")
    if #rows == 0 then diag.note = "no recipe rows found in this window"
    elseif not best then diag.note = "no recipe picked yet (click Plan it)" end
    built.highlight = diag.source or "recipe list"
end
--------------------------------------------------------------------------------
-- Bank: light up the materials my craft plan needs
--------------------------------------------------------------------------------
local function GlowBank()
    if not On() or not addon.ModuleOn("crafting") or not addon.CraftReagentIds then return end
    local ids = addon.CraftReagentIds()
    if not next(ids) then return end
    local first = _G.BANK_CONTAINER or -1
    for slot = 1, (_G.NUM_BANKGENERIC_SLOTS or 28) do
        local btn = _G["BankFrameItem" .. slot]
        if btn then
            local id
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(first, slot)
                id = info and info.itemID
            elseif GetContainerItemLink then
                local link = GetContainerItemLink(first, slot)
                id = link and tonumber(link:match("item:(%d+)"))
            end
            if not btn.flGlow then
                btn.flGlow = btn:CreateTexture(nil, "OVERLAY")
                btn.flGlow:SetPoint("TOPLEFT", -3, 3); btn.flGlow:SetPoint("BOTTOMRIGHT", 3, -3)
                btn.flGlow:SetColorTexture(1, 0.82, 0, 0.35)
            end
            btn.flGlow:SetShown(id and ids[id] and true or false)
        end
    end
end

--------------------------------------------------------------------------------
-- Flight map and boat chat
--------------------------------------------------------------------------------
local taxiBar
local function BuildTaxi()
    if taxiBar or not On() then return end
    local f, name = FirstFrame({ "TaxiFrame", "FlightMapFrame" })
    if not f then problems.taxi = "no flight map window found"; return end
    built.taxi = name
    taxiBar = BarUnder(f, {
        { "Nearest new flight point", 160, function() Cmd("fp") end },
        { "Take me to...", 100, function() Ask("Where to?", function(t) Cmd("go", t) end) end },
    })
end

-- The flight map: ring the flight point the trip wants me to fly to, and say it at the top of the map.
local function Norm(s) return (tostring(s or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")) end
local function SameFlightPoint(a, b)
    a, b = Norm(a), Norm(b)
    if a == "" or b == "" then return false end
    if a == b then return true end
    return a:match("^[^,]+") == b:match("^[^,]+")
end

-- every flight point button on the map, whichever kind of window this is: { frame, name }
local function TaxiPoints()
    local out = {}
    if _G.FlightMapFrame and FlightMapFrame.EnumerateAllPins then
        pcall(function()
            for pin in FlightMapFrame:EnumerateAllPins() do
                local d = pin.taxiNodeData
                local nm = (d and d.name) or pin.name
                if nm then out[#out + 1] = { pin, nm } end
            end
        end)
    end
    if #out == 0 and NumTaxiNodes and TaxiNodeName then
        for i = 1, (NumTaxiNodes() or 0) do
            local b = _G["TaxiButton" .. i]
            if b then out[#out + 1] = { b, TaxiNodeName(i) } end
        end
    end
    return out
end

local taxiHint
local function TaxiHighlight()
    local win = (_G.FlightMapFrame and FlightMapFrame:IsShown() and FlightMapFrame) or (_G.TaxiFrame and TaxiFrame:IsShown() and TaxiFrame)
    local target = addon.GoFlightTarget and addon.GoFlightTarget()
    if not win or not target then
        if taxiHint then taxiHint:Hide() end
        return
    end
    if not taxiHint then
        taxiHint = CreateFrame("Frame", nil, UIParent)
        taxiHint:SetSize(360, 26)
        taxiHint:SetFrameStrata("FULLSCREEN_DIALOG")
        local bg = taxiHint:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.8)
        taxiHint.text = taxiHint:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        taxiHint.text:SetPoint("CENTER")
    end
    taxiHint:ClearAllPoints()
    taxiHint:SetPoint("BOTTOM", win, "TOP", 0, 4)
    taxiHint.text:SetText("Forever Lazy: fly to " .. (target:match("^[^,]+") or target))
    taxiHint:SetWidth(math.max(260, taxiHint.text:GetStringWidth() + 30))
    taxiHint:Show()
    local pulse = 0.6 + 0.4 * math.sin(GetTime() * 6)
    for _, p in ipairs(TaxiPoints()) do
        local btn = p[1]
        if not btn.flRing then
            btn.flRing = btn:CreateTexture(nil, "OVERLAY")
            btn.flRing:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
            btn.flRing:SetBlendMode("ADD")
            btn.flRing:SetVertexColor(1, 0.85, 0.1)
            btn.flRing:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.flRing:SetSize(54, 54)
        end
        if SameFlightPoint(p[2], target) then
            btn.flRing:SetAlpha(pulse)
            btn.flRing:Show()
        else
            btn.flRing:Hide()
        end
    end
end

local taxiTick = CreateFrame("Frame")
local taxiAcc = 0
taxiTick:SetScript("OnUpdate", function(_, dt)
    taxiAcc = taxiAcc + dt
    if taxiAcc < 0.1 then return end
    taxiAcc = 0
    if On() then pcall(TaxiHighlight) end
end)

--------------------------------------------------------------------------------
-- Titan Panel / any LibDataBroker display bar: a "Forever Lazy" button with the next stop and its distance.
-- Left-click = Lazy Mode, right-click = the services menu, shift-click = options.
--------------------------------------------------------------------------------
local ldbMain
local hoverSrc
local function SetupMainLDB()
    if ldbMain then return true end
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB then return false end
    local function NextText()
        local trip, leg = nil, nil
        if addon.GoStatus then trip, leg = addon.GoStatus() end
        if trip then return "Trip: " .. tostring(leg):gsub("%s*%(about.-%)", "") end
        local db = DB()
        local wp = db and db.waypoints and db.waypoints[1]
        if not wp then return "Lazy: no stop" end
        local text = tostring(wp.name or wp.label or "stop"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local px, py, pinst = api.hbd:GetPlayerWorldPosition()
        if px and wp.x and wp.instance == pinst then
            text = string.format("%s (%d yd)", text, math.sqrt((wp.x - px) ^ 2 + (wp.y - py) ^ 2))
        end
        return text
    end
    -- one icon, a line of text, and the whole menu opens when the mouse is over it
    ldbMain = LDB:NewDataObject("Forever Lazy", {
        type = "data source",
        label = "Forever Lazy",
        text = "Lazy",
        icon = "Interface\\AddOns\\ForeverLazy\\media\\icon",
        OnClick = function(_, button)
            if IsShiftKeyDown() then addon:OpenOptions() else Cmd("now") end
        end,
        OnEnter = function(frame)
            hoverSrc = frame
            addon:OpenMenu()
        end,
        OnLeave = function() end,
    })
    local acc, outside = 0, 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(_, dt)
        -- close the hover menu once the mouse has left both the button and the menu
        if hoverSrc and menu and menu:IsShown() then
            local over = (hoverSrc.IsMouseOver and hoverSrc:IsMouseOver()) or menu:IsMouseOver()
            outside = over and 0 or (outside + dt)
            if outside > 0.6 then menu:Hide(); hoverSrc = nil; outside = 0 end
        else
            outside = 0
        end
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        pcall(function() ldbMain.text = NextText() end)
    end)
    return true
end
local ldbWatch = CreateFrame("Frame")
pcall(ldbWatch.RegisterEvent, ldbWatch, "PLAYER_LOGIN")
ldbWatch:SetScript("OnEvent", function()
    if not C_Timer or not C_Timer.After then return end
    -- the bar addon may load after this one, so try again a few times
    for _, secs in ipairs({ 2, 6, 15 }) do C_Timer.After(secs, function() pcall(SetupMainLDB) end) end
end)

--------------------------------------------------------------------------------
-- A new zone: offer to plan it, but only once I have stayed a while (not while just passing through)
--------------------------------------------------------------------------------
local STAY_SECONDS = 25
local lastZone, zoneToast, zoneToken = nil, nil, 0

local function ZoneName(id)
    local info = C_Map and C_Map.GetMapInfo and id and C_Map.GetMapInfo(id)
    return info and info.name or "this zone"
end

local function ShowZoneToast(zoneId)
    if not zoneToast then
        local f = CreateFrame("Frame", "ForeverLazy_ZoneToast", UIParent)
        f:SetSize(400, 92)
        f:SetPoint("TOP", 0, -150)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.text:SetPoint("TOP", 0, -12); f.text:SetWidth(380)
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -4); f.sub:SetWidth(380)
        f.sub:SetText(L("Plan the quests you can do here, or leave it if you are just passing through?"))
        local plan = MakeButton(f, "Plan it", 90, function()
            f:Hide()
            if addon.PlanRoute then addon:PlanRoute() end
        end)
        plan:SetPoint("BOTTOMLEFT", 20, 10)
        local later = MakeButton(f, "Not now", 90, function() f:Hide() end)
        later:SetPoint("LEFT", plan, "RIGHT", 6, 0)
        local never = MakeButton(f, "Not in this zone", 130, function()
            local db = DB()
            db.zoneNoAsk = db.zoneNoAsk or {}
            if f.zoneId then db.zoneNoAsk[f.zoneId] = true end
            f:Hide()
        end)
        never:SetPoint("LEFT", later, "RIGHT", 6, 0)
        f:Hide()
        zoneToast = f
    end
    zoneToast.zoneId = zoneId
    zoneToast.text:SetText("You are in " .. ZoneName(zoneId))
    do
        local base = "Plan the quests you can do here, or leave it if you are just passing through?"
        local pace = addon.HivePace and addon.HivePace(ZoneName(zoneId))
        zoneToast.sub:SetText(pace and (base .. string.format("\nYou have earned about %d XP per hour here before.", pace)) or base)
    end
    zoneToast:Show()
    local token = zoneToken
    if C_Timer and C_Timer.After then
        C_Timer.After(30, function() if zoneToast and zoneToast:IsShown() and token == zoneToken then zoneToast:Hide() end end)
    end
end

local function CheckZoneOffer(zoneId, token)
    if token ~= zoneToken or not On() then return end
    local db = DB()
    if not db or db.zonePrompt == false or not addon.ModuleOn("plan") then return end
    if db.zoneNoAsk and db.zoneNoAsk[zoneId] then return end
    local here = api.hbd:GetPlayerZone()
    if here ~= zoneId then return end                                    -- I moved on: just passing through
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    if (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) or (InCombatLockdown and InCombatLockdown()) then return end
    if IsInInstance and IsInInstance() then return end
    if IsResting and IsResting() then return end                         -- towns and inns
    if addon.GoStatus and addon.GoStatus() then return end               -- a trip is under way
    -- nothing here worth doing for my level (all red or grey): do not ask
    if addon.ZoneWorthPlanning and addon.ZoneWorthPlanning(zoneId) == false then return end
    local wp = db.waypoints and db.waypoints[1]
    if wp and wp.label and wp.uiMapId == zoneId then return end          -- already planned for here
    ShowZoneToast(zoneId)
end

local zoneEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do pcall(zoneEv.RegisterEvent, zoneEv, e) end
zoneEv:SetScript("OnEvent", function()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(2, function()
        local id = api.hbd:GetPlayerZone()
        if not id or id == lastZone then return end
        lastZone = id
        zoneToken = zoneToken + 1
        if zoneToast then zoneToast:Hide() end
        local token = zoneToken
        C_Timer.After(STAY_SECONDS, function() pcall(CheckZoneOffer, id, token) end)
    end)
end)

local gossipBar
local function GossipText()
    if C_GossipInfo and C_GossipInfo.GetText then return C_GossipInfo.GetText() end
    if GetGossipText then return GetGossipText() end
end
local function BuildGossip()
    if not On() or not addon.ModuleOn("boats") then return end
    local f = _G.GossipFrame
    if not f then return end
    if not gossipBar then
        gossipBar = BarUnder(f, { { "Mark this dock", 110, function() Cmd("boat", "mark") end } })
        built.gossip = "GossipFrame"
    end
    local text = (GossipText() or ""):lower()
    local boat = text:find("berth", 1, true) or text:find("passage", 1, true) or text:find("zeppelin", 1, true) or text:find("ferry", 1, true)
    gossipBar:SetShown(boat and true or false)
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "BANKFRAME_OPENED",
                     "TAXIMAP_OPENED", "GOSSIP_SHOW", "BAG_UPDATE_DELAYED", "TRADE_SKILL_LIST_UPDATE",
                     "TRADE_SKILL_DATA_SOURCE_CHANGED", "ADDON_LOADED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if not C_Timer then return end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(3, function()
            Try("minimap", HookMinimap)
            local wm = _G.WorldMapFrame
            if wm and wm.HookScript then
                wm:HookScript("OnShow", function()
                    Try("map", BuildMap)
                    if not _G.QuestLogFrame then Try("quest", BuildQuestLog) end
                end)
            end
            local ql = _G.QuestLogFrame
            if ql and ql.HookScript then ql:HookScript("OnShow", function() Try("quest", BuildQuestLog) end) end
        end)
    elseif event == "ADDON_LOADED" then
        -- the professions window is loaded the first time it is needed: attach then
        if arg1 == "Blizzard_Professions" or arg1 == "Blizzard_TradeSkillUI" then
            C_Timer.After(0.5, function()
                local pf = _G.ProfessionsFrame or _G.TradeSkillFrame
                if pf and pf.HookScript then
                    pf:HookScript("OnShow", function()
                        if addon.ReadProfession then addon.ReadProfession() end
                        Try("craft", ShowCraft, { "ProfessionsFrame", "TradeSkillFrame" })
                    end)
                end
            end)
        end
    elseif event == "TRADE_SKILL_SHOW" then
        C_Timer.After(0.2, function() Try("craft", ShowCraft, { "TradeSkillFrame", "ProfessionsFrame" }) end)
    elseif event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "TRADE_SKILL_LIST_UPDATE" then
        C_Timer.After(1.2, function() pcall(RefreshCraftPanel) end)
    elseif event == "TRADE_SKILL_UPDATE" or event == "CRAFT_UPDATE" then
        C_Timer.After(1.2, function() pcall(RefreshCraftPanel) end)
    elseif event == "CRAFT_SHOW" then
        C_Timer.After(0.2, function() Try("craft", ShowCraft, { "CraftFrame", "ProfessionsFrame" }) end)
    elseif event == "BANKFRAME_OPENED" or event == "BAG_UPDATE_DELAYED" then
        C_Timer.After(0.5, function() Try("bank", GlowBank) end)
    elseif event == "TAXIMAP_OPENED" then
        C_Timer.After(0.2, function() Try("taxi", BuildTaxi) end)
    elseif event == "GOSSIP_SHOW" then
        C_Timer.After(0.2, function() Try("gossip", BuildGossip) end)
    end
end)

--------------------------------------------------------------------------------
-- /lazy windows: which windows were found, and what failed (for bug reports)
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "windows" then
        local function has(n) return _G[n] and "yes" or "no" end
        Print(L("buttons in the windows: ") .. (On() and "on" or "OFF in the options"))
        Print(string.format(L("  windows: map %s, quest log %s, quest map %s, old profession %s, new profession %s, bank %s, flight map %s, new flight map %s, gossip %s, minimap button %s"),
            has("WorldMapFrame"), has("QuestLogFrame"), has("QuestMapFrame"), has("TradeSkillFrame"), has("ProfessionsFrame"),
            has("BankFrame"), has("TaxiFrame"), has("FlightMapFrame"), has("GossipFrame"), has("ForeverLazy_MinimapButton")))
        Print(string.format(L("  old profession API %s, new profession API %s"),
            GetTradeSkillLine and "yes" or "no", (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) and "yes" or "no"))
        local d = addon.CraftDiag
        if d then
            Print(string.format(L("  last recipe read: profession %s, %s recipes listed, %s learned read%s"), tostring(d.profession), tostring(d.total or "?"),
                tostring(d.recipes or 0), d.note and (" - " .. d.note) or ""))
        else
            Print(L("  no recipe read yet (open a profession window)"))
        end
        local h = addon.HighlightDiag
        if h then
            Print(string.format(L("  recipe list: window %s, source %s, rows seen %s, plan pick %s, matched %s, sample ids %s%s"),
                tostring(h.window), tostring(h.source), tostring(h.rows), tostring(h.best),
                tostring(h.matched), tostring(h.sampleIds), h.note and (" - " .. h.note) or ""))
        end
        local any
        for k, v in pairs(built) do Print(L("  built on ") .. k .. ": " .. tostring(v)); any = true end
        if not any then Print(L("  nothing built yet (open a window, then try again)")) end
        local bad
        for k, v in pairs(problems) do Print(L("  |cffff5555problem|r ") .. k .. ": " .. v); bad = true end
        if not bad then Print(L("  no errors recorded")) end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["UI.lua"] = true end end
