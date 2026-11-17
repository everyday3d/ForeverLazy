-- Boats and zeppelins: type where you want to go and the arrow points at the dock to use.
--   /lazy boat darnassus          route from where you are, arrow on the first dock
--   /lazy boat stormwind to rutheran   name both ends yourself
--   /lazy boat mark [port]        stand on a dock and teach me where it is
--   /lazy boat list | stop
-- The routes come from the Forever travel guide. The game gives no dock positions, so a dock the addon does not
-- know yet is learned from you with /lazy boat mark (it is kept for all your characters).
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

-- ports: where each one is, and the words that name it
local NODES = {
    stormwind  = { name = "Stormwind Harbour",   zones = { "Elwynn Forest", "Stormwind City" }, words = { "stormwind", "elwynn" } },
    auberdine  = { name = "Auberdine",           zones = { "Darkshore" },                       words = { "auberdine", "darkshore" } },
    rutheran   = { name = "Rut'theran Village",  zones = { "Teldrassil" },                      words = { "rutheran", "rut'theran", "darnassus", "teldrassil" },
                   note = "From Rut'theran Village take the portal up to Darnassus." },
    menethil   = { name = "Menethil Harbor",     zones = { "Wetlands" },                        words = { "menethil", "wetlands" } },
    theramore  = { name = "Theramore Isle",      zones = { "Dustwallow Marsh" },                words = { "theramore", "dustwallow" } },
    southshore = { name = "Southshore",          zones = { "Hillsbrad Foothills" },             words = { "southshore", "hillsbrad" } },
    ratchet    = { name = "Ratchet",             zones = { "The Barrens" },                     words = { "ratchet", "barrens" }, seed = "Grimble" },
    bootybay   = { name = "Booty Bay",           zones = { "Stranglethorn Vale" },              words = { "booty", "stranglethorn" }, seed = "Grizzlowe" },
    gromgol    = { name = "Grom'gol",            zones = { "Stranglethorn Vale" },              words = { "grom'gol", "gromgol", "grom" } },
    orgrimmar  = { name = "Orgrimmar zeppelin tower", zones = { "Durotar" },                    words = { "orgrimmar", "durotar" } },
    undercity  = { name = "Undercity zeppelin tower", zones = { "Tirisfal Glades" },            words = { "undercity", "tirisfal" } },
}

-- from, to, boat, side (A = Alliance, H = Horde, nil = anyone), oneWay
local EDGES = {
    { "stormwind", "auberdine", "the Stormwind Harbour boat", "A" },
    { "auberdine", "rutheran",  "The Moonspray", "A" },
    { "menethil",  "theramore", "The Lady Mehley", "A" },
    { "auberdine", "menethil",  "the Auberdine-Menethil-Southshore boat", "A", true },
    { "menethil",  "southshore", "the Auberdine-Menethil-Southshore boat", "A", true },
    { "southshore", "auberdine", "the Auberdine-Menethil-Southshore boat", "A", true },
    { "ratchet",   "bootybay",  "The Maiden's Fancy" },
    { "orgrimmar", "gromgol",   "The Iron Eagle zeppelin", "H" },
    { "undercity", "gromgol",   "the Undercity zeppelin", "H" },
    { "orgrimmar", "undercity", "the Orgrimmar-Undercity zeppelin", "H" },
}

