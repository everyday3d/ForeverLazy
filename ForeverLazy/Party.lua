-- Party: share your plan, and see which quests you have in common with the people in your group.
--   /lazy party            quests you share with the group, and ones a friend has that you could take
--   /lazy shareplan        send your plan to the group (needs this addon on their side)
--   /lazy acceptplan       follow a plan someone sent you
-- Everything goes over this addon's own messages to your party or raid. Players without the addon see nothing.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local QUEST_PREFIX = "FLQUESTS"
local PLAN_PREFIX = "FLPLAN"

local function Channel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function Short(name) return (name or "?"):match("^([^%-]+)") or name end

-- duo mode: whoever leads the party leads the duo, so there is nothing to pick
local function IsLeaderName(name)
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and UnitName(u) == name then return UnitIsGroupLeader(u) and true or false end
    end
    for i = 1, 40 do
        local u = "raid" .. i
        if UnitExists(u) and UnitName(u) == name then return UnitIsGroupLeader(u) and true or false end
    end
    return false
end

-- two players, both with the addon: duo mode starts by itself (switch it off with /lazy duo off)
function addon.AutoDuoPartner()
    local db = addon.GetDB()
    if not db or db.duoAuto == false then return nil end
    if not (GetNumGroupMembers and GetNumGroupMembers() == 2) then return nil end
    for who in pairs(addon.partyQuests or {}) do
        if UnitInParty(who) then return who end        -- they sent me their quests, so they have the addon
    end
end

function addon.DuoRole()
    local db = addon.GetDB()
    if not db or not addon.ModuleOn("party") then return nil end
    if not (IsInGroup and IsInGroup()) then return nil end
    if not (db.duo or addon.AutoDuoPartner()) then return nil end
    return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and "lead" or "follow"
end

--------------------------------------------------------------------------------
-- Quests in common
--------------------------------------------------------------------------------
local theirs = {}                -- player name -> { ids = set, t = time }
addon.partyQuests = theirs
addon.sharedQuests = addon.sharedQuests or {}

local function Rebuild()
    if not addon.ModuleOn("party") then addon.sharedQuests = {}; return end
    local mine = {}
    if api.ReadQuestLog then for _, q in ipairs(api.ReadQuestLog()) do mine[q.id] = q end end
    local shared = {}
    for _, t in pairs(theirs) do
        for id in pairs(t.ids) do if mine[id] then shared[id] = true end end
    end
    addon.sharedQuests = shared
end

