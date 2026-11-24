-- Gear advisor: shows which gear is an upgrade for my class and spec (the scoring is in Gear.lua).
--   a line in item tooltips ("Upgrade: +14 over ...")
--   a green ^ on upgrades in the bag window and at vendors
--   an optional small bar (off until /lazy gear bar on) with a button that equips an upgrade from my bags (it only equips when I click it)
--   optional: a chat note when I loot or buy an upgrade
--   /lazy gear on|off   /lazy gear bar on|off   /lazy gear note on|off
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On() local d = DB(); return d and d.gearAdvisor ~= false and addon.ModuleOn("gear") end
local function BarOn() local d = DB(); return d and d.gearAdvisor ~= false and d.gearBar == true and addon.ModuleOn("gear") end

--------------------------------------------------------------------------------
-- Is this item an upgrade? (cached until my gear or talents change)
--------------------------------------------------------------------------------
local cache = {}
local function ClearCache() cache = {} end

local MARGIN = 0.03           -- a gain under 3% of what I wear is not worth a flag
local MIN_GAIN = 2

-- returns { gain, pct, over, slotKey } or nil
function addon.GearUpgrade(link)
    if not link or not GetItemInfo then return nil end
    local hit = cache[link]
    if hit ~= nil then return hit or nil end
    local result = false
    local _, _, _, ilvl, minLevel, _, _, _, equipLoc = GetItemInfo(link)
    local slots = addon.GearSlots and equipLoc and addon.GearSlots[equipLoc]
    if slots and IsEquippableItem and IsEquippableItem(link) and (minLevel or 0) <= (UnitLevel("player") or 1) then
        local usable = true
        if IsUsableItem then local u = IsUsableItem(link); if u == false then usable = false end end
        if usable then
            local gain, _, over, worn = addon.GearGain(link, slots, equipLoc, ilvl)
            if gain and gain >= MIN_GAIN and gain >= (worn or 0) * MARGIN then
                result = { gain = gain, pct = (worn and worn > 0) and (gain / worn * 100) or nil, over = over, slotKey = slots[1] }
            end
        end
    end
    cache[link] = result
    return result or nil
end

--------------------------------------------------------------------------------
-- The tooltip line
--------------------------------------------------------------------------------
local function AddLine(tt, link)
    if not On() or not link or tt.flGear == link then return end
    local up = addon.GearUpgrade(link)
    if not up then return end
    tt.flGear = link
    local over = up.over and (GetItemInfo(up.over)) or nil
    local spec = addon.GearSpec and addon.GearSpec()
    local text = string.format("Upgrade%s: +%.0f%s%s", spec and (" for " .. spec.name) or "", up.gain, up.pct and string.format(" (%.0f%%)", up.pct) or "", over and (" over " .. over) or "")
    tt:AddLine(text, 0.2, 1, 0.2)
    if tt.Show then tt:Show() end
end

local function HookTooltips()
    local hooked = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
            local link = data and data.hyperlink
            if not link and tt.GetItem then local _, l = tt:GetItem(); link = l end
            if link then pcall(AddLine, tt, link) end
        end)
    end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tt = _G[name]
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) self.flGear = nil end)
            if not hooked then
                pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    if link then pcall(AddLine, self, link) end
                end)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- A green ^ on an item button (the bag window and vendor lists call this)
--------------------------------------------------------------------------------
function addon.GearMark(button, link)
    if not button then return end
    local show = On() and (DB().gearArrows ~= false) and link and addon.GearUpgrade(link) and true or false
    if show and not button.flGearUp then
        button.flGearUp = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
        button.flGearUp:SetPoint("TOPRIGHT", -1, -1)
        button.flGearUp:SetText("^")
        button.flGearUp:SetTextColor(0.2, 1, 0.2)
        local font, size = button.flGearUp:GetFont()
        if font then pcall(button.flGearUp.SetFont, button.flGearUp, font, size, "OUTLINE") end
    end
    if button.flGearUp then button.flGearUp:SetShown(show) end
end

-- vendor windows
local function MarkMerchant()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    local per = _G.MERCHANT_ITEMS_PER_PAGE or 10
    local page = MerchantFrame.page or 1
    for i = 1, per do
        local b = _G["MerchantItem" .. i .. "ItemButton"]
        if b then
            local link = GetMerchantItemLink and GetMerchantItemLink((page - 1) * per + i)
            addon.GearMark(b, link)
        end
    end
end

-- the standard bag windows (the Forever Lazy bag window marks its own buttons)
local function MarkItem(b, bag)
    if not (b and b.CreateFontString) then return end
    local slot = b.GetID and b:GetID()
    local bagId = (b.GetBagID and b:GetBagID()) or bag
    local link = bagId and slot and C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bagId, slot)
    addon.GearMark(b, link)
