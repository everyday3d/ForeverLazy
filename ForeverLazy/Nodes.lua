-- Ore and herb nodes I have found: remembered, marked on the world map, and offered to the arrow for farming.
--   Every time I mine or pick a plant, the spot is saved (same node found again just counts up).
--   The world map shows a pin for each one, and hovering a pin says what it is and how often I found it.
--   The arrow can walk me from node to node (right-click the arrow, or /lazy nodes farm). A node I just
--   emptied is skipped for a while, and one I reached that was not there is skipped too.
--   /lazy nodes            what I know          /lazy nodes farm [ore|herb|name]   arrow to the nearest
--   /lazy nodes pins on|off                      /lazy nodes clear                   forget them all
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local SAME_SPOT = 35            -- yards: a node found within this of a saved one is the same node
local MAX_NODES = 800
local RESPAWN_SKIP = 300        -- seconds I leave a node alone after gathering it (it respawns in minutes)
local MISSING_SKIP = 600        -- seconds I leave a node alone when I got there and it was not there
local ARRIVE = 12               -- yards

local ICONS = {
    ore  = "Interface\\Icons\\Trade_Mining",
    herb = "Interface\\Icons\\Trade_Herbalism",
}

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Nodes()
    local db = DB()
    if not db then return {} end
    db.nodes = db.nodes or {}
    return db.nodes
end

local function On()
    return addon.ModuleOn and addon.ModuleOn("gather")
end

