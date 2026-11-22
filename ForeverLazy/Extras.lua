-- Extras for Forever Lazy:
--   own quest log arrow, waypoint routes, waypoint sharing, import/export,
--   compass bar, minimap menu, named profiles, friend switching, self-test.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local hbd = api.hbd
local state = addon.state
local Print = addon.Print

local function DB() return addon.GetDB() end

--------------------------------------------------------------------------------
-- Own quest log arrow
--------------------------------------------------------------------------------
local mine = { groups = {}, chosen = nil, dirty = true, lastBuild = 0, lastPick = 0 }
local mineArrow

local function ReadQuestLog()
    local out = {}
    local zone                       -- the zone header the quest sits under in the log
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and info.isHeader then zone = info.title end
            if info and not info.isHeader and info.questID then
                local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                local watched = false
                if C_QuestLog.GetQuestWatchType then
                    watched = C_QuestLog.GetQuestWatchType(info.questID) ~= nil
                elseif C_QuestLog.IsQuestWatched then
                    watched = C_QuestLog.IsQuestWatched(info.questID) and true or false
                end
                out[#out + 1] = { id = info.questID, title = info.title or "Quest", complete = done and true or false,
                                  watched = watched, level = info.level, group = info.suggestedGroup, zone = zone }
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local n = GetNumQuestLogEntries()
        for i = 1, n do
            local title, qLevel, suggested, isHeader, _, isComplete, _, questId = GetQuestLogTitle(i)
            if title and isHeader then zone = title end
            if title and not isHeader and questId then
                local watched = IsQuestWatched and IsQuestWatched(i) and true or false
                out[#out + 1] = { id = questId, title = title, complete = (isComplete == 1 or isComplete == true),
                                  watched = watched, level = qLevel, group = tonumber(suggested), zone = zone }
            end
        end
    end
    return out
end
api.ReadQuestLog = ReadQuestLog

local BuildGroup

