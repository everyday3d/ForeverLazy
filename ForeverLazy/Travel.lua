-- Hearthstone and flight points.
--   /lazy hearth            arrow to the inn my hearthstone is bound to
--   /lazy hearth set        I am at my inn: remember it
--   /lazy fp                nearest flight master I have not discovered yet
--   /lazy fp list           the flight points I have learned
-- The game does not tell addons where the hearthstone is bound or where flight masters stand, so the addon learns it:
-- it notices when you bind (or open a flight map) and remembers the spot you were standing on.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end
local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end
local function Store(name)
    local root = addon.GetRoot()
    root[name] = root[name] or {}
    root[name][CharKey()] = root[name][CharKey()] or {}
    return root[name][CharKey()]
end

local function MapName(id)
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or "?"
end

local function Mod(name)
    return ns.data.Module(name)
end

--------------------------------------------------------------------------------
-- Hearthstone
--------------------------------------------------------------------------------
local lastBind
local function RememberHearth(manual)
    local zx, zy, map = hbd:GetPlayerZonePosition()
    if not zx then if manual then Print(L("I can't read your position here")) end; return end
    local h = Store("hearth")
    h.map, h.zx, h.zy = map, zx, zy
    h.name = (GetBindLocation and GetBindLocation()) or MapName(map)
    Print(string.format(L("hearthstone spot remembered: %s (%s %.1f, %.1f)"), h.name, MapName(map), zx * 100, zy * 100))
end

local function BindCheck()
    if not GetBindLocation then return end
    local now = GetBindLocation()
    if lastBind and now and now ~= lastBind then RememberHearth(false) end
    lastBind = now
end

-- binding to a new inn: the confirm window opens while I stand at the innkeeper
if hooksecurefunc and _G.ConfirmBinder then
    pcall(hooksecurefunc, "ConfirmBinder", function() if C_Timer then C_Timer.After(2, BindCheck) end end)
end

local function GoHearth()
    local h = Store("hearth")
    if not h.map then
        Print(L("I don't know where your hearthstone is bound yet. Stand at your inn and type /lazy hearth set,"))
        Print(L("or just bind again at an innkeeper and I will remember it."))
        return
    end
    local wps = DB().waypoints
    for i = #wps, 1, -1 do if wps[i].hearth then table.remove(wps, i) end end
    addon:AddWaypointZone(h.map, h.zx, h.zy, "Hearth: " .. tostring(h.name))
    if DB().waypoints[1] then
        DB().waypoints[1].hearth = true
        DB().waypoints[1].detail = "Your hearthstone is bound at this inn"
    end
end

-- a nudge when the next stop is far and the hearthstone would save the walk
local nudged
local function HearthNudge()
    local db = DB()
    if not db or db.hearthNudge == false or not addon.ModuleOn("travel") then return end
    local h = Store("hearth")
    local wp = db.waypoints[1]
    if not (h.map and wp and wp.label and not wp.hearth) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not (GetItemCount and GetItemCount(6948) > 0) then return end
    local start, duration = GetItemCooldown(6948)
    if start and start > 0 and duration and duration > 2 then return end
    local key = wp.name or wp.label
    if nudged == key then return end
    local hx, hy, hinst = hbd:GetWorldCoordinatesFromZone(h.zx, h.zy, h.map)
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not (hx and px) or hinst ~= wp.instance or pinst ~= wp.instance then return end
    local fromHere = Dist({ x = px, y = py }, wp)
    local fromHearth = Dist({ x = hx, y = hy }, wp)
    if fromHere - fromHearth > 1500 then
        nudged = key
        Print(string.format(L("your next stop is far: your hearthstone (bound at %s) would save about %d yards. /lazy hearth shows the way to it."),
            tostring(h.name), fromHere - fromHearth))
    end
end

--------------------------------------------------------------------------------
-- Flight points
--------------------------------------------------------------------------------
-- the flight map lists the points I have opened as reachable; the guide data gives each one's position
local function LearnFlightPoint()
    if not (NumTaxiNodes and TaxiNodeGetType and TaxiNodeName) or not addon.ModuleOn("travel") then return end
    local fp = Store("flightPoints")
    local added, last = 0, nil
    for i = 1, NumTaxiNodes() do
        local kind = TaxiNodeGetType(i)
        if kind == "CURRENT" or kind == "REACHABLE" then
            local name = TaxiNodeName(i)
            if name and not fp[name] then
                local data = api.FlightPointByName and api.FlightPointByName(name)
                if data then
                    fp[name] = { map = data.map, zx = data.zx, zy = data.zy }
                elseif kind == "CURRENT" then
                    local zx, zy, map = hbd:GetPlayerZonePosition()
                    if zx then fp[name] = { map = map, zx = zx, zy = zy } end
                end
                if fp[name] then added = added + 1; last = name end
            end
        end
    end
    if added == 1 then Print(L("flight point learned: ") .. last)
    elseif added > 1 then Print(string.format(L("learned %d flight points from the flight map"), added)) end
