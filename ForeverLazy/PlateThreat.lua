-- Threat on nameplates. Three things, each off until you turn it on (options, Combat, Plates v2):
--   who it is attacking   a short name beside the health bar, in that player's class colour ("YOU" when it is you)
--   your threat           your threat on the mob as a percentage, on the other side of the bar
--   pull warning          PULL! over a mob that is about to turn on you, with one sound (not while the tank colours are on)
-- The tank colours live in PlateColors.lua with the other health bar colours.
--   /lazy threat check    target a mob in a fight: says what the game lets an addon read, and what it hides
-- The game hides some combat values. A hidden value may be handed straight to the game to show, but never read or compared,
-- so a hidden name or number still shows, while the warning (which has to compare) stays quiet.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local T = {}
addon.PlateThreat = T

local function DB() return addon.GetDB() end
local function Opt(key) local d = DB(); return d and d[key] == true end
-- these are Plates v2: while v1 is picked, all of it waits
local function AnyOn()
    if addon.PlateStyle and addon.PlateStyle() ~= "v2" then return false end
    return Opt("plateTargetName") or Opt("plateThreatNum") or Opt("platePullWarn")
end

local PULL_AT = 80                     -- percent of what it takes to pull: from here the warning shows

local function Hidden(v) return issecretvalue ~= nil and issecretvalue(v) and true or false end

--------------------------------------------------------------------------------
-- Rules (pure logic: tests/platethreat.lua)
--------------------------------------------------------------------------------
-- a WoW Forever name is a first name and a surname: the first name is enough on a nameplate
function T.Short(name)
    local first = tostring(name or ""):match("^[^%s%-]+") or ""
    return first
end

-- all three as the game gives them, none of them hidden. status 1: more threat than whoever the mob is on
function T.AboutToPull(tanking, status, scaled)
    if tanking then return false end
    if status == 1 then return true end
    return type(scaled) == "number" and scaled >= PULL_AT
end

--------------------------------------------------------------------------------
-- Reading the game. "ok" is false when the call failed
--------------------------------------------------------------------------------
-- the value when it can be read, else nil; the second answer says it was hidden
local function Read(fn, ...)
    if not fn then return nil, false end
    local ok, v = pcall(fn, ...)
    if not ok then return nil, false end
    if Hidden(v) then return nil, true end
    return v, false
end

local function Threat(unit)
    if not UnitDetailedThreatSituation then return nil end
    local ok, tanking, status, scaled = pcall(UnitDetailedThreatSituation, "player", unit)
    if not ok then return nil end
    return { tanking = tanking, status = status, scaled = scaled }
end

local function Fighting(unit)
    if Read(UnitIsPlayer, unit) == true then return false end
    local can, canHidden = Read(UnitCanAttack, "player", unit)
    if can ~= true and not canHidden then return false end
    local combat, combatHidden = Read(UnitAffectingCombat, unit)
    return combat == true or combatHidden
end

local function ClassColour(unit)
    if not UnitClass then return end
    local ok, _, token = pcall(UnitClass, unit)
    if not ok then return end
    if not Hidden(token) then
        local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
        if c then return c.r, c.g, c.b end
        return
    end
    -- a hidden class: the game may still colour with it
    local okC, c = pcall(function() return C_ClassColor.GetClassColor(token) end)
    if okC and c then
        local okV, r, g, b = pcall(c.GetRGB, c)
        if okV then return r, g, b end
    end
end

--------------------------------------------------------------------------------
-- The words on a nameplate
--------------------------------------------------------------------------------
local parts = setmetatable({}, { __mode = "k" })       -- nameplate -> its words
local warned = {}                                      -- unit -> the warning has sounded for this pull
local lastSound = -100