end

local function MarkBags()
    for i = 1, 13 do
        local f = _G["ContainerFrame" .. i]
        if f and f:IsShown() then
            if f.EnumerateValidItems then
                for _, b in f:EnumerateValidItems() do MarkItem(b) end
            else
                local bag = f.GetID and f:GetID()
                for j = 1, (f.size or 40) do MarkItem(_G["ContainerFrame" .. i .. "Item" .. j], bag) end
            end
        end
    end
    local c = _G.ContainerFrameCombinedBags
    if c and c:IsShown() and c.EnumerateValidItems then
        for _, b in c:EnumerateValidItems() do MarkItem(b) end
    end
end

local function MarkBagsSoon()
    pcall(MarkBags)
    if C_Timer and C_Timer.After then C_Timer.After(0.15, function() pcall(MarkBags) end) end
end

--------------------------------------------------------------------------------
-- The bag scan: upgrades I carry
--------------------------------------------------------------------------------
local function Scan()
    local list = {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return list end
    local best = {}
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            local up = link and addon.GearUpgrade(link)
            if up then
                local cur = best[up.slotKey]
                if not cur or up.gain > cur.gain then
                    best[up.slotKey] = { bag = bag, slot = slot, link = link, gain = up.gain, pct = up.pct, over = up.over }
                end
            end
        end
    end
    for _, e in pairs(best) do list[#list + 1] = e end
    table.sort(list, function(a, b) return a.gain > b.gain end)
    return list
end

--------------------------------------------------------------------------------
-- The equip bar (secure buttons: changed only out of combat; equipping needs my click)
--------------------------------------------------------------------------------
local MAX = 3
local holder, buttons = nil, {}
local waiting = false

local function Build()
    holder = CreateFrame("Frame", "ForeverLazyGearBar", UIParent)
    holder:SetSize(48, 48)
    holder:SetFrameStrata("MEDIUM")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    local pos = DB() and DB().gearBarPos
    if pos then holder:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 290) end
    for i = 1, MAX do
        local b = CreateFrame("Button", "ForeverLazyGearBtn" .. i, holder, "SecureActionButtonTemplate")
        b:SetSize(40, 40)
        b:SetPoint("BOTTOM", holder, "BOTTOM", (i - 2) * 46, 0)
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("type", "item")
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.edge = b:CreateTexture(nil, "BACKGROUND")
        b.edge:SetPoint("TOPLEFT", -2, 2)
        b.edge:SetPoint("BOTTOMRIGHT", 2, -2)
        b.edge:SetColorTexture(0.2, 1, 0.2, 1)
        b.up = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
        b.up:SetPoint("TOPRIGHT", -1, -1)
        b.up:SetText("^"); b.up:SetTextColor(0.2, 1, 0.2)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function() if IsShiftKeyDown() and not InCombatLockdown() then holder:StartMoving() end end)
        b:SetScript("OnDragStop", function()
            holder:StopMovingOrSizing()
            local p, _, rp, x, y = holder:GetPoint(1)
            DB().gearBarPos = { p, rp, x, y }
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self.bag and self.slot then pcall(GameTooltip.SetBagItem, GameTooltip, self.bag, self.slot) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("Upgrade +%.0f%s. Click to equip it. Shift-drag to move.", self.gain or 0,
                self.pct and string.format(" (%.0f%%)", self.pct) or ""), 0.2, 1, 0.2)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        buttons[i] = b
    end
end

local told = {}
local function Apply()
    if not holder then return end
    if InCombatLockdown() then waiting = true; return end
    waiting = false
    local list = (BarOn() and Scan()) or {}
    for i = 1, MAX do
        local b, e = buttons[i], list[i]
        if e then
            b.bag, b.slot, b.gain, b.pct = e.bag, e.slot, e.gain, e.pct
            b:SetAttribute("item", e.bag .. " " .. e.slot)
            local icon = GetItemIcon and GetItemIcon(e.link)
            b.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            b:Show()
        else
            b:Hide()
        end
    end
    -- a note in chat, once for each upgrade, when it is switched on
    if DB() and DB().gearNote == true then
        for _, e in ipairs(Scan()) do
            if not told[e.link] then
                told[e.link] = true
                local over = e.over and (GetItemInfo(e.over)) or nil
                Print(string.format(L("upgrade: %s%s (+%.0f%s)"), e.link, over and (" instead of " .. over) or "", e.gain, e.pct and string.format(", %.0f%%", e.pct) or ""))
            end
        end
    end
end

