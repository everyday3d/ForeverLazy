-- Autopilot: the levelling route that keeps going by itself, like a levelling guide.
--   after a quest stop, if bags are almost full or gear is damaged, the next step is the vendor; if my trainer has something
--   new for me, the next step is the trainer
--   when the zone has nothing left worth doing, the next step is the next zone on my journey: the trip there (flight, boat,
--   tram) and then a plan for that zone as soon as I arrive
-- It never interrupts a quest I am in the middle of, and never acts in a dungeon, in combat, dead or on a flight.
--   /lazy autopilot on|off
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local lastService = {}        -- label -> when I last sent myself there
local lastMoveOn = 0
local lastNothing = 0

local function Busy()
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
    if UnitOnTaxi and UnitOnTaxi("player") then return true end
    if InCombatLockdown and InCombatLockdown() then return true end
    if IsInInstance then
        local inside, kind = IsInInstance()
        if inside and (kind == "party" or kind == "raid") then return true end
    end
    if addon.GoStatus and addon.GoStatus() then return true end          -- a trip is under way
    return false
end

local function PlanStops()
    local n = 0
    for _, w in ipairs(DB().waypoints or {}) do
        if w.label and not w.go and not w.gather and not w.guard and not w.lazy then n = n + 1 end
    end
    return n
end

local function FirstStop() return DB().waypoints and DB().waypoints[1] end

local function Log(text)
    if addon.PlanLog then addon.PlanLog("autopilot", text) end
end

-- the next zone on my journey that is not this one
local function NextZoneSegment()
    if not addon.JourneySegments then return nil end
    local level = UnitLevel("player") or 1
    local here = (GetRealZoneText and GetRealZoneText() or ""):lower()
    for _, s in ipairs(addon.JourneySegments() or {}) do
        if s.map and level < s.to and (s.zone or ""):lower() ~= here then return s end
    end
end

local function Tick()
    local db = DB()
    if not (db and db.autopilot) or db.planPaused or Busy() then return end
    if not api.QuestieReady or not api.QuestieReady() then return end
    local now = GetTime()
    local first = FirstStop()

    -- a service stop or a trip leg is already the next thing: let it finish
    if first and (first.lazy or first.go) then return end

    -- 1. services come between quest stops, never in the middle of one
    local midQuest = first and first.quests and addon.StopHasOpenObjectives and addon.StopHasOpenObjectives(first)
    if not midQuest and addon.LazyDecide then
        local ok, d = pcall(addon.LazyDecide)
        if ok and d and d.map and not d.trip and d.label and d.label:find("^Lazy mode:") then
            if not lastService[d.label] or now - lastService[d.label] > 900 then
                lastService[d.label] = now
                Log("next step: " .. tostring(d.say))
                Print(L("autopilot: ") .. tostring(d.say))
                if addon.LazyNow then addon.LazyNow() end
                return
            end
        end
    end

    -- 2. no quest stop left: make a plan for here, and if there is nothing, move on to the next zone
    if PlanStops() == 0 and now - lastMoveOn > 60 then
        lastMoveOn = now
        addon.planWhy = "autopilot: nothing left in the plan"
        pcall(addon.PlanRoute, addon, false, true, true)
        if PlanStops() > 0 then
            Log("made a plan for this zone")
            return
        end
        local s = NextZoneSegment()
        if s then
            Log("nothing left worth doing here: on to " .. tostring(s.zone))
            Print(L("autopilot: nothing left to do here, on to ") .. tostring(s.zone))
            if addon.PlanZone then addon.PlanZone(s.zone) end
        elseif now - lastNothing > 600 then
            lastNothing = now
            Print(L("autopilot: nothing left to do here and no next zone on your journey (/lazy guide)"))
        end
    end
end

local acc = 0
local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 4 then return end
    acc = 0
    pcall(Tick)
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "autopilot" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local db = DB()
        if a == "on" then db.autopilot = true
        elseif a == "off" then db.autopilot = false
        else db.autopilot = not db.autopilot end
        Print(L("autopilot ") .. (db.autopilot and "on: services, the next zone and its plan follow by themselves" or "off"))
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Autopilot.lua"] = true end end
