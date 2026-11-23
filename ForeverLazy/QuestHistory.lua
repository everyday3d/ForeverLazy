-- Quest history: the quests I have finished, zone by zone, with how many are left (for my race and class).
--   /lazy history     (also a button in the options)    hover a zone to see some of the quests still to do there
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local data = ns.data
local Print = addon.Print

local ROWS = 16
local win, zones, offset = nil, {}, 0

local function CompletedSet()
    local set = {}
    local list
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        local ok, l = pcall(C_QuestLog.GetAllCompletedQuestIDs)
        if ok and type(l) == "table" then list = l end
    end
    if list then
        for _, id in ipairs(list) do set[id] = true end
    elseif GetQuestsCompleted then
        local ok, t = pcall(GetQuestsCompleted)
        if ok and type(t) == "table" then for id, v in pairs(t) do if v then set[id] = true end end end
    end
    return set
end

local function ZoneLabel(zone)
    if zone and zone > 0 then
        return addon.AreaLabel(zone) or (C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(zone)) or ("zone " .. zone)
    end
    return "Other (class, profession, events)"
end

local function Compute()
    local index, done = addon.QuestIndex()
    local doneSet = CompletedSet()
    local byZone, all = {}, 0
    for _, e in ipairs(index) do
        if e.mine then
            local key = (e.zone and e.zone > 0) and e.zone or 0
            local z = byZone[key]
            if not z then z = { key = key, total = 0, done = 0, left = {} }; byZone[key] = z end
            z.total = z.total + 1
            if doneSet[e.id] then z.done = z.done + 1; all = all + 1
            else z.left[#z.left + 1] = e end
        end
    end
    local list = {}
    for _, z in pairs(byZone) do
        if z.done > 0 then z.name = ZoneLabel(z.key); list[#list + 1] = z end
    end
    table.sort(list, function(a, b)
        if a.done ~= b.done then return a.done > b.done end
        return a.name < b.name
    end)
    zones = list
    local n = 0
    for _ in pairs(doneSet) do n = n + 1 end
    return n, done
end

local function Render()
    if not win then return end
    for i = 1, ROWS do
        local row = win.rows[i]
        local z = zones[offset + i]
        if z then
            local pct = z.total > 0 and (z.done / z.total) or 0
            row.fs:SetText(string.format("%s", z.name))
            row.num:SetText(string.format("%d / %d", z.done, z.total))
            row.bar:SetWidth(math.max(1, 120 * math.min(1, pct)))
            row.bar:SetColorTexture(pct >= 0.99 and 0.3 or 0.2, pct >= 0.99 and 0.9 or 0.6, 0.3, 0.9)
            row.zone = z
            row:Show()
        else
            row.zone = nil
            row:Hide()
        end
    end
end

local function Refresh()
    if not win then return end
    local total, done = Compute()
    win.sub:SetText(string.format("%d quests finished%s", total, done and "" or "  |cff888888(still reading the quest list, reopen in a moment)|r"))
    offset = 0
    Render()
end

local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_QuestHistory", UIParent)
    f:SetSize(480, 70 + ROWS * 22 + 16)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText(L("Quest history"))
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(450, 20)
        r:SetPoint("TOPLEFT", 14, -56 - (i - 1) * 22)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        r.bar = r:CreateTexture(nil, "BACKGROUND")
        r.bar:SetPoint("LEFT", 300, 0); r.bar:SetHeight(10); r.bar:SetWidth(1)
        r.fs = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        r.fs:SetPoint("LEFT", 4, 0); r.fs:SetWidth(240); r.fs:SetJustifyH("LEFT"); r.fs:SetWordWrap(false)
        r.num = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.num:SetPoint("LEFT", 246, 0); r.num:SetWidth(50); r.num:SetJustifyH("RIGHT")
        r:SetScript("OnEnter", function(self)
            local z = self.zone
            if not z then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(z.name, 1, 0.82, 0)
            GameTooltip:AddLine(string.format("%d of %d done (%d%%)", z.done, z.total, z.total > 0 and math.floor(z.done / z.total * 100 + 0.5) or 0), 1, 1, 1)
            if #z.left > 0 then
                local lvl = UnitLevel("player") or 1
                local list = {}
                for _, e in ipairs(z.left) do list[#list + 1] = e end
                -- the ones near my level first
                table.sort(list, function(a, b) return math.abs((a.level or 0) - lvl) < math.abs((b.level or 0) - lvl) end)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L("Still to do (nearest my level):"), 0.7, 0.85, 1)
                for i2 = 1, math.min(8, #list) do GameTooltip:AddLine(string.format("[%d] %s", list[i2].level or 0, list[i2].name), 0.9, 0.9, 0.9) end
                if #list > 8 then GameTooltip:AddLine(string.format("... and %d more", #list - 8), 0.5, 0.5, 0.5) end
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        f.rows[i] = r
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #zones - ROWS), offset - delta * 3))
        Render()
    end)
    table.insert(UISpecialFrames, "ForeverLazy_QuestHistory")
    f:Hide()
    return f
end

function addon.QuestHistoryOpen()
    win = win or Build()
    win:Show()
    Refresh()
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "history" then
        addon.QuestHistoryOpen()
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestHistory.lua"] = true end end
