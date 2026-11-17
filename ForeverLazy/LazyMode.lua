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

-- a trainer visit is due on every even level from 4 until I have been to one at that level
local function TrainerDue()
    local lvl = UnitLevel("player") or 1
    local even = lvl - lvl % 2
    if even < 4 then return false end
    local root = addon.GetRoot()
    root.trained = root.trained or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    return (root.trained[key] or 0) < even
end

local trainEv = CreateFrame("Frame")
trainEv:RegisterEvent("TRAINER_SHOW")
trainEv:SetScript("OnEvent", function()
    local root = addon.GetRoot()
    root.trained = root.trained or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    root.trained[key] = UnitLevel("player") or 0
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
        local w = db.waypoints[1]
        if w and w.label then
            return { follow = true, say = "next stop of your plan: " .. tostring(w.name or w.label) }
        end
    end

    if addon.ModuleOn("zones") and addon.JourneyNext then
        local s = addon.JourneyNext()
        if s then
            return { map = s.map, zx = s.zx, zy = s.zy, label = string.format("Lazy mode: %s (level %d-%d)", s.zone, s.from, s.to),
                     reason = "nothing left to do here, time to move on to " .. s.zone, say = "nothing left to do here: on to " .. s.zone }
        end
    end
    return { say = "nothing to suggest right now. Take a quest, or /lrxp plan" }
end

local function Now()
    local d = Decide()
    if d.map then
        Waypoint(d.map, d.zx, d.zy, d.label, d.reason)
        Print("lazy mode: " .. d.say)
    elseif d.follow then
        -- the plan's own first stop is already the arrow: make sure it shows
        Print("lazy mode: " .. d.say)
        local w = DB().waypoints[1]
        if w and w.detail == nil and addon.WaypointDetail then w.detail = nil end
    else
        Print("lazy mode: " .. d.say)
    end
end
addon.LazyNow = Now
function _G.LRXPT_LazyNow() Now() end
_G.BINDING_NAME_LRXPT_NOW = "Lazy mode: point me at the next thing"

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
