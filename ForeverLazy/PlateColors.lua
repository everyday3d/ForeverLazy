-- Nameplate colours: a hostile mob's health bar shows who it is attacking.
--   red     it is attacking ME (the usual look: aggressive mobs stay red)
--   yellow  it is in a fight with someone else
--   purple  my quests need it (kill or loot) and it is not in a fight
-- Nothing else is touched: players, friendly and tapped mobs and mobs out of combat keep the game's own colour. It is off until you
-- turn it on in the options (Nameplates). If another nameplate addon colours the same bars, the one that loads last wins; this one
-- loads after BetterBlizzPlates, so a mob attacking you stays red even when that addon turns it green.
--   /lazy platecolors on|off
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On() local d = DB(); return d and d.plateColors == true end

local DEFAULTS = {
    plateColorMe = { 1, 0, 0 },
    plateColorOthers = { 1, 0.82, 0.1 },
    plateColorQuest = { 0.75, 0.3, 1 },
}
local function Defaults()
    local db = DB()
    if not db then return end
    for k, v in pairs(DEFAULTS) do if type(db[k]) ~= "table" then db[k] = { v[1], v[2], v[3] } end end
end

-- which colour a mob gets (pure, tested offline). info: { hostileNpc, tapped, tankingMe, targetsMe, inCombat, questKind }
-- returns "me", "others", "quest" or nil (leave the game's own colour)
function addon.PlateColorState(info, useThreat, useQuest)
    if not info or not info.hostileNpc or info.tapped then return nil end
    if useThreat ~= false then
        if info.tankingMe or info.targetsMe then return "me" end
        if info.inCombat then return "others" end
    end
    if useQuest ~= false and not info.inCombat and (info.questKind == "kill" or info.questKind == "loot") then return "quest" end
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
    local tanking = Safe(UnitDetailedThreatSituation, "player", unit)
    info.tankingMe = tanking == true
    info.targetsMe = Safe(UnitIsUnit, unit .. "target", "player") == true
    info.inCombat = Safe(UnitAffectingCombat, unit) == true
    info.questKind = addon.PlateQuestKind and addon.PlateQuestKind(unit) or nil
    return info
end

local function Paint(frame)
    if not On() then return end
    local unit = frame and frame.unit
    if type(unit) ~= "string" or issecretvalue and issecretvalue(unit) or not unit:find("^nameplate") then return end
    local bar = frame.healthBar
    if not bar or not bar.SetStatusBarColor then return end
    local db = DB()
    local state = addon.PlateColorState(InfoFor(unit), db.plateThreat, db.plateQuest)
    local c = state == "me" and db.plateColorMe or state == "others" and db.plateColorOthers or state == "quest" and db.plateColorQuest
    if c then bar:SetStatusBarColor(c[1], c[2], c[3]) end
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
                     "PLAYER_REGEN_ENABLED", "QUEST_LOG_UPDATE", "PLAYER_TARGET_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then Defaults(); Hook(); return end
    if not On() then return end
    if type(unit) == "string" and unit:find("^nameplate") then PaintUnit(unit)
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then PaintAll()
    else PaintAll() end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "platecolors" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "on" then db.plateColors = true elseif a == "off" then db.plateColors = nil else db.plateColors = (not db.plateColors) or nil end
        Print(L("nameplate colours: ") .. (db.plateColors and L("on (red = attacking me, yellow = someone else, purple = a quest mob)") or L("off")))
        addon.PlateColorsRefresh()
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["PlateColors.lua"] = true end end