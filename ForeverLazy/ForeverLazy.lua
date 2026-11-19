-- Forever Lazy
-- Listens for a party member's RestedXP "active step" broadcast (addon channel RXPGComms)
-- and points arrows at the quest / kill / collect / NPC location (via the Questie database)
-- and at the party member who sent the step.  RestedXP does NOT need to be installed on this client.

local ADDON, ns = ...
local PREFIX = "RXPGComms"
-- item and bag functions: newer clients moved them into C_Item / C_Container, so bring the old names back when they are missing
if C_Item then
    if not GetItemInfo and C_Item.GetItemInfo then GetItemInfo = C_Item.GetItemInfo end
    if not GetItemCount and C_Item.GetItemCount then GetItemCount = C_Item.GetItemCount end
    if not GetItemIcon and C_Item.GetItemIconByID then GetItemIcon = C_Item.GetItemIconByID end
    if not IsEquippableItem and C_Item.IsEquippableItem then IsEquippableItem = C_Item.IsEquippableItem end
    if not IsUsableItem and C_Item.IsUsableItem then IsUsableItem = C_Item.IsUsableItem end
end
if C_Container then
    if not GetItemCooldown and C_Container.GetItemCooldown then
        -- some versions return start, duration, enabled, others one table: hand back the first form either way
        GetItemCooldown = function(id)
            local a, b, c = C_Container.GetItemCooldown(id)
            if type(a) == "table" then return a.startTime or a.start or 0, a.duration or 0, a.isEnabled end
            return a, b, c
        end
    end
    if not GetContainerNumSlots and C_Container.GetContainerNumSlots then GetContainerNumSlots = C_Container.GetContainerNumSlots end
    if not GetContainerNumFreeSlots and C_Container.GetContainerNumFreeSlots then GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots end
end
if not GetCoinTextureString and C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString end
local MEDIA = "Interface\\AddOns\\ForeverLazy\\media\\"

local LibStub = _G.LibStub
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")
local hbd = LibStub("HereBeDragons-2.0")
local hbdp = LibStub("HereBeDragons-Pins-2.0", true)

local addon = {}
ns.addon = addon
LibStub("AceComm-3.0"):Embed(addon)
AceSerializer:Embed(addon)

-- Binding labels
_G.BINDING_HEADER_FOREVERLAZY = "Forever Lazy"
_G.BINDING_NAME_FOREVERLAZY_CYCLE = "Cycle arrow mode"
_G.BINDING_NAME_FOREVERLAZY_OPTIONS = "Open options"
_G.BINDING_NAME_FOREVERLAZY_PANEL = "Show / hide step panel"

local DEFAULTS = {
    mode = "both",            -- both | quest | friend | off
    scale = 1,
    alpha = 1,
    locked = false,
    style = "minimap",        -- minimap | chevron | thick
    colorQuest = { 1, 0.85, 0.2 },
    colorFriend = { 0.3, 1, 0.3 },
    colorWaypoint = { 0.3, 0.7, 1 },
    waypointAutoClear = true,
    colorMine = { 1, 0.5, 0.9 },
    ownQuests = false,        -- arrow for my own quest log
    animate = true,
    compassBar = true,
    showHistory = true,
    stuckAlert = true,
    acceptShared = true,
    routes = {},
    waypoints = {},           -- list of {name, instance, x, y, uiMapId, zx, zy}; first one is active
    showText = true,
    showDistance = true,
    units = "yd",             -- yd | m
    arrival = 8,
    extraTargets = 0,         -- 0..2 additional quest arrows
    hideCombat = false,
    hideResting = false,
    hideTaxi = true,
    compassIcon = 3,          -- marker for my partner on the compass: 1 star, 2 circle, 3 diamond, 4 triangle, 5 moon
    simpleArrows = true,      -- one main arrow; everything else shows on the compass
    showPanel = false,        -- only useful with a RestedXP friend
    rxpListen = false,        -- RestedXP is optional: off until switched on in the options
    panelScale = 1,
    alertChat = true,
    alertSound = false,
    arrivalSound = true,
    followLastSeen = true,
    mapPins = true,
    minimapPins = true,
    tomtom = false,
    minimapButton = true,
    minimapAngle = 200,
    pos = {
        quest  = { point = "TOP", x = -90, y = -120 },
        friend = { point = "TOP", x = 90,  y = -120 },
        panel  = { point = "TOPRIGHT", x = -20, y = -200 },
        waypoint = { point = "TOP", x = 0, y = -260 },
        mine = { point = "TOP", x = -190, y = -260 },
        compass = { point = "TOP", x = 0, y = -30 },
    },
}
addon.DEFAULTS = DEFAULTS

local function Print(msg) print("|cff33ccffForeverLazy:|r " .. tostring(msg)) end
addon.Print = Print

-- each module can be switched off in the options: db.modules[key] == false means off
function addon.ModuleOn(key)
    local d = addon.GetDB and addon.GetDB()
    return not (d and d.modules and d.modules[key] == false)
end

local function Strip(s)
    if not s then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cRXP_%u+_", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", ""):gsub("{rt%d}", ""):gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function ShortName(name)
    return name and (name:match("^([^%-]+)") or name)
end

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = DeepCopy(v) end
    return o
end

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

--------------------------------------------------------------------------------
-- Saved variables / profiles
--------------------------------------------------------------------------------
local db  -- active profile

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function addon:SelectProfile()
    local root = _G.ForeverLazyDB
    root.profiles = root.profiles or {}
    if root.useChar then
        local key = CharKey()
        if not root.chars[key] then root.chars[key] = DeepCopy(root.global) end
        db = root.chars[key]
    elseif root.active and root.profiles[root.active] then
        db = root.profiles[root.active]
    else
        db = root.global
    end
    CopyDefaults(db, DEFAULTS)
end

function addon.GetDB() return db end
function addon.GetRoot() return _G.ForeverLazyDB end

