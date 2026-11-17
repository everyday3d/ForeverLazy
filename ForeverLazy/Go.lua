-- Take me there: name a place and the addon plans the whole trip, then the arrow follows it leg by leg.
--   /lazy go westfall | stormwind | the deadmines | darnassus | hearth | inn | <a flight point you found>
--   /lazy go stop
-- It uses what it knows: the flight points you have opened, the boat docks you taught it, the Deeprun Tram,
-- your hearthstone (when it is ready) and walking, and picks the quickest. Times are estimates; flights use the
-- times the addon has learned. A leg it knows nothing about (a dock you never marked) is simply not used.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end
local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function MapName(id)
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or "?"
end

local function Speed()
    local _, run = GetUnitSpeed("player")
    return math.max(run or 7, 7)
end

local function Clock(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function Mod(name)
    local ql = _G.QuestieLoader
    if not ql then return nil end
    local ok, m = pcall(ql.ImportModule, ql, name)
    return ok and m or nil
end

--------------------------------------------------------------------------------
-- Where am I going
--------------------------------------------------------------------------------
local function Place(name, map, zx, zy)
    local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(zx, zy, map)
    if not wx then return nil end
    return { name = name, map = map, zx = zx, zy = zy, x = wx, y = wy, instance = inst }
end

local CITIES = { "Stormwind City", "Ironforge", "Darnassus", "Orgrimmar", "Undercity", "Thunder Bluff" }

local function CityPlace(text)
    for _, city in ipairs(CITIES) do
        local short = city:lower():gsub(" city$", "")
        if text == short or text == city:lower() then
            local mapId
            for id = 1400, 1500 do
                local info = C_Map.GetMapInfo(id)
                if info and info.name == city then mapId = id; break end
            end
            if not mapId then return nil end
            -- a flight master in the city is a fair point to aim at, else the middle of the map
            local T, QDB = Mod("Townsfolk"), api.GetQuestie()
            if T and QDB and T.townsfolk and T.townsfolk["Flight Master"] then
                for _, npc in ipairs(T.townsfolk["Flight Master"]) do
                    local sp = {}
                    api.AddNpcs(sp, { npc })
                    for _, s in ipairs(sp) do
                        if s.uiMapId == mapId then return Place(city, mapId, s.zx, s.zy) end
                    end
                end
            end
            return Place(city, mapId, 0.5, 0.5)
        end
    end
end

local function Resolve(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if text == "hearth" or text == "home" then
        local h = api.HearthPoint and api.HearthPoint()
        if h then return Place("your hearthstone inn (" .. tostring(h.name) .. ")", h.map, h.zx, h.zy) end
        return nil, "I don't know where your hearthstone is bound yet (/lazy hearth set)"
    end
    -- a dungeon
    local rec = api.DungeonFind and api.DungeonFind(text)
    if rec then
        local e = rec.entrances[1]
        return Place(rec.name .. " entrance", e.uiMapId, e.zx, e.zy)
    end
    -- a flight point I have found
    if api.KnownFlightPoints then
        for _, f in ipairs(api.KnownFlightPoints()) do
            if f.name:lower():find(text, 1, true) then return Place(f.name .. " flight point", f.map, f.zx, f.zy) end
        end
    end
    -- a capital city
    local city = CityPlace(text)
    if city then return city end
    -- a zone: its quest hub
    local NZ = api.NextZone
    if NZ and NZ.zones then
        local faction = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
        for _, z in ipairs(NZ.zones) do
            if z[1]:lower():find(text, 1, true) then
                local hub = z[faction] or z.A or z.H
                local mapId = NZ.mapId(z[1])
                if hub and mapId then return Place(z[1] .. " (" .. (z[faction] and "quest hub" or "hub") .. ")", mapId, hub[1] / 100, hub[2] / 100) end
            end
        end
    end
    -- a service (inn, repair, bank ...)
    if api.FindService then
        local r = api.FindService(text)
        if r then return Place(r.name or text, r.spawn.uiMapId, r.spawn.zx, r.spawn.zy) end
    end
    return nil, "I don't know a place called '" .. text .. "' (try a zone, a city, a dungeon, a flight point you found, hearth, or inn)"
end

--------------------------------------------------------------------------------
-- The map of ways to travel
--------------------------------------------------------------------------------
local function BuildGraph(dest)
    local nodes, rides = {}, {}      -- rides[i] = list of { to, cost, kind, text }
    local function add(n) nodes[#nodes + 1] = n; rides[#nodes] = {}; return #nodes end

    -- me
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return nil end
    local zx, zy, map = hbd:GetPlayerZonePosition()
    local start = add({ name = "here", instance = pinst, x = px, y = py, map = map, zx = zx, zy = zy })

    -- flight points I have found
    local fps = {}
    for _, f in ipairs(api.KnownFlightPoints and api.KnownFlightPoints() or {}) do
        local n = Place(f.name, f.map, f.zx, f.zy)
        if n then n.fp = true; n.index = add(n); fps[#fps + 1] = n end
    end
    local times = DB().flightTimes or {}
    for _, a in ipairs(fps) do
        for _, b in ipairs(fps) do
            if a ~= b and a.instance == b.instance then
                local rec = times[a.name .. "->" .. b.name]
                local cost = rec and rec.avg or (Dist(a, b) / 30 + 15)
                table.insert(rides[a.index], { to = b.index, cost = cost + 10, kind = "fly",
                    text = string.format("Talk to the flight master here and fly to %s (about %s)", b.name:match("^[^,]+") or b.name, Clock(cost)) })
            end
        end
    end

    -- boats and zeppelins whose docks I know
    local byKey = {}
    local function dockNode(d)
        local key = d.map .. ":" .. string.format("%.3f,%.3f", d.zx, d.zy)
        if byKey[key] then return byKey[key] end
        local n = Place(d.name, d.map, d.zx, d.zy)
        if not n then return nil end
        n.index = add(n); byKey[key] = n
        return n
    end
    for _, link in ipairs(api.BoatLinks and api.BoatLinks() or {}) do
        local a, b = dockNode(link.from), dockNode(link.to)
        if a and b then
            table.insert(rides[a.index], { to = b.index, cost = 180, kind = "boat",
                text = string.format("Board %s at the %s to %s", link.boat, a.name, b.name:gsub(" dock$", "")) })
        end
    end

    -- the Deeprun Tram
    local tram = api.DungeonFind and api.DungeonFind("deeprun")
    if tram and #tram.entrances >= 2 then
        local a = Place("Deeprun Tram", tram.entrances[1].uiMapId, tram.entrances[1].zx, tram.entrances[1].zy)
        local b = Place("Deeprun Tram", tram.entrances[2].uiMapId, tram.entrances[2].zx, tram.entrances[2].zy)
        if a and b then
            a.index, b.index = add(a), add(b)
            table.insert(rides[a.index], { to = b.index, cost = 100, kind = "tram", text = "Take the Deeprun Tram through to the other city" })
            table.insert(rides[b.index], { to = a.index, cost = 100, kind = "tram", text = "Take the Deeprun Tram through to the other city" })
        end
    end

    -- my hearthstone, if it is ready
    local hearth
    local hp = api.HearthPoint and api.HearthPoint()
    if hp and GetItemCount and GetItemCount(6948) > 0 then
        local start2, dur = GetItemCooldown(6948)
        if not (start2 and start2 > 0 and dur and dur > 2) then
            hearth = Place("hearthstone inn", hp.map, hp.zx, hp.zy)
            if hearth then hearth.index = add(hearth) end
        end
    end

    local d = dest
    d.index = add(d)
    return nodes, rides, start, hearth, d.index
end

-- the quickest way: walk, fly, boat, tram, hearth
local function Route(dest)
    local nodes, rides, start, hearth, goal = BuildGraph(dest)
    if not nodes then return nil, "I can't read your position here" end
    local speed = Speed()
    local best, prev, how = {}, {}, {}
    for i = 1, #nodes do best[i] = math.huge end
    best[start] = 0
    local done = {}
    while true do
        local u, ud = nil, math.huge
        for i = 1, #nodes do if not done[i] and best[i] < ud then u, ud = i, best[i] end end
        if not u then break end
        done[u] = true
        if u == goal then break end
        local function relax(v, cost, edge)
            if best[u] + cost < best[v] then best[v] = best[u] + cost; prev[v] = u; how[v] = edge end
        end
        for v = 1, #nodes do
            if v ~= u and nodes[v].instance == nodes[u].instance then
                local d = Dist(nodes[u], nodes[v])
                relax(v, d / speed, { kind = "walk", dist = d })
            end
        end
        for _, r in ipairs(rides[u]) do relax(r.to, r.cost, r) end
        if hearth and u ~= hearth.index and u ~= start or (hearth and u == start) then
            if hearth and u ~= hearth.index then relax(hearth.index, 25, { kind = "hearth", text = "Use your hearthstone (it takes you to " .. hearth.name .. ")" }) end
        end
    end
    if best[goal] == math.huge then return nil, "no way I know of gets you there from here. Teach me the docks (/lazy boat) and open flight maps." end
    local chain, cur = {}, goal
    while cur ~= start do table.insert(chain, 1, { from = prev[cur], to = cur, edge = how[cur], t = best[cur] - best[prev[cur]] }); cur = prev[cur] end

    -- one walk after another is one walk
    local legs = {}
    for _, step in ipairs(chain) do
        local last = legs[#legs]
        if step.edge.kind == "walk" and last and last.kind == "walk" then
            last.to = nodes[step.to]; last.t = last.t + step.t; last.dist = last.dist + step.edge.dist
        else
            legs[#legs + 1] = { kind = step.edge.kind, from = nodes[step.from], to = nodes[step.to], t = step.t,
                                dist = step.edge.dist or 0, text = step.edge.text }
        end
    end
    return legs, best[goal]
end

--------------------------------------------------------------------------------
-- Following the trip
--------------------------------------------------------------------------------
local trip

local function Clear()
    local wps = DB().waypoints
    for i = #wps, 1, -1 do if wps[i].go then table.remove(wps, i) end end
end

local function LegText(l)
    if l.kind == "walk" then return string.format("Walk to %s (about %d yards, %s)", l.to.name == "here" and "the spot" or l.to.name, l.dist, Clock(l.t)) end
    return l.text
end

local function Show()
    if not trip then return end
    local l = trip.legs[trip.idx]
    Clear()
    -- walk legs point at where they end; rides point at where to board
    local at = (l.kind == "walk") and l.to or l.from
    local wps = DB().waypoints
    table.insert(wps, 1, { name = string.format("Trip: %s", LegText(l)), go = true, detail = LegText(l),
                           instance = at.instance, x = at.x, y = at.y, uiMapId = at.map, zx = at.zx, zy = at.zy })
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
end

local function Start(dest)
    local legs, total = Route(dest)
    if not legs then Print(total); return end
    if #legs == 0 then Print("you are already there"); return end
    trip = { legs = legs, idx = 1, dest = dest }
    Print(string.format("trip to %s: %d step%s, about %s in all", dest.name, #legs, #legs == 1 and "" or "s", Clock(total)))
    for i, l in ipairs(legs) do Print(string.format("  %d. %s", i, LegText(l))) end
    Show()
end
function addon.GoTo(map, zx, zy, name)
    local dest = Place(name or "there", map, zx, zy)
    if dest then Start(dest) end
end

-- Lazy Mode asks this for a far-away stop: if the quickest way there uses a flight, start that trip
function addon.GoWithFlight(map, zx, zy, name)
    local dest = Place(name or "there", map, zx, zy)
    if not dest then return false end
    local legs = Route(dest)
    if not legs or #legs == 0 then return false end
    local flies = false
    for _, l in ipairs(legs) do if l.kind == "fly" then flies = true end end
    if not flies then return false end
    Start(dest)
    return true
end

-- the rest of the trip as points to draw: where to board, where each ride lands, where the walks end.
-- Each point is { x, y, instance, kind = how I get there ("walk", "fly", "boat", "tram", "hearth"), name, text }.
function addon.GoTripPath()
    if not trip then return nil end
    local out = {}
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local last = px and { x = px, y = py, instance = pinst } or nil
    for i = trip.idx, #trip.legs do
        local l = trip.legs[i]
        if l.kind == "walk" then
            out[#out + 1] = { x = l.to.x, y = l.to.y, instance = l.to.instance, kind = "walk", name = l.to.name, text = LegText(l) }
        else
            -- walk to the boarding point first, unless I am already there
            if l.from and last and (l.from.instance ~= last.instance or Dist(l.from, last) > 8) then
                out[#out + 1] = { x = l.from.x, y = l.from.y, instance = l.from.instance, kind = "walk", name = l.from.name, text = LegText(l) }
            end
            out[#out + 1] = { x = l.to.x, y = l.to.y, instance = l.to.instance, kind = l.kind, name = l.to.name, text = LegText(l) }
        end
        last = out[#out]
    end
    return out
end
-- the flight point the trip flies to next (nil when no trip, or no flight left in it)
function addon.GoFlightTarget()
    if not trip then return nil end
    for i = trip.idx, #trip.legs do
        local l = trip.legs[i]
        if l.kind == "fly" then return l.to.name end
    end
    return nil
end
-- what the trip in progress wants me to do now (nil when there is none)
function addon.GoStatus()
    if not trip then return nil end
    return trip.dest.name, LegText(trip.legs[trip.idx])
end

local function Tick()
    if not trip or not addon.ModuleOn("go") then return end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return end
    local l = trip.legs[trip.idx]
    local near = l.to.instance == pinst and Dist({ x = px, y = py }, l.to)
    local reached
    if l.kind == "walk" then
        reached = near and near < 40
    else
        -- a ride (tram, boat, flight, hearth): done when I am where it lands, or when it clearly took me away from where I boarded
        reached = near and near < 150
        local fromD = (l.from and l.from.instance == pinst) and Dist({ x = px, y = py }, l.from) or nil
        if not reached and near and fromD and fromD > 400 and near < fromD then reached = true end
        -- the tram and some boats run inside another area: once I have been in it and I am back out away from the boarding spot, it is done
        if l.to.instance ~= pinst then trip.away = true end
        if not reached and trip.away and l.to.instance == pinst and (not fromD or fromD > 150) then reached = true end
    end
    if reached then trip.away = nil end
    if reached then
        trip.idx = trip.idx + 1
        if trip.idx > #trip.legs then
            Clear()
            Print("you have arrived at " .. trip.dest.name)
            trip = nil
            addon:RefreshPins()
        else
            Show()
            Print("next: " .. LegText(trip.legs[trip.idx]))
        end
    end
end

local t = 0
local ev = CreateFrame("Frame")
ev:SetScript("OnUpdate", function(_, dt)
    t = t + dt
    if t < 1.5 then return end
    t = 0
    pcall(Tick)
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "go" then
        local arg = ((rest or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        if arg:lower() == "stop" then
            trip = nil
            Clear()
            addon:RefreshPins()
            Print("trip cancelled")
        elseif arg == "" then
            if trip then Print("on the way to " .. trip.dest.name .. ": " .. LegText(trip.legs[trip.idx])) else Print("/lazy go <place>, for example /lazy go westfall, /lazy go stormwind, /lazy go the deadmines, /lazy go hearth") end
        else
            local dest, err = Resolve(arg)
            if not dest then Print(err or "I could not place that"); return true end
            Start(dest)
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Go.lua"] = true end end
