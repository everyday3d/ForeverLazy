-- Quest helpers: a button for quest items, what comes next in a chain, a pick for the quest reward, and where to farm.
--   (quest item buttons appear by themselves; drag the first one to move it, they follow)
--   /lazy chain [go]     the follow-up quest after the one I just handed in
--   /lazy farm [n]       best place to get the item my quest needs
-- Quest and drop data come from Questie.
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
-- 1. Quest item buttons
--------------------------------------------------------------------------------
local MAXB = 3
local buttons = {}
local pendingRefresh

local function MakeButton(i)
    local b = CreateFrame("Button", "ForeverLazy_QuestItem" .. i, UIParent, "SecureActionButtonTemplate")
    b:SetSize(40, 40)
    b:SetFrameStrata("MEDIUM")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "macro")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -2, 2); b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.border:SetColorTexture(1, 0.82, 0, 0.35)
    b.border:SetDrawLayer("BACKGROUND")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
    b:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if i == 1 then
        b:SetMovable(true)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            if not InCombatLockdown() and not DB().locked then self:StartMoving() end
        end)
        b:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            DB().pos.questItem = { point = point, x = x, y = y }
        end)
        local p = DB() and DB().pos.questItem or { point = "BOTTOM", x = -230, y = 230 }
        b:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    else
        b:SetPoint("LEFT", buttons[i - 1], "RIGHT", 6, 0)
    end
    b:Hide()
    buttons[i] = b
    return b
end

