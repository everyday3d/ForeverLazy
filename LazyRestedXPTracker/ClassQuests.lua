-- Class quests: finds the quests only your class can take, tells you when a new one opens up, and puts the
-- giver in your plan when you are in the zone they are in.
--   /lrxp class            class quests you can take now, and the ones coming in the next few levels
--   /lrxp class go [n]     waypoint on the giver
-- Everything comes from Questie's database (quests that need your class).
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end
local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function Mod(name)
    local ql = _G.QuestieLoader
    if not ql then return nil end
    local ok, m = pcall(ql.ImportModule, ql, name)
    return ok and m or nil
end

local function HasClass(mask)
    local P = Mod("QuestiePlayer")
    if P and P.HasRequiredClass then return P.HasRequiredClass(mask) and true or false end
    local id = select(3, UnitClass("player")) or 1
    return (mask % (2 ^ id)) >= (2 ^ (id - 1))
end

local function HasRace(mask)
    if not mask or mask == 0 then return true end
    local P = Mod("QuestiePlayer")
    if P and P.HasRequiredRace then return P.HasRequiredRace(mask) and true or false end
    return true
end

--------------------------------------------------------------------------------
-- Find them all once (a few hundred quests per frame so the game does not hitch)
--------------------------------------------------------------------------------
local list          -- ids of every quest that needs my class
local scanning

local function QuestXP(id)
    local XP = Mod("QuestXP")
    if XP and XP.GetQuestLogRewardXP then
        local ok, xp = pcall(XP.GetQuestLogRewardXP, XP, id, false)
        if ok and tonumber(xp) then return tonumber(xp) end
    end
    return 0
end

local OnReady

