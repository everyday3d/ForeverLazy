-- Quest search: type part of a quest's name, see the quests that match, hover for the details, click one to point the arrow
-- at it (where to pick it up, where to hand it in, or the next thing to do for it).
--   /lazy find <text>     open the search (also in the options)     shift-click a row: put the quest link in chat
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local data = ns.data
local Print = addon.Print

local function DB() return addon.GetDB() end
local ROWS = 12

local win

--------------------------------------------------------------------------------
-- Pointing the arrow
--------------------------------------------------------------------------------
local function PointAt(id, name)
    local db = DB()
    local by
    if addon.QuestInLog(id) then
        local ok, done = pcall(C_QuestLog.IsComplete, id)
        if not (ok and done) then
            if addon.FocusQuest then addon:FocusQuest(id, name) end
            return
        end
        by = data.Field("quests", id, "finishedBy")
    else
        by = data.Field("quests", id, "startedBy")
    end
    if type(by) ~= "table" then Print("no place known for " .. tostring(name)) return end
    local list = {}
    if api.AddNpcs then pcall(api.AddNpcs, list, by[1]) end
    if api.AddObjects then pcall(api.AddObjects, list, by[2]) end
    if #list == 0 then Print("no place known for " .. tostring(name)) return end
    local hbd = api.hbd
    local px, py, pinst = hbd and hbd:GetPlayerWorldPosition()
    local best, bd
    for _, s in ipairs(list) do
        local d = (px and s.instance == pinst) and api.D2(s.x, s.y, px, py) or 1e18
        if not bd or d < bd then best, bd = s, d end
    end
    for i = #db.waypoints, 1, -1 do
        if db.waypoints[i].questMapPin then table.remove(db.waypoints, i) end
    end
    addon:AddWaypointZone(best.uiMapId, best.zx, best.zy, tostring(name))
    if db.waypoints[1] then db.waypoints[1].questMapPin = true; db.waypoints[1].area = best.area end
    if addon.RefreshOptions then addon.RefreshOptions() end
end

addon.QuestPointAt = PointAt

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local results, offset = {}, 0

local function Status(e)
    if addon.QuestCompleted(e.id) then return "|cff888888done|r" end
    if addon.QuestInLog(e.id) then return "|cffffd100in log|r" end
    if not e.mine then return "|cff666666other race/class|r" end
    return "|cff55ff55open|r"
end

local function Render()
    if not win then return end
    for i = 1, ROWS do
        local row = win.rows[i]
        local e = results[offset + i]
        if e then
            local zone = (e.zone and e.zone > 0) and (addon.AreaLabel(e.zone) or (C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(e.zone))) or nil
            row.fs:SetText(string.format("|cffcccccc[%d]|r %s  |cff888888%s|r", e.level or 0, e.name, zone and (" - " .. zone) or ""))
            row.st:SetText(Status(e))
            row.entry = e
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    local _, done, frac = addon.QuestIndex()
    local text
    if #results == 0 then text = "no quests match" else text = string.format("%d match%s", #results, #results == 1 and "" or "es") end
    if #results > ROWS then text = text .. string.format("  (showing %d-%d, scroll for more)", offset + 1, math.min(#results, offset + ROWS)) end
    if not done then text = text .. string.format("  |cff888888(still reading the quest list: %d%%)|r", math.floor(frac * 100)) end
    win.count:SetText(text)
end

local function Search()
    if not win then return end
    local q = (win.edit:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local index = addon.QuestIndex()
    results, offset = {}, 0
    if #q >= 2 then
        local lvl = tonumber(q)
        for _, e in ipairs(index) do
            if e.lname:find(q, 1, true) or (lvl and e.level == lvl and false) then results[#results + 1] = e end
            if #results >= 400 then break end
        end
        -- quests I can take first, then by level
        table.sort(results, function(a, b)
            if a.mine ~= b.mine then return a.mine end
            if a.level ~= b.level then return a.level < b.level end
            return a.name < b.name
        end)
    end
    Render()
end

local function ChatLink(e)
    return string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", e.id, e.level or 0, e.name)
end

local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_QuestSearch", UIParent)
    f:SetSize(520, 52 + ROWS * 22 + 44)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText("Find a quest")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local edit = CreateFrame("EditBox", "ForeverLazy_QuestSearchBox", f, "InputBoxTemplate")
    edit:SetSize(300, 22)
    edit:SetPoint("TOPLEFT", 22, -38)
    edit:SetAutoFocus(false)
    edit:SetScript("OnTextChanged", function() Search() end)
    edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    f.edit = edit
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("LEFT", edit, "RIGHT", 10, 0)
    f.hint:SetText("click: point the arrow   shift-click: link")
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.count:SetPoint("BOTTOMLEFT", 16, 14)
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(490, 20)
        r:SetPoint("TOPLEFT", 14, -66 - (i - 1) * 22)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        r.fs = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        r.fs:SetPoint("LEFT", 4, 0); r.fs:SetWidth(390); r.fs:SetJustifyH("LEFT"); r.fs:SetWordWrap(false)
        r.st = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.st:SetPoint("RIGHT", -4, 0); r.st:SetJustifyH("RIGHT")
        r:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(e.name, 1, 0.82, 0)
            for _, l in ipairs(addon.QuestInfoLines(e.id)) do GameTooltip:AddLine(l, 1, 1, 1) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self)
            local e = self.entry
            if not e then return end
            if IsShiftKeyDown() then
                if ChatEdit_InsertLink then ChatEdit_InsertLink(ChatLink(e)) end
            else
                PointAt(e.id, e.name)
            end
        end)
        r:Hide()
        f.rows[i] = r
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #results - ROWS)
        offset = math.max(0, math.min(maxOff, offset - delta * 3))
        Render()
    end)
    -- the list is still being read when the window opens: keep the results fresh until it is done
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.7 then return end
        acc = 0
        local _, done = addon.QuestIndex()
        if not done and (f.edit:GetText() or "") ~= "" then
            local keep = offset
            Search(); offset = keep; Render()
        elseif not f.settled then
            f.settled = done
            if done then Search() end
        end
    end)
    table.insert(UISpecialFrames, "ForeverLazy_QuestSearch")
    f:Hide()
    return f
end

function addon.QuestSearchOpen(text)
    win = win or Build()
    win:Show()
    addon.QuestIndex()
    if text and text ~= "" then win.edit:SetText(text) else Search() end
    win.edit:SetFocus()
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "find" or c == "search" or c == "qfind" then
        addon.QuestSearchOpen((rest or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestSearch.lua"] = true end end
