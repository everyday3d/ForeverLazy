-- One bag window for everything, with the useful parts of Bagnon:
--   * all your bags in one window (columns you can change), free slots and money
--   * a search box that dims what does not match, coloured borders for quality and quest items
--   * the bank in the same window when you are at the bank
--   * look inside any of your other characters' bags, bank and mail (from what Forever Lazy saved when you played them)
-- It takes over the bag keys and buttons when Bagnon is NOT running (or when you say so). With Bagnon running it stays out of the way
-- and opens only with  /lazy bags.
--   /lazy bags                 open or close the window
--   /lazy bags replace on|off  take over the bag keys and buttons (default: only when Bagnon is not loaded)
--   /lazy bags cols <n>        slots per row     /lazy bags scale <n>     size     /lazy bags reset   move it back
local ADDON, ns = ...
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

local atBank = false                 -- shared by both windows
local function ByCat() local db = addon.GetDB(); return not (db and db.bagsByCategory == false) end
local NUMBAGS = NUM_BAG_SLOTS or 4

-- Everything below (up to the end of "Open, close") is ONE bag window. At the bank there are two of them side by side:
-- the main one shows my bags, the second (isBank) shows the bank, so things can be moved from one to the other.
local function NewWindow(id, isBank)
local GN = (id == 1) and "" or tostring(id)          -- keeps the global frame names apart
local SZ, GAP = 37, 3
local catFilter = nil       -- nil = everything, otherwise a key of CATS
local CategoryOf             -- defined further down
-- the categories: each one is a tab and a section, and only exists while you carry something of that kind
local CATS = {
    { key = "all",     text = "All" },
    { key = "travel",  text = "Travel" },
    { key = "quest",   text = "Quest" },
    { key = "gear",    text = "Equipment" },
    { key = "food",    text = "Food & drink" },
    { key = "potion",  text = "Potions" },
    { key = "bandage", text = "Bandages" },
    { key = "use",     text = "Consumables" },
    { key = "trade",   text = "Trade goods" },
    { key = "reagent", text = "Reagents" },
    { key = "recipe",  text = "Recipes" },
    { key = "gem",     text = "Gems" },
    { key = "ammo",    text = "Ammo" },
    { key = "bags",    text = "Bags" },
    { key = "key",     text = "Keys" },
    { key = "misc",    text = "Misc" },
    { key = "junk",    text = "Junk" },
}
local function CatMatch(info, bag, slot)
    if not catFilter or catFilter == "all" then return true end
    if not info then return false end
    return CategoryOf({ info = info, bag = bag, slot = slot }) == catFilter
end
local frame, buttons, bagFrames, offButtons = nil, {}, {}, {}
local view = { char = nil, place = "bags" }     -- char nil = me
local searchText = ""
local btnCount = 0
local dirty, layoutNeeded = true, true

