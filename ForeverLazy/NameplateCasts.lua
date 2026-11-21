-- Interrupt marker on nameplates: while a hostile mob is casting or channeling, a small icon of the spell shows on the right of its
-- plate. The border tells you what you can do about it:
--   green  = your interrupt is ready      red = your interrupt is on cooldown      grey = you have no interrupt at all
-- Spells the game says can NOT be interrupted get no marker. Switch it off in the options (Nameplates).
local ADDON, ns = ...
local addon = ns.addon

local function DB() return addon.GetDB() end
local function On()
    local db = DB()
    return not (db and db.nameplateCasts == false)
end

-- interrupts by class (spell ids of the first rank; found again by name so higher ranks count too)
local INTERRUPTS = {
    WARRIOR = { 6552, 72 },            -- Pummel, Shield Bash
    ROGUE = { 1766 },                  -- Kick
    MAGE = { 2139 },                   -- Counterspell
    SHAMAN = { 8042, 57994 },          -- Earth Shock, Wind Shear
    PALADIN = { 96231 },               -- Rebuke
    PRIEST = { 15487 },                -- Silence
    DEATHKNIGHT = { 47528 },           -- Mind Freeze
    DRUID = { 106839, 5211 },          -- Skull Bash, Bash
    WARLOCK = { 19647 },               -- Spell Lock (felhunter)
    HUNTER = { 147362 },               -- Counter Shot
}

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id); if ok and n then return n end end
    if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok then return type(n) == "table" and n.name or n end end
end

local function Cooldown(spell)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, c = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and type(c) == "table" then return c.startTime, c.duration end
    end
    if GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, spell)
        if ok then return s, d end
    end
end

-- 1 ready, 0 on cooldown, nil I have none
local function InterruptState()
    local _, class = UnitClass("player")
    local list = INTERRUPTS[class or ""]
    if not list then return nil end
    local known
    for _, id in ipairs(list) do
        local name = SpellName(id)
        local isKnown = name and ((GetSpellInfo and GetSpellInfo(name)) ~= nil or (IsSpellKnown and IsSpellKnown(id)))
        if isKnown then
            known = true
            local s, d = Cooldown(name)
            if s and d and not (issecretvalue and (issecretvalue(s) or issecretvalue(d))) then
                if s == 0 or d <= 1.6 then return 1 end
            else
                return 1
            end
        end
    end
    return known and 0 or nil
end

local markers = {}     -- nameplate frame -> marker frame

local function MarkerFor(plate)
    local f = markers[plate]
    if f then return f end
    f = CreateFrame("Frame", nil, plate)
    f:SetSize(22, 22)
    f:SetFrameStrata("HIGH")
    f.edge = f:CreateTexture(nil, "BACKGROUND")
    f.edge:SetPoint("TOPLEFT", -2, 2)
    f.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    f.edge:SetColorTexture(0.6, 0.6, 0.6, 1)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f:SetPoint("LEFT", plate, "RIGHT", -2, 0)
    f:Hide()
    markers[plate] = f
    return f
end

local function Paint(f)
    local st = InterruptState()
    if st == 1 then f.edge:SetColorTexture(0.1, 0.9, 0.2, 1)
    elseif st == 0 then f.edge:SetColorTexture(0.9, 0.15, 0.15, 1)
    else f.edge:SetColorTexture(0.55, 0.55, 0.55, 1) end
end

local function Update(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local f = markers[plate]
    if not On() then if f then f:Hide() end return end
    local show, icon = false, nil
    if UnitCanAttack("player", unit) then
        local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
        -- UnitCastingInfo: name, text, texture, start, end, isTrade, castID, notInterruptible
        local okC, name, _, tex, _, _, _, _, notInt = pcall(UnitCastingInfo, unit)
        if okC and name and Plain(name) then
            icon = tex
            show = not (notInt and Plain(notInt))
        else
            -- UnitChannelInfo: name, text, texture, start, end, isTrade, notInterruptible
            local okH, cname, _, ctex, _, _, _, cNot = pcall(UnitChannelInfo, unit)
            if okH and cname and Plain(cname) then
                icon = ctex
                show = not (cNot and Plain(cNot))
            end
        end
    end
    if not show then if f then f:Hide() end return end
    f = f or MarkerFor(plate)
    if icon and not (issecretvalue and issecretvalue(icon)) then f.tex:SetTexture(icon) end
    Paint(f)
    f:Show()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if type(unit) ~= "string" or unit:sub(1, 9) ~= "nameplate" then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate and markers[plate] then markers[plate]:Hide() end
        return
    end
    pcall(Update, unit)
end)

-- keep the border colour right while a cast is going (my interrupt comes off cooldown, or goes on it)
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.25 then return end
    acc = 0
    for _, f in pairs(markers) do if f:IsShown() then pcall(Paint, f) end end
end)

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["NameplateCasts.lua"] = true end end