local function PartsFor(plate)
    local p = parts[plate]
    if p then return p end
    local frame = plate.UnitFrame or plate
    local anchor = frame.healthBar or frame
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(anchor)
    if holder.SetFrameLevel and frame.GetFrameLevel then
        local level = frame:GetFrameLevel()
        if type(level) == "number" then holder:SetFrameLevel(level + 8) end
    end
    local function Word(font, point, relative, x, y)
        local fs = holder:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint(point, holder, relative, x, y)
        fs:Hide()
        return fs
    end
    p = {
        holder = holder,
        target = Word("GameFontNormalSmall", "LEFT", "RIGHT", 4, 0),
        number = Word("GameFontHighlightSmall", "RIGHT", "LEFT", -4, 0),
        warn = Word("GameFontNormalLarge", "BOTTOM", "TOP", 0, 14),
    }
    parts[plate] = p
    return p
end

local function HideAll(p) p.target:Hide(); p.number:Hide(); p.warn:Hide() end

-- the quest icon sits left of a nameplate and the interrupt marker right of it: my words move out past whichever is showing.
-- Looked at each time, since both come and go
local function Beside(p, fs, key, mark, point, relative, x)
    local to = mark or p.holder
    if p[key] == to then return end
    p[key] = to
    local ok = pcall(function()
        fs:ClearAllPoints()
        fs:SetPoint(point, to, relative, x, 0)
    end)
    if not ok then fs:ClearAllPoints(); fs:SetPoint(point, p.holder, relative, x, 0) end
end

local function Place(p, plate)
    Beside(p, p.number, "numberBy", addon.QuestPlateIcon and addon.QuestPlateIcon(plate), "RIGHT", "LEFT", -4)
    Beside(p, p.target, "targetBy", addon.CastMarkerFor and addon.CastMarkerFor(plate), "LEFT", "RIGHT", 4)
end

local function ShowTarget(fs, unit)
    local them = unit .. "target"
    local exists, existsHidden = Read(UnitExists, them)
    if exists ~= true and not existsHidden then fs:Hide(); return end
    if Read(UnitIsUnit, them, "player") == true then
        fs:SetText(L("YOU"))
        fs:SetTextColor(1, 0.25, 0.25)
        fs:Show()
        return
    end
    local ok, name = pcall(UnitName, them)
    if not ok then fs:Hide(); return end
    if not Hidden(name) then
        if type(name) ~= "string" or name == "" then fs:Hide(); return end
        name = T.Short(name)
    end
    if not pcall(fs.SetText, fs, name) then fs:Hide(); return end
    local r, g, b = ClassColour(them)
    if not (r and pcall(fs.SetTextColor, fs, r, g, b)) then fs:SetTextColor(1, 1, 1) end
    fs:Show()
end

local function ShowNumber(fs, t)
    if not t then fs:Hide(); return end
    if not Hidden(t.scaled) and t.scaled == nil then fs:Hide(); return end      -- I am not on its list
    if not pcall(fs.SetFormattedText, fs, "%.0f%%", t.scaled) then fs:Hide(); return end
    if not Hidden(t.tanking) and t.tanking then
        fs:SetTextColor(1, 0.4, 0.7)
    elseif not Hidden(t.tanking) and not Hidden(t.status) and not Hidden(t.scaled) and T.AboutToPull(t.tanking, t.status, t.scaled) then
        fs:SetTextColor(1, 0.82, 0)
    else
        fs:SetTextColor(1, 1, 1)
    end
    fs:Show()
end

local function ShowWarning(fs, t, unit)
    local pulling = false
    if t and not Hidden(t.tanking) and not Hidden(t.status) and not Hidden(t.scaled) and t.scaled ~= nil then
        pulling = T.AboutToPull(t.tanking, t.status, t.scaled)
    end
    if not pulling then
        warned[unit] = nil
        fs:Hide()
        return
    end
    fs:SetText(L("PULL!"))
    fs:SetTextColor(1, 0.55, 0)
    fs:Show()
    -- one sound for each mob and pull, and never a stream of them
    if not warned[unit] then
        warned[unit] = true
        if GetTime() - lastSound > 4 and PlaySound then
            lastSound = GetTime()
            pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
        end
    end
end

