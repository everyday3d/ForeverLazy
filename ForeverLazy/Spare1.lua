-- Quest tooltips: hover a creature, an object or an item that one of my quests needs and the tooltip says which quest and how many
-- are done ("A Baying of Gnolls: Redridge Brute slain 3/10"), from our own quest data, and the same for each person in my group
-- who also has Forever Lazy ("Alex: Redridge Brute slain 1/10"), like Questie does.
-- When Questie is installed it already does this, so this stays quiet (no double lines). It never changes a line another addon
-- put in the tooltip; it only adds its own at the end.
--   /lazy tooltips on | off | auto     auto (the default) = on only when Questie is not installed
local ADDON, ns = ...
local addon = ns.addon
local data = ns.data
local Print = addon.Print

-- is the Questie add-on itself running? (its data add-on can be enabled without it, and that is not the same thing)
local function QuestieAddonLoaded()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not isLoaded then return false end
    local ok, v = pcall(isLoaded, "Questie")
    return ok and v and true or false
end

local function Enabled()
    local db = addon.GetDB()
    if not db then return false end
    if db.questTooltips == true then return true end
    if db.questTooltips == false then return false end
    -- auto: Questie adds these itself when it is installed (the test mode that ignores Questie turns ours on)
    return not QuestieAddonLoaded() or db.noQuestie == true
end

