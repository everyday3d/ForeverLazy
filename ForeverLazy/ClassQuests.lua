-- Class quests: finds the quests only your class can take, tells you when a new one opens up, and puts the
-- giver in your plan when you are in the zone they are in.
--   /lazy class            class quests you can take now, and the ones coming in the next few levels
--   /lazy class go [n]     waypoint on the giver
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
            if ok and api.IsDungeonQuest and api.IsDungeonQuest(id, false) then ok = false end   -- a dungeon quest: not for the plan
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
    if not addon.ModuleOn("classq") then return out end
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
    if #shown > 0 then Print("/lazy class go 1  puts a waypoint on the first giver") end
end

local function Go(arg)
    if #shown == 0 then Show() end
    local q = shown[tonumber(arg) or 1]
    if not q then Print("no such class quest, try /lazy class first"); return end
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
    if not list or not db or not addon.ModuleOn("classq") then return end
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
    if #fresh > 0 then Print("/lazy class lists them, /lazy class go puts a waypoint on the giver") end
end

OnReady = function()
    local seen = Seen()
    if not next(seen) then Announce(true) end        -- first run: what is already open is not news
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, event)
    if not C_Timer or not C_Timer.After then return end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(12, function() pcall(Scan) end)
    else
        C_Timer.After(4, function() pcall(function() if not list then Scan() else Announce() end end) end)
    end
end)

--------------------------------------------------------------------------------
-- Walking into a zone that has something for a class quest: say so once
--------------------------------------------------------------------------------
local toast
local lastZone

local function ClassSet()
    local set = {}
    for _, id in ipairs(list or {}) do set[id] = true end
    return set
end

-- is this one of my class quests?
function addon.IsClassQuestId(id)
    if not list then return false end
    return ClassSet()[id] and true or false
end

-- the id of a class quest by its title (for plan stops that only carry a name)
local titleToId
function addon.ClassQuestIdByTitle(title)
    if not list then return nil end
    if not titleToId then
        titleToId = {}
        local QDB = api.GetQuestie()
        if QDB then
            for _, id in ipairs(list) do
                local n = QDB.QueryQuestSingle(id, "name")
                if n then titleToId[n:lower()] = id end
            end
        end
    end
    return titleToId[(title or ""):lower()]
end

-- what my class quests need in this zone: who to take quests from, and the objectives or hand-ins of quests in my log.
-- each entry: { text = one line saying what, from whom and where, spawn, label }
local function NpcNameOf(QDB, list)
    local id = type(list) == "table" and list[1]       -- the first npc id of a start/finish list
    return id and QDB.QueryNPCSingle(id, "name") or nil
end

