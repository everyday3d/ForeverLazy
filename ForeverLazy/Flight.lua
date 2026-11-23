-- Flight timer: shows how long a flight path takes and how much is left.
-- The game does not tell addons the length of a flight, so the addon learns it:
-- the first time you fly a route it measures the ride, after that it can count down
-- (and show the time on the flight map when you hover a destination).
--   /lazy flight   lists the flight times learned so far
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

local frame
local ride      -- { start, origin, dest, lostAt }
local pending   -- { origin, dest, t }: set when I click a destination on the flight map

local function Key(o, d) return (o or "?") .. "->" .. (d or "?") end
local function Short(name) return name and (name:match("^[^,]+") or name) or "?" end
local function Fmt(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function Times()
    local db = DB()
    db.flightTimes = db.flightTimes or {}
    return db.flightTimes
end

local function CurrentNode()
    if not (NumTaxiNodes and TaxiNodeGetType and TaxiNodeName) then return nil end
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
    end
end

-- remember where I clicked to fly
if hooksecurefunc and _G.TakeTaxiNode then
    pcall(hooksecurefunc, "TakeTaxiNode", function(index)
        pending = { origin = CurrentNode(), dest = TaxiNodeName and TaxiNodeName(index), t = GetTime() }
    end)
end

-- show the known flight time when hovering a destination on the flight map
if hooksecurefunc and _G.TaxiNodeOnButtonEnter then
    pcall(hooksecurefunc, "TaxiNodeOnButtonEnter", function(button)
        local ok = pcall(function()
            local db = DB()
            if not db or db.flightTimer == false then return end
            local dest = TaxiNodeName(button:GetID())
            local rec = Times()[Key(CurrentNode(), dest)]
            if rec and GameTooltip and GameTooltip:IsShown() then
                GameTooltip:AddLine("Flight time: " .. Fmt(rec.avg), 1, 1, 1)
                GameTooltip:Show()
            end
        end)
    end)
end

local function MakeFrame()
    local f = CreateFrame("Frame", "ForeverLazy_FlightTimer", UIParent)
    f:SetSize(260, 44)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not DB().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        DB().pos.flight = { point = point, x = x, y = y }
    end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -6)
    f.time = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.time:SetPoint("BOTTOM", 0, 6)
    f:Hide()
    return f
end

local function Place()
    if not frame then return end
    local p = DB().pos.flight or { point = "TOP", x = 0, y = -110 }
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    frame:SetScale(DB().scale or 1)
end

local function Finish()
    local r = ride
    ride = nil
    if frame then frame:Hide() end
    if not (r and r.origin and r.dest) then return end
    local dur = GetTime() - r.start
    if dur < 8 then return end
    local t = Times()
    local key = Key(r.origin, r.dest)
    local rec = t[key]
    if rec then
        if dur < rec.avg * 0.8 then return end        -- cut short, do not learn from it
        rec.avg = (rec.avg * rec.n + dur) / (rec.n + 1)
        rec.n = math.min(rec.n + 1, 5)
    else
        t[key] = { avg = dur, n = 1 }
        Print(string.format(L("learned the flight time %s to %s: %s"), Short(r.origin), Short(r.dest), Fmt(dur)))
    end
end

local timer = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    timer = timer + dt
    if timer < 0.25 then return end
    timer = 0
    local db = DB()
    if not db then return end
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")

    if onTaxi then
        if not ride then
            local p = pending and (GetTime() - pending.t < 90) and pending or nil
            ride = { start = GetTime(), origin = p and p.origin, dest = p and p.dest }
        end
        ride.lostAt = nil
        if db.flightTimer == false or not addon.ModuleOn("flight") then return end
        if not frame then frame = MakeFrame(); Place() end
        local elapsed = GetTime() - ride.start
        local rec = ride.origin and ride.dest and Times()[Key(ride.origin, ride.dest)]
        frame.title:SetText(ride.dest and ("Flying to " .. Short(ride.dest)) or "Flying")
        if rec then
            local left = rec.avg - elapsed
            frame.time:SetText(left > 1 and (Fmt(left) .. " left") or "Arriving...")
        else
            frame.time:SetText(Fmt(elapsed) .. " (learning this route)")
        end
        frame:Show()
    elseif ride then
        -- a short gap between two legs of a flight is not the end
        ride.lostAt = ride.lostAt or GetTime()
        if GetTime() - ride.lostAt > 3 then Finish() end
    end
end)

local origLayout = addon.ApplyLayout
function addon:ApplyLayout()
    origLayout(self)
    Place()
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd == "flighttimes" or cmd == "flighttime" then
        local list = {}
        for k, v in pairs(Times()) do list[#list + 1] = { k = k, v = v } end
        table.sort(list, function(a, b) return a.k < b.k end)
        if #list == 0 then
            Print(L("no flight times learned yet. They are measured the first time you fly each route."))
        else
            Print(#list .. L(" flight times learned:"))
            for _, e in ipairs(list) do
                local o, d = e.k:match("^(.-)%->(.*)$")
                Print(string.format("  %s to %s: %s", Short(o), Short(d), Fmt(e.v.avg)))
            end
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Flight.lua"] = true end end
