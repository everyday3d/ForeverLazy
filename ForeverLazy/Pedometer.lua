-- Pedometer: how far you have walked. It adds up the distance you cover on foot (not mounted, not on a flight, not teleported),
-- for this session, today, this level, and in total, and remembers which zones you walk the most.
--   /lazy steps          the numbers in a window        /lazy steps reset     start again from zero
--   /lazy steps on|off   count the distance (on by default)     /lazy steps show|hide   a small readout on the screen
-- The unit follows the distance setting in the options (yards, meters or steps).
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local hbd = api and api.hbd
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On() local d = DB(); return d and d.pedometer ~= false end

local STRIDE_M = 0.75                 -- a step, in meters (db.pedoStride sets it)
local MAX_JUMP = 30                   -- yards in one reading: more than that is a teleport, a loading screen or a fast ride
local TICK = 0.5

local sessionYards = 0
local lx, ly, linst

local function Data()
    local db = DB()
    if not db then return nil end
    local p = db.pedo
    if type(p) ~= "table" then
        p = { total = 0, level = 0, lastLevel = 0, levelNo = UnitLevel and UnitLevel() or 1, days = {}, zones = {} }
        db.pedo = p
    end
    p.days = p.days or {}
    p.zones = p.zones or {}
    return p
end

local function Today() return date and date("%Y-%m-%d") or "today" end

-- distance in the unit of the options
local function Commas(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
function addon.PedometerFormat(yards)
    yards = yards or 0
    local db = DB()
    local unit = db and db.units or "yd"
    local meters = yards * 0.9144
    if unit == "m" then
        if meters >= 1000 then return string.format("%.2f km", meters / 1000) end
        return Commas(meters) .. " m"
    elseif unit == "steps" then
        local stride = tonumber(db and db.pedoStride) or STRIDE_M
        return Commas(meters / stride) .. " " .. L("steps")
    end
    if yards >= 1760 then return string.format("%.2f miles", yards / 1760) end
    return Commas(yards) .. " yd"
end

local function Add(d, zone)
    local p = Data()
    if not p then return end
    sessionYards = sessionYards + d
    p.total = (p.total or 0) + d
    p.level = (p.level or 0) + d
    local day = Today()
    p.days[day] = (p.days[day] or 0) + d
    if zone then p.zones[zone] = (p.zones[zone] or 0) + d end
end

-- one reading of where I am. onFoot: not mounted, not on a flight. Returns the yards that were counted.
function addon.PedometerFeed(x, y, inst, onFoot, zone)
    if not (x and y) then lx = nil; return 0 end
    if not lx or linst ~= inst then lx, ly, linst = x, y, inst; return 0 end
    local d = math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2)
    lx, ly = x, y
    if not onFoot or d < 0.05 or d > MAX_JUMP then return 0 end
    Add(d, zone)
    return d
end

local function OnFoot()
    local db = DB()
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    if UnitInVehicle and UnitInVehicle("player") then return false end
    if db and db.pedoMounted == true then return true end
    if IsMounted and IsMounted() then return false end
    if IsFlying and IsFlying() then return false end
    return true
end

--------------------------------------------------------------------------------
-- The report
--------------------------------------------------------------------------------
local function ZoneName(id)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or ("map " .. tostring(id))
end

