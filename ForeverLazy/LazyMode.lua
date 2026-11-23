-- Lazy Mode: one command (or key, or button) and the addon points the arrow at the single best next thing to do.
--   /lazy now          do it
-- It looks at, in this order:
--   1. am I a ghost                      -> the corpse arrow already shows the way
--   2. bags nearly full, or gear damaged -> the nearest vendor and repair NPC
--   3. a trainer visit is due            -> my class trainer
--   4. my plan has a stop                -> stop 1 (turn-ins and pick-ups are already in order there)
--   5. nothing to do in this zone        -> the next stop of my journey
-- Modules that are switched off are skipped. With "keep going" on, it picks the next thing by itself when I arrive.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

--------------------------------------------------------------------------------
-- What does my character need
--------------------------------------------------------------------------------
local function FreeSlots()
    local free = 0
    for bag = 0, 4 do
        local n
        if C_Container and C_Container.GetContainerNumFreeSlots then n = C_Container.GetContainerNumFreeSlots(bag)
        elseif GetContainerNumFreeSlots then n = GetContainerNumFreeSlots(bag) end
        if n then free = free + n end
    end
    return free
end

local function LowestDurability()
    local lowest, broken = 1, 0
    for slot = 1, 18 do
        if slot ~= 4 then
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 then
                local p = cur / max
                if p < lowest then lowest = p end
                if cur == 0 then broken = broken + 1 end
            end
        end
    end
    return lowest, broken
end

-- A trainer visit. Even levels are when most classes get new skills, but the trainer's own window says what is
-- really left: how many skills can be learned now, what the cheapest costs, and the level the next ones need.
-- That is remembered on every class trainer visit, so later the visit is skipped when there is nothing to learn.
local function TrainerKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end

local function ReadTrainer()
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end        -- a profession trainer says nothing about my class
    local count = GetNumTrainerServices and GetNumTrainerServices()
    if not count then return end
    local lvl = UnitLevel("player") or 1
    local avail, minCost, nextLevel = 0, nil, nil
    for i = 1, count do
        local name, _, category = GetTrainerServiceInfo(i)
        if name and category == "available" then
            avail = avail + 1
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
            if type(cost) == "table" then cost = cost[1] end
            if type(cost) == "number" and (not minCost or cost < minCost) then minCost = cost end
        elseif name and category == "unavailable" and GetTrainerServiceLevelReq then
            local ok, req = pcall(GetTrainerServiceLevelReq, i)
            if ok and type(req) == "number" and req > lvl and (not nextLevel or req < nextLevel) then nextLevel = req end
        end
    end
    local root = addon.GetRoot()
    root.trained = root.trained or {}
    root.trainerInfo = root.trainerInfo or {}
    local key = TrainerKey()
    root.trained[key] = lvl
    root.trainerInfo[key] = { level = lvl, avail = avail, minCost = minCost, nextLevel = nextLevel }
end

local function TrainerDue()
    -- new class skills only come at EVEN levels (4, 6, 8...): an odd level counts as the even level below it
    local lvl = UnitLevel("player") or 1
    lvl = lvl - lvl % 2
    if lvl < 4 then return false end
    local root = addon.GetRoot()
    root.trained = root.trained or {}
    local key = TrainerKey()
    local info = root.trainerInfo and root.trainerInfo[key]
    if info then
        -- skills I could learn but could not afford earlier: due again once I have the money
        if (info.avail or 0) > 0 then
            return (GetMoney and GetMoney() or 0) >= (info.minCost or 0)
        end
        -- nothing to learn at the last visit: due only once I have reached the level the next skills need
        if info.nextLevel then
            local last = (info.level or 0); last = last - last % 2
            return lvl >= info.nextLevel and last < info.nextLevel
        end
        -- the window did not say, so fall back on every even level
    end
    local seen = root.trained[key] or 0
    return seen - seen % 2 < lvl
end

local trainEv = CreateFrame("Frame")
pcall(trainEv.RegisterEvent, trainEv, "TRAINER_SHOW")
pcall(trainEv.RegisterEvent, trainEv, "TRAINER_UPDATE")
trainEv:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function() pcall(ReadTrainer) end)     -- the list fills a moment after the window opens
    else
        pcall(ReadTrainer)
    end
end)
--------------------------------------------------------------------------------
-- Deciding
--------------------------------------------------------------------------------
local function Waypoint(map, zx, zy, label, reason)
    local wps = DB().waypoints
    for i = #wps, 1, -1 do if wps[i].lazy then table.remove(wps, i) end end
    addon:AddWaypointZone(map, zx, zy, label)
    local w = DB().waypoints[1]
    if w then w.lazy = true; w.detail = reason end
end