local function InitSavedVars()
    local root = _G.ForeverLazyDB
    -- settings saved under the old name are carried over once
    if type(root) ~= "table" and type(_G.LRXPTDB) == "table" then root = _G.LRXPTDB end
    if type(root) ~= "table" then root = {} end
    -- migrate old flat table
    if root.mode and not root.global then
        root = { global = root, chars = {}, useChar = false }
    end
    root.global = root.global or {}
    root.chars = root.chars or {}
    _G.ForeverLazyDB = root
    CopyDefaults(root.global, DEFAULTS)
    addon:SelectProfile()
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local state = {
    friend = nil,
    stepText = nil,
    stepLines = {},
    rawLines = {},
    groups = {},
    chosen = {},
    sig = "",
    pending = false,
    lastKnown = nil,    -- friend last seen position
    friends = {},       -- name -> {text, t}
    history = {},       -- earlier step first lines
    pinned = nil,       -- friend the user chose to follow
    rawCount = 0,       -- any RXPGComms messages seen
    msgCount = 0,       -- valid STEP messages seen
    index = { progress = 0 },
}
addon.state = state
function addon.GetState() return state end

--------------------------------------------------------------------------------
-- Questie database + name indexes
--------------------------------------------------------------------------------
local QuestieDB, ZoneDB
local qIndex, nIndex, iIndex = {}, {}, {}
local indexBuilding, indexReady = false, false

local function GetQuestie()
    if QuestieDB and ZoneDB then return true end
    local loader = _G.QuestieLoader
    if not loader then return false end
    local ok1, d = pcall(loader.ImportModule, loader, "QuestieDB")
    local ok2, z = pcall(loader.ImportModule, loader, "ZoneDB")
    if ok1 and ok2 and d and z then QuestieDB, ZoneDB = d, z; return true end
    return false
end

local function QuestieReady()
    return GetQuestie() and QuestieDB.QuestPointers and QuestieDB.NPCPointers and QuestieDB.ItemPointers
        and QuestieDB.QueryQuestSingle and QuestieDB.QueryNPCSingle
        and QuestieDB.QueryObjectSingle and QuestieDB.QueryItemSingle
end

local jobs, jobIdx
local indexFrame = CreateFrame("Frame")