end

local function KnownFlightPoints()
    local list = {}
    for name, f in pairs(Store("flightPoints")) do
        local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(f.zx, f.zy, f.map)
        if wx then list[#list + 1] = { name = name, x = wx, y = wy, instance = inst } end
    end
    return list
end

-- flight points I have not opened, nearest first (the guide data lists every one)
local function Undiscovered()
    if not api.FlightData then return nil, "the flight point data did not load" end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return nil, "I can't read your position here" end
    local have = {}
    for name in pairs(Store("flightPoints")) do have[((name:match("^[^,]+")) or name):lower()] = true end
    local out = {}
    for _, f in ipairs(api.FlightData()) do
        if not have[f.name:lower()] then
            local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(f.zx, f.zy, f.map)
            if wx and inst == pinst then
                out[#out + 1] = { name = f.name, d = Dist({ x = px, y = py }, { x = wx, y = wy }),
                                  spawn = { uiMapId = f.map, zx = f.zx, zy = f.zy, x = wx, y = wy, instance = inst } }
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end
local function GoFlightPoint(n)
    local list, err = Undiscovered()
    if not list then Print(err); return end
    if #list == 0 then Print(L("no undiscovered flight masters on this continent that I know of")); return end
    local pick = math.min(math.max(tonumber(n) or 1, 1), #list)
    for i = 1, math.min(3, #list) do
        local r = list[i]
        Print(string.format(L("%s%d. %s - %s %.0f, %.0f (about %d yards)"), i == pick and "> " or "  ", i, r.name,
            MapName(r.spawn.uiMapId), r.spawn.zx * 100, r.spawn.zy * 100, r.d))
    end
    local r = list[pick]
    local wps = DB().waypoints
    for i = #wps, 1, -1 do if wps[i].service then table.remove(wps, i) end end
    addon:AddWaypointZone(r.spawn.uiMapId, r.spawn.zx, r.spawn.zy, "New flight point: " .. r.name)
    if DB().waypoints[1] then
        DB().waypoints[1].service = true
        DB().waypoints[1].detail = "Talk to " .. r.name .. " to learn this flight point"
    end
    if next(Store("flightPoints")) == nil then
        Print(L("I have not learned any of your flight points yet, so this may include ones you already have. Opening a flight map at a flight master teaches me."))
    end
end

--------------------------------------------------------------------------------
-- Events and command
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "TAXIMAP_OPENED")
pcall(ev.RegisterEvent, ev, "CONFIRM_BINDER")
pcall(ev.RegisterEvent, ev, "HEARTHSTONE_BOUND")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        lastBind = GetBindLocation and GetBindLocation() or nil
    elseif event == "TAXIMAP_OPENED" then
        LearnFlightPoint()
    elseif C_Timer then
        C_Timer.After(2, BindCheck)
    end
end)

local timer = 0
ev:SetScript("OnUpdate", function(_, dt)
    timer = timer + dt
    if timer < 15 then return end
    timer = 0
    BindCheck()
    pcall(HearthNudge)
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    local arg = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if word == "hearth" or word == "home" then
        if arg == "set" then RememberHearth(true) else GoHearth() end
        return true
    elseif word == "fp" or word == "flightpoint" or word == "flightpoints" then
        if arg == "list" then
            local n, names = 0, {}
            for name in pairs(Store("flightPoints")) do n = n + 1; names[#names + 1] = name end
            table.sort(names)
            Print(n == 0 and "no flight points learned yet. Open the flight map at a flight master and I will remember it."
                or (n .. " flight points learned: " .. table.concat(names, ", ")))
        else
            GoFlightPoint(tonumber(arg))
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- used by the trip planner
function api.KnownFlightPoints()
    local out = {}
    for name, f in pairs(Store("flightPoints")) do out[#out + 1] = { name = name, map = f.map, zx = f.zx, zy = f.zy } end
    return out
end

function api.HearthPoint()
    local h = Store("hearth")
    if h.map then return { name = h.name, map = h.map, zx = h.zx, zy = h.zy } end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Travel.lua"] = true end end