local function Side()
    return (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
end

local function Neighbours(node)
    local out = {}
    for _, e in ipairs(EDGES) do
        if not e[4] or e[4] == Side() then
            if e[1] == node then out[#out + 1] = { to = e[2], boat = e[3] } end
            if e[2] == node and not e[5] then out[#out + 1] = { to = e[1], boat = e[3] } end
        end
    end
    return out
end

-- shortest chain of ports from a to b
local function Path(a, b)
    if a == b then return { a }, {} end
    local prev, boat, queue, seen = {}, {}, { a }, { [a] = true }
    local qi = 1
    while queue[qi] do
        local n = queue[qi]; qi = qi + 1
        for _, nb in ipairs(Neighbours(n)) do
            if not seen[nb.to] then
                seen[nb.to] = true
                prev[nb.to] = n
                boat[nb.to] = nb.boat
                if nb.to == b then
                    local path, boats, cur = {}, {}, b
                    while cur do table.insert(path, 1, cur); if prev[cur] then table.insert(boats, 1, boat[cur]) end; cur = prev[cur] end
                    return path, boats
                end
                queue[#queue + 1] = nb.to
            end
        end
    end
end

local function NodeByWord(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    for key, n in pairs(NODES) do
        for _, w in ipairs(n.words) do
            if text == w or text:find(w, 1, true) then return key end
        end
    end
end

local function ZoneName()
    local id = hbd:GetPlayerZone()
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name
end

local function NodeHere()
    local zone = ZoneName()
    if not zone then return nil end
    local found
    for key, n in pairs(NODES) do
        for _, z in ipairs(n.zones) do
            if z == zone then
                if not found or (key == "bootybay" and Side() == "A") or (key == "gromgol" and Side() == "H") then found = key end
            end
        end
    end
    return found
end

--------------------------------------------------------------------------------
-- Dock positions: taught by me, or found through Questie for a few known dock NPCs
--------------------------------------------------------------------------------
local seeds = {}
local function Docks()
    local root = addon.GetRoot()
    root.docks = root.docks or {}
    return root.docks
end

local scanning
local function ScanSeeds()
    if scanning or not (api.QuestieReady and api.QuestieReady()) then return end
    local QDB = api.GetQuestie()
    if not (QDB and QDB.NPCPointers and C_Timer and C_Timer.After) then return end
    scanning = true
    local want = {}
    for key, n in pairs(NODES) do if n.seed then want[n.seed] = key end end
    local ids = {}
    for id in pairs(QDB.NPCPointers) do ids[#ids + 1] = id end
    local i = 1
    local function step()
        local last = math.min(i + 499, #ids)
        for k = i, last do
            local name = QDB.QueryNPCSingle(ids[k], "name")
            local key = name and want[name]
            if key and not seeds[key] then
                local sp = {}
                api.AddNpcs(sp, { ids[k] })
                if sp[1] then seeds[key] = { map = sp[1].uiMapId, zx = sp[1].zx, zy = sp[1].zy } end
            end
        end
        i = last + 1
        if i <= #ids then C_Timer.After(0, step) end
    end
    step()
end

-- docks told to me directly: "from>to" = zone name and map coordinates in percent
local KNOWN = {
    ["auberdine>rutheran"] = { zone = "Darkshore", x = 33, y = 40 },       -- the boat to Teldrassil
}

local mapByName = {}
local function MapIdByName(name)
    if mapByName[name] ~= nil then return mapByName[name] or nil end
    local found
    for id = 1400, 1500 do
        local info = C_Map.GetMapInfo(id)
        if info and info.name == name then found = id; break end
    end
    mapByName[name] = found or false
    return found
end

local function DockFor(node, to)
    local d = Docks()
    local mine = d[node .. ">" .. (to or "")] or d[node]
    if mine then return mine end
    local k = KNOWN[node .. ">" .. (to or "")]
    if k then
        local map = MapIdByName(k.zone)
        if map then return { map = map, zx = k.x / 100, zy = k.y / 100 } end
    end
    return seeds[node]
end

--------------------------------------------------------------------------------
-- The trip
--------------------------------------------------------------------------------
local function Renumber(wps)
    for i, w in ipairs(wps) do
        if w.label then w.name = i .. ". " .. w.label end
    end
end

local function ClearStop()
    local wps = DB().waypoints
    local removed
    for i = #wps, 1, -1 do
        if wps[i].boat then table.remove(wps, i); removed = true end
    end
    if removed then Renumber(wps); addon:RefreshPins() end
end

local function PlaceStop(dock, label, detail)
    ClearStop()
    local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(dock.zx, dock.zy, dock.map)
    if not wx then return false end
    local wps = DB().waypoints
    table.insert(wps, 1, { name = "", label = label, boat = true, detail = detail, instance = inst, x = wx, y = wy,
                           uiMapId = dock.map, zx = dock.zx, zy = dock.zy })
    Renumber(wps)
    wps[1].name = "1. " .. label
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    return true
end

local trip   -- { path, boats, idx }

local function Show()
    if not trip then return end
    local from, to = trip.path[trip.idx], trip.path[trip.idx + 1]
    if not to then return end
    local fromName, toName = NODES[from].name, NODES[to].name
    local boat = trip.boats[trip.idx]
    local detail = string.format("Board %s to %s", boat, toName)
    local dock = DockFor(from, to)
    if dock then
        PlaceStop(dock, "Boat to " .. toName .. ": " .. fromName .. " dock", detail)
    else
        ClearStop()
        Print(string.format("I don't know where the %s dock is yet. Walk to the dock, stand on it, and type /lazy boat mark %s so I remember it.", fromName, NODES[from].words[1]))
    end
end

local function StartTrip(fromKey, toKey)
    local path, boats = Path(fromKey, toKey)
    if not path then
        Print(string.format("no boat route from %s to %s that your faction can take", NODES[fromKey].name, NODES[toKey].name))
        return
    end
    if #path == 1 then Print("you are already there"); return end
    trip = { path = path, boats = boats, idx = 1, goal = toKey }
    local names = {}
    for i, k in ipairs(path) do names[i] = NODES[k].name end
    Print("route: " .. table.concat(names, " > ") .. " (" .. table.concat(boats, ", then ") .. ")")
    if NODES[toKey].note then Print(NODES[toKey].note) end
    Show()
end

-- moved on to the next port
local function Arrived()
    if not trip then return end
    local here = NodeHere()
    if not here then return end
    for idx = trip.idx + 1, #trip.path do
        if trip.path[idx] == here then
            trip.idx = idx
            if idx == #trip.path then
                ClearStop()
                Print("arrived at " .. NODES[here].name)
                trip = nil
            else
                Show()
            end
            return
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    if not C_Timer or not C_Timer.After then return end
    if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(20, function() pcall(ScanSeeds) end) end
    C_Timer.After(3, function() pcall(Arrived) end)
end)

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd ~= "boat" and cmd ~= "boats" and cmd ~= "zeppelin" then
        if prev then return prev(self, cmd, rest) end
        return
    end
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local low = rest:lower()
    if low == "stop" or low == "off" then
        trip = nil
        ClearStop()
        Print("boat trip cancelled")
    elseif low == "list" or low == "" then
        if low == "" then
            Print("|cffffd100/lazy boat <where>|r  route and arrow to the dock, for example /lazy boat darnassus")
            Print("|cffffd100/lazy boat <from> to <where>|r  name both ends, for example /lazy boat stormwind to darnassus")
            Print("|cffffd100Adding a dock:|r stand on the dock where you board, then type |cffffd100/lazy boat mark <port>|r, for example /lazy boat mark menethil. I remember it for all your characters.")
            Print("|cffffd100/lazy boat list|r shows the docks you taught me, |cffffd100/lazy boat stop|r cancels a trip")
        end
        Print("ports: " .. (function()
            local t = {}
            for _, n in pairs(NODES) do t[#t + 1] = n.name end
            table.sort(t)
            return table.concat(t, ", ")
        end)())
        local known = {}
        for k, d in pairs(Docks()) do
            known[#known + 1] = string.format("  %s: %s %.1f, %.1f", k, MapIdByName and "" or "", d.zx * 100, d.zy * 100)
        end
        table.sort(known)
        if #known > 0 then
            Print("docks you taught me (share these in a GitHub issue to help everyone):")
            for _, line in ipairs(known) do Print(line) end
        else
            Print("no docks taught yet")
        end
        Print("use /lazy boat <where>, for example /lazy boat darnassus")
        Print("to teach me a dock: stand on it, then type /lazy boat mark <port>, for example /lazy boat mark menethil")
    elseif low:match("^mark") then
        local arg = low:gsub("^mark%s*", "")
        local key = arg ~= "" and NodeByWord(arg) or NodeHere()
        local zx, zy, map = hbd:GetPlayerZonePosition()
        if not key then Print("tell me which port: /lazy boat mark auberdine"); return true end
        if not zx then Print("I can't read your position here"); return true end
        Docks()[key] = { map = map, zx = zx, zy = zy }
        Print(string.format("remembered the %s dock at %.1f, %.1f", NODES[key].name, zx * 100, zy * 100))
        if trip then Show() end
    else
        local a, b = low:match("^(.-)%s+to%s+(.+)$")
        local fromKey, toKey
        if a then
            fromKey, toKey = NodeByWord(a), NodeByWord(b)
        else
            toKey = NodeByWord(low)
            fromKey = NodeHere()
        end
        if not toKey then Print("I don't know that place. /lazy boat list shows the ports"); return true end
        if not fromKey then Print("stand in the zone of a port, or say where from: /lazy boat stormwind to darnassus"); return true end
        StartTrip(fromKey, toKey)
    end
    return true
end