local function SpellNameOf(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and n then return n end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok and n then return n end
    end
end

local miningName, herbName
local function KindOfSpell(spellId)
    if not spellId or IsSecret(spellId) then return nil end
    miningName = miningName or SpellNameOf(2575)
    herbName = herbName or SpellNameOf(2366)
    local n = SpellNameOf(spellId)
    if not n then return nil end
    if n == miningName then return "ore" end
    if n == herbName then return "herb" end
end

local function Dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function Ago(t)
    local s = math.max(0, (time and time() or 0) - (t or 0))
    if s < 3600 then return math.floor(s / 60) .. " minutes ago" end
    if s < 86400 then return math.floor(s / 3600) .. " hours ago" end
    return math.floor(s / 86400) .. " days ago"
end

--------------------------------------------------------------------------------
-- Remembering a node
--------------------------------------------------------------------------------
local lastHit = setmetatable({}, { __mode = "k" })     -- node -> GetTime() when I last emptied it
local skipUntil = setmetatable({}, { __mode = "k" })   -- node -> GetTime() until which the arrow ignores it
local RefreshPins                                       -- forward declaration

local function Record(kind, name)
    local px, py, inst = hbd:GetPlayerWorldPosition()
    if not px then return end
    local zx, zy, map = hbd:GetPlayerZonePosition()
    local list = Nodes()
    local hit
    for _, n in ipairs(list) do
        if n.i == inst and n.k == kind and Dist(n.x, n.y, px, py) <= SAME_SPOT then
            if not name or n.name == name or n.name == (kind == "ore" and "Ore" or "Herb") then hit = n; break end
        end
    end
    if hit then
        hit.c = (hit.c or 1) + 1
        hit.t = time and time() or hit.t
        if name then hit.name = name end
    else
        if #list >= MAX_NODES then table.remove(list, 1) end      -- the oldest goes first
        hit = { k = kind, name = name or (kind == "ore" and "Ore" or "Herb"), i = inst, x = px, y = py,
                m = map, zx = zx, zy = zy, c = 1, t = time and time() or 0 }
        list[#list + 1] = hit
        Print(string.format(L("noted %s on the map (%d found so far)"), hit.name, #list))
    end
    lastHit[hit] = GetTime()
    if C_Timer then C_Timer.After(1, RefreshPins) else RefreshPins() end
end

local pending       -- the gather I just started: { kind, name, guid }
local ev = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, a, b, c, d)
    if event == "PLAYER_ENTERING_WORLD" then
        if C_Timer then C_Timer.After(3, RefreshPins) end
        return
    end
    if a ~= "player" or not On() then return end
    if event == "UNIT_SPELLCAST_SENT" then
        -- a = unit, b = target name, c = cast id, d = spell id
        local kind = KindOfSpell(d)
        if kind then
            local name = (type(b) == "string" and not IsSecret(b) and b ~= "") and b or nil
            pending = { kind = kind, name = name, guid = c }
        else
            pending = nil
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a = unit, b = cast id, c = spell id
        if pending and (b == pending.guid or KindOfSpell(c) == pending.kind) then
            local p = pending
            pending = nil
            pcall(Record, p.kind, p.name)
        end
    end
end)

--------------------------------------------------------------------------------
-- Pins on the world map
--------------------------------------------------------------------------------
local hbdp = LibStub("HereBeDragons-Pins-2.0", true)
local pinRef = {}
local pinFrames = {}

-- an ore pin shows the ore the vein holds (copper vein = copper ore), in a round rock-coloured frame
local ORE_ICONS = {
    { "truesilver", "INV_Ore_Truesilver_01" }, { "thorium", "INV_Ore_Thorium_02" }, { "mithril", "INV_Ore_Mithril_02" },
    { "copper", "INV_Ore_Copper_01" }, { "tin", "INV_Ore_Tin_01" }, { "silver", "INV_Ore_Silver_01" },
    { "iron", "INV_Ore_Iron_01" }, { "gold", "INV_Ore_Gold_01" },
}
local function IconFor(n)
    if n.k == "ore" then
        local l = (n.name or ""):lower()
        for _, e in ipairs(ORE_ICONS) do
            if l:find(e[1], 1, true) then return "Interface\\Icons\\" .. e[2] end
        end
        return ICONS.ore
    end
    return ICONS.herb
end

local function PinEnter(self)
    local n = self.node
    if not n then return end
    if self.mini then self.hover = true; self:SetAlpha(0.1) end      -- out of the way so the real blip under it shows
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(n.name or "Node", 1, 0.82, 0)
    GameTooltip:AddLine(string.format("Found %d time%s, last %s", n.c or 1, (n.c or 1) == 1 and "" or "s", Ago(n.t)), 1, 1, 1)
    if addon.NodeResting and addon.NodeResting(n) then
        GameTooltip:AddLine(L("Faded: you just took it, or it was not there. Probably respawning."), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(L("Forever Lazy"), 0.5, 0.5, 0.5)
    GameTooltip:Show()
end
local function PinLeave(self)
    GameTooltip:Hide()
    if self and self.hover then self.hover = nil; self:SetAlpha(1) end     -- the next tick puts back its usual fade
end

local function WantKind(n)
    local f = DB().nodeFilter or "all"
    return f == "all" or f == n.k
end

local function MakePin(size, withMouse)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(size, size)
    local inset = math.max(1, math.floor(size / 15))
    f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, 0)       -- dark edge so it stands out on any map
    f.shadow:SetAllPoints()
    f.shadow:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.shadow:SetVertexColor(0, 0, 0, 0.9)
    f.ring = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.ring:SetPoint("TOPLEFT", inset, -inset); f.ring:SetPoint("BOTTOMRIGHT", -inset, inset)
    f.ring:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", inset * 2 + 1, -(inset * 2 + 1)); f.tex:SetPoint("BOTTOMRIGHT", -(inset * 2 + 1), inset * 2 + 1)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if f.ring.SetMask then
        for _, t in ipairs({ f.shadow, f.ring, f.tex }) do
            pcall(t.SetMask, t, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
        end
    end
    if withMouse then
        f:EnableMouse(true)
        f:SetScript("OnEnter", PinEnter)
        f:SetScript("OnLeave", PinLeave)
    end
    f:Hide()
    return f
end

local function Paint(f, n)
    f.node = n
    f.tex:SetTexture(IconFor(n))
    if n.k == "herb" then f.ring:SetVertexColor(0.3, 1, 0.3) else f.ring:SetVertexColor(1, 0.8, 0.2) end
end

local miniFrames = {}
local miniRef = {}

function RefreshPins()
    if not hbdp then return end
    pcall(hbdp.RemoveAllWorldMapIcons, hbdp, pinRef)
    pcall(hbdp.RemoveAllMinimapIcons, hbdp, miniRef)
    local db = DB()
    if not db or db.nodePins == false or not On() then return end
    local mini = db.nodeMini ~= false
    for idx, n in ipairs(Nodes()) do
        if WantKind(n) then
            local f = pinFrames[idx]
            if not f then f = MakePin(30, true); pinFrames[idx] = f end
            Paint(f, n)
            pcall(hbdp.AddWorldMapIconWorld, hbdp, pinRef, f, n.i, n.x, n.y, 1)
            if mini then
                local m = miniFrames[idx]
                if not m then m = MakePin(20, true); m.mini = true; miniFrames[idx] = m end
                Paint(m, n)
                pcall(hbdp.AddMinimapIconWorld, hbdp, miniRef, m, n.i, n.x, n.y, false)
            end
        end
    end
end
addon.RefreshNodePins = RefreshPins

-- a node I just emptied (or reached and found missing) is probably not there: its pin fades until it should be back
local function Resting(n)
    local now = GetTime()
    local skip, hit = skipUntil[n], lastHit[n]
    return (skip and skip > now) or (hit and now - hit < RESPAWN_SKIP) or false
end
addon.NodeResting = Resting

-- is Find Minerals / Find Herbs switched on? (the game then shows the real nodes on the minimap)
local function TrackingNow()
    local on = {}
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return on end
    local minerals, herbs = SpellNameOf(2580), SpellNameOf(2383)
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local ok, a, b, c = pcall(C_Minimap.GetTrackingInfo, i)
        if ok then
            local name, active = a, c
            if type(a) == "table" then name, active = a.name, a.active end
            if active and name then
                if name == minerals then on.ore = true elseif name == herbs then on.herb = true end
            end
        end
    end
    return on
end

local fadeAcc = 0
local fadeFrame = CreateFrame("Frame")
fadeFrame:SetScript("OnUpdate", function(_, dt)
    fadeAcc = fadeAcc + dt
    if fadeAcc < 2 then return end
    fadeAcc = 0
    local track = TrackingNow()
    for _, set in ipairs({ pinFrames, miniFrames }) do
        for _, f in pairs(set) do
            if f.node and not f.hover then
                local a = Resting(f.node) and 0.3 or 1
                -- the game is already drawing the real nodes on the minimap: keep mine faint so its blip shows through
                if set == miniFrames and a == 1 and track[f.node.k] and DB().nodeFadeTracked ~= false then a = 0.45 end
                f:SetAlpha(a)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- The arrow: the nearest node worth walking to
--------------------------------------------------------------------------------
local cache, cacheT = nil, 0

function addon.NearestNode()
    if not On() then return nil end
    local now = GetTime()
    if cache and now - cacheT < 0.5 then return cache.ref and cache.target end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return nil end
    local best, bestD
    for _, n in ipairs(Nodes()) do
        if n.i == pinst and WantKind(n) then
            local skip = skipUntil[n]
            local hit = lastHit[n]
            if not ((skip and skip > now) or (hit and now - hit < RESPAWN_SKIP)) then
                local d = Dist(n.x, n.y, px, py)
                if d <= ARRIVE then
                    -- stood where it should be for 20 seconds and did not gather it: it is not there, give it a rest
                    n.seen = n.seen or now
                    if now - n.seen > 20 then skipUntil[n] = now + MISSING_SKIP; n.seen = nil end
                else
                    n.seen = nil
                end
                if not skipUntil[n] or skipUntil[n] <= now then
                    if not bestD or d < bestD then best, bestD = n, d end
                end
            end
        end
    end
    if not best then
        cache, cacheT = { ref = nil }, now
        return nil
    end
    local target = { instance = best.i, x = best.x, y = best.y, name = best.name, detail = "Found " .. (best.c or 1) .. "x, last " .. Ago(best.t) }
    cache, cacheT = { ref = best, target = target }, now
    return target
end

-- the walk the arrow will take: the nearest node, then the nearest to that one, and so on (for the map lines)
function addon.NodeFarmPath(max)
    local first = addon.NearestNode()
    if not first or not cache or not cache.ref then return nil end
    local now = GetTime()
    local _, _, pinst = hbd:GetPlayerWorldPosition()
    local path = { { x = first.x, y = first.y, instance = first.instance, name = first.name, detail = first.detail } }
    local used = { [cache.ref] = true }
    local cur = cache.ref
    local list = Nodes()
    while #path < (max or 8) do
        local best, bestD
        for _, n in ipairs(list) do
            if not used[n] and n.i == pinst and WantKind(n) then
                local skip, hit = skipUntil[n], lastHit[n]
                if not ((skip and skip > now) or (hit and now - hit < RESPAWN_SKIP)) then
                    local d = Dist(n.x, n.y, cur.x, cur.y)
                    if d < 800 and (not bestD or d < bestD) then best, bestD = n, d end
                end
            end
        end
        if not best then break end
        used[best] = true
        cur = best
        path[#path + 1] = { x = best.x, y = best.y, instance = best.i, name = best.name, detail = "Found " .. (best.c or 1) .. "x" }
    end
    return path
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- The finder window: /lazy nodes silver
--------------------------------------------------------------------------------
local win, rows = nil, {}

local function ZoneOf(n)
    if n.m and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(n.m)
        if info and info.name then return info.name end
    end
    return "?"
end

local function ShowResults(want, mine, list, names, note)
    if not win then
        local f = CreateFrame("Frame", "ForeverLazy_NodeFinder", UIParent)
        f:SetSize(500, 440)
        f:SetPoint("CENTER", 0, 30)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.head = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.head:SetPoint("TOPLEFT", 16, -46); f.head:SetWidth(468); f.head:SetJustifyH("LEFT")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", "ForeverLazy_NodeFinderScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -100); scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        f.content = CreateFrame("Frame", nil, scroll)
        f.content:SetSize(440, 10)
        scroll:SetScrollChild(f.content)
        table.insert(UISpecialFrames, "ForeverLazy_NodeFinder")
        f:Hide()
        win = f
    end
    local scale = math.min(2.6, math.max(0.8, tonumber(DB().guideScale) or 1))
    win:SetScale(scale)
    win.title:SetText("Nodes: " .. want)
    local head = ""
    if names and #names > 0 then
        head = "Matches: " .. table.concat(names, ", ", 1, math.min(5, #names)) .. (#names > 5 and ", ..." or "")
    end
    if note then head = (head ~= "" and (head .. "\n") or "") .. note end
    win.head:SetText(head)

    for _, r in ipairs(rows) do r.text:Hide(); r.btn:Hide() end
    local y, i = 0, 0
    local function Row(text, btnText, onClick)
        i = i + 1
        local r = rows[i]
        if not r then
            r = {}
            r.text = win.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.text:SetJustifyH("LEFT")
            r.btn = CreateFrame("Button", nil, win.content, "UIPanelButtonTemplate")
            r.btn:SetSize(120, 22)
            rows[i] = r
        end
        r.text:ClearAllPoints(); r.text:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -y - 4)
        r.text:SetWidth(onClick and 300 or 430)
        r.text:SetText(text); r.text:Show()
        if onClick then
            r.btn:ClearAllPoints(); r.btn:SetPoint("TOPLEFT", win.content, "TOPLEFT", 310, -y)
            r.btn:SetText(btnText or "Take me there")
            r.btn:SetScript("OnClick", function() win:Hide(); pcall(onClick) end)
            r.btn:Show()
        end
        y = y + math.max(30, r.text:GetStringHeight() + 12)
    end

    local anyMine = false
    for z, c in pairs(mine) do
        anyMine = true
        Row(string.format("|cff55ff55You found %d in %s|r", c, z))
    end
    if list then
        if #list == 0 then
            Row("Questie has no node named like '" .. want .. "'.")
        else
            if anyMine then y = y + 6 end
            for k = 1, math.min(12, #list) do
                local z = list[k]
                Row(string.format("%s: %d spot%s", z.zone, z.n, z.n == 1 and "" or "s"), "Take me there", function()
                    if z.map and z.zx and addon.GoTo then addon.GoTo(z.map, z.zx, z.zy, z.zone)
                    elseif z.map and z.zx and addon.AddWaypointZone then addon:AddWaypointZone(z.map, z.zx, z.zy, "Node: " .. want) end
                end)
            end
            Row("Once you are there, /lazy ore " .. want .. " (or /lazy herb " .. want .. ") makes a route through the spots.")
        end
    elseif not anyMine then
        Row("Looking... one moment.")
    end
    win.content:SetHeight(math.max(y, 40))
    win:Show()
end

local function Find(want)
    local mine = {}
    for _, n in ipairs(Nodes()) do
        if (n.name or ""):lower():find(want, 1, true) then
            local z = ZoneOf(n)
            mine[z] = (mine[z] or 0) + 1
        end
    end
    ShowResults(want, mine, nil, nil, nil)       -- show it now, fill it in when the list is read
    if addon.NodeZones then
        addon.NodeZones(want, function(list, names)
            ShowResults(want, mine, list, names, nil)
        end)
    end
end

local function Summary()
    local list = Nodes()
    if #list == 0 then
        Print(L("no nodes saved yet. Mine or pick something and I will mark it (nodes: ") .. ((DB().nodePins == false) and "pins off" or "pins on") .. ")")
        return
    end
    local byName, order = {}, {}
    for _, n in ipairs(list) do
        local e = byName[n.name]
        if not e then e = { name = n.name, c = 0, k = n.k }; byName[n.name] = e; order[#order + 1] = e end
        e.c = e.c + 1
    end
    table.sort(order, function(a, b) return a.c > b.c end)
    Print(string.format(L("%d saved node%s:"), #list, #list == 1 and "" or "s"))
    for i = 1, math.min(8, #order) do Print(string.format(L("  %s: %d spot%s"), order[i].name, order[i].c, order[i].c == 1 and "" or "s")) end
    if #order > 8 then Print(string.format(L("  ...and %d other kinds"), #order - 8)) end
    Print(L("/lazy nodes farm points the arrow at the nearest; /lazy nodes pins on|off; /lazy nodes clear"))
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    if word == "nodes" or word == "node" then
        local arg = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        local sub, more = arg:match("^(%S+)%s*(.-)$")
        if not sub then
            Summary()
        elseif sub == "farm" then
            local f = more
            if f == "" or f == "all" then f = "all"
            elseif f == "mining" or f == "mine" or f == "ore" or f == "ores" then f = "ore"
            elseif f == "herb" or f == "herbs" or f == "herbalism" then f = "herb" end
            db.nodeFilter = f
            db.arrowSource = "nodes"
            if addon.RefreshOptions then addon.RefreshOptions() end
            RefreshPins()
            local t = addon.NearestNode()
            if t then
                Print(string.format(L("the arrow walks me to saved nodes (%s). First: %s"), f, t.name))
            else
                Print(L("the arrow is set to saved nodes (") .. f .. L("), but I have none to point at here yet. Go find some!"))
            end
        elseif sub == "debug" then
            local tr = TrackingNow()
            Print(string.format(L("tracking seen: ore=%s herb=%s; fade-when-tracked=%s; saved nodes=%d"),
                tostring(tr.ore or false), tostring(tr.herb or false), tostring(db.nodeFadeTracked ~= false), #Nodes()))
            if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
                for i = 1, C_Minimap.GetNumTrackingTypes() do
                    local ok, a, b, c = pcall(C_Minimap.GetTrackingInfo, i)
                    if type(a) == "table" then Print(string.format(L("  %d: %s active=%s"), i, tostring(a.name), tostring(a.active)))
                    else Print(string.format(L("  %d: %s active=%s"), i, tostring(a), tostring(c))) end
                end
            else
                Print(L("  this client has no C_Minimap tracking list I can read"))
            end
            Print(L("  Find Minerals is '") .. tostring(SpellNameOf(2580)) .. L("', Find Herbs is '") .. tostring(SpellNameOf(2383)) .. "'")
        elseif sub == "pins" then
            db.nodePins = not (more == "off" or more == "no")
            RefreshPins()
            Print(L("node pins on the map: ") .. (db.nodePins == false and "off" or "on"))
        elseif sub == "clear" then
            if more == "yes" then
                db.nodes = {}
                cache = nil
                RefreshPins()
                Print(L("forgot all saved nodes"))
            else
                Print(string.format(L("this forgets all %d saved nodes. Type /lazy nodes clear yes to do it."), #Nodes()))
            end
        else
            -- anything else is a name to look for: /lazy nodes silver
            local want = arg:gsub("^find%s+", "")
            Find(want)
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Nodes.lua"] = true end end