local function IndexStep()
    local t0 = debugprofilestop()
    while jobIdx <= #jobs and debugprofilestop() - t0 < 4 do
        local job = jobs[jobIdx]
        local ids, pos = job.ids, job.pos
        local query, index = job.query, job.index
        while pos <= #ids and debugprofilestop() - t0 < 4 do
            local id = ids[pos]
            local name = query(id, "name")
            if type(name) == "string" and name ~= "" then
                local t = index[name]
                if not t then t = {}; index[name] = t end
                t[#t + 1] = id
            end
            pos = pos + 1
        end
        job.pos = pos
        if pos > #ids then jobIdx = jobIdx + 1 end
    end
    local done, total = 0, 0
    for _, j in ipairs(jobs) do done = done + math.min(j.pos - 1, #j.ids); total = total + #j.ids end
    state.index.progress = total > 0 and done / total or 1
    if jobIdx > #jobs then
        indexFrame:SetScript("OnUpdate", nil)
        indexBuilding, indexReady = false, true
        state.index.progress = 1
        if state.pending then
            state.pending = false
            addon:ResolveTargets()
        end
    end
end

local function BuildIndex()
    if indexReady or indexBuilding or not QuestieReady() then return end
    indexBuilding = true
    local function keys(t) local o = {}; for id in pairs(t) do o[#o + 1] = id end; return o end
    jobs = {
        { ids = keys(QuestieDB.QuestPointers), pos = 1, query = QuestieDB.QueryQuestSingle, index = qIndex },
        { ids = keys(QuestieDB.NPCPointers),   pos = 1, query = QuestieDB.QueryNPCSingle,   index = nIndex },
        { ids = keys(QuestieDB.ItemPointers),  pos = 1, query = QuestieDB.QueryItemSingle,  index = iIndex },
    }
    jobIdx = 1
    indexFrame:SetScript("OnUpdate", IndexStep)
end

local MAX_SPAWNS = 500

local function AddSpawns(list, spawns)
    if type(spawns) ~= "table" then return end
    for areaId, coords in pairs(spawns) do
        if #list >= MAX_SPAWNS then return end
        local uiMapId = ZoneDB:GetUiMapIdByAreaId(areaId)
        if uiMapId and type(coords) == "table" then
            for _, c in ipairs(coords) do
                local x, y = c[1], c[2]
                if x and y and x >= 0 and y >= 0 and #list < MAX_SPAWNS then
                    local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(x / 100, y / 100, uiMapId)
                    if wx then
                        list[#list + 1] = { instance = inst, x = wx, y = wy, uiMapId = uiMapId, zx = x / 100, zy = y / 100 }
                    end
                end
            end
        end
    end
end

local function AddNpcs(list, ids)
    if type(ids) ~= "table" then return end
    for _, id in pairs(ids) do AddSpawns(list, QuestieDB.QueryNPCSingle(id, "spawns")) end
end

local function AddObjects(list, ids)
    if type(ids) ~= "table" then return end
    for _, id in pairs(ids) do AddSpawns(list, QuestieDB.QueryObjectSingle(id, "spawns")) end
end

local function AddQuestLocations(list, questId, kind)
    local by
    if kind == "accept" then by = QuestieDB.QueryQuestSingle(questId, "startedBy")
    else by = QuestieDB.QueryQuestSingle(questId, "finishedBy") end
    if by then AddNpcs(list, by[1]); AddObjects(list, by[2]) end
end

local function AddItemSources(list, itemId)
    local npcs = QuestieDB.QueryItemSingle(itemId, "npcDrops")
    if type(npcs) == "table" then
        local n = 0
        for _, id in pairs(npcs) do
            n = n + 1
            if n > 40 then break end
            AddSpawns(list, QuestieDB.QueryNPCSingle(id, "spawns"))
        end
    end
    AddObjects(list, QuestieDB.QueryItemSingle(itemId, "objectDrops"))
end

local function Variants(name)
    local out, seen = {}, {}
    local function add(s)
        if s and s ~= "" and not seen[s] then seen[s] = true; out[#out + 1] = s end
    end
    add(name)
    local n = name:gsub("^%d+%s*[xX]?%s*", ""):gsub("[%.,!]+$", "")
    add(n)
    add((n:gsub("ies$", "y")))
    add((n:gsub("ves$", "f")))
    add((n:gsub("es$", "")))
    add((n:gsub("s$", "")))
    return out
end

local function Lookup(index, name)
    for _, v in ipairs(Variants(name)) do
        if index[v] then return index[v], v end
    end
end

local QUEST_KINDS = {
    { "^[Aa]ccept%s+(.+)$", "accept", "Accept: " },
    { "^[Tt]urn in%s+(.+)$", "turnin", "Turn in: " },
    { "^[Hh]and in%s+(.+)$", "turnin", "Turn in: " },
}

local function NewGroup(label)
    local g = { label = label, spawns = {} }
    state.groups[#state.groups + 1] = g
    return g
end

local function GroupDone(g)
    if #g.spawns == 0 then state.groups[#state.groups] = nil end
end

function addon:ResolveTargets()
    state.groups = {}
    state.chosen = {}
    state.sig = ""
    if not QuestieReady() then return end
    if not indexReady then
        state.pending = true
        BuildIndex()
        return
    end

    for i, raw in ipairs(state.rawLines) do
        local line = state.stepLines[i]
        local matched = false

        for _, k in ipairs(QUEST_KINDS) do
            local qname = line:match(k[1])
            if qname then
                local ids = Lookup(qIndex, qname)
                if ids then
                    local g = NewGroup(k[3] .. qname)
                    for _, id in ipairs(ids) do AddQuestLocations(g.spawns, id, k[2]) end
                    GroupDone(g)
                end
                matched = true
                break
            end
        end

        if not matched then
            local sawTag = false
            for tag, name in raw:gmatch("|cRXP_(%u+)_(.-)|r") do
                if tag == "ENEMY" or tag == "FRIENDLY" then
                    sawTag = true
                    local ids = Lookup(nIndex, name)
                    if ids then
                        local g = NewGroup((tag == "ENEMY" and "Kill: " or "Talk to: ") .. name)
                        for _, id in ipairs(ids) do AddSpawns(g.spawns, QuestieDB.QueryNPCSingle(id, "spawns")) end
                        GroupDone(g)
                    end
                elseif tag == "LOOT" then
                    sawTag = true
                    local ids = Lookup(iIndex, name)
                    if ids then
                        local g = NewGroup("Collect: " .. name)
                        for _, id in ipairs(ids) do AddItemSources(g.spawns, id) end
                        GroupDone(g)
                    end
                end
            end
            if not sawTag then
                local mob = line:match("^[Kk]ill%s+(.+)$")
                local item = line:match("^[Cc]ollect%s+(.+)$") or line:match("^[Ll]oot%s+(.+)$")
                if mob then
                    local ids = Lookup(nIndex, mob)
                    if ids then
                        local g = NewGroup("Kill: " .. mob)
                        for _, id in ipairs(ids) do AddSpawns(g.spawns, QuestieDB.QueryNPCSingle(id, "spawns")) end
                        GroupDone(g)
                    end
                elseif item then
                    local ids = Lookup(iIndex, item)
                    if ids then
                        local g = NewGroup("Collect: " .. item)
                        for _, id in ipairs(ids) do AddItemSources(g.spawns, id) end
                        GroupDone(g)
                    end
                end
            end
        end
    end
    self:Recompute()
end

--------------------------------------------------------------------------------
-- Choosing the nearest targets, map pins, TomTom
--------------------------------------------------------------------------------
local function D2(a, b, c, d) local dx, dy = a - c, b - d; return dx * dx + dy * dy end

function addon:Recompute()
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local list = {}
    for _, g in ipairs(state.groups) do
        local best, bd
        for _, s in ipairs(g.spawns) do
            local d = (px and s.instance == pinst) and D2(s.x, s.y, px, py) or 1e18
            if not bd or d < bd then best, bd = s, d end
        end
        if best then list[#list + 1] = { label = g.label, spawn = best, d = bd } end
    end
    table.sort(list, function(a, b) return a.d < b.d end)

    local kept = {}
    for _, e in ipairs(list) do
        local dup = false
        for _, k in ipairs(kept) do
            if k.spawn.instance == e.spawn.instance and D2(k.spawn.x, k.spawn.y, e.spawn.x, e.spawn.y) < 225 then
                dup = true; break
            end
        end
        if not dup then kept[#kept + 1] = e end
        if #kept >= 3 then break end
    end
    state.chosen = kept

    local parts = {}
    for _, k in ipairs(kept) do parts[#parts + 1] = k.label .. ":" .. math.floor(k.spawn.x) .. ":" .. math.floor(k.spawn.y) end
    local sig = table.concat(parts, "|")
    if sig ~= state.sig then
        state.sig = sig
        self:RefreshPins()
        self:UpdateTomTom()
    end
end

local pinFrames = {}
local function GetPinFrames(i)
    if pinFrames[i] then return pinFrames[i] end
    local function make(size)
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(size, size)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        t:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        f.tex = t
        f:Hide()
        return f
    end
    pinFrames[i] = { world = make(18), mini = make(14) }
    return pinFrames[i]
end

function addon:RefreshPins()
    if not hbdp or not db then return end
    pcall(hbdp.RemoveAllWorldMapIcons, hbdp, addon)
    pcall(hbdp.RemoveAllMinimapIcons, hbdp, addon)

    -- own waypoint pin (shown regardless of arrow mode)
    local wp = db.waypoints[1]
    if wp then
        local f = GetPinFrames(10)
        f.world.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
        f.mini.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
        if db.mapPins then
            pcall(hbdp.AddWorldMapIconWorld, hbdp, addon, f.world, wp.instance, wp.x, wp.y, _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2)
        end
        if db.minimapPins then
            pcall(hbdp.AddMinimapIconWorld, hbdp, addon, f.mini, wp.instance, wp.x, wp.y, true)
        end
    end

    -- the rest of my waypoints (e.g. the library books) as small book icons
    for i = 2, math.min(#db.waypoints, 60) do
        local w = db.waypoints[i]
        local f = GetPinFrames(100 + i)
        f.world.tex:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        f.mini.tex:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        if db.mapPins then
            pcall(hbdp.AddWorldMapIconWorld, hbdp, addon, f.world, w.instance, w.x, w.y, _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2)
        end
        if db.minimapPins then
            pcall(hbdp.AddMinimapIconWorld, hbdp, addon, f.mini, w.instance, w.x, w.y, false)
        end
    end

    if db.mode == "off" or db.mode == "friend" then return end
    for i, c in ipairs(state.chosen) do
        local f = GetPinFrames(i)
        local s = c.spawn
        if db.mapPins then
            pcall(hbdp.AddWorldMapIconWorld, hbdp, addon, f.world, s.instance, s.x, s.y, _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2)
        end
        if db.minimapPins then
            pcall(hbdp.AddMinimapIconWorld, hbdp, addon, f.mini, s.instance, s.x, s.y, true)
        end
    end
end

local tomtomUid
function addon:UpdateTomTom()
    local TT = _G.TomTom
    if not TT or not TT.AddWaypoint then return end
    if tomtomUid and TT.RemoveWaypoint then pcall(TT.RemoveWaypoint, TT, tomtomUid) end
    tomtomUid = nil
    if not db.tomtom or db.mode == "off" or db.mode == "friend" then return end
    local c = state.chosen[1]
    if c and c.spawn.uiMapId then
        local ok, uid = pcall(TT.AddWaypoint, TT, c.spawn.uiMapId, c.spawn.zx, c.spawn.zy,
            { title = c.label, persistent = false })
        if ok then tomtomUid = uid end
    end
end

--------------------------------------------------------------------------------
-- Receiving RXP's broadcast
--------------------------------------------------------------------------------
local function DecodeSteps(payload)
    if type(payload) ~= "string" then return end
    local decoded = LibDeflate:DecodeForWoWChatChannel(payload)
    if not decoded then return end
    local raw = LibDeflate:DecompressDeflate(decoded)
    if not raw then return end
    local ok, steps = addon:Deserialize(raw)
    if ok and type(steps) == "table" then return steps end
end

local function PlayAlert(id)
    pcall(PlaySound, id)
end

function addon:SetStepText(sender, text)
    local previous = state.stepText
    if sender and ShortName(sender) ~= state.friend then
        state.history = {}
        state.lastKnown = nil
        previous = nil
    end
    if sender then state.friend = ShortName(sender) end
    if previous and previous ~= "" and text and Strip(text) ~= previous then
        local first = previous:match("^[^\n]+")
        if first then
            table.insert(state.history, 1, first)
            while #state.history > 4 do table.remove(state.history) end
        end
    end
    state.rawLines, state.stepLines = {}, {}
    for line in (text or ""):gmatch("[^\n]+") do
        local stripped = Strip(line)
        if stripped ~= "" then
            state.rawLines[#state.rawLines + 1] = line
            state.stepLines[#state.stepLines + 1] = stripped
        end
    end
    state.stepText = table.concat(state.stepLines, "\n")
    self:ResolveTargets()
    self:UpdatePanel()

    if sender and previous ~= state.stepText and state.stepText ~= "" then
        if db.alertChat then
            Print(string.format("|cffffd100%s|r: %s", state.friend or "Friend", state.stepLines[1] or ""))
        end
        if db.alertSound then
            PlayAlert((_G.SOUNDKIT and _G.SOUNDKIT.TELL_MESSAGE) or 3081)
        end
    end
end

function addon:OnComm(prefix, message, distribution, sender)
    if prefix ~= PREFIX then return end
    if db and db.rxpListen == false then return end       -- RestedXP is optional: switched off in the options
    if ShortName(sender) == ShortName(UnitName("player")) then return end
    state.rawCount = (state.rawCount or 0) + 1
    local ok, obj = self:Deserialize(message)
    if not ok or type(obj) ~= "table" or obj.command ~= "STEP" then return end
    local steps = DecodeSteps(obj.encodedPayload)
    if not steps then return end
    local parts = {}
    for _, step in ipairs(steps) do
        if step.active ~= false and step.text and step.text ~= "" then parts[#parts + 1] = step.text end
    end
    state.lastRaw = steps
    state.msgCount = (state.msgCount or 0) + 1
    state.lastMsg = GetTime()
    local who = ShortName(sender)
    local text = table.concat(parts, "\n")
    state.friends[who] = { text = text, t = GetTime() }
    if state.pinned and state.pinned ~= who then return end
    self:SetStepText(sender, text)
end

addon:RegisterComm(PREFIX, "OnComm")

function addon:SelectFriend(name, pin)
    local f = name and state.friends[name]
    if not f then Print("no step received from " .. tostring(name)); return end
    state.pinned = pin and name or nil
    self:SetStepText(name, f.text)
end

function addon:CycleFriend()
    local names = {}
    for n in pairs(state.friends) do names[#names + 1] = n end
    table.sort(names)
    if #names < 2 then Print("only one friend has sent a step so far"); return end
    local nextName = names[1]
    for i, n in ipairs(names) do
        if n == state.friend then nextName = names[i % #names + 1]; break end
    end
    self:SelectFriend(nextName, true)
    Print("following " .. nextName)
end

function addon:PingFriend()
    if IsInGroup() then SendChatMessage("On my way!", "PARTY") end
end

--------------------------------------------------------------------------------
-- Arrow frames
--------------------------------------------------------------------------------
local arrows = {}       -- quest1..quest3 as arrows.quest[1..3], arrows.friend
local questArrows = {}

local function StyleTexture()
    if db.style == "chevron" then return MEDIA .. "arrow_chevron" end
    if db.style == "thick" then return MEDIA .. "arrow_thick" end
    return "Interface\\Minimap\\ROTATING-MINIMAPARROW"
end

local function MakeArrow(name, size, movableKey)
    local f = CreateFrame("Frame", "ForeverLazy_" .. name, UIParent)
    f:SetSize(size, size)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    if movableKey then
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            db.pos[movableKey] = { point = point, x = x, y = y }
        end)
    end
    if movableKey == "friend" then
        f:SetScript("OnMouseUp", function(_, b)
            if b == "LeftButton" and IsShiftKeyDown() then addon:PingFriend() end
        end)
    end
    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetAllPoints()
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.title:SetWidth(200)
    f.title:SetShadowOffset(1, -1)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -2)
    f.sub:SetWidth(200)
    f.sub:SetShadowOffset(1, -1)
    return f
end

function addon:ApplyStyle()
    if not db or not arrows.friend then return end
    local tex = StyleTexture()
    for i, f in ipairs(questArrows) do
        f.arrow:SetTexture(tex)
        f.arrow:SetVertexColor(unpack(db.colorQuest))
        f:SetAlpha(db.alpha)
    end
    arrows.friend.arrow:SetTexture(tex)
    arrows.friend.arrow:SetVertexColor(unpack(db.colorFriend))
    arrows.friend:SetAlpha(db.alpha)
    arrows.waypoint.arrow:SetTexture(tex)
    arrows.waypoint.arrow:SetVertexColor(unpack(db.colorWaypoint))
    arrows.waypoint:SetAlpha(db.alpha)
end

function addon:ApplyLayout()
    if not db or not arrows.friend then return end
    local q, fr = db.pos.quest, db.pos.friend
    questArrows[1]:ClearAllPoints()
    questArrows[1]:SetPoint(q.point, UIParent, q.point, q.x, q.y)
    questArrows[1]:SetScale(db.scale)
    for i = 2, 3 do
        questArrows[i]:ClearAllPoints()
        questArrows[i]:SetPoint("RIGHT", questArrows[i - 1], "LEFT", -(i == 2 and 70 or 55), 0)
        questArrows[i]:SetScale(db.scale)
    end
    arrows.friend:ClearAllPoints()
    arrows.friend:SetPoint(fr.point, UIParent, fr.point, fr.x, fr.y)
    arrows.friend:SetScale(db.scale)
    local w = db.pos.waypoint
    arrows.waypoint:ClearAllPoints()
    arrows.waypoint:SetPoint(w.point, UIParent, w.point, w.x, w.y)
    arrows.waypoint:SetScale(db.scale)
    if addon.panel then
        local p = db.pos.panel
        addon.panel:ClearAllPoints()
        addon.panel:SetPoint(p.point, UIParent, p.point, p.x, p.y)
        addon.panel:SetScale(db.panelScale)
    end
end

local function FindUnit(shortName)
    if not shortName then return end
    if UnitName("player") == shortName then return "player" end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and UnitName(u) == shortName then return u end
    end
    for i = 1, 40 do
        local u = "raid" .. i
        if UnitExists(u) and UnitName(u) == shortName then return u end
    end
end

local function FormatDist(d)
    if db.units == "steps" then return string.format("~%d steps", d / 0.8) end
    if db.units == "m" then d = d * 0.9144 end
    return string.format("%d %s", d, db.units)
end

-- returns distance or nil
local function PointAt(f, instance, tx, ty, title, subPrefix)
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px or pinst ~= instance then
        f.arrow:Hide()
        f.title:SetText(db.showText and title or "")
        f.sub:SetText((subPrefix or "") .. "|cffaaaaaaDifferent zone or area|r")
        return nil
    end
    local angle, dist = hbd:GetWorldVector(instance, px, py, tx, ty)
    local facing = GetPlayerFacing()
    f.arrow:Show()
    if angle and facing then f.arrow:SetRotation(angle - facing) end
    if db.animate and angle and facing then
        local rel = (angle - facing + math.pi) % (2 * math.pi) - math.pi
        local a = 1
        if dist and dist < db.arrival * 3 then a = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(GetTime() * 7)) end
        if math.abs(rel) > 0.2 then a = a * 0.75 end
        f.arrow:SetAlpha(a)
    else
        f.arrow:SetAlpha(1)
    end
    f.title:SetText(db.showText and (title or "") or "")
    if dist and dist < db.arrival then
        f.sub:SetText((subPrefix or "") .. "|cff55ff55You are here|r")
    elseif db.showDistance then
        f.sub:SetText((subPrefix or "") .. FormatDist(dist or 0))
    else
        f.sub:SetText(subPrefix or "")
    end
    return dist
end

local arrivedKey
local function UpdateQuestArrows(show)
    local mainShown = show and (db.mode == "quest" or db.mode == "both") and state.stepText
    if not mainShown then
        for _, f in ipairs(questArrows) do f:Hide() end
        return
    end
    local f1 = questArrows[1]
    f1:Show()
    if not QuestieReady() then
        f1.arrow:Hide(); f1.title:SetText("Quest arrow needs Questie"); f1.sub:SetText("")
        for i = 2, 3 do questArrows[i]:Hide() end
        return
    end
    if state.pending or not indexReady then
        f1.arrow:Hide()
        f1.title:SetText(string.format("Loading quest database... %d%%", (state.index.progress or 0) * 100))
        f1.sub:SetText("")
        for i = 2, 3 do questArrows[i]:Hide() end
        return
    end
    local chosen = state.chosen
    if #chosen == 0 then
        f1.arrow:Hide()
        f1.title:SetText("No map spot for this step")
        f1.sub:SetText("|cffaaaaaa" .. (state.stepLines[1] or "") .. "|r")
        for i = 2, 3 do questArrows[i]:Hide() end
        return
    end
    for i = 1, 3 do
        local f, c = questArrows[i], chosen[i]
        if c and (i == 1 or i <= 1 + db.extraTargets) then
            f:Show()
            local dist = PointAt(f, c.spawn.instance, c.spawn.x, c.spawn.y, c.label)
            if i == 1 and dist then
                local key = c.label .. math.floor(c.spawn.x) .. math.floor(c.spawn.y)
                if dist < db.arrival then
                    if arrivedKey ~= key then
                        arrivedKey = key
                        if db.arrivalSound then PlayAlert((_G.SOUNDKIT and _G.SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) or 878) end
                    end
                elseif dist > db.arrival * 2 and arrivedKey == key then
                    arrivedKey = nil
                end
            end
        elseif i > 1 then
            f:Hide()
        end
    end
end

local function UpdateFriendArrow(show)
    local f = arrows.friend
    local name = state.friend
    if not show or not name or not (db.mode == "friend" or db.mode == "both") then f:Hide(); return end
    f:Show()
    f:SetAlpha(db.alpha)
    local unit = FindUnit(name)
    if not unit or unit == "player" then
        f.arrow:Hide(); f.title:SetText(name); f.sub:SetText("|cffaaaaaaNot in your party|r")
        return
    end
    local ux, uy, uinst = hbd:GetUnitWorldPosition(unit)
    if ux then
        state.lastKnown = { x = ux, y = uy, instance = uinst, t = GetTime() }
        local s = state.stuck
        if not s or s.instance ~= uinst or D2(s.x, s.y, ux, uy) > 9 then
            state.stuck = { x = ux, y = uy, instance = uinst, t = GetTime() }
        elseif db.stuckAlert and not s.alerted and GetTime() - s.t > 180 then
            s.alerted = true
            Print(name .. " hasn't moved for 3 minutes")
        end
        PointAt(f, uinst, ux, uy, name)
        return
    end
    local lk = state.lastKnown
    if db.followLastSeen and lk and GetTime() - lk.t < 600 then
        f:SetAlpha(db.alpha * 0.55)
        local ago = math.floor(GetTime() - lk.t)
        PointAt(f, lk.instance, lk.x, lk.y, name, string.format("last seen %ds ago - ", ago))
        return
    end
    f.arrow:Hide(); f.title:SetText(name); f.sub:SetText("|cffaaaaaaToo far away to track|r")
end

local wpArrived
local function UpdateWaypointArrow(show)
    local f = arrows.waypoint
    local wp = (addon.ArrowTarget and addon.ArrowTarget()) or db.waypoints[1] or (db.simpleArrows ~= false and addon.SimpleTarget and addon.SimpleTarget()) or nil
    if not show or not wp or db.waypointArrowOff then f:Hide(); return end
    f:Show()
    f:SetAlpha(db.alpha)
    -- a gold "?" over the arrow when this stop is a quest turn-in
    if not f.marker then
        f.marker = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.marker:SetPoint("BOTTOM", f, "TOP", 0, 2)
        f.marker:SetTextColor(1, 0.82, 0)
        f.marker:SetShadowOffset(1, -1)
        f.marker:SetText("?")
    end
    local mark
    if wp.label and wp.label:find("Turn in:", 1, true) then mark = "?"
    elseif wp.label and (wp.label:find("Pick up:", 1, true) or wp.label:find("Class quest:", 1, true)) then mark = "!" end
    f.marker:SetText(mark or "?")
    f.marker:SetShown(mark ~= nil)
    -- the line under the arrow says what to do at this stop (kill / collect / turn in / how to get there)
    local detail = wp.detail
    if addon.WaypointDetail then
        local ok, d = pcall(addon.WaypointDetail, wp)
        if ok and d then detail = d end
    end
    local dist = PointAt(f, wp.instance, wp.x, wp.y, wp.name, detail and ("|cffffffff" .. detail .. "|r\n") or nil)
    if dist and dist < db.arrival and wpArrived ~= wp then
        wpArrived = wp
        if db.arrivalSound then PlayAlert((_G.SOUNDKIT and _G.SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) or 878) end
        -- a stop for a quest I have not finished (kills, items) stays until the objectives are done; getting there is not enough
        local open = addon.StopHasOpenObjectives and addon.StopHasOpenObjectives(wp)
        if addon.PlanLog and wp.quests then addon.PlanLog("arrival", (open and "arrived but kept the stop (its quest step is not done): " or "arrived, stop is done: ") .. tostring(wp.name or wp.label)) end
        if db.waypointAutoClear and not open then
            C_Timer.After(1.5, function()
                if db.waypoints[1] == wp and not (addon.StopHasOpenObjectives and addon.StopHasOpenObjectives(wp)) then
                    addon:RemoveWaypoint(1)
                    Print("arrived at " .. wp.name)
                end
            end)
        end
    end
end

local function ShouldHide()
    -- as a ghost only the corpse arrow shows
    if db.ghostArrow ~= false and UnitIsGhost and UnitIsGhost("player") then return true end
    -- inside a dungeon or raid the arrows only get in the way (the corpse arrow still shows)
    if db.hideInstance ~= false and IsInInstance then
        local inside, kind = IsInInstance()
        if inside and (kind == "party" or kind == "raid") then return true end
    end
    if db.hideCombat and UnitAffectingCombat("player") then return true end
    if db.hideResting and IsResting() then return true end
    if db.hideTaxi and UnitOnTaxi("player") then return true end
    return false
end

local elapsed, recompute = 0, 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    if not db or not arrows.friend then return end
    elapsed, recompute = elapsed + dt, recompute + dt
    if elapsed < 0.05 then return end
    elapsed = 0
    if recompute > 0.5 then
        recompute = 0
        if #state.groups > 0 then addon:Recompute() end
    end
    local show = db.mode ~= "off" and not ShouldHide() and db.rxpListen ~= false
    local simple = db.simpleArrows ~= false      -- simple arrows: only the one main arrow (plus ghost and follow)
    UpdateQuestArrows(show and not simple)
    UpdateFriendArrow(show and not simple)
    UpdateWaypointArrow(not ShouldHide())
    if addon.panel then
        addon.panel:SetShown(db.showPanel and state.stepText ~= nil and not ShouldHide() and db.rxpListen ~= false)
    end
end)

--------------------------------------------------------------------------------
-- Step panel
--------------------------------------------------------------------------------
local function MakePanel()
    local f = CreateFrame("Frame", "ForeverLazy_Panel", UIParent)
    f:SetSize(260, 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        db.pos.panel = { point = point, x = x, y = y }
    end)
    f:SetScript("OnMouseUp", function(_, b) if b == "RightButton" then addon:CycleFriend() end end)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.55)
    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.header:SetPoint("TOPLEFT", 8, -6)
    f.header:SetPoint("TOPRIGHT", -8, -6)
    f.header:SetJustifyH("LEFT")
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -4)
    f.body:SetWidth(244)
    f.body:SetJustifyH("LEFT")
    f.body:SetSpacing(2)
    f:Hide()
    return f
end

function addon:UpdatePanel()
    local p = addon.panel
    if not p then return end
    p.header:SetText((state.friend or "Friend") .. "'s step")
    local body = state.stepText or ""
    if db.showHistory and #state.history > 0 then
        body = body .. "\n\n|cff888888Earlier:|r"
        for _, h in ipairs(state.history) do body = body .. "\n|cff888888- " .. h .. "|r" end
    end
    p.body:SetText(body)
    p:SetHeight(24 + p.body:GetStringHeight() + 10)
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------
local mmb
local function PositionMinimapButton()
    if not mmb then return end
    local a = math.rad(db.minimapAngle or 200)
    mmb:ClearAllPoints()
    mmb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

local MODES = { "both", "quest", "friend", "off" }
function addon:CycleMode()
    for i, m in ipairs(MODES) do
        if m == db.mode then db.mode = MODES[i % #MODES + 1]; break end
    end
    Print("mode: " .. db.mode)
    self:RefreshPins()
    self:UpdateTomTom()
    if addon.RefreshOptions then addon.RefreshOptions() end
end

local function MakeMinimapButton()
    mmb = CreateFrame("Button", "ForeverLazy_MinimapButton", Minimap)
    mmb:SetSize(31, 31)
    mmb:SetFrameStrata("MEDIUM")
    mmb:SetFrameLevel(8)
    mmb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mmb:RegisterForDrag("LeftButton")
    local icon = mmb:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(25, 25)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(MEDIA .. "icon")
    local border = mmb:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mmb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    mmb:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if IsShiftKeyDown() or not addon.OpenMenu then addon:CycleMode() else addon:OpenMenu(mmb) end
        else
            addon:OpenOptions()
        end
    end)
    mmb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            db.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            PositionMinimapButton()
        end)
    end)
    mmb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Forever Lazy")
        GameTooltip:AddLine("Left-click: Lazy Mode (do the next thing)", 1, 1, 1)
        GameTooltip:AddLine("Right-click: menu    Shift-click: options", 1, 1, 1)
        GameTooltip:AddLine("Drag: move button", 1, 1, 1)
        GameTooltip:Show()
    end)
    mmb:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function addon:UpdateMinimapButton()
    if not mmb then return end
    mmb:SetShown(db.minimapButton)
    PositionMinimapButton()
end

--------------------------------------------------------------------------------
-- Apply everything / keybind functions
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Own waypoints
--------------------------------------------------------------------------------
local function MapName(uiMapId)
    local info = uiMapId and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapId)
    return info and info.name or "Waypoint"
end

function addon:AddWaypointZone(uiMapId, zx, zy, name)
    local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(zx, zy, uiMapId)
    if not wx then Print("can't place a waypoint on that map"); return end
    if not name or name == "" then
        name = string.format("%s %.1f, %.1f", MapName(uiMapId), zx * 100, zy * 100)
    end
    table.insert(db.waypoints, 1, { name = name, instance = inst, x = wx, y = wy, uiMapId = uiMapId, zx = zx, zy = zy })
    wpArrived = nil
    Print("waypoint set: " .. name)
    self:RefreshPins()
end

function addon:DropWaypointHere(name)
    local zx, zy, uiMapId = hbd:GetPlayerZonePosition()
    if not zx then Print("can't read your position here"); return end
    self:AddWaypointZone(uiMapId, zx, zy, name)
end

function addon:RemoveWaypoint(i)
    if db.waypoints[i] then table.remove(db.waypoints, i) end
    wpArrived = nil
    self:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
end

function addon:ClearWaypoints()
    db.waypoints = {}
    wpArrived = nil
    self:RefreshPins()
    Print("all waypoints cleared")
end

function addon:ListWaypoints()
    if #db.waypoints == 0 then
        Print("no waypoints. /lazy way <x> <y> [name], /lazy way here [name], or Ctrl+right-click the world map")
        return
    end
    for i, w in ipairs(db.waypoints) do
        Print(string.format("%d. %s%s", i, w.name, i == 1 and " |cff55ff55(active)|r" or ""))
    end
end

function addon:HandleWayCommand(rest)
    local sub, arg = rest:match("^(%S*)%s*(.*)$")
    sub = (sub or ""):lower()
    if sub == "" or sub == "list" then
        self:ListWaypoints()
    elseif sub == "here" then
        self:DropWaypointHere(arg)
    elseif sub == "clear" then
        self:ClearWaypoints()
    elseif sub == "export" then
        if addon.OpenIO then addon:OpenIO("export") end
    elseif sub == "import" then
        if addon.OpenIO then addon:OpenIO("import") end
    elseif sub == "send" or sub == "share" then
        if addon.ShareWaypoint then addon:ShareWaypoint() end
    elseif sub == "next" or sub == "skip" then
        self:RemoveWaypoint(1)
    elseif sub == "remove" or sub == "delete" then
        local n = tonumber(arg)
        if n and db.waypoints[n] then self:RemoveWaypoint(n) else Print("usage: /lazy way remove <number>") end
    else
        local a, b, name = rest:match("^([%d%.]+)[%s,]+([%d%.]+)%s*(.*)$")
        a, b = tonumber(a), tonumber(b)
        if a and b then
            if a > 1 or b > 1 then a, b = a / 100, b / 100 end
            local uiMapId = hbd:GetPlayerZone()
            if not uiMapId then Print("can't tell which zone you are in"); return end
            self:AddWaypointZone(uiMapId, a, b, name)
        elseif tonumber(sub) and db.waypoints[tonumber(sub)] then
            local w = table.remove(db.waypoints, tonumber(sub))
            table.insert(db.waypoints, 1, w)
            wpArrived = nil
            self:RefreshPins()
            Print("active waypoint: " .. w.name)
        else
            Print("usage: /lazy way <x> <y> [name] | here [name] | list | <number> | next | remove <n> | clear")
        end
    end
end

-- Ctrl + right-click on the world map drops a waypoint
local mapHooked = false
local function HookWorldMap()
    if mapHooked then return end
    local wm = _G.WorldMapFrame
    if not (wm and wm.ScrollContainer and wm.ScrollContainer.HookScript) then return end
    mapHooked = true
    wm.ScrollContainer:HookScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" or not IsControlKeyDown() then return end
        local x, y = self:GetNormalizedCursorPosition()
        local mapId = wm.GetMapID and wm:GetMapID()
        if x and y and mapId and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            addon:AddWaypointZone(mapId, x, y)
        end
    end)
end

function _G.ForeverLazy_DropWaypoint() addon:DropWaypointHere() end
_G.BINDING_NAME_FOREVERLAZY_WAYPOINT = "Drop waypoint at my position"

function addon:ApplyAll()
    self:ApplyStyle()
    self:ApplyLayout()
    self:UpdateMinimapButton()
    self:UpdatePanel()
    self:RefreshPins()
    self:UpdateTomTom()
end

function _G.ForeverLazy_CycleMode() addon:CycleMode() end
function _G.ForeverLazy_ToggleOptions() addon:OpenOptions() end
function _G.ForeverLazy_TogglePanel()
    db.showPanel = not db.showPanel
    Print("step panel " .. (db.showPanel and "shown" or "hidden"))
    if addon.RefreshOptions then addon.RefreshOptions() end
end

--------------------------------------------------------------------------------
-- Setup + slash commands
--------------------------------------------------------------------------------
local init = CreateFrame("Frame")
pcall(init.RegisterEvent, init, "PLAYER_LOGIN")
pcall(init.RegisterEvent, init, "GROUP_ROSTER_UPDATE")
init:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        InitSavedVars()
        questArrows[1] = MakeArrow("QuestArrow", 64, "quest")
        questArrows[2] = MakeArrow("QuestArrow2", 40)
        questArrows[3] = MakeArrow("QuestArrow3", 40)
        arrows.friend = MakeArrow("FriendArrow", 64, "friend")
        arrows.waypoint = MakeArrow("WaypointArrow", 64, "waypoint")
        addon.panel = MakePanel()
        MakeMinimapButton()
        addon:ApplyAll()
        for _, f in ipairs(questArrows) do f:Hide() end
        arrows.friend:Hide()
        arrows.waypoint:Hide()
        HookWorldMap()
        C_Timer.After(3, HookWorldMap)
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        if not (isLoaded and isLoaded("TomTom")) then
            _G.SLASH_FOREVERLAZYWAY1 = "/way"
            SlashCmdList["FOREVERLAZYWAY"] = function(m) addon:HandleWayCommand(m or "") end
        end
        C_Timer.After(5, BuildIndex)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if state.friend and not FindUnit(state.friend) then state.friend = nil end
        if db.followName and not FindUnit(db.followName) then
            Print(db.followName .. " is no longer in your group, the follow arrow is off")
            db.followName = nil
        end
    end
end)

-- internals shared with Extras.lua
ns.api = {
    arrows = arrows, questArrows = questArrows, hbd = hbd,
    PointAt = PointAt, FindUnit = FindUnit, PlayAlert = PlayAlert, ShouldHide = ShouldHide,
    QuestieReady = QuestieReady, D2 = D2, DeepCopy = DeepCopy, MakeArrow = MakeArrow, StyleTexture = StyleTexture,
    AddSpawns = AddSpawns, AddNpcs = AddNpcs, AddObjects = AddObjects, AddItemSources = AddItemSources,
    GetQuestie = function() GetQuestie(); return QuestieDB, ZoneDB end,
    IsMapHooked = function() return mapHooked end,
    IndexReady = function() return indexReady end,
}

SLASH_FOREVERLAZY1 = "/lrxp"
SLASH_FOREVERLAZY2 = "/forever"
SLASH_FOREVERLAZY3 = "/lazy"
SlashCmdList["FOREVERLAZY"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    if cmd == "both" or cmd == "quest" or cmd == "friend" or cmd == "off" then
        db.mode = cmd; Print("mode: " .. cmd); addon:RefreshPins(); addon:UpdateTomTom()
    elseif cmd == "lock" then
        db.locked = true; Print("arrows locked")
    elseif cmd == "unlock" then
        db.locked = false; Print("arrows unlocked - drag them to move")
    elseif cmd == "scale" then
        local s = tonumber(rest)
        if s and s >= 0.3 and s <= 3 then db.scale = s; addon:ApplyLayout(); Print("scale " .. s)
        else Print("usage: /lazy scale 0.5 - 3") end
    elseif cmd == "reset" then
        db.pos = DeepCopy(DEFAULTS.pos); db.scale = 1; addon:ApplyLayout(); Print("positions reset")
    elseif cmd == "way" or cmd == "waypoint" then
        addon:HandleWayCommand(rest)
    elseif cmd == "panel" then
        _G.ForeverLazy_TogglePanel()
    elseif cmd == "minimap" then
        db.minimapButton = not db.minimapButton; addon:UpdateMinimapButton()
    elseif cmd == "test" then
        if rest == "" then Print("usage: /lazy test Accept <quest name>   or   Kill <mob>"); return end
        state.friend = state.friend or UnitName("player")
        addon:SetStepText(nil, rest)
        Print("simulated step: " .. rest)
    elseif cmd == "status" then
        Print(string.format("mode=%s friend=%s questie=%s index=%d%% groups=%d chosen=%d",
            db.mode, tostring(state.friend), tostring(QuestieReady() and true or false),
            (state.index.progress or 0) * 100, #state.groups, #state.chosen))
        if state.stepText then Print("step: " .. state.stepText:gsub("\n", " | ")) end
        for i, c in ipairs(state.chosen) do Print(i .. ": " .. c.label) end
    elseif cmd == "" or cmd == "options" or cmd == "config" then
        addon:OpenOptions()
    elseif addon.HandleExtraCommand and (function()
            local ok, res = pcall(addon.HandleExtraCommand, addon, cmd, rest)
            if not ok then Print("|cffff5555error in /" .. tostring(cmd) .. ":|r " .. tostring(res)); return true end
            return res
        end)() then
        -- handled in Extras.lua
    else
        Print("commands: /lazy (options) | both | quest | friend | off | lock | unlock | scale <n> | reset | panel | minimap | way | status | test <text>")
    end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["ForeverLazy.lua"] = true end end
