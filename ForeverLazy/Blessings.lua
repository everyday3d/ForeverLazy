-- Paladin blessings, simply: ONE button buffs the next party member who needs a blessing, and for every class in the group you
-- choose which blessing it should get (click a class to change it).
--   /lazy blessings          show or hide the panel     /lazy blessings debug   what the addon sees (spells, buffs, range)
--   /lazy blessings reset    back to the usual choices (Might for fighters, Wisdom for casters)
-- It only shows for a paladin who is in a group. The button casts by clicking it (a game rule: a spell needs a click), and its target
-- changes between fights, never during one.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On()
    local d = DB()
    return d and d.blessPanel ~= false
end

local REFRESH = 90            -- seconds left on a blessing before it counts as running out

-- what a class gets unless I choose otherwise (the short name of the blessing)
local DEFAULT = {
    WARRIOR = "Might", ROGUE = "Might", HUNTER = "Might", PALADIN = "Might", DEATHKNIGHT = "Might",
    PRIEST = "Wisdom", MAGE = "Wisdom", WARLOCK = "Wisdom", SHAMAN = "Wisdom", DRUID = "Wisdom",
}
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local ORDER = { "Might", "Wisdom", "Kings", "Salvation", "Light", "Sanctuary" }       -- the usual order in the choices

--------------------------------------------------------------------------------
-- The blessings this paladin knows, from the spellbook
--------------------------------------------------------------------------------
local function SpellsKnown()
    local out = {}               -- spell name -> true
    local function Add(name) if name then out[name] = true end end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if li then
                for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                    local si = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if si and si.name and not si.isPassive then Add(si.name) end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
                local ok, name = pcall(GetSpellBookItemName, i, "spell")
                if ok then Add(name) end
            end
        end
    end
    return out
end