local function HereNeeds(zoneId)
    local out = {}
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return out end
    local from = { x = px, y = py }
    local QDB = api.GetQuestie()
    if not QDB then return out end
    -- quests I can take now, with the giver in this zone
    for _, q in ipairs(Quests(true)) do
        local best, bd
        for _, s in ipairs(q.spawns) do
            if s.instance == pinst and s.uiMapId == zoneId then
                local d = Dist(s, from)
                if not bd or d < bd then best, bd = s, d end
            end
        end
        if best then
            out[#out + 1] = {
                text = string.format("Take: %s (level %d)\n     from %s at %.0f, %.0f, about %d yards",
                    q.name, q.level or 0, q.npc or "the quest giver", best.zx * 100, best.zy * 100, bd),
                spawn = best, label = "Class quest: " .. q.name }
        end
    end
    -- quests already in my log
    if addon.QuestLogSpawns then
        local set = ClassSet()
        for _, g in ipairs(addon.QuestLogSpawns()) do
            if g.id and set[g.id] and (g.complete or not (api.IsDungeonQuest and api.IsDungeonQuest(g.id, false))) then
                local best, bd
                for _, s in ipairs(g.spawns) do
                    if s.instance == pinst and s.uiMapId == zoneId then
                        local d = Dist(s, from)
                        if not bd or d < bd then best, bd = s, d end
                    end
                end
                if best then
                    local name = (g.label or ""):gsub("^Turn in: ", "")
                    local text
                    if g.complete then
                        local npc = NpcNameOf(QDB, QDB.QueryQuestSingle(g.id, "finishedBy") and QDB.QueryQuestSingle(g.id, "finishedBy")[1])
                        text = string.format("Hand in: %s\n     to %s at %.0f, %.0f, about %d yards",
                            name, npc or "the quest giver", best.zx * 100, best.zy * 100, bd)
                    else
                        text = string.format("Do: %s\n     the nearest spot is at %.0f, %.0f, about %d yards",
                            name, best.zx * 100, best.zy * 100, bd)
                    end
                    out[#out + 1] = { text = text, spawn = best, label = g.label }
                end
            end
        end
    end
    return out
end
local function ShowToast(zoneId, needs)
    if not toast then
        local f = CreateFrame("Frame", "ForeverLazy_ClassToast", UIParent)
        f:SetSize(420, 150)
        f:SetPoint("TOP", 0, -270)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -12); f.title:SetWidth(400)
        f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.body:SetPoint("TOP", f.title, "BOTTOM", 0, -8); f.body:SetWidth(396); f.body:SetJustifyH("LEFT")
        local show = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        show:SetSize(130, 22); show:SetPoint("BOTTOMLEFT", 16, 12); show:SetText("Show me")
        show:SetScript("OnClick", function()
            f:Hide()
            local n = f.needs and f.needs[1]
            if n and n.spawn and n.spawn.uiMapId then
                addon:AddWaypointZone(n.spawn.uiMapId, n.spawn.zx, n.spawn.zy, n.label or n.text)
                local w = DB().waypoints[1]
                if w then w.guard = true end          -- like a guard's directions: the arrow goes away when I get there
            end
        end)
        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetSize(90, 22); close:SetPoint("LEFT", show, "RIGHT", 8, 0); close:SetText("Close")
        close:SetScript("OnClick", function() f:Hide() end)
        f:Hide()
        toast = f
    end
    toast.needs = needs
    toast.title:SetText("Class quest in " .. MapName(zoneId))
    local lines = {}
    for i, n in ipairs(needs) do
        if i > 4 then lines[#lines + 1] = string.format("...and %d more", #needs - 4); break end
        lines[#lines + 1] = n.text
    end
    toast.body:SetText(table.concat(lines, "\n"))
    toast:SetHeight(math.max(110, 78 + toast.body:GetStringHeight()))
    toast:Show()
    if C_Timer then
        local mine = zoneId
        C_Timer.After(40, function() if toast and toast:IsShown() and toast.needs == needs then toast:Hide() end end)
    end
end

local function CheckZone()
    local db = DB()
    if not db or db.classZoneAlert == false or not addon.ModuleOn("classq") then return end
    local zoneId = hbd:GetPlayerZone()
    if not zoneId or zoneId == lastZone then return end
    lastZone = zoneId
    if toast then toast:Hide() end
    if not list then Scan(); return end
    if UnitOnTaxi and UnitOnTaxi("player") then lastZone = nil; return end        -- still flying: ask again when I land
    if IsInInstance and IsInInstance() then return end
    local needs = HereNeeds(zoneId)
    if #needs > 0 then ShowToast(zoneId, needs) end
end

-- /lazy class here: exactly what my class quests need in this zone, any time
function addon.ClassHere()
    if not list then Scan(); Print("looking up your class quests, try again in a moment"); return end
    local zoneId = hbd:GetPlayerZone()
    if not zoneId then Print("can't tell which zone you are in"); return end
    local needs = HereNeeds(zoneId)
    if #needs == 0 then Print("your class quests need nothing in " .. MapName(zoneId)); return end
    ShowToast(zoneId, needs)
end

--------------------------------------------------------------------------------
-- /lazy class quest: every class quest I have, can take or will soon, and what to do for each
--------------------------------------------------------------------------------
local cwin, crows = nil, {}

local function ObjectiveLines(QDB, id)
    local lines = {}
    -- what the game says about my progress, when the quest is in my log
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
        if ok and type(objs) == "table" then
            for _, o in ipairs(objs) do
                if o.text and o.text ~= "" then lines[#lines + 1] = (o.finished and "|cff55ff55done:|r " or "") .. o.text end
            end
        end
    end
    if #lines == 0 then
        local t = QDB.QueryQuestSingle(id, "objectivesText")
        if type(t) == "table" then
            for _, s in ipairs(t) do if type(s) == "string" and s ~= "" then lines[#lines + 1] = s end end
        elseif type(t) == "string" and t ~= "" then
            lines[1] = t
        end
    end
    return lines
end

local function ClassEntries()
    local out = {}
    local QDB = api.GetQuestie()
    if not (QDB and list) then return out end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local from = px and { x = px, y = py }
    local function Nearest2(spawns)
        local best, bd
        for _, s in ipairs(spawns or {}) do
            local d = (from and s.instance == pinst) and Dist(s, from) or nil
            if not best or (d and (not bd or d < bd)) then best, bd = s, d end
        end
        return best, bd
    end
    local function Place(s, d)
        if not s then return "location unknown" end
        return string.format("%s %.0f, %.0f%s", MapName(s.uiMapId), s.zx * 100, s.zy * 100, d and string.format(", about %d yards", d) or "")
    end
    local set = ClassSet()
    -- 1. in my log
    if addon.QuestLogSpawns then
        for _, g in ipairs(addon.QuestLogSpawns()) do
            if g.id and set[g.id] and (g.complete or not (api.IsDungeonQuest and api.IsDungeonQuest(g.id, false))) then
                local s, d = Nearest2(g.spawns)
                local name = (g.label or ""):gsub("^Turn in: ", "")
                local body
                if g.complete then
                    local by = QDB.QueryQuestSingle(g.id, "finishedBy")
                    local npc = by and by[1] and by[1][1] and QDB.QueryNPCSingle(by[1][1], "name")
                    body = "Finished. Hand it in to " .. (npc or "the quest giver") .. " at " .. Place(s, d)
                else
                    local lines = ObjectiveLines(QDB, g.id)
                    body = (#lines > 0 and table.concat(lines, "\n") or "No objective text found.") .. "\nNearest spot: " .. Place(s, d)
                end
                out[#out + 1] = { title = name .. (g.complete and "  (ready to hand in)" or "  (in your quest log)"), body = body,
                                  spawn = s, label = g.label, rank = 1 }
            end
        end
    end
    -- 2. I can take them now, and 3. soon
    for pass = 1, 2 do
        for _, q in ipairs(Quests(pass == 1)) do
            local s, d = Nearest2(q.spawns)
            local lines = ObjectiveLines(QDB, q.id)
            local body = (#lines > 0 and (table.concat(lines, "\n") .. "\n") or "")
                .. "Get it from " .. (q.npc or "the quest giver") .. " at " .. Place(s, d)
            if pass == 2 then body = "Opens at level " .. q.need .. ".\n" .. body end
            out[#out + 1] = { title = q.name .. string.format("  (level %d, %s)", q.level or 0, pass == 1 and "you can take it now" or "coming soon"),
                              body = body, spawn = s, label = "Class quest: " .. q.name, rank = pass + 1 }
        end
    end
    table.sort(out, function(a, b) return a.rank < b.rank end)
    return out
end

function addon.ClassWindow()
    if not list then Scan(); Print("looking up your class quests, try again in a moment"); return end
    if not cwin then
        local f = CreateFrame("Frame", "ForeverLazy_ClassWindow", UIParent)
        f:SetSize(520, 460)
        f:SetPoint("CENTER", 0, 30)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.title:SetText("Your class quests")
        f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.empty:SetPoint("TOPLEFT", 16, -56); f.empty:SetWidth(480); f.empty:SetJustifyH("LEFT")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", "ForeverLazy_ClassWindowScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -50); scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        f.content = CreateFrame("Frame", nil, scroll)
        f.content:SetSize(460, 10)
        scroll:SetScrollChild(f.content)
        table.insert(UISpecialFrames, "ForeverLazy_ClassWindow")
        f:Hide()
        cwin = f
    end
    local scale = math.min(2.6, math.max(0.8, tonumber(DB().guideScale) or 1))
    cwin:SetScale(scale)
    for _, r in ipairs(crows) do r.title:Hide(); r.body:Hide(); r.btn:Hide() end
    local entries = ClassEntries()
    cwin.empty:SetText(#entries == 0 and "No class quests in your log, open to you now, or coming in the next few levels." or "")
    local y = 0
    for i, e in ipairs(entries) do
        local r = crows[i]
        if not r then
            r = {}
            r.title = cwin.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            r.title:SetJustifyH("LEFT")
            r.body = cwin.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.body:SetJustifyH("LEFT")
            r.btn = CreateFrame("Button", nil, cwin.content, "UIPanelButtonTemplate")
            r.btn:SetSize(120, 22)
            crows[i] = r
        end
        r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", cwin.content, "TOPLEFT", 0, -y)
        r.title:SetWidth(450); r.title:SetText((e.rank == 1 and "|cff55ff55" or "") .. e.title .. (e.rank == 1 and "|r" or "")); r.title:Show()
        y = y + math.max(22, r.title:GetStringHeight()) + 4
        r.body:ClearAllPoints(); r.body:SetPoint("TOPLEFT", cwin.content, "TOPLEFT", 8, -y)
        r.body:SetWidth(440); r.body:SetText(e.body); r.body:Show()
        y = y + r.body:GetStringHeight() + 6
        r.btn:ClearAllPoints(); r.btn:SetPoint("TOPLEFT", cwin.content, "TOPLEFT", 8, -y)
        r.btn:SetText("Show me")
        r.btn:SetScript("OnClick", function()
            cwin:Hide()
            if e.spawn and e.spawn.uiMapId then
                addon:AddWaypointZone(e.spawn.uiMapId, e.spawn.zx, e.spawn.zy, e.label or e.title)
                local w = DB().waypoints[1]
                if w then w.guard = true end
            end
        end)
        r.btn:Show()
        y = y + 40
    end
    cwin.content:SetHeight(math.max(y, 40))
    cwin:Show()
end

local zoneEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do pcall(zoneEv.RegisterEvent, zoneEv, e) end
zoneEv:SetScript("OnEvent", function()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(4, function() pcall(CheckZone) end)
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd == "class" then
        local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
        if sub == "go" then Go(arg)
        elseif sub == "here" or sub == "zone" then addon.ClassHere()
        elseif sub == "list" or sub == "chat" then Show()
        else addon.ClassWindow() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["ClassQuests.lua"] = true end end