local function Decide()
    local db = DB()
    if UnitIsGhost and UnitIsGhost("player") then
        return { say = "you are a ghost: follow the corpse arrow" }
    end

    if addon.ModuleOn("services") and api.FindService then
        local free = FreeSlots()
        local low, broken = LowestDurability()
        if free <= 2 or low < 0.25 or broken > 0 then
            local r = api.FindService("repair")
            if r then
                local why = (free <= 2) and "your bags are almost full" or "your gear is damaged"
                if free <= 2 and (low < 0.25 or broken > 0) then why = "your bags are full and your gear is damaged" end
                return { map = r.spawn.uiMapId, zx = r.spawn.zx, zy = r.spawn.zy, label = "Lazy mode: " .. (r.name or "vendor"),
                         reason = why .. ": sell and repair", say = why .. ", off to " .. (r.name or "a vendor") }
            end
        end
        if TrainerDue() then
            local r = api.FindService("classtrainer")
            if r then
                return { map = r.spawn.uiMapId, zx = r.spawn.zx, zy = r.spawn.zy, label = "Lazy mode: " .. (r.name or "trainer"),
                         reason = "new skills are waiting for you at your trainer", say = "time to visit your trainer, " .. (r.name or "") }
            end
        end
    end

    if addon.ModuleOn("plan") then
        if not (db.waypoints[1] and db.waypoints[1].label) and api.QuestieReady and api.QuestieReady() then
            addon:PlanRoute(false, true)              -- nothing planned yet: plan now
        end
        -- a trip is already under way (flight, boat, walk): say what to do now
        local tripTo, tripLeg = nil, nil
        if addon.GoStatus then tripTo, tripLeg = addon.GoStatus() end
        if tripTo then return { say = "on the way to " .. tripTo .. ": " .. tostring(tripLeg) } end
        local w = db.waypoints[1]
        if w and w.label then
            -- a stop far away: if flying gets me there quicker, send me to a flight master and say where to fly
            if w.uiMapId and w.zx and w.x and addon.ModuleOn("go") and addon.GoWithFlight then
                local px, py, pinst = hbd:GetPlayerWorldPosition()
                if px and w.instance == pinst and math.sqrt((w.x - px) ^ 2 + (w.y - py) ^ 2) > 1500 then
                    return { flightTrip = { w.uiMapId, w.zx, w.zy, tostring(w.name or w.label) }, say = "that stop is a long way off" }
                end
            end
            return { follow = true, say = "next stop of your plan: " .. tostring(w.name or w.label) }
        end
    end

    if addon.ModuleOn("zones") and addon.JourneyNext then
        local s = addon.JourneyNext()
        if s then
            return { map = s.map, zx = s.zx, zy = s.zy, label = string.format("Lazy mode: %s (level %d-%d)", s.zone, s.from, s.to),
                     reason = "nothing left to do here, time to move on to " .. s.zone, say = "nothing left to do here: on to " .. s.zone, trip = s.zone }
        end
    end
    return { say = "nothing to suggest right now. Take a quest, or /lazy plan" }
end

local function Now()
    local d = Decide()
    if d.flightTrip then
        if addon.GoWithFlight(d.flightTrip[1], d.flightTrip[2], d.flightTrip[3], d.flightTrip[4]) then return end
        Print(L("lazy mode: next stop of your plan: ") .. d.flightTrip[4])
        return
    end
    if d.map and d.trip and addon.GoTo and addon.ModuleOn("go") then
        Print(L("lazy mode: ") .. d.say)
        addon.GoTo(d.map, d.zx, d.zy, d.trip)       -- far away: plan the whole trip
    elseif d.map then
        Waypoint(d.map, d.zx, d.zy, d.label, d.reason)
        Print(L("lazy mode: ") .. d.say)
    elseif d.follow then
        -- the plan's own first stop is already the arrow: make sure it shows
        Print(L("lazy mode: ") .. d.say)
        local w = DB().waypoints[1]
        if w and w.detail == nil and addon.WaypointDetail then w.detail = nil end
    else
        Print(L("lazy mode: ") .. d.say)
    end
end
addon.LazyNow = Now
addon.LazyDecide = Decide
addon.LazyTrainerDue = TrainerDue
function _G.ForeverLazy_LazyNow() Now() end
_G.BINDING_NAME_FOREVERLAZY_NOW = "Lazy mode: point me at the next thing"

--------------------------------------------------------------------------------
-- Keep going: when the lazy stop is reached, pick the next thing
--------------------------------------------------------------------------------
local origRemove = addon.RemoveWaypoint
function addon:RemoveWaypoint(i)
    local w = DB().waypoints[i]
    local wasLazy = w and w.lazy
    origRemove(self, i)
    if wasLazy and DB().lazyKeepGoing and addon.ModuleOn("lazymode") and C_Timer then
        C_Timer.After(1.5, function() pcall(Now) end)
    end
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "now" then
        Now()
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- A plan stop a long way off: when a flight is the quick way there, start that trip by itself, so the arrow points at
-- the flight master (with what to say there) instead of at a quest far away. Pressing Lazy Mode does the same by hand.
local autoTried, lastAuto = {}, 0
local autoAcc = 0
local autoFrame = CreateFrame("Frame")
autoFrame:SetScript("OnUpdate", function(_, dt)
    autoAcc = autoAcc + dt
    if autoAcc < 4 then return end
    autoAcc = 0
    local db = DB()
    if not db or db.autoTrip ~= true or not addon.ModuleOn("go") or not addon.GoWithFlight then return end
    if addon.GoStatus and addon.GoStatus() then return end                 -- a trip is already under way
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if UnitIsGhost and UnitIsGhost("player") then return end
    local w = db.waypoints and db.waypoints[1]
    if not (w and w.label and w.uiMapId and w.zx and w.x and w.instance) then return end    -- only plan stops
    local key = tostring(w.label)
    if autoTried[key] and GetTime() - autoTried[key] < 1800 then return end        -- the same stop: not again for 30 minutes
    if GetTime() - lastAuto < 300 then return end
    if addon.GoLastCancel and GetTime() - addon.GoLastCancel < 1200 then return end   -- I cancelled a trip: leave me alone for a while
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px or w.instance ~= pinst then return end
    if math.sqrt((w.x - px) ^ 2 + (w.y - py) ^ 2) <= 1500 then return end
    autoTried[key] = GetTime()
    lastAuto = GetTime()
    pcall(addon.GoWithFlight, w.uiMapId, w.zx, w.zy, tostring(w.name or w.label))
end)
-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["LazyMode.lua"] = true end end
