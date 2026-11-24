-- Version note: when someone in your group or guild runs a newer Forever Lazy, you get one line and a What's new button.
-- Only the version number travels, as a hidden addon message to your group.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local PREFIX = "FLVER"

local function MyVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON, "Version") or "0"
end

-- 1 when a is newer than b, -1 when older, 0 when the same
local function Compare(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

-- A small button at the top of the screen while a newer version is known: click for the what's new window (with where to get it),
-- right-click to hide it until the next login.
local banner
local function ShowBanner()
    if not banner then
        banner = CreateFrame("Button", "ForeverLazy_UpdateBanner", UIParent, "UIPanelButtonTemplate")
        banner:SetSize(230, 24)
        banner:SetPoint("TOP", UIParent, "TOP", 0, -70)
        banner:SetFrameStrata("HIGH")
        banner:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        banner:SetScript("OnClick", function(self, button)
            if button == "RightButton" then self:Hide() else addon.ShowWhatsNew() end
        end)
        banner:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Forever Lazy " .. tostring(addon.newerVersion) .. " is out")
            GameTooltip:AddLine("You have " .. MyVersion() .. ". Click for what's new and where to get it. Right-click to hide.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        banner:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    banner:SetText("Forever Lazy " .. tostring(addon.newerVersion) .. " out - What's new")
    banner:Show()
end

local warned = {}
function addon:OnVersion(prefix, message, distribution, sender)
    if prefix ~= PREFIX or type(message) ~= "string" or #message > 20 then return end
    local who = (sender or "?"):match("^([^%-]+)") or sender
    if who == UnitName("player") then return end
    if Compare(message, MyVersion()) > 0 then
        if not addon.newerVersion or Compare(message, addon.newerVersion) > 0 then
            addon.newerVersion, addon.newerFrom = message, who
            pcall(ShowBanner)
        end
        if not warned[message] then
            warned[message] = true
            Print(string.format(L("%s runs a newer Forever Lazy (%s, you have %s). Update it on CurseForge: curseforge.com/wow/addons/foreverlazy (or in the CurseForge app). /lazy new shows what changed."), who, message, MyVersion()))
        end
    end
end
addon:RegisterComm(PREFIX, "OnVersion")

-- say my version to the group, and to the guild once after logging in, so people on older versions find out
local pending
local function Announce()
    pending = false
    local ch = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY")
    if ch then addon:SendCommMessage(PREFIX, MyVersion(), ch) end
end
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function()
    if pending or not C_Timer then return end
    pending = true
    C_Timer.After(8, Announce)
end)
local login = CreateFrame("Frame")
pcall(login.RegisterEvent, login, "PLAYER_ENTERING_WORLD")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if not C_Timer then return end
    C_Timer.After(15, function()
        if IsInGuild and IsInGuild() then pcall(addon.SendCommMessage, addon, PREFIX, MyVersion(), "GUILD") end
        Announce()
    end)
end)
-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Version.lua"] = true end end
