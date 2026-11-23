-- Gathering routes and fishing spots, from Questie's object data.
--   /lazy herb peacebloom      a route through the nearest peacebloom (also /lazy ore tin, /lazy gather <name>)
--   /lazy gather               a route for the nodes my crafting plan is missing (after /lazy craft)
--   /lazy fish                 nearest fishing pools and wreckage; /lazy fish 2 for the next one
-- The arrow goes to the first spot and moves on as you arrive. Names are matched on part of the node's name.
local ADDON, ns = ...
local L = ns.L
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

--------------------------------------------------------------------------------
-- An index of object names (made once, a few hundred per frame)
--------------------------------------------------------------------------------
local index, scanning
local waiting = {}

local function WithIndex(cb)
    if index then cb(); return end
    waiting[#waiting + 1] = cb
    if scanning then return end
    local QDB = api.GetQuestie()
    if not (api.QuestieReady and api.QuestieReady() and QDB and QDB.ObjectPointers and C_Timer) then
        waiting = {}
        Print(L("needs Questie loaded and ready"))
        return
    end
    scanning = true
    Print(L("reading Questie's object list, one moment..."))
    local ids = {}
    for id in pairs(QDB.ObjectPointers) do ids[#ids + 1] = id end
    local list, i = {}, 1
    local function step()
        local last = math.min(i + 499, #ids)
        for k = i, last do
            local name = QDB.QueryObjectSingle(ids[k], "name")
            if name and name ~= "" then list[#list + 1] = { id = ids[k], name = name, lname = name:lower() } end
        end
        i = last + 1
        if i <= #ids then
            C_Timer.After(0, step)
        else
            index, scanning = list, false
            local w = waiting
            waiting = {}
            for _, f in ipairs(w) do pcall(f) end
        end
    end
    step()
end

local function MatchIds(matcher)
    local ids = {}
    for _, o in ipairs(index) do
        if matcher(o.lname) then ids[#ids + 1] = o end
    end
    return ids
end

--------------------------------------------------------------------------------
-- Spots near me
--------------------------------------------------------------------------------
local function Spots(objs)
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return {} end
    local here = { x = px, y = py }
    local out = {}
    for n, o in ipairs(objs) do
        if n > 60 then break end
        local sp = {}
        api.AddObjects(sp, { o.id })
        for _, s in ipairs(sp) do
            if s.instance == pinst then
                out[#out + 1] = { spawn = s, name = o.name, d = Dist(here, s) }
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

local function ClearGather()
    local wps = DB().waypoints
    for i = #wps, 1, -1 do if wps[i].gather then table.remove(wps, i) end end
end

local function Place(route, title)
    ClearGather()
    local wps = DB().waypoints
    for i = #route, 1, -1 do
        local r = route[i]
        local s = r.spawn
        table.insert(wps, 1, { name = string.format("%s (%d of %d)", r.name, i, #route), gather = true, detail = title,
                               instance = s.instance, x = s.x, y = s.y, uiMapId = s.uiMapId, zx = s.zx, zy = s.zy })
    end
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
end

-- a walk through the nearest spots, each next one the nearest to the last
local function Route(spots, maxStops)
    local route, left = {}, {}
    for _, s in ipairs(spots) do left[#left + 1] = s end
    local cur = nil
    local px, py = hbd:GetPlayerWorldPosition()
    cur = { x = px, y = py }
    while #route < maxStops and #left > 0 do
        local bi, bd
        for i, s in ipairs(left) do
            local d = Dist(cur, s.spawn)
            if d < 2500 and (not bd or d < bd) then bi, bd = i, d end
        end
        if not bi then break end
        local s = table.remove(left, bi)
        if bd > 40 or #route == 0 then       -- two nodes in one spot count as one stop
            route[#route + 1] = s
            cur = s.spawn
        end
    end
    return route
end

local function Gather(arg)
    local want = arg
    if not want or want == "" then
        local needs = addon.CraftNeeds and addon.CraftNeeds() or {}
        for _, n in ipairs(needs) do
            if n.src and n.src.kind == "node" and n.src.name then want = n.src.name:lower(); break end
        end
        if not want or want == "" then
            Print(L("which node? For example /lazy herb peacebloom or /lazy ore tin. After /lazy craft, /lazy gather finds the nodes you are missing."))
            return
        end
    end
    WithIndex(function()
        local matches = MatchIds(function(n) return n:find(want, 1, true) ~= nil end)
        if #matches == 0 then Print(L("no node named like '") .. want .. L("' in Questie's data")); return end
        local spots = Spots(matches)
        if #spots == 0 then Print(L("none of those on this continent that I know of")); return end
        local route = Route(spots, 12)
        Place(route, "Gather " .. (route[1].name or want))
        Print(string.format(L("gathering route: %d stop%s for %s, the first about %d yards away (%s %.0f, %.0f)"), #route,
            #route == 1 and "" or "s", route[1].name, route[1].d, MapName(route[1].spawn.uiMapId),
            route[1].spawn.zx * 100, route[1].spawn.zy * 100))
    end)
end

local FISH = { "school", "swarm", "wreckage", "oil spill", "debris" }
local function Fish(n)
    WithIndex(function()
        local matches = MatchIds(function(name)
            for _, p in ipairs(FISH) do if name:find(p, 1, true) then return true end end
        end)
        local spots = Spots(matches)
        if #spots == 0 then Print(L("no fishing spots known on this continent")); return end
        -- the same pool listed twice is one
        local list = {}
        for _, s in ipairs(spots) do
            local dup
            for _, o in ipairs(list) do if Dist(o.spawn, s.spawn) < 60 then dup = true; break end end
            if not dup then list[#list + 1] = s end
            if #list >= 5 then break end
        end
        local pick = math.min(math.max(tonumber(n) or 1, 1), #list)
        for i = 1, math.min(3, #list) do
            local s = list[i]
            Print(string.format(L("%s%d. %s - %s %.0f, %.0f (about %d yards)"), i == pick and "> " or "  ", i, s.name,
                MapName(s.spawn.uiMapId), s.spawn.zx * 100, s.spawn.zy * 100, s.d))
        end
        Place({ list[pick] }, "Fish here")
    end)
end

-- which zones have a node like this? cb(list of { zone, n }, list of distinct node names), biggest zone first
function addon.NodeZones(want, cb)
    WithIndex(function()
        local matches = MatchIds(function(n) return n:find(want, 1, true) ~= nil end)
        local by, names, nameList = {}, {}, {}
        for i, o in ipairs(matches) do
            if i > 80 then break end
            if not names[o.name] then names[o.name] = true; nameList[#nameList + 1] = o.name end
            local sp = {}
            api.AddObjects(sp, { o.id })
            for _, s in ipairs(sp) do
                if s.uiMapId then
                    local e = by[s.uiMapId]
                    if not e then e = { n = 0, zx = s.zx, zy = s.zy }; by[s.uiMapId] = e end
                    e.n = e.n + 1
                end
            end
        end
        local list = {}
        for map, e in pairs(by) do list[#list + 1] = { zone = MapName(map), n = e.n, map = map, zx = e.zx, zy = e.zy } end
        table.sort(list, function(a, b) return a.n > b.n end)
        cb(list, nameList)
    end)
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    local arg = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if word == "gather" or word == "herb" or word == "herbs" or word == "ore" then
        Gather(arg)
        return true
    elseif word == "fish" or word == "fishing" then
        Fish(tonumber(arg))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Gather.lua"] = true end end
