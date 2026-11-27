-- Battleground helpers. Everything here is off until you turn it on (options, the Battlegrounds page).
--   timer bars: how long the queue should take, how long you have to accept, and when the battle begins
--   how long until a base that is being taken changes hands (Arathi Basin, Alterac Valley, Darkspear Islands)
--   when the flag comes back (Warsong Gulch, Darkspear Islands), and the time left in Warsong Gulch if the game says it
--   a guess at the final score, from how fast each side is scoring in this match
--   shift-click a bar to say it in battleground chat
--   Alterac Valley hand-ins and troop upgrades when you talk to the right person (hold Shift to stop it)
--   /lazy pvp [status|test|check|help]
-- With the Capping addon loaded, all of this stays out of its way.
-- Blizzard has not published the capture times, flag times or scoring rates, so none of it is confirmed until seen in game.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local B = {}
addon.BG = B

local function DB() return addon.GetDB() end
local function Opt(key) local d = DB(); return d and d[key] == true end

--------------------------------------------------------------------------------
-- Rules (pure logic: tests/battleground.lua)
--------------------------------------------------------------------------------
-- by instance id. cap: seconds to take a base. flag: seconds until the flag is back
local AB = { name = "Arathi Basin", cap = 60, score = true }
local WSG = { name = "Warsong Gulch", flag = 12, clock = true }
B.MAPS = {
    [529] = AB, [2107] = AB,
    [489] = WSG, [2106] = WSG,
    [30] = { name = "Alterac Valley", cap = 300, av = true },
    [2997] = { name = "Darkspear Islands", cap = 60, flag = 23, score = true },
}

-- the map icon numbers the game uses while a base is being taken, and by whom
B.CONTESTED = {}
for _, pair in ipairs({ { 4, 14 }, { 9, 12 }, { 17, 19 }, { 22, 24 }, { 27, 29 }, { 32, 34 }, { 37, 39 },
                        { 137, 139 }, { 142, 144 }, { 147, 149 }, { 152, 154 }, { 208, 209 }, { 213, 214 }, { 218, 219 } }) do
    B.CONTESTED[pair[1]], B.CONTESTED[pair[2]] = "alliance", "horde"
end

