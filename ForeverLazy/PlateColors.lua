-- Nameplate colours: a hostile mob's health bar says at a glance what it will do.
--   red     it is AGGRESSIVE (it will attack you on sight), before the fight and during it, and always when it is attacking ME
--   orange  it is in a fight with someone else
--   purple  a NEUTRAL mob that my quests need (kill or loot) and that is not in a fight (an aggressive quest mob stays red)
-- Nothing else is touched: players, friendly and tapped mobs and idle neutral mobs keep the game's own colour. It is off until you
-- turn it on in the options (Nameplates). If another nameplate addon colours the same bars, the one that loads last wins; this one
-- loads after BetterBlizzPlates, so an aggressive mob stays red even when that addon turns it green.
--   /lazy platecolors on|off
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

-- Two kinds of plates, one in use at a time. v1: these red, orange and purple colours. v2: the tank colours below and the
-- threat words in PlateThreat.lua. Each keeps its own settings while the other is in use.
local V2_KEYS = { "plateTank", "plateTargetName", "plateThreatNum", "platePullWarn" }
function addon.PlateStyle()
    local d = DB()
    if not d then return "v1" end
    if d.plateStyle == "v1" or d.plateStyle == "v2" then return d.plateStyle end
    for _, k in ipairs(V2_KEYS) do if d[k] == true then return "v2" end end         -- nothing picked yet: what is ticked says it
    return "v1"
end
local function Full() local d = DB(); return d and d.plateColors == true and addon.PlateStyle() == "v1" end
local function Tank() local d = DB(); return d and d.plateTank == true and addon.PlateStyle() == "v2" end
local function On() return Full() or Tank() end

function addon.SetPlateStyle(style)
    local d = DB()
    if not d or (style ~= "v1" and style ~= "v2") then return end
    local changed = addon.PlateStyle() ~= style
    d.plateStyle = style
    if changed then Print(L("nameplates: now using Plates ") .. style) end
    if addon.PlateColorsRefresh then addon.PlateColorsRefresh() end
    if addon.PlateThreatRefresh then addon.PlateThreatRefresh() end
    if addon.RefreshOptions then addon.RefreshOptions() end
end

local DEFAULTS = {
    plateColorMe = { 1, 0, 0 },
    plateColorOthers = { 1, 0.55, 0 },
    plateColorQuest = { 0.75, 0.3, 1 },
}
-- tank colours: green holding it, yellow about to lose it, hot pink got away
local TANK = { safe = { 0.1, 0.75, 0.25 }, slipping = { 1, 0.85, 0 }, lost = { 1, 0.2, 0.7 } }

local function Defaults()
    local db = DB()
    if not db then return end
    for k, v in pairs(DEFAULTS) do if type(db[k]) ~= "table" then db[k] = { v[1], v[2], v[3] } end end
    -- the first version used yellow for "someone else", which is the game's colour for a neutral mob: orange tells them apart
    local o = db.plateColorOthers
    if o and o[1] == 1 and o[2] == 0.82 and o[3] == 0.1 then db.plateColorOthers = { 1, 0.55, 0 } end
end