-- my quests and their unfinished objectives, read at most once a second
local logCache, logAt = nil, 0
local function MyQuests()
    if logCache and GetTime() - logAt < 1 then return logCache end
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives then
        for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
            local ok, info = pcall(C_QuestLog.GetInfo, i)
            if ok and type(info) == "table" and not info.isHeader and info.questID then
                local okO, objs = pcall(C_QuestLog.GetQuestObjectives, info.questID)
                out[#out + 1] = { id = info.questID, title = info.title, objectives = okO and objs or {} }
            end
        end
    end
    logCache, logAt = out, GetTime()
    return out
end

-- does an objective group of a quest (creatures = 1, objects = 2, items = 3, kill credit = 5) name this id?
local function Names(group, id)
    for _, e in ipairs(group or {}) do
        local ref = e[1]
        if ref == id then return true end
        if type(ref) == "table" then for _, r in ipairs(ref) do if r == id then return true end end end
    end
    return false
end

local AugmentNow
-- Once per hover: the game rebuilds a tooltip several times while the mouse rests on something, and every rebuild fires the
-- events again. A tooltip remembers what I already added to it (cleared when the tooltip is cleared).
-- The lines are added right when the tooltip is built, and the tooltip is never told to show again (that makes some bag
-- addons re-anchor it and flash a second copy).
local function Augment(tooltip, kind, id)
    local key = kind .. ":" .. tostring(id)
    if tooltip.flqtAdded == key then return end
    tooltip.flqtAdded = key
    pcall(AugmentNow, tooltip, kind, id)
end
-- add the lines for one creature (kind "npc"), object ("object") or item ("item"):
-- for each quest that needs it, what I still need, and what each person in my group still needs
AugmentNow = function(tooltip, kind, id)
    if not (tooltip and id and Enabled()) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local groupFor = { npc = { 1, 5 }, object = { 2 }, item = { 3 } }
    local store = { npc = "npcs", object = "objects", item = "items" }
    local name = data.Field(store[kind], id, "name")
    local lowName = name and name:lower()

    local function Needs(qid)
        local objectives = data.Field("quests", qid, "objectives")
        if type(objectives) ~= "table" then return false end
        for _, g in ipairs(groupFor[kind]) do if Names(objectives[g], id) then return true end end
        return false
    end
    local function Matching(texts)
        local out = {}
        for _, text in ipairs(texts or {}) do
            if not lowName or text:lower():find(lowName, 1, true) then out[#out + 1] = text end
        end
        return out
    end

    local perQuest, order = {}, {}
    local function Entry(qid, title)
        local e = perQuest[qid]
        if not e then e = { title = title or data.Field("quests", qid, "name") or ("quest " .. qid), lines = {} }; perQuest[qid] = e; order[#order + 1] = qid end
        return e
    end

    -- mine: the quest is always named, finished objectives are shown in green so you can see it is done
    for _, q in ipairs(MyQuests()) do
        if Needs(q.id) then
            local e = Entry(q.id, q.title)
            local any = false
            for _, o in ipairs(q.objectives or {}) do
                if o.text and o.text ~= "" and (not lowName or o.text:lower():find(lowName, 1, true)) then
                    any = true
                    if o.finished then
                        e.lines[#e.lines + 1] = { text = o.text .. "  (done)", r = 0.45, g = 1, b = 0.45 }
                    else
                        e.lines[#e.lines + 1] = { text = o.text }
                    end
                end
            end
            -- nothing in the log text mentions it by name: still say the quest needs it
            if not any then e.lines[#e.lines + 1] = { text = "needed for this quest", r = 0.8, g = 0.8, b = 0.8 } end
        end
    end
    -- the people in my group (they send their unfinished objectives)
    if addon.PartyProgress then
        for who, quests in pairs(addon.PartyProgress()) do
            for qid, texts in pairs(quests) do
                if Needs(qid) then
                    for _, l in ipairs(Matching(texts)) do
                        local e = Entry(qid)
                        e.lines[#e.lines + 1] = { text = who .. ": " .. l, r = 0.55, g = 0.8, b = 1 }
                    end
                end
            end
        end
    end

    -- while this is being sorted out: a grey line that says what was found (switch off with /lazy tooltips debug off)
    if addon.GetDB().tooltipDebug == true then
        local mine = MyQuests()
        local withData, needing = 0, 0
        for _, q in ipairs(mine) do
            if type(data.Field("quests", q.id, "objectives")) == "table" then withData = withData + 1 end
            if Needs(q.id) then needing = needing + 1 end
        end
        local lines = 0
        for _, qid in ipairs(order) do lines = lines + #perQuest[qid].lines end
        tooltip:AddLine(string.format("|cff808080FL: %s %d \"%s\" | %d quests in log, %d have data, %d need this, %d lines|r",
            kind, id, tostring(name), #mine, withData, needing, lines))
    end

    -- text already in the tooltip (another addon, such as Questie, may have added the same quest)
    local existing = {}
    local tname = tooltip.GetName and tooltip:GetName()
    for i = 1, (tooltip.NumLines and tooltip:NumLines() or 0) do
        local fs = tname and _G[tname .. "TextLeft" .. i]
        local txt = fs and fs.GetText and fs:GetText()
        if txt then existing[#existing + 1] = txt:lower() end
    end
    local haystack = table.concat(existing, "\n")

    local added = false
    for _, qid in ipairs(order) do
        local e = perQuest[qid]
        local title = tostring(e.title)
        if #e.lines > 0 and not haystack:find(title:lower(), 1, true) then
            if not added then tooltip:AddLine(" "); added = true end
            tooltip:AddLine("Quest: " .. title, 1, 0.82, 0)
            -- the quest name in the bold header font, in bright gold (changing the font can drop the colour, so it is set again)
            local fs = tname and _G[tname .. "TextLeft" .. tooltip:NumLines()]
            if fs and fs.SetFontObject and _G.GameTooltipHeaderText then
                fs:SetFontObject(_G.GameTooltipHeaderText)
                if fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
                tooltip.flqtBold = tooltip.flqtBold or {}
                tooltip.flqtBold[#tooltip.flqtBold + 1] = fs
            end
            for _, l in ipairs(e.lines) do tooltip:AddLine("  " .. l.text, l.r or 1, l.g or 1, l.b or 1) end
        end
    end
end
local function IdFromGuid(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if not id then return nil end
    if kind == "Creature" or kind == "Vehicle" then return id, "npc" end
    if kind == "GameObject" then return id, "object" end
end

-- objects (chests, plants ...) have no unit: find the one my quests need by the name on the first line
local objectNames
local function QuestObjectByName(name)
    if not name then return nil end
    objectNames = objectNames or {}
    for _, q in ipairs(MyQuests()) do
        local objectives = data.Field("quests", q.id, "objectives")
        local group = type(objectives) == "table" and objectives[2]
        for _, e in ipairs(group or {}) do
            local oid = e[1]
            if oid then
                local nm = objectNames[oid]
                if nm == nil then nm = data.Field("objects", oid, "name") or false; objectNames[oid] = nm end
                if nm and nm == name then return oid end
            end
        end
    end
end

local function Hook()
    -- forget what was added when the tooltip is cleared (it is rebuilt from scratch), and put the normal font back
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tt = _G[name]
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnTooltipCleared", function(self)
                self.flqtKey, self.flqtAdded, self.flqtPending = nil, nil, nil
                for _, fs in ipairs(self.flqtBold or {}) do if _G.GameTooltipText then fs:SetFontObject(_G.GameTooltipText) end end
                self.flqtBold = nil
            end)
        end
    end
    -- the newer tooltip hooks only fire on clients that build tooltips from data; Classic clients still use the older events
    local modern = type(GameTooltip.GetPrimaryTooltipData) == "function" and TooltipDataProcessor
        and type(TooltipDataProcessor.AddTooltipPostCall) == "function" and Enum and Enum.TooltipDataType
    if modern then
        local T = Enum.TooltipDataType
        if T.Unit then
            pcall(TooltipDataProcessor.AddTooltipPostCall, T.Unit, function(tt, d)
                pcall(function()
                    if tt ~= GameTooltip then return end
                    local id, kind = IdFromGuid(d and d.guid)
                    if id and kind == "npc" then Augment(tt, "npc", id) end
                end)
            end)
        end
        if T.Object then
            pcall(TooltipDataProcessor.AddTooltipPostCall, T.Object, function(tt, d)
                pcall(function()
                    if tt ~= GameTooltip then return end
                    local id = d and (d.id or IdFromGuid(d.guid))
                    if id then Augment(tt, "object", id) end
                end)
            end)
        end
        if T.Item then
            pcall(TooltipDataProcessor.AddTooltipPostCall, T.Item, function(tt, d)
                pcall(function()
                    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
                    if d and d.id then Augment(tt, "item", d.id) end
                end)
            end)
        end
        return
    end

    -- the older events. A tooltip can fire its event more than once for one hover, so each tooltip remembers what it did.
    local function Once(tt, key)
        if tt.flqtKey == key then return false end
        tt.flqtKey = key
        return true
    end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tt = _G[name]
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                pcall(function()
                    local _, link = self:GetItem()
                    local id = link and tonumber(link:match("item:(%d+)"))
                    if id and Once(self, "item" .. id) then Augment(self, "item", id) end
                end)
            end)
        end
    end
    if GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(self)
            pcall(function()
                local _, unit = self:GetUnit()
                local id, kind = IdFromGuid(unit and UnitGUID(unit))
                if id and kind == "npc" and Once(self, "npc" .. id) then Augment(self, "npc", id) end
            end)
        end)
        -- objects: no item, no unit
        pcall(GameTooltip.HookScript, GameTooltip, "OnShow", function(self)
            pcall(function()
                if self:GetItem() or self:GetUnit() then return end
                local first = _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
                local oid = QuestObjectByName(first)
                if oid and Once(self, "object" .. oid) then Augment(self, "object", oid) end
            end)
        end)
    end
end
Hook()
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "tooltips" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local db = addon.GetDB()
        if a == "debug off" then db.tooltipDebug = false elseif a == "debug on" then db.tooltipDebug = true end
        if a == "on" then db.questTooltips = true
        elseif a == "off" then db.questTooltips = false
        elseif a == "auto" then db.questTooltips = nil end
        Print("quest tooltips on creatures, objects and items: " .. (Enabled() and "ON" or "off") ..
            (db.questTooltips == nil and (QuestieAddonLoaded() and " (auto: off while Questie is running)" or " (auto: on, Questie is not running)") or ""))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Spare1.lua"] = true end end
