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

-- The bank bag slots. The bank is the base bank (Tab 1, the first container) and then up to eight slots, each holding a bag of mine
-- (this client says so: ShouldUsePlayerBagsInBank). I read how many are bought, and which hold a bag, from the game's own data.
local MAXB = 8
local function BankData()
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum and Enum.BankType then
        local ok, data = pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType.Character)
        if ok and type(data) == "table" then return data end
    end
end
local function BagsInBank()
    if not (C_Bank and C_Bank.ShouldUsePlayerBagsInBank) then return false end
    local ok, v = pcall(C_Bank.ShouldUsePlayerBagsInBank)
    return ok and v == true
end
local function FirstBankId()
    local data = BankData()
    if data and data[1] and data[1].ID then return tonumber(data[1].ID) end
    return (_G.NUM_BAG_SLOTS or 4) + (_G.NUM_REAGENTBAG_SLOTS or 0) + 1
end
local function SlotCounts()
    local data = BankData()
    local owned = data and #data or 1
    local total = (Constants and Constants.InventoryConstants and tonumber(Constants.InventoryConstants.NumCharacterBankSlots)) or 9
    return math.max(0, owned - 1), math.min(MAXB, math.max(1, total - 1))            -- the base bank is not a bag slot
end
local function ContainerOfSlot(i) return FirstBankId() + i end
local function InvSlotOf(containerId)
    if C_Container and C_Container.ContainerIDToInventoryID then
        local ok, v = pcall(C_Container.ContainerIDToInventoryID, containerId)
        if ok and v then return v end
    end
    if ContainerIDToInventoryID then
        local ok, v = pcall(ContainerIDToInventoryID, containerId)
        if ok and v then return v end
    end
    return nil
end
local function NumSlotsOf(containerId)
    return (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(containerId)) or 0
end

--------------------------------------------------------------------------------
-- The game's own bank window, brought forward on request
--------------------------------------------------------------------------------
-- Buying a bank slot is a protected action: an addon cannot call it. What an addon can do is lay the game's own Purchase button, invisible,
-- over its own button, so the click lands on the real one (the game then shows its own confirmation with the price). It goes back where it was
-- when the mouse leaves.
local function GamePurchaseButton()
    if _G.BankFramePurchaseButton then return _G.BankFramePurchaseButton, "BankFramePurchaseButton" end
    local bp = _G.BankPanel
    local pb = bp and bp.PurchasePrompt and bp.PurchasePrompt.TabCostFrame and bp.PurchasePrompt.TabCostFrame.PurchaseButton
    if pb then return pb, "BankPanel purchase prompt" end
    return nil
end

