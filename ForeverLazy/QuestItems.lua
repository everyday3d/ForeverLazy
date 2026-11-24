-- Quest item reminders: some quests hand you an item you have to USE (on a mob, at a spot). When you are standing where the quest
-- wants it - or you have its mob targeted - a button with the item's icon appears; click it to use the item. A short chat line
-- says which item and which quest, once per visit.
--   Shift-drag the button to move it.   Switch it off in the options (Quests).
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local data = ns.data
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On()
    local db = DB()
    return db and db.questItemReminder == true and addon.ModuleOn("quests")          -- off unless I turn it on
end

local NEAR = 45          -- yards from where the quest wants it
local MAX = 3            -- buttons at most

--------------------------------------------------------------------------------
-- The quests in my log that come with a usable item
--------------------------------------------------------------------------------
local function SpecialItem(index)
    local fn = GetQuestLogSpecialItemInfo or (C_QuestLog and C_QuestLog.GetQuestLogSpecialItemInfo)
    if not fn then return nil end
    local ok, link, icon, charges, showWhenComplete = pcall(fn, index)
    if ok and link then return link, icon, charges, showWhenComplete end
end

local spotCache = {}
local function Spots(qid)
    local c = spotCache[qid]
    if c then return c end
    local list = {}
    local o = data.Field("quests", qid, "objectives")
    if type(o) == "table" then
        local npcs, objects = {}, {}
        for _, e in ipairs(o[1] or {}) do if e[1] then npcs[#npcs + 1] = e[1] end end
        for _, e in ipairs(o[5] or {}) do
            if type(e[1]) == "table" then for _, n in ipairs(e[1]) do npcs[#npcs + 1] = n end elseif e[1] then npcs[#npcs + 1] = e[1] end
        end
        for _, e in ipairs(o[2] or {}) do if e[1] then objects[#objects + 1] = e[1] end end
        if #npcs > 0 and api.AddNpcs then pcall(api.AddNpcs, list, npcs) end
        if #objects > 0 and api.AddObjects then pcall(api.AddObjects, list, objects) end
        c = { spots = list, npcs = {} }
        for _, n in ipairs(npcs) do c.npcs[n] = true end
    else
        c = { spots = list, npcs = {} }
    end
    spotCache[qid] = c
    return c
end

local function TargetNpc()
    if not UnitExists("target") then return nil end
    local ok, guid = pcall(UnitGUID, "target")
    if not ok or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- quests whose item I should be using right now: { { qid, title, link, icon, itemId } ... }
local function Wanted()
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
    local hbd = api and api.hbd
    local px, py, pinst; if hbd then px, py, pinst = hbd:GetPlayerWorldPosition() end
    local tn = TargetNpc()
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local link, icon, _, showWhenComplete = SpecialItem(i)
            if link then
                local complete = C_QuestLog.IsComplete and select(2, pcall(C_QuestLog.IsComplete, info.questID))
                if not complete or showWhenComplete then
                    local c = Spots(info.questID)
                    local here = tn and c.npcs[tn] and true or false
                    if not here and px then
                        for _, s in ipairs(c.spots) do
                            if s.instance == pinst and s.x and s.y then
                                local dx, dy = s.x - px, s.y - py
                                if dx * dx + dy * dy <= NEAR * NEAR then here = true; break end
                            end
                        end
                    end
                    if here then
                        out[#out + 1] = { qid = info.questID, title = tostring(info.title or "quest"), link = link, icon = icon,
                                          itemId = tonumber(tostring(link):match("item:(%d+)")) }
                        if #out >= MAX then break end
                    end
                end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- The buttons (secure, so a click really uses the item)
--------------------------------------------------------------------------------
local holder, buttons = nil, {}

local function Build()
    holder = CreateFrame("Frame", "ForeverLazyQuestItems", UIParent)
    holder:SetSize(48, 48)
    holder:SetFrameStrata("MEDIUM")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    local pos = DB() and DB().questItemPos
    if pos then holder:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230) end
    for i = 1, MAX do
        local b = CreateFrame("Button", "ForeverLazyQuestItemBtn" .. i, holder, "SecureActionButtonTemplate")
        b:SetSize(44, 44)
        b:SetPoint("BOTTOM", holder, "BOTTOM", (i - 2) * 50, 0)
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("type", "macro")
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.edge = b:CreateTexture(nil, "BACKGROUND")
        b.edge:SetPoint("TOPLEFT", -2, 2)
        b.edge:SetPoint("BOTTOMRIGHT", 2, -2)
        b.edge:SetColorTexture(1, 0.82, 0, 1)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints()
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function() if IsShiftKeyDown() and not InCombatLockdown() then holder:StartMoving() end end)
        b:SetScript("OnDragStop", function()
            holder:StopMovingOrSizing()
            local p, _, rp, x, y = holder:GetPoint(1)
            DB().questItemPos = { p, rp, x, y }
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self.link then GameTooltip:SetHyperlink(self.link) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Quest: " .. (self.title or ""), 1, 0.82, 0)
            GameTooltip:AddLine(L("Click to use it. Shift-drag to move."), 0.5, 1, 0.5)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        buttons[i] = b
    end
end

local told = {}          -- quest id -> time of the last chat line
local waiting = false

local function Apply()
    if not holder then return end
    if InCombatLockdown() then waiting = true; return end      -- secure buttons change only out of combat
    waiting = false
    local list = On() and Wanted() or {}
    for i = 1, MAX do
        local b, w = buttons[i], list[i]
        if w then
            b.link, b.title = w.link, w.title
            b.tex:SetTexture(w.icon)
            b:SetAttribute("macrotext", "/use " .. (w.itemId and ("item:" .. w.itemId) or tostring(w.link)))
            b:Show()
            local now = GetTime()
            if not told[w.qid] or now - told[w.qid] > 90 then
                told[w.qid] = now
                Print(L("use ") .. tostring(w.link) .. L(" here (") .. w.title .. ")")
            end
        else
            b:Hide()
        end
    end
    -- forget quests I am no longer near, so the next visit reminds again
    local have = {}
    for _, w in ipairs(list) do have[w.qid] = true end
    for qid in pairs(told) do if not have[qid] and GetTime() - told[qid] > 90 then told[qid] = nil end end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local acc = 0
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not holder then pcall(Build) end
    end
    if event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then spotCache = {} end
    if event == "PLAYER_REGEN_ENABLED" and not waiting then return end
    pcall(Apply)
end)
-- walking up to the spot: check a few times a second
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.7 then return end
    acc = 0
    if holder then pcall(Apply) end          -- also while off, so the buttons go away when I switch it off
end)

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestItems.lua"] = true end end
