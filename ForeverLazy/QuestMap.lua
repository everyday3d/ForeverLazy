-- The quest map: where my quests' mobs, items and objects are, drawn on the world map and the minimap, like Questie does.
--   skull      kill this           purple diamond   collect this (where it drops)       green triangle   use or click this
--   yellow !   a quest I can pick up here (this zone)                     yellow ?   a finished quest to hand in
-- Hover a pin for the quest and what is left. Finished objectives are not drawn. Own pins, separate from the route and arrow pins.
--   /lazy questmap on|off   everything      /lazy questmap objectives|givers on|off
local ADDON, ns = ...
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
    object = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
    give = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
}
local MAX_WORLD, MAX_MINI, PER_OBJECTIVE = 320, 70, 45
local CELL = 70                                          -- spots closer than 1/70 of a zone map share one pin

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
    GameTooltip:AddLine("Click: point the arrow here", 0.5, 1, 0.5)
    GameTooltip:AddLine("Forever Lazy", 0.5, 0.5, 0.5)
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

local function AreaSize()
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    local w = canvas and canvas.GetWidth and canvas:GetWidth() or 1000
    if not w or w <= 0 then w = 1000 end
    return w * 2.4 / CELL
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

local spawnCache = {}
local function Spawns(ref)
    local key = ref.store .. ":" .. table.concat(ref.ids, ",")
    local c = spawnCache[key]
    if c then return c end
    local list = {}
    if ref.store == "npcs" and api.AddNpcs then pcall(api.AddNpcs, list, ref.ids)
    elseif ref.store == "objects" and api.AddObjects then pcall(api.AddObjects, list, ref.ids)
    elseif ref.store == "items" and api.AddItemSources then for _, id in ipairs(ref.ids) do pcall(api.AddItemSources, list, id) end end
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
    local key = kind .. ":" .. s.uiMapId .. ":" .. math.floor(s.zx * CELL) .. ":" .. math.floor(s.zy * CELL)
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
                            local spawns = Spawns(ref)
                            local picked = 0
                            for _, s in ipairs(spawns) do
                                if picked >= PER_OBJECTIVE then break end
                                picked = picked + 1
                                local ql = tonumber(data.Field("quests", q.questID, "questLevel")) or tonumber(q.level)
                                local lines = {}
                                if ql and ql > 0 then lines[#lines + 1] = "Quest level " .. ql end
                                local ml = MobLevelText(ref)
                                if ml then lines[#lines + 1] = ml end
                                lines[#lines + 1] = o.text or ""
                                AddCell(cells, order, ref.kind, s, tostring(q.title), lines)
                            end
                        end
                    end
                end
            end
        end
    end

    -- quests I can pick up in this zone
    if Wants("givers") and mapNow and data.Available then
        local avail = data.Available()
        local n = 0
        local QDB = api.GetQuestie and api.GetQuestie()
        local mine = {}
        for _, q in ipairs(MyQuests()) do mine[q.questID] = true end
        for id in pairs(avail or {}) do
            if n >= 120 then break end
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
                            if s.uiMapId == mapNow then
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
local lastSig = ""
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
    local px, py, pinst = hbd and hbd:GetPlayerWorldPosition()
    -- nearest first for the minimap
    local byDistance = {}
    for _, c in ipairs(order) do
        local d = (px and c.instance == pinst) and ((c.x - px) ^ 2 + (c.y - py) ^ 2) or 1e18
        byDistance[#byDistance + 1] = { c = c, d = d }
    end
    table.sort(byDistance, function(a, b) return a.d < b.d end)

    -- the coloured areas first, so the icons sit on top
    if Wants("areas") then
        local size = AreaSize()
        local n = 0
        for _, e in ipairs(byDistance) do
            local c = e.c
            if c.kind == "kill" or c.kind == "collect" or c.kind == "object" then
                n = n + 1
                if n > MAX_WORLD then break end
                local f = AreaFrame(n)
                local r, g, b = Colour(c.title or "")
                f.tex:SetVertexColor(r, g, b, 0.30)
                f:SetSize(size, size)
                f.info, f.cell = c.info, c
                if f.SetHitRectInsets then local ins = size * 0.15; f:SetHitRectInsets(ins, ins, ins, ins) end
                pcall(hbdp.AddWorldMapIconMap, hbdp, OWNER, f, c.uiMapId, c.zx, c.zy)
            end
        end
    end

    for i, e in ipairs(byDistance) do
        local c = e.c
        if i <= MAX_WORLD then
            local f = Frame(worldFrames, i, c.kind == "give" and 16 or 13)
            f.tex:SetTexture(TEX[c.kind]); f.info = c.info; f.cell = c
            local scale = math.max(0.5, math.min(2, tonumber(db.questMapScale) or 1))
            local sz = ((c.kind == "give" or c.kind == "turnin") and 16 or 13) * scale
            f:SetSize(sz, sz)
            pcall(hbdp.AddWorldMapIconMap, hbdp, OWNER, f, c.uiMapId, c.zx, c.zy)
        end
        if i <= MAX_MINI and e.d < 1e18 and e.d < 1500 ^ 2 then
            local f = Frame(miniFrames, i, 11)
            f.tex:SetTexture(TEX[c.kind]); f.info = c.info; f.cell = c
            local msz = 11 * math.max(0.5, math.min(2, tonumber(db.questMapScale) or 1))
            f:SetSize(msz, msz)
            pcall(hbdp.AddMinimapIconMap, hbdp, OWNER, f, c.uiMapId, c.zx, c.zy, false, false)
        end
    end
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
-- the minimap shows the pins nearest to me: refresh them now and then as I move
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 15 then return end
    acc = 0
    if hbdp and DB() and DB().questMap ~= false then Later(0, true) end
end)

if WorldMapFrame and WorldMapFrame.HookScript then
    pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", function()
        local size = AreaSize()
        for _, f in ipairs(areaFrames) do
            f:SetSize(size, size)
            if f.SetHitRectInsets then local ins = size * 0.15; f:SetHitRectInsets(ins, ins, ins, ins) end
        end
    end)
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
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "questmap" then
        local a, b = (rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
        local db = DB()
        local on = (b == "on" or a == "on")
        local off = (b == "off" or a == "off")
        local function Set(key) if on then db[key] = nil elseif off then db[key] = false end end
        if a == "objectives" then Set("questMapObjectives")
        elseif a == "areas" then Set("questMapAreas")
        elseif a == "givers" then Set("questMapGivers")
        elseif a == "on" or a == "off" then Set("questMap") end
        if db.questMap == false then Clear() else addon.QuestMapRefresh() end
        Print(string.format("quest map: %s (objectives %s, areas %s, quest givers and turn-ins %s)", db.questMap == false and "OFF" or "on",
            db.questMapObjectives == false and "off" or "on", db.questMapAreas == false and "off" or "on", db.questMapGivers == false and "off" or "on"))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestMap.lua"] = true end end