local function ShowBuyTip(owner, placed, why)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L("Buy the next bank slot"), 0.3, 1, 0.3)
    local okC, cost = pcall(NextCost)
    if okC and cost then GameTooltip:AddLine(L("Cost: ") .. Money(cost), 1, 1, 1) end
    if placed then
        GameTooltip:AddLine(L("Click it: the game asks you to confirm, and shows the price."), 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(why or L("Not available here: all bought, in combat, or this client has no Purchase button. Use the game's window."), 1, 0.7, 0.3, true)
    end
    GameTooltip:Show()
end

local proxied                -- { button =, parent =, points = { ... }, alpha =, target = }
local hookedButtons = {}
local function RestoreProxy()
    if not proxied then return end
    local pb = proxied.button
    if InCombatLockdown and InCombatLockdown() then return end        -- a secure button moves only out of combat
    pcall(function()
        pb:SetParent(proxied.parent)
        pb:ClearAllPoints()
        for _, pt in ipairs(proxied.points) do pb:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
        pb:SetAlpha(proxied.alpha or 1)
    end)
    proxied = nil
end

local function ProxyOver(target)
    if InCombatLockdown and InCombatLockdown() then return false, L("In combat: the game's button cannot be moved until the fight ends.") end
    local pb = GamePurchaseButton()
    if not pb then return false, L("This client has no Purchase button to use. Use the game's window (the button below).") end
    if not proxied then
        local pts = {}
        for i = 1, (pb.GetNumPoints and pb:GetNumPoints() or 0) do pts[#pts + 1] = { pb:GetPoint(i) } end
        proxied = { button = pb, parent = pb:GetParent(), points = pts, alpha = pb:GetAlpha() }
    end
    proxied.target = target
    if not hookedButtons[pb] then
        hookedButtons[pb] = true
        -- the game's button is now the one under the mouse: it shows the tooltip, and sends itself home when the mouse leaves
        pcall(pb.HookScript, pb, "OnEnter", function() if proxied and proxied.button == pb and proxied.target then ShowBuyTip(proxied.target, true) end end)
        pcall(pb.HookScript, pb, "OnLeave", function() GameTooltip:Hide(); if proxied and proxied.button == pb then RestoreProxy() end end)
    end
    pcall(function()
        if pb.SetAttribute and Enum and Enum.BankType then pb:SetAttribute("overrideBankType", Enum.BankType.Character) end
        pb:SetParent(target)
        pb:ClearAllPoints()
        pb:SetAllPoints(target)
        pb:SetFrameLevel(target:GetFrameLevel() + 10)
        pb:SetAlpha(0)
        pb:Show()
    end)
    return true
end

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
    f:SetSize(274, 52)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.04, 0.06, 0.95); f:SetBackdropBorderColor(0.6, 0.6, 0.7, 1)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", 8, -5)
    f.title:SetText(L("Bank bag slots"))
    -- the bank bag slots themselves: put a bag in one, take it out, or buy the next
    f.slots = {}
    for i = 1, MAXB do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(28, 28)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * 32, -20)
        b:RegisterForClicks("LeftButtonUp")
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
        b.shade = b:CreateTexture(nil, "OVERLAY"); b.shade:SetAllPoints(); b.shade:SetColorTexture(0, 0, 0, 0)
        b.plus = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); b.plus:SetPoint("CENTER")
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
        b.index = i
        local function Use(self)
            if self.state == "buy" then return end                        -- the game's own Purchase button lies over this one
            if self.state == "locked" then Print(L("bank: buy the slot before this one first")); return end
            local container = ContainerOfSlot(self.index)
            local inv = InvSlotOf(container)
            if not inv then Print(string.format(L("bank: I cannot find the game slot for bank bag slot %d (container %d). /lazy bankslots"), self.index, container)); return end
            if GetCursorInfo and GetCursorInfo() == "item" then
                local ok, err = pcall(PutItemInBag, inv)                    -- the bag on my cursor goes into this slot
                if not ok then Print(L("bank: could not put it there: ") .. tostring(err))
                elseif GetCursorInfo and GetCursorInfo() == "item" then
                    Print(L("bank: the game would not put that in this slot (is it a bag?)"))
                end
            elseif self.state == "bag" then
                pcall(PickupBagFromSlot, inv)                                 -- take the bag out again
            else
                Print(L("bank: pick up a bag first (click it in your bags), then click this slot, or drag the bag onto it"))
            end
        end
        b:SetScript("OnClick", Use)
        b:SetScript("OnReceiveDrag", Use)
        b:SetScript("OnEnter", function(self)
            if self.state == "buy" then
                local ok, placed, why = pcall(ProxyOver, self)
                ShowBuyTip(self, ok and placed, ok and why or nil)
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local container = ContainerOfSlot(self.index)
            local inv = InvSlotOf(container)
            if self.state == "bag" then
                if inv then GameTooltip:SetInventoryItem("player", inv)
                else GameTooltip:AddLine(string.format(L("A bag with %d slots"), NumSlotsOf(container)), 1, 1, 1) end
                GameTooltip:AddLine(L("Click to take it out."), 0.7, 0.7, 0.7)
            elseif self.state == "empty" then
                GameTooltip:AddLine(L("Empty bank bag slot"), 1, 0.82, 0)
                GameTooltip:AddLine(L("Pick up a bag, then click here (or drag it onto this slot)."), 0.8, 0.8, 0.8, true)
            else
                GameTooltip:AddLine(L("Not bought yet"), 0.6, 0.6, 0.6)
                GameTooltip:AddLine(L("Buy the slot before it first."), 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            local pb = proxied and proxied.button
            if self.state == "buy" and pb and pb.IsMouseOver and pb:IsMouseOver() then return end
            GameTooltip:Hide()
            if self.state == "buy" then RestoreProxy() end
        end)
        f.slots[i] = b
    end
    f:Hide()
    return f
end

-- paint the row: which slots hold a bag, which are bought but empty, which one is next, which are locked
local function RefreshRow()
    if not (panel and panel:IsShown() and panel.slots) then return end
    local owned, total
    local states
    if BagsInBank() then
        owned, total = SlotCounts()
        states = addon.BankSlotStates(owned, total, function(i) return NumSlotsOf(ContainerOfSlot(i)) > 0 end)
    else
        -- a client with bank tabs, not bags: just the buy square, when there is another tab to buy
        states = (NextCost() and { "buy" }) or {}
    end
    local shown = 0
    for i = 1, MAXB do if states[i] then shown = shown + 1 end end
    panel:SetWidth(math.max(120, 14 + shown * 32))
    panel.title:SetText(shown > 0 and L("Bank bag slots") or L("Bank bag slots: none to buy"))
    for i = 1, MAXB do
        local b, st = panel.slots[i], states[i]
        if st then
            b.state = st
            local inv = InvSlotOf(ContainerOfSlot(i))
            local tex = (st == "bag" and inv and GetInventoryItemTexture and GetInventoryItemTexture("player", inv)) or nil
            if st == "bag" then b.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_Bag_08")
            else b.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag") end
            b.icon:SetDesaturated(st == "locked")
            b.shade:SetColorTexture(0, 0, 0, st == "locked" and 0.55 or 0)
            b.plus:SetText(st == "buy" and "|cff55ff55+|r" or "")
            b:Show()
        else
            b:Hide()
        end
    end
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
    panel:Show()
    RefreshRow()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED", "PLAYERBANKBAGSLOTS_CHANGED", "BANK_TABS_CHANGED",
                     "BANK_TAB_SETTINGS_UPDATED", "ITEM_LOCK_CHANGED", "PLAYER_MONEY" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        if C_Timer then C_Timer.After(0.8, function() pcall(Show) end) end       -- after the bank window is up
    elseif event ~= "BANKFRAME_CLOSED" then
        pcall(RefreshRow)
    else
        gameShown = false
        RestoreProxy()
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
        if a == "mouse" then
            -- /lazy bankslots mouse, then hold the mouse over the buy button: five seconds later it says what is under the mouse
            Print(L("bank: hold the mouse over the Buy the next bank slot button, I will look in 5 seconds"))
            if C_Timer and C_Timer.After then C_Timer.After(5, function()
                local lines = {}
                local function Add(s) lines[#lines + 1] = s end
                Add("bank slots code: buy-button version (hover, then the game's Purchase button laid over ours)")
                local f
                if GetMouseFoci then f = (GetMouseFoci() or {})[1] elseif GetMouseFocus then f = GetMouseFocus() end
                if not f then Add("nothing is under the mouse")
                else
                    local n = 0
                    local cur = f
                    while cur and n < 8 do
                        Add(string.format("%s%s (%s)  strata %s, level %s, mouse %s, alpha %.2f, shown %s", n == 0 and "under the mouse: " or "    inside: ",
                            tostring(cur.GetName and cur:GetName() or "(unnamed)"), tostring(cur.GetObjectType and cur:GetObjectType() or "?"),
                            tostring(cur.GetFrameStrata and cur:GetFrameStrata() or "?"), tostring(cur.GetFrameLevel and cur:GetFrameLevel() or "?"),
                            tostring(cur.IsMouseEnabled and cur:IsMouseEnabled() or "?"), cur.GetAlpha and cur:GetAlpha() or 0, tostring(cur.IsShown and cur:IsShown() or "?")))
                        cur = cur.GetParent and cur:GetParent(); n = n + 1
                    end
                    Add("is it our buy button: " .. tostring(panel and panel.buy == f))
                end
                if panel then
                    Add(string.format("our box: shown %s, strata %s, level %s, size %dx%d, top %s", tostring(panel:IsShown()), tostring(panel:GetFrameStrata()), tostring(panel:GetFrameLevel()),
                        panel:GetWidth() or 0, panel:GetHeight() or 0, tostring(panel:GetTop())))
                    if panel.buy then Add(string.format("our buy button: shown %s, level %s, left %s, top %s, enabled %s", tostring(panel.buy:IsShown()), tostring(panel.buy:GetFrameLevel()), tostring(panel.buy:GetLeft()), tostring(panel.buy:GetTop()), tostring(panel.buy:IsEnabled()))) end
                else Add("our box does not exist") end
                local win = addon.BankWindowFrame and addon.BankWindowFrame()
                if win then Add(string.format("our bank window: strata %s, level %s, bottom %s, left %s", tostring(win:GetFrameStrata()), tostring(win:GetFrameLevel()), tostring(win:GetBottom()), tostring(win:GetLeft()))) end
                local bf = _G.BankFrame
                if bf then Add(string.format("the game's bank window: shown %s, alpha %.2f, strata %s, level %s, mouse %s", tostring(bf:IsShown()), bf:GetAlpha(), tostring(bf:GetFrameStrata()), tostring(bf:GetFrameLevel()), tostring(bf:IsMouseEnabled()))) end
                if addon.ReportWindow then addon.ReportWindow(L("Forever Lazy: bank slots mouse"), lines) else for _, l in ipairs(lines) do Print(l) end end
            end) end
            return true
        end
        if a == "window" then SetGameBank(not gameShown); Print(gameShown and L("bank: the game's own bank window is in front (/lazy bankslots window hides it)") or L("bank: the game's own bank window is hidden again")); return true end
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
            local pb, pbName = GamePurchaseButton()
            Add("the game's Purchase button we can lay over ours: " .. (pb and (pbName .. (pb:IsShown() and " (shown)" or " (hidden)")) or "none found"))
            if C_Bank then
                local function Try(name, ...)
                    local fn = C_Bank[name]
                    if not fn then return name .. ": not in this client" end
                    local ok, v = pcall(fn, ...)
                    return name .. ": " .. (ok and tostring(v) or ("error " .. tostring(v)))
                end
                Add(Try("ShouldUsePlayerBagsInBank"))
                Add(Try("FetchNumPurchasedBankTabs", Enum and Enum.BankType and Enum.BankType.Character or 0))
                if C_Bank.FetchPurchasedBankTabData then
                    local ok, data = pcall(C_Bank.FetchPurchasedBankTabData, Enum and Enum.BankType and Enum.BankType.Character or 0)
                    if ok and type(data) == "table" then
                        Add("purchased bank tabs/slots: " .. #data)
                        for i, d in ipairs(data) do Add(string.format("    %d: id=%s name=%s icon=%s", i, tostring(d.ID), tostring(d.name), tostring(d.icon))) end
                    else
                        Add("FetchPurchasedBankTabData: " .. tostring(data))
                    end
                end
            end
            for i = 1, MAXB do
                local c = ContainerOfSlot(i)
                local inv = InvSlotOf(c)
                Add(string.format("bank bag slot %d: container %d, %d slots, inventory slot %s, picture %s", i, c, NumSlotsOf(c), tostring(inv),
                    tostring(inv and GetInventoryItemTexture and GetInventoryItemTexture("player", inv) or "none")))
            end
            Add("Constants NumCharacterBankSlots: " .. tostring(Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumCharacterBankSlots) .. "    BankButtonIDToInvSlotID: " .. tostring(BankButtonIDToInvSlotID ~= nil))
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