--------------------------------------------------------------------------------
-- Which bags
--------------------------------------------------------------------------------
local function BagList()
    local list = {}
    for b = 0, NUMBAGS do list[#list + 1] = b end
    local reagent = NUM_REAGENTBAG_SLOTS or 0
    for b = NUMBAGS + 1, NUMBAGS + reagent do list[#list + 1] = b end
    return list
end
local function BankList()
    local list = { -1 }
    local first = NUMBAGS + (NUM_REAGENTBAG_SLOTS or 0) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = b end
    return list
end

local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function SlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" then return info end
        return nil
    end
    if GetContainerItemInfo then
        local icon, count, locked, quality, _, _, link = GetContainerItemInfo(bag, slot)
        if icon then return { iconFileID = icon, stackCount = count, isLocked = locked, quality = quality, hyperlink = link } end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local Refresh

local function Cols() return math.max(4, math.min(24, (DB() and DB().bagsCols) or 10)) end

local function SavePos()
    local db = DB()
    if not (db and frame) or isBank then return end
    local p, _, rp, x, y = frame:GetPoint(1)
    db.bagsPos = { p, rp, x, y }
end

local function Button(text, w, onClick, tip)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if tip then
        b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

local function CharList()
    local out = {}
    local root = addon.GetRoot and addon.GetRoot()
    local inv = root and root.inv or {}
    local me = (UnitName("player") or "?")
    for k, c in pairs(inv) do
        if type(c) == "table" and not (k:sub(-1) == "-") then out[#out + 1] = { key = k, name = c.full or c.name or k, me = (c.name == me) } end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        return a.name < b.name
    end)
    return out
end

-- lowest quality that gets a coloured border: -1 = none, 0 = grey and up, 1 = white and up, 2 = green and up (default), 3 = blue and up
local function BorderMin()
    local v = DB() and DB().bagsBorderMin
    if v == nil then return 2 end
    return v
end
local BORDER_NAMES = { [-1] = "none", [0] = "all items", [1] = "common and up", [2] = "uncommon and up", [3] = "rare and up" }

local function BuildNow()
    frame = CreateFrame("Frame", "ForeverLazyBagsFrame" .. GN, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.04, 0.04, 0.06, (DB() and DB().bagsAlpha) or 0.92)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.7, 1)
    local pos = DB() and DB().bagsPos
    if isBank then
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 110)      -- placed beside the bag window each time the bank opens
    elseif pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 110) end
    frame:SetScale((DB() and DB().bagsScale) or 1)
    if UISpecialFrames then table.insert(UISpecialFrames, "ForeverLazyBagsFrame" .. GN) end
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 10, -9)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- who and where
    frame.who = Button("Character", 80, function()
        local list = CharList()
        local cur = 0
        for i, c in ipairs(list) do if c.key == view.char then cur = i end end
        local nxt = list[cur + 1]
        if cur == 0 then nxt = list[1] end
        -- first one is me
        if nxt and nxt.me then view.char = nil elseif nxt then view.char = nxt.key else view.char = nil end
        if cur == #list then view.char = nil end
        layoutNeeded = true
        Refresh()
    end, "Click to look at your other characters' bags (from what was saved when you played them)")
    frame.who:SetPoint("TOPLEFT", 10, -28)

    frame.place = Button("Bags", 56, function()
        if view.place == "bags" then view.place = "bank" elseif view.place == "bank" and view.char then view.place = "mail" elseif view.place == "mail" then view.place = "bags" else view.place = "bags" end
        if view.place == "bank" and not view.char and not atBank then
            -- not at the bank: show what the bank held last time
            view.char = view.char
        end
        layoutNeeded = true
        Refresh()
    end, "Bags / bank (/ mail for other characters)")
    frame.place:SetPoint("LEFT", frame.who, "RIGHT", 4, 0)

    frame.sort = Button("Sort", 44, function()
        if view.char then return end
        if InCombatLockdown() then return end
        local f = (C_Container and C_Container.SortBags) or SortBags
        if view.place == "bank" then f = (C_Container and C_Container.SortBankBags) or SortBankBags or f end
        if f then pcall(f) end
    end, "Tidy the items up")
    frame.sort:SetPoint("LEFT", frame.place, "RIGHT", 4, 0)

    -- settings: a little panel of buttons beside the window
    local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    panel:SetSize(210, 140)
    panel:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    panel:SetBackdropBorderColor(0.6, 0.6, 0.7, 1)
    panel:Hide()
    frame.panel = panel
    -- the settings panel always goes away with the bag window (and is its own top layer so it never hides behind it)
    panel:SetFrameStrata("DIALOG")
    frame:HookScript("OnHide", function() panel:Hide() end)
    local rows = {}
    local function Row(i, get, click)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(192, 22)
        b:SetPoint("TOP", 0, -8 - (i - 1) * 26)
        b:SetScript("OnClick", function() click(); for _, r in ipairs(rows) do r.update() end; layoutNeeded = true; Refresh() end)
        b.update = function() b:SetText(get()) end
        rows[#rows + 1] = b
        b.update()
    end
    Row(1, function() return "Auto sort: " .. ((DB().bagsAutoSort ~= false) and "on" or "off") end,
        function() DB().bagsAutoSort = (DB().bagsAutoSort == false) and nil or false end)
    Row(2, function() return "Border colours: " .. BORDER_NAMES[BorderMin()] end,
        function() local v = BorderMin() + 1; if v > 3 then v = -1 end; DB().bagsBorderMin = v end)
    Row(3, function() return "Quest item border: " .. ((DB().bagsQuestBorder ~= false) and "gold" or "off") end,
        function() DB().bagsQuestBorder = (DB().bagsQuestBorder == false) and nil or false end)
    Row(4, function()
        local v = DB().bagsReplace
        return "Replace game bags: " .. (v == true and "always" or v == false and "never" or "auto")
    end, function()
        local v = DB().bagsReplace
        if v == nil then DB().bagsReplace = true elseif v == true then DB().bagsReplace = false else DB().bagsReplace = nil end
    end)
    Row(5, function() return "Item size: " .. SZ end,
        function() local v = (DB().bagsItemSize or 37) + 5; if v > 47 then v = 27 end; DB().bagsItemSize = v end)
    Row(6, function() return "Background: " .. math.floor(((DB().bagsAlpha or 0.92) * 100) + 0.5) .. "%" end,
        function() local v = (DB().bagsAlpha or 0.92); v = (v >= 0.99) and 0.4 or (v < 0.6 and 0.7 or (v < 0.9 and 0.92 or 1)); DB().bagsAlpha = v; frame:SetBackdropColor(0.04, 0.04, 0.06, v) end)
    Row(7, function() return "Item level on gear: " .. ((DB().bagsItemLevel ~= false) and "on" or "off") end,
        function() DB().bagsItemLevel = (DB().bagsItemLevel == false) and nil or false end)
    Row(8, function() return "Layout: " .. (ByCat() and "by category" or "bag order") end,
        function() DB().bagsByCategory = ByCat() and false or nil end)
    panel:SetSize(210, 8 + 8 * 26 + 26)
    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("BOTTOM", 0, 6)
    note:SetWidth(190)
    note:SetText("auto = only when Bagnon is switched off")
    frame.gear = Button("...", 24, function()
        if panel:IsShown() then panel:Hide() else for _, r in ipairs(rows) do r.update() end; panel:Show() end
    end, "Settings: auto sort, border colours, replacing the game's bags")
    frame.gear:SetPoint("LEFT", frame.sort, "RIGHT", 4, 0)
    if isBank then
        -- the bank window is just the bank: no character / place / settings buttons
        frame.who:Hide(); frame.place:Hide(); frame.gear:Hide()
        frame.sort:ClearAllPoints(); frame.sort:SetPoint("TOPLEFT", 10, -28)
        -- closing it (Esc or the X) leaves the bank, like the game's own bank window does
        frame:HookScript("OnHide", function() if atBank and CloseBankFrame then pcall(CloseBankFrame) end end)
    end

    frame.less = Button("-", 22, function() DB().bagsCols = math.max(4, Cols() - 1); layoutNeeded = true; Refresh() end, "Fewer slots per row")
    frame.more = Button("+", 22, function() DB().bagsCols = math.min(24, Cols() + 1); layoutNeeded = true; Refresh() end, "More slots per row")
    frame.more:SetPoint("TOPRIGHT", -28, -28)
    frame.less:SetPoint("RIGHT", frame.more, "LEFT", -2, 0)

    frame.search = CreateFrame("EditBox", "ForeverLazyBagsSearch" .. GN, frame, "InputBoxTemplate")
    frame.search:SetSize(120, 18)
    frame.search:SetAutoFocus(false)
    frame.search:SetPoint("RIGHT", frame.less, "LEFT", -8, 0)
    frame.search:SetScript("OnTextChanged", function(self)
        searchText = (self:GetText() or ""):lower()
        Refresh(true)
    end)
    frame.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    frame.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- the category buttons (like Bagnon's sidebar): show only one kind of item
    frame.cats = {}
    local prevCat
    -- plain text tabs with an underline under the chosen one (no chunky buttons)
    local function PaintTabs()
        for _, t in ipairs(frame.cats) do
            local on = t.key == (catFilter or "all")
            t.label:SetTextColor(on and 1 or 0.65, on and 0.82 or 0.65, on and 0.2 or 0.7)
            t.line:SetShown(on)
        end
    end
    for _, c in ipairs(CATS) do
        local b = CreateFrame("Button", nil, frame)
        b.key = c.key
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.label:SetPoint("CENTER")
        b.label:SetText(c.text)
        b:SetSize(b.label:GetStringWidth() + 4, 16)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(1, 0.82, 0.2, 0.9)
        b.line:SetHeight(1)
        b.line:SetPoint("BOTTOMLEFT", 0, 0)
        b.line:SetPoint("BOTTOMRIGHT", 0, 0)
        b:SetScript("OnClick", function()
            catFilter = (c.key == "all") and nil or c.key
            PaintTabs()
            Refresh(true)
        end)
        b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", PaintTabs)
        if prevCat then b:SetPoint("LEFT", prevCat, "RIGHT", 10, 0) else b:SetPoint("TOPLEFT", 12, -54) end
        frame.cats[#frame.cats + 1] = b
        prevCat = b
    end
    PaintTabs()

    -- one small button per bag: click to hide that bag's items (like Bagnon's bag toggle)
    frame.bagBtns = {}
    for i, bag in ipairs(BagList()) do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(18, 18)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.bag = bag
        b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 100 + (i - 1) * 20, 6)
        b:SetScript("OnClick", function(self)
            local h = DB().bagsHidden or {}
            h[self.bag] = (not h[self.bag]) or nil
            DB().bagsHidden = h
            layoutNeeded = true
            Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.bag == 0 and "Backpack" or ("Bag " .. self.bag))
            GameTooltip:AddLine("Click to show or hide what is in it", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.bagBtns[#frame.bagBtns + 1] = b
    end

    -- the items live in a scroll frame so a full bag never makes a giant window (mouse wheel to scroll)
    frame.scroll = CreateFrame("ScrollFrame", nil, frame)
    frame.scroll:SetPoint("TOPLEFT", 10, -76)
    frame.scroll:EnableMouseWheel(true)
    frame.body = CreateFrame("Frame", nil, frame.scroll)
    frame.body:SetSize(10, 10)
    frame.scroll:SetScrollChild(frame.body)
    frame.thumb = frame.scroll:CreateTexture(nil, "OVERLAY")
    frame.thumb:SetColorTexture(0.7, 0.7, 0.8, 0.5)
    frame.thumb:SetWidth(4)
    frame.thumb:Hide()
    local function ScrollMax() return math.max(0, frame.body:GetHeight() - frame.scroll:GetHeight()) end
    frame.UpdateThumb = function()
        local sc = frame.scroll
        local max = ScrollMax()
        if max <= 0 then frame.thumb:Hide(); return end
        local h = sc:GetHeight()
        local th = math.max(20, h * h / (h + max))
        frame.thumb:ClearAllPoints()
        frame.thumb:SetHeight(th)
        frame.thumb:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -(h - th) * (sc:GetVerticalScroll() / max))
        frame.thumb:Show()
    end
    frame.scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = math.max(0, math.min(ScrollMax(), self:GetVerticalScroll() - delta * (SZ + GAP) * 1.5))
        self:SetVerticalScroll(v)
        frame.UpdateThumb()
    end)

    frame.free = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.money = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    return frame
end

-- built once; if building fails the real error is kept and shown every time (so it is never half a window)
local buildError
local function Build()
    if frame then
        if frame.flBuilt then return frame end
        error(buildError or "the bag window could not be built", 0)
    end
    local ok, err = pcall(BuildNow)
    if not ok then
        buildError = tostring(err)
        error(buildError, 0)
    end
    frame.flBuilt = true
    return frame
end

--------------------------------------------------------------------------------
-- Item buttons (real, secure ones for what I am carrying)
--------------------------------------------------------------------------------
local function NewItemButton(parent)
    btnCount = btnCount + 1
    local ok, b = pcall(CreateFrame, "ItemButton", "ForeverLazyBagBtn" .. GN .. "x" .. btnCount, parent, "ContainerFrameItemButtonTemplate")
    if not ok or not b then
        ok, b = pcall(CreateFrame, "Button", "ForeverLazyBagBtn" .. GN .. "x" .. btnCount, parent, "ContainerFrameItemButtonTemplate")
    end
    if not ok or not b then return nil end
    b:SetSize(SZ, SZ)
    -- the game's own item button draws its own quality border, new-item glow and overlays; we draw ours, so hide those
    local name = b:GetName()
    for _, key in ipairs({ "IconBorder", "IconOverlay", "IconOverlay2", "NewItemTexture", "BattlepayItemTexture", "ItemContextOverlay",
                           "JunkIcon", "UpgradeIcon", "flash", "Flash", "IconQuestTexture", "SearchOverlay", "ExtendedSlot" }) do
        local r = b[key] or (name and _G[name .. key])
        if r and r.Hide then
            r:Hide()
            if r.SetAlpha then r:SetAlpha(0) end
            -- the game shows them again when it updates an item; keep them hidden
            if hooksecurefunc and r.Show then pcall(hooksecurefunc, r, "Show", function(self) self:Hide() end) end
        end
    end
    if not addon.bagDebugDone then
        addon.bagDebugDone = true
        local found = {}
        for k, v in pairs(b) do
            if type(v) == "table" and v.GetObjectType and v:GetObjectType() == "Texture" and v:IsShown() then found[#found + 1] = tostring(k) end
        end
        if #found > 0 then Print("bag slot textures showing: " .. table.concat(found, ", ")) end
    end
    b.flBorder = b:CreateTexture(nil, "OVERLAY")
    b.flBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.flBorder:SetBlendMode("ADD")
    b.flBorder:SetPoint("CENTER")
    b.flBorder:SetSize(SZ * 1.7, SZ * 1.7)
    b.flBorder:Hide()
    b.flCool = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.flCool:SetAllPoints()
    return b
end

local function BagFrame(bag, parent)
    local bf = bagFrames[bag]
    if not bf then
        bf = CreateFrame("Frame", nil, parent)
        bf:SetAllPoints(parent)
        bf:SetID(bag)
        bagFrames[bag] = bf
        buttons[bag] = {}
    end
    return bf
end

local function QualityColor(q)
    local min = BorderMin()
    if q and min >= 0 and q >= min and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]
        return c.r, c.g, c.b
    end
end

local function Matches(info, bag, slot)
    if not CatMatch(info, bag, slot) then return false end
    if searchText == "" then return true end
    if not info then return false end
    local name = info.itemName
    if not name and info.hyperlink then name = GetItemInfo(info.hyperlink) end
    if not name and info.itemID then name = GetItemInfo(info.itemID) end
    return name and name:lower():find(searchText, 1, true) and true or false
end

local function UpdateButton(b, bag, slot)
    local info = SlotInfo(bag, slot)
    if SetItemButtonTexture then SetItemButtonTexture(b, info and info.iconFileID or nil) end
    if SetItemButtonCount then SetItemButtonCount(b, info and info.stackCount or 0) end
    if SetItemButtonDesaturated then SetItemButtonDesaturated(b, info and info.isLocked and true or false) end
    local r, g, bl = QualityColor(info and info.quality)
    local quest = false
    if info and C_Container and C_Container.GetContainerItemQuestInfo then
        local ok, qi = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
        quest = ok and type(qi) == "table" and (qi.isQuestItem or (qi.questID and qi.questID > 0)) and true or false
    end
    if quest and not (DB() and DB().bagsQuestBorder == false) then r, g, bl = 1, 0.82, 0 end
    if r then b.flBorder:SetVertexColor(r, g, bl, 0.9); b.flBorder:Show() else b.flBorder:Hide() end
    b:SetAlpha(Matches(info, bag, slot) and 1 or 0.25)
    -- item level on gear
    if not b.flLevel then
        b.flLevel = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.flLevel:SetPoint("TOPLEFT", 2, -2)
    end
    local lvlText = ""
    if info and info.hyperlink and not (DB() and DB().bagsItemLevel == false) then
        local classId = info.itemID and GetItemInfoInstant and select(6, GetItemInfoInstant(info.itemID))
        if classId == 2 or classId == 4 then
            local lvl = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(info.hyperlink)
            if lvl and lvl > 1 then lvlText = tostring(lvl) end
        end
    end
    b.flLevel:SetText(lvlText)
    if r then b.flLevel:SetTextColor(r, g, bl) else b.flLevel:SetTextColor(1, 1, 1) end
    if b.flCool and C_Container and C_Container.GetContainerItemCooldown then
        local ok, s, d = pcall(C_Container.GetContainerItemCooldown, bag, slot)
        if ok and s and d and d > 0 then b.flCool:SetCooldown(s, d) else b.flCool:Clear() end
    end
end

--------------------------------------------------------------------------------
-- Another character's items (just icons and counts: only what was saved)
--------------------------------------------------------------------------------
local function OffButton(i)
    local b = offButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame.body)
    b:SetSize(SZ, SZ)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.itemId)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if IsModifiedClick and IsModifiedClick("CHATLINK") then
            local _, link = GetItemInfo(self.itemId)
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end
    end)
    offButtons[i] = b
    return b
