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
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                local watched = false
                if C_QuestLog.GetQuestWatchType then
                    watched = C_QuestLog.GetQuestWatchType(info.questID) ~= nil
                elseif C_QuestLog.IsQuestWatched then
                    watched = C_QuestLog.IsQuestWatched(info.questID) and true or false
                end
                out[#out + 1] = { id = info.questID, title = info.title or "Quest", complete = done and true or false,
                                  watched = watched, level = info.level, group = info.suggestedGroup }
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local n = GetNumQuestLogEntries()
        for i = 1, n do
            local title, qLevel, suggested, isHeader, _, isComplete, _, questId = GetQuestLogTitle(i)
            if title and not isHeader and questId then
                local watched = IsQuestWatched and IsQuestWatched(i) and true or false
                out[#out + 1] = { id = questId, title = title, complete = (isComplete == 1 or isComplete == true),
                                  watched = watched, level = qLevel, group = tonumber(suggested) }
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
            if Wanted(g, keepGrey) then mine.groups[#mine.groups + 1] = g else mine.skipped = mine.skipped + 1 end
        end
    end
    return true
end

-- XP a quest gives me now (Questie's own table, already scaled for my level), and whether it is grey
local function QuestXPNow(id)
    local ql = _G.QuestieLoader
    if not ql then return 0 end
    local ok, mod = pcall(ql.ImportModule, ql, "QuestXP")
    if not ok or not mod or not mod.GetQuestLogRewardXP then return 0 end
    local ok2, xp = pcall(mod.GetQuestLogRewardXP, mod, id, false)
    return (ok2 and tonumber(xp)) or 0
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
                    if total >= 4 then
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

function addon.ArrowTarget()
    local db = DB()
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
    elseif src == "partner" then
        local pt = PartnerTarget()
        if pt then return pt end
    end
    return (db.waypoints and db.waypoints[1]) or addon.SimpleTarget()
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
local planActive    -- a plan is being followed (it refills itself when it runs out)

-- Quests I can pick up in this zone (Questie already works out which ones I may take), worth doing
-- by colour, nearest givers first. Used when none of my own quests are here.
local function CollectGivers(zoneId, pinst, from)
    local ql = _G.QuestieLoader
    local QDB = api.GetQuestie()
    if not (ql and QDB and zoneId) then return {} end
    local ok, AQ = pcall(ql.ImportModule, ql, "AvailableQuests")
    local avail = ok and AQ and AQ.__availableQuests
    if type(avail) ~= "table" then return {} end
    local out = {}
    for id in pairs(avail) do
        local level = QDB.QueryQuestSingle(id, "questLevel")
        local need = QDB.QueryQuestSingle(id, "requiredLevel") or 0     -- Questie can list quests above my level
        local g = { id = id, level = level, complete = false, grey = IsGrey(QDB, level) }
        g.tier = Tier(level, g.grey)
        if need <= (UnitLevel("player") or 1) and not g.grey and Wanted(g) then
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
    local ql = _G.QuestieLoader
    local okAQ, AQ = pcall(function() return ql and ql:ImportModule("AvailableQuests") end)
    local avail = okAQ and AQ and AQ.__availableQuests
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
function addon:PlanRoute(allZones, quiet, auto)
    local Print = quiet and function() end or Print
    local db = DB()
    if not api.QuestieReady() then Print("planning needs Questie loaded and ready"); return end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then Print("can't read your position here"); return end
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

    local skipGrey = db.planSkipGrey ~= false
    local zoneId = hbd:GetPlayerZone()
    lastPlanZone, lastPlanAll = zoneId, allZones and not auto
    local here0 = { x = px, y = py }
    local pool, elsewhere, otherZone, greyCount, totalXP = {}, 0, 0, mine.skipped or 0, 0
    local groupSkipped = 0
    for _, g in ipairs(mine.groups) do
        if db.planSkip and g.id and db.planSkip[g.id] then
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
            if not (db.planSkip and db.planSkip[g.id]) then
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
            if not have[g.id] and not (db.planSkip and db.planSkip[g.id]) then
                pool[#pool + 1] = { g = g, spawns = Thin(g.spawns), w = Weight(g) * 1.5 }
                totalXP = totalXP + (g.xp or 0)
            end
        end
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
                    local w = item.w
                    for k, other in ipairs(pool) do
                        if k ~= i and not other.locked and closest(other, s) then w = w + other.w end
                    end
                    local score = w / (Dist(s, cur) + 100)
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
                seq[#seq + 1] = { label = d.item.g.label, s = d.s, w = d.item.w, qid = d.item.qid, turn = d.item.turn,
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
            cum = cum + Dist(prev, e.s)
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
                            uiMapId = st.s.uiMapId, zx = st.s.zx, zy = st.s.zy, quests = st.quests }
    end

    db.waypoints = list
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
    if otherZone > 0 then
        Print(string.format("%d quest%s in other zones left out. /lazy plan all includes them", otherZone, otherZone == 1 and "" or "s"))
    end
    if elsewhere > 0 then Print(string.format("%d quest%s on another continent left out", elsewhere, elsewhere == 1 and "" or "s")) end
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
    if db.planAuto == false then return end
    local wps = db.waypoints
    if #wps == 0 and planActive then
        -- the last stop was the quest giver: now the new quest's objectives become the plan
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
    Print(string.format("added %s to your plan as stop %d%s", g.label, bestPos + 1,
        bestPos == 0 and " (next up)" or ""))
end

local planEvents = CreateFrame("Frame")
pcall(planEvents.RegisterEvent, planEvents, "QUEST_ACCEPTED")
planEvents:SetScript("OnEvent", function(_, _, a, b)
    local id = tonumber(b) or tonumber(a)     -- classic: (logIndex, questId), newer: (questId)
    if not id then return end
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
            if planActive and #DB().waypoints == 0 then pcall(addon.PlanRoute, addon, false, true) end
        end)
    end
end

-- Walked or flew into a new zone: the plan only covers the zone it was made in, so build it again here.
local function ReplanForZone()
    local db = DB()
    if db.planAuto == false or db.planZoneOnly == false or lastPlanAll then return end
    local wps = db.waypoints
    if not wps or (#wps > 0 and not (wps[1] and wps[1].label)) then return end   -- keep my own waypoints
    if UnitOnTaxi and UnitOnTaxi("player") then return end              -- the landing will trigger this again
    if UnitIsGhost and UnitIsGhost("player") then return end
    local zone = hbd:GetPlayerZone()
    if not zone or zone == lastPlanZone then return end
    addon:PlanRoute(false, true)
    local now = db.waypoints
    if now and now[1] and now[1].label then
        Print(string.format("new zone, plan rebuilt: %d stop%s. First: %s", #now, #now == 1 and "" or "s", now[1].name))
    end
end

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
    addon:PlanRoute(lastPlanAll and true or false, true)
    local after = db.waypoints
    if after and after[1] and after[1].label then
        Print("quest progress, plan updated. Next: " .. after[1].name)
    end
end

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
local planOnEvent = planEvents:GetScript("OnEvent")
planEvents:SetScript("OnEvent", function(self, event, ...)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() pcall(ReplanForZone) end)       -- let the position settle
        end
        return
    end
    return planOnEvent(self, event, ...)
end)

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
    ReplanAfterSkip()
end

addon.SkipQuest = SkipQuest

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
    local wp = db.waypoints[1]
    if not (wp and wp.label) then Print("no plan stop to skip. /lazy plan builds a plan"); return end
    skipMenu = skipMenu or BuildSkipMenu()
    local f = skipMenu
    f.title:SetText(wp.name or wp.label)
    local items = {}
    for _, q in ipairs(wp.quests or {}) do
        local slow = addon.HiveQuestSlow and addon.HiveQuestSlow(q.id)
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
        addon:RemoveWaypoint(1)
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

    elseif cmd == "plan" or cmd == "route!" then
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
