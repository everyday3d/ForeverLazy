-- The quest map: where my quests' mobs, items and objects are, drawn on the world map and the minimap, like Questie does.
--   coloured area    where to kill or collect (one colour for each quest)                green dot        click this on the ground
--   (skull and purple diamond icons on those spots are an option, off unless the areas are off)
--   yellow !   a quest I can pick up here (this zone)                     yellow ?   a finished quest to hand in
-- Hover a pin for the quest and what is left. Finished objectives are not drawn. Own pins, separate from the route and arrow pins.
--   /lazy questmap on|off   everything      /lazy questmap objectives|givers on|off
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local data = ns.data
local DS = ns.dataset
local Print = addon.Print

local hbdp = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local hbd = api and api.hbd
local OWNER = { name = "ForeverLazyQuestMap" }          -- its own owner, so the route pins refreshing never wipe these

local function DB() return addon.GetDB() end
local function Wants(kind)
    local db = DB()
    if not db or db.questMap == false then return false end
    if kind == "objectives" then return db.questMapObjectives ~= false end
    if kind == "givers" then return db.questMapGivers ~= false end
    if kind == "areas" then return db.questMapAreas ~= false end
    return true
end

local TEX = {
    kill = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    collect = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    give = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
}
local MAX_WORLD, MAX_MINI = 600, 70
-- the most spots drawn for one objective in one zone. Things on the ground get far more: each one is a place to click
local PER_ZONE, PER_ZONE_OBJECT = 45, 150
-- pin sizes (times the "Pin size" slider): small, so they do not cover the map
local SIZE_WORLD = { give = 14, turnin = 14, object = 7, other = 10 }
local SIZE_MINI = { object = 6, other = 9 }
local AREA_ALPHA, PIN_ALPHA = 0.45, 0.7                  -- how strong the coloured areas and the mob icons are
local DOT = "Interface\\CharacterFrame\\TempPortraitAlphaMask"       -- a white disc
local CELL = 70                                          -- spots closer than 1/70 of a zone map share one pin
local CELL_OBJECT = 160                                  -- ground objects are kept apart more finely

--------------------------------------------------------------------------------
-- Click a pin or a coloured area: the arrow points there
--------------------------------------------------------------------------------
local function PointArrowAt(f)
    local c = f.cell
    if not (c and c.uiMapId and addon.AddWaypointZone) then return end
    local db = DB()
    -- a spot set by an earlier click goes away, so clicks do not pile up
    for i = #db.waypoints, 1, -1 do
        if db.waypoints[i].questMapPin then table.remove(db.waypoints, i) end
    end
    local title = c.info and c.info[1] or "Quest spot"
    -- the waypoint made here carries its area so the arrow can name it
    local area = c.area
    addon:AddWaypointZone(c.uiMapId, c.zx, c.zy, title)
    if db.waypoints[1] then db.waypoints[1].questMapPin = true; db.waypoints[1].area = area end
    if addon.RefreshOptions then addon.RefreshOptions() end
end

