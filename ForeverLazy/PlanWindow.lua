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
    f.empty:SetText("No plan yet. /lazy plan builds one.")
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
local markers = {}

-- a numbered marker on the map for each stop, with its name when the mouse is over it
local function Marker(i)
    local m = markers[i]
    if m then return m end
    m = CreateFrame("Frame", nil, overlay)
    m:SetSize(20, 20)
    m:EnableMouse(true)
    m.bg = m:CreateTexture(nil, "ARTWORK")
    m.bg:SetAllPoints()
    m.bg:SetColorTexture(1, 0.82, 0, 0.95)
    m.num = m:CreateFontString(nil, "OVERLAY", "GameFontBlackSmall")
    m.num:SetPoint("CENTER")
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.title or "Stop", 1, 0.82, 0)
        if self.detail then GameTooltip:AddLine(self.detail, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    markers[i] = m
    return m
end

-- a stop on the route: a plan stop, or a stop made by a trip, boat, gathering, service or Lazy Mode
local function RouteStop(s)
    return s.label or s.go or s.gather or s.lazy or s.boat or s.service or s.craft or s.farm or s.hearth
end
-- the points of my route in order: the rest of a trip in progress, then the plan's stops.
-- { x, y, instance, kind, stop = { name, detail } }; kind says how I get there (walk, fly, boat, tram, hearth)
local KIND_COLOR = {
    walk = { 1, 0.82, 0 }, fly = { 0.3, 0.85, 1 }, boat = { 0.4, 0.6, 1 }, tram = { 0.8, 0.5, 1 }, hearth = { 1, 0.5, 0.9 },
}
local function RoutePoints(max)
    local db = DB()
    local pts = {}
    local path = addon.GoTripPath and addon.GoTripPath()
    if path then
        for _, p in ipairs(path) do
            pts[#pts + 1] = { x = p.x, y = p.y, instance = p.instance, kind = p.kind, stop = { name = p.name, detail = p.text } }
        end
    end
    -- the arrow is set to farm my saved nodes: the lines follow that walk instead of the plan
    if db.arrowSource == "nodes" and addon.NodeFarmPath then
        local fp = addon.NodeFarmPath(max or 15)
        if fp then
            for _, p in ipairs(fp) do
                if #pts >= (max or 15) then break end
                pts[#pts + 1] = { x = p.x, y = p.y, instance = p.instance, kind = "walk", stop = { name = p.name, detail = p.detail } }
            end
            return pts
        end
    end
    for _, s in ipairs(db.waypoints or {}) do
        if #pts >= (max or 15) then break end
        -- the trip's own waypoint is already covered by the trip path
        if RouteStop(s) and s.instance and s.x and not (path and s.go) then
            pts[#pts + 1] = { x = s.x, y = s.y, instance = s.instance, kind = "walk", stop = s }
        end
    end
    return pts
end
local function Canvas()
    local wm = _G.WorldMapFrame
    if not wm then return nil end
    if wm.GetCanvas then return wm:GetCanvas() end
    local sc = wm.ScrollContainer
    return sc and (sc.Child or (sc.GetCanvas and sc:GetCanvas()))
end

local function HideLines(from)
    for i = from or 1, #lines do lines[i]:Hide() end
    if not from then for _, m in ipairs(markers) do m:Hide() end end
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
    local pts, stopOf = {}, {}
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if px then pts[#pts + 1] = { px, py, pinst } end
    local number = 0
    local kinds = {}
    for _, rp in ipairs(RoutePoints(15)) do
        number = number + 1
        pts[#pts + 1] = { rp.x, rp.y, rp.instance }
        kinds[#pts] = rp.kind
        stopOf[#pts] = { stop = rp.stop, number = number }
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
            local c = KIND_COLOR[kinds[i + 1] or "walk"] or KIND_COLOR.walk
            line:SetColorTexture(c[1], c[2], c[3], i == 1 and 0.95 or 0.7)
            line:SetStartPoint("TOPLEFT", overlay, a[1], a[2])
            line:SetEndPoint("TOPLEFT", overlay, b[1], b[2])
            line:Show()
        end
    end
    HideLines(n + 1)

    -- numbered markers on the stops that are on this map
    local m = 0
    for i = 1, #pts do
        local info, pos = stopOf[i], screen[i]
        if info and pos then
            m = m + 1
            local mk = Marker(m)
            mk:SetParent(overlay)
            mk:SetFrameLevel(overlay:GetFrameLevel() + 3)
            mk:ClearAllPoints()
            mk:SetPoint("CENTER", overlay, "TOPLEFT", pos[1], pos[2])
            mk.num:SetText(tostring(info.number))
            mk.title = info.stop.name or info.stop.label
            mk.detail = info.stop.detail
            mk.bg:SetColorTexture(1, 0.82, 0, info.number == 1 and 1 or 0.8)
            mk:Show()
        end
    end
    for i = m + 1, #markers do markers[i]:Hide() end
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
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

--------------------------------------------------------------------------------
-- My route on the minimap: numbered stops joined in order, clipped to the minimap's edge.
-- Straight segments between stops (the game gives addons no pathfinding), but each stop is exactly placed.
--------------------------------------------------------------------------------
local OUTDOOR_RADIUS = { [0] = 116.7, [1] = 100, [2] = 83.3, [3] = 66.7, [4] = 50, [5] = 33.3 }
local mmLines, mmMarks = {}, {}
local MAX_STOPS = 8

local function ViewRadius(mm)
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, r = pcall(C_Minimap.GetViewRadius)
        if ok and type(r) == "number" and r > 0 then return r end
    end
    return OUTDOOR_RADIUS[mm:GetZoom() or 3] or 66.7
end

local function MinimapHolder(mm)
    if not mm.flRouteHolder then
        local h = CreateFrame("Frame", nil, mm)
        h:SetAllPoints(mm)
        h:SetFrameLevel(mm:GetFrameLevel() + 3)
        mm.flRouteHolder = h
    end
    return mm.flRouteHolder
end

local function GetMark(mm, i)
    local m = mmMarks[i]
    if m then return m end
    m = CreateFrame("Frame", nil, MinimapHolder(mm))
    m:SetSize(15, 15)
    m:SetFrameLevel(mm:GetFrameLevel() + 6)
    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    m.num = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.num:SetPoint("CENTER", 0, 0)
    m.dist = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.dist:SetPoint("TOP", m, "BOTTOM", 0, -1)
    mmMarks[i] = m
    return m
end

local function GetSeg(mm, i)
    local l = mmLines[i]
    if not l then
        l = MinimapHolder(mm):CreateLine(nil, "OVERLAY")
        l:SetThickness(2)
        mmLines[i] = l
    end
    return l
end

local function HideMinimapRoute()
    for _, l in ipairs(mmLines) do l:Hide() end
    for _, m in ipairs(mmMarks) do m:Hide() end
end

-- the part of the segment A-B that lies inside a circle of radius R around 0,0, or nil
local function ClipToCircle(ax, ay, bx, by, R)
    local dx, dy = bx - ax, by - ay
    local a = dx * dx + dy * dy
    if a < 1e-6 then return nil end
    local b = 2 * (ax * dx + ay * dy)
    local c = ax * ax + ay * ay - R * R
    local disc = b * b - 4 * a * c
    if disc < 0 then return nil end
    local s = math.sqrt(disc)
    local t1, t2 = (-b - s) / (2 * a), (-b + s) / (2 * a)
    local lo, hi = math.max(t1, 0), math.min(t2, 1)
    if lo >= hi then return nil end
    return ax + dx * lo, ay + dy * lo, ax + dx * hi, ay + dy * hi
end

local function UpdateMinimapRoute()
    local db = DB()
    local mm = _G.Minimap
    if not (db and mm) or db.minimapLine == false or db.mode == "off" then return HideMinimapRoute() end
    if api.ShouldHide and api.ShouldHide() then return HideMinimapRoute() end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return HideMinimapRoute() end
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing()
    if rotate and not facing then return HideMinimapRoute() end

    local half = mm:GetWidth() / 2
    local R = half - 3
    local scale = half / ViewRadius(mm)

    -- the stops that are in this zone, as offsets from the middle of the minimap in pixels
    local pts, dists, kinds = { { 0, 0 } }, {}, {}
    for _, w in ipairs(RoutePoints(MAX_STOPS)) do
        if #pts > MAX_STOPS then break end
        if w.x and w.y and w.instance == pinst then
            local angle, dist = hbd:GetWorldVector(pinst, px, py, w.x, w.y)
            if angle then
                local theta = rotate and (angle - facing) or angle
                local r = (dist or 0) * scale
                pts[#pts + 1] = { -math.sin(theta) * r, math.cos(theta) * r }
                dists[#pts] = dist
                kinds[#pts] = w.kind
            end
        end
    end
    if #pts == 1 then return HideMinimapRoute() end

    local segs = 0
    for i = 1, #pts - 1 do
        local x1, y1, x2, y2 = ClipToCircle(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], R)
        if x1 then
            segs = segs + 1
            local l = GetSeg(mm, segs)
            local c = KIND_COLOR[kinds[i + 1] or "walk"] or KIND_COLOR.walk
            l:SetColorTexture(c[1], c[2], c[3], i == 1 and 0.95 or 0.65)
            l:SetStartPoint("CENTER", mm, x1, y1)
            l:SetEndPoint("CENTER", mm, x2, y2)
            l:Show()
        end
    end
    for i = segs + 1, #mmLines do mmLines[i]:Hide() end

    local marks = 0
    for i = 2, #pts do
        local x, y = pts[i][1], pts[i][2]
        if x * x + y * y <= R * R then
            marks = marks + 1
            local m = GetMark(mm, marks)
            m:ClearAllPoints()
            m:SetPoint("CENTER", mm, "CENTER", x, y)
            m.bg:SetVertexColor(i == 2 and 1 or 0.15, i == 2 and 0.82 or 0.15, i == 2 and 0.1 or 0.2, 0.95)
            m.num:SetText(i - 1)
            m.num:SetTextColor(i == 2 and 0 or 1, i == 2 and 0 or 0.82, i == 2 and 0 or 0.1)
            m.dist:SetText(i == 2 and dists[i] and string.format("%d yd", dists[i]) or "")
            m:Show()
        end
    end
    for i = marks + 1, #mmMarks do mmMarks[i]:Hide() end
end

local mmTick = CreateFrame("Frame")
local mmAcc = 0
mmTick:SetScript("OnUpdate", function(_, dt)
    mmAcc = mmAcc + dt
    if mmAcc < 0.05 then return end
    mmAcc = 0
    pcall(UpdateMinimapRoute)
end)
--------------------------------------------------------------------------------
-- XP hot spots: a heat layer on the zone map showing where the quests worth doing for my level are
--------------------------------------------------------------------------------
local GX, GY = 40, 27
local heatFrame, heatCells, heatLabel = nil, {}, nil

local function HeatColor(t)
    -- low: cool blue-green, middle: yellow, high: red
    if t < 0.5 then
        local k = t / 0.5
        return 0.2 + 0.8 * k, 0.6 + 0.25 * k, 1 - 0.9 * k
    end
    local k = (t - 0.5) / 0.5
    return 1, 0.85 - 0.65 * k, 0.1
end

local function HideHeat()
    if heatFrame then heatFrame:Hide() end
end

function addon.DrawXPHeat()
    local db = DB()
    local wm = _G.WorldMapFrame
    if not db or not db.xpHeat or db.planPaused or not addon.ModuleOn("plan") or not (wm and wm:IsShown()) then return HideHeat() end
    local canvas = Canvas()
    local mapId = wm.GetMapID and wm:GetMapID()
    if not (canvas and mapId and canvas.GetWidth) then return HideHeat() end
    if not heatFrame then
        heatFrame = CreateFrame("Frame", nil, canvas)
        heatFrame:SetAllPoints(canvas)
        heatLabel = CreateFrame("Frame", nil, heatFrame)
        heatLabel:SetSize(10, 10)
        heatLabel.bg = heatLabel:CreateTexture(nil, "BACKGROUND")
        heatLabel.bg:SetAllPoints(); heatLabel.bg:SetColorTexture(0, 0, 0, 0.7)
        heatLabel.text = heatLabel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heatLabel.text:SetPoint("CENTER")
    end
    heatFrame:SetParent(canvas)
    heatFrame:SetFrameLevel(canvas:GetFrameLevel() + 1)
    heatFrame:Show()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local cw, ch = w / GX, h / GY
    local list = addon.XPHotSpots and addon.XPHotSpots(mapId)
    local function label(text)
        heatLabel.text:SetText(text)
        heatLabel:SetSize(heatLabel.text:GetStringWidth() + 24, 26)
        heatLabel:ClearAllPoints()
        heatLabel:SetPoint("TOP", heatFrame, "TOP", 0, -8)
        heatLabel:Show()
    end
    for _, c in ipairs(heatCells) do c:Hide() end
    if list == nil then return label("XP hot spots: waiting for Questie") end
    if #list == 0 then return label("XP hot spots: nothing worth doing here for your level") end

    -- spread each quest's XP over the cells around it
    local heat, top, topCell = {}, 0, nil
    for _, p in ipairs(list) do
        local cx, cy = p.zx * GX, p.zy * GY
        for gx = math.max(0, math.floor(cx - 3)), math.min(GX - 1, math.ceil(cx + 3)) do
            for gy = math.max(0, math.floor(cy - 3)), math.min(GY - 1, math.ceil(cy + 3)) do
                local d2 = (gx + 0.5 - cx) ^ 2 + (gy + 0.5 - cy) ^ 2
                local v = p.xp * math.exp(-d2 / 2.4)
                local i = gx + gy * GX + 1
                heat[i] = (heat[i] or 0) + v
                if heat[i] > top then top, topCell = heat[i], { gx, gy } end
            end
        end
    end
    local n = 0
    for i, v in pairs(heat) do
        local t = v / top
        if t > 0.15 then
            n = n + 1
            local c = heatCells[n]
            if not c then
                c = heatFrame:CreateTexture(nil, "ARTWORK")
                heatCells[n] = c
            end
            local gx, gy = (i - 1) % GX, math.floor((i - 1) / GX)
            local r, g, b = HeatColor(t)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", heatFrame, "TOPLEFT", gx * cw, -gy * ch)
            c:SetSize(cw, ch)
            c:SetColorTexture(r, g, b, 0.04 + 0.16 * t)
            c:Show()
        end
    end
    -- the hottest spot in words
    local sum, count, names = 0, 0, {}
    for _, p in ipairs(list) do
        if math.abs(p.zx * GX - (topCell[1] + 0.5)) <= 4 and math.abs(p.zy * GY - (topCell[2] + 0.5)) <= 4 then
            sum = sum + p.xp; count = count + 1
            if #names < 3 then names[#names + 1] = p.name end
        end
    end
    label(string.format("Hottest spot: about %d XP in %d quest%s  (%s)", sum, count, count == 1 and "" or "s", table.concat(names, ", ")))
end

local heatEv = CreateFrame("Frame")
pcall(heatEv.RegisterEvent, heatEv, "PLAYER_LOGIN")
heatEv:SetScript("OnEvent", function()
    if not C_Timer then return end
    C_Timer.After(3.5, function()
        local wm = _G.WorldMapFrame
        if not wm then return end
        wm:HookScript("OnShow", function() addon.DrawXPHeat() end)
        if hooksecurefunc and wm.OnMapChanged then pcall(hooksecurefunc, wm, "OnMapChanged", function() addon.DrawXPHeat() end) end
        local t = 0
        wm:HookScript("OnUpdate", function(_, dt)
            t = t + dt
            if t > 2 then t = 0; addon.DrawXPHeat() end
        end)
    end)
end)
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    if word == "xpmap" or word == "heat" or word == "hotspots" then
        local db = DB()
        local a = (rest or ""):lower()
        if a == "on" then db.xpHeat = true elseif a == "off" then db.xpHeat = false else db.xpHeat = not db.xpHeat end
        Print("XP hot spots on the world map " .. (db.xpHeat and "on (open the map)" or "off"))
        if addon.DrawXPHeat then addon.DrawXPHeat() end
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    end
    if word == "window" or word == "list" or word == "stops" then
        addon:TogglePlanWindow()
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["PlanWindow.lua"] = true end end
