-- Ask a guard where something is (a trainer, the bank, the inn...) and the arrow takes you there, then goes away.
-- The game answers with a red flag on the map. This catches that flag, puts the arrow on it as the next stop whether the
-- plan is on or off, and clears it again when you arrive. A new question replaces the last answer.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local lastGossip = -100      -- when a gossip window was last open or closing (a flag only counts just after one)
local lastSig                -- the flag I last acted on

local function PoiList(mapId)
    local gi = C_GossipInfo
    if not gi then return {} end
    local listFn = gi.GetPoiForUiMapID or gi.GetGossipPoiForUiMapID
    if not listFn then return {} end
    local ok, ids = pcall(listFn, mapId)
    if not ok or ids == nil then return {} end
    if type(ids) == "number" then ids = { ids } end
    return type(ids) == "table" and ids or {}
end

local function PoiPos(mapId, id)
    local gi = C_GossipInfo
    local infoFn = gi and (gi.GetPoiInfo or gi.GetGossipPoiInfo)
    if not infoFn then return nil end
    local ok, info = pcall(infoFn, mapId, id)
    if not ok or type(info) ~= "table" then return nil end
    local pos = info.position
    local x, y
    if type(pos) == "table" then
        if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
    end
    if not (tonumber(x) and tonumber(y)) then return nil end
    return tonumber(x), tonumber(y), info.name or info.description
end

local function RemoveGuardStops()
    local wps = DB().waypoints
    for i = #wps, 1, -1 do if wps[i].guard then table.remove(wps, i) end end
end

local function Check()
    if GetTime() - lastGossip > 8 then return end
    local mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapId then return end
    for _, id in ipairs(PoiList(mapId)) do
        local x, y, name = PoiPos(mapId, id)
        if x then
            local sig = string.format("%d:%s:%.4f:%.4f", mapId, tostring(id), x, y)
            if sig ~= lastSig then
                lastSig = sig
                RemoveGuardStops()
                addon:AddWaypointZone(mapId, x, y, "Guard: " .. tostring(name or "where you asked"))
                local w = DB().waypoints[1]
                if w then
                    w.guard = true
                    w.detail = "What the guard pointed to"
                end
                -- the arrow has to be on the automatic setting to show this stop
                local src = DB().arrowSource
                if src and src ~= "auto" and src ~= "plan" then DB().arrowSource = "auto" end
                addon:RefreshPins()
                if addon.RefreshOptions then addon.RefreshOptions() end
                return
            end
        end
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "GOSSIP_CLOSED", "DYNAMIC_GOSSIP_POI_UPDATED", "GOSSIP_POI_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "GOSSIP_SHOW" or event == "GOSSIP_CLOSED" then
        lastGossip = GetTime()
        -- the flag arrives as the window closes
        if event == "GOSSIP_CLOSED" and C_Timer then C_Timer.After(0.5, function() pcall(Check) end) end
    else
        if C_Timer then C_Timer.After(0.3, function() pcall(Check) end) else pcall(Check) end
    end
end)

-- the arrow goes away when I get there
local acc = 0
local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    local db = DB()
    local w = db and db.waypoints and db.waypoints[1]
    if not (w and w.guard) then return end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px or w.instance ~= pinst then return end
    local d = math.sqrt((w.x - px) ^ 2 + (w.y - py) ^ 2)
    if d <= math.max(tonumber(db.arrival) or 15, 20) then
        if C_Timer then
            C_Timer.After(1, function()
                local cur = DB().waypoints[1]
                if cur == w then addon:RemoveWaypoint(1); Print("arrived at " .. tostring(w.name)) end
            end)
        else
            addon:RemoveWaypoint(1)
        end
        w.guard = nil          -- only schedule it once
    end
end)

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["GuardPoi.lua"] = true end end