local function Scan()
    if list or scanning then return end
    if not (api.QuestieReady and api.QuestieReady()) then return end
    local QDB = api.GetQuestie()
    if not (QDB and QDB.QuestPointers and C_Timer and C_Timer.After) then return end
    scanning = true
    local ids = {}
    for id in pairs(QDB.QuestPointers) do ids[#ids + 1] = id end
    local i, found = 1, {}
    local function step()
        local last = math.min(i + 399, #ids)
        for k = i, last do
            local id = ids[k]
            local mask = QDB.QueryQuestSingle(id, "requiredClasses")
            if mask and mask ~= 0 and HasClass(mask) then found[#found + 1] = id end
        end
        i = last + 1
        if i <= #ids then
            C_Timer.After(0, step)
        else
            list, scanning = found, false
            if OnReady then OnReady() end
        end
    end
    step()
end

--------------------------------------------------------------------------------
-- What can I take, what is coming
--------------------------------------------------------------------------------
local function InLog()
    local set = {}
    if api.ReadQuestLog then for _, q in ipairs(api.ReadQuestLog()) do set[q.id] = true end end
    return set
end

local function Completed(id)
    local Q = _G.Questie
    return Q and Q.db and Q.db.char and Q.db.char.complete and Q.db.char.complete[id] and true or false
end

local function Giver(QDB, id)
    local by = QDB.QueryQuestSingle(id, "startedBy")
    local spawns, npcName = {}, nil
    if by then
        api.AddNpcs(spawns, by[1]); api.AddObjects(spawns, by[2])
        if by[1] and by[1][1] then npcName = QDB.QueryNPCSingle(by[1][1], "name") end
    end
    return spawns, npcName
end

-- { id, name, level, need, npc, spawns } for quests I can take now (now = true) or soon (now = false)
local function Quests(now)
    local out = {}
    if not list then return out end
    local QDB = api.GetQuestie()
    local lvl = UnitLevel("player") or 1
    local log = InLog()
    for _, id in ipairs(list) do
        if not log[id] and not Completed(id) then
            local need = QDB.QueryQuestSingle(id, "requiredLevel") or 0
            local ok = false
            if now then
                -- Questie's "doable" does not check my level, so do that here
                if need <= lvl then
                    local okd, doable = pcall(QDB.IsDoable, id)
                    ok = okd and doable and true or false
                end
            else
                ok = need > lvl and need <= lvl + 4 and HasRace(QDB.QueryQuestSingle(id, "requiredRaces"))
            end
            if ok then
                local spawns, npc = Giver(QDB, id)
                if #spawns > 0 then
                    out[#out + 1] = { id = id, name = QDB.QueryQuestSingle(id, "name") or ("quest " .. id),
                                      level = QDB.QueryQuestSingle(id, "questLevel") or need, need = need,
                                      npc = npc, spawns = spawns }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.need < b.need end)
    return out
end

-- for the route planner: quests I can take now whose giver is in this zone
function api.ClassGivers(zoneId, pinst, from)
    local out = {}
    for _, q in ipairs(Quests(true)) do
        local here, near, nearSpawn = {}, nil, nil
        for _, s in ipairs(q.spawns) do
            if s.instance == pinst and s.uiMapId == zoneId then
                here[#here + 1] = s
                local d = Dist(s, from)
                if not near or d < near then near, nearSpawn = d, s end
            end
        end
        if #here > 0 then
            local xp = QuestXP(q.id)
            if xp <= 0 then xp = 40 + 10 * (q.level or 1) end
            out[#out + 1] = { id = q.id, label = "Class quest: " .. q.name, xp = xp, spawns = here,
                              near = near, nearSpawn = nearSpawn, level = q.level }
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Announce new ones, list them, go to them
--------------------------------------------------------------------------------
local function MapName(id)
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or "?"
end

local function Nearest(spawns)
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local best, bd
    for _, s in ipairs(spawns) do
        local d = (px and s.instance == pinst) and Dist(s, { x = px, y = py }) or nil
        if not best or (d and (not bd or d < bd)) then best, bd = s, d end
    end
    return best, bd
end

local function Where(q)
    local s, d = Nearest(q.spawns)
    if not s then return "location unknown" end
    return string.format("%s%s %.0f, %.0f%s", q.npc and (q.npc .. ", ") or "", MapName(s.uiMapId), s.zx * 100, s.zy * 100,
        d and string.format(" (about %d yards)", d) or "")
end

local shown = {}
local function Show()
    if not list then
        Scan()
        Print("looking up your class quests, try again in a moment")
        return
    end
    shown = {}
    local now, soon = Quests(true), Quests(false)
    if #now == 0 then
        Print("no class quests open to you right now")
    else
        Print("class quests you can take now:")
        for _, q in ipairs(now) do
            shown[#shown + 1] = q
            Print(string.format("  %d. %s (level %d) - %s", #shown, q.name, q.level or 0, Where(q)))
        end
    end
    if #soon > 0 then
        Print("coming in the next few levels:")
        for i, q in ipairs(soon) do
            if i > 6 then break end
            shown[#shown + 1] = q
            Print(string.format("  %d. %s (from level %d) - %s", #shown, q.name, q.need, Where(q)))
        end
    end
    if #shown > 0 then Print("/lrxp class go 1  puts a waypoint on the first giver") end
end

local function Go(arg)
    if #shown == 0 then Show() end
    local q = shown[tonumber(arg) or 1]
    if not q then Print("no such class quest, try /lrxp class first"); return end
    local s = Nearest(q.spawns)
    if not s then return end
    addon:AddWaypointZone(s.uiMapId, s.zx, s.zy, "Class quest: " .. q.name)
end

local function Seen()
    local root = addon.GetRoot()
    root.classSeen = root.classSeen or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    root.classSeen[key] = root.classSeen[key] or {}
    return root.classSeen[key]
end

local function Announce(silent)
    local db = DB()
    if not list or not db then return end
    local seen = Seen()
    local fresh = {}
    for _, q in ipairs(Quests(true)) do
        if not seen[q.id] then
            seen[q.id] = true
            fresh[#fresh + 1] = q
        end
    end
    if silent or db.classAlert == false then return end
    for i, q in ipairs(fresh) do
        if i > 3 then break end
        Print(string.format("new class quest: %s (level %d) - %s", q.name, q.level or 0, Where(q)))
    end
    if #fresh > 0 then Print("/lrxp class lists them, /lrxp class go puts a waypoint on the giver") end
end

OnReady = function()
    local seen = Seen()
    if not next(seen) then Announce(true) end        -- first run: what is already open is not news
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, event)
    if not C_Timer or not C_Timer.After then return end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(12, function() pcall(Scan) end)
    else
        C_Timer.After(4, function() pcall(function() if not list then Scan() else Announce() end end) end)
    end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd == "class" then
        local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
        if sub == "go" then Go(arg) else Show() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end
