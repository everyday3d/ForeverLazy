-- The bank's bag slots. On this client they are bought, and bags are put into them, in the game's own bank window, which our bank window
-- replaces. So under our bank window there is one button that brings the game's own bank window back on top, and takes it away again.
-- (Buying and placing bags is done there, by the game, with its own price and confirmation.)
--   /lazy bankslots          what this client offers, in a window you can copy        /lazy bankslots on|off   the button under the bank window
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

-- States of the slots (kept for the tests and a later row of slots): bought = how many I own, max = how many exist
function addon.BankSlotStates(bought, max, equipped)
    local out = {}
    for i = 1, max do
        if i <= bought then out[i] = (equipped and equipped(i)) and "bag" or "empty"
        elseif i == bought + 1 then out[i] = "buy"
        else out[i] = "locked" end
    end
    return out
end

local function TabMode()
    return C_Bank and C_Bank.FetchNextPurchasableBankTabData and Enum and Enum.BankType and Enum.BankType.Character ~= nil
end

local function Money(copper)
    if GetMoneyString then
        local ok, s = pcall(GetMoneyString, copper)
        if ok and s then return s end
    end
    return tostring(copper) .. "c"
end

-- the price of the next one, from the game's own bank data (never read off the screen: the bank window shows my gold too)
local function NextCost()
    if not TabMode() then return nil end
    local ok, data = pcall(C_Bank.FetchNextPurchasableBankTabData, Enum.BankType.Character)
    return ok and type(data) == "table" and tonumber(data.tabCost) or nil
end

--------------------------------------------------------------------------------
-- The game's own bank window, brought forward on request
--------------------------------------------------------------------------------
local gameShown = false
local function SetGameBank(show)
    local bf = _G.BankFrame
    if not bf then Print(L("bank: this client has no game bank window to show")); return end
    gameShown = show
    if show then
        bf:SetAlpha(1)
        if bf.SetFrameStrata then bf:SetFrameStrata("FULLSCREEN_DIALOG") end
        if bf.Raise then bf:Raise() end
    else
        bf:SetAlpha(0)                            -- back out of sight (it stays open: the bank needs it)
    end
end

local panel
local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_BankSlots", UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH")
    f:SetSize(250, 46)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.04, 0.06, 0.95); f:SetBackdropBorderColor(0.6, 0.6, 0.7, 1)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", 8, -5)
    f.title:SetText(L("Bank bag slots"))
    f.btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.btn:SetSize(232, 22)
    f.btn:SetPoint("TOPLEFT", 8, -18)
    f.btn:SetText(L("Buy slots / put bags in: the game's window"))
    f.btn:SetScript("OnClick", function(self)
        SetGameBank(not gameShown)
        self:SetText(gameShown and L("Hide the game's bank window") or L("Buy slots / put bags in: the game's window"))
    end)
    f.btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("Bank bag slots"), 1, 0.82, 0)
        GameTooltip:AddLine(L("Brings the game's own bank window forward. Its Bag Slots row has the Purchase button and the places to put your bags."), 1, 1, 1, true)
        local cost = NextCost()
        if cost then GameTooltip:AddLine(L("The next one costs ") .. Money(cost), 0.5, 1, 0.5) end
        GameTooltip:AddLine(L("Click again to hide it."), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    f.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

local function Place()
    local win = addon.BankWindowFrame and addon.BankWindowFrame()
    if not win then return false end
    panel = panel or Build()
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 0, -2)
    return true
end

local function Show()
    local db = DB()
    if db and db.bankSlots == false then return end
    gameShown = false
    if not Place() then return end
    panel.btn:SetText(L("Buy slots / put bags in: the game's window"))
    panel:Show()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        if C_Timer then C_Timer.After(0.8, function() pcall(Show) end) end       -- after the bank window is up
    else
        gameShown = false
        if panel then panel:Hide() end
    end
end)

--------------------------------------------------------------------------------
-- /lazy bankslots
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "bankslots" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "off" then db.bankSlots = false; if panel then panel:Hide() end; Print(L("bank bag slots button: off"))
        elseif a == "on" then db.bankSlots = nil; pcall(Show); Print(L("bank bag slots button: on (it shows under the bank window)"))
        else
            local lines = {}
            local function Add(s) lines[#lines + 1] = s end
            local ids = {}
            for b = 5, 14 do ids[#ids + 1] = b .. "=" .. tostring(C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(b) or "?") end
            Add("slots in containers 5 to 14: " .. table.concat(ids, "  "))
            Add("containers counted as the bank: " .. table.concat(addon.BankContainerIds and addon.BankContainerIds() or {}, ","))
            Add(string.format("bank tab system: %s    the game's bank window: %s", tostring(TabMode() and true or false), tostring(_G.BankFrame ~= nil)))
            local cost = NextCost()
            Add("next one costs: " .. (cost and Money(cost) or "unknown (nothing left to buy, or not at the bank)"))
            Add(string.format("our bank window: %s    our button: %s    your gold: %s", tostring(addon.BankWindowFrame and addon.BankWindowFrame() ~= nil), tostring(panel and panel:IsShown() or false), Money(GetMoney and GetMoney() or 0)))
            Add("Nothing is bought by this. /lazy bankslots on|off")
            if addon.ReportWindow then addon.ReportWindow(L("Forever Lazy: bank slots"), lines) else for _, l in ipairs(lines) do Print(l) end end
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["BankSlots.lua"] = true end end
