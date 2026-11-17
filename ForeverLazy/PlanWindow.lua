-- The plan window and the route lines on the world map.
--   /lazy window        open or close the plan window (also: /lazy list)
--   click a stop to do it next, right-click to skip that quest (or drop the stop)
-- The map draws a gold line from you through every stop of your plan.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end
local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local ROWS, ROWH = 12, 20
local win

local function Plain(label)
    local t = label or "?"
    t = t:gsub("^Turn in: ", ""):gsub("^Pick up: ", ""):gsub("^Class quest: ", ""):gsub("^Sleeping bag: ", "")
    return t
end

local function Kind(label)
    label = label or ""
    if label:find("^Turn in:") then return "|cffffd100?|r " end
    if label:find("^Pick up:") or label:find("^Class quest:") then return "|cffffd100!|r " end
    return ""
end

local function FormatDist(d)
    if not d then return "" end
    if d >= 1000 then return string.format("%.1fk", d / 1000) end
    return string.format("%d", d)
end

local function Update()
    if not (win and win:IsShown()) then return end
    local db = DB()
    local wps = db.waypoints or {}
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local shown = 0
    for i = 1, ROWS do
        local row = win.rows[i]
        local w = wps[i]
        if w then
            shown = shown + 1
            local d = (px and w.instance == pinst) and Dist({ x = px, y = py }, w) or nil
            row.fs:SetText(string.format("%s%d. %s", Kind(w.label), i, Plain(w.label or w.name)))
            row.dist:SetText(d and FormatDist(d) or "|cff888888far|r")
            row.index = i
            row:Show()
        else
            row.index = nil
            row:Hide()
        end
    end
    local more = #wps > ROWS and string.format("  (+%d more)", #wps - ROWS) or ""
    win.title:SetText(string.format("Plan  |cffaaaaaa%d stop%s%s|r", #wps, #wps == 1 and "" or "s", more))
    win.empty:SetShown(#wps == 0)
    win:SetHeight(46 + math.max(shown, 1) * ROWH)
end

local function Click(i, button)
    local db = DB()
    local wps = db.waypoints
    local w = wps[i]
    if not w then return end
    local q = w.quests and w.quests[1]
    if button == "RightButton" then
        if q and q.id and addon.SkipQuest then
            addon.SkipQuest(q.id, q.label)
        else
            addon:RemoveWaypoint(i)
        end
    else
        if i == 1 then return end
        if q and q.id and addon.FocusQuest then
            addon:FocusQuest(q.id, q.label)
        else
            table.remove(wps, i)
            table.insert(wps, 1, w)
            for k, s in ipairs(wps) do if s.label then s.name = k .. ". " .. s.label end end
            addon:RefreshPins()
        end
    end
    Update()
end

local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_PlanWindow", UIParent)
    f:SetSize(300, 70)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        DB().pos.planWindow = { point = point, x = x, y = y }
    end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.88)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPRIGHT", -28, -10)
    f.hint:SetText("|cff888888click: do next  right-click: skip|r")
    local close = CreateFrame("Button", nil, f)
    close:SetSize(18, 18); close:SetPoint("TOPRIGHT", -4, -4)
    close.fs = close:CreateFontString(nil, "OVERLAY", "GameFontNormal"); close.fs:SetPoint("CENTER"); close.fs:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("TOPLEFT", 12, -28)
    f.empty:SetText("No plan yet. /lrxp plan builds one.")
    f.rows = {}
    for i = 1, ROWS do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(284, ROWH)
        b:SetPoint("TOPLEFT", 8, -26 - (i - 1) * ROWH)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.fs:SetPoint("LEFT", 2, 0); b.fs:SetWidth(232); b.fs:SetJustifyH("LEFT")
        b.dist = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.dist:SetPoint("RIGHT", -2, 0); b.dist:SetJustifyH("RIGHT")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.12)
        b:SetScript("OnClick", function(self, button) if self.index then Click(self.index, button) end end)
        f.rows[i] = b
    end
    local p = DB().pos.planWindow or { point = "TOPRIGHT", x = -30, y = -260 }
    f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    local t = 0
    f:SetScript("OnUpdate", function(_, dt) t = t + dt; if t > 0.5 then t = 0; Update() end end)
    f:Hide()
    return f
end

function addon:TogglePlanWindow()
    win = win or Build()
    win:SetShown(not win:IsShown())
    Update()
end

-- keep it in step with the plan
local origRefresh = addon.RefreshPins
function addon:RefreshPins(...)
    origRefresh(self, ...)
    if win and win:IsShown() then Update() end
    if addon.DrawRouteLines then addon.DrawRouteLines() end
end

--------------------------------------------------------------------------------
-- Route lines on the world map
--------------------------------------------------------------------------------
local overlay
local lines = {}

local function Canvas()
    local wm = _G.WorldMapFrame
    if not wm then return nil end
    if wm.GetCanvas then return wm:GetCanvas() end
    local sc = wm.ScrollContainer
    return sc and (sc.Child or (sc.GetCanvas and sc:GetCanvas()))
end

local function HideLines(from)
    for i = from or 1, #lines do lines[i]:Hide() end
end

function addon.DrawRouteLines()
    local db = DB()
    local wm = _G.WorldMapFrame
    if not db or db.mapRoute == false or not addon.ModuleOn("plan") or not (wm and wm:IsShown()) then HideLines(); return end
    local canvas = Canvas()
    local mapId = wm.GetMapID and wm:GetMapID()
    if not (canvas and mapId and canvas.GetWidth) then HideLines(); return end
    if not overlay then
        overlay = CreateFrame("Frame", nil, canvas)
        overlay:SetAllPoints(canvas)
    end
    overlay:SetParent(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 6)
    overlay:Show()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local pts = {}
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if px then pts[#pts + 1] = { px, py, pinst } end
    for i, s in ipairs(db.waypoints or {}) do
        if i > 15 then break end
        if s.label and s.instance and s.x then pts[#pts + 1] = { s.x, s.y, s.instance } end
    end
    local screen = {}
    for i, p in ipairs(pts) do
        local zx, zy = hbd:GetZoneCoordinatesFromWorldInstance(p[1], p[2], p[3], mapId, true)
        if zx and zx > -0.3 and zx < 1.3 and zy > -0.3 and zy < 1.3 then
            screen[i] = { zx * w, -zy * h }
        end
    end
    local n = 0
    for i = 1, #pts - 1 do
        local a, b = screen[i], screen[i + 1]
        if a and b then
            n = n + 1
            local line = lines[n]
            if not line then
                line = overlay:CreateLine(nil, "OVERLAY")
                line:SetThickness(3)
                lines[n] = line
            end
            line:SetColorTexture(1, 0.82, 0, i == 1 and 0.95 or 0.65)
            line:SetStartPoint("TOPLEFT", overlay, a[1], a[2])
            line:SetEndPoint("TOPLEFT", overlay, b[1], b[2])
            line:Show()
        end
    end
    HideLines(n + 1)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if not C_Timer then return end
    C_Timer.After(3, function()
        local wm = _G.WorldMapFrame
        if not wm then return end
        if wm.HookScript then wm:HookScript("OnShow", function() addon.DrawRouteLines() end) end
        if hooksecurefunc and wm.OnMapChanged then pcall(hooksecurefunc, wm, "OnMapChanged", function() addon.DrawRouteLines() end) end
        -- the player moves, so redraw about once a second while the map is open
        local t = 0
        wm:HookScript("OnUpdate", function(_, dt)
            t = t + dt
            if t > 1 then t = 0; addon.DrawRouteLines() end
        end)
    end)
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    if word == "window" or word == "list" or word == "stops" then
        addon:TogglePlanWindow()
        return true
    end
    if prev then return prev(self, cmd, rest) end
end