local function Refresh()
    ClearCache()
    if C_Timer then C_Timer.After(0.2, function() pcall(Apply) end) else pcall(Apply) end
    MarkMerchant()
    MarkBagsSoon()
    if addon.BagWindowRefresh then pcall(addon.BagWindowRefresh) end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
                     "CHARACTER_POINTS_CHANGED", "MERCHANT_SHOW", "ACTIVE_TALENT_GROUP_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not holder then pcall(Build) end
        pcall(HookTooltips)
        if _G.MerchantFrame_UpdateMerchantInfo then pcall(hooksecurefunc, "MerchantFrame_UpdateMerchantInfo", function() pcall(MarkMerchant) end) end
        for _, fn in ipairs({ "ContainerFrame_Update", "ContainerFrame_UpdateAll", "ContainerFrame_GenerateFrame", "OpenAllBags", "OpenBag", "ToggleBag", "ToggleAllBags", "ToggleBackpack" }) do
            if _G[fn] then pcall(hooksecurefunc, fn, MarkBagsSoon) end
        end
        for i = 1, 13 do
            local f = _G["ContainerFrame" .. i]
            if f and f.HookScript then pcall(f.HookScript, f, "OnShow", MarkBagsSoon) end
        end
        if _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags.HookScript then pcall(_G.ContainerFrameCombinedBags.HookScript, _G.ContainerFrameCombinedBags, "OnShow", MarkBagsSoon) end
        if C_Timer then C_Timer.After(3, Refresh) end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and not waiting then return end
    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP"
        or event == "CHARACTER_POINTS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        ClearCache()
    end
    pcall(Apply)
    if event == "MERCHANT_SHOW" then pcall(MarkMerchant) end
    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then MarkBagsSoon() end
end)

-- options and commands call this
addon.GearAdvisorRefresh = Refresh

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "gear" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        local which, val = a:match("^(%a+)%s+(%a+)$")
        local function Flag(v) if v == "on" then return true elseif v == "off" then return false end end
        if a == "on" or a == "off" then
            db.gearAdvisor = Flag(a) and nil or false
            Print(L("gear advisor: ") .. (db.gearAdvisor == false and "OFF" or "on")); Refresh(); return true
        elseif which == "bar" and Flag(val) ~= nil then
            db.gearBar = Flag(val) and true or nil
            Print(L("gear advisor bar: ") .. (db.gearBar == true and "on" or "OFF")); Refresh(); return true
        elseif which == "note" and Flag(val) ~= nil then
            db.gearNote = Flag(val) and true or nil
            Print(L("gear advisor chat note: ") .. (db.gearNote and "on" or "OFF")); return true
        elseif a == "why" then
            -- every piece of gear in the bags, and the reason it is or is not flagged
            local spec = addon.GearSpec and addon.GearSpec()
            local lines = { "Spec: " .. (spec and (spec.name .. " (" .. tostring(spec.kind) .. ")") or "?") .. "   gear advisor on: " .. tostring(On() and true or false), "" }
            local n = 0
            for bag = 0, 4 do
                for slot = 1, ((C_Container and C_Container.GetContainerNumSlots(bag)) or 0) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    local link = info and info.hyperlink
                    if link then
                        local _, _, _, ilvl, minLevel, _, _, _, loc = GetItemInfo(link)
                        local slots = loc and addon.GearSlots[loc]
                        if slots then
                            n = n + 1
                            local why
                            if IsEquippableItem and not IsEquippableItem(link) then why = "not equippable"
                            elseif (minLevel or 0) > (UnitLevel("player") or 1) then why = "needs level " .. tostring(minLevel)
                            elseif IsUsableItem and IsUsableItem(link) == false then why = "you cannot use it"
                            else
                                local gain, _, _, worn = addon.GearGain(link, slots, loc, ilvl)
                                local score = addon.GearScore(link, spec)
                                if not gain then why = "no comparison (a tank does not use two-handers)"
                                else why = string.format("score %s, wearing %s, gain %.1f (needs %.1f and at least %d)", score and string.format("%.1f", score) or "no stats", string.format("%.1f", worn or 0), gain, (worn or 0) * MARGIN, MIN_GAIN) end
                            end
                            lines[#lines + 1] = string.format("%s  [%s]: %s", GetItemInfo(link) or link, loc, why)
                        end
                    end
                end
            end
            if n == 0 then lines[#lines + 1] = "No gear in your bags." end
            addon.ReportWindow("Forever Lazy: gear check", lines)
            return true
        elseif a == "list" then
            local list = Scan()
            if #list == 0 then Print(L("gear: no upgrades in your bags")) end
            for _, e in ipairs(list) do
                local over = e.over and (GetItemInfo(e.over)) or nil
                Print(string.format(L("gear: %s +%.0f%s%s"), e.link, e.gain, e.pct and string.format(" (%.0f%%)", e.pct) or "", over and (" over " .. over) or ""))
            end
            return true
        end
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["GearAdvisor.lua"] = true end end
