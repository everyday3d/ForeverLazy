-- Items I do not want to lose to a vendor (my sleeping bag, for one).
--   /lazy keep                       what is protected
--   /lazy keep <item link or name>   protect it (shift-click the item into the command to paste its link)
--   /lazy keep remove <item>         let it go again
-- The game does not let an addon stop a sale, so this does three things around it:
--   the item's tooltip says it is protected,
--   opening a vendor lists the protected items in my bags,
--   and if one is sold anyway it is bought straight back from the vendor's buyback list.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

local DEFAULTS = { "cozy sleeping bag" }

local function Keep()
    local db = DB()
    if not db then return {} end
    if not db.keep then
        db.keep = {}
        for _, n in ipairs(DEFAULTS) do db.keep[n] = true end
    end
    return db.keep
end

local function On() return DB() and DB().keepOn ~= false end

local function NameOf(text)
    if not text or text == "" then return nil end
    local linkName = text:match("|h%[(.-)%]|h")
    return ((linkName or text):lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

local function IsKept(name)
    return name and Keep()[name:lower()] and true or false
end
addon.IsKeptItem = function(name) return On() and IsKept(name) end

--------------------------------------------------------------------------------
-- Tooltip line
--------------------------------------------------------------------------------
local function Mark(tt, name)
    if not (On() and name and IsKept(name)) then return end
    tt:AddLine(" ")
    tt:AddLine(L("|TInterface\\DialogFrame\\DialogAlertIcon:20:20|t |cffff2020DO NOT SELL|r |TInterface\\DialogFrame\\DialogAlertIcon:20:20|t"), 1, 1, 1)
    tt:AddLine(L("Protected by Forever Lazy: a vendor sale gets bought back"), 1, 0.8, 0.2, true)
    if tt.Show then tt:Show() end
end

local function Hook()
    local hooked = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
            local id = data and data.id
            if id then
                local name = GetItemInfo and GetItemInfo(id)
                Mark(tt, name)
            end
        end)
    end
    if not hooked then
        for _, nm in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
            local tt = _G[nm]
            if tt and tt.HookScript then
                pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                    local name = self:GetItem()
                    Mark(self, name)
                end)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- At the vendor
--------------------------------------------------------------------------------
local function BagItems()
    local out = {}
    for bag = 0, 4 do
        local n = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag))
            or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            local link
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                link = info and info.hyperlink
            elseif GetContainerItemLink then
                link = GetContainerItemLink(bag, slot)
            end
            if link then
                local name = GetItemInfo and GetItemInfo(link)
                if name and IsKept(name) then out[#out + 1] = name end
            end
        end
    end
    return out
end

-- a big message in the middle of the screen that fades after a few seconds
local alertFrame
local function Alert(text, r, g, b)
    if not alertFrame then
        local f = CreateFrame("Frame", "ForeverLazy_ProtectAlert", UIParent)
        f:SetSize(700, 60)
        f:SetPoint("TOP", UIParent, "TOP", 0, -180)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.text:SetPoint("CENTER")
        f.text:SetShadowOffset(2, -2)
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -4)
        f.sub:SetTextColor(1, 1, 1)
        f.sub:SetShadowOffset(1, -1)
        f:Hide()
        alertFrame = f
    end
    local f = alertFrame
    f.shown = GetTime()
    f.text:SetText(text)
    f.text:SetTextColor(r or 1, g or 0.2, b or 0.2)
    f.sub:SetText("")
    f:SetAlpha(1)
    f:Show()
    f:SetScript("OnUpdate", function(self)
        local age = GetTime() - self.shown
        if age > 5 then self:Hide(); self:SetScript("OnUpdate", nil)
        elseif age > 3.5 then self:SetAlpha(1 - (age - 3.5) / 1.5) end
    end)
    return f
end

local tried = {}     -- buyback slot + name -> time of my last try, so one failure does not loop

local function CheckBuyback()
    if not On() or not (GetNumBuybackItems and GetBuybackItemInfo and BuybackItem) then return end
    for i = 1, GetNumBuybackItems() do
        local name = GetBuybackItemInfo(i)
        if name and IsKept(name) then
            local key = i .. ":" .. name
            if not tried[key] or GetTime() - tried[key] > 3 then
                tried[key] = GetTime()
                local ok = pcall(BuybackItem, i)
                if ok then
                    Print(L("|cffff6060") .. name .. L(" was sold, but it is protected: buying it back|r"))
                    local f = Alert("PROTECTED ITEM: " .. name, 1, 0.3, 0.2)
                    f.sub:SetText(L("It was sold by mistake. Buying it back now."))
                else
                    Print(L("|cffff6060") .. name .. L(" was sold and I could not buy it back. Do it from the Buyback tab.|r"))
                    local f = Alert("YOU SOLD " .. name .. "!", 1, 0.1, 0.1)
                    f.sub:SetText(L("It is protected. Buy it back from the Buyback tab."))
                end
                return           -- the list shifts after a buyback; the next update checks the rest
            end
        end
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }) do pcall(ev.RegisterEvent, ev, e) end
local merchantOpen = false
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        pcall(Hook)
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        tried = {}
        if not On() then return end
        local items = BagItems()
        if #items > 0 then
            local seen, list = {}, {}
            for _, n in ipairs(items) do if not seen[n] then seen[n] = true; list[#list + 1] = n end end
            Print(L("protected, don't sell: ") .. table.concat(list, ", "))
        end
    elseif event == "MERCHANT_UPDATE" then
        if merchantOpen then CheckBuyback() end
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
    end
end)

--------------------------------------------------------------------------------
-- /lazy keep
--------------------------------------------------------------------------------
local function List()
    local names = {}
    for n in pairs(Keep()) do names[#names + 1] = n end
    table.sort(names)
    if #names == 0 then
        Print(L("nothing is protected. /lazy keep <item> protects one (shift-click it into the command)"))
        return
    end
    Print(L("protected from vendors (") .. #names .. "): " .. table.concat(names, ", "))
    Print(L("/lazy keep <item> adds, /lazy keep remove <item> removes"))
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "keep" then
        local text = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local verb, more = text:match("^(%a+)%s+(.+)$")
        if text == "" then
            List()
        elseif verb and (verb:lower() == "remove" or verb:lower() == "delete" or verb:lower() == "off") then
            local n = NameOf(more)
            if n and Keep()[n] then Keep()[n] = nil; Print(L("no longer protected: ") .. n) else Print(L("that was not on the list")) end
        elseif text:lower() == "on" or text:lower() == "off" then
            DB().keepOn = (text:lower() == "on")
            Print(L("item protection ") .. (DB().keepOn and "on" or "off"))
        else
            local n = NameOf(text)
            if n then Keep()[n] = true; Print(L("protected: ") .. n) end
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Protect.lua"] = true end end