local function SendMyQuests()
    local ch = Channel()
    if not ch or not api.ReadQuestLog or not addon.ModuleOn("party") then return end
    local ids = {}
    for _, q in ipairs(api.ReadQuestLog()) do ids[#ids + 1] = q.id end
    addon:SendCommMessage(QUEST_PREFIX, addon:Serialize({ ids = ids }), ch)
end

function addon:OnPartyQuests(prefix, message, distribution, sender)
    if prefix ~= QUEST_PREFIX or not addon.ModuleOn("party") then return end
    local who = Short(sender)
    if who == UnitName("player") then return end
    local ok, t = self:Deserialize(message)
    if not ok or type(t) ~= "table" or type(t.ids) ~= "table" then return end
    local set = {}
    for _, id in ipairs(t.ids) do if type(id) == "number" then set[id] = true end end
    theirs[who] = { ids = set, t = GetTime() }
    Rebuild()
end
addon:RegisterComm(QUEST_PREFIX, "OnPartyQuests")

local function QuestName(id)
    local QDB = api.GetQuestie()
    return QDB and QDB.QueryQuestSingle(id, "name") or ("quest " .. id)
end

local function ShowParty()
    if not Channel() then Print("you are not in a group"); return end
    SendMyQuests()                      -- they will answer, and I send mine so they can compare too
    local any = false
    local mine = {}
    if api.ReadQuestLog then for _, q in ipairs(api.ReadQuestLog()) do mine[q.id] = q end end
    for who, t in pairs(theirs) do
        any = true
        local both, they = {}, {}
        for id in pairs(t.ids) do
            if mine[id] then both[#both + 1] = QuestName(id) else they[#they + 1] = id end
        end
        table.sort(both)
        Print(string.format("%s: %d quest%s in common%s", who, #both, #both == 1 and "" or "s",
            #both > 0 and (" - " .. table.concat(both, ", ", 1, math.min(#both, 6))) or ""))
        -- quests they have that I could pick up
        local QDB = api.GetQuestie()
        local could = {}
        if QDB and api.QuestieReady and api.QuestieReady() then
            for _, id in ipairs(they) do
                local okd, doable = pcall(QDB.IsDoable, id)
                local need = QDB.QueryQuestSingle(id, "requiredLevel") or 0
                if okd and doable and need <= (UnitLevel("player") or 1) then could[#could + 1] = QuestName(id) end
            end
        end
        if #could > 0 then
            table.sort(could)
            Print(string.format("  %s has %d you could take: %s", who, #could, table.concat(could, ", ", 1, math.min(#could, 5))))
        end
    end
    if not any then
        Print("nobody in your group has sent their quests yet (they need this addon). I asked, try again in a few seconds.")
    end
end

--------------------------------------------------------------------------------
-- Share the plan
--------------------------------------------------------------------------------
local received = {}      -- sender -> list of stops
local AcceptPlan          -- defined below

local function SharePlan(silent)
    local ch = Channel()
    if not ch then Print("you are not in a group"); return end
    local stops = {}
    for _, w in ipairs(DB().waypoints) do
        if w.label and w.uiMapId and w.zx and w.zy and #stops < 15 then
            stops[#stops + 1] = { label = w.label, map = w.uiMapId, zx = w.zx, zy = w.zy, detail = w.detail }
        end
    end
    if #stops == 0 then Print("you have no plan to share. /lazy plan builds one"); return end
    addon:SendCommMessage(PLAN_PREFIX, addon:Serialize({ stops = stops, lead = addon.DuoRole() == "lead" }), ch)
    if not silent then Print(string.format("sent your plan (%d stops) to the group. Players with the addon can follow it with /lazy acceptplan", #stops)) end
end

function addon:OnPartyPlan(prefix, message, distribution, sender)
    if prefix ~= PLAN_PREFIX or not addon.ModuleOn("party") then return end
    local who = Short(sender)
    if who == UnitName("player") then return end
    if not DB().acceptShared then return end
    local ok, t = self:Deserialize(message)
    if not ok or type(t) ~= "table" or type(t.stops) ~= "table" then return end
    local clean = {}
    for _, s in ipairs(t.stops) do
        if type(s) == "table" and type(s.map) == "number" and type(s.zx) == "number" and type(s.zy) == "number"
            and s.zx >= 0 and s.zx <= 1 and s.zy >= 0 and s.zy <= 1 and #clean < 15 then
            clean[#clean + 1] = { label = tostring(s.label or "Stop"):sub(1, 70), map = s.map, zx = s.zx, zy = s.zy,
                                  detail = s.detail and tostring(s.detail):sub(1, 120) or nil }
        end
    end
    if #clean == 0 then return end
    received[who] = clean
    if t.lead and addon.DuoRole() == "follow" and IsLeaderName(who) then
        addon.duoPlanAt = GetTime()
        AcceptPlan()                    -- duo mode: the leader's plan is mine
        return
    end
    Print(string.format("%s shared a plan with %d stops (first: %s). /lazy acceptplan to follow it.", who, #clean, clean[1].label))
end
addon:RegisterComm(PLAN_PREFIX, "OnPartyPlan")

AcceptPlan = function()
    local who, stops
    for w, s in pairs(received) do who, stops = w, s end     -- the latest one is enough
    if not stops then Print("nobody has shared a plan with you"); return end
    local list = {}
    for i, s in ipairs(stops) do
        local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(s.zx, s.zy, s.map)
        if wx then
            list[#list + 1] = { name = i .. ". " .. s.label, label = s.label, instance = inst, x = wx, y = wy,
                                uiMapId = s.map, zx = s.zx, zy = s.zy, detail = s.detail }
        end
    end
    if #list == 0 then Print("could not place that plan on your map"); return end
    DB().waypoints = list
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    received[who] = nil
    Print(string.format("following %s's plan: %d stops. First: %s", who, #list, list[1].name))
end

--------------------------------------------------------------------------------
-- Keep the lists fresh
--------------------------------------------------------------------------------
local pending
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GROUP_ROSTER_UPDATE")
pcall(ev.RegisterEvent, ev, "QUEST_ACCEPTED")
pcall(ev.RegisterEvent, ev, "QUEST_REMOVED")
ev:SetScript("OnEvent", function(_, event)
    if not C_Timer or not C_Timer.After then return end
    if event == "GROUP_ROSTER_UPDATE" then
        -- forget people who left
        for who in pairs(theirs) do
            if not (UnitInParty(who) or UnitInRaid(who)) then theirs[who] = nil end
        end
        if not Channel() then addon.sharedQuests = {} end
    end
    if pending then return end
    pending = true
    C_Timer.After(5, function()
        pending = false
        pcall(SendMyQuests)
        pcall(Rebuild)
    end)
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    if word == "party" then ShowParty(); return true
    elseif word == "shareplan" then SharePlan(); return true
    elseif word == "acceptplan" then AcceptPlan(); return true end
    if prev then return prev(self, cmd, rest) end
end

--------------------------------------------------------------------------------
-- Duo mode: one player leads, the other follows the leader's plan
--   /lazy duo lead      I make the plan, it goes to the group whenever it is rebuilt
--   /lazy duo follow    I take the leader's plan (my own automatic replans wait)
--   /lazy duo off
--------------------------------------------------------------------------------
local origPlan = addon.PlanRoute
local lastAuto = 0
function addon:PlanRoute(allZones, quiet, auto)
    local db = DB()
    -- while following a leader, automatic replans would overwrite their plan
    if quiet and addon.DuoRole() == "follow" and addon.duoPlanAt and GetTime() - addon.duoPlanAt < 1200 and Channel() then return end
    origPlan(self, allZones, quiet, auto)
    if addon.DuoRole() == "lead" and Channel() and GetTime() - lastAuto > 8 then
        lastAuto = GetTime()
        pcall(SharePlan, true)
    end
end

local prevDuo = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "duo" then
        local db = DB()
        local arg = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if arg == "off" then
            db.duo = nil
            db.duoAuto = false
            addon.duoPlanAt = nil
            Print("duo mode off (it will not start by itself again; /lazy duo on turns it back on)")
        elseif arg == "" or arg == "on" or arg == "lead" or arg == "follow" or arg == "leader" then
            if arg == "" and addon.DuoRole() then
                local role = addon.DuoRole()
                Print("duo mode is on" .. (addon.AutoDuoPartner() and " (started automatically)" or "") .. (role and (": you " .. (role == "lead" and "lead, your plan goes to the group" or "follow the party leader's plan")) or ", it works once you are in a group") .. ". /lazy duo off")
            else
                db.duo = true
                db.duoAuto = nil
                addon.duoPlanAt = nil
                Print("duo mode on. The party leader makes the plan and the others follow it. Shared quests count extra.")
                if addon.DuoRole() == "lead" and Channel() then pcall(SharePlan, true) end
            end
        end
        return true
    end
    if prevDuo then return prevDuo(self, cmd, rest) end
end

-- when the leader changes (or someone joins), the leader sends the plan again
local roster = CreateFrame("Frame")
pcall(roster.RegisterEvent, roster, "GROUP_ROSTER_UPDATE")
local announcedWith
roster:SetScript("OnEvent", function()
    if not C_Timer then return end
    local function check()
        local partner = addon.AutoDuoPartner()
        if partner and not DB().duo and announcedWith ~= partner then
            announcedWith = partner
            local role = addon.DuoRole()
            Print(string.format("duo mode started with %s (you %s). /lazy duo off stops it.", partner,
                role == "lead" and "lead: your plan goes to them" or "follow their plan"))
        elseif not partner then
            announcedWith = nil
        end
        if addon.DuoRole() == "lead" and Channel() then pcall(SharePlan, true) end
    end
    C_Timer.After(4, check)
    C_Timer.After(14, check)           -- their quest list may take a moment to arrive
end)

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Party.lua"] = true end end