-- which colour a mob gets (pure, tested offline).
-- info: { hostileNpc, tapped, reaction (the game's 1 to 8: 1 to 3 hostile, 4 neutral), tankingMe, targetsMe, inCombat, questKind,
--         status (my threat status), onList (I am on its threat list), targetsGroup, unsure (the game hides who it is on) }
-- returns "me" (red), "others" (orange), "quest" (purple) or nil (leave the game's own colour)
-- with tank colours, a mob in a fight is "safe" (on me), "slipping" (on me, someone has more threat) or "lost" (got away)
function addon.PlateColorState(info, useThreat, useQuest, tank)
    if not info or not info.hostileNpc or info.tapped then return nil end
    local aggressive = type(info.reaction) == "number" and info.reaction <= 3
    local onMe = info.tankingMe or info.targetsMe
    -- hidden values are no answer: better the game's own colour than a wrong one
    if info.inCombat and info.unsure and not onMe and (tank or useThreat ~= false) then return nil end
    if tank and info.inCombat then
        if onMe then return info.status == 2 and "slipping" or "safe" end
        if info.onList or info.targetsGroup then return "lost" end
        return "others"
    end
    if useThreat ~= false then
        if onMe then return "me" end
        if aggressive and not info.inCombat then return "me" end              -- aggressive before the fight: red, so you know
        if info.inCombat then return "others" end
    end
    if useQuest ~= false and not aggressive and not info.inCombat and (info.questKind == "kill" or info.questKind == "loot") then return "quest" end
    return nil
end

local function Safe(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then return nil end
    return a, b
end

local function InfoFor(unit)
    local info = {}
    info.hostileNpc = (Safe(UnitIsPlayer, unit) ~= true) and (Safe(UnitCanAttack, "player", unit) == true)
    info.tapped = Safe(UnitIsTapDenied, unit) == true
    info.reaction = Safe(UnitReaction, "player", unit)
    local okT, tanking, status = pcall(UnitDetailedThreatSituation, "player", unit)
    local function Hidden(v) return issecretvalue ~= nil and issecretvalue(v) end
    if not okT then tanking, status = nil, nil end
    if not Hidden(tanking) then info.tankingMe = tanking == true end
    if not Hidden(status) then info.status, info.onList = status, status ~= nil end
    local okU, mine = pcall(UnitIsUnit, unit .. "target", "player")
    if okU and Hidden(mine) then
        info.unsure = true
    elseif okU then
        info.targetsMe = mine == true
    end
    info.targetsGroup = (UnitInParty and Safe(UnitInParty, unit .. "target") and true) or (UnitInRaid and Safe(UnitInRaid, unit .. "target") and true) or false
    info.inCombat = Safe(UnitAffectingCombat, unit) == true
    info.questKind = addon.PlateQuestKind and addon.PlateQuestKind(unit) or nil
    return info
end

local painted = setmetatable({}, { __mode = "k" })      -- health bar -> the colour it had before mine

-- give a bar its own colour back. The game keeps what it last set in bar.r, g, b, and may not set it again by itself
local function Unpaint(bar)
    local was = painted[bar]
    if not was then return end
    painted[bar] = nil
    local r, g, b = bar.r, bar.g, bar.b
    if type(r) ~= "number" then r, g, b = was[1], was[2], was[3] end
    if r then bar:SetStatusBarColor(r, g, b) end
end

local function Paint(frame)
    if not On() then return end
    local unit = frame and frame.unit
    if type(unit) ~= "string" or issecretvalue and issecretvalue(unit) or not unit:find("^nameplate") then return end
    local bar = frame.healthBar
    if not bar or not bar.SetStatusBarColor then return end
    local db = DB()
    local full = Full()
    local state = addon.PlateColorState(InfoFor(unit), full and db.plateThreat ~= false or false, full and db.plateQuest ~= false or false, Tank())
    -- on their own, the tank colours colour nothing but the three tank states
    local c = TANK[state]
    if full and not c then
        c = state == "me" and db.plateColorMe or state == "others" and db.plateColorOthers or state == "quest" and db.plateColorQuest or nil
    end
    if c then
        if not painted[bar] then painted[bar] = bar.GetStatusBarColor and { bar:GetStatusBarColor() } or {} end
        bar:SetStatusBarColor(c[1], c[2], c[3])
    else
        Unpaint(bar)
    end
end

local function PaintUnit(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    local frame = plate and plate.UnitFrame
    if frame then pcall(Paint, frame) end
end

local function PaintAll()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        if plate.UnitFrame then pcall(Paint, plate.UnitFrame) end
    end
end

-- put the game's own colour back (when switched off)
local function Restore()
    for bar in pairs(painted) do pcall(Unpaint, bar) end
    if not (C_NamePlate and C_NamePlate.GetNamePlates and CompactUnitFrame_UpdateHealthColor) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        if plate.UnitFrame then pcall(CompactUnitFrame_UpdateHealthColor, plate.UnitFrame) end
    end
end

local hooked = false
local function Hook()
    if hooked or not CompactUnitFrame_UpdateHealthColor then return end
    hooked = true
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame) pcall(Paint, frame) end)
end

addon.PlateColorsRefresh = function()
    Defaults()
    Hook()
    if On() then PaintAll() else Restore() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "NAME_PLATE_UNIT_ADDED", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "PLAYER_REGEN_DISABLED",
                     "PLAYER_REGEN_ENABLED", "QUEST_LOG_UPDATE", "PLAYER_TARGET_CHANGED", "UNIT_TARGET" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then Defaults(); Hook(); return end
    if not On() then return end
    if event == "UNIT_TARGET" and not (type(unit) == "string" and unit:find("^nameplate")) then return end
    if type(unit) == "string" and unit:find("^nameplate") then PaintUnit(unit)
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then PaintAll()
    else PaintAll() end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "platestyle" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "v1" or a == "v2" then addon.SetPlateStyle(a) end
        Print(L("nameplates: using Plates ") .. addon.PlateStyle() .. L("  (/lazy platestyle v1|v2)"))
        return true
    elseif (cmd or ""):lower() == "platecolors" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "on" then db.plateColors = true elseif a == "off" then db.plateColors = nil
        else db.plateColors = (not (db.plateColors and addon.PlateStyle() == "v1")) or nil end
        if db.plateColors then addon.SetPlateStyle("v1") end                      -- these are the v1 colours
        Print(L("nameplate colours: ") .. (db.plateColors and L("on (red = aggressive or attacking me, orange = fighting someone else, purple = a neutral quest mob)") or L("off")))
        addon.PlateColorsRefresh()
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["PlateColors.lua"] = true end end