function B.Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- state: kept for one battleground. pois: { { name =, icon = } }
-- gives { { start = name, side = } or { stop = name } } and true when anything on the map changed.
-- What is already being taken when I arrive gets no timer: how long it has left is not known.
function B.ScanNodes(state, pois)
    local events, changed = {}, false
    if #pois == 0 then return events, false end
    local first = not state.seen
    state.seen = state.seen or {}
    for _, p in ipairs(pois) do
        if p.name and p.icon then
            local before = state.seen[p.name]
            if before ~= p.icon then
                state.seen[p.name] = p.icon
                if not first then
                    changed = true
                    local side = B.CONTESTED[p.icon]
                    if side then
                        events[#events + 1] = { start = p.name, side = side }
                    else
                        events[#events + 1] = { stop = p.name }
                    end
                end
            end
        end
    end
    return events, changed
end

-- a system message about the flag being captured (English game text). A message naming a base is about the base
function B.IsFlagCapture(msg, bases)
    if type(msg) ~= "string" then return false end
    local m = msg:lower()
    if not m:find("captured the", 1, true) then return false end
    if m:find("flag", 1, true) then return true end
    for name in pairs(bases or {}) do
        if m:find(name:lower(), 1, true) then return false end
    end
    return true
end

-- how fast each side is scoring, measured in this match
function B.NewRace() return { alliance = { rates = {} }, horde = { rates = {} } } end

local function Tick(side, now, value)
    if side.value == nil then side.value, side.since = value, now; return end
    if value == side.value then return end
    if value < side.value then
        side.rates, side.at = {}, nil
    elseif side.at then
        local gap = now - side.at
        if gap > 0.4 then
            side.rates[#side.rates + 1] = (value - side.value) / gap
            if #side.rates > 5 then table.remove(side.rates, 1) end
        end
    end
    side.value, side.at, side.since = value, now, now
end

function B.Sample(race, now, alliance, horde, max)
    race.max = max
    Tick(race.alliance, now, alliance)
    Tick(race.horde, now, horde)
end

-- a base changed hands: the old speeds no longer hold. The next score step only starts the clock again
function B.Forget(race)
    for _, side in ipairs({ race.alliance, race.horde }) do side.rates, side.at = {}, nil end
end

-- points a second, or nil when not known yet. The middle value, so one flag bonus does not count as speed
local function Rate(side, now)
    if #side.rates >= 2 then
        local sorted = {}
        for i, r in ipairs(side.rates) do sorted[i] = r end
        table.sort(sorted)
        return sorted[math.floor((#sorted + 1) / 2)]
    end
    -- not scored for a long while: treat as standing still
    if side.since and now - side.since >= 45 then return 0 end
end

-- gives winner ("alliance" or "horde"), seconds left, the winner's score and the other side's score then
function B.Predict(race, now)
    local max = race.max
    local a, h = race.alliance, race.horde
    if not max or max <= 0 or not a.value or not h.value then return end
    local ra, rh = Rate(a, now), Rate(h, now)
    if not ra or not rh or (ra <= 0 and rh <= 0) then return end
    local function Left(side, rate)
        if rate <= 0 then return math.huge end
        return math.max(0, (max - side.value) / rate - (now - (side.at or now)))
    end
    local ta, th = Left(a, ra), Left(h, rh)
    local winner, left, other, rate = "alliance", ta, h, rh
    if th < ta then winner, left, other, rate = "horde", th, a, ra end
    local final = other.value + rate * (left + (other.at and now - other.at or 0))
    final = math.max(other.value, math.min(max - 10, math.floor(final / 10 + 0.5) * 10))
    return winner, left, max, final
end

-- what a queue should show. times as the game gives them: estimate and waited in milliseconds, expires in seconds
-- gives { kind = "accept"|"wait"|"over", seconds =, total = } or nil
function B.QueueView(status, estimate, waited, expires)
    if status == "confirm" then
        if expires and expires > 0 then return { kind = "accept", seconds = expires } end
    elseif status == "queued" then
        local est, so = math.floor((estimate or 0) / 1000), math.floor((waited or 0) / 1000)
        if est > so + 1 then return { kind = "wait", seconds = est - so, total = est } end
        return { kind = "over", seconds = so }
    end
end

-- Alterac Valley. Only these are ever chosen for me; nothing that sends a wing commander out, and never a reward choice
B.AV_UPGRADES = {}
for _, id in ipairs({ 30904, 30905, 30906, 35736, 35737, 35738, 97833, 97511, 97512 }) do B.AV_UPGRADES[id] = true end
-- quest id = { item, how many it takes }
B.AV_TURNINS = {
    [6781] = { 17422, 20 }, [6741] = { 17422, 20 },                    -- armor scraps
    [7385] = { 17306, 5 }, [6801] = { 17306, 1 },                      -- blood
    [7386] = { 17423, 5 }, [6881] = { 17423, 1 },                      -- storm crystals
    [7026] = { 17643, 1 }, [7002] = { 17642, 1 },                      -- hides
}
-- supplies: handed in only when the game says the quest is complete
B.AV_SUPPLIES = { [5892] = true, [5893] = true, [6982] = true, [6985] = true }

-- options: gossip option ids. available: quest ids on offer. active: { { id =, complete = } }. count(item) -> in my bags
function B.AVPick(options, available, active, count)
    for _, q in ipairs(active or {}) do
        if B.AV_SUPPLIES[q.id] and q.complete then return "active", q.id end
    end
    for _, id in ipairs(options or {}) do
        if B.AV_UPGRADES[id] then return "option", id end
    end
    local best, bestNeed
    for _, id in ipairs(available or {}) do
        local t = B.AV_TURNINS[id]
        -- the bigger hand-in first
        if t and (count(t[1]) or 0) >= t[2] and (not bestNeed or t[2] > bestNeed) then best, bestNeed = id, t[2] end
    end
    if best then return "available", best end
end

function B.IsAVQuest(id) return (B.AV_TURNINS[id] or B.AV_SUPPLIES[id]) and true or false end

--------------------------------------------------------------------------------
-- What the game says
--------------------------------------------------------------------------------
local function Hidden(v) return issecretvalue and issecretvalue(v) and true or false end
local function Plain(v) if not Hidden(v) then return v end end

function B.CappingLoaded()
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return fn and fn("Capping") and true or false
end

local function On(key) return Opt(key) and not B.CappingLoaded() end

local function Instance()
    if not GetInstanceInfo then return nil end
    local name, kind, _, _, _, _, _, id = GetInstanceInfo()
    return Plain(id), Plain(kind), Plain(name)
end

local function Pois()
    local out = {}
    if not (C_Map and C_Map.GetBestMapForUnit and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap) then return out end
    local map = Plain(C_Map.GetBestMapForUnit("player"))
    if not map then return out end
    for _, id in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(map) or {}) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(map, id)
        if info then
            out[#out + 1] = { id = id, name = Plain(info.name), icon = Plain(info.textureIndex), atlas = Plain(info.atlasName) }
        end
    end
    return out, map
end

-- the two score bars at the top of the screen: alliance on the left
local SCORE_WIDGET = 7467
local function Score(widget)
    local fn = C_UIWidgetManager and C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo
    local info = fn and fn(widget)
    if not info then return nil end
    local a, h, max = Plain(info.leftBarValue), Plain(info.rightBarValue), Plain(info.leftBarMax)
    if type(a) ~= "number" or type(h) ~= "number" or type(max) ~= "number" or max < 500 then return nil end
    return a, h, max
end

--------------------------------------------------------------------------------
-- The timer bars
--------------------------------------------------------------------------------
local COLORS = {
    alliance = { 0.20, 0.45, 0.95 }, horde = { 0.85, 0.18, 0.15 },
    queue = { 0.45, 0.45, 0.50 }, accept = { 0.15, 0.70, 0.25 }, other = { 0.85, 0.62, 0.10 },
}
local WIDTH, HEIGHT = 220, 18
local bars = {}                    -- key -> { label, ends, total, color, kind, countFrom }
local frames = {}
local anchor, title

local function Now() return GetTime() end

local function Text(e, now)
    if e.countFrom then return e.label, B.Clock(now - e.countFrom) end
    return e.label, B.Clock(e.ends - now)
end

-- soonest at the front; the ones that count up go last
function B.Sorted(now)
    local list = {}
    for key, e in pairs(bars) do
        if not e.countFrom and e.ends <= now then bars[key] = nil
        else list[#list + 1] = { key = key, e = e } end
    end
    table.sort(list, function(x, y)
        local a, b = x.e.countFrom and math.huge or x.e.ends, y.e.countFrom and math.huge or y.e.ends
        if a ~= b then return a < b end
        return x.key < y.key
    end)
    return list
end

function B.CallText(key, now)
    local e = bars[key]
    if not e or e.kind == "queue" then return nil end
    local label, clock = Text(e, now or Now())
    return label .. ": " .. clock
end

local function Call(key)
    if not On("bgCall") or not (IsShiftKeyDown and IsShiftKeyDown()) then return end
    local text = B.CallText(key)
    if not text then return end
    local _, kind = Instance()
    if kind ~= "pvp" then Print(text); return end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then pcall(send, text, "INSTANCE_CHAT") end
end

local function SavePosition(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    local d = DB()
    d.pos = d.pos or {}
    d.pos.battleground = { point, x, y }
end

local function Build()
    if anchor then return end
    anchor = CreateFrame("Frame", "ForeverLazy_BGTimers", UIParent)
    anchor:SetSize(WIDTH, 14)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) if not Opt("bgLocked") then self:StartMoving() end end)
    anchor:SetScript("OnDragStop", SavePosition)
    title = anchor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetPoint("CENTER")
    title:SetText(L("Battleground timers (drag)"))
    local since = 0
    anchor:SetScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since < 0.1 then return end
        since = 0
        B.Paint()
    end)
    anchor:Hide()
end

local function Place()
    local d = DB()
    anchor:ClearAllPoints()
    local p = d.pos and d.pos.battleground
    if p then anchor:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else anchor:SetPoint("CENTER", UIParent, "CENTER", -320, 160) end
    anchor:SetScale(tonumber(d.bgScale) or 1)
    anchor:EnableMouse(not Opt("bgLocked"))
    title:SetShown(not Opt("bgLocked"))
end

local function Row(i)
    local f = frames[i]
    if f then return f end
    f = CreateFrame("Button", nil, anchor)
    f:SetSize(WIDTH, HEIGHT)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
    f.fill = CreateFrame("StatusBar", nil, f)
    f.fill:SetAllPoints()
    f.fill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.fill:SetMinMaxValues(0, 1)
    f.time = f.fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.time:SetPoint("RIGHT", -4, 0)
    f.label = f.fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetPoint("LEFT", 4, 0)
    f.label:SetPoint("RIGHT", f.time, "LEFT", -4, 0)
    f.label:SetJustifyH("LEFT")
    f.label:SetWordWrap(false)
    f:SetScript("OnClick", function(self) Call(self.key) end)
    frames[i] = f
    return f
end

function B.Paint()
    if not anchor then return end
    local now = Now()
    local list = B.Sorted(now)
    if #list == 0 then
        for _, f in ipairs(frames) do f:Hide() end
        anchor:Hide()
        return
    end
    local up = Opt("bgGrowUp")
    local clicks = On("bgCall")
    for i, item in ipairs(list) do
        local f, e = Row(i), item.e
        f.key = item.key
        f:ClearAllPoints()
        local off = (i - 1) * (HEIGHT + 2) + 2
        if up then f:SetPoint("BOTTOM", anchor, "TOP", 0, off) else f:SetPoint("TOP", anchor, "BOTTOM", 0, -off) end
        local label, clock = Text(e, now)
        f.label:SetText(label)
        f.time:SetText(clock)
        local c = COLORS[e.color] or COLORS.other
        f.fill:SetStatusBarColor(c[1], c[2], c[3])
        f.fill:SetValue(e.countFrom and 1 or math.max(0, math.min(1, (e.ends - now) / e.total)))
        f:EnableMouse(clicks and e.kind ~= "queue")
        f:Show()
    end
    for i = #list + 1, #frames do frames[i]:Hide() end
end

-- opts: total (a full bar), countUp (seconds already gone), kind
function B.StartBar(key, label, seconds, color, opts)
    opts = opts or {}
    local now = Now()
    bars[key] = {
        label = label, color = color, kind = opts.kind,
        ends = now + seconds, total = math.max(opts.total or seconds, seconds, 1),
        countFrom = opts.countUp and (now - seconds) or nil,
    }
    Build()
    Place()
    anchor:Show()
    B.Paint()
end

function B.StopBar(key)
    if bars[key] then bars[key] = nil; B.Paint() end
end

local function StopKind(kind)
    for key, e in pairs(bars) do if e.kind == kind then bars[key] = nil end end
    B.Paint()
end

function B.Bar(key) return bars[key] end

-- a bar that is already about right is left running
local function Keep(key, seconds, label)
    local e = bars[key]
    return e and not e.countFrom and e.label == label and math.abs((e.ends - Now()) - seconds) <= 5
end

function B.Test()
    B.StartBar("test1", L("A base being taken"), 45, "alliance", { kind = "test" })
    B.StartBar("test2", L("The flag comes back"), 20, "other", { kind = "test" })
    B.StartBar("test3", L("Waiting in the queue"), 90, "queue", { kind = "test" })
    Print(L("sample timers shown: drag the title to move them (when they are not locked)"))
end

function B.ResetBars()
    local d = DB()
    if d.pos then d.pos.battleground = nil end
    if anchor then Place() end
end

--------------------------------------------------------------------------------
-- Queues
--------------------------------------------------------------------------------
function B.Queues()
    if not On("bgQueue") then StopKind("queue"); StopKind("accept"); return end
    if not GetBattlefieldStatus then return end
    local count = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or 3
    for i = 1, count do
        local key = "queue" .. i
        local status, name = GetBattlefieldStatus(i)
        status, name = Plain(status), Plain(name)
        local view = status and B.QueueView(status,
            GetBattlefieldEstimatedWaitTime and Plain(GetBattlefieldEstimatedWaitTime(i)),
            GetBattlefieldTimeWaited and Plain(GetBattlefieldTimeWaited(i)),
            GetBattlefieldPortExpiration and Plain(GetBattlefieldPortExpiration(i)))
        name = name or L("Battleground")
        if not view then
            B.StopBar(key)
        elseif view.kind == "accept" then
            local label = name .. L(": accept now")
            if not Keep(key, view.seconds, label) then B.StartBar(key, label, view.seconds, "accept", { kind = "accept" }) end
        elseif view.kind == "wait" then
            local label = name .. L(": expected wait")
            if not Keep(key, view.seconds, label) then B.StartBar(key, label, view.seconds, "queue", { kind = "queue", total = view.total }) end
        else
            B.StartBar(key, name .. L(": waited"), view.seconds, "queue", { kind = "queue", countUp = true })
        end
    end
end

--------------------------------------------------------------------------------
-- Inside a battleground
--------------------------------------------------------------------------------
local zone                         -- B.MAPS entry while inside one I know
local nodes, race = {}, B.NewRace()
local estimate                     -- the label of the score guess on show
local messages = {}                -- the last few battleground messages, for /lazy pvp check
local ticker

local function ScanNodes()
    if not zone or not zone.cap then return end
    local events, changed = B.ScanNodes(nodes, (Pois()))
    if changed then B.Forget(race) end
    for _, e in ipairs(events) do
        if e.stop then
            B.StopBar("node:" .. e.stop)
        elseif On("bgNodes") then
            local who = e.side == "alliance" and L("Alliance") or L("Horde")
            B.StartBar("node:" .. e.start, e.start .. " (" .. who .. ")", zone.cap, e.side, { kind = "node" })
        else
            B.StopBar("node:" .. e.start)
        end
    end
end

local function ReadScore(widget)
    if not zone or not zone.score then return end
    local a, h, max = Score(widget or SCORE_WIDGET)
    if not a then return end
    local now = Now()
    B.Sample(race, now, a, h, max)
    if not On("bgScore") then return end
    local winner, left, top, other = B.Predict(race, now)
    if not winner or left < 1 then return end
    local label
    if winner == "alliance" then label = string.format(L("Guess: Alliance %d, Horde %d"), top, other)
    else label = string.format(L("Guess: Alliance %d, Horde %d"), other, top) end
    if estimate and estimate ~= label then B.StopBar("score") end
    estimate = label
    if not Keep("score", left, label) then B.StartBar("score", label, left, winner, { kind = "score" }) end
end

local function ReadClock()
    if not zone or not zone.clock or not On("bgTime") then return end
    local fn = C_UIWidgetManager and C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo
    if not fn then return end
    for _, id in ipairs({ 6, 630 }) do
        local info = fn(id)
        local text = info and Plain(info.text)
        local m, s
        if text then m, s = text:match("(%d+):(%d%d)") end
        if m then
            local left = tonumber(m) * 60 + tonumber(s)
            if left > 3 and not Keep("clock", left, L("Time left")) then
                B.StartBar("clock", L("Time left"), left, "other", { kind = "clock" })
            end
            return
        end
    end
end

local function SystemMessage(msg)
    if not zone or Hidden(msg) or type(msg) ~= "string" then return end
    messages[#messages + 1] = msg
    if #messages > 6 then table.remove(messages, 1) end
    if zone.flag and On("bgFlag") and B.IsFlagCapture(msg, nodes.seen) then
        B.StartBar("flag", L("The flag comes back"), zone.flag, "other", { kind = "flag" })
    end
end

local function LeaveZone()
    zone, nodes, race, estimate = nil, {}, B.NewRace(), nil
    for _, kind in ipairs({ "node", "flag", "score", "clock", "start" }) do StopKind(kind) end
    if ticker then ticker:Cancel(); ticker = nil end
end

function B.EnterWorld()
    local id, kind = Instance()
    local found = kind == "pvp" and B.MAPS[id] or nil
    if zone and zone == found then return end
    LeaveZone()
    zone = found
    if zone and C_Timer and C_Timer.NewTicker then
        local beat = 0
        ticker = C_Timer.NewTicker(1, function()
            beat = beat + 1
            pcall(ScanNodes)
            if beat % 5 == 0 then pcall(ReadClock) end
        end)
    end
end

function B.Zone() return zone end

-- an option changed
function B.Update()
    if not DB() then return end
    if not On("bgNodes") then StopKind("node") end
    if not On("bgFlag") then StopKind("flag") end
    if not On("bgScore") then StopKind("score"); estimate = nil end
    if not On("bgTime") then StopKind("clock") end
    if not On("bgQueue") then StopKind("start") end
    B.Queues()
    if anchor then Place(); B.Paint() end
end
addon.BattlegroundRefresh = B.Update

--------------------------------------------------------------------------------
-- Alterac Valley hand-ins
--------------------------------------------------------------------------------
local function AVOn()
    return zone and zone.av and On("bgAV") and not (IsShiftKeyDown and IsShiftKeyDown())
end

local function ItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return fn and fn(id) or 0
end

function B.Gossip()
    if not AVOn() or not C_GossipInfo then return end
    local options, available, active = {}, {}, {}
    for _, o in ipairs((C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()) or {}) do
        options[#options + 1] = Plain(o.gossipOptionID)
    end
    for _, q in ipairs((C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests()) or {}) do
        available[#available + 1] = Plain(q.questID)
    end
    for _, q in ipairs((C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()) or {}) do
        active[#active + 1] = { id = Plain(q.questID), complete = Plain(q.isComplete) and true or false }
    end
    local what, id = B.AVPick(options, available, active, ItemCount)
    if what == "option" then C_GossipInfo.SelectOption(id)
    elseif what == "available" then C_GossipInfo.SelectAvailableQuest(id)
    elseif what == "active" then C_GossipInfo.SelectActiveQuest(id) end
end

local function AVQuest(event)
    if not AVOn() or not GetQuestID or not B.IsAVQuest(Plain(GetQuestID())) then return end
    if event == "QUEST_PROGRESS" then
        if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then CompleteQuest() end
    elseif (not GetNumQuestChoices or GetNumQuestChoices() == 0) and GetQuestReward then
        GetQuestReward(0)
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_BATTLEFIELD_STATUS", "START_TIMER", "AREA_POIS_UPDATED", "UPDATE_UI_WIDGET",
                     "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL",
                     "GOSSIP_SHOW", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
    pcall(ev.RegisterEvent, ev, e)
end

function B.OnEvent(_, event, a, b)
    if not DB() then return end
    if event == "PLAYER_ENTERING_WORLD" then
        B.EnterWorld()
        B.Queues()
    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        B.Queues()
    elseif event == "START_TIMER" then
        local _, kind = Instance()
        local seconds = Plain(b)
        if kind == "pvp" and On("bgQueue") and type(seconds) == "number" and seconds > 0 then
            if not Keep("start", seconds, L("The battle begins")) then
                B.StartBar("start", L("The battle begins"), seconds, "accept", { kind = "start" })
            end
        end
    elseif event == "AREA_POIS_UPDATED" then
        ScanNodes()
    elseif event == "UPDATE_UI_WIDGET" then
        local widget = type(a) == "table" and Plain(a.widgetID)
        if widget == SCORE_WIDGET then ReadScore(widget) end
    elseif event:find("^CHAT_MSG_BG_SYSTEM") then
        SystemMessage(a)
    elseif event == "GOSSIP_SHOW" then
        B.Gossip()
    elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        AVQuest(event)
    end
end
ev:SetScript("OnEvent", function(...) pcall(B.OnEvent, ...) end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
local OPTIONS = {
    { "bgQueue", "queue and start timers" }, { "bgNodes", "base capture timers" }, { "bgFlag", "flag timer" },
    { "bgTime", "Warsong Gulch time left" }, { "bgScore", "score guess" }, { "bgCall", "shift-click to call out" },
    { "bgAV", "Alterac Valley hand-ins" },
}

local function Status()
    if B.CappingLoaded() then Print(L("the Capping addon is loaded, so our battleground helpers stay out of its way")) end
    local on = {}
    for _, o in ipairs(OPTIONS) do if Opt(o[1]) then on[#on + 1] = L(o[2]) end end
    Print(#on > 0 and (L("battleground helpers on: ") .. table.concat(on, ", "))
        or L("all battleground helpers are off (options, the Battlegrounds page)"))
end

-- everything needed to put a wrong number right
function B.CheckLines()
    local lines = {}
    local id, kind, name = Instance()
    lines[#lines + 1] = string.format("instance %s (%s) %s, known: %s", tostring(id), tostring(kind), tostring(name),
        id and B.MAPS[id] and B.MAPS[id].name or "no")
    local pois, map = Pois()
    lines[#lines + 1] = string.format("map %s, %d map points", tostring(map), #pois)
    for i = 1, math.min(#pois, 20) do
        local p = pois[i]
        lines[#lines + 1] = string.format("  point %s: %s, icon %s%s", tostring(p.id), tostring(p.name or "hidden"), tostring(p.icon),
            p.atlas and (", atlas " .. p.atlas) or "")
    end
    local m = C_UIWidgetManager
    if m and m.GetTopCenterWidgetSetID and m.GetAllWidgetsBySetID then
        for _, w in ipairs(m.GetAllWidgetsBySetID(m.GetTopCenterWidgetSetID()) or {}) do
            local a, h, max = Score(w.widgetID)
            lines[#lines + 1] = string.format("  widget %s type %s%s", tostring(w.widgetID), tostring(w.widgetType),
                a and string.format(", score %d / %d of %d", a, h, max) or "")
        end
    end
    for _, msg in ipairs(messages) do lines[#lines + 1] = "  message: " .. msg end
    return lines
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "pvp" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "" or a == "status" then Status()
        elseif a == "test" then B.Test()
        elseif a == "check" then for _, line in ipairs(B.CheckLines()) do Print(line) end
        else Print(L("/lazy pvp status, /lazy pvp test (sample timers), /lazy pvp check (in a battleground, for bug reports). Turn the helpers on in the options, under Battlegrounds.")) end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Battleground.lua"] = true end end