-- the wording of the objectives I have not finished yet (lower case), or nil when the game does not say
local function UnfinishedTexts(id)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
    if not ok or type(objs) ~= "table" or #objs == 0 then return nil end
    local out = {}
    for _, o in ipairs(objs) do
        if not o.finished and o.text then out[#out + 1] = o.text:lower() end
    end
    return out
end

-- does this NPC, object or item belong to one of the open objectives? (matching on its name or its longer words)
local function MatchesOpen(open, name)
    if not open or #open == 0 or not name then return true end
    local n = name:lower()
    for _, t in ipairs(open) do
        if t:find(n, 1, true) then return true end
        for word in n:gmatch("%a+") do
            if #word >= 5 and t:find(word, 1, true) then return true end
        end
    end
    return false
end

-- Quest colour like the quest log: grey (too low), green, yellow, orange, red (too high)
local function Tier(level, grey)
    if grey then return "grey" end
    if not level or level <= 0 then return "yellow" end
    local diff = level - (UnitLevel("player") or 1)
    if diff >= 5 then return "red" elseif diff >= 3 then return "orange" elseif diff >= -2 then return "yellow" end
    return "green"
end

-- Arrows only go to quests worth doing: green, yellow and orange ones. Red ones only once they
-- are finished (a turn-in). Grey ones never.
local function Wanted(g, keepGrey)
    if DB().questColorFilter == false then return true end
    if g.tier == "grey" then return keepGrey and true or false end
    if g.complete then return true end
    return g.tier ~= "red"      -- green, yellow and orange are fine; red only as a turn-in
end

local function RebuildMine(keepGrey)
    mine.groups = {}
    mine.chosen = nil
    mine.skipped = 0
    if not api.QuestieReady() then return false end
    for _, q in ipairs(ReadQuestLog()) do
        local g = BuildGroup(q)
        if #g.spawns > 0 then
            if not g.complete and g.id and api.IsDungeonQuest and api.IsDungeonQuest(g.id, false) then
                -- a dungeon quest: no arrow to it, neither my quest arrow nor the plan
            elseif Wanted(g, keepGrey) then mine.groups[#mine.groups + 1] = g else mine.skipped = mine.skipped + 1 end
        end
    end
    return true
end

-- for other files: my quest log as groups with their spots (objectives, or the hand-in when finished)
function addon.QuestLogSpawns()
    local out = {}
    if not api.QuestieReady() then return out end
    for _, q in ipairs(ReadQuestLog()) do
        local ok, g = pcall(BuildGroup, q)
        if ok and g and #g.spawns > 0 then out[#out + 1] = g end
    end
    return out
end

-- XP a quest gives me now (Questie's own table, already scaled for my level), and whether it is grey
local function QuestXPNow(id)
    return ns.data.QuestXP(id)

end

local function IsGrey(QDB, level)
    if not level or level <= 0 then return false end
    if QDB.IsTrivial then
        local ok, r = pcall(QDB.IsTrivial, level)
        if ok then return r and true or false end
    end
    local range = GetQuestGreenRange and GetQuestGreenRange() or 8
    return level < (UnitLevel("player") or 80) - range
end

function BuildGroup(q)
    local QDB = api.GetQuestie()
    do
        local level = q.level
        if not level or level == 0 then level = QDB.QueryQuestSingle(q.id, "questLevel") end
        local g = { label = (q.complete and "Turn in: " or "") .. q.title, spawns = {}, complete = q.complete,
                    id = q.id, watched = q.watched, level = level, group = q.group,
                    xp = QuestXPNow(q.id), grey = IsGrey(QDB, level) }
        g.tier = Tier(level, g.grey)
        if q.complete then
            local by = QDB.QueryQuestSingle(q.id, "finishedBy")
            if by then api.AddNpcs(g.spawns, by[1]); api.AddObjects(g.spawns, by[2]) end
        else
            local obj = QDB.QueryQuestSingle(q.id, "objectives")
            if type(obj) == "table" then
                -- only the objectives still open count: a quest that says "talk to A, then B" points at B once A is done
                local open = UnfinishedTexts(q.id)
                local function pick(list, nameOf)
                    local all, keep = {}, {}
                    for _, c in pairs(list or {}) do
                        if c[1] then
                            all[#all + 1] = c[1]
                            if MatchesOpen(open, nameOf(c[1])) then keep[#keep + 1] = c[1] end
                        end
                    end
                    if #keep > 0 then return keep end
                    return all
                end
                -- each spawn remembers which objective it belongs to, so a stop can say what to do there
                local function tag(n0, name)
                    for i = n0 + 1, #g.spawns do g.spawns[i].src = name end
                end
                for _, id in ipairs(pick(obj[1], function(i) return QDB.QueryNPCSingle(i, "name") end)) do
                    local n0 = #g.spawns
                    api.AddNpcs(g.spawns, { id })
                    tag(n0, QDB.QueryNPCSingle(id, "name"))
                end
                for _, id in ipairs(pick(obj[2], function(i) return QDB.QueryObjectSingle(i, "name") end)) do
                    local n0 = #g.spawns
                    api.AddObjects(g.spawns, { id })
                    tag(n0, QDB.QueryObjectSingle(id, "name"))
                end
                for _, id in ipairs(pick(obj[3], function(i) return QDB.QueryItemSingle(i, "name") end)) do
                    local n0 = #g.spawns
                    api.AddItemSources(g.spawns, id)
                    tag(n0, QDB.QueryItemSingle(id, "name"))
                end
            end
            local te = QDB.QueryQuestSingle(q.id, "triggerEnd")
            if type(te) == "table" and te[2] then api.AddSpawns(g.spawns, te[2]) end
            -- where the objective was really done (mine and other players', from the Hive): when it is well known it
            -- replaces Questie's spawn points, which were made for the original game; a few sightings are added to them
            if addon.HiveQuestSpots and DB().hiveSpots ~= false then
                local ok, spots, total = pcall(addon.HiveQuestSpots, q.id)
                if ok and spots and #spots > 0 then
                    -- the learned places only take over when I am near enough to them to be doing the quest there;
                    -- from far away they are added next to Questie's, so a closer spawn is never thrown out
                    local nearLearned = false
                    local px, py, pinst = hbd:GetPlayerWorldPosition()
                    if px then
                        for _, s in ipairs(spots) do
                            if s.instance == pinst and api.D2(s.x, s.y, px, py) <= 1500 * 1500 then nearLearned = true; break end
                        end
                    end
                    if total >= 4 and nearLearned then
                        g.spawns = spots
                    else
                        for _, s in ipairs(spots) do g.spawns[#g.spawns + 1] = s end
                    end
                end
            end
        end
        return g
    end
end

-- the quest I have picked: super-tracked first, else the one selected in the quest log
local function SelectedQuestId()
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local id = C_SuperTrack.GetSuperTrackedQuestID()
        if id and id ~= 0 then return id end
    end
    if GetQuestLogSelection and GetQuestLogTitle then
        local i = GetQuestLogSelection()
        if i and i > 0 then
            local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not isHeader and id and id ~= 0 then return id end
        end
    end
    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        local id = C_QuestLog.GetSelectedQuest()
        if id and id ~= 0 then return id end
    end
end

local function PickMine()
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local best, bd

    -- narrow down to the quest I picked, or to my tracked quests
    local groups = mine.groups
    if DB().ownFocus ~= false then
        local sel = SelectedQuestId()
        local narrowed
        if sel then
            narrowed = {}
            for _, g in ipairs(groups) do if g.id == sel then narrowed[#narrowed + 1] = g end end
        end
        if not narrowed or #narrowed == 0 then
            narrowed = {}
            for _, g in ipairs(groups) do if g.watched then narrowed[#narrowed + 1] = g end end
        end
        if #narrowed > 0 then groups = narrowed end
    end

    for _, g in ipairs(groups) do
        for _, s in ipairs(g.spawns) do
            local d = (px and s.instance == pinst) and api.D2(s.x, s.y, px, py) or 1e18
            -- prefer finished quests a little (turn-ins are quick wins)
            if g.complete then d = d * 0.5 end
            if not bd or d < bd then best, bd = { label = g.label, spawn = s }, d end
        end
    end
    mine.chosen = best
end

local questEvents = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
                     "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE" }) do
    pcall(questEvents.RegisterEvent, questEvents, e)
end
questEvents:SetScript("OnEvent", function() mine.dirty = true end)

local mineTimer = 0
local function UpdateMine(dt)
    local db = DB()
    if not db or not mineArrow then return end
    mineTimer = mineTimer + dt
    if mineTimer < 0.1 then return end
    mineTimer = 0
    local mode = db.mode
    if not db.ownQuests or mode == "off" or api.ShouldHide() then mineArrow:Hide(); return end
    local now = GetTime()
    if mine.dirty and now - mine.lastBuild > 2 then
        if RebuildMine() then mine.dirty = false end
        mine.lastBuild = now
        mine.lastPick = 0
    end
    if now - mine.lastPick > 0.5 then PickMine(); mine.lastPick = now end
    if db.simpleArrows ~= false then mineArrow:Hide(); return end
    mineArrow:Show()
    mineArrow:SetAlpha(db.alpha)
    if not api.QuestieReady() then
        mineArrow.arrow:Hide(); mineArrow.title:SetText("My quests need Questie"); mineArrow.sub:SetText("")
        return
    end
    if not mine.chosen then
        mineArrow.arrow:Hide(); mineArrow.title:SetText("No quest spots found"); mineArrow.sub:SetText("")
        return
    end
    api.PointAt(mineArrow, mine.chosen.spawn.instance, mine.chosen.spawn.x, mine.chosen.spawn.y, mine.chosen.label)
end

--------------------------------------------------------------------------------
-- Compass bar
--------------------------------------------------------------------------------
local compass
local function MakeCompass()
    local f = CreateFrame("Frame", "ForeverLazy_Compass", UIParent)
    f:SetSize(360, 18)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not DB().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        DB().pos.compass = { point = point, x = x, y = y }
    end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.45)
    local tick = f:CreateTexture(nil, "ARTWORK")
    tick:SetSize(2, 18); tick:SetPoint("CENTER"); tick:SetColorTexture(1, 1, 1, 0.5)
    f.markers = {}
    for i = 1, 8 do
        local m = CreateFrame("Frame", nil, f)
        m:SetSize(10, 18)
        m.tex = m:CreateTexture(nil, "OVERLAY")
        m.tex:SetAllPoints()
        m.icon = m:CreateTexture(nil, "OVERLAY")
        m.icon:SetSize(16, 16)
        m.icon:SetPoint("CENTER")
        m.icon:Hide()
        m.letter = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        m.letter:SetPoint("CENTER", 0, 0)
        m.letter:SetShadowOffset(1, -1)
        m:Hide()
        f.markers[i] = m
    end
    f:Hide()
    return f
end

-- the marker my partner gets on the compass (raid target icons: 1 star, 2 circle, 3 diamond, 4 triangle, 5 moon)
local function PartnerIcon() return (DB() and DB().compassIcon) or 3 end

local function CompassSources()
    local db = DB()
    local out = {}
    local mode = db.mode
    if mode == "quest" or mode == "both" then
        for i, c in ipairs(state.chosen) do
            if i == 1 or i <= 1 + db.extraTargets then
                out[#out + 1] = { c.spawn.instance, c.spawn.x, c.spawn.y, db.colorQuest }
            end
        end
    end
    if mode == "friend" or mode == "both" then
        local lk = state.lastKnown
        if lk and GetTime() - lk.t < 3 then out[#out + 1] = { lk.instance, lk.x, lk.y, db.colorFriend, nil, 4 } end
    end
    -- the person I follow with the purple arrow
    local fp = addon.FollowPosition and addon.FollowPosition()
    if fp and addon.ModuleOn("follow") and GetTime() - fp.t < 3 then out[#out + 1] = { fp.instance, fp.x, fp.y, { 0.85, 0.5, 1 }, nil, PartnerIcon() } end
    local wp = db.waypoints[1]
    if wp then out[#out + 1] = { wp.instance, wp.x, wp.y, db.colorWaypoint } end
    if db.ownQuests and mine.chosen then
        out[#out + 1] = { mine.chosen.spawn.instance, mine.chosen.spawn.x, mine.chosen.spawn.y, db.colorMine }
    end
    return out
end

-- simple arrows: with no plan stop, the one main arrow points at the friend's quest target, else my own quest
function addon.SimpleTarget()
    local db = DB()
    if not db then return nil end
    if db.rxpListen == true and (db.mode == "quest" or db.mode == "both") and state.chosen and state.chosen[1] then
        local c = state.chosen[1]
        return { instance = c.spawn.instance, x = c.spawn.x, y = c.spawn.y, name = c.label }
    end
    if db.ownQuests and mine.chosen then
        return { instance = mine.chosen.spawn.instance, x = mine.chosen.spawn.x, y = mine.chosen.spawn.y, name = mine.chosen.label }
    end
    return nil
end

-- The one main arrow points at whatever the player picked in its right-click menu (db.arrowSource):
--   auto     what is next: a plan or trip stop, else my own quest (the default)
--   plan     my plan or trip stop
--   mine     my nearest quest objective
--   partner  my partner, the friend I follow, or a group member
--   rxp      my friend's quest target (RestedXP)
-- When the picked source has nothing to point at yet, it falls back to auto so the arrow never just vanishes.
local function PartnerTarget()
    local fp = addon.FollowPosition and addon.FollowPosition()
    if fp and addon.ModuleOn("follow") and GetTime() - fp.t < 3 then
        return { instance = fp.instance, x = fp.x, y = fp.y, name = "Your partner" }
    end
    local lk = state.lastKnown
    if lk and GetTime() - lk.t < 3 then
        return { instance = lk.instance, x = lk.x, y = lk.y, name = state.friend or "Your friend" }
    end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") then
            local x, y, inst = hbd:GetUnitWorldPosition(u)
            if x then return { instance = inst, x = x, y = y, name = UnitName(u) or "Group member" } end
        end
    end
    return nil
end

-- For a stop that is kills or items: the arrow points at the nearest spot where those things are (Questie's spawns, or the places
-- other players really did it), not at the middle of the stop. It stays at a spot while I am making progress there, and moves to
-- the next one when I have stood there a while with nothing counting up.
-- PickSpot does the choosing for any list of quests and any way of finding their spots (a plan stop out in the world, or the
-- quests of a dungeon I am inside).
local spotStates = setmetatable({}, { __mode = "k" })

local function OpenObjectiveIds(wp)
    local ids = {}
    for _, q in ipairs(wp.quests or {}) do
        local lbl = q.label or ""
        if q.id and not (lbl:find("^Turn in:") or lbl:find("^Pick up:") or lbl:find("^Class quest:"))
            and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.IsComplete then
            local okI, idx = pcall(C_QuestLog.GetLogIndexForQuestID, q.id)
            if okI and idx and idx > 0 then
                local okC, done = pcall(C_QuestLog.IsComplete, q.id)
                if okC and not done then ids[#ids + 1] = q.id end
            end
        end
    end
    return ids
end

local function ObjectiveProgress(ids)
    local n = 0
    for _, id in ipairs(ids) do
        if C_QuestLog and C_QuestLog.GetQuestObjectives then
            local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
            if ok and type(objs) == "table" then
                for _, o in ipairs(objs) do n = n + (tonumber(o.numFulfilled) or 0) end
            end
        end
    end
    return n
end

-- the spots of these quests out in the world, from the quest log's own spawn lists
local function WorldSpots(ids, pinst)
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    local cands, grid = {}, {}
    -- stay in the zone I am in: a spot in another zone only counts when it is right next to me (the arrow must not hop around the world)
    local db = DB()
    local zone = db and db.arrowSameZone ~= false and hbd and hbd:GetPlayerZone() or nil
    local px, py = hbd and hbd:GetPlayerWorldPosition()
    for _, g in ipairs(addon.QuestLogSpawns()) do
        if g.id and want[g.id] and not g.complete then
            for _, s in ipairs(g.spawns) do
                local near = (not zone) or s.uiMapId == nil or s.uiMapId == zone
                    or (px and s.x and math.sqrt((s.x - px) ^ 2 + (s.y - py) ^ 2) < 400)
                if s.instance == pinst and s.x and near then
                    local key = math.floor(s.x / 25) .. ":" .. math.floor(s.y / 25)
                    if not grid[key] then
                        grid[key] = true
                        cands[#cands + 1] = { x = s.x, y = s.y, instance = s.instance, uiMapId = s.uiMapId, zx = s.zx, zy = s.zy, key = key }
                    end
                end
            end
        end
    end
    return cands
end

-- key: what these spots belong to (a table, kept as long as it lives); ids: the open quests; getCands(ids, pinst): the spots
local function PickSpot(key, ids, label, quests, getCands)
    if #ids == 0 then spotStates[key] = nil; return nil end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return nil end
    local now = GetTime()
    local state = spotStates[key]
    if not state then state = { visited = {}, lastProgress = 0 }; spotStates[key] = state end
    local sigIds = table.concat(ids, ",")
    if state.sigIds ~= sigIds or not state.cands or now - state.candsAt > 6 then
        state.cands = getCands(ids, pinst) or {}
        state.candsAt = now
        if state.sigIds ~= sigIds then state.cur = nil; state.visited = {}; state.sig = nil end
        state.sigIds = sigIds
        -- the spot I was heading for is no longer a candidate (I left its zone): choose again from the ones left
        if state.cur then
            local still = false
            for _, c in ipairs(state.cands) do if c.key == state.cur.key then still = true; break end end
            if not still then state.cur = nil end
        end
    end
    local cands = state.cands
    if #cands == 0 then return nil end
    -- progress: while it counts up, stay
    local sig = ObjectiveProgress(ids)
    if sig ~= state.sig then state.sig = sig; state.lastProgress = now end
    local function dist(s) return math.sqrt((s.x - px) ^ 2 + (s.y - py) ^ 2) end
    local cur = state.cur
    if cur then
        local d = dist(cur)
        if d <= 45 then
            cur.arrivedAt = cur.arrivedAt or now
            if now - math.max(cur.arrivedAt, state.lastProgress) > 25 then     -- stood here, nothing counting up: next spot
                state.visited[cur.key] = now
                cur = nil
            end
        else
            cur.arrivedAt = nil
        end
    end
    local function nearestFresh()
        local best, bd
        for _, c in ipairs(cands) do
            local seen = state.visited[c.key]
            if not (seen and now - seen < 180) then
                local d = dist(c)
                if not bd or d < bd then best, bd = c, d end
            end
        end
        return best, bd
    end
    if not cur then
        local c = nearestFresh()
        if not c then state.visited = {}; c = nearestFresh() end         -- seen them all: start over
        cur = c
    elseif dist(cur) > 150 then
        local c, bd = nearestFresh()
        if c and c ~= cur and bd < dist(cur) * 0.5 then cur = c end            -- a much nearer one: use that
    end
    state.cur = cur
    if not cur then return nil end
    -- one table that is kept and updated, so "arrived" is only noticed once per stop
    local tg = state.target
    if not tg then tg = {}; state.target = tg end
    tg.instance, tg.x, tg.y, tg.uiMapId, tg.zx, tg.zy = cur.instance, cur.x, cur.y, cur.uiMapId, cur.zx, cur.zy
    tg.name, tg.label, tg.quests, tg.spot = label, label, quests, true
    return tg
end
addon.PickObjectiveSpot = PickSpot

local function ObjectiveSpot(wp)
    local db = DB()
    if db.arrowSpots == false or not addon.QuestLogSpawns then return nil end
    return PickSpot(wp, OpenObjectiveIds(wp), wp.name, wp.quests, WorldSpots)
end
local function BaseArrowTarget()    local db = DB()
    if not db then return nil end
    local src = db.arrowSource or "auto"
    if src == "plan" then
        local wp = db.waypoints and db.waypoints[1]
        if wp then return wp end
    elseif src == "mine" then
        if mine.chosen then
            return { instance = mine.chosen.spawn.instance, x = mine.chosen.spawn.x, y = mine.chosen.spawn.y, name = mine.chosen.label }
        end
    elseif src == "rxp" then
        local c = state.chosen and state.chosen[1]
        if c then return { instance = c.spawn.instance, x = c.spawn.x, y = c.spawn.y, name = c.label } end
    elseif src == "books" then
        local b = addon.NearestBook and addon.NearestBook()
        if b then return b end
    elseif src == "nodes" then
        local nd = addon.NearestNode and addon.NearestNode()
        if nd then return nd end
    elseif src == "partner" then
        local pt = PartnerTarget()
        if pt then return pt end
    end
    return (db.waypoints and db.waypoints[1]) or addon.SimpleTarget()
end

function addon.ArrowTarget()
    -- inside a dungeon with quests that need something here: the spots in there come first
    local okD, ds = pcall(function() return addon.DungeonArrowTarget and addon.DungeonArrowTarget() end)
    if okD and ds then return ds end
    local wp = BaseArrowTarget()
    local db = DB()
    local skipped
    -- the closest stop first: of the next few stops that are in this zone, the arrow goes to the nearest one (it sticks with its
    -- choice until another is a lot closer, so it does not flip back and forth)
    if wp and db and db.arrowNearest ~= false and db.waypoints and wp == db.waypoints[1] and #db.waypoints > 1 and hbd then
        local okN, pick = pcall(function()
            local px, py, pinst = hbd:GetPlayerWorldPosition()
            if not px then return nil end
            local zone = hbd:GetPlayerZone()
            local function dist(w)
                local t = w
                if w.quests then
                    local okS, s = pcall(ObjectiveSpot, w)
                    if okS and s then t = s end
                end
                if not (t.x and t.y) or t.instance ~= pinst then return nil end
                return math.sqrt((t.x - px) ^ 2 + (t.y - py) ^ 2)
            end
            -- a finished quest that is about to turn grey (its hand-in would soon give no XP) goes first: the nearest such hand-in
            local pl = UnitLevel("player") or 1
            local green = (GetQuestGreenRange and tonumber(GetQuestGreenRange("player"))) or 8
            local function AboutToGrey(w)
                if not w.quests then return false end
                for _, q in ipairs(w.quests) do
                    if q.id and (q.label or ""):find("^Turn in:") and C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
                        local okI, idx = pcall(C_QuestLog.GetLogIndexForQuestID, q.id)
                        local okQ, qi = false, nil
                        if okI and idx and idx > 0 then okQ, qi = pcall(C_QuestLog.GetInfo, idx) end
                        local lvl = okQ and type(qi) == "table" and tonumber(qi.level)
                        if lvl and lvl > 0 then
                            local diff = pl - lvl
                            if diff >= green - 2 and diff < green then return true end
                        end
                    end
                end
                return false
            end
            local urgent, ud
            for i = 1, math.min(#db.waypoints, 15) do
                local w = db.waypoints[i]
                if not (w.quests and w.uiMapId and zone and w.uiMapId ~= zone) and AboutToGrey(w) then
                    local d = dist(w)
                    if d and (not ud or d < ud) then urgent, ud = w, d end
                end
            end
            if urgent then addon.arrowNearestPick = urgent; return urgent end
            local best, bd
            for i = 1, math.min(#db.waypoints, 8) do
                local w = db.waypoints[i]
                local inZone = not (w.quests and w.uiMapId and zone and w.uiMapId ~= zone)
                if inZone then
                    local d = dist(w)
                    if d and (not bd or d < bd) then best, bd = w, d end
                end
            end
            if not best then return nil end
            local keep = addon.arrowNearestPick
            if keep and keep ~= best then
                for i = 1, math.min(#db.waypoints, 8) do
                    if db.waypoints[i] == keep then
                        local kd = dist(keep)
                        if kd and bd > kd * 0.7 then best = keep end
                        break
                    end
                end
            end
            addon.arrowNearestPick = best
            return best
        end)
        if okN and pick then wp, skipped = pick, (pick ~= db.waypoints[1]) end
    end
    -- a quest stop in another zone stays off the arrow until I am in that zone: the arrow goes to the next stop that is here,
    -- or nowhere (false) when none is
    if wp and wp.quests and wp.uiMapId and db and db.waypoints and wp == db.waypoints[1] and db.arrowSameZone ~= false then
        local zone = hbd and hbd:GetPlayerZone()
        if zone and wp.uiMapId ~= zone then
            local pick
            for i = 2, #db.waypoints do
                local w = db.waypoints[i]
                if not (w.quests and w.uiMapId and w.uiMapId ~= zone) then pick = w; break end
            end
            if not pick then return false end
            wp, skipped = pick, true
        end
    end
    if wp and wp.quests and db and db.waypoints and (wp == db.waypoints[1] or skipped) then
        local ok, s = pcall(ObjectiveSpot, wp)
        if ok and s then return s end
    end
    return wp
end
-- duo mode: my partner is on the compass as an F, even when the compass bar and the arrows are off
local function DuoPartnerSource()
    local db = DB()
    if db.duoCompass == false or not (addon.DuoRole and addon.DuoRole()) then return nil end
    if (GetNumGroupMembers and GetNumGroupMembers() or 0) ~= 2 then return nil end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") then
            local x, y, inst = hbd:GetUnitWorldPosition(u)
            if x then return { inst, x, y, { 0.85, 0.5, 1 }, nil, PartnerIcon() } end
        end
    end
end

local compassTimer = 0
local function UpdateCompass(dt)
    local db = DB()
    if not db or not compass then return end
    compassTimer = compassTimer + dt
    if compassTimer < 0.05 then return end
    compassTimer = 0
    local partner = DuoPartnerSource()
    local normal = db.compassBar and db.mode ~= "off"
    if (not normal and not partner) or api.ShouldHide() then compass:Hide(); return end
    compass:Show()
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local facing = GetPlayerFacing()
    for _, m in ipairs(compass.markers) do m:Hide() end
    if not px or not facing then return end
    local half = compass:GetWidth() / 2 - 8
    local n = 0
    local sources = normal and CompassSources() or {}
    if partner then sources[#sources + 1] = partner end
    for _, s in ipairs(sources) do
        if s[1] == pinst and n < #compass.markers then
            local angle = hbd:GetWorldVector(pinst, px, py, s[2], s[3])
            if angle then
                local rel = (angle - facing + math.pi) % (2 * math.pi) - math.pi
                if math.abs(rel) <= math.pi / 2 then
                    n = n + 1
                    local m = compass.markers[n]
                    m:ClearAllPoints()
                    m:SetPoint("CENTER", compass, "CENTER", -rel / (math.pi / 2) * half, 0)
                    m.icon:Hide()
                    m.letter:SetText("")
                    if s[6] then
                        -- a person: a raid target marker instead of a block
                        m.tex:SetColorTexture(0, 0, 0, 0)
                        m.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                        if SetRaidTargetIconTexture then SetRaidTargetIconTexture(m.icon, s[6]) end
                        m.icon:Show()
                        m:SetSize(16, 18)
                    elseif s[5] then
                        m.tex:SetColorTexture(0, 0, 0, 0)
                        m.letter:SetText(s[5])
                        m.letter:SetTextColor(s[4][1], s[4][2], s[4][3])
                        m:SetSize(14, 18)
                    else
                        m.tex:SetColorTexture(unpack(s[4]))
                        m:SetSize(10, 18)
                    end
                    m:Show()
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Style / layout hooks for the extra frames
--------------------------------------------------------------------------------
local origStyle, origLayout = addon.ApplyStyle, addon.ApplyLayout
function addon:ApplyStyle()
    origStyle(self)
    local db = DB()
    if mineArrow and db then
        mineArrow.arrow:SetTexture(api.StyleTexture())
        mineArrow.arrow:SetVertexColor(unpack(db.colorMine))
    end
end
function addon:ApplyLayout()
    origLayout(self)
    local db = DB()
    if not db then return end
    if mineArrow then
        local p = db.pos.mine
        mineArrow:ClearAllPoints()
        mineArrow:SetPoint(p.point, UIParent, p.point, p.x, p.y)
        mineArrow:SetScale(db.scale)
    end
    if compass then
        local p = db.pos.compass
        compass:ClearAllPoints()
        compass:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    end
end

--------------------------------------------------------------------------------
-- Waypoint sharing (party) -- needs this addon on both sides
--------------------------------------------------------------------------------
local SHARE_PREFIX = "FLWP"

function addon:ShareWaypoint()
    local wp = DB().waypoints[1]
    if not wp then Print("no active waypoint to share"); return end
    if not IsInGroup() then Print("you are not in a party"); return end
    local data = self:Serialize({ name = wp.name, uiMapId = wp.uiMapId, zx = wp.zx, zy = wp.zy })
    self:SendCommMessage(SHARE_PREFIX, data, IsInRaid() and "RAID" or "PARTY")
    Print("sent waypoint to the group: " .. wp.name)
end

function addon:OnSharedWaypoint(prefix, message, distribution, sender)
    if prefix ~= SHARE_PREFIX then return end
    if (sender or ""):match("^([^%-]+)") == UnitName("player") then return end
    if not DB().acceptShared then return end
    local ok, t = self:Deserialize(message)
    if not ok or type(t) ~= "table" then return end
    if type(t.uiMapId) ~= "number" or type(t.zx) ~= "number" or type(t.zy) ~= "number" then return end
    if t.zx < 0 or t.zx > 1 or t.zy < 0 or t.zy > 1 then return end
    local from = (sender or "?"):match("^([^%-]+)") or sender
    local name = string.format("%s (from %s)", tostring(t.name or "Waypoint"):sub(1, 60), from)
    self:AddWaypointZone(t.uiMapId, t.zx, t.zy, name)
end
addon:RegisterComm(SHARE_PREFIX, "OnSharedWaypoint")

--------------------------------------------------------------------------------
-- Import / export dialog
--------------------------------------------------------------------------------
local io
local function MakeIO()
    local f = CreateFrame("Frame", "ForeverLazy_IOFrame", UIParent)
    f:SetSize(400, 250)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPLEFT", 14, -34)
    local ebBg = f:CreateTexture(nil, "BORDER")
    ebBg:SetPoint("TOPLEFT", 12, -52); ebBg:SetSize(376, 150); ebBg:SetColorTexture(0, 0, 0, 0.6)
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal or GameFontHighlight)
    eb:SetSize(364, 146)
    eb:SetPoint("TOPLEFT", 18, -56)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(8000)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.edit = eb
    f.action = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.action:SetSize(110, 24); f.action:SetPoint("BOTTOMLEFT", 14, 12)
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(90, 24); close:SetPoint("BOTTOMRIGHT", -14, 12); close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    return f
end

local function ExportText()
    local lines = {}
    for _, w in ipairs(DB().waypoints) do
        if w.uiMapId and w.zx and w.zy then
            lines[#lines + 1] = string.format("%d,%.4f,%.4f,%s", w.uiMapId, w.zx, w.zy, (w.name or ""):gsub("[\r\n]", " "))
        end
    end
    return table.concat(lines, "\n")
end

function addon:OpenIO(mode)
    io = io or MakeIO()
    io:Show()
    if mode == "export" then
        io.title:SetText("Export waypoints")
        io.hint:SetText("Select all (Ctrl+A) and copy (Ctrl+C). One waypoint per line.")
        io.edit:SetText(ExportText())
        io.edit:HighlightText()
        io.edit:SetFocus()
        io.action:SetText("Select all")
        io.action:SetScript("OnClick", function() io.edit:SetFocus(); io.edit:HighlightText() end)
    else
        io.title:SetText("Import waypoints")
        io.hint:SetText("Paste lines like:  mapId,x,y,name   (x and y between 0 and 1)")
        io.edit:SetText("")
        io.edit:SetFocus()
        io.action:SetText("Import")
        io.action:SetScript("OnClick", function()
            local found = {}
            for line in (io.edit:GetText() or ""):gmatch("[^\r\n]+") do
                local m, x, y, name = line:match("^%s*(%d+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,?%s*(.-)%s*$")
                m, x, y = tonumber(m), tonumber(x), tonumber(y)
                if m and x and y and x <= 1 and y <= 1 then found[#found + 1] = { m, x, y, name } end
            end
            -- add last first so the first line ends up active
            for i = #found, 1, -1 do
                local f = found[i]
                addon:AddWaypointZone(f[1], f[2], f[3], f[4])
            end
            Print(string.format("imported %d waypoints", #found))
            io:Hide()
        end)
    end
end

--------------------------------------------------------------------------------
-- Minimap right-click menu
--------------------------------------------------------------------------------
local menu
local function MakeMenu()
    local f = CreateFrame("Frame", "ForeverLazy_Menu", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.buttons = {}
    local items = {
        { function() return "Options" end, function() addon:OpenOptions() end },
        { function() return "Arrow mode: " .. DB().mode .. " (click to change)" end, function() addon:CycleMode() end },
        { function() return DB().showPanel and "Hide step panel" or "Show step panel" end, function() _G.ForeverLazy_TogglePanel() end },
        { function() return "Drop waypoint here" end, function() addon:DropWaypointHere() end },
        { function() return "Clear waypoints" end, function() addon:ClearWaypoints() end },
        { function() return "Follow next friend" end, function() addon:CycleFriend() end },
        { function() return "Run self-test" end, function() addon:RunSelfTest() end },
    }
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 20)
        b:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * 20)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 4, 0)
        b.fs = fs
        b.getText = it[1]
        b:SetScript("OnClick", function() it[2](); f:Hide() end)
        f.buttons[i] = b
    end
    f:SetSize(230, 12 + #items * 20)
    local away = 0
    f:SetScript("OnUpdate", function(self, dt)
        if MouseIsOver(self) or (self.anchorFrame and MouseIsOver(self.anchorFrame)) then away = 0
        else away = away + dt; if away > 0.8 then self:Hide() end end
    end)
    f:Hide()
    return f
end

function addon:OpenMenu(anchor)
    menu = menu or MakeMenu()
    for _, b in ipairs(menu.buttons) do b.fs:SetText(b.getText()) end
    menu.anchorFrame = anchor
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 10, 0)
    menu:Show()
end

--------------------------------------------------------------------------------
-- Self-test
--------------------------------------------------------------------------------
function addon:RunSelfTest()
    local function line(ok, text, detail)
        local tag = ok == nil and "|cffffd100--|r " or (ok and "|cff55ff55OK|r " or "|cffff5555FAIL|r ")
        print("  " .. tag .. text .. (detail and (" - " .. detail) or ""))
    end
    Print("self-test")
    local LS = _G.LibStub
    line(LS("AceComm-3.0", true) ~= nil, "AceComm library")
    line(LS("AceSerializer-3.0", true) ~= nil, "AceSerializer library")
    line(LS("LibDeflate", true) ~= nil, "LibDeflate library")
    line(LS("HereBeDragons-2.0", true) ~= nil, "HereBeDragons library")
    line(LS("HereBeDragons-Pins-2.0", true) ~= nil, "map pin library")

    local px, py, pinst = hbd:GetPlayerWorldPosition()
    line(px ~= nil, "your world position", px and string.format("%.0f, %.0f (instance %s)", px, py, tostring(pinst)) or "unreadable here")
    line(GetPlayerFacing() ~= nil, "your facing direction", GetPlayerFacing() and string.format("%.2f rad", GetPlayerFacing()) or "unreadable (mounted/flying?)")

    local zx, zy, zone = hbd:GetPlayerZonePosition()
    line(zx ~= nil, "zone position (for waypoints)", zx and string.format("%.1f, %.1f in map %s", zx * 100, zy * 100, tostring(zone)) or nil)
    if zx and zone then
        local wx, wy = hbd:GetWorldCoordinatesFromZone(zx, zy, zone)
        local ok = wx and px and math.abs(wx - px) < 25 and math.abs(wy - py) < 25
        line(ok and true or false, "map-to-world conversion round trip",
            wx and string.format("off by %.1f / %.1f yards", math.abs(wx - (px or 0)), math.abs(wy - (py or 0))) or "failed")
    end

    line(IsInGroup() and true or nil, "in a party", IsInGroup() and GetNumGroupMembers() .. " members" or "join your friend's party")
    if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered then
        line(C_ChatInfo.IsAddonMessagePrefixRegistered("RXPGComms") and true or false, "listening on RXPGComms")
    else
        line(nil, "listening on RXPGComms", "cannot be checked on this client")
    end
    local age = state.lastMsg and string.format("last one %ds ago", GetTime() - state.lastMsg) or "none yet"
    line(state.msgCount > 0 and true or nil, "friend step messages received", string.format("%d valid, %d total, %s", state.msgCount, state.rawCount, age))
    if state.msgCount == 0 then
        line(nil, "tip", "your friend needs RXP Beta features + Share active steps turned on, and must be in your party")
    end
    line(state.friend ~= nil, "following a friend", state.friend)

    line(api.QuestieReady() and true or false, "Questie database")
    line(api.IndexReady() and true or nil, "name index", string.format("%d%%", (state.index.progress or 0) * 100))
    line(#state.groups > 0 and true or nil, "map spots found for current step", string.format("%d groups, %d arrows", #state.groups, #state.chosen))
    line(api.IsMapHooked() and true or nil, "world map Ctrl+right-click hook")
    line(_G.TomTom ~= nil and true or nil, "TomTom installed (optional)")
    local lk = state.lastKnown
    line(lk ~= nil and true or nil, "friend position tracking", lk and string.format("seen %ds ago", GetTime() - lk.t) or "friend not in range yet")
end

--------------------------------------------------------------------------------
-- Profiles, routes, friend commands
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Route planner: put my quest spots in a sensible order and make them waypoints
--------------------------------------------------------------------------------
local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Stay in the zone I am in: spots in other zones are ignored unless they are right next to me.
local NEAR_ENOUGH = 400   -- yards
local function InScope(db, allZones, zoneId, start, s)
    if allZones or db.planZoneOnly == false or not zoneId then return true end
    if s.uiMapId == nil or s.uiMapId == zoneId then return true end
    return Dist(s, start) < NEAR_ENOUGH
end

-- thin a long list of spawn points to a few spread-out ones, enough to plan a route with
local function Thin(list, gap, max)
    gap, max = gap or 60, max or 12
    local out = {}
    for _, s in ipairs(list) do
        local ok = true
        for _, k in ipairs(out) do
            if Dist(s, k) < gap then ok = false; break end
        end
        if ok then
            out[#out + 1] = s
            if #out >= max then break end
        end
    end
    return out
end

-- A quest I chose to do now (right-click menu): its stops go to the front until it is handed in, then the plan carries on.
local function ApplyFocus(wps)
    local db = DB()
    local f = db.planFocus
    if not f or not wps then return end
    local inLog = false
    for _, q in ipairs(ReadQuestLog()) do if q.id == f.id then inLog = true; break end end
    if inLog then
        f.seen = true
    elseif f.seen then
        db.planFocus = nil                  -- done (handed in, or dropped): back to the plan
        return
    end
    local moving, rest = {}, {}
    for _, w in ipairs(wps) do
        local has = false
        for _, q in ipairs(w.quests or {}) do if q.id == f.id then has = true end end
        if has then moving[#moving + 1] = w else rest[#rest + 1] = w end
    end
    if #moving == 0 then return end
    local out, i = {}, 1
    while rest[i] and rest[i].bag do out[#out + 1] = rest[i]; i = i + 1 end
    for _, w in ipairs(moving) do out[#out + 1] = w end
    for k = i, #rest do out[#out + 1] = rest[k] end
    for k = 1, #wps do wps[k] = out[k] end
    for k, w in ipairs(wps) do
        if w.label then w.name = k .. ". " .. w.label end
    end
end

local lastPlanZone, lastPlanAll
local lastPlanInst  -- the continent (world instance) the plan was last made on
local planActive    -- a plan is being followed (it refills itself when it runs out)

-- Quests I can pick up in this zone (Questie already works out which ones I may take), worth doing
-- by colour, nearest givers first. Used when none of my own quests are here.
local function CollectGivers(zoneId, pinst, from, all)
    local QDB = api.GetQuestie()
    if not (QDB and zoneId) then return {} end
    local avail = ns.data.Available()
    if type(avail) ~= "table" then return {} end
    local out = {}
    for id in pairs(avail) do
        local level = QDB.QueryQuestSingle(id, "questLevel")
        local need = QDB.QueryQuestSingle(id, "requiredLevel") or 0     -- Questie can list quests above my level
        local g = { id = id, level = level, complete = false, grey = IsGrey(QDB, level) }
        g.tier = Tier(level, g.grey)
        if need <= (UnitLevel("player") or 1) and not g.grey and Wanted(g)
            and not (api.IsDungeonQuest and api.IsDungeonQuest(id, false)) then
            local by = QDB.QueryQuestSingle(id, "startedBy")
            local sp, here = {}, {}
            if by then api.AddNpcs(sp, by[1]); api.AddObjects(sp, by[2]) end
            local near, nearSpawn
            for _, s in ipairs(sp) do
                if s.instance == pinst and s.uiMapId == zoneId then
                    here[#here + 1] = s
                    local d = Dist(s, from)
                    if not near or d < near then near, nearSpawn = d, s end
                end
            end
            if #here > 0 then
                g.label = "Pick up: " .. (QDB.QueryQuestSingle(id, "name") or ("quest " .. id))
                g.xp = QuestXPNow(id)
                if g.xp <= 0 and level and level > 0 then g.xp = 40 + 10 * level end   -- no data: rough guess by level
                g.spawns = here
                g.near, g.nearSpawn = near, nearSpawn
                out[#out + 1] = g
            end
        end
    end
    table.sort(out, function(a, b) return a.near < b.near end)
    -- only the nearest hub: take its quests, do them, and the next hub is planned when these are done
    local hub = out[1] and out[1].nearSpawn
    local kept = {}
    for _, g in ipairs(out) do
        if hub then
            for _, s in ipairs(g.spawns) do
                if Dist(s, hub) < 200 then kept[#kept + 1] = g; break end
            end
        end
    end
    if all then
        -- the whole zone: every hub, nearest first (a zone plan walks them in the order that suits the route)
        kept = out
        for i = #kept, 26, -1 do kept[i] = nil end
        return kept
    end
    for i = #kept, 13, -1 do kept[i] = nil end
    return kept
end

-- XP hot spots on a zone map: where the quests worth doing for my level are, weighted by the XP they give.
-- Returns a list of { zx, zy, xp, name } (positions as fractions of the zone map), or nil when Questie is not ready.
-- Quests I hold count where their objectives are, quests I can pick up count where their giver stands.
local hotCache = {}
function addon.XPHotSpots(mapId)
    local QDB = api.GetQuestie()
    if not (mapId and QDB and api.QuestieReady and api.QuestieReady()) then return nil end
    local cached = hotCache[mapId]
    if cached and GetTime() - cached.at < 8 then return cached.list end
    local out = {}
    local function add(spawn, xp, name, share)
        if spawn and spawn.uiMapId == mapId and spawn.zx and xp > 0 then
            out[#out + 1] = { zx = spawn.zx, zy = spawn.zy, xp = xp * (share or 1), name = name }
        end
    end
    -- quests I hold
    local okLog, log = pcall(ReadQuestLog)
    if okLog and type(log) == "table" then
        for _, q in ipairs(log) do
            local ok, g = pcall(BuildGroup, q)
            if ok and g and g.spawns and Wanted(g) and not q.complete then
                local xp = QuestXPNow(q.id)
                if xp <= 0 and q.level and q.level > 0 then xp = 40 + 10 * q.level end
                local here = {}
                for _, s in ipairs(g.spawns) do if s.uiMapId == mapId then here[#here + 1] = s end end
                for _, s in ipairs(here) do add(s, xp, q.title, 1 / #here) end
            end
        end
    end
    -- quests I can pick up
    local avail = ns.data.Available()
    if type(avail) == "table" then
        local mylvl = UnitLevel("player") or 1
        for id in pairs(avail) do
            local level = QDB.QueryQuestSingle(id, "questLevel")
            local need = QDB.QueryQuestSingle(id, "requiredLevel") or 0
            local g = { id = id, level = level, complete = false, grey = IsGrey(QDB, level) }
            g.tier = Tier(level, g.grey)
            if need <= mylvl and not g.grey and Wanted(g) then
                local by = QDB.QueryQuestSingle(id, "startedBy")
                if by then
                    local sp, here = {}, {}
                    api.AddNpcs(sp, by[1]); api.AddObjects(sp, by[2])
                    for _, s in ipairs(sp) do if s.uiMapId == mapId then here[#here + 1] = s end end
                    if #here > 0 then
                        local xp = QuestXPNow(id)
                        if xp <= 0 and level and level > 0 then xp = 40 + 10 * level end
                        local name = QDB.QueryQuestSingle(id, "name") or ("quest " .. id)
                        for _, s in ipairs(here) do add(s, xp, name, 1 / #here) end
                    end
                end
            end
        end
    end
    hotCache[mapId] = { at = GetTime(), list = out }
    return out
end
-- Is there anything worth planning in this zone? true / false, or nil when Questie cannot say yet.
-- Quests I already hold here count, and so do quests I can pick up here that are not red or grey.
function addon.ZoneWorthPlanning(zoneId)
    local QDB = api.GetQuestie()
    if not (zoneId and QDB and api.QuestieReady and api.QuestieReady()) then return nil end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return nil end
    local okLog, log = pcall(ReadQuestLog)
    if okLog and type(log) == "table" then
        for _, q in ipairs(log) do
            local ok, g = pcall(BuildGroup, q)
            if ok and g and g.spawns and Wanted(g) then
                for _, s in ipairs(g.spawns) do
                    if s.uiMapId == zoneId then return true end
                end
            end
        end
    end
    local ok, givers = pcall(CollectGivers, zoneId, pinst, { x = px, y = py })
    if not ok then return nil end
    return #givers > 0
end
-- /lazy plan debug: everything the planner works from, so a wrong plan can be understood instead of guessed at
function addon.PlanDebug()
    local db = DB()
    local QDB = api.GetQuestie()
    if not (QDB and api.QuestieReady()) then Print("plan debug: needs Questie loaded and ready"); return end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then Print("plan debug: can't read your position"); return end
    local here = { x = px, y = py }
    local zoneId = hbd:GetPlayerZone()
    local zi = zoneId and C_Map.GetMapInfo(zoneId)
    local function ZoneName(id) local i = id and C_Map.GetMapInfo(id); return i and i.name or "?" end
    Print(string.format("plan debug: you are in %s (map %s), level %d", zi and zi.name or "?", tostring(zoneId), UnitLevel("player") or 0))
    Print(string.format("  settings: planAuto=%s zoneOnly=%s batch=%s autoTrip=%s hiveSpots=%s lastPlanAll=%s planActive=%s",
        tostring(db.planAuto ~= false), tostring(db.planZoneOnly ~= false), tostring(db.planBatch ~= false), tostring(db.autoTrip == true),
        tostring(db.hiveSpots ~= false), tostring(lastPlanAll and true or false), tostring(planActive and true or false)))
    Print("  your quests (spots = places the planner knows for it):")
    for _, q in ipairs(ReadQuestLog()) do
        local ok, g = pcall(BuildGroup, q)
        if ok and g then
            local inScope, nearD, nearZone = 0, nil, nil
            for _, s in ipairs(g.spawns) do
                if s.instance == pinst then
                    if InScope(db, false, zoneId, here, s) then inScope = inScope + 1 end
                    local d = Dist(s, here)
                    if not nearD or d < nearD then nearD, nearZone = d, s.uiMapId end
                end
            end
            local flags = {}
            if q.complete then flags[#flags + 1] = "done" end
            if g.grey then flags[#flags + 1] = "grey" end
            if db.planSkip and db.planSkip[q.id] then flags[#flags + 1] = "SKIPPED" end
            Print(string.format("    %s [%s%s]: %d spots, %d in this zone, nearest %s", tostring(q.title), tostring(g.tier),
                #flags > 0 and (", " .. table.concat(flags, ", ")) or "", #g.spawns, inScope,
                nearD and string.format("%d yd away (%s)", nearD, ZoneName(nearZone)) or "none on this continent"))
        end
    end
    Print("  the plan, as it stands:")
    local shown = 0
    for i, w in ipairs(db.waypoints or {}) do
        if shown >= 8 then break end
        shown = shown + 1
        local d = (w.x and w.instance == pinst) and string.format("%d yd", Dist(w, here)) or "other area"
        Print(string.format("    %d. %s  (%s%s)", i, tostring(w.name or w.label), d, w.go and ", TRIP STOP" or (w.lazy and ", lazy" or "")))
    end
    if shown == 0 then Print("    no stops") end
end
-- a quest I put off ("come back to it later"): it stays out of the plan until its time is up, or until nothing else is left
local function LaterActive(db, id)
    local t = db.planLater and db.planLater[id]
    return t and t > (time and time() or 0) or false
end

function addon:PlanRoute(allZones, quiet, auto)
    local Print = quiet and function() end or Print
    local db = DB()
    if db.planPaused then
        -- the plan is switched off: only me asking for a new one (not an automatic replan) brings it back
        if quiet or auto then return end
        db.planPaused, db.planSaved = nil, nil
        Print("a new plan replaces the paused one")
    end
    local zonePlanNow = addon.zonePlanFlag      -- set by /lazy plan zone for this one call
    addon.zonePlanFlag = nil
    if not api.QuestieReady() then Print("planning needs Questie loaded and ready"); return end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then Print("can't read your position here"); return end
    lastPlanInst = pinst
    RebuildMine(db.planSkipGrey == false)
    mine.dirty = true      -- the arrow rebuilds its own list again afterwards

    -- only spots on the continent I am standing on
    -- how much a quest is worth to me: its XP (unfinished ones count a bit less, the XP is still to earn)
    local useXP = db.planXP ~= false
    local function Weight(g)
        if not useXP then return 1 end
        local xp = g.xp or 0
        if xp <= 0 then xp = 50 end          -- no XP data: assume a small quest
        if not g.complete then xp = xp * 0.7 end
        -- the best quests are yellow (my level): orange ones pay more XP but are slower and riskier, so they rank below yellow;
        -- green ones are easy but small. A finished quest (a hand-in) is not affected.
        if not g.complete and db.planPreferYellow ~= false then
            if g.tier == "yellow" then xp = xp * 1.25
            elseif g.tier == "orange" then xp = xp * 0.6
            elseif g.tier == "green" then xp = xp * 0.9 end
        end
        -- a quest a friend in my group has too is worth more: we can do it together
        if db.planShared ~= false and addon.sharedQuests and g.id then
            local sh = addon.sharedQuests[g.id]
            if addon.DuoRole and addon.DuoRole() then
                xp = xp * (sh and 1.6 or 0.8)          -- duo mode: quests we both have are worth much more
            elseif sh then
                xp = xp * 1.3
            end
        end
        return xp
    end

    -- Time: a quest is worth its XP for the time it takes, walking included (like a levelling guide, XP per minute).
    -- Walking is about 7 yards a second. A quest takes what I measured for it, else my average, else 7 minutes.
    local RUN = 7
    local avgQuestSecs = (addon.HiveAvgQuestSecs and addon.HiveAvgQuestSecs()) or 420
    local function QuestSecs(g)
        if not g or g.complete then return 30 end                         -- only a hand-in left
        local secs
        if g.id and addon.HiveQuestRate and g.xp and g.xp > 0 then
            local rate = addon.HiveQuestRate(g.id)                         -- XP per minute, measured
            if rate and rate > 0 then secs = g.xp / rate * 60 end
        end
        secs = secs or avgQuestSecs
        return math.min(1800, math.max(60, secs))
    end
    local function ItemSecs(item)
        if item.t then return item.t end
        if item.turn then item.t = 30 else item.t = QuestSecs(item.g) + 20 end
        return item.t
    end

    local skipGrey = db.planSkipGrey ~= false
    local zoneId = hbd:GetPlayerZone()
    lastPlanZone, lastPlanAll = zoneId, allZones and not auto
    local here0 = { x = px, y = py }
    local pool, elsewhere, otherZone, greyCount, totalXP = {}, 0, 0, mine.skipped or 0, 0
    local groupSkipped = 0
    for _, g in ipairs(mine.groups) do
        if g.id and api.IsDungeonQuest and api.IsDungeonQuest(g.id, g.complete) and not g.complete then
            -- a dungeon quest: not part of a plan (a finished one is still handed in)
        elseif (db.planSkip and g.id and db.planSkip[g.id]) or (g.id and LaterActive(db, g.id)) then
            -- skipped by me from the arrow's right-click menu
        elseif g.group and g.group > 1 and not g.complete and db.planSkipGroup ~= false and g.tier ~= "green"
            and (GetNumGroupMembers and GetNumGroupMembers() or 0) < 2 then
            groupSkipped = groupSkipped + 1       -- meant for a group and I am on my own (green ones are fine alone)
        elseif skipGrey and g.grey then
            greyCount = greyCount + 1
        else
            local here, onContinent = {}, false
            for _, s in ipairs(g.spawns) do
                if s.instance == pinst then
                    onContinent = true
                    if InScope(db, allZones, zoneId, here0, s) then here[#here + 1] = s end
                end
            end
            if #here > 0 then
                local item = { g = g, spawns = Thin(here), w = Weight(g) }
                pool[#pool + 1] = item
                totalXP = totalXP + (g.xp or 0)
                -- an unfinished quest also has to be handed in, which can only happen after its objectives
                if not g.complete and g.id then
                    local QDB = api.GetQuestie()
                    local by = QDB and QDB.QueryQuestSingle(g.id, "finishedBy")
                    local sp, there = {}, {}
                    if by then api.AddNpcs(sp, by[1]); api.AddObjects(sp, by[2]) end
                    for _, s in ipairs(sp) do
                        if s.instance == pinst and InScope(db, allZones, zoneId, here0, s) then there[#there + 1] = s end
                    end
                    if #there > 0 then
                        local xp = (g.xp and g.xp > 0) and g.xp or 50
                        local turn = { g = { id = g.id, label = "Turn in: " .. g.label }, spawns = Thin(there), locked = true,
                                       turn = true, qid = g.id, w = useXP and (xp * 0.3) or 1 }
                        item.turnItem, item.qid = turn, g.id
                        pool[#pool + 1] = turn
                    end
                end
            elseif onContinent then
                otherZone = otherZone + 1
            else
                elsewhere = elsewhere + 1
            end
        end
    end
    local pickup = false
    if #pool == 0 and not allZones and zoneId then
        -- nothing of mine is here: point at the quest givers in this zone instead
        for _, g in ipairs(CollectGivers(zoneId, pinst, here0)) do
            if not (db.planSkip and db.planSkip[g.id]) and not LaterActive(db, g.id) then
                pool[#pool + 1] = { g = g, spawns = Thin(g.spawns), w = Weight(g) }
                totalXP = totalXP + (g.xp or 0)
                pickup = true
            end
        end
    end
    if not allZones and zoneId and db.planClass ~= false and api.ClassGivers then
        -- class quests I can take are worth a detour: their givers join the plan when they are in this zone
        local have = {}
        for _, it in ipairs(pool) do if it.g.id then have[it.g.id] = true end end
        for _, g in ipairs(api.ClassGivers(zoneId, pinst, here0)) do
            if not have[g.id] and not (db.planSkip and db.planSkip[g.id]) and not LaterActive(db, g.id) then
                pool[#pool + 1] = { g = g, spawns = Thin(g.spawns), w = Weight(g) * 1.5 }
                totalXP = totalXP + (g.xp or 0)
            end
        end
    end
    -- a zone plan (/lazy plan zone): besides the quests I hold, every quest worth taking in this zone goes in, so the plan
    -- covers the whole zone; it stays a zone plan while I stay in the zone, and ends with an ordinary plan request
    if zonePlanNow then db.zonePlan = zoneId elseif not quiet and not auto then db.zonePlan = nil end
    if not allZones and zoneId and (zonePlanNow or db.zonePlan == zoneId) then
        local have = {}
        for _, it in ipairs(pool) do if it.g.id then have[it.g.id] = true end end
        for _, g in ipairs(CollectGivers(zoneId, pinst, here0, true)) do
            if not have[g.id] and not (db.planSkip and db.planSkip[g.id]) and not LaterActive(db, g.id) then
                pool[#pool + 1] = { g = g, spawns = Thin(g.spawns), w = Weight(g) }
                totalXP = totalXP + (g.xp or 0)
                have[g.id] = true
            end
        end
    end
    -- quests I do not have yet but that are right here: the plan counts them too (the pick-up is a stop, and the objectives
    -- join the plan when I take the quest)
    if not allZones and zoneId and db.planNearby ~= false then
        local have = {}
        for _, it in ipairs(pool) do if it.g.id then have[it.g.id] = true end end
        for _, g in ipairs(CollectGivers(zoneId, pinst, here0, true)) do
            if not have[g.id] and not (db.planSkip and db.planSkip[g.id]) and not LaterActive(db, g.id) and (g.near or 1e9) <= 600 then
                pool[#pool + 1] = { g = g, spawns = Thin(g.spawns), w = Weight(g) }
                totalXP = totalXP + (g.xp or 0)
                have[g.id] = true
            end
        end
    end
    -- Is a quest worth the time? Small quests are not: their XP for the time they take (walking included) has to beat a floor,
    -- and a quest has to be a real share of the level. The floor is the pace I measured (when there is one) and half of what the
    -- typical quest in this plan gives. A hand-in, a finished quest and a quest that opens the next of a chain always stay.
    local notWorth = 0
    if db.planWorth ~= false then
        local QDBw = api.GetQuestie()
        local rates, cands = {}, {}
        for _, it in ipairs(pool) do
            local g = it.g
            if not it.turn and not g.complete and g.id and g.xp and g.xp > 0 then
                local r = g.xp / (QuestSecs(g) + 60) * 3600
                rates[#rates + 1] = r
                cands[#cands + 1] = { it = it, rate = r }
            end
        end
        if #cands >= 3 then
            table.sort(rates)
            local median = rates[math.ceil(#rates / 2)]
            local measured = addon.HivePace and (addon.HivePace(GetRealZoneText and GetRealZoneText() or nil) or addon.HivePace())
            local floorRate = math.max((measured and measured * 0.4) or 0, median * 0.5)
            local levelXP = (UnitXPMax and UnitXPMax("player")) or 0
            local minShare = levelXP > 0 and levelXP * 0.015 or 0          -- under 1.5% of a level: not worth stopping for
            local drop, keepCount = {}, 0
            for _, c in ipairs(cands) do
                local g = c.it.g
                local nxt = QDBw and QDBw.QueryQuestSingle(g.id, "nextQuestInChain")
                local chain = nxt and nxt > 0
                if not chain and (c.rate < floorRate or g.xp < minShare) then drop[g.id] = true else keepCount = keepCount + 1 end
            end
            if keepCount > 0 and next(drop) then
                local kept = {}
                for _, it in ipairs(pool) do
                    local id = it.g.id
                    if id and drop[id] then
                        if not it.turn then notWorth = notWorth + 1 end
                    else
                        kept[#kept + 1] = it
                    end
                end
                pool = kept
            end
        end
    end    if #pool == 0 and db.planLater and next(db.planLater) then
        db.planLater = nil; db.planLaterStops = nil
        if addon.PlanLog then addon.PlanLog("plan", "nothing else is left, so the quests you put off come back now") end
        return addon:PlanRoute(allZones, quiet, auto)
    end
    if #pool == 0 then
        if otherZone > 0 and not allZones then
            -- nothing to do here: plan the worthwhile quests wherever they are instead
            Print(string.format("none of your quests are in this zone, planning the %d elsewhere instead", otherZone))
            return addon:PlanRoute(true, quiet, true)
        elseif greyCount > 0 then
            Print(string.format("nothing worth planning: %d grey quest%s skipped", greyCount, greyCount == 1 and "" or "s"))
        else
            Print("no quest locations found on this continent")
        end
        return
    end
    local questCount = 0
    for _, it in ipairs(pool) do if not it.turn then questCount = questCount + 1 end end

    -- 1. next stop = the best XP for the walking (XP divided by distance), starting from where I stand.
    --    A spot where several quests can be done at once counts all of them, and they are done together.
    local TOGETHER = 120     -- yards: quests this close to the spot get done on the same visit
    local function closest(item, s)
        local bd, bsp
        for _, o in ipairs(item.spawns) do
            local d = Dist(o, s)
            if d < TOGETHER and (not bd or d < bd) then bd, bsp = d, o end
        end
        return bsp
    end
    local seq = {}
    local start = { x = px, y = py }
    local cur = start
    while #pool > 0 do
        local bi, bs, bscore
        for i, item in ipairs(pool) do
            if not item.locked then
                for _, s in ipairs(item.spawns) do
                    local w, tt = item.w, ItemSecs(item)
                    for k, other in ipairs(pool) do
                        if k ~= i and not other.locked and closest(other, s) then w = w + other.w; tt = tt + ItemSecs(other) end
                    end
                    -- XP for the time: walking there plus the time the quests take here
                    local score = w / (Dist(s, cur) / RUN + tt + 20)
                    if not bscore or score > bscore then bi, bs, bscore = i, s, score end
                end
            end
        end
        if not bi then
            for _, it in ipairs(pool) do it.locked = false end     -- should not happen, never get stuck
        else
            local item = table.remove(pool, bi)
            local done = { { item = item, s = bs } }
            for k = #pool, 1, -1 do
                local other = pool[k]
                if not other.locked then
                    local sp = closest(other, bs)
                    if sp then done[#done + 1] = { item = table.remove(pool, k), s = sp } end
                end
            end
            for _, d in ipairs(done) do
                seq[#seq + 1] = { label = d.item.g.label, s = d.s, w = d.item.w, t = ItemSecs(d.item), qid = d.item.qid, turn = d.item.turn,
                                  id = d.item.g.id, src = d.s.src, grp = d.item.g.group, tier = d.item.g.tier }
                if d.item.turnItem then d.item.turnItem.locked = false end
            end
            cur = bs
        end
    end

    -- 2. improve it: a route is better when the XP comes sooner, so try reversing stretches of it
    --    and keep a change when the XP-weighted walking time drops (never handing a quest in before its objectives)
    local function valid(order)
        local seen = {}
        for _, e in ipairs(order) do
            if e.turn then
                if not seen[e.qid] then return false end
            elseif e.qid then
                seen[e.qid] = true
            end
        end
        return true
    end
    local function cost(order)
        local cum, total, prev = 0, 0, start
        for _, e in ipairs(order) do
            cum = cum + Dist(prev, e.s) / RUN + (e.t or 0)       -- seconds until this quest's XP is in
            total = total + e.w * cum
            prev = e.s
        end
        return total
    end
    local function reverse(i, j)
        while i < j do
            seq[i], seq[j] = seq[j], seq[i]
            i = i + 1; j = j - 1
        end
    end
    local best = cost(seq)
    for _ = 1, 20 do
        local improved = false
        for i = 1, #seq - 1 do
            for j = i + 1, #seq do
                reverse(i, j)
                local c = valid(seq) and cost(seq) or math.huge
                if c + 0.01 < best then
                    best = c
                    improved = true
                else
                    reverse(i, j)     -- not better, put it back
                end
            end
        end
        if not improved then break end
    end

    -- 2b. do the quests around here before walking back to hand any in, unless handing one in continues a chain
    --     (the next quest of a chain only opens at the hand-in, so that one is not put off)
    if db.planBatch ~= false then
        local BATCH = 400        -- yards from where a quest's objectives were: quests this close are finished first
        local QDBb = api.GetQuestie()
        local function continuesChain(qid)
            local nxt = QDBb and QDBb.QueryQuestSingle(qid, "nextQuestInChain")
            return nxt and nxt > 0
        end
        local i, guard = 1, 0
        while i <= #seq and guard < 300 do
            guard = guard + 1
            local e = seq[i]
            local moved = false
            if e.turn and e.qid and not continuesChain(e.qid) then
                local center
                for j = 1, i - 1 do
                    if seq[j].qid == e.qid and not seq[j].turn then center = seq[j].s end
                end
                if center then
                    local last = i
                    for k = i + 1, #seq do
                        local o = seq[k]
                        if Dist(o.s, center) > BATCH then break end
                        if o.qid and not o.turn then last = k end
                    end
                    if last > i then
                        local item = table.remove(seq, i)
                        table.insert(seq, last, item)      -- it now sits right after the last quest of that area
                        moved = true
                    end
                end
            end
            if not moved then i = i + 1 end
        end
    end

    -- 3. stops that are close together become one waypoint
    local stops = {}
    for _, e in ipairs(seq) do
        local last = stops[#stops]
        local join = last and Dist(last.s, e.s) < 40
        local target = join and last or nil
        if join then
            if e.id and not last.qseen[e.id] then
                last.qseen[e.id] = true
                last.quests[#last.quests + 1] = { id = e.id, label = e.label, src = e.src, grp = e.grp, tier = e.tier }
            end
        end
        if join then
            if e.turn and last.byQuest[e.qid] then
                last.names[last.byQuest[e.qid]] = e.label        -- same spot: do it, then hand it in
            else
                last.names[#last.names + 1] = e.label
                if e.qid and not e.turn then last.byQuest[e.qid] = #last.names end
            end
        else
            stops[#stops + 1] = { s = e.s, names = { e.label }, byQuest = {}, qseen = {}, quests = {} }
            if e.id then
                stops[#stops].qseen[e.id] = true
                stops[#stops].quests[1] = { id = e.id, label = e.label, src = e.src, grp = e.grp, tier = e.tier }
            end
            if e.qid and not e.turn then stops[#stops].byQuest[e.qid] = 1 end
        end
    end

    local list, total, prev = {}, 0, start
    for i, st in ipairs(stops) do
        if i > 30 then break end
        total = total + Dist(prev, st.s)
        prev = st.s
        local label = table.concat(st.names, " + ")
        if #label > 80 then label = label:sub(1, 77) .. "..." end
        list[#list + 1] = { name = i .. ". " .. label, label = label, instance = st.s.instance, x = st.s.x, y = st.s.y,
                            uiMapId = st.s.uiMapId, zx = st.s.zx, zy = st.s.zy, quests = st.quests, area = st.s.area }
    end

    -- Turn-ins first: when I am in an area (about 600 yards) with quests I can hand in right now, those go to the front of the
    -- plan, nearest first, before anything else. Only stops that are nothing but finished hand-ins move.
    do
        local HOIST = 600
        local function Finished(id)
            if not (id and C_QuestLog and C_QuestLog.IsComplete) then return false end
            local okC, done = pcall(C_QuestLog.IsComplete, id)
            return okC and done and true or false
        end
        local near, rest = {}, {}
        for _, w in ipairs(list) do
            local onlyTurnIns = w.quests and #w.quests > 0
            for _, q in ipairs(w.quests or {}) do
                if not ((q.label or ""):find("^Turn in:") and Finished(q.id)) then onlyTurnIns = false; break end
            end
            if onlyTurnIns and w.instance == pinst and Dist(w, start) < HOIST then near[#near + 1] = w else rest[#rest + 1] = w end
        end
        if #near > 0 then
            local ordered, cur = {}, start
            while #near > 0 do
                local bi, bd
                for i, w in ipairs(near) do
                    local d = Dist(cur, w)
                    if not bd or d < bd then bi, bd = i, d end
                end
                local w = table.remove(near, bi)
                ordered[#ordered + 1] = w
                cur = w
            end
            for _, w in ipairs(rest) do ordered[#ordered + 1] = w end
            list = ordered
            for i, w in ipairs(list) do w.name = i .. ". " .. tostring(w.label) end
        end
    end

    -- a place a guard just pointed me to stays the next stop through a replan
    local guardStop
    for _, w in ipairs(db.waypoints or {}) do if w.guard then guardStop = w; break end end
    db.waypoints = list
    if guardStop then table.insert(list, 1, guardStop) end
    ApplyFocus(db.waypoints)
    list = db.waypoints
    planActive = true
    if db.ownQuests then
        -- the plan replaces the "nearest/selected quest" arrow, two arrows would disagree
        db.ownQuests = false
        mine.dirty = true
        Print("my quest log arrow switched off while you follow the plan (/lazy own turns it back on)")
    end
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    Print(string.format("planned %d stop%s for %d quest%s, about %d yards of walking%s. First: %s",
        #list, #list == 1 and "" or "s", questCount, questCount == 1 and "" or "s", total,
        totalXP > 0 and string.format(", about %d XP in total", totalXP) or "", list[1].name))
    if groupSkipped > 0 then
        Print(string.format("%d group quest%s left out because you are solo (they come back when you join a group)",
            groupSkipped, groupSkipped == 1 and "" or "s"))
    end
    if pickup then
        Print("none of your quests are in this zone: pick up the quests at the nearest quest givers (!), then the plan fills in with their objectives")
    end
    if greyCount > 0 then Print(string.format("%d quest%s skipped (grey, or too high a level)", greyCount, greyCount == 1 and "" or "s")) end
    if notWorth > 0 then
        Print(string.format("%d small quest%s left out: not worth the time for the XP (Options > planner turns this off)", notWorth, notWorth == 1 and "" or "s"))
    end
    if otherZone > 0 then
        Print(string.format("%d quest%s in other zones left out. /lazy plan all includes them", otherZone, otherZone == 1 and "" or "s"))
    end
    if elsewhere > 0 then Print(string.format("%d quest%s on another continent left out", elsewhere, elsewhere == 1 and "" or "s")) end
    if addon.PurgeDungeonStops then pcall(addon.PurgeDungeonStops) end       -- belt and braces: no dungeon quest in a fresh plan
end

-- Plan the whole zone for the fastest levelling: my quests plus every quest worth taking here, in a walking order that
-- earns the most XP for the walk. With a zone name (/lazy level ashenvale) it takes me there first, then plans on arrival.
function addon.PlanZone(name)
    local db = DB()
    if db.planPaused then db.planPaused, db.planSaved = nil, nil end
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name:lower() == "steps" or name:lower() == "list" or name:lower() == "window" then
        if addon.ZonePlanWindow then addon.ZonePlanWindow() end       -- the plan I already have, written out
        return
    end
    if name ~= "" then
        local want = name:lower()
        local here = (GetRealZoneText and GetRealZoneText() or ""):lower()
        if not here:find(want, 1, true) then
            local seg
            for _, s in ipairs(addon.JourneySegments and addon.JourneySegments() or {}) do
                if s.map and (s.zone or ""):lower():find(want, 1, true) then seg = s; break end
            end
            if not seg then Print("I don't know a zone called '" .. name .. "'. /lazy guide lists the zones on your way.") return end
            db.zonePlanPending = { zone = seg.zone, t = time() }
            if addon.GoTo then addon.GoTo(seg.map, seg.zx, seg.zy, seg.zone) end
            Print("on the way to " .. seg.zone .. ": I will plan the zone when you arrive")
            return
        end
    end
    addon.zonePlanFlag = true
    addon:PlanRoute(false)
    if addon.ZonePlanWindow then pcall(addon.ZonePlanWindow) end
    local ok, opts = pcall(addon.CoachOptions)
    local best = ok and opts and opts[1]
    if best and best.key == "grind" then
        Print("tip: by your measured numbers, " .. best.label:lower() .. " is faster right now (/lazy coach)")
    end
end

local pendingEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do pcall(pendingEv.RegisterEvent, pendingEv, e) end
pendingEv:SetScript("OnEvent", function()
    if not C_Timer then return end
    C_Timer.After(3, function()
        local db = DB()
        local p = db and db.zonePlanPending
        if not p then return end
        if time() - (p.t or 0) > 1800 then db.zonePlanPending = nil; return end
        local here = (GetRealZoneText and GetRealZoneText() or ""):lower()
        if here ~= "" and here == (p.zone or ""):lower() then
            db.zonePlanPending = nil
            pcall(addon.PlanZone)
        end
    end)
end)

-- Turn the plan off but keep my place: the stops still to do are put aside, and nothing replans or re-adds arrows.
function addon.PlanPause()
    local db = DB()
    if db.planPaused then Print("the plan is already off. /lazy plan on picks it up where you left it"); return end
    local keep, rest = {}, {}
    for _, w in ipairs(db.waypoints or {}) do
        if w.label and not w.go and not w.gather then keep[#keep + 1] = w else rest[#rest + 1] = w end
    end
    if #keep == 0 then Print("there is no plan to turn off"); return end
    local zone = GetRealZoneText and GetRealZoneText() or "?"
    db.planSaved = { stops = api.DeepCopy(keep), zone = zone, time = time and time() or 0, all = lastPlanAll and true or false }
    db.waypoints = rest
    db.planPaused = true
    planActive = false
    addon:RefreshPins()
    if addon.DrawRouteLines then pcall(addon.DrawRouteLines) end
    if addon.DrawXPHeat then pcall(addon.DrawXPHeat) end
    if addon.RefreshQuestItems then pcall(addon.RefreshQuestItems) end
    if addon.UpdateTomTom then addon:UpdateTomTom() end
    if addon.RefreshOptions then addon.RefreshOptions() end
    Print(string.format("plan off. I kept your place: %d stop%s still to do, next was %s. /lazy plan on resumes it.",
        #keep, #keep == 1 and "" or "s", tostring(keep[1].name or keep[1].label)))
end

-- Pick the plan up where it was left.
function addon.PlanResume()
    local db = DB()
    local saved = db.planSaved
    if not db.planPaused then Print("the plan is not off"); return end
    db.planPaused = nil
    db.planSaved = nil
    if not saved or not saved.stops or #saved.stops == 0 then
        Print("nothing was saved, planning fresh")
        addon:PlanRoute()
        return
    end
    local wps = db.waypoints or {}
    for i = #saved.stops, 1, -1 do table.insert(wps, 1, saved.stops[i]) end
    db.waypoints = wps
    lastPlanAll = saved.all
    planActive = true
    addon:RefreshPins()
    if addon.DrawXPHeat then pcall(addon.DrawXPHeat) end
    if addon.RefreshQuestItems then pcall(addon.RefreshQuestItems) end
    if addon.UpdateTomTom then addon:UpdateTomTom() end
    if addon.RefreshOptions then addon.RefreshOptions() end
    local here = GetRealZoneText and GetRealZoneText() or "?"
    Print(string.format("plan back on: %d stop%s, next is %s%s", #saved.stops, #saved.stops == 1 and "" or "s",
        tostring(saved.stops[1].name or saved.stops[1].label),
        saved.zone and saved.zone ~= here and (" (it was in " .. saved.zone .. "; /lazy plan makes a new one for here)") or ""))
end

-- A quest was just taken: slot it into the plan where it adds the least walking.
-- A quest closer than the next stop naturally ends up in front of it.
local function RenumberPlan(wps)
    for i, w in ipairs(wps) do
        if w.label then w.name = i .. ". " .. w.label end
    end
end

local function AddQuestToPlan(questId)
    local db = DB()
    if db.planAuto == false or db.planPaused then return end
    local wps = db.waypoints
    if #wps == 0 and planActive then
        -- the last stop was the quest giver: now the new quest's objectives become the plan
        addon.planWhy = "the plan was empty and a quest was accepted"
        addon:PlanRoute(false, true)
        local now = db.waypoints
        if now[1] and now[1].label then Print("plan updated with your new quest: " .. now[1].name) end
        return
    end
    if not (wps[1] and wps[1].label) then return end        -- no plan running
    if not api.QuestieReady() then return end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return end

    local q
    for _, e in ipairs(ReadQuestLog()) do if e.id == questId then q = e; break end end
    if not q then return end
    local g = BuildGroup(q)
    if not Wanted(g, db.planSkipGrey == false) then return end   -- grey, or orange/red and not done: not worth a stop
    if db.planSkip and db.planSkip[g.id] then return end         -- I skipped this one
    if LaterActive(db, g.id) then return end                     -- I put this one off for a while
    if not g.complete and api.IsDungeonQuest and api.IsDungeonQuest(g.id, false) then return end   -- dungeon quests stay out of the plan

    -- candidate spots on this continent, in the zone I am in
    local start = { x = px, y = py }
    local zoneId = hbd:GetPlayerZone()
    local cands = {}
    for _, s in ipairs(g.spawns) do
        if s.instance == pinst and InScope(db, false, zoneId, start, s) then cands[#cands + 1] = s end
    end
    if #cands == 0 then return end

    local function pt(i) return i == 0 and start or wps[i] end
    local n = #wps
    local bestS, bestPos, bestCost
    for _, s in ipairs(cands) do
        for pos = 0, n do          -- insert after stop number `pos`
            if pos == 0 or pt(pos).instance == pinst then
                local a = pt(pos)
                local b = pos < n and wps[pos + 1] or nil
                if not b or b.instance == pinst then
                    local cost = Dist(a, s) + (b and (Dist(s, b) - Dist(a, b)) or 0)
                    if not bestCost or cost < bestCost then bestS, bestPos, bestCost = s, pos, cost end
                end
            end
        end
    end
    if not bestS then return end

    -- right next to an existing stop? then just add the quest to that stop
    for i, w in ipairs(wps) do
        if w.label and w.instance == bestS.instance and Dist(w, bestS) < 40 then
            if not w.label:find(g.label, 1, true) then w.label = w.label .. " + " .. g.label end
            RenumberPlan(wps)
            addon:RefreshPins()
            if addon.PlanLog then addon.PlanLog("plan", "added " .. tostring(g.label) .. " to stop " .. i .. " (a quest was accepted next to it)") end
            Print(string.format("added %s to plan stop %d", g.label, i))
            return
        end
    end

    table.insert(wps, bestPos + 1, { name = "", label = g.label, instance = bestS.instance, x = bestS.x, y = bestS.y,
                                     uiMapId = bestS.uiMapId, zx = bestS.zx, zy = bestS.zy,
                                     quests = { { id = g.id, label = g.label, src = bestS.src, grp = g.group, tier = g.tier } } })
    RenumberPlan(wps)
    ApplyFocus(wps)
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    if addon.PlanLog then addon.PlanLog("plan", "added " .. tostring(g.label) .. " as stop " .. (bestPos + 1) .. " (a quest was accepted)") end
    Print(string.format("added %s to your plan as stop %d%s", g.label, bestPos + 1,
        bestPos == 0 and " (next up)" or ""))
end

local planEvents = CreateFrame("Frame")
pcall(planEvents.RegisterEvent, planEvents, "QUEST_ACCEPTED")
planEvents:SetScript("OnEvent", function(_, _, a, b)
    local id = tonumber(b) or tonumber(a)     -- classic: (logIndex, questId), newer: (questId)
    if not id then return end
    pcall(addon.PickupDone, id)                   -- the accept step is done
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function() pcall(AddQuestToPlan, id) end)   -- give the quest log a moment
    end
end)

-- The plan ran out of stops. Normally accepting a quest refills it; if nothing happens, plan again.
local origRemove = addon.RemoveWaypoint
function addon:RemoveWaypoint(i)
    origRemove(self, i)
    local db = DB()
    if planActive and db.planAuto ~= false and #db.waypoints == 0 and C_Timer and C_Timer.After then
        C_Timer.After(25, function()
            if planActive and #DB().waypoints == 0 then addon.planWhy = "the plan ran out of stops"; pcall(addon.PlanRoute, addon, false, true) end
        end)
    end
end

-- Walked or flew into a new zone: the plan only covers the zone it was made in, so build it again here.
local function ReplanForZone()
    local db = DB()
    if db.planAuto == false or db.planPaused then return end
    local _, _, inst = hbd:GetPlayerWorldPosition()
    -- a new continent (hearthstone, boat, tram, zeppelin, portal): the old stops are all out of reach, always rebuild
    local wps = db.waypoints
    -- A spot I set by clicking the map is only a pointer for where I was: once I am in another zone it no longer applies, and
    -- while it is the first stop the plan keeps its hands off ("keep my own waypoints"), so take it away first.
    do
        local zoneNow = hbd:GetPlayerZone()
        local dropped
        for i = #(wps or {}), 1, -1 do
            local w = wps[i]
            if w.questMapPin then
                -- only drop it once I have moved to another zone SINCE I clicked it (a pin clicked far away must stay: it is where I am going)
                if w.setZone == nil then w.setZone, w.setInst = zoneNow or false, inst or false end
                local moved = (zoneNow and w.setZone and w.setZone ~= zoneNow) or (inst and w.setInst and w.setInst ~= inst)
                if moved then
                    table.remove(wps, i); dropped = true
                end
            end
        end
        if dropped then
            addon:RefreshPins()
            if addon.PlanLog then addon.PlanLog("plan", "the spot set by a map click was in another zone, so it was dropped") end
        end
    end
    local planInst = lastPlanInst or (wps and wps[1] and wps[1].label and wps[1].instance)    -- after a reload: the first stop says
    local newContinent = planInst and inst and inst ~= planInst
    if not newContinent and (db.planZoneOnly == false or lastPlanAll) then return end
    if not wps or (#wps > 0 and not (wps[1] and wps[1].label)) then return end   -- keep my own waypoints
    if UnitOnTaxi and UnitOnTaxi("player") then return end              -- the landing will trigger this again
    if UnitIsGhost and UnitIsGhost("player") then return end
    local zone = hbd:GetPlayerZone()
    if not zone or (zone == lastPlanZone and not newContinent) then return end
    addon.planWhy = "you entered a new zone or continent"
    addon:PlanRoute(false, true)
    local now = db.waypoints
    if newContinent and inst then
        -- stops left over from the other continent cannot be walked to: take them out of the plan
        local removed = 0
        for i = #now, 1, -1 do
            local w = now[i]
            if w.label and w.instance and w.instance ~= inst and not w.go then table.remove(now, i); removed = removed + 1 end
        end
        if removed > 0 then
            RenumberPlan(now)
            addon:RefreshPins()
            if addon.RefreshOptions then addon.RefreshOptions() end
            Print(string.format("new continent: %d plan stop%s from the other one put away. /lazy plan rebuilds when you are back", removed, removed == 1 and "" or "s"))
        end
    end
    if now and now[1] and now[1].label then
        Print(string.format("new zone, plan rebuilt: %d stop%s. First: %s", #now, #now == 1 and "" or "s", now[1].name))
    end
end

-- Moved somewhere else in the same zone (or flew, or hearthed): the plan was made for where I stood, so when the next stop is
-- now far away and another stop is much closer, build it again from here.
local lastDrift = 0
local driftAcc = 0
local driftFrame = CreateFrame("Frame")
driftFrame:SetScript("OnUpdate", function(_, dt)
    driftAcc = driftAcc + dt
    if driftAcc < 5 then return end
    driftAcc = 0
    local db = DB()
    if not db or db.planAuto == false or not planActive then return end
    if GetTime() - lastDrift < 90 then return end
    if (UnitOnTaxi and UnitOnTaxi("player")) or (UnitIsGhost and UnitIsGhost("player")) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local wps = db.waypoints
    local first = wps and wps[1]
    if not (first and first.label and first.instance and first.x) then return end        -- only while a plan stop is next
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px or first.instance ~= pinst then return end
    local d1 = math.sqrt(api.D2(first.x, first.y, px, py))
    if d1 < 800 then return end
    local nearest
    for i = 2, #wps do
        local w = wps[i]
        if w.label and w.instance == pinst and w.x then
            local d = math.sqrt(api.D2(w.x, w.y, px, py))
            if not nearest or d < nearest then nearest = d end
        end
    end
    if nearest and nearest < d1 * 0.5 and d1 - nearest > 600 then
        lastDrift = GetTime()
        addon.planWhy = "you moved far from the plan, so it was rebuilt from where you are"
        pcall(addon.PlanRoute, addon, lastPlanAll and true or false, true)
        local after = db.waypoints
        if after and after[1] and after[1].label then
            Print("you moved on, plan rebuilt from here. Next: " .. after[1].name)
        end
    end
end)

-- A quest got finished (ready to hand in) or handed in / dropped: move the plan on.
local questState, questProgress, questCheck
local function QuestChanged()
    questCheck = false
    local db = DB()
    if not api.QuestieReady() then return end
    local now = {}
    local okRead, log = pcall(ReadQuestLog)
    if not okRead or type(log) ~= "table" then return end
    local progress = {}
    for _, q in ipairs(log) do
        if q.id then
            now[q.id] = q.complete and true or false
            -- how many of its objectives are finished: one more means the next stop may be somewhere else
            local n = 0
            if C_QuestLog and C_QuestLog.GetQuestObjectives then
                local okO, objs = pcall(C_QuestLog.GetQuestObjectives, q.id)
                if okO and type(objs) == "table" then
                    for _, o in ipairs(objs) do if o.finished then n = n + 1 end end
                end
            end
            progress[q.id] = n
        end
    end
    local old, oldProgress = questState, questProgress
    questState, questProgress = now, progress
    if not old then return end                       -- first look, nothing to compare with
    local changed
    for id, done in pairs(now) do
        if done and old[id] == false then changed = true end      -- just finished
        if oldProgress and oldProgress[id] and progress[id] > oldProgress[id] then changed = true end   -- an objective done
    end
    for id in pairs(old) do
        if now[id] == nil then changed = true end                 -- handed in or dropped
    end
    local wps = db.waypoints
    if not changed or db.planAuto == false or not (wps and wps[1] and wps[1].label) then return end
    addon.planWhy = "quest progress: a quest was finished, handed in or an objective done"
    addon:PlanRoute(lastPlanAll and true or false, true)
    local after = db.waypoints
    if after and after[1] and after[1].label then
        Print("quest progress, plan updated. Next: " .. after[1].name)
    end
end

-- Is anything at this plan stop still to be done? A stop only counts as done when its quests really are:
--   an accept stop when the quest is in my log, objectives when the quest is complete, a hand-in when it is gone from my log.
-- Getting there is never enough. (Stops with no quest, such as a vendor, are done on arrival.)
local function QuestOpen(id)
    if not (id and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.IsComplete) then return false end
    local okI, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    if not okI or not idx or idx == 0 then return false end           -- not in my log: nothing open
    local okC, done = pcall(C_QuestLog.IsComplete, id)
    return okC and not done
end
local function InMyLog(id)
    if not (id and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return nil end
    local okI, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    if not okI then return nil end
    return idx and idx > 0 and true or false
end
function addon.StopHasOpenObjectives(wp)
    for _, q in ipairs(wp and wp.quests or {}) do
        local lbl = q.label or ""
        local inLog = InMyLog(q.id)
        if inLog ~= nil then
            if lbl:find("^Turn in:") then
                if inLog then return true end                         -- not handed in yet
            elseif lbl:find("^Pick up:") or lbl:find("^Class quest:") then
                if not inLog then return true end                      -- not accepted yet
            elseif QuestOpen(q.id) then
                return true                                            -- objectives not finished
            end
        end
    end
    return false
end

-- I accepted a quest: its accept step is done, take it out of the plan (the plan then gets the quest's objectives)
function addon.PickupDone(id)
    local wps = DB().waypoints
    if not wps or not id then return end
    local changed = false
    for i = #wps, 1, -1 do
        local w = wps[i]
        if w.quests and #w.quests > 0 then
            local keep = {}
            for _, q in ipairs(w.quests) do
                local lbl = q.label or ""
                if not (q.id == id and (lbl:find("^Pick up:") or lbl:find("^Class quest:"))) then keep[#keep + 1] = q end
            end
            if #keep < #w.quests then
                changed = true
                if #keep == 0 then
                    table.remove(wps, i)
                else
                    w.quests = keep
                    local labels = {}
                    for _, q in ipairs(keep) do labels[#labels + 1] = q.label end
                    w.label = table.concat(labels, " + ")
                end
            end
        end
    end
    if changed then
        for k, w in ipairs(wps) do if w.label then w.name = k .. ". " .. w.label end end
        addon:RefreshPins()
        if addon.RefreshOptions then addon.RefreshOptions() end
    end
end
-- Dungeon quests do not belong in a plan: take them out of every stop (alone or joined with other quests), unless the quest
-- is finished and only waits for its hand-in. verbose = say what was found (/lazy dungeons purge).
function addon.PurgeDungeonStops(verbose)
    local db = DB()
    if not (db and db.waypoints and api.IsDungeonQuest) then return 0 end
    local ids, count = {}, 0
    for si, s in ipairs(db.waypoints) do
        for _, q in ipairs(s.quests or {}) do
            local verdict = q.id and api.IsDungeonQuest(q.id, false)
            if verbose then Print(string.format("  stop %d: %s (id %s): dungeon = %s", si, tostring(q.label), tostring(q.id), tostring(verdict))) end
            if q.id and verdict and not ids[q.id] then
                local done = false
                if C_QuestLog and C_QuestLog.IsComplete then
                    local okC, c = pcall(C_QuestLog.IsComplete, q.id)
                    done = okC and c and true or false
                end
                if verbose then Print("     finished and waiting for a hand-in: " .. tostring(done)) end
                if not done then ids[q.id] = true; count = count + 1 end
            end
        end
    end
    if count > 0 and addon.ScrubQuest then
        for id in pairs(ids) do pcall(addon.ScrubQuest, id) end
        Print(string.format("took %d dungeon quest%s out of your plan", count, count == 1 and "" or "s"))
    end
    -- stops that only carry a name (no quest list): match them by title against my log and my class quests
    local byTitle = {}
    if api.ReadQuestLog then
        local okL, log = pcall(api.ReadQuestLog)
        if okL and type(log) == "table" then
            for _, q in ipairs(log) do if q.id and q.title then byTitle[q.title:lower()] = q.id end end
        end
    end
    local named = 0
    for i = #db.waypoints, 1, -1 do
        local s = db.waypoints[i]
        local shownName = s.label or s.name       -- a stop made by "Show me" or /lazy class go has a name but no label
        if shownName and not s.go and not s.gather and not (s.quests and #s.quests > 0) then
            local title = tostring(shownName):gsub("^%d+%.%s*", ""):gsub("^Class quest: ", ""):gsub("^Pick up: ", ""):gsub("^Turn in: ", "")
            local id = byTitle[title:lower()] or (addon.ClassQuestIdByTitle and addon.ClassQuestIdByTitle(title))
            local byName = (not id) and api.DungeonTitle and api.DungeonTitle(title)
            if verbose then Print(string.format("  named stop %d: %s -> id %s%s", i, tostring(shownName), tostring(id), byName and " (a dungeon quest by name)" or "")) end
            if byName or (id and api.IsDungeonQuest(id, false)) then
                local done = false
                if C_QuestLog and C_QuestLog.IsComplete then
                    local okC, c = pcall(C_QuestLog.IsComplete, id)
                    done = okC and c and true or false
                end
                if not done then table.remove(db.waypoints, i); named = named + 1 end
            end
        end
    end
    if named > 0 then
        addon:RefreshPins()
        if addon.RefreshOptions then addon.RefreshOptions() end
        Print(string.format("took %d dungeon quest stop%s out of your arrow list", named, named == 1 and "" or "s"))
    end
    if verbose and count == 0 and named == 0 then
        Print("no dungeon quests to take out (" .. #db.waypoints .. " stops looked at)")
    end
    return count + named
end
-- Safety net for the accept step: any "Pick up" / "Class quest" entry whose quest is already in my log is done, whether or not the
-- accepted event reached us (a different id, a quest taken some other way, a reload in between).
local sweepAcc = 0
local sweepTick = CreateFrame("Frame")
sweepTick:SetScript("OnUpdate", function(_, dt)
    sweepAcc = sweepAcc + dt
    if sweepAcc < 1 then return end
    sweepAcc = 0
    local db = DB()
    local wps = db and db.waypoints
    if not wps or #wps == 0 then return end
    local done
    for _, w in ipairs(wps) do
        for _, q in ipairs(w.quests or {}) do
            local lbl = q.label or ""
            if q.id and (lbl:find("^Pick up:") or lbl:find("^Class quest:")) and InMyLog(q.id) == true then
                done = done or {}
                done[q.id] = true
            end
        end
    end
    if done then
        for id in pairs(done) do pcall(addon.PickupDone, id) end
    end
end)

-- a hand-in must never come up while the quest is not finished: rebuild the plan so the objectives come first
local lastFix = 0
local fixTick = CreateFrame("Frame")
local fixAcc = 0
fixTick:SetScript("OnUpdate", function(_, dt)
    fixAcc = fixAcc + dt
    if fixAcc < 4 then return end
    fixAcc = 0
    local db = DB()
    if db and GetTime() - (addon.lastDungeonPurge or 0) > 20 then addon.lastDungeonPurge = GetTime(); pcall(addon.PurgeDungeonStops) end
    -- a quest I put off goes back into the plan when I am near where it was again (after I have been away from it), or when its
    -- time is up
    if db and db.planLaterStops and next(db.planLaterStops) and not db.planPaused then
        local nowT = time and time() or 0
        local px, py, pinst = hbd:GetPlayerWorldPosition()
        local inFight = InCombatLockdown and InCombatLockdown()
        for id, rec in pairs(db.planLaterStops) do
            local back, why = false, nil
            if (db.planLater and db.planLater[id] or 0) <= nowT then back, why = true, "its time is up" end
            if not back and px then
                local nearest
                for _, r in ipairs(rec.recs or {}) do
                    if r.instance == pinst and r.x then
                        local d = math.sqrt(api.D2(r.x, r.y, px, py))
                        if not nearest or d < nearest then nearest = d end
                    end
                end
                if nearest then
                    if nearest > 500 then rec.away = true end                 -- I have left the crowd behind
                    if rec.away and nearest <= 350 and not inFight then back, why = true, "you are near it again" end
                end
            end
            if back then pcall(addon.PlanLaterReturn, id, why) end
        end
    end    local w = db and db.waypoints and db.waypoints[1]
    if not w or db.planPaused or db.planAuto == false or not (w.label and w.label:find("^Turn in:")) then return end
    for _, q in ipairs(w.quests or {}) do
        if QuestOpen(q.id) and GetTime() - lastFix > 30 then
            lastFix = GetTime()
            addon.planWhy = "a hand-in for an unfinished quest came up first"
            pcall(addon.PlanRoute, addon, lastPlanAll and true or false, true)
            return
        end
    end
end)

-- a finished quest whose hand-in is right here: do it now, whatever the plan says is next
local function QuestFinished(id)
    if not (id and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.IsComplete) then return false end
    local okI, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    if not okI or not idx or idx == 0 then return false end
    local okC, done = pcall(C_QuestLog.IsComplete, id)
    return okC and done and true or false
end
local nearTick = CreateFrame("Frame")
local nearAcc, nearAt = 0, setmetatable({}, { __mode = "k" })
nearTick:SetScript("OnUpdate", function(_, dt)
    nearAcc = nearAcc + dt
    if nearAcc < 2 then return end
    nearAcc = 0
    local db = DB()
    local wps = db and db.waypoints
    if not wps or #wps < 2 or db.planPaused or db.planAuto == false then return end
    local first = wps[1]
    if not (first and first.label) then return end              -- the arrow is on something that is not the plan
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return end
    local d1 = first.instance == pinst and math.sqrt(api.D2(first.x, first.y, px, py)) or nil
    -- is the stop the arrow is on already a hand-in? then only a clearly closer one takes over
    local firstIsTurn = first.quests and #first.quests > 0
    for _, q in ipairs(first.quests or {}) do
        if not ((q.label or ""):find("^Turn in:")) then firstIsTurn = false; break end
    end
    for i = 2, #wps do
        local w = wps[i]
        if w.label and w.instance == pinst and w.x and w.quests and #w.quests > 0 and not nearAt[w] then
            local allHandIns = true
            for _, q in ipairs(w.quests) do
                if not ((q.label or ""):find("^Turn in:") and QuestFinished(q.id)) then allHandIns = false; break end
            end
            if allHandIns then
                local d = math.sqrt(api.D2(w.x, w.y, px, py))
                -- close by (about a minute's walk), and nearer than where the arrow points now
                -- in an area with hand-ins (about 600 yards): they come first, unless I am already heading to a nearer one
                if d < 600 and (not firstIsTurn or not d1 or d1 > d + 60) then
                    nearAt[w] = GetTime()
                    table.remove(wps, i)
                    table.insert(wps, 1, w)
                    RenumberPlan(wps)
                    addon:RefreshPins()
                    if addon.RefreshOptions then addon.RefreshOptions() end
                    if addon.PlanLog then addon.PlanLog("plan", "you are close to a hand-in, so it was moved to the front: " .. tostring(w.label)) end
                    Print("you are close to a hand-in: " .. tostring(w.label):gsub("^Turn in: ", "Turn in "))
                    return
                end
            end
        end
    end
end)

-- A quest was handed in (in any order) or dropped: take it out of every stop of the plan right away, wherever the
-- stop is in the list, so the arrow never sends me back to a quest giver I have already seen.
local function ScrubQuest(id)
    local wps = DB().waypoints
    if not wps or #wps == 0 then return end
    local changed = false
    for i = #wps, 1, -1 do
        local w = wps[i]
        if w.quests and #w.quests > 0 then
            local keep = {}
            for _, q in ipairs(w.quests) do
                if q.id ~= id then keep[#keep + 1] = q end
            end
            if #keep < #w.quests then
                changed = true
                if #keep == 0 and w.label then
                    table.remove(wps, i)
                else
                    w.quests = keep
                    local labels = {}
                    for _, q in ipairs(keep) do labels[#labels + 1] = q.label end
                    if #labels > 0 then w.label = table.concat(labels, " + ") end
                end
            end
        end
    end
    if changed then
        RenumberPlan(wps)
        addon:RefreshPins()
        if addon.RefreshOptions then addon.RefreshOptions() end
    end
end
addon.ScrubQuest = ScrubQuest

local questWatch = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
    pcall(questWatch.RegisterEvent, questWatch, e)
end
questWatch:SetScript("OnEvent", function(_, event, arg1)
    if event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        local id = tonumber(arg1)
        if id then pcall(ScrubQuest, id) end
    end
    if questCheck or not (C_Timer and C_Timer.After) then return end
    questCheck = true
    C_Timer.After(1.5, function() pcall(QuestChanged); questCheck = false end)
end)

pcall(planEvents.RegisterEvent, planEvents, "ZONE_CHANGED_NEW_AREA")
planEvents:RegisterEvent("PLAYER_ENTERING_WORLD")      -- trams, boats and portals load a new area without the zone event
pcall(planEvents.RegisterEvent, planEvents, "PLAYER_CONTROL_GAINED")   -- a flight ends: the zone event came mid-flight and was skipped, so look again now
local planOnEvent = planEvents:GetScript("OnEvent")
planEvents:SetScript("OnEvent", function(self, event, ...)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_CONTROL_GAINED" then
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() pcall(ReplanForZone) end)       -- let the position settle
        end
        return
    end
    return planOnEvent(self, event, ...)
end)

-- Backup for the events above: every few seconds, when the zone I am standing in is not the one the plan was made for and I am
-- not on a flight, plan again. (A flight crosses zone borders without the plan being able to follow, and nothing fires at the landing.)
do
    local zoneAcc, askedFor = 0, nil
    local zoneWatch = CreateFrame("Frame")
    zoneWatch:SetScript("OnUpdate", function(_, dt)
        zoneAcc = zoneAcc + dt
        if zoneAcc < 4 then return end
        zoneAcc = 0
        local db = DB()
        if not db or db.planAuto == false or db.planPaused then return end
        if UnitOnTaxi and UnitOnTaxi("player") then return end
        if InCombatLockdown and InCombatLockdown() then return end
        local zone = hbd:GetPlayerZone()
        if not zone or zone == lastPlanZone or zone == askedFor then return end
        askedFor = zone                   -- once for each zone: ReplanForZone decides whether a new plan is needed
        pcall(ReplanForZone)
    end)
end

--------------------------------------------------------------------------------
-- The line under the plan arrow: what to do at this stop
--------------------------------------------------------------------------------
local function PlainTitle(label)
    local t = label or "?"
    t = t:gsub("^Turn in: ", ""):gsub("^Pick up: ", ""):gsub("^Class quest: ", "")
    return t
end

local npcNames = {}
local function GiverName(id, field)
    local key = id .. field
    if npcNames[key] ~= nil then return npcNames[key] or nil end
    local name
    local QDB = api.GetQuestie()
    local by = QDB and QDB.QueryQuestSingle(id, field)
    if by and by[1] and by[1][1] then name = QDB.QueryNPCSingle(by[1][1], "name") end
    if not name and by and by[2] and by[2][1] then name = QDB.QueryObjectSingle(by[2][1], "name") end
    npcNames[key] = name or false
    return name
end

-- "Defias Pillager slain: 3/8" becomes "Kill 5 more Defias Pillager (3/8)"
local function ObjectiveLines(id, src)
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return out end
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
    if not ok or type(objs) ~= "table" then return out end
    -- only the objective this stop is for ("talk to X" at X's stop, not the one in another city)
    local mine
    if src then
        for _, o in ipairs(objs) do
            if not o.finished and o.text and MatchesOpen({ o.text:lower() }, src) then mine = true end
        end
    end
    for _, o in ipairs(objs) do
        if not o.finished and o.text and o.text ~= "" and (not mine or MatchesOpen({ o.text:lower() }, src)) then
            local have, need = o.numFulfilled, o.numRequired
            local name = o.text:match("^(.-):%s*%d+/%d+") or o.text
            local slain = name:find(" slain$") ~= nil
            name = name:gsub(" slain$", "")
            local multi = have and need and need > 1
            local line
            if slain then
                -- a real kill objective
                line = multi and string.format("Kill %d more %s (%d/%d)", need - have, name, have, need) or ("Kill " .. name)
            elseif o.type == "item" then
                line = multi and string.format("Collect %d more %s (%d/%d)", need - have, name, have, need) or ("Get " .. name)
            else
                -- talk to, explore, use, escort...: the quest's own wording says it best
                line = multi and string.format("%s (%d/%d)", name, have, need) or name
            end
            out[#out + 1] = line
        end
    end
    return out
end

local detailCache = setmetatable({}, { __mode = "k" })
function addon.WaypointDetail(wp)
    if not wp then return nil end
    local c = detailCache[wp]
    local now = GetTime()
    if c and now - c.t < 1 then return c.text end
    local text = wp.detail
    if wp.quests and #wp.quests > 0 then
        local parts = {}
        for i, q in ipairs(wp.quests) do
            if i > 2 then parts[#parts + 1] = string.format("+%d more", #wp.quests - 2); break end
            local title = PlainTitle(q.label)
            local lbl = q.label or ""
            if lbl:find("^Turn in:") then
                local npc = GiverName(q.id, "finishedBy")
                parts[#parts + 1] = "Turn in " .. title .. (npc and (" to " .. npc) or "")
            elseif lbl:find("^Pick up:") or lbl:find("^Class quest:") then
                local npc = GiverName(q.id, "startedBy")
                parts[#parts + 1] = "Pick up " .. title .. (npc and (" from " .. npc) or "")
            else
                local lines = ObjectiveLines(q.id, q.src)
                local part
                if #lines > 0 then
                    part = table.concat(lines, ", ", 1, math.min(#lines, 2))
                else
                    part = title
                end
                -- meant for a group: say so, and say when a green one can be done alone
                if q.grp and q.grp > 1 then
                    if q.tier == "green" and (GetNumGroupMembers and GetNumGroupMembers() or 0) < 2 then
                        part = part .. " [group quest, but green: you can likely solo it]"
                    else
                        part = part .. " [group quest]"
                    end
                end
                parts[#parts + 1] = part
            end
        end
        text = table.concat(parts, "; ")
    end
    detailCache[wp] = { t = now, text = text }
    return text
end

-- The zone plan written out: for each stop, what to pick up and from whom, what to kill or collect and where, and what to
-- hand in. The plan already keeps quests of an area open and hands them in together, so this reads top to bottom.
local zpWin, zpRows = nil, {}

function addon.ZonePlanLines(maxStops)
    local out = {}
    local db = DB()
    local n = 0
    for i, w in ipairs(db.waypoints or {}) do
        if w.label and not w.go and not w.gather and not w.guard then
            n = n + 1
            if n > (maxStops or 25) then break end
            local head = string.format("%d. %s", i, PlainTitle(w.label))
            if w.zx and w.zy then head = head .. string.format("   |cffaaaaaa(%.0f, %.0f)|r", w.zx * 100, w.zy * 100) end
            local lines = {}
            for _, q in ipairs(w.quests or {}) do
                local title = PlainTitle(q.label)
                local lbl = q.label or ""
                if lbl:find("^Turn in:") then
                    local npc = GiverName(q.id, "finishedBy")
                    lines[#lines + 1] = "|cffffd100?|r Hand in " .. title .. (npc and (" to " .. npc) or "")
                elseif lbl:find("^Pick up:") or lbl:find("^Class quest:") then
                    local npc = GiverName(q.id, "startedBy")
                    lines[#lines + 1] = "|cffffd100!|r Get " .. title .. (npc and (" from " .. npc) or "")
                else
                    local objs = ObjectiveLines(q.id, q.src)
                    if #objs > 0 then
                        for _, o in ipairs(objs) do lines[#lines + 1] = "- " .. title .. ": " .. o end
                    else
                        lines[#lines + 1] = "- " .. title
                    end
                end
            end
            if #lines == 0 then lines[1] = "- " .. PlainTitle(w.label) end
            out[#out + 1] = { head = head, lines = lines }
        end
    end
    return out
end

function addon.ZonePlanWindow()
    if not zpWin then
        local f = CreateFrame("Frame", "ForeverLazy_ZonePlan", UIParent)
        f:SetSize(540, 500)
        f:SetPoint("CENTER", 0, 20)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.sub:SetPoint("TOPLEFT", 16, -46); f.sub:SetWidth(500); f.sub:SetJustifyH("LEFT")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", "ForeverLazy_ZonePlanScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -84); scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        f.content = CreateFrame("Frame", nil, scroll)
        f.content:SetSize(480, 10)
        scroll:SetScrollChild(f.content)
        table.insert(UISpecialFrames, "ForeverLazy_ZonePlan")
        f:Hide()
        zpWin = f
    end
    local scale = math.min(2.6, math.max(0.8, tonumber(DB().guideScale) or 1))
    zpWin:SetScale(scale)
    local zone = GetRealZoneText and GetRealZoneText() or "this zone"
    zpWin.title:SetText("Level " .. zone)
    zpWin.sub:SetText("In order. Get the quests, do their objectives together, and the plan hands them in in one go, unless a hand-in opens the next quest of a chain. Stop 1 is where the arrow points now.")
    for _, r in ipairs(zpRows) do r.head:Hide(); r.body:Hide() end
    local steps = addon.ZonePlanLines(25)
    local y = 0
    for i, s in ipairs(steps) do
        local r = zpRows[i]
        if not r then
            r = {}
            r.head = zpWin.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.head:SetJustifyH("LEFT")
            r.body = zpWin.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.body:SetJustifyH("LEFT")
            zpRows[i] = r
        end
        r.head:ClearAllPoints(); r.head:SetPoint("TOPLEFT", zpWin.content, "TOPLEFT", 0, -y)
        r.head:SetWidth(470); r.head:SetText(s.head); r.head:Show()
        y = y + math.max(18, r.head:GetStringHeight()) + 2
        r.body:ClearAllPoints(); r.body:SetPoint("TOPLEFT", zpWin.content, "TOPLEFT", 10, -y)
        r.body:SetWidth(455); r.body:SetText(table.concat(s.lines, "\n")); r.body:Show()
        y = y + r.body:GetStringHeight() + 10
    end
    if #steps == 0 then
        local r = zpRows[1]
        if not r then
            r = { head = zpWin.content:CreateFontString(nil, "OVERLAY", "GameFontNormal"), body = zpWin.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight") }
            zpRows[1] = r
        end
        r.head:ClearAllPoints(); r.head:SetPoint("TOPLEFT", zpWin.content, "TOPLEFT", 0, 0); r.head:SetWidth(470)
        r.head:SetText("There is no plan yet. /lazy level makes one for this zone."); r.head:Show()
        y = 30
    end
    zpWin.content:SetHeight(math.max(y, 40))
    zpWin:Show()
end

--------------------------------------------------------------------------------
-- The step window: the plan as numbered steps, one thing at a time (like a levelling guide)
--   !  accept a quest, from whom, where        -  do its objectives (kill, collect, go)        ?  turn it in
-- It ticks a step off by itself when it is done and shows the next few. The arrow already follows the first stop.
--------------------------------------------------------------------------------
local stepWin, stepRows = nil, {}
local stepHistory, stepSeen = {}, {}          -- steps just done (shown ticked for a while), and the ones seen last time
local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:14|t"

local function InLog(id)
    if not (id and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return false end
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    return ok and idx and idx > 0 and true or false
end

function addon.StepList(max)
    local db = DB()
    local steps = {}
    local pts = addon.TalentPointsUnspent and addon.TalentPointsUnspent() or 0
    if pts > 0 and db.talentReminder ~= false then
        steps[#steps + 1] = { kind = "go", key = "talents", text = "Spend " .. pts .. " talent point" .. (pts == 1 and "" or "s") .. " (press N)", done = false }
    end
    for si, w in ipairs(db.waypoints or {}) do
        if #steps >= (max or 12) then break end
        if w.lazy and not w.label then
            -- a service step Lazy mode or the autopilot added: sell and repair, visit the trainer, move on
            local nm = tostring(w.name or "Go"):gsub("^Lazy mode: ", "")
            steps[#steps + 1] = { kind = "go", key = "lazy:" .. si .. ":" .. nm, stop = si, text = "Go to " .. nm .. (w.detail and (" - " .. w.detail) or ""), done = false }
        end
        if w.label and not w.go and not w.gather and not w.guard then
            local where = w.zx and w.zy and string.format("%.0f, %.0f", w.zx * 100, w.zy * 100) or nil
            local acc, dos, trn = {}, {}, {}
            for _, q in ipairs(w.quests or {}) do
                local lbl = q.label or ""
                local title = PlainTitle(lbl)
                if lbl:find("^Turn in:") then
                    local npc = GiverName(q.id, "finishedBy")
                    trn[#trn + 1] = { kind = "turn", key = tostring(q.id) .. ":turn", stop = si, where = where,
                        text = "Turn in " .. title .. (npc and (" to " .. npc) or ""), done = not InLog(q.id), qid = q.id, label = q.label }
                elseif lbl:find("^Pick up:") or lbl:find("^Class quest:") then
                    local npc = GiverName(q.id, "startedBy")
                    acc[#acc + 1] = { kind = "accept", key = tostring(q.id) .. ":accept", stop = si, where = where,
                        text = "Accept " .. title .. (npc and (" from " .. npc) or ""), done = InLog(q.id), qid = q.id, label = q.label }
                else
                    local lines = ObjectiveLines(q.id, q.src)
                    local text = (#lines > 0) and (title .. ": " .. table.concat(lines, ", ", 1, math.min(#lines, 2))) or ("Do " .. title)
                    local finished = C_QuestLog and C_QuestLog.IsComplete and select(2, pcall(C_QuestLog.IsComplete, q.id)) or false
                    dos[#dos + 1] = { kind = "do", key = tostring(q.id) .. ":do", stop = si, where = where, text = text,
                        done = finished and true or false, qid = q.id, label = q.label }
                end
            end
            for _, t in ipairs(acc) do steps[#steps + 1] = t end
            for _, t in ipairs(dos) do steps[#steps + 1] = t end
            for _, t in ipairs(trn) do steps[#steps + 1] = t end
            if #w.quests == 0 then
                steps[#steps + 1] = { kind = "go", key = "go:" .. si .. ":" .. tostring(w.label), stop = si, where = where,
                    text = "Go to " .. PlainTitle(w.label), done = false }
            end
        end
    end
    return steps
end

local KIND_MARK = { accept = "|cffffd100!|r", ["do"] = "|cffffffff-|r", turn = "|cffffd100?|r", go = "|cff80c0ff>|r" }

local function StepScale()
    local db = DB()
    return math.min(2.6, math.max(0.7, tonumber(db.stepsScale) or tonumber(db.guideScale) or 1))
end

local function StepRefresh()
    local db = DB()
    if not stepWin then return end
    local steps = (db and not db.planPaused) and addon.StepList(14) or {}
    -- steps seen before that are gone now were done: keep a few ticked for a while
    local now, current = GetTime(), {}
    for _, s in ipairs(steps) do current[s.key] = true end
    for key, s in pairs(stepSeen) do
        if not current[key] and not s.gone then
            s.gone = now
            stepHistory[#stepHistory + 1] = s
        end
    end
    stepSeen = {}
    for _, s in ipairs(steps) do stepSeen[s.key] = s end
    for i = #stepHistory, 1, -1 do
        if now - stepHistory[i].gone > 20 or i < #stepHistory - 2 then table.remove(stepHistory, i) end
    end

    stepWin:SetScale(StepScale())
    local fixedHeight = db.pos and db.pos.stepsSize and db.pos.stepsSize.h        -- I sized it: as many steps as fit
    local width = math.max(160, stepWin:GetWidth() - 28)
    local rows, n = {}, 0
    for _, s in ipairs(stepHistory) do rows[#rows + 1] = { s = s, done = true } end
    local firstOpen = true
    for _, s in ipairs(steps) do
        if not fixedHeight and #rows >= 8 then break end
        rows[#rows + 1] = { s = s, done = s.done, current = (not s.done) and firstOpen }
        if not s.done then firstOpen = false end
    end
    local y, shown = 0, 0
    local room = fixedHeight and (fixedHeight - 40) or nil
    for i, r in ipairs(rows) do
        local row = stepRows[i]
        if not row then
            row = stepWin.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row:SetJustifyH("LEFT")
            stepRows[i] = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", stepWin.content, "TOPLEFT", 4, -y)
        row:SetWidth(width)
        local s = r.s
        local text = string.format("%s %s%s", r.done and CHECK or KIND_MARK[s.kind] or "-", s.text, s.where and ("  |cff999999(" .. s.where .. ")|r") or "")
        if r.done then text = "|cff55ff55" .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r"
        elseif r.current then text = "|cffffd100" .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r" end
        row:SetText(text)
        local h = row:GetStringHeight() + 6
        if room and shown > 0 and y + h > room then break end      -- no more room: the rest shows when there is
        row:Show()
        y = y + h
        shown = i
    end
    for i = shown + 1, #stepRows do stepRows[i]:Hide() end
    local zone = GetRealZoneText and GetRealZoneText() or ""
    stepWin.title:SetText(#rows > 0 and ("Steps  |cffaaaaaa" .. zone .. "|r") or "Steps")
    stepWin.empty:SetWidth(width)
    stepWin.empty:SetShown(#rows == 0)
    stepWin.content:SetSize(width, math.max(y, 20))
    if not fixedHeight and not stepWin.sizing then stepWin:SetHeight(math.max(70, 40 + y)) end
end

local function BuildStepWindow()
    local f = CreateFrame("Frame", "ForeverLazy_Steps", UIParent)
    local size = DB() and DB().pos and DB().pos.stepsSize
    f:SetSize(size and size.w or 300, size and size.h or 140)
    local saved = DB() and DB().pos and DB().pos.steps
    if saved then f:SetPoint(saved.point or "TOPRIGHT", UIParent, saved.rel or "TOPRIGHT", saved.x or 0, saved.y or 0)
    else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -250) end
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetResizable(true)
    pcall(f.SetResizeBounds, f, 190, 90, 900, 900)          -- newer clients
    pcall(f.SetMinResize, f, 190, 90)                       -- older ones
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        local db = DB()
        if db then db.pos = db.pos or {}; db.pos.steps = { point = point, rel = rel, x = x, y = y } end
    end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.04, 0.07, 0.85)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 8, -8)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() DB().stepsHidden = true; f:Hide() end)
    -- text size, like the guide window: A- smaller, A+ bigger
    local function SizeButton(text, anchor, delta)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(24, 18); b:SetText(text); b:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
        b:SetScript("OnClick", function()
            local db = DB()
            db.stepsScale = math.min(2.6, math.max(0.7, StepScale() + delta))
            StepRefresh()
        end)
        return b
    end
    local bigger = SizeButton("A+", close, 0.15)
    SizeButton("A-", bigger, -0.15)
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", 8, -28); f.content:SetSize(272, 20)
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.empty:SetPoint("TOPLEFT", 8, -30); f.empty:SetWidth(272); f.empty:SetJustifyH("LEFT")
    f.empty:SetText("No plan yet. /lazy plan or /lazy level makes one.")
    -- drag the corner to resize; the size is remembered. Shift + right-click on the title goes back to automatic height.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f.sizing = true; f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f.sizing = false
        local db = DB()
        if db then db.pos = db.pos or {}; db.pos.stepsSize = { w = f:GetWidth(), h = f:GetHeight() } end
        StepRefresh()
    end)
    f:SetScript("OnSizeChanged", function(self) if self.sizing then StepRefresh() end end)
    local reset = CreateFrame("Button", nil, f)
    reset:SetPoint("TOPLEFT", 0, 0); reset:SetPoint("TOPRIGHT", -70, 0); reset:SetHeight(24)
    reset:RegisterForClicks("RightButtonUp")
    reset:RegisterForDrag("LeftButton")                      -- the title strip still drags the whole window
    reset:SetScript("OnDragStart", function() f:StartMoving() end)
    reset:SetScript("OnDragStop", function() local h = f:GetScript("OnDragStop"); if h then h(f) end end)
    reset:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            local db = DB()
            if db and db.pos then db.pos.stepsSize = nil end
            f:SetSize(300, 140)
            StepRefresh()
        end
    end)
    f:Hide()
    return f
end
function addon.ToggleSteps(force)
    local db = DB()
    if not stepWin then stepWin = BuildStepWindow() end
    local show
    if force ~= nil then show = force else show = not stepWin:IsShown() end
    db.stepsHidden = not show
    if show then stepWin:Show(); StepRefresh() else stepWin:Hide() end
end

-- show it by itself while a plan is running (unless I closed it), keep it up to date
local stepAcc = 0
local stepTick = CreateFrame("Frame")
stepTick:SetScript("OnUpdate", function(_, dt)
    stepAcc = stepAcc + dt
    if stepAcc < 0.7 then return end
    stepAcc = 0
    local db = DB()
    if not db then return end
    local wantAuto = db.stepsAuto ~= false and not db.stepsHidden and not db.planPaused and addon.ModuleOn("plan")
    local has = false
    for _, w in ipairs(db.waypoints or {}) do if w.label and not w.go and not w.gather and not w.guard then has = true; break end end
    if not stepWin then
        if not (wantAuto and has) then return end
        stepWin = BuildStepWindow()
    end
    if (wantAuto and has) or (db.stepsHidden == false and stepWin:IsShown()) then
        if not stepWin:IsShown() then stepWin:Show() end
        pcall(StepRefresh)
    elseif stepWin:IsShown() and (not has or db.planPaused) then
        stepWin:Hide()
    end
end)

--------------------------------------------------------------------------------
-- Right-click the plan arrow to skip a quest (or just this stop)
--------------------------------------------------------------------------------
local function SkippedCount()
    local n = 0
    for _ in pairs(DB().planSkip or {}) do n = n + 1 end
    return n
end

local function ReplanAfterSkip()
    local db = DB()
    addon.planWhy = "the quest you skipped (or brought back) changed the plan"
    addon:PlanRoute(lastPlanAll and true or false, true)
    local wps = db.waypoints
    if wps and wps[1] and wps[1].label then
        Print("plan updated. Next: " .. wps[1].name)
    else
        Print("nothing left in the plan")
    end
end

local function SkipQuest(id, label)
    local db = DB()
    db.planSkip = db.planSkip or {}
    db.planSkip[id] = PlainTitle(label)
    Print("skipping " .. PlainTitle(label) .. " (/lazy skip clear brings skipped quests back)")
    -- take it out of the plan I have right now, so it is gone even before (or if) the plan is rebuilt
    pcall(addon.ScrubQuest, id)
    if db.waypoints[1] and db.waypoints[1].label then ReplanAfterSkip() else addon:RefreshPins() end
end

addon.SkipQuest = SkipQuest

-- Come back to a quest later (a crowded spot, say). The plan simply goes on with its next stop, in its own order. The quest
-- waits; when I am near where it was (or its time is up) it is put back into the plan where it costs the least walking.
local function QuestSpotsInPlan(id)
    local recs = {}
    for _, w in ipairs(DB().waypoints or {}) do
        for _, q in ipairs(w.quests or {}) do
            if q.id == id then
                recs[#recs + 1] = { q = { id = q.id, label = q.label, src = q.src, grp = q.grp, tier = q.tier },
                                    instance = w.instance, x = w.x, y = w.y, uiMapId = w.uiMapId, zx = w.zx, zy = w.zy }
            end
        end
    end
    return recs
end

function addon.PlanLater(id, label, minutes)
    local db = DB()
    if not id then return end
    minutes = minutes or 10
    local due = (time and time() or 0) + minutes * 60
    db.planLater = db.planLater or {}
    db.planLaterStops = db.planLaterStops or {}
    local recs = QuestSpotsInPlan(id)
    db.planLater[id] = due
    db.planLaterStops[id] = { recs = recs, label = label }
    if addon.PlanLog then addon.PlanLog("plan", string.format("%s put off (come back to it later): the plan goes on with its next stop", PlainTitle(label))) end
    pcall(addon.ScrubQuest, id)                 -- out of the plan, nothing else rearranged
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    local nxt = db.waypoints[1]
    Print(string.format("%s put off. I will fit it back in when you are near it again (or in %d minutes). Next: %s",
        PlainTitle(label), minutes, nxt and tostring(nxt.name or nxt.label) or "nothing left in the plan"))
end

-- put a quest I put off back into the plan, where it adds the least walking
function addon.PlanLaterReturn(id, why)
    local db = DB()
    local rec = db.planLaterStops and db.planLaterStops[id]
    if db.planLater then db.planLater[id] = nil end
    if db.planLaterStops then db.planLaterStops[id] = nil end
    if not rec then return end
    local wps = db.waypoints
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local placed = 0
    for _, r in ipairs(rec.recs or {}) do
        if r.x and r.instance then
            local start = { x = px or r.x, y = py or r.y }
            local function pt(i) return i == 0 and start or wps[i] end
            local n = #wps
            local bestPos, bestCost
            for pos = 0, n do
                local a = pt(pos)
                local b = pos < n and wps[pos + 1] or nil
                local okA = pos == 0 or (a and a.instance == r.instance and a.x)
                local okB = not b or (b.instance == r.instance and b.x)
                if okA and okB then
                    local cost = Dist(a, r) + (b and (Dist(r, b) - Dist(a, b)) or 0)
                    if not bestCost or cost < bestCost then bestPos, bestCost = pos, cost end
                end
            end
            table.insert(wps, (bestPos or 0) + 1, { name = "", label = r.q.label, instance = r.instance, x = r.x, y = r.y,
                uiMapId = r.uiMapId, zx = r.zx, zy = r.zy, quests = { r.q } })
            placed = placed + 1
        end
    end
    if placed > 0 then
        RenumberPlan(wps)
        addon:RefreshPins()
        if addon.RefreshOptions then addon.RefreshOptions() end
        Print(string.format("%s is back in your plan (%s)", PlainTitle(rec.label), why or "back"))
        if addon.PlanLog then addon.PlanLog("plan", string.format("%s fitted back into the plan (%s)", PlainTitle(rec.label), why or "back")) end
    elseif addon.PlanRoute then
        addon.planWhy = "a quest you put off came back"
        pcall(addon.PlanRoute, addon, lastPlanAll and true or false, true)
    end
end

-- do this quest next (the plan window and the right-click menu both use it)
function addon:FocusQuest(id, label)
    local db = DB()
    db.planFocus = { id = id, label = PlainTitle(label) }
    ApplyFocus(db.waypoints)
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    local first = db.waypoints[1]
    Print("doing " .. PlainTitle(label) .. " first, then back to the plan" .. (first and (". Next: " .. first.name) or ""))
end

local skipMenu, skipCatcher
local function BuildSkipMenu()
    local f = CreateFrame("Frame", "ForeverLazy_SkipMenu", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetWidth(300); f.title:SetJustifyH("LEFT")
    f.rows = {}
    skipCatcher = CreateFrame("Button", nil, UIParent)
    skipCatcher:SetAllPoints(UIParent)
    skipCatcher:SetFrameStrata("FULLSCREEN")
    skipCatcher:Hide()
    skipCatcher:RegisterForClicks("AnyUp")
    skipCatcher:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnShow", function() skipCatcher:Show() end)
    f:SetScript("OnHide", function() skipCatcher:Hide() end)
    table.insert(UISpecialFrames, "ForeverLazy_SkipMenu")
    f:Hide()
    return f
end

local function MenuRow(f, i)
    local b = f.rows[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetSize(300, 20)
    b:SetPoint("TOPLEFT", 10, -26 - (i - 1) * 20)
    b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.fs:SetPoint("LEFT", 2, 0)
    b.fs:SetWidth(296); b.fs:SetJustifyH("LEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnClick", function(self)
        f:Hide()
        if self.fn then self.fn() end
    end)
    f.rows[i] = b
    return b
end

function addon:OpenSkipMenu()
    local db = DB()
    -- the first quest stop of the plan, even when something else (directions, a trip) is in front of it
    local wp, wpIndex
    for i, w in ipairs(db.waypoints) do if w.label then wp, wpIndex = w, i; break end end
    if not wp then Print("no plan stop to skip. /lazy plan builds a plan"); return end
    skipMenu = skipMenu or BuildSkipMenu()
    local f = skipMenu
    f.title:SetText(wp.name or wp.label)
    local items = {}
    for _, q in ipairs(wp.quests or {}) do
        local slow = addon.HiveQuestSlow and addon.HiveQuestSlow(q.id)
        items[#items + 1] = { text = "Come back to " .. PlainTitle(q.label) .. " later (too crowded?)",
                              fn = function() addon.PlanLater(q.id, q.label) end }
        items[#items + 1] = { text = "Skip quest: " .. PlainTitle(q.label) .. (slow and "  |cffff8800(slow for you)|r" or ""),
                              fn = function() SkipQuest(q.id, q.label) end }
    end
    items[#items + 1] = { text = "Do a quest from the plan now...", fn = function() addon:OpenQuestList() end }
    if db.planFocus then
        items[#items + 1] = { text = "Back to the plan (stop doing " .. tostring(db.planFocus.label) .. ")", fn = function()
            db.planFocus = nil
            Print("back to the plan")
            ReplanAfterSkip()
        end }
    end
    items[#items + 1] = { text = "Skip this stop for now", fn = function()
        addon:RemoveWaypoint(wpIndex)
        local nxt = db.waypoints[1]
        Print(nxt and ("skipped. Next: " .. (nxt.name or "?")) or "skipped. That was the last stop")
    end }
    if SkippedCount() > 0 then
        items[#items + 1] = { text = string.format("Bring back %d skipped quest%s", SkippedCount(), SkippedCount() == 1 and "" or "s"),
                              fn = function() db.planSkip = nil; Print("skipped quests are back in"); ReplanAfterSkip() end }
    end
    for i, it in ipairs(items) do
        local row = MenuRow(f, i)
        row.fn = it.fn
        row.fs:SetText(it.text)
        row:Show()
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(320, 36 + #items * 20)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 10, y / s + 10)
    f:Show()
end

-- pick any quest in the plan to do next, whatever its place in the order
function addon:OpenQuestList()
    local db = DB()
    skipMenu = skipMenu or BuildSkipMenu()
    local f = skipMenu
    local items, seen = {}, {}
    for _, w in ipairs(db.waypoints) do
        for _, q in ipairs(w.quests or {}) do
            if q.id and not seen[q.id] then
                seen[q.id] = true
                local lbl = q.label or ""
                local kind = lbl:find("^Turn in:") and "turn in" or ((lbl:find("^Pick up:") or lbl:find("^Class quest:")) and "pick up" or "do")
                local mark = (db.planFocus and db.planFocus.id == q.id) and "|cff55ff55> |r" or ""
                items[#items + 1] = { text = mark .. PlainTitle(lbl) .. "  |cffaaaaaa(" .. kind .. ")|r", fn = function()
                    db.planFocus = { id = q.id, label = PlainTitle(lbl) }
                    ApplyFocus(db.waypoints)
                    addon:RefreshPins()
                    if addon.RefreshOptions then addon.RefreshOptions() end
                    local first = db.waypoints[1]
                    Print("doing " .. PlainTitle(lbl) .. " first, then back to the plan" .. (first and (". Next: " .. first.name) or ""))
                end }
                if #items >= 14 then break end
            end
        end
        if #items >= 14 then break end
    end
    if #items == 0 then Print("no quests in the plan. /lazy plan builds one"); return end
    f.title:SetText("Do which quest now?")
    for i, it in ipairs(items) do
        local row = MenuRow(f, i)
        row.fn = it.fn
        row.fs:SetText(it.text)
        row:Show()
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(320, 36 + #items * 20)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 10, y / s + 10)
    f:Show()
end

-- pick anyone in my party or raid for the friend arrow to follow
function addon:OpenFollowMenu()
    skipMenu = skipMenu or BuildSkipMenu()
    local f = skipMenu
    local items, seen = {}, {}
    local function add(unit)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local name = UnitName(unit)
            if name and not seen[name] then
                seen[name] = true
                local _, cls = UnitClass(unit)
                local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                local hex = c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
                items[#items + 1] = { text = hex .. name .. "|r", fn = function() addon:FollowMember(name) end }
            end
        end
    end
    for i = 1, 4 do add("party" .. i) end
    for i = 1, 40 do add("raid" .. i) end
    if #items == 0 then Print("you are not in a group"); return end
    items[#items + 1] = { text = "|cffaaaaaaStop pinning (follow whoever sends a step)|r", fn = function() addon:StopFollowing() end }
    f.title:SetText("Follow who?")
    for i, it in ipairs(items) do
        local row = MenuRow(f, i)
        row.fn = it.fn
        row.fs:SetText(it.text)
        row:Show()
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(320, 36 + #items * 20)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 10, y / s + 10)
    f:Show()
end

-- right-click on the plan arrow
local skipHooked = CreateFrame("Frame")
pcall(skipHooked.RegisterEvent, skipHooked, "PLAYER_LOGIN")
skipHooked:SetScript("OnEvent", function()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(2, function()
        local f = api.arrows and api.arrows.waypoint
        if f then
            f:EnableMouse(true)
            f:SetScript("OnMouseUp", function(_, button)
                if button == "RightButton" then
                    if addon.OpenServicesMenu then addon:OpenServicesMenu() else addon:OpenSkipMenu() end
                end
            end)
        end
    end)
end)

local function ProfileNames()
    local names = {}
    for n in pairs(addon.GetRoot().profiles) do names[#names + 1] = n end
    table.sort(names)
    return names
end

local function SwitchProfile()
    addon:SelectProfile()
    addon:ApplyAll()
    if addon.RefreshOptions then addon.RefreshOptions() end
end

function addon:HandleExtraCommand(cmd, rest)
    local root = addon.GetRoot()
    if cmd == "selftest" or cmd == "test!" then
        addon:RunSelfTest(); return true

    elseif cmd == "own" then
        local db = DB()
        db.ownQuests = not db.ownQuests
        mine.dirty = true
        Print("my quest log arrow " .. (db.ownQuests and "on" or "off"))
        return true

    elseif cmd == "follow" then
        local arg = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if arg:lower() == "off" then
            addon:StopFollowing()
        elseif arg ~= "" then
            addon:FollowMember(arg)
        elseif UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
            and (UnitInParty("target") or UnitInRaid("target")) then
            addon:FollowMember(UnitName("target"))
        else
            addon:OpenFollowMenu()
        end
        return true

    elseif cmd == "why" then
        -- explains where the plan's arrow comes from, for the quest at stop 1 (or "why all" for every quest in the log)
        local db = DB()
        local QDB = api.GetQuestie()
        if not (QDB and api.QuestieReady()) then Print("needs Questie loaded and ready"); return true end
        local zone = hbd:GetPlayerZone()
        local px, py = hbd:GetPlayerWorldPosition()
        local zi = zone and C_Map.GetMapInfo(zone)
        Print(string.format("you are in %s (map %s)", zi and zi.name or "?", tostring(zone)))
        local ids = {}
        if (rest or ""):lower() == "all" then
            for _, q in ipairs(ReadQuestLog()) do ids[#ids + 1] = q.id end
        else
            local w = db.waypoints[1]
            if w then
                Print(string.format("stop 1: %s at %s %.1f, %.1f%s", tostring(w.label or w.name), tostring(w.uiMapId and C_Map.GetMapInfo(w.uiMapId).name),
                    (w.zx or 0) * 100, (w.zy or 0) * 100, w.detail and (" - " .. w.detail) or ""))
                for _, q in ipairs(w.quests or {}) do ids[#ids + 1] = q.id end
            else
                Print("no stop 1, try /lazy why all")
            end
        end
        for _, id in ipairs(ids) do
            local title = QDB.QueryQuestSingle(id, "name") or ("quest " .. id)
            local open = UnfinishedTexts(id)
            Print(string.format("%s (%d): open objectives: %s", title, id, open and (#open > 0 and table.concat(open, " | ") or "none") or "unknown"))
            local obj = QDB.QueryQuestSingle(id, "objectives")
            local function show(kind, list, nameOf, spawnsOf)
                for _, c in pairs(list or {}) do
                    if c[1] then
                        local sp = {}
                        spawnsOf(sp, c[1])
                        local byMap = {}
                        for _, s in ipairs(sp) do
                            local n = s.uiMapId and C_Map.GetMapInfo(s.uiMapId) and C_Map.GetMapInfo(s.uiMapId).name or "?"
                            byMap[n] = (byMap[n] or 0) + 1
                        end
                        local parts = {}
                        for n, cnt in pairs(byMap) do parts[#parts + 1] = n .. " x" .. cnt end
                        Print(string.format("  %s %s: %s%s", kind, tostring(nameOf(c[1])), #parts > 0 and table.concat(parts, ", ") or "NO SPAWNS",
                            MatchesOpen(open, nameOf(c[1])) and "" or "  (not an open objective)"))
                    end
                end
            end
            if type(obj) == "table" then
                show("npc", obj[1], function(i) return QDB.QueryNPCSingle(i, "name") end, function(sp, i) api.AddNpcs(sp, { i }) end)
                show("object", obj[2], function(i) return QDB.QueryObjectSingle(i, "name") end, function(sp, i) api.AddObjects(sp, { i }) end)
            else
                Print("  Questie has no objectives for this quest")
            end
        end
        return true

    elseif cmd == "macros" or cmd == "macro" then
        if (rest or ""):lower() == "remove" then addon.RemoveMacros() else addon.MakeMacros() end
        return true

    elseif cmd == "toggle" then
        -- one key: arrows off, and back to what they were
        local db = DB()
        if db.mode ~= "off" then
            db.lastMode = db.mode
            db.mode = "off"
        else
            db.mode = db.lastMode or "both"
        end
        Print("arrows " .. (db.mode == "off" and "off" or ("on (" .. db.mode .. ")")))
        addon:RefreshPins()
        if addon.UpdateTomTom then addon:UpdateTomTom() end
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true

    elseif cmd == "skip" then
        local db = DB()
        if (rest or ""):lower() == "clear" then
            db.planSkip = nil
            Print("skipped quests are back in")
            if db.waypoints[1] and db.waypoints[1].label then ReplanAfterSkip() end
        else
            local n = 0
            for _, title in pairs(db.planSkip or {}) do
                n = n + 1
                Print("  skipped: " .. tostring(title))
            end
            Print(n == 0 and "no quests skipped. Right-click the plan arrow to skip one" or "/lazy skip clear brings them back")
        end
        return true

    elseif cmd == "later" or cmd == "comeback" then
        local db = DB()
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if a == "back" or a == "now" or a == "clear" then
            db.planLater = nil; db.planLaterStops = nil
            Print("the quests you put off are back in the plan")
            if db.waypoints[1] and db.waypoints[1].label then ReplanAfterSkip() else addon:PlanRoute(false, true) end
        elseif a == "list" then
            local n = 0
            for id, due in pairs(db.planLater or {}) do
                n = n + 1
                local rec = db.planLaterStops and db.planLaterStops[id]
                Print(string.format("  %s: back when you are near it again, or in about %d minutes", PlainTitle(rec and rec.label or ("quest " .. id)), math.max(0, math.ceil((due - time()) / 60))))
            end
            if n == 0 then Print("no quests put off") end
        else
            -- put off the quests of the stop I am on
            local w = db.waypoints and db.waypoints[1]
            if w and w.quests and #w.quests > 0 then
                local list = {}
                for _, q in ipairs(w.quests) do list[#list + 1] = q end
                for _, q in ipairs(list) do addon.PlanLater(q.id, q.label) end
            else
                Print("nothing to put off: the arrow is not on a quest stop")
            end
        end
        return true

    elseif cmd == "steps" or cmd == "step" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if a == "on" or a == "show" then addon.ToggleSteps(true)
        elseif a == "off" or a == "hide" then addon.ToggleSteps(false)
        elseif a == "auto" then DB().stepsAuto = DB().stepsAuto == false; Print("the step window shows by itself: " .. tostring(DB().stepsAuto ~= false))
        else addon.ToggleSteps() end
        return true

    elseif cmd == "level" or cmd == "levelzone" then
        addon.PlanZone(rest)
        return true

    elseif cmd == "plan" or cmd == "route!" then
        local arg = (rest or ""):lower()
        if arg == "debug" then addon.PlanDebug(); return true end
        if arg == "zone" or arg == "level" then addon.PlanZone(); return true end
        if arg == "off" or arg == "pause" or arg == "stop" then addon.PlanPause(); return true end
        if arg == "on" or arg == "resume" or arg == "continue" then addon.PlanResume(); return true end
        addon:PlanRoute((rest or ""):lower() == "all"); return true

    elseif cmd == "compass" then
        local db = DB()
        db.compassBar = not db.compassBar
        Print("compass bar " .. (db.compassBar and "on" or "off"))
        return true

    elseif cmd == "friend" then
        if rest == "" then
            local names = {}
            for n in pairs(state.friends) do names[#names + 1] = n end
            table.sort(names)
            Print("friends heard from: " .. (#names > 0 and table.concat(names, ", ") or "none"))
            Print("following: " .. tostring(state.friend) .. (state.pinned and " (pinned)" or " (latest sender)"))
            Print("/lazy friend <name> to pin, /lazy friend auto to follow whoever sent last")
        elseif rest:lower() == "auto" then
            state.pinned = nil
            Print("following the latest sender")
        else
            addon:SelectFriend(rest, true)
        end
        return true

    elseif cmd == "route" then
        local db = DB()
        local sub, name = rest:match("^(%S*)%s*(.*)$")
        sub = (sub or ""):lower()
        if sub == "save" and name ~= "" then
            db.routes[name] = api.DeepCopy(db.waypoints)
            Print(string.format("route '%s' saved (%d waypoints)", name, #db.waypoints))
        elseif sub == "load" and name ~= "" then
            if db.routes[name] then
                db.waypoints = api.DeepCopy(db.routes[name])
                addon:RefreshPins()
                Print(string.format("route '%s' loaded (%d waypoints)", name, #db.waypoints))
            else
                Print("no route named " .. name)
            end
        elseif sub == "delete" and name ~= "" then
            db.routes[name] = nil
            Print("route '" .. name .. "' deleted")
        elseif sub == "list" or sub == "" then
            local any = false
            for n, r in pairs(db.routes) do any = true; Print(string.format("%s (%d waypoints)", n, #r)) end
            if not any then Print("no routes. /lazy route save <name> stores your current waypoints") end
        else
            Print("usage: /lazy route save|load|delete <name>  or  /lazy route list")
        end
        return true

    elseif cmd == "profile" then
        local sub, name = rest:match("^(%S*)%s*(.*)$")
        sub = (sub or ""):lower()
        if sub == "" or sub == "list" then
            local names = ProfileNames()
            Print("active: " .. (root.useChar and "this character" or (root.active or "default")))
            Print("profiles: default" .. (#names > 0 and (", " .. table.concat(names, ", ")) or ""))
        elseif sub == "new" and name ~= "" then
            root.profiles[name] = api.DeepCopy(DB())
            root.active = name
            root.useChar = false
            SwitchProfile()
            Print("created and switched to profile " .. name)
        elseif (sub == "use" or sub == "switch") and name ~= "" then
            if name:lower() == "default" then root.active = nil
            elseif root.profiles[name] then root.active = name
            else Print("no profile named " .. name); return true end
            root.useChar = false
            SwitchProfile()
            Print("using profile " .. (root.active or "default"))
        elseif sub == "delete" and name ~= "" then
            root.profiles[name] = nil
            if root.active == name then root.active = nil end
            SwitchProfile()
            Print("deleted profile " .. name)
        else
            Print("usage: /lazy profile list | new <name> | use <name> | delete <name>")
        end
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Ghost: point at my corpse (the other arrows are hidden while I am a ghost)
--------------------------------------------------------------------------------
local corpseArrow
local CORPSE_COLOR = { 1, 0.35, 0.35 }

-- remember where I died, in case the game can't tell me where the corpse is
local deathFrame = CreateFrame("Frame")
pcall(deathFrame.RegisterEvent, deathFrame, "PLAYER_DEAD")
deathFrame:SetScript("OnEvent", function()
    local x, y, inst = hbd:GetPlayerWorldPosition()
    -- died inside a dungeon or raid? then the corpse run starts at its entrance
    local dungeon
    if IsInInstance then
        local inside, kind = IsInInstance()
        if inside and (kind == "party" or kind == "raid") then dungeon = GetInstanceInfo() end
    end
    if DB() then DB().lastDeath = { x = x, y = y, instance = inst, dungeon = dungeon } end
end)

local function CorpsePoint()
    local d0 = DB().lastDeath
    if d0 and d0.dungeon and api.DungeonEntrance and not (IsInInstance and IsInInstance()) then
        local inst, x, y, label = api.DungeonEntrance(d0.dungeon)
        if inst then return inst, x, y, label end
    end
    local mapId = hbd:GetPlayerZone()
    if mapId and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
        local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, mapId)
        if ok and pos then
            local cx, cy
            if pos.GetXY then cx, cy = pos:GetXY() else cx, cy = pos.x, pos.y end
            if cx and cy and (cx ~= 0 or cy ~= 0) then
                local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(cx, cy, mapId)
                if wx then return inst, wx, wy end
            end
        end
    end
    local d = DB().lastDeath
    if d then return d.instance, d.x, d.y end
end

local corpseTimer = 0
local function UpdateCorpse(dt)
    local db = DB()
    if not db or not corpseArrow then return end
    corpseTimer = corpseTimer + dt
    if corpseTimer < 0.05 then return end
    corpseTimer = 0
    if db.ghostArrow == false or not (UnitIsGhost and UnitIsGhost("player")) then
        corpseArrow:Hide()
        return
    end
    corpseArrow:Show()
    corpseArrow:SetAlpha(db.alpha)
    local inst, x, y, label = CorpsePoint()
    if not inst then
        corpseArrow.arrow:Hide()
        corpseArrow.title:SetText("Corpse location unknown")
        corpseArrow.sub:SetText("")
        return
    end
    api.PointAt(corpseArrow, inst, x, y, label or "Your corpse")
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------
-- The follow arrow: points at one person in my group. It has nothing to do with RestedXP,
-- the person does not need the addon (or anything else).
local followArrow
local FOLLOW_COLOR = { 0.85, 0.5, 1 }
local followLast, followTimer = nil, 0
function addon.FollowPosition() return followLast end

function addon:FollowMember(name)
    local short = name and name:match("^[^-]+")
    local unit = short and api.FindUnit(short)
    if not unit or unit == "player" then Print((short or "that player") .. " is not in your group"); return false end
    DB().followName = short
    followLast = nil
    Print("following " .. short .. " with the purple arrow (right-click it to change)")
    return true
end

function addon:StopFollowing()
    DB().followName = nil
    followLast = nil
    if followArrow then followArrow:Hide() end
    Print("follow arrow off")
end

local function UpdateFollow(dt)
    local db = DB()
    if not db or not followArrow then return end
    followTimer = followTimer + dt
    if followTimer < 0.05 then return end
    followTimer = 0
    local name = db.followName
    if not name or api.ShouldHide() or not addon.ModuleOn("follow") then followArrow:Hide(); return end
    followArrow:Show()
    followArrow:SetAlpha(db.alpha)
    local unit = api.FindUnit(name)
    if not unit then
        followArrow.arrow:Hide()
        followArrow.title:SetText(name)
        followArrow.sub:SetText("|cffaaaaaaNot in your group|r")
        return
    end
    local ux, uy, uinst = hbd:GetUnitWorldPosition(unit)
    if ux then
        followLast = { x = ux, y = uy, instance = uinst, t = GetTime() }
        api.PointAt(followArrow, uinst, ux, uy, name)
    elseif followLast and GetTime() - followLast.t < 600 then
        followArrow:SetAlpha(db.alpha * 0.55)
        api.PointAt(followArrow, followLast.instance, followLast.x, followLast.y, name,
            string.format("last seen %ds ago - ", math.floor(GetTime() - followLast.t)))
    else
        followArrow.arrow:Hide()
        followArrow.title:SetText(name)
        followArrow.sub:SetText("|cffaaaaaaToo far away to track|r")
    end
end

local setup = CreateFrame("Frame")
pcall(setup.RegisterEvent, setup, "PLAYER_LOGIN")
setup:SetScript("OnEvent", function()
    mineArrow = api.MakeArrow("MineArrow", 64, "mine")
    mineArrow:Hide()
    corpseArrow = api.MakeArrow("CorpseArrow", 72, "corpse")
    corpseArrow:Hide()
    followArrow = api.MakeArrow("FollowArrow", 64, "follow")
    followArrow:Hide()
    followArrow:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then addon:OpenFollowMenu() end
    end)
    compass = MakeCompass()
    addon:ApplyAll()
end)

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    UpdateMine(dt)
    UpdateCompass(dt)
    UpdateCorpse(dt)
    UpdateFollow(dt)
end)

-- style and position for the corpse and follow arrows
do
    local style, layout = addon.ApplyStyle, addon.ApplyLayout
    function addon:ApplyStyle()
        style(self)
        if corpseArrow then
            corpseArrow.arrow:SetTexture(api.StyleTexture())
            corpseArrow.arrow:SetVertexColor(unpack(CORPSE_COLOR))
        end
        if followArrow then
            followArrow.arrow:SetTexture(api.StyleTexture())
            followArrow.arrow:SetVertexColor(unpack(FOLLOW_COLOR))
        end
    end
    function addon:ApplyLayout()
        layout(self)
        local db = DB()
        if corpseArrow and db then
            local p = db.pos.corpse or { point = "TOP", x = 0, y = -180 }
            corpseArrow:ClearAllPoints()
            corpseArrow:SetPoint(p.point, UIParent, p.point, p.x, p.y)
            corpseArrow:SetScale(db.scale)
        end
        if followArrow and db then
            local p = db.pos.follow or { point = "TOP", x = 0, y = -260 }
            followArrow:ClearAllPoints()
            followArrow:SetPoint(p.point, UIParent, p.point, p.x, p.y)
            followArrow:SetScale(db.scale)
        end
    end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Extras.lua"] = true end end