-- an item that only STARTED a quest (it is in the quest's "started by" and is not one of its objectives or needed items)
-- has done its job once the quest is in my log
function addon.IsStarterOnlyItem(questId, itemId)
    local data = ns and ns.data
    if not (questId and itemId and data and data.Field) then return false end
    local okS, by = pcall(data.Field, "quests", questId, "startedBy")
    if not (okS and type(by) == "table" and type(by[3]) == "table") then return false end
    local starter = false
    for _, v in pairs(by[3]) do if v == itemId then starter = true; break end end
    if not starter then return false end
    local okO, o = pcall(data.Field, "quests", questId, "objectives")
    if okO and type(o) == "table" then
        for _, e in ipairs(o[3] or {}) do if e[1] == itemId then return false end end
    end
    local okR, req = pcall(data.Field, "quests", questId, "requiredSourceItems")
    if okR and type(req) == "table" then
        for _, v in pairs(req) do if v == itemId then return false end end
    end
    return true
end

local function QuestItems()
    local items, seen = {}, {}
    local currentQuest
    local function add(link)
        local itemStr = link and link:match("item:%d+")
        -- a key opens a gate or door when I walk up to it: no button for it (this covers the "item the quest gives me" fallback too)
        if itemStr and addon.IsKeyItem and addon.IsKeyItem(link) then return end
        if itemStr and currentQuest and addon.IsStarterOnlyItem(currentQuest, tonumber(itemStr:match("%d+"))) then return end
        if itemStr and not seen[itemStr] then
            seen[itemStr] = true
            items[#items + 1] = { link = link, itemStr = itemStr, icon = select(10, GetItemInfo(link)) or GetItemIcon(itemStr) }
        end
    end
    local n = (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, n do
        if GetQuestLogSpecialItemInfo then
            local ok, link, _, _, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, i)
            currentQuest = nil
            if GetQuestLogTitle then
                local okT, _, _, _, isHeader, _, _, _, qid = pcall(GetQuestLogTitle, i)
                if okT and not isHeader and qid and qid ~= 0 then currentQuest = qid end
            end
            if ok and link and not (addon.IsKeyItem and addon.IsKeyItem(link)) then add(link) end
            currentQuest = nil
        end
    end
    -- fallback: the item a quest gives me to use (Questie knows it)
    if #items == 0 and api.ReadQuestLog and api.QuestieReady and api.QuestieReady() then
        local QDB = api.GetQuestie()
        for _, q in ipairs(api.ReadQuestLog()) do
            if not q.complete then
                local itemId = QDB.QueryQuestSingle(q.id, "sourceItemId")
                if itemId and itemId > 0 and GetItemCount(itemId) > 0 then
                    local _, link = GetItemInfo(itemId)
                    currentQuest = q.id
                    add(link or ("item:" .. itemId))
                    currentQuest = nil
                end
            end
        end
    end
    return items
end

local function RefreshItems()
    pendingRefresh = false
    local db = DB()
    if not db then return end
    if InCombatLockdown() then pendingRefresh = true; return end
    local items = db.questItemButton ~= false and not db.planPaused and addon.ModuleOn("quests") and QuestItems() or {}
    for i = 1, MAXB do
        local b = buttons[i] or MakeButton(i)
        local it = items[i]
        if it then
            b.link = it.link
            b:SetAttribute("macrotext", "/use " .. it.itemStr)
            b.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            b:Show()
        else
            b.link = nil
            b:Hide()
        end
    end
end

addon.RefreshQuestItems = RefreshItems

--------------------------------------------------------------------------------
-- 2. What comes next in the chain
--------------------------------------------------------------------------------
local chainNext

local function Giver(QDB, id)
    local by = QDB.QueryQuestSingle(id, "startedBy")
    local spawns = {}
    if by then api.AddNpcs(spawns, by[1]); api.AddObjects(spawns, by[2]) end
    local npc = by and by[1] and by[1][1] and QDB.QueryNPCSingle(by[1][1], "name")
    return spawns, npc
end

local function NearestSpawn(spawns)
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local best, bd
    for _, s in ipairs(spawns) do
        local d = (px and s.instance == pinst) and Dist(s, { x = px, y = py }) or nil
        if not best or (d and (not bd or d < bd)) then best, bd = s, d end
    end
    return best, bd
end

local function AnnounceChain(doneId)
    local db = DB()
    if not db or db.chainHint == false or not addon.ModuleOn("quests") then return end
    if not (api.QuestieReady and api.QuestieReady()) then return end
    local QDB = api.GetQuestie()
    local nxt = QDB.QueryQuestSingle(doneId, "nextQuestInChain")
    if not nxt or nxt == 0 then chainNext = nil; return end
    local steps, cur = 0, nxt
    while cur and cur ~= 0 and steps < 12 do
        steps = steps + 1
        cur = QDB.QueryQuestSingle(cur, "nextQuestInChain")
    end
    local spawns, npc = Giver(QDB, nxt)
    local s, d = NearestSpawn(spawns)
    chainNext = { id = nxt, spawn = s, name = QDB.QueryQuestSingle(nxt, "name") or ("quest " .. nxt) }
    local where = "location unknown"
    if s then
        where = (d and d < 60) and ("right here" .. (npc and (", " .. npc) or ""))
            or string.format("%s%s %.0f, %.0f%s", npc and (npc .. ", ") or "", MapName(s.uiMapId), s.zx * 100, s.zy * 100,
                d and string.format(" (about %d yards)", d) or "")
    end
    Print(string.format(L("next in the chain: %s (level %s) - %s%s"), chainNext.name,
        tostring(QDB.QueryQuestSingle(nxt, "questLevel") or "?"), where,
        steps > 1 and string.format(". %d more steps after it", steps - 1) or ". The last step"))
    if s and not (d and d < 60) then Print(L("  /lazy chain go puts a waypoint on it")) end
end

--------------------------------------------------------------------------------
-- 3. Reward picker
--------------------------------------------------------------------------------
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

local function RewardButton(i)
    local b
    if QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons then b = QuestInfoRewardsFrame.RewardButtons[i] end
    return b or _G["QuestInfoItem" .. i]
end

local marks = {}
local function ClearMarks() for _, m in pairs(marks) do m:Hide() end end

-- Which gear is an upgrade for my class and spec is worked out in Gear.lua (addon.GearGain), the same scoring the gear advisor uses.

local function EvaluateRewards(retry)
    local db = DB()
    if not db or db.rewardPick == false or not addon.ModuleOn("quests") then return end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 2 then return end
    local me = UnitLevel("player") or 1
    local best, bestGain, bestSell, bestSellIdx, bestNote
    local missing
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        if not link then missing = true else
            local name, _, _, ilvl, minLevel, _, _, _, equipLoc, _, sell = GetItemInfo(link)
            if not name then missing = true else
                local slots = SLOTS[equipLoc]
                local usable = slots and IsEquippableItem and IsEquippableItem(link)
                if usable and IsUsableItem then
                    local u = IsUsableItem(link)
                    if u == false then usable = false end
                end
                if usable and (minLevel or 0) <= me then
                    local gain, note = addon.GearGain and addon.GearGain(link, slots, equipLoc, ilvl)       -- the shared scorer (Gear.lua)
                    if gain and gain > 0 and (not bestGain or gain > bestGain) then best, bestGain, bestNote = i, gain, note end
                end
                if not bestSell or (sell or 0) > bestSell then bestSell, bestSellIdx = sell or 0, i end
            end
        end
    end
    if missing and not retry and C_Timer then
        C_Timer.After(0.6, function() EvaluateRewards(true) end)    -- item data was not loaded yet
        return
    end
    local pick, why
    if best then
        pick, why = best, bestNote or string.format("likely upgrade (+%.0f)", bestGain)
    elseif bestSellIdx then
        pick, why = bestSellIdx, "highest vendor price " .. (GetCoinTextureString and GetCoinTextureString(bestSell) or tostring(bestSell))
    end
    if not pick then return end
    ClearMarks()
    local btn = RewardButton(pick)
    if btn then
        local m = marks[btn]
        if not m then
            m = btn:CreateTexture(nil, "OVERLAY")
            m:SetSize(26, 26)
            m:SetPoint("TOPRIGHT", 6, 6)
            m:SetTexture("Interface\\Common\\ReputationStar")
            m:SetTexCoord(0, 0.5, 0, 0.5)
            marks[btn] = m
        end
        m:Show()
    end
    Print(string.format(L("reward pick: %s - %s"), GetQuestItemLink("choice", pick) or ("choice " .. pick), why))
end

--------------------------------------------------------------------------------
-- 4. Where to farm
--------------------------------------------------------------------------------
local function OpenItemTargets(QDB, questId)
    local obj = QDB.QueryQuestSingle(questId, "objectives")
    local items = {}
    if type(obj) == "table" and obj[3] then
        local open = {}
        if C_QuestLog and C_QuestLog.GetQuestObjectives then
            local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questId)
            if ok and type(objs) == "table" then
                for _, o in ipairs(objs) do
                    if not o.finished and o.text then open[#open + 1] = o.text:lower() end
                end
            end
        end
        local all = {}
        for _, c in pairs(obj[3]) do
            if c[1] then
                all[#all + 1] = c[1]
                local nm = QDB.QueryItemSingle(c[1], "name")
                for _, t in ipairs(open) do
                    if nm and t:find(nm:lower(), 1, true) then items[#items + 1] = c[1]; break end
                end
            end
        end
        if #items == 0 then items = all end
    end
    return items
end

local function FarmQuestId()
    local wp = DB().waypoints[1]
    if wp and wp.quests and wp.quests[1] and wp.quests[1].id then return wp.quests[1].id end
    if GetQuestLogSelection and GetQuestLogTitle then
        local i = GetQuestLogSelection()
        if i and i > 0 then
            local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not isHeader and id and id ~= 0 then return id end
        end
    end
end

local farmList = {}
local function Farm(pick)
    if not (api.QuestieReady and api.QuestieReady()) then Print(L("needs Questie loaded and ready")); return end
    local QDB = api.GetQuestie()
    local qid = FarmQuestId()
    if not qid then Print(L("select a quest in your log (or have one at stop 1 of the plan) first")); return end
    local items = OpenItemTargets(QDB, qid)
    if #items == 0 then Print((QDB.QueryQuestSingle(qid, "name") or "that quest") .. L(" has no item to collect")); return end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then Print(L("I can't read your position here")); return end
    local me = UnitLevel("player") or 1
    local here = { x = px, y = py }
    local results = {}
    for _, itemId in ipairs(items) do
        local itemName = QDB.QueryItemSingle(itemId, "name") or "the item"
        local drops = QDB.QueryItemSingle(itemId, "npcDrops")
        local n = 0
        for _, npcId in pairs(drops or {}) do
            n = n + 1
            if n > 40 then break end
            local sp = {}
            api.AddNpcs(sp, { npcId })
            local mine = {}
            for _, s in ipairs(sp) do if s.instance == pinst then mine[#mine + 1] = s end end
            if #mine > 0 then
                local rate = 10
                if QDB.GetItemDroprate then
                    local ok, r = pcall(QDB.GetItemDroprate, itemId, npcId)
                    if ok and type(r) == "table" and tonumber(r[1]) then rate = tonumber(r[1]) end
                end
                local maxL = QDB.QueryNPCSingle(npcId, "maxLevel") or me
                local rank = QDB.QueryNPCSingle(npcId, "rank") or 0
                local fit = (maxL <= me + 2) and 1 or 0.4
                if rank and rank > 0 then fit = fit * 0.2 end
                -- the spot with the most of these mobs close together, weighed against the walk
                local bestS, bestScore, bestCount
                for i = 1, math.min(#mine, 150) do
                    local c = 0
                    for j = 1, math.min(#mine, 150) do
                        if Dist(mine[i], mine[j]) < 120 then c = c + 1 end
                    end
                    local d = Dist(here, mine[i])
                    local score = math.max(rate, 1) * c * fit / (d + 300)
                    if not bestScore or score > bestScore then bestS, bestScore, bestCount = mine[i], score, c end
                end
                results[#results + 1] = { npc = QDB.QueryNPCSingle(npcId, "name"), item = itemName, rate = rate, spawn = bestS,
                                          score = bestScore, count = bestCount, d = Dist(here, bestS),
                                          lo = QDB.QueryNPCSingle(npcId, "minLevel"), hi = maxL, rank = rank }
            end
        end
    end
    table.sort(results, function(a, b) return a.score > b.score end)
    if #results == 0 then Print(L("no drop sources found on this continent")); return end
    farmList = results
    pick = math.min(math.max(tonumber(pick) or 1, 1), #results)
    for i = 1, math.min(3, #results) do
        local r = results[i]
        Print(string.format(L("%s%d. %s (level %s%s)%s drops %s ~%s%% - %s %.0f, %.0f, %d nearby, about %d yards"), i == pick and "> " or "  ", i,
            r.npc or "?", tostring(r.lo or "?"), (r.hi and r.hi ~= r.lo) and ("-" .. r.hi) or "", (r.rank and r.rank > 0) and " elite" or "",
            r.item, string.format("%.0f", r.rate), MapName(r.spawn.uiMapId), r.spawn.zx * 100, r.spawn.zy * 100, r.count, r.d))
    end
    local r = results[pick]
    local wps = DB().waypoints
    for i = #wps, 1, -1 do if wps[i].farm then table.remove(wps, i) end end
    addon:AddWaypointZone(r.spawn.uiMapId, r.spawn.zx, r.spawn.zy, "Farm: " .. (r.npc or "mobs"))
    if DB().waypoints[1] then
        DB().waypoints[1].farm = true
        DB().waypoints[1].detail = string.format("Kill %s for %s", r.npc or "them", r.item)
    end
end

--------------------------------------------------------------------------------
-- Events and commands
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED",
                     "UNIT_QUEST_LOG_CHANGED", "QUEST_TURNED_IN", "QUEST_COMPLETE", "QUEST_FINISHED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local scheduled
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "QUEST_TURNED_IN" then
        local id = arg1
        if C_Timer then C_Timer.After(1.5, function() pcall(AnnounceChain, id) end) end
        return
    elseif event == "QUEST_COMPLETE" then
        if C_Timer then C_Timer.After(0.2, function() pcall(EvaluateRewards) end) end
        return
    elseif event == "QUEST_FINISHED" then
        ClearMarks()
        return
    end
    if scheduled or not C_Timer then return end
    scheduled = true
    C_Timer.After(0.5, function() scheduled = false; pcall(RefreshItems) end)
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    local arg = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if word == "chain" then
        if not chainNext then Print(L("no follow-up quest known. It shows after you hand a quest in.")); return true end
        if arg == "go" then
            if chainNext.spawn then
                addon:AddWaypointZone(chainNext.spawn.uiMapId, chainNext.spawn.zx, chainNext.spawn.zy, "Next: " .. chainNext.name)
            else
                Print(L("I don't know where that quest starts"))
            end
        else
            Print(L("next in the chain: ") .. chainNext.name .. L(". /lazy chain go puts a waypoint on it"))
        end
        return true
    elseif word == "farm" then
        Farm(tonumber(arg))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Quests.lua"] = true end end
