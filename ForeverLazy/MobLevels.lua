-- Mob levels: every hostile creature you target, mouse over or see a nameplate for is noted with its level, per zone.
--   /lazy moblevels            the level range in the zone you are in, and the mobs in it
--   /lazy moblevels all        every zone you have seen
--   /lazy moblevels <zone>     that zone        /lazy moblevels <mob>   that mob wherever it was seen
--   /lazy moblevels clear      forget it all
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

local function Store()
    local db = DB()
    if not db then return nil end
    db.mobLevels = db.mobLevels or {}
    return db.mobLevels
end

local function Note(unit)
    if not (unit and UnitExists(unit)) then return end
    if UnitIsPlayer(unit) or (UnitPlayerControlled and UnitPlayerControlled(unit)) then return end
    if not (UnitCanAttack and UnitCanAttack("player", unit)) then return end
    if UnitIsDead and UnitIsDead(unit) then return end
    local ctype = UnitCreatureType and UnitCreatureType(unit)
    if ctype == "Critter" or ctype == "Non-combat Pet" then return end
    local name = UnitName(unit)
    local level = UnitLevel and UnitLevel(unit)
    if not name or not level then return end
    local zone = GetRealZoneText and GetRealZoneText()
    local st = Store()
    if not (zone and zone ~= "" and st) then return end
    st[zone] = st[zone] or {}
    local rec = st[zone][name]
    if not rec then rec = { n = 0 }; st[zone][name] = rec end
    if level < 0 then
        rec.skull = true                       -- a "??" level: much higher than mine
    else
        rec.min = rec.min and math.min(rec.min, level) or level
        rec.max = rec.max and math.max(rec.max, level) or level
    end
    rec.n = (rec.n or 0) + 1
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then unit = "target"
    elseif event == "UPDATE_MOUSEOVER_UNIT" then unit = "mouseover" end
    pcall(Note, unit)
end)

--------------------------------------------------------------------------------
-- Reading it back
--------------------------------------------------------------------------------
local function Range(mobs)
    local lo, hi, count, skull
    for _, r in pairs(mobs) do
        count = (count or 0) + 1
        if r.min then
            lo = lo and math.min(lo, r.min) or r.min
            hi = hi and math.max(hi, r.max) or r.max
        end
        if r.skull then skull = true end
    end
    return lo, hi, count or 0, skull
end

local function Span(lo, hi)
    if not lo then return "?" end
    return lo == hi and tostring(lo) or (lo .. "-" .. hi)
end

local function ZoneReport(zone, mobs)
    local lo, hi, count, skull = Range(mobs)
    Print(string.format(L("%s: levels %s, %d kind%s of mob seen%s"), zone, Span(lo, hi), count, count == 1 and "" or "s",
        skull and " (and some ?? level ones)" or ""))
    local list = {}
    for name, r in pairs(mobs) do list[#list + 1] = { name = name, r = r } end
    table.sort(list, function(a, b)
        local am, bm = a.r.min or 999, b.r.min or 999
        if am ~= bm then return am < bm end
        return a.name < b.name
    end)
    local line = {}
    for i, m in ipairs(list) do
        if i > 14 then line[#line + 1] = string.format("and %d more", #list - 14); break end
        line[#line + 1] = string.format("%s %s", m.name, m.r.min and ("(" .. Span(m.r.min, m.r.max) .. ")") or "(??)")
    end
    if #line > 0 then Print("  " .. table.concat(line, ", ")) end
end

function addon.MobLevels(arg)
    local st = Store()
    if not st then return end
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local low = arg:lower()
    if low == "clear" or low == "reset" then
        wipe(st)
        Print(L("mob levels forgotten"))
        return
    end
    if low == "all" then
        local names = {}
        for z in pairs(st) do names[#names + 1] = z end
        table.sort(names)
        if #names == 0 then Print(L("no mobs seen yet. Target or mouse over some and they are noted.")) return end
        for _, z in ipairs(names) do
            local lo, hi, count = Range(st[z])
            Print(string.format(L("%s: levels %s (%d mobs)"), z, Span(lo, hi), count))
        end
        return
    end
    if low == "" then
        local zone = GetRealZoneText and GetRealZoneText()
        if zone and st[zone] and next(st[zone]) then
            ZoneReport(zone, st[zone])
        else
            Print(L("nothing seen in ") .. tostring(zone or "this zone") .. L(" yet. Target or mouse over a hostile mob and it is noted."))
        end
        return
    end
    -- a zone name
    for z, mobs in pairs(st) do
        if z:lower() == low or z:lower():find(low, 1, true) == 1 then ZoneReport(z, mobs); return end
    end
    -- a mob name, in any zone
    local found = 0
    for z, mobs in pairs(st) do
        for name, r in pairs(mobs) do
            if name:lower():find(low, 1, true) then
                found = found + 1
                if found <= 12 then
                    Print(string.format(L("%s: level %s in %s%s"), name, r.min and Span(r.min, r.max) or "??", z, r.skull and " (also ??)" or ""))
                end
            end
        end
    end
    if found == 0 then Print(L("nothing seen called '") .. arg .. L("'. Try /lazy moblevels all")) end
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "moblevels" or c == "moblevel" or c == "mobs" then
        addon.MobLevels(rest)
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["MobLevels.lua"] = true end end