-- the blessings (full spell names) I can cast, in the usual order. "Blessing of Might", or "Greater Blessing of Might" when that is what I have
function addon.BlessingsAvailable(known)
    known = known or SpellsKnown()
    local list, seen = {}, {}
    for _, short in ipairs(ORDER) do
        for _, prefix in ipairs({ "Blessing of ", "Greater Blessing of " }) do
            local full = prefix .. short
            if known[full] and not seen[short] then list[#list + 1] = full; seen[short] = true end
        end
    end
    -- any other blessing this client has
    local extra = {}
    for name in pairs(known) do
        local short = name:match("^Blessing of (.+)$") or name:match("^Greater Blessing of (.+)$")
        if short and not seen[short] and short ~= "Freedom" and short ~= "Protection" and short ~= "Sacrifice" then extra[#extra + 1] = name end
    end
    table.sort(extra)
    for _, n in ipairs(extra) do list[#list + 1] = n end
    return list
end

local function Short(full)
    if not full then return "-" end
    return (full:gsub("^Greater Blessing of ", ""):gsub("^Blessing of ", ""))
end
addon.BlessingShort = Short

-- the blessing a class gets: my choice, else the usual one when I have it, else none
function addon.BlessingFor(class, available)
    local db = DB()
    local mine = db and db.blessings and db.blessings[class]
    if mine == "none" then return nil end
    if mine then return mine end
    local want = DEFAULT[class]
    for _, full in ipairs(available or {}) do if Short(full) == want then return full end end
    return nil
end

--------------------------------------------------------------------------------
-- Who needs what (pure logic, tested offline)
--------------------------------------------------------------------------------
-- members: { { unit =, class =, name =, alive =, connected = , inRange = }, ... } (me first)
-- buffsOf(unit) -> list of { name =, left = seconds (or nil for no end) } ; a unit whose buffs cannot be read returns nil
-- returns the member who is next, the blessing to cast on them, and how many still need one
function addon.BlessNext(members, available, buffsOf)
    local pick, pickBless, count = nil, nil, 0
    for _, m in ipairs(members) do
        if m.alive ~= false and m.connected ~= false then
            local bless = addon.BlessingFor(m.class, available)
            if bless then
                local short = Short(bless)
                local buffs = buffsOf(m.unit)
                if buffs then
                    local has = false
                    for _, b in ipairs(buffs) do
                        local bs = b.name and Short(b.name)
                        if bs == short and (b.left == nil or b.left > REFRESH) then has = true; break end
                    end
                    if not has then
                        count = count + 1
                        if not pick and m.inRange ~= false then pick, pickBless = m, bless end
                    end
                end
            end
        end
    end
    return pick, pickBless, count
end

--------------------------------------------------------------------------------
-- Reading the group
--------------------------------------------------------------------------------
local function BuffsOf(unit)
    local out = {}
    local now = GetTime and GetTime() or 0
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        for i = 1, 40 do
            local a = C_UnitAuras.GetBuffDataByIndex(unit, i)
            if not a then break end
            if issecretvalue and (issecretvalue(a.name) or issecretvalue(a.expirationTime)) then return nil end
            local left = (a.expirationTime and a.expirationTime > 0) and (a.expirationTime - now) or nil
            out[#out + 1] = { name = a.name, left = left, source = a.sourceUnit }
        end
    elseif UnitBuff then
        for i = 1, 40 do
            local name, _, _, _, duration, expires, source = UnitBuff(unit, i)
            if not name then break end
            local left = (expires and expires > 0) and (expires - now) or nil
            out[#out + 1] = { name = name, left = left, source = source }
        end
    else
        return nil
    end
    return out
end

local function Members(spellForRange)
    local list = {}
    local function Add(unit)
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            local inRange = true
            if unit ~= "player" and spellForRange then
                local r
                if C_Spell and C_Spell.IsSpellInRange then r = C_Spell.IsSpellInRange(spellForRange, unit)
                elseif IsSpellInRange then r = IsSpellInRange(spellForRange, unit) end
                if r == false or r == 0 then inRange = false end
            end
            list[#list + 1] = { unit = unit, class = class, name = UnitName(unit),
                alive = not UnitIsDeadOrGhost(unit), connected = UnitIsConnected(unit) ~= false, inRange = inRange }
        end
    end
    Add("player")
    if IsInRaid and IsInRaid() then
        for i = 1, math.min(40, GetNumGroupMembers and GetNumGroupMembers() or 0) do Add("raid" .. i) end
    else
        for i = 1, 4 do Add("party" .. i) end
    end
    -- in a raid "raidN" includes me: keep one entry for me
    local seen, out = {}, {}
    for _, m in ipairs(list) do
        local key = m.name or m.unit
        if not seen[key] then seen[key] = true; out[#out + 1] = m end
    end
    return out
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------
local frame, button, rows = nil, nil, {}
local waiting = false
local lastSig = ""

local function ClassName(class)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end
local function ClassColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function Cycle(class, step)
    local db = DB()
    db.blessings = db.blessings or {}
    local avail = addon.BlessingsAvailable()
    local cur = db.blessings[class] or addon.BlessingFor(class, avail) or "none"
    local list = { "none" }
    for _, f in ipairs(avail) do list[#list + 1] = f end
    local idx = 1
    for i, v in ipairs(list) do if v == cur then idx = i end end
    idx = ((idx - 1 + step) % #list) + 1
    db.blessings[class] = list[idx]
    lastSig = ""
    if addon.BlessingsRefresh then addon.BlessingsRefresh() end
end

local function Build()
    local f = CreateFrame("Frame", "ForeverLazyBlessings", UIParent)
    f:SetSize(190, 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
    local title = CreateFrame("Button", nil, f)
    title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT"); title:SetHeight(16)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() if not DB().locked then f:StartMoving() end end)
    title:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        DB().pos = DB().pos or {}
        DB().pos.bless = { point = point, x = x, y = y }
    end)
    f.title = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("LEFT", 6, 0)
    f.title:SetText(L("Blessings"))
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(18, 18); close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function()
        DB().blessPanel = false
        f:Hide()
        Print(L("blessings: panel closed. /lazy blessings brings it back."))
    end)
    -- the one button (secure: its target is set between fights)
    local b = CreateFrame("Button", "ForeverLazyBlessButton", f, "SecureActionButtonTemplate")
    b:SetSize(180, 26)
    b:SetPoint("TOPLEFT", 5, -18)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "spell")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(); b.bg:SetColorTexture(0.1, 0.35, 0.1, 0.9)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22); b.icon:SetPoint("LEFT", 2, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0); b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("One button for the whole group"), 1, 0.82, 0)
        GameTooltip:AddLine(L("Click: bless the next player who needs it."), 1, 1, 1)
        GameTooltip:AddLine(L("Click a class below to choose its blessing."), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button = b
    f:Hide()
    return f
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, frame)
    r:SetSize(180, 18)
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -46 - (i - 1) * 19)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.07)
    r.cls = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.cls:SetPoint("LEFT", 4, 0)
    r.bless = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.bless:SetPoint("RIGHT", -4, 0)
    r:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    r:SetScript("OnClick", function(self, mouse) if self.class then Cycle(self.class, mouse == "RightButton" and -1 or 1) end end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("Click: the next blessing. Right-click: the one before."), 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function Place()
    if not frame then return end
    local p = DB().pos and DB().pos.bless or { point = "LEFT", x = 20, y = 60 }
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

local function IsPaladin()
    local _, class = UnitClass("player")
    return class == "PALADIN"
end

local function Refresh()
    local db = DB()
    if not db then return end
    if not (On() and IsPaladin()) or not (IsInGroup and IsInGroup() or db.blessSolo == true) then
        if frame then frame:Hide() end
        return
    end
    if InCombatLockdown() then waiting = true; return end
    waiting = false
    if not frame then frame = Build(); Place() end
    local avail = addon.BlessingsAvailable()
    if #avail == 0 then
        if frame then frame:Hide() end
        return
    end
    local members = Members(avail[1])
    local pick, bless, count = addon.BlessNext(members, avail, BuffsOf)
    -- the class rows: the classes that are in the group
    local present, seen = {}, {}
    for _, m in ipairs(members) do if m.class and not seen[m.class] then seen[m.class] = true end end
    for _, c in ipairs(CLASS_ORDER) do if seen[c] then present[#present + 1] = c end end
    for c in pairs(seen) do local known = false; for _, p in ipairs(present) do if p == c then known = true end end; if not known then present[#present + 1] = c end end
    for i = 1, math.max(#present, #rows) do
        local r = present[i] and Row(i) or rows[i]
        if r then
            if present[i] then
                r.class = present[i]
                local cr, cg, cb = ClassColor(present[i])
                r.cls:SetText(ClassName(present[i]))
                r.cls:SetTextColor(cr, cg, cb)
                local b = addon.BlessingFor(present[i], avail)
                r.bless:SetText(b and Short(b) or L("none"))
                r:Show()
            else
                r:Hide()
            end
        end
    end
    frame:SetHeight(48 + #present * 19)
    -- the button
    if pick and bless then
        button:SetAttribute("spell", bless)
        button:SetAttribute("unit", pick.unit)
        local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(bless)) or (GetSpellTexture and GetSpellTexture(bless))
        button.icon:SetTexture(icon or "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings")
        button.icon:SetShown(true)
        button.text:SetText(string.format("%s: %s", Short(bless), tostring(pick.name or pick.unit)) .. (count > 1 and string.format("  (+%d)", count - 1) or ""))
        button.bg:SetColorTexture(0.1, 0.35, 0.1, 0.9)
    else
        button:SetAttribute("spell", nil)
        button:SetAttribute("unit", nil)
        button.icon:SetShown(false)
        button.text:SetText(count > 0 and L("someone is out of range") or L("everyone is blessed"))
        button.bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
    end
    Place()
    frame:Show()
end
addon.BlessingsRefresh = Refresh

--------------------------------------------------------------------------------
-- Keeping it fresh
--------------------------------------------------------------------------------
local pending
local function Soon()
    if pending or not C_Timer or not C_Timer.After then pcall(Refresh); return end
    pending = true
    C_Timer.After(0.4, function() pending = false; pcall(Refresh) end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_AURA" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        if not unit or not (unit == "player" or unit:find("^party") or unit:find("^raid")) then return end
        if not frame or not frame:IsShown() then return end
    end
    if event == "PLAYER_REGEN_ENABLED" and not waiting then Soon(); return end
    Soon()
end)
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 2 then return end
    acc = 0
    if frame and frame:IsShown() then Soon() end          -- blessings run out
end)

--------------------------------------------------------------------------------
-- /lazy blessings
--------------------------------------------------------------------------------
function addon.BlessingsDebug()
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    local _, class = UnitClass("player")
    Add("Class: " .. tostring(class) .. "   in a group: " .. tostring(IsInGroup and IsInGroup()))
    local known = SpellsKnown()
    local names = {}
    for name in pairs(known) do
        if name:find("Blessing") or name:find("Aura") or name:find("Seal") or name:find("Righteous Fury") or name:find("Salvation") then names[#names + 1] = name end
    end
    table.sort(names)
    Add("Blessing, aura and seal spells in the spellbook (" .. #names .. "): " .. table.concat(names, ", "))
    local avail = addon.BlessingsAvailable(known)
    Add("Blessings the panel offers: " .. (#avail > 0 and table.concat(avail, ", ") or "none"))
    Add("")
    Add("Aura reading: C_UnitAuras.GetBuffDataByIndex=" .. tostring(C_UnitAuras and C_UnitAuras.GetBuffDataByIndex ~= nil) .. "  UnitBuff=" .. tostring(UnitBuff ~= nil)
        .. "  C_Spell.IsSpellInRange=" .. tostring(C_Spell and C_Spell.IsSpellInRange ~= nil))
    Add("")
    for _, m in ipairs(Members(avail[1])) do
        local b = addon.BlessingFor(m.class, avail)
        Add(string.format("%s (%s, %s): gets %s, in range %s", tostring(m.name), tostring(m.class), m.alive and "alive" or "dead", b and Short(b) or "none", tostring(m.inRange)))
        local buffs = BuffsOf(m.unit)
        if not buffs then Add("     buffs cannot be read")
        else
            local parts = {}
            for i = 1, math.min(12, #buffs) do
                local x = buffs[i]
                parts[#parts + 1] = string.format("%s%s", tostring(x.name), x.left and string.format(" (%ds)", x.left) or "")
            end
            Add("     buffs: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
        end
    end
    addon.ReportWindow(L("Forever Lazy: blessings"), lines)
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "blessings" or c == "bless" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "debug" then addon.BlessingsDebug(); return true end
        if a == "reset" then db.blessings = nil; Print(L("blessings: back to the usual choices (Might for fighters, Wisdom for casters)"))
        elseif a == "solo" then db.blessSolo = not db.blessSolo or nil; Print(L("blessings: the panel also shows when you are alone: ") .. tostring(db.blessSolo == true))
        else
            db.blessPanel = (db.blessPanel == false) and nil or false
            if db.blessPanel == false then Print(L("blessings: panel hidden")) else Print(L("blessings: panel on (it shows for a paladin in a group)")) end
        end
        if addon.RefreshOptions then addon.RefreshOptions() end
        Refresh()
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Blessings.lua"] = true end end