local function OnEnterPin(self)
    if not self.info then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for n, line in ipairs(self.info) do
        if n == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    local area = self.cell and self.cell.area
    if area and not (DB() and DB().showAreas == false) then GameTooltip:AddLine(area, 0.7, 0.85, 1) end
    GameTooltip:AddLine(L("Click: point the arrow here"), 0.5, 1, 0.5)
    GameTooltip:AddLine(L("Forever Lazy"), 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Pins (frames are reused)
--------------------------------------------------------------------------------
local worldFrames, miniFrames = {}, {}
local function Frame(pool, i, size)
    local f = pool[i]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(size, size)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f:EnableMouse(true)
    f:SetScript("OnEnter", OnEnterPin)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnMouseUp", function(self, button) if button == "LeftButton" then pcall(PointArrowAt, self) end end)
    f:Hide()
    pool[i] = f
    return f
end

-- how a pin looks: a ground object is a small green dot with a dark edge, everything else is an icon. Frames are reused, so
-- everything one look sets is set again by the other
local function Style(f, kind)
    f.tex:ClearAllPoints()
    if kind == "object" then
        if not f.ring then
            f.ring = f:CreateTexture(nil, "ARTWORK")
            f.ring:SetAllPoints()
            f.ring:SetTexture(DOT)
            f.ring:SetVertexColor(0, 0, 0, 0.9)
        end
        f.ring:Show()
        f.tex:SetPoint("TOPLEFT", 1.2, -1.2); f.tex:SetPoint("BOTTOMRIGHT", -1.2, 1.2)
        f.tex:SetTexture(DOT)
        f.tex:SetVertexColor(0.3, 1, 0.45, 1)
    else
        if f.ring then f.ring:Hide() end
        f.tex:SetAllPoints()
        f.tex:SetTexture(TEX[kind])
        f.tex:SetVertexColor(1, 1, 1, 1)
    end
    -- the mob and drop icons are held back a little, so the coloured areas read first
    f.tex:SetAlpha((kind == "kill" or kind == "collect") and PIN_ALPHA or 1)
end

-- translucent coloured areas behind the pins (world map only), one colour for each quest
local areaFrames = {}
local function AreaFrame(i)
    local f = areaFrames[i]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")      -- a white disc
    f:EnableMouse(true)
    f:SetScript("OnEnter", OnEnterPin)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnMouseUp", function(self, button) if button == "LeftButton" then pcall(PointArrowAt, self) end end)
    f:Hide()
    areaFrames[i] = f
    return f
end

local function Colour(title)
    local h = 5381
    for i = 1, #title do h = (h * 33 + title:byte(i)) % 360 end
    local hue = h / 60
    local c, x = 1, 1 - math.abs(hue % 2 - 1)
    local r, g, b
    if hue < 1 then r, g, b = c, x, 0 elseif hue < 2 then r, g, b = x, c, 0 elseif hue < 3 then r, g, b = 0, c, x
    elseif hue < 4 then r, g, b = 0, x, c elseif hue < 5 then r, g, b = x, 0, c else r, g, b = c, 0, x end
    return 0.35 + r * 0.65, 0.35 + g * 0.65, 0.35 + b * 0.65
end

-- With OpenMap's stitched map the canvas shows more than one zone, so a zone is only a part of the canvas: how big a part
-- (1 on the game's own zone map)
local function ZoneFraction(uiMapId)
    local om = _G.OpenMapAPI
    if not (uiMapId and om and om.IsStitched and om.IsStitched() and om.WorldFromMap and om.MapFromWorld
            and WorldMapFrame and WorldMapFrame.GetMapID) then return 1 end
    local ok, f = pcall(function()
        local host = WorldMapFrame:GetMapID()
        if not host or host == uiMapId then return 1 end
        local u1, v1 = om.WorldFromMap(uiMapId, 0.45, 0.5)
        local u2, v2 = om.WorldFromMap(uiMapId, 0.55, 0.5)
        if not (u1 and u2) then return 1 end
        local x1 = om.MapFromWorld(host, u1, v1)
        local x2 = om.MapFromWorld(host, u2, v2)
        if not (x1 and x2) then return 1 end
        return math.max(0.02, math.min(3, math.abs(x2 - x1) / 0.1))
    end)
    return ok and tonumber(f) or 1
end

local function AreaSize(uiMapId)
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    local w = canvas and canvas.GetWidth and canvas:GetWidth() or 1000
    if not w or w <= 0 then w = 1000 end
    return w * 2.4 / CELL * ZoneFraction(uiMapId)
end

local function Clear()
    if not hbdp then return end
    pcall(hbdp.RemoveAllWorldMapIcons, hbdp, OWNER)
    pcall(hbdp.RemoveAllMinimapIcons, hbdp, OWNER)
    for _, f in ipairs(worldFrames) do f:Hide() end
    for _, f in ipairs(areaFrames) do f:Hide() end
    for _, f in ipairs(miniFrames) do f:Hide() end
end

--------------------------------------------------------------------------------
-- What each objective of a quest points at, in the order Questie lists them (creatures, objects, items, kill credit)
--------------------------------------------------------------------------------
local function Refs(qid)
    local out = {}
    local o = data.Field("quests", qid, "objectives")
    if type(o) ~= "table" then return out end
    for _, e in ipairs(o[1] or {}) do if e[1] then out[#out + 1] = { kind = "kill", store = "npcs", ids = { e[1] } } end end
    for _, e in ipairs(o[2] or {}) do if e[1] then out[#out + 1] = { kind = "object", store = "objects", ids = { e[1] } } end end
    for _, e in ipairs(o[3] or {}) do if e[1] then out[#out + 1] = { kind = "collect", store = "items", ids = { e[1] } } end end
    for _, e in ipairs(o[5] or {}) do
        local ids = type(e[1]) == "table" and e[1] or (e[1] and { e[1] })
        if ids then out[#out + 1] = { kind = "kill", store = "npcs", ids = ids } end
    end
    return out
end

local function RefName(ref)
    local id = ref.ids[1]
    return id and data.Field(ref.store, id, "name") or nil
end

-- the level range of the creatures behind an objective (the mobs to kill, or the mobs that drop the item)
local function MobLevelText(ref)
    local npcs = {}
    if ref.store == "npcs" then npcs = ref.ids
    elseif ref.store == "items" then
        for _, id in ipairs(ref.ids) do
            local d = data.Field("items", id, "npcDrops")
            if type(d) == "table" then for _, n in pairs(d) do npcs[#npcs + 1] = n end end
        end
    else return nil end
    local lo, hi
    for i, id in ipairs(npcs) do
        if i > 40 then break end
        local a, b = data.Field("npcs", id, "minLevel"), data.Field("npcs", id, "maxLevel")
        a, b = tonumber(a), tonumber(b or a)
        if a and a > 0 then
            lo = lo and math.min(lo, a) or a
            hi = hi and math.max(hi, b or a) or (b or a)
        end
    end
    if not lo then return nil end
    return lo == hi and ("Mob level " .. lo) or ("Mob levels " .. lo .. "-" .. hi)
end

-- spots on the ground (object = true: a thing to click) and spots where mobs are. An item can come from both, and they are
-- gathered apart so a long list of mobs never pushes the objects off the map
local function GatherSpawns(ref)
    local list = {}
    local function Objects(ids)
        if type(ids) ~= "table" or not api.AddObjects then return end
        local got = {}
        pcall(api.AddObjects, got, ids)
        for _, s in ipairs(got) do s.object = true; list[#list + 1] = s end
    end
    if ref.store == "objects" then
        Objects(ref.ids)
    elseif ref.store == "npcs" then
        if api.AddNpcs then pcall(api.AddNpcs, list, ref.ids) end
    elseif ref.store == "items" then
        for _, id in ipairs(ref.ids) do
            Objects(data.Field("items", id, "objectDrops"))
            local npcs = data.Field("items", id, "npcDrops")
            if type(npcs) == "table" and api.AddNpcs then
                local some = {}
                for _, n in pairs(npcs) do
                    if #some >= 40 then break end
                    some[#some + 1] = n
                end
                local got = {}
                pcall(api.AddNpcs, got, some)
                for _, s in ipairs(got) do list[#list + 1] = s end
            end
        end
    end
    return list
end

-- the spots to draw: a limit for each zone (one for the whole list would drop the zone I am in), objects with their own, larger one
local function PickSpots(list)
    local out, count = {}, {}
    for _, s in ipairs(list) do
        local key = tostring(s.uiMapId) .. (s.object and "o" or "n")
        local n = count[key] or 0
        if n < (s.object and PER_ZONE_OBJECT or PER_ZONE) then
            count[key] = n + 1
            out[#out + 1] = s
        end
    end
    return out
end
addon.QuestMapSpots = { Gather = GatherSpawns, Pick = PickSpots }            -- for the offline tests

local spawnCache = {}
local function Spawns(ref)
    local key = ref.store .. ":" .. table.concat(ref.ids, ",")
    local c = spawnCache[key]
    if c then return c end
    local list = PickSpots(GatherSpawns(ref))
    spawnCache[key] = list
    return list
end

--------------------------------------------------------------------------------
-- Collect the pins
--------------------------------------------------------------------------------
local function InInstance()
    return IsInInstance and select(1, IsInInstance()) and true or false
end

local function MyQuests()
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then out[#out + 1] = info end
    end
    return out
end

local function AddCell(cells, order, kind, s, title, lines)
    if not (s.uiMapId and s.zx and s.zy) then return end
    local cell = kind == "object" and CELL_OBJECT or CELL
    local key = kind .. ":" .. s.uiMapId .. ":" .. math.floor(s.zx * cell) .. ":" .. math.floor(s.zy * cell)
    local c = cells[key]
    if not c then
        c = { kind = kind, uiMapId = s.uiMapId, zx = s.zx, zy = s.zy, x = s.x, y = s.y, instance = s.instance, info = {}, titles = {}, title = title, area = s.area }
        cells[key] = c
        order[#order + 1] = c
    end
    if not c.titles[title] then
        c.titles[title] = true
        c.info[#c.info + 1] = title
        for _, l in ipairs(lines or {}) do c.info[#c.info + 1] = l end
    end
end

local function Build()
    local cells, order = {}, {}
    local db = DB()
    local mapNow = hbd and hbd:GetPlayerZone()
    local dungeonHere = InInstance()

    for _, q in ipairs(MyQuests()) do
        local done = C_QuestLog.IsComplete and select(2, pcall(C_QuestLog.IsComplete, q.questID))
        local dungeonQuest = api.IsDungeonQuest and api.IsDungeonQuest(q.questID, done and true or false)
        if dungeonQuest and not dungeonHere then
            -- dungeon quests only show inside a dungeon, like the tracker
        elseif done then
            -- a finished quest: a ? where it is handed in
            if Wants("givers") then
                local by = data.Field("quests", q.questID, "finishedBy")
                if type(by) == "table" then
                    local list = {}
                    if api.AddNpcs then pcall(api.AddNpcs, list, by[1]) end
                    if api.AddObjects then pcall(api.AddObjects, list, by[2]) end
                    for _, s in ipairs(list) do AddCell(cells, order, "turnin", s, "Turn in: " .. tostring(q.title), { "Ready to hand in" }) end
                end
            end
        elseif Wants("objectives") then
            local okO, objs = pcall(C_QuestLog.GetQuestObjectives, q.questID)
            local refs = Refs(q.questID)
            if okO and type(objs) == "table" and #refs > 0 then
                for i, o in ipairs(objs) do
                    if not o.finished then
                        -- which thing is this objective about: by name in the objective text, else by position
                        local ref
                        local text = (o.text or ""):lower()
                        for _, r in ipairs(refs) do
                            local nm = RefName(r)
                            if nm and text:find(nm:lower(), 1, true) then ref = r; break end
                        end
                        if not ref and #objs == #refs then ref = refs[i] end
                        if ref then
                            -- the tooltip words are the same for every spot, so they are worked out once, not spot by spot:
                            -- the mob levels alone can take dozens of lookups, and a hunting quest has hundreds of spots
                            local ql = tonumber(data.Field("quests", q.questID, "questLevel")) or tonumber(q.level)
                            local lines = {}
                            if ql and ql > 0 then lines[#lines + 1] = "Quest level " .. ql end
                            local ml = MobLevelText(ref)
                            if ml then lines[#lines + 1] = ml end
                            lines[#lines + 1] = o.text or ""
                            local ground = { unpack(lines) }
                            ground[#ground + 1] = "On the ground: click it"
                            for _, s in ipairs(Spawns(ref)) do
                                AddCell(cells, order, s.object and "object" or ref.kind, s, tostring(q.title), s.object and ground or lines)
                            end
                        end
                    end
                end
            end
        end
    end

    -- quests I can pick up in this zone
    -- the zone I am in, and whatever the world map is showing now (a zone, or a continent with all its zones)
    local zones = {}
    if mapNow then zones[mapNow] = true end
    local viewed = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if viewed then
        zones[viewed] = true
        if C_Map and C_Map.GetMapChildrenInfo then
            local okK, kids = pcall(C_Map.GetMapChildrenInfo, viewed, nil, true)
            if okK and type(kids) == "table" then for _, k in ipairs(kids) do if k.mapID then zones[k.mapID] = true end end end
        end
    end
    local giverCap = viewed and 400 or 120
    if Wants("givers") and next(zones) and data.Available then
        local avail = data.Available()
        local n = 0
        local QDB = api.GetQuestie and api.GetQuestie()
        local mine = {}
        for _, q in ipairs(MyQuests()) do mine[q.questID] = true end
        for id in pairs(avail or {}) do
            if n >= giverCap then break end
            if not mine[id] and not (api.IsDungeonQuest and api.IsDungeonQuest(id, false)) then
                local level = data.Field("quests", id, "questLevel")
                local grey = QDB and QDB.IsTrivial and level and level > 0 and QDB.IsTrivial(level)
                local skipped = db.planSkip and db.planSkip[id]
                -- map filter: hide quests far above my level (the slider; 10 = show everything)
                local above = tonumber(db.questMapGiverAbove) or 10
                local tooHigh = above < 10 and level and level > 0 and level > (UnitLevel("player") or 1) + above
                if tooHigh then skipped = true end
                if not grey and not skipped then
                    local by = data.Field("quests", id, "startedBy")
                    if type(by) == "table" then
                        local list = {}
                        if api.AddNpcs then pcall(api.AddNpcs, list, by[1]) end
                        if api.AddObjects then pcall(api.AddObjects, list, by[2]) end
                        for _, s in ipairs(list) do
                            if zones[s.uiMapId] then
                                n = n + 1
                                AddCell(cells, order, "give", s, string.format("[%s] %s", tostring(level or "?"), tostring(data.Field("quests", id, "name"))), { "Quest to pick up" })
                            end
                        end
                    end
                end
            end
        end
    end
    return order
end

--------------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------------
-- Which pins go on the world map when there are more than it takes. Taking the nearest ones hid whole quests until I walked
-- up to them, so the room is shared: every quest (and every giver) gets one pin, then every one a second, and so on, each
-- its nearest first. Zones in "here" (mine and the one on the map) are served before the others.
-- entries: { { c = { kind, title, uiMapId } }, ... } nearest first. Returns the chosen entries, still nearest first.
local function Budget(entries, max, here)
    if #entries <= max then return entries end
    local chosen, total = {}, 0
    for _, wantHere in ipairs({ true, false }) do
        local queues, order = {}, {}
        for _, e in ipairs(entries) do
            if (here[e.c.uiMapId] == true) == wantHere then
                local key = tostring(e.c.kind) .. "\1" .. tostring(e.c.title)
                if not queues[key] then queues[key] = {}; order[#order + 1] = queues[key] end
                table.insert(queues[key], e)
            end
        end
        local round, more = 1, true
        while more and total < max do
            more = false
            for _, q in ipairs(order) do
                if q[round] and total < max then
                    chosen[q[round]] = true; total = total + 1; more = true
                end
            end
            round = round + 1
        end
    end
    local out = {}
    for _, e in ipairs(entries) do if chosen[e] then out[#out + 1] = e end end
    return out
end
addon.QuestMapBudget = Budget                                                -- for the offline tests

local lastSig = ""
local LiftAfterDraw
local drawnAt                   -- where I stood, and when, the last time the pins were drawn
local function Draw(force)
    if not hbdp then return end
    local db = DB() or {}
    local ok, order = pcall(Build)
    if not ok then order = {} end
    -- same pins as last time: leave them
    local sigParts = { #order }
    for i = 1, math.min(#order, 40) do sigParts[#sigParts + 1] = order[i].kind .. order[i].uiMapId .. math.floor(order[i].zx * 1000) end
    local sig = table.concat(sigParts, ",")
    if sig == lastSig and not force then return end
    lastSig = sig

    Clear()
    local px, py, pinst; if hbd then px, py, pinst = hbd:GetPlayerWorldPosition() end
    drawnAt = { x = px, y = py, inst = pinst, time = GetTime and GetTime() or 0 }
    -- nearest first for the minimap
    local byDistance = {}
    for _, c in ipairs(order) do
        local d = (px and c.instance == pinst) and ((c.x - px) ^ 2 + (c.y - py) ^ 2) or 1e18
        byDistance[#byDistance + 1] = { c = c, d = d }
    end
    table.sort(byDistance, function(a, b) return a.d < b.d end)
    local here = {}
    local mine = hbd and hbd:GetPlayerZone()
    if mine then here[mine] = true end
    local viewed = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if viewed then here[viewed] = true end
    -- mob and drop spots show as coloured areas. The skull and diamond icons hide what is under them, so they are only drawn
    -- when I ask for them, or when the areas are off and there would be nothing to see
    local icons = db.questMapIcons == true or not Wants("areas")
    local areaSpots, pinSpots = {}, {}
    for _, e in ipairs(byDistance) do
        local mobs = e.c.kind == "kill" or e.c.kind == "collect"
        if mobs then areaSpots[#areaSpots + 1] = e end
        if icons or not mobs then pinSpots[#pinSpots + 1] = e end
    end
    local forAreas = Budget(areaSpots, MAX_WORLD, here)
    local forWorld = Budget(pinSpots, MAX_WORLD, here)

    -- the coloured areas first, so the icons sit on top
    if Wants("areas") then
        for n, e in ipairs(forAreas) do
            local c = e.c
            local size = AreaSize(c.uiMapId)
            local f = AreaFrame(n)
            local r, g, b = Colour(c.title or "")
            f.tex:SetVertexColor(r, g, b, AREA_ALPHA)
            f:SetSize(size, size)
            f.info, f.cell = c.info, c
            if f.SetHitRectInsets then local ins = size * 0.15; f:SetHitRectInsets(ins, ins, ins, ins) end
            pcall(hbdp.AddWorldMapIconMap, hbdp, OWNER, f, c.uiMapId, c.zx, c.zy)
        end
    end

    local scale = math.max(0.5, math.min(2, tonumber(db.questMapScale) or 1))
    for i, e in ipairs(forWorld) do
        local c = e.c
        local f = Frame(worldFrames, i, SIZE_WORLD.other)
        Style(f, c.kind); f.info = c.info; f.cell = c
        local sz = (SIZE_WORLD[c.kind] or SIZE_WORLD.other) * scale
        f:SetSize(sz, sz)
        pcall(hbdp.AddWorldMapIconMap, hbdp, OWNER, f, c.uiMapId, c.zx, c.zy, _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2)
    end
    -- the minimap shows what is around me, so there the nearest ones are the right ones
    for i = 1, math.min(#byDistance, MAX_MINI) do
        local e = byDistance[i]
        local c = e.c
        if e.d < 1e18 and e.d < 1500 ^ 2 then
            local f = Frame(miniFrames, i, SIZE_MINI.other)
            Style(f, c.kind); f.info = c.info; f.cell = c
            local msz = (SIZE_MINI[c.kind] or SIZE_MINI.other) * scale
            -- the minimap has no areas: a small see-through dot in the quest's colour stands in for the icon
            if not icons and (c.kind == "kill" or c.kind == "collect") then
                f.tex:SetTexture(DOT)
                local r, g, b = Colour(c.title or "")
                f.tex:SetVertexColor(r, g, b, 1)
                msz = SIZE_MINI.object * scale
            end
            f:SetSize(msz, msz)
            pcall(hbdp.AddMinimapIconMap, hbdp, OWNER, f, c.uiMapId, c.zx, c.zy, false, false)
        end
    end
    if LiftAfterDraw then LiftAfterDraw() end
end

local pending
local function Later(delay, force)
    if pending or not C_Timer then return end
    pending = true
    C_Timer.After(delay or 2, function() pending = false; pcall(Draw, force) end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then Later(6, true) else Later(2) end
end)
-- the minimap shows the pins nearest to me: refresh them now and then as I move. Drawing everything again is the heaviest
-- thing here, so standing about or fighting in one place does not do it (only once a minute, to be safe)
local MOVED, STALE = 75, 60             -- yards, seconds
local function NeedsRedraw()
    if not drawnAt or (GetTime and GetTime() or 0) - drawnAt.time >= STALE then return true end
    if not hbd then return true end
    local x, y, inst = hbd:GetPlayerWorldPosition()
    if not (x and drawnAt.x) or inst ~= drawnAt.inst then return true end
    return (x - drawnAt.x) ^ 2 + (y - drawnAt.y) ^ 2 >= MOVED ^ 2
end
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 15 then return end
    acc = 0
    if hbdp and DB() and DB().questMap ~= false and NeedsRedraw() then Later(0, true) end
end)

-- OpenMap draws its map art over the canvas and lifts only the pins it knows by name; ours would sit under the art, so lift them
-- above it (areas lowest, then the skulls and diamonds, the ! and ? on top)
local function LiftAll()
    local om = _G.OpenMapAPI
    if not (om and om.IsStitched and om.IsStitched() and om.ArtTopLevel) then return end
    local top = om.ArtTopLevel()
    if type(top) ~= "number" or InCombatLockdown() then return end
    local function Up(f, level)
        if f and f.SetFrameLevel and f:GetFrameLevel() < level then pcall(f.SetFrameLevel, f, level) end
    end
    for _, f in ipairs(areaFrames) do Up(f, top + 1) end
    for _, f in ipairs(worldFrames) do
        local k = f.cell and f.cell.kind
        Up(f, (k == "give" or k == "turnin") and top + 5 or top + 3)
    end
end

local function ResizeAreas()
    pcall(LiftAll)
    local cache = {}
    for _, f in ipairs(areaFrames) do
        if f:IsShown() or f.cell then
            local id = f.cell and f.cell.uiMapId
            local size = cache[id or 0]
            if not size then size = AreaSize(id); cache[id or 0] = size end
            f:SetSize(size, size)
            if f.SetHitRectInsets then local ins = size * 0.15; f:SetHitRectInsets(ins, ins, ins, ins) end
        end
    end
end

-- the map moves to another zone or continent while it is open: show that place's quest givers too
if WorldMapFrame and hooksecurefunc and WorldMapFrame.OnMapChanged then
    pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", function() if WorldMapFrame:IsShown() then lastSig = ""; Later(0.4, true) end end)
end

LiftAfterDraw = function()
    -- once now, and again a moment later: the map places the pins just after they are handed to it
    pcall(LiftAll)
    if C_Timer and C_Timer.After then C_Timer.After(0.5, function() pcall(LiftAll) end) end
end
if WorldMapFrame and WorldMapFrame.HookScript then
    pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", function() lastSig = ""; Later(0.2, true); ResizeAreas(); if C_Timer then C_Timer.After(0.3, function() pcall(LiftAll) end) end end)
end
-- OpenMap: the stitched map changes what a zone is on the canvas as you zoom, so the areas follow
do
    local om = _G.OpenMapAPI
    if om and om.RegisterCallback then
        local owner = {}
        pcall(om.RegisterCallback, owner, "OpenMap_StitchedChanged", function() pcall(ResizeAreas) end)
        pcall(om.RegisterCallback, owner, "OpenMap_ViewChanged", function() pcall(ResizeAreas) end)
    end
end

-- Clicking a quest on the game's own map (or in its quest list) tracks it: point the arrow at that quest too
do
    local lastId, lastT = nil, 0
    local function OnTrack(id)
        id = tonumber(id)
        if not id or id <= 0 or not Wants("objectives") then return end
        if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end          -- only clicks made on the map, not the game tracking by itself
        local now = GetTime and GetTime() or 0
        if id == lastId and now - lastT < 2 then return end
        lastId, lastT = id, now
        if not (addon.QuestInLog and addon.QuestInLog(id) and addon.QuestPointAt) then return end
        local name = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id) or ("quest " .. id)
        if C_Timer and C_Timer.After then C_Timer.After(0.1, function() pcall(addon.QuestPointAt, id, name) end) end
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID and hooksecurefunc then
        pcall(hooksecurefunc, C_SuperTrack, "SetSuperTrackedQuestID", OnTrack)
    end
    if hooksecurefunc and _G.SetSuperTrackedQuestID then pcall(hooksecurefunc, "SetSuperTrackedQuestID", OnTrack) end
end

function addon.QuestMapRefresh() lastSig = ""; spawnCache = {}; Later(0, true) end

--------------------------------------------------------------------------------
-- /lazy questmap
--------------------------------------------------------------------------------
-- a small window with text you can select and copy (Ctrl-A, Ctrl-C)
function addon.ShowTextPopup(title, text)
    local f = addon.textPopup
    if not f then
        f = CreateFrame("Frame", "ForeverLazyTextPopup", UIParent, "BackdropTemplate")
        f:SetSize(560, 300)
        f:SetPoint("CENTER", 0, 60)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
        f:SetBackdropBorderColor(0.6, 0.6, 0.7, 1)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 12, -10)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local sf = CreateFrame("ScrollFrame", "ForeverLazyTextPopupScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -32)
        sf:SetPoint("BOTTOMRIGHT", -30, 12)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal or GameFontHighlight)
        eb:SetWidth(510)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        sf:SetScrollChild(eb)
        f.edit = eb
        if UISpecialFrames then table.insert(UISpecialFrames, "ForeverLazyTextPopup") end
        addon.textPopup = f
    end
    f.title:SetText(title or "Forever Lazy")
    f.edit:SetText(text or "")
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "questmap" then
        local a, b = (rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
        local db = DB()
        if a == "debug" then
            -- what the map pins look like with the map OPEN (closed, the map lets go of them): opens it, looks 2 seconds later
            local function Dump()
            local lines = {}
            local function Say(s) lines[#lines + 1] = s end
            local om = _G.OpenMapAPI
            local okB, order = pcall(Build)
            local counts = {}
            if okB then for _, c in ipairs(order) do counts[c.kind] = (counts[c.kind] or 0) + 1 end end
            local parts = {}
            for k, v in pairs(counts) do parts[#parts + 1] = k .. "=" .. v end
            Say("quest map debug: pins wanted: " .. (#parts > 0 and table.concat(parts, " ") or "none") .. (okB and "" or (" (build error: " .. tostring(order) .. ")")))
            Say(string.format("  OpenMap %s, stitched %s, art level %s, map shown %s, map id %s, my zone %s", om and "yes" or "no",
                tostring(om and om.IsStitched and om.IsStitched()), tostring(om and om.ArtTopLevel and om.ArtTopLevel()),
                tostring(WorldMapFrame and WorldMapFrame:IsShown()), tostring(WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()),
                tostring(hbd and hbd:GetPlayerZone())))
            local seen = {}
            for _, f in ipairs(worldFrames) do
                local k = f.cell and f.cell.kind
                if k and not seen[k] and f.cell then
                    seen[k] = true
                    local p = f:GetParent()
                    local cx, cy = f:GetCenter()
                    Say(string.format("  %s: shown %s visible %s level %s strata %s alpha %.2f size %.0f scale %.2f parent %s points %d center %s",
                        k, tostring(f:IsShown()), tostring(f:IsVisible()), tostring(f:GetFrameLevel()), tostring(f:GetFrameStrata()), f:GetAlpha(),
                        f:GetWidth(), f:GetEffectiveScale(), tostring(p and (p:GetName() or p:GetObjectType())), f:GetNumPoints(), cx and string.format("%.0f,%.0f", cx, cy) or "none"))
                end
            end
            if not next(seen) then Say("  no pin frames have been made yet") end
            addon.ShowTextPopup(L("Quest map pins"), table.concat(lines, "\n"))
            end
            if WorldMapFrame and not WorldMapFrame:IsShown() and ToggleWorldMap and not InCombatLockdown() then
                pcall(ToggleWorldMap)
                if C_Timer then C_Timer.After(2, function() pcall(Dump) end) else pcall(Dump) end
            else
                Dump()
            end
            return true
        end
        local on = (b == "on" or a == "on")
        local off = (b == "off" or a == "off")
        local function Set(key) if on then db[key] = nil elseif off then db[key] = false end end
        if a == "objectives" then Set("questMapObjectives")
        elseif a == "areas" then Set("questMapAreas")
        elseif a == "givers" then Set("questMapGivers")
        elseif a == "on" or a == "off" then Set("questMap") end
        if db.questMap == false then Clear() else addon.QuestMapRefresh() end
        Print(string.format(L("quest map: %s (objectives %s, areas %s, quest givers and turn-ins %s)"), db.questMap == false and "OFF" or "on",
            db.questMapObjectives == false and "off" or "on", db.questMapAreas == false and "off" or "on", db.questMapGivers == false and "off" or "on"))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestMap.lua"] = true end end