end

local function ShowOther()
    local root = addon.GetRoot and addon.GetRoot()
    local c = root and root.inv and root.inv[view.char]
    local items = c and c[view.place] or {}
    local list = {}
    for id, n in pairs(items) do
        if type(id) == "number" and type(n) == "number" and n > 0 then
            local name = GetItemInfo(id) or ""
            list[#list + 1] = { id = id, n = n, name = name:lower() }
        end
    end
    table.sort(list, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.id < b.id end)
    local cols = Cols()
    local shown = 0
    for i, e in ipairs(list) do
        local b = OffButton(i)
        b.itemId = e.id
        b.icon:SetTexture(GetItemIcon and GetItemIcon(e.id) or (select(10, GetItemInfo(e.id))))
        b.count:SetText(e.n > 1 and e.n or "")
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame.body, "TOPLEFT", ((i - 1) % cols) * (SZ + GAP), -math.floor((i - 1) / cols) * (SZ + GAP))
        local ok = searchText == "" or (e.name ~= "" and e.name:find(searchText, 1, true))
        b:SetAlpha(ok and 1 or 0.25)
        b:Show()
        shown = i
    end
    for i = shown + 1, #offButtons do offButtons[i]:Hide() end
    return math.max(shown, 1)
end

--------------------------------------------------------------------------------
-- Layout by category: labelled sections instead of bag order
--------------------------------------------------------------------------------
local warned = false
local SECTIONS = {}
for _, c in ipairs(CATS) do if c.key ~= "all" then SECTIONS[#SECTIONS + 1] = c end end
local headers = {}
local HideHeaders, LayoutCategories

CategoryOf = function(e)
    local info = e.info
    if info and (info.itemID == 6948 or info.itemName == "Hearthstone") then return "travel" end
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local ok, qi = pcall(C_Container.GetContainerItemQuestInfo, e.bag, e.slot)
        if ok and type(qi) == "table" and (qi.isQuestItem or (qi.questID and qi.questID > 0)) then return "quest" end
    end
    if info.quality == 0 then return "junk" end
    local classId, subId
    local ref = info.itemID or info.hyperlink
    if ref then
        local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if instant then
            local ok, _, _, _, _, _, c, s = pcall(instant, ref)
            if ok then classId, subId = c, s end
        end
        if not classId and GetItemInfo then
            local ok, _, _, _, _, _, _, _, _, _, _, _, c, s = pcall(GetItemInfo, ref)
            if ok then classId, subId = c, s end
        end
    end
    if not classId and not warned then
        warned = true
        Print("bag sections: could not read the item type of " .. tostring(info.hyperlink or info.itemID) .. " (id " .. tostring(info.itemID) .. ")")
    end
    if classId == 2 or classId == 4 then return "gear" end
    if classId == 0 then
        if subId == 5 then return "food" end
        if subId == 1 or subId == 2 or subId == 3 then return "potion" end
        if subId == 7 then return "bandage" end
        return "use"
    end
    if classId == 7 then return "trade" end
    if classId == 5 then return "reagent" end
    if classId == 9 then return "recipe" end
    if classId == 3 then return "gem" end
    if classId == 6 then return "ammo" end
    if classId == 1 or classId == 11 then return "bags" end
    if classId == 13 then return "key" end
    return "misc"
end

local function Header(i)
    local h = headers[i]
    if not h then
        h = frame.body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        headers[i] = h
    end
    return h
end
HideHeaders = function(from)
    for i = from + 1, #headers do headers[i]:Hide() end
end

-- places every slot button in its section, returns the height used (out of combat only)
LayoutCategories = function(entries, cols)
    local groups, free = {}, {}
    for _, e in ipairs(entries) do
        if e.info then
            local c = CategoryOf(e)
            groups[c] = groups[c] or {}
            table.insert(groups[c], e)
        else
            free[#free + 1] = e
        end
    end
    local function Name(e)
        local n = e.info.itemName or (e.info.hyperlink and GetItemInfo(e.info.hyperlink)) or ""
        return tostring(n):lower()
    end
    local function Place(e, n, y)
        local b = e.b
        b:SetSize(SZ, SZ)
        b.flBorder:SetSize(SZ * 1.7, SZ * 1.7)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame.body, "TOPLEFT", ((n - 1) % cols) * (SZ + GAP), -(y + math.floor((n - 1) / cols) * (SZ + GAP)))
        b:Show()
    end
    local y, hdr = 0, 0
    local function Section(label, list, limit)
        local count = math.min(#list, limit or #list)
        if count == 0 then return end
        hdr = hdr + 1
        local h = Header(hdr)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 2, -y)
        h:SetText(label)
        h:Show()
        y = y + 18
        for n = 1, count do Place(list[n], n, y) end
        for n = count + 1, #list do list[n].b:Hide() end
        y = y + math.ceil(count / cols) * (SZ + GAP) + 6
    end
    for _, s in ipairs(SECTIONS) do
        local g = groups[s.key]
        if g then
            table.sort(g, function(a, b)
                local qa, qb = a.info.quality or 0, b.info.quality or 0
                if qa ~= qb then return qa > qb end
                local na, nb = Name(a), Name(b)
                if na ~= nb then return na < nb end
                return (a.bag * 1000 + a.slot) < (b.bag * 1000 + b.slot)
            end)
            Section(s.text .. " (" .. #g .. ")", g)
        end
    end
    -- empty slots: one row is enough to drop things into
    Section("Free (" .. #free .. ")", free, cols)
    HideHeaders(hdr)
    return y
end

--------------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------------
Refresh = function(contentOnly)
    if not frame or not frame:IsShown() then dirty = true; return end
    local cols = Cols()
    local newSz = (DB() and DB().bagsItemSize) or 37
    if newSz ~= SZ then SZ = newSz; layoutNeeded = true end
    local mine = view.char == nil
    local hiddenBags = (DB() and DB().bagsHidden) or {}
    for _, bb in ipairs(frame.bagBtns) do
        local inv = ContainerIDToInventoryID and bb.bag > 0 and ContainerIDToInventoryID(bb.bag)
        local tex = inv and GetInventoryItemTexture("player", inv) or (bb.bag == 0 and "Interface\\Buttons\\Button-Backpack-Up") or nil
        bb.tex:SetTexture(tex)
        bb.tex:SetDesaturated(hiddenBags[bb.bag] and true or false)
        bb:SetAlpha(hiddenBags[bb.bag] and 0.5 or 1)
        bb:SetShown(mine and view.place == "bags" and tex ~= nil)
    end
    local who = mine and (UnitName("player") or "?") or nil
    if not mine then
        local root = addon.GetRoot()
        local c = root and root.inv and root.inv[view.char]
        who = c and (c.full or c.name) or view.char
    end
    frame.title:SetText(isBank and (who .. "'s bank") or (who .. (mine and "" or " (saved)")))
    local placeName = view.place == "bank" and "Bank" or view.place == "mail" and "Mail" or "Bags"
    frame.place:SetText(placeName)

    local slotsTotal, free = 0, 0
    if mine and (view.place == "bags" or (view.place == "bank" and atBank)) then
        -- live, secure buttons
        for i = 1, #offButtons do offButtons[i]:Hide() end
        local bags = {}
        for _, bag in ipairs(view.place == "bank" and BankList() or BagList()) do
            if not (view.place == "bags" and hiddenBags[bag]) then bags[#bags + 1] = bag end
        end
        local combat = InCombatLockdown()
        local canLayout = not combat
        -- hide the bag frames of the other place (out of combat only: they hold secure buttons)
        local want = {}
        for _, b in ipairs(bags) do want[b] = true end
        if canLayout then
            for bag, bf in pairs(bagFrames) do bf:SetShown(want[bag] and true or false) end
        end
        local byCat = ByCat()
        local idx = 0
        local entries = {}
        for _, bag in ipairs(bags) do
            local n = NumSlots(bag)
            local bf = BagFrame(bag, frame.body)
            for slot = 1, n do
                idx = idx + 1
                local b = buttons[bag][slot]
                if not b and canLayout then
                    b = NewItemButton(bf)
                    if b then
                        b:SetID(slot); buttons[bag][slot] = b
                        -- right-click uses the item in this exact bag slot (a secure action, so it works for sleeping bags, food, scrolls...)
                        if b.SetAttribute then
                            pcall(b.RegisterForClicks, b, "AnyUp")
                            b:SetAttribute("type2", "item")
                            b:SetAttribute("item2", bag .. " " .. slot)
                        end
                    end
                end
                local info = SlotInfo(bag, slot)
                if b then
                    entries[#entries + 1] = { b = b, bag = bag, slot = slot, info = info, idx = idx }
                    if canLayout and not byCat and (layoutNeeded or not b:IsShown()) then
                        b:SetSize(SZ, SZ)
                        b.flBorder:SetSize(SZ * 1.7, SZ * 1.7)
                        b:ClearAllPoints()
                        b:SetPoint("TOPLEFT", frame.body, "TOPLEFT", ((idx - 1) % cols) * (SZ + GAP), -math.floor((idx - 1) / cols) * (SZ + GAP))
                        b:Show()
                    end
                    UpdateButton(b, bag, slot)
                end
                slotsTotal = slotsTotal + 1
                if not info then free = free + 1 end
            end
            -- buttons left over from a bigger bag
            if canLayout then
                for slot = n + 1, #buttons[bag] do if buttons[bag][slot] then buttons[bag][slot]:Hide() end end
            end
        end
        -- a category tab only exists while you carry something of that kind
        local have = {}
        for _, e in ipairs(entries) do if e.info then local k = CategoryOf(e); have[k] = (have[k] or 0) + 1 end end
        if catFilter and not have[catFilter] then
            catFilter = nil
            for _, e in ipairs(entries) do UpdateButton(e.b, e.bag, e.slot) end
        end
        local prevTab
        for _, tb in ipairs(frame.cats) do
            local show = tb.key == "all" or have[tb.key]
            tb:SetShown(show and true or false)
            if show then
                tb:ClearAllPoints()
                if prevTab then tb:SetPoint("LEFT", prevTab, "RIGHT", 10, 0) else tb:SetPoint("TOPLEFT", 12, -54) end
                prevTab = tb
            end
            local on = tb.key == (catFilter or "all")
            tb.label:SetTextColor(on and 1 or 0.65, on and 0.82 or 0.65, on and 0.2 or 0.7)
            tb.line:SetShown(on)
        end
        local bodyHeight
        if byCat and canLayout then
            bodyHeight = LayoutCategories(entries, cols)
        else
            if not byCat then HideHeaders(0) end
            bodyHeight = math.ceil(math.max(idx, 1) / cols) * (SZ + GAP)
        end
        if canLayout then layoutNeeded = false end
        frame.body:SetSize(cols * (SZ + GAP), math.max(bodyHeight or 0, SZ))
        frame.free:SetText(string.format("%d / %d free", free, slotsTotal))
        frame.sort:Show()
    else
        -- another character, or the bank when I am not at it: the saved list
        if not InCombatLockdown() then for _, bf in pairs(bagFrames) do bf:Hide() end end
        local shown = ShowOther()
        local rows = math.ceil(shown / cols)
        frame.body:SetSize(cols * (SZ + GAP), rows * (SZ + GAP))
        local n = 0
        local root = addon.GetRoot()
        local c = root and root.inv and root.inv[mine and (addon.InventoryKey and addon.InventoryKey()) or view.char]
        frame.free:SetText(mine and "bank as last seen" or "as last saved")
        frame.sort:Hide()
    end

    if not InCombatLockdown() then
        -- at most about 60% of the screen tall; anything more scrolls
        local maxH = math.max(120, math.floor((UIParent:GetHeight() * 0.6) / (frame:GetScale() or 1)) - 104)
        local viewH = math.min(frame.body:GetHeight(), maxH)
        frame.scroll:SetSize(frame.body:GetWidth() + 6, viewH)
        frame:SetSize(math.max(frame.body:GetWidth() + 26, 360), viewH + 76 + 28)
        if frame.scroll:GetVerticalScroll() > math.max(0, frame.body:GetHeight() - viewH) then
            frame.scroll:SetVerticalScroll(math.max(0, frame.body:GetHeight() - viewH))
        end
        frame.UpdateThumb()
    end
    frame.free:ClearAllPoints()
    frame.free:SetPoint("BOTTOMLEFT", 10, 9)
    frame.money:ClearAllPoints()
    frame.money:SetPoint("BOTTOMRIGHT", -10, 9)
    local copper = GetMoney and GetMoney() or 0
    frame.money:SetText(mine and (GetCoinTextureString and GetCoinTextureString(copper) or tostring(copper)) or "")
    dirty = false
end

--------------------------------------------------------------------------------
-- Open, close, keys
--------------------------------------------------------------------------------
local function Open(place)
    Build()
    if place then view.place = place end
    layoutNeeded = true
    frame:Show()
    Refresh()
end
local function Close()
    if frame then
        if frame.panel then frame.panel:Hide() end
        frame:Hide()
    end
end
local function ToggleNow()
    Build()
    if frame:IsShown() then Close() else view.char = nil; if view.place ~= "bank" or not atBank then view.place = "bags" end; Open() end
end
return {
    Build = Build, Open = Open, Close = Close, ToggleNow = ToggleNow, Refresh = function(c) return Refresh(c) end,
    Frame = function() return frame end,
    View = function() return view end,
    NeedLayout = function() layoutNeeded = true end,
    SetDirty = function() dirty = true end,
    Searching = function() return searchText ~= "" end,
    Shown = function() return frame and frame:IsShown() end,
}
end   -- NewWindow

local main = NewWindow(1, false)
local bankWin = NewWindow(2, true)

-- any error is shown in chat (not everyone has Lua errors switched on)
local function Toggle()
    local ok, err = pcall(main.ToggleNow)
    if not ok then Print("the bag window hit an error: " .. tostring(err)) end
end
addon.ToggleBags = Toggle

local function BagnonRunning()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not isLoaded then return false end
    local ok, v = pcall(isLoaded, "Bagnon")
    return ok and v and true or false
end

local function Takeover()
    local db = DB()
    if not db then return false end
    if db.bagsReplace == true then return true end
    if db.bagsReplace == false then return false end
    return not BagnonRunning()
end

-- the game's own bag functions: when we are in charge they open our window instead
local orig = {}
local function Wrap(name, fn)
    local o = _G[name]
    if type(o) ~= "function" then return end
    orig[name] = o
    _G[name] = function(...)
        if Takeover() then
            local ok, err = pcall(fn, ...)
            if not ok then Print("the bag window hit an error: " .. tostring(err)) end
            return
        end
        return o(...)
    end
end
local wrapped = false
local function InitWrappers()
    wrapped = true
    Wrap("ToggleAllBags", function() Toggle() end)
    Wrap("ToggleBackpack", function() Toggle() end)
    Wrap("ToggleBag", function(id) if id == nil or id <= NUMBAGS + (NUM_REAGENTBAG_SLOTS or 0) then Toggle() end end)
    local function OpenMain() main.Build(); if not main.Shown() then main.View().char = nil; main.Open("bags") end end
    Wrap("OpenAllBags", OpenMain)
    Wrap("OpenBackpack", OpenMain)
    Wrap("OpenBag", OpenMain)
    Wrap("CloseAllBags", function() main.Close() end)
    Wrap("CloseBackpack", function() main.Close() end)
    Wrap("CloseBag", function() main.Close() end)
end
InitWrappers()

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local pending
local function Soon()
    main.SetDirty(); bankWin.SetDirty()
    if pending then return end
    pending = true
    C_Timer.After(0.05, function()
        pending = false
        if main.Shown() then main.Refresh() end
        if bankWin.Shown() then bankWin.Refresh() end
    end)
end

-- auto sort: a moment after the bags settle, tidy them (never in combat, never while carrying something, never while searching)
local sortPending, lastSort = false, 0
local function AutoSort()
    sortPending = false
    local db = DB()
    if not db or db.bagsAutoSort == false or ByCat() or not Takeover() then return end
    if InCombatLockdown() or (CursorHasItem and CursorHasItem()) or main.Searching() then return end
    if GetTime() - lastSort < 3 then return end
    local f = (C_Container and C_Container.SortBags) or SortBags
    if f then lastSort = GetTime(); pcall(f) end
end
local function QueueSort()
    if sortPending then return end
    local db = DB()
    if not db or db.bagsAutoSort == false then return end
    sortPending = true
    C_Timer.After(1.5, AutoSort)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY", "BANKFRAME_OPENED",
                     "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Print(Takeover() and "bag window is in charge of the bag keys (B)" or "bag window: Bagnon is running, so the game's bags are untouched (open ours with /lazy bags)")
    elseif event == "BANKFRAME_OPENED" then
        atBank = true
        if Takeover() then
            -- two windows side by side: my bags, and the bank to their left (so things can go from one to the other)
            main.Build(); bankWin.Build()
            main.View().char = nil; bankWin.View().char = nil
            -- the game's own bank window is hidden from view (it still has to be "open" for the bank to work)
            if BankFrame then BankFrame:SetAlpha(0) end
            main.Open("bags")
            local bf = bankWin.Frame()
            bf:ClearAllPoints()
            bf:SetPoint("BOTTOMRIGHT", main.Frame(), "BOTTOMLEFT", -12, 0)
            bankWin.Open("bank")
        end
    elseif event == "BANKFRAME_CLOSED" then
        atBank = false
        if BankFrame then BankFrame:SetAlpha(1) end
        bankWin.Close()
        if main.Shown() and main.View().place == "bank" and not main.View().char then main.View().place = "bags"; main.NeedLayout(); main.Refresh() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        main.NeedLayout(); bankWin.NeedLayout()
        Soon()
    elseif event == "BAG_UPDATE_DELAYED" then
        Soon()
        QueueSort()
    else
        Soon()
    end
end)

--------------------------------------------------------------------------------
-- /lazy bags
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "bags" then
        local a, b = (rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
        local db = DB()
        if a == "" then Toggle()
        elseif a == "replace" then
            if b == "on" then db.bagsReplace = true elseif b == "off" then db.bagsReplace = false else db.bagsReplace = nil end
            Print("bag window takes over the bag keys: " .. (Takeover() and "YES" or "no") .. (db.bagsReplace == nil and "  (automatic: only when Bagnon is not loaded)" or ""))
        elseif a == "cols" and tonumber(b) then
            db.bagsCols = math.max(4, math.min(24, tonumber(b)))
            main.NeedLayout(); bankWin.NeedLayout()
            if main.Frame() then main.Refresh() end
            if bankWin.Frame() then bankWin.Refresh() end
        elseif a == "scale" and tonumber(b) then
            db.bagsScale = math.max(0.5, math.min(2, tonumber(b))); main.Build(); main.Frame():SetScale(db.bagsScale)
            bankWin.Build(); bankWin.Frame():SetScale(db.bagsScale)
        elseif a == "reset" then
            db.bagsPos = nil; main.Build(); main.Frame():ClearAllPoints(); main.Frame():SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 110)
        else
            Print("/lazy bags  (open)   /lazy bags replace on|off   /lazy bags cols <n>   /lazy bags scale <n>   /lazy bags reset")
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["BagWindow.lua"] = true end end
