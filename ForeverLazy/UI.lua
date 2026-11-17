-- Buttons and menus in the game's own windows, so most things are a click instead of a slash command.
--   minimap button: left-click = Lazy Mode, right-click = the menu, shift+left-click = options
--   world map: a search box ("go to ...") and a Lazy button
--   quest log: plan my route, do this quest next, skip it
--   profession window: a craft plan panel with the materials (bags and bank)
--   bank: the materials your craft plan needs are lit up
--   flight map: nearest new flight point, take me there
--   boat NPC chat: mark this dock
-- Everything sits beside or below the game's windows, never on top of their own buttons.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On() local d = DB(); return d and d.uiButtons ~= false end

local function Cmd(cmd, rest)
    if addon.HandleExtraCommand then addon:HandleExtraCommand(cmd, rest) end
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
    menu:Show()
end

local function Back(fn) return { text = "< Back", fn = function() addon:OpenMenu() end } end

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
    }
end

function addon:OpenMenu()
    addon.ShowMenu({
        { text = "Do the next thing (Lazy Mode)", fn = function() Cmd("now") end, module = "lazymode" },
        { text = "Plan my route", fn = function() addon:PlanRoute() end, module = "plan" },
        { text = "Plan window", fn = function() Cmd("window") end, module = "plan" },
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
    local b = _G.LRXPT_MinimapButton
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
        GameTooltip:AddLine("Forever Lazy")
        GameTooltip:AddLine("Left-click: do the next thing", 1, 1, 1)
        GameTooltip:AddLine("Right-click: the menu", 1, 1, 1)
        GameTooltip:AddLine("Shift-click: options", 1, 1, 1)
        GameTooltip:Show()
    end)
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
    if not wm then return end
    mapBuilt = true
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
    local f = _G.QuestLogFrame or _G.QuestLogPopupDetailFrame
    if not f then return end
    questBar = BarUnder(f, {
        { "Plan my route", 110, function() addon:PlanRoute() end },
        { "Do this next", 100, function()
            local id, title = SelectedQuest()
            if id then addon:FocusQuest(id, title) else Print("select a quest in the log first") end
        end },
        { "Skip this", 80, function()
            local id, title = SelectedQuest()
            if id and addon.SkipQuest then addon.SkipQuest(id, title) else Print("select a quest in the log first") end
        end },
    })
end

--------------------------------------------------------------------------------
-- Profession window: the craft plan panel
--------------------------------------------------------------------------------
local craftPanel
local function RefreshCraftPanel()
    if not craftPanel or not craftPanel:IsShown() then return end
    local lines = addon.CraftPlanText and addon.CraftPlanText() or { "crafting is switched off" }
    craftPanel.text:SetText(table.concat(lines, "\n"))
    craftPanel:SetHeight(math.max(80, 60 + craftPanel.text:GetStringHeight()))
end

local function BuildCraftPanel(frame)
    if craftPanel then
        craftPanel:SetParent(frame); craftPanel:ClearAllPoints()
        craftPanel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, -40)
        craftPanel:Show()
        return
    end
    local p = CreateFrame("Frame", "ForeverLazy_CraftPanel", frame)
    p:SetSize(330, 120)
    p:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, -40)
    p:SetFrameStrata("HIGH")
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
    local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 10, -8); t:SetText("Forever Lazy: craft plan")
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.text:SetPoint("TOPLEFT", 10, -28)
    p.text:SetWidth(310); p.text:SetJustifyH("LEFT"); p.text:SetJustifyV("TOP")
    local b1 = MakeButton(p, "Where to get it", 110, function() Cmd("craft", "go") end)
    b1:SetPoint("BOTTOMLEFT", 8, 8)
    local b2 = MakeButton(p, "Bank", 60, function() Cmd("craft", "bank") end)
    b2:SetPoint("LEFT", b1, "RIGHT", 4, 0)
    local b3 = MakeButton(p, "Refresh", 70, function() RefreshCraftPanel() end)
    b3:SetPoint("LEFT", b2, "RIGHT", 4, 0)
    craftPanel = p
end

local function ShowCraft(frameName)
    if not On() or not addon.ModuleOn("crafting") then return end
    local f = _G[frameName]
    if not f then return end
    BuildCraftPanel(f)
    if C_Timer then C_Timer.After(1.2, RefreshCraftPanel) end
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
    local f = _G.TaxiFrame
    if not f then return end
    taxiBar = BarUnder(f, {
        { "Nearest new flight point", 160, function() Cmd("fp") end },
        { "Take me to...", 100, function() Ask("Where to?", function(t) Cmd("go", t) end) end },
    })
end

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
                     "TAXIMAP_OPENED", "GOSSIP_SHOW", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if not C_Timer then return end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(3, function()
            pcall(HookMinimap)
            local wm = _G.WorldMapFrame
            if wm and wm.HookScript then wm:HookScript("OnShow", function() pcall(BuildMap) end) end
            local ql = _G.QuestLogFrame
            if ql and ql.HookScript then ql:HookScript("OnShow", function() pcall(BuildQuestLog) end) end
        end)
    elseif event == "TRADE_SKILL_SHOW" then
        C_Timer.After(0.2, function() pcall(ShowCraft, "TradeSkillFrame") end)
    elseif event == "TRADE_SKILL_UPDATE" or event == "CRAFT_UPDATE" then
        C_Timer.After(1.2, function() pcall(RefreshCraftPanel) end)
    elseif event == "CRAFT_SHOW" then
        C_Timer.After(0.2, function() pcall(ShowCraft, "CraftFrame") end)
    elseif event == "BANKFRAME_OPENED" or event == "BAG_UPDATE_DELAYED" then
        C_Timer.After(0.5, function() pcall(GlowBank) end)
    elseif event == "TAXIMAP_OPENED" then
        C_Timer.After(0.2, function() pcall(BuildTaxi) end)
    elseif event == "GOSSIP_SHOW" then
        C_Timer.After(0.2, function() pcall(BuildGossip) end)
    end
end)
