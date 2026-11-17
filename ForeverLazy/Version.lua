-- Version note: when someone in your group runs a newer Forever Lazy, you get one line saying so.
-- Only the version number travels, as a hidden addon message to your group.
local ADDON, ns = ...
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

local warned = {}
function addon:OnVersion(prefix, message, distribution, sender)
    if prefix ~= PREFIX or type(message) ~= "string" or #message > 20 then return end
    local who = (sender or "?"):match("^([^%-]+)") or sender
    if who == UnitName("player") then return end
    if Compare(message, MyVersion()) > 0 and not warned[message] then
        warned[message] = true
        Print(string.format("%s runs a newer Forever Lazy (%s, you have %s). The latest is on the GitHub releases page.", who, message, MyVersion()))
    end
end
addon:RegisterComm(PREFIX, "OnVersion")

local pending
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function()
    if pending or not C_Timer then return end
    pending = true
    C_Timer.After(8, function()
        pending = false
        local ch = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY")
        if ch then addon:SendCommMessage(PREFIX, MyVersion(), ch) end
    end)
end)

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Version.lua"] = true end end