local function PlateFor(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plate.IsForbidden and plate:IsForbidden() then return nil end
    return plate
end

local anyShown = false
function T.PaintUnit(unit)
    local plate = PlateFor(unit)
    if not plate then return end
    if not AnyOn() or not Fighting(unit) then
        if parts[plate] then HideAll(parts[plate]) end
        warned[unit] = nil
        return
    end
    local p = PartsFor(plate)
    anyShown = true
    Place(p, plate)
    if Opt("plateTargetName") then ShowTarget(p.target, unit) else p.target:Hide() end
    local t = (Opt("plateThreatNum") or Opt("platePullWarn")) and Threat(unit) or nil
    if Opt("plateThreatNum") then ShowNumber(p.number, t) else p.number:Hide() end
    -- a tank wants the mobs on them: no warning with the tank colours
    if Opt("platePullWarn") and not Opt("plateTank") then ShowWarning(p.warn, t, unit) else p.warn:Hide(); warned[unit] = nil end
    return p
end

function T.PaintAll()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    anyShown = false
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if type(unit) == "string" and not Hidden(unit) then pcall(T.PaintUnit, unit) end
    end
end

local function HideEverything()
    for _, p in pairs(parts) do HideAll(p) end
    warned = {}
    anyShown = false
end

function addon.PlateThreatRefresh()
    HideEverything()
    if AnyOn() then T.PaintAll() end
end

--------------------------------------------------------------------------------
-- When to look again
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_TARGET", "UNIT_THREAT_LIST_UPDATE",
                     "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if not DB() then return end
    local isPlate = type(unit) == "string" and not Hidden(unit) and unit:find("^nameplate") ~= nil
    if event == "NAME_PLATE_UNIT_REMOVED" then
        -- the game uses the same frame for the next mob: leave nothing behind
        if isPlate then
            warned[unit] = nil
            local plate = PlateFor(unit)
            if plate and parts[plate] then HideAll(parts[plate]) end
        end
        return
    end
    if not AnyOn() then return end
    if event == "PLAYER_REGEN_ENABLED" then T.PaintAll()
    elseif isPlate then pcall(T.PaintUnit, unit) end
end)
-- threat climbs without an event for every step: look a few times a second in a fight
local since = 0
ev:SetScript("OnUpdate", function(_, elapsed)
    since = since + (elapsed or 0)
    if since < 0.3 then return end
    local waited = since
    if not DB() or not AnyOn() then since = 0; return end
    local busy = anyShown or (UnitAffectingCombat and Read(UnitAffectingCombat, "player") == true)
    if not busy and waited < 1.5 then return end
    since = 0
    T.PaintAll()
end)

--------------------------------------------------------------------------------
-- /lazy threat check
--------------------------------------------------------------------------------
local function Says(v)
    if Hidden(v) then return L("hidden by the game") end
    if v == nil then return L("nothing") end
    return tostring(v)
end

local function Check()
    local ok, exists = pcall(UnitExists, "target")
    if not ok or (not Hidden(exists) and not exists) then Print(L("threat check: target a mob that is in a fight first")); return end
    Print(L("threat check, for my target:"))
    local function Line(label, fn, ...)
        local okL, v = pcall(fn, ...)
        Print("  " .. label .. ": " .. (okL and Says(v) or L("the game gave an error")))
    end
    Line(L("in a fight"), UnitAffectingCombat, "target")
    local t = Threat("target")
    Print("  " .. L("my threat percent") .. ": " .. (t and Says(t.scaled) or L("the game gave an error")))
    Print("  " .. L("am I the one it is on") .. ": " .. (t and Says(t.tanking) or L("the game gave an error")))
    Print("  " .. L("threat status") .. ": " .. (t and Says(t.status) or L("the game gave an error")))
    Line(L("its target is me"), UnitIsUnit, "targettarget", "player")
    Line(L("its target's name"), UnitName, "targettarget")
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "threat" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "check" then Check()
        else Print(L("/lazy threat check says what the game lets addons read about your target. Turn the nameplate threat helpers on in the options, under Combat, Plates v2.")) end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["PlateThreat.lua"] = true end end