function addon.PedometerReport()
    local p = Data()
    if not p then return end
    local F = addon.PedometerFormat
    local lines = {}
    local function Add2(s) lines[#lines + 1] = s end
    Add2(string.format("%-18s %s", L("This session:"), F(sessionYards)))
    Add2(string.format("%-18s %s", L("Today:"), F(p.days[Today()] or 0)))
    Add2(string.format("%-18s %s   (%s %s)", L("This level:"), F(p.level or 0), L("level"), tostring(p.levelNo or "?")))
    if (p.lastLevel or 0) > 0 then Add2(string.format("%-18s %s", L("The level before:"), F(p.lastLevel))) end
    Add2(string.format("%-18s %s", L("In total:"), F(p.total or 0)))
    -- the last days
    local keys = {}
    for k in pairs(p.days) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return a > b end)
    if #keys > 0 then
        Add2("")
        Add2(L("The last days:"))
        for i = 1, math.min(7, #keys) do Add2(string.format("   %s   %s", keys[i], F(p.days[keys[i]]))) end
    end
    -- the zones walked most
    local zs = {}
    for id, yards in pairs(p.zones) do zs[#zs + 1] = { id = id, yards = yards } end
    table.sort(zs, function(a, b) return a.yards > b.yards end)
    if #zs > 0 then
        Add2("")
        Add2(L("Where you walk the most:"))
        for i = 1, math.min(5, #zs) do Add2(string.format("   %-28s %s", ZoneName(zs[i].id), F(zs[i].yards))) end
    end
    Add2("")
    Add2(L("It counts the distance you cover on foot. Mounted travel, flights and teleports are left out. /lazy steps reset starts again."))
    addon.ReportWindow(L("Forever Lazy: distance walked"), lines)
end

--------------------------------------------------------------------------------
-- The small readout
--------------------------------------------------------------------------------
local box
local function MakeBox()
    local f = CreateFrame("Frame", "ForeverLazy_Pedometer", UIParent)
    f:SetSize(170, 22)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() if not DB().locked then f:StartMoving() end end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        DB().pos = DB().pos or {}
        DB().pos.pedo = { point = point, x = x, y = y }
    end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.45)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("CENTER")
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local p = Data()
        local F = addon.PedometerFormat
        GameTooltip:AddLine(L("Distance walked"), 1, 0.82, 0)
        GameTooltip:AddDoubleLine(L("This session:"), F(sessionYards), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L("Today:"), F(p and p.days[Today()] or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L("This level:"), F(p and p.level or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L("In total:"), F(p and p.total or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine(L("Click for all the numbers. Drag to move."), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" and not f.moved then addon.PedometerReport() end end)
    local pos = DB() and DB().pos and DB().pos.pedo or { point = "TOPLEFT", x = 20, y = -200 }
    f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    f:Hide()
    return f
end

local function UpdateBox()
    local db = DB()
    if not (db and db.pedoShow == true and On()) then
        if box then box:Hide() end
        return
    end
    box = box or MakeBox()
    local p = Data()
    box.text:SetText(L("Today:") .. " " .. addon.PedometerFormat(p and p.days[Today()] or 0))
    box:Show()
end

--------------------------------------------------------------------------------
-- Driving it
--------------------------------------------------------------------------------
local acc = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < TICK then return end
    acc = 0
    if not On() then lx = nil; return end
    local x, y, inst = hbd and hbd:GetPlayerWorldPosition()
    local zone = hbd and hbd:GetPlayerZone()
    addon.PedometerFeed(x, y, inst, OnFoot(), zone)
    UpdateBox()
end)

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, newLevel)
    local p = Data()
    if event == "PLAYER_LOGIN" and p then
        -- keep the last 60 days
        local keys = {}
        for k in pairs(p.days) do keys[#keys + 1] = k end
        table.sort(keys)
        while #keys > 60 do p.days[table.remove(keys, 1)] = nil end
        local lvl = UnitLevel and UnitLevel() or 1
        if p.levelNo ~= lvl then p.levelNo = lvl; p.level = 0 end
    elseif event == "PLAYER_ENTERING_WORLD" then
        lx = nil                                           -- a loading screen is not a walk
    elseif event == "PLAYER_LEVEL_UP" and p then
        p.lastLevel = p.level or 0
        p.level = 0
        p.levelNo = tonumber(newLevel) or ((p.levelNo or 1) + 1)
    end
end)

addon.PedometerRefresh = UpdateBox

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "steps" or (cmd or ""):lower() == "pedometer" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "reset" then
            db.pedo = nil
            sessionYards = 0
            Print(L("pedometer: started again from zero"))
        elseif a == "off" then db.pedometer = false; Print(L("pedometer: off, the distance is not counted"))
        elseif a == "on" then db.pedometer = nil; Print(L("pedometer: on, it counts the distance you walk"))
        elseif a == "show" then db.pedoShow = true; Print(L("pedometer: readout on the screen (drag it to move it)")); UpdateBox()
        elseif a == "hide" then db.pedoShow = nil; Print(L("pedometer: readout hidden")); UpdateBox()
        else addon.PedometerReport() end
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Pedometer.lua"] = true end end
