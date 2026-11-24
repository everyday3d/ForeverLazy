-- Paladin blessings, simply: ONE button buffs the next party member who needs a blessing, and for every class in the group you
-- choose which blessing it should get (click a class to change it).
--   /lazy blessings on|off   show or hide the panel     /lazy blessings debug   what the addon sees (spells, buffs, range)
--   /lazy blessings solo     also show it when you are alone (type it again to undo)
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
-- skip(class, shortName) -> true when another paladin gives that blessing to that class (see BlessCovered)
-- recent(member, shortName) -> true when I cast that blessing on that player a moment ago (the new buff may not show yet)
function addon.BlessNext(members, available, buffsOf, skip, recent)
    local pick, pickBless, count = nil, nil, 0
    for _, m in ipairs(members) do
        if m.alive ~= false and m.connected ~= false then
            local bless = addon.BlessingFor(m.class, available)
            if bless and skip and skip(m.class, Short(bless)) then bless = nil end
            if bless then
                local short = Short(bless)
                local buffs = buffsOf(m.unit)
                if buffs then
                    local has = false
                    for _, b in ipairs(buffs) do
                        local bs = b.name and Short(b.name)
                        if bs == short and (b.left == nil or b.left > REFRESH) then has = true; break end
                    end
                    if not has and recent and recent(m, short) then has = true end
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
-- Sharing with the other paladins (pure logic, tested offline)
--------------------------------------------------------------------------------
-- What I give each class, as a small text for the other paladins: "DRUID=Wisdom;WARRIOR=Might"
function addon.BlessEncode(map)
    local classes = {}
    for c in pairs(map or {}) do classes[#classes + 1] = c end
    table.sort(classes)
    local parts = {}
    for _, c in ipairs(classes) do parts[#parts + 1] = c .. "=" .. map[c] end
    return table.concat(parts, ";")
end

function addon.BlessDecode(text)
    local map = {}
    for class, bless in tostring(text or ""):gmatch("(%u+)=(%a+)") do map[class] = bless end
    return map
end

-- Two paladins who both give the same blessing to a class would only waste mana, so the one who comes first in the alphabet
-- casts it and the other skips that class. Both clients work this out the same way, so no talking is needed.
-- others: { [name] = { map = { CLASS = "Might" } } }. Returns the name of the paladin who covers it, or nil when I cast it.
function addon.BlessCovered(class, short, me, others)
    local mine = (me or ""):lower()
    local best
    for name, o in pairs(others or {}) do
        local n = name:lower()
        -- a paladin who is dead, offline or too far away can not do it: then I cast it (o.active == false)
        if o.active ~= false and o.map and o.map[class] == short and n < mine and (not best or n < best:lower()) then best = name end
    end
    return best
end

-- The blessing to give a class so it does not repeat what the other paladins already give it.
-- shorts: the blessings I can cast (short names, in my usual order); taken: { Might = true, ... } for that class; want: the usual one.
function addon.BlessSplitFor(shorts, taken, want)
    taken = taken or {}
    local function Free(s) return s and not taken[s] end
    local has = {}
    for _, s in ipairs(shorts) do has[s] = true end
    if has[want] and Free(want) then return want end
    for _, s in ipairs({ "Kings", "Might", "Wisdom", "Light", "Sanctuary", "Salvation" }) do
        if has[s] and Free(s) then return s end
    end
    for _, s in ipairs(shorts) do if Free(s) then return s end end
    return nil
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
    if addon.BlessSend then addon.BlessSend("U") end                 -- tell the other paladins what I changed
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
    -- secure buttons fire on the key-down or key-up edge depending on the ActionButtonUseKeyDown setting, so listen for both
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")
    b:SetAttribute("type1", "spell")
    b:SetAttribute("useOnKeyDown", false)
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
    -- after the click (the cast itself is the secure part): remember who was just blessed and move on to the next person
    b:HookScript("PostClick", function(self)
        if addon.BlessNoteCast then addon.BlessNoteCast(self:GetAttribute("unit"), self:GetAttribute("spell")) end
    end)
    b:HookScript("OnClick", function(self)
        -- only after /lazy blessings debug, and only until the next reload
        if addon.blessClickDebug then
            local macro = self:GetAttribute("macrotext")
            Print("blessings click: " .. (macro and ("casts: " .. macro) or "nothing to cast (everyone is blessed, or nobody can be reached)"))
        end
    end)
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
        -- what the other paladins in the group give this class
        local o = addon.BlessLastOthers and addon.BlessLastOthers() or {}
        for name, e in pairs(o) do
            local b = self.class and e.map and e.map[self.class]
            GameTooltip:AddLine(string.format("%s: %s", name, b or L("none")), 0.6, 0.8, 1)
        end
        if self.coveredBy then
            GameTooltip:AddLine(string.format(L("%s gives this blessing to this class, so your button skips them."), self.coveredBy), 0.8, 0.8, 0.5, true)
        end
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

--------------------------------------------------------------------------------
-- Talking to the other paladins in the group
--------------------------------------------------------------------------------
local PREFIX = "FLBLS"
local others = {}                 -- paladin name -> { map = { CLASS = "Might" }, t = time heard }
local lastOthers = {}             -- the ones that are in the group right now (set by Refresh)

-- A blessing I just cast counts as given for a few seconds: the buff takes a moment to show on the player, and until it does the
-- button would point at the same person again (and a quick second click would bless them twice). It also lets the button move on
-- to the next person when a cast did not land (out of sight, out of range) instead of hanging on one player.
local recent = {}
local RECENT = 8
function addon.BlessRecently(m, short)
    local t = recent[tostring(m.name or m.unit) .. ":" .. tostring(short)]
    return t ~= nil and GetTime() - t < RECENT
end
function addon.BlessNoteCast(unit, spell)
    if not (unit and spell) then return end
    local name = UnitName and UnitName(unit)
    if not name then return end
    recent[name .. ":" .. Short(spell)] = GetTime()
    if addon.BlessingsRefresh then pcall(addon.BlessingsRefresh) end          -- point the button at the next person at once
end
function addon.BlessLastOthers() return lastOthers end

local function MyClaims(avail)
    local map = {}
    for class in pairs(DEFAULT) do
        local b = addon.BlessingFor(class, avail)
        if b then map[class] = Short(b) end
    end
    return map
end

-- kind "H": hello (I joined or the group changed, please tell me yours); "U": here is mine
function addon.BlessSend(kind)
    local db = DB()
    if not db or db.blessShare == false then return end
    if not IsPaladin() or not (IsInGroup and IsInGroup()) then return end
    if not addon.SendCommMessage then return end
    local avail = addon.BlessingsAvailable()
    if #avail == 0 then return end
    local channel = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    pcall(addon.SendCommMessage, addon, PREFIX, "1|" .. kind .. "|" .. addon.BlessEncode(MyClaims(avail)), channel)
end

function addon:OnBlessSync(prefix, message, distribution, sender)
    if prefix ~= PREFIX or type(message) ~= "string" or #message > 250 then return end
    local who = (sender or "?"):match("^([^%-]+)") or sender
    if who == UnitName("player") then return end
    local ver, kind, body = message:match("^(%d+)|(%a)|(.*)$")
    if not ver then return end
    others[who] = { map = addon.BlessDecode(body), t = GetTime and GetTime() or 0 }
    if kind == "H" then addon.BlessSend("U") end
    if addon.BlessingsRefresh then pcall(addon.BlessingsRefresh) end
end
if addon.RegisterComm then pcall(addon.RegisterComm, addon, PREFIX, "OnBlessSync") end

local helloPending
local function HelloSoon()
    if helloPending or not (C_Timer and C_Timer.After) then return end
    helloPending = true
    C_Timer.After(4, function() helloPending = false; addon.BlessSend("H") end)
end

-- the other paladins that are really in my group now (anyone who left is forgotten)
local function OthersNow(members)
    local out = {}
    local db = DB()
    if db and db.blessShare == false then return out end
    for _, m in ipairs(members) do
        local o = m.class == "PALADIN" and m.name and others[m.name]
        if o and m.name ~= UnitName("player") then
            -- active: alive, online and near enough to reach people with me (if not, the blessing falls back to my button)
            out[m.name] = { map = o.map, t = o.t, active = m.alive ~= false and m.connected ~= false and m.inRange ~= false }
        end
    end
    return out
end

-- one click: for every class in the group, take a blessing the other paladins are not giving it
function addon.BlessSplit()
    local db = DB()
    if not db then return false end
    local avail = addon.BlessingsAvailable()
    if #avail == 0 then return false end
    local shorts, fullOf = {}, {}
    for _, f in ipairs(avail) do local s = Short(f); shorts[#shorts + 1] = s; fullOf[s] = f end
    db.blessings = db.blessings or {}
    local changed = 0
    for _, m in ipairs(Members(avail[1])) do
        local class = m.class
        if class and not (db.blessings[class] == "none") then
            local taken = {}
            for _, o in pairs(lastOthers) do if o.map and o.map[class] then taken[o.map[class]] = true end end
            local pickShort = addon.BlessSplitFor(shorts, taken, DEFAULT[class])
            if pickShort and fullOf[pickShort] and db.blessings[class] ~= fullOf[pickShort] then
                db.blessings[class] = fullOf[pickShort]
                changed = changed + 1
            end
        end
    end
    if addon.BlessSend then addon.BlessSend("U") end
    if addon.BlessingsRefresh then addon.BlessingsRefresh() end
    return changed
end

local function Refresh()
    local db = DB()
    if not db then return end
    addon.blessWhy = nil
    if not On() then addon.blessWhy = "the panel is switched off (/lazy blessings turns it on)"
    elseif not IsPaladin() then addon.blessWhy = "you are not a paladin"
    elseif not (IsInGroup and IsInGroup() or db.blessSolo == true) then addon.blessWhy = "you are not in a group (/lazy blessings solo shows it when you are alone)" end
    if addon.blessWhy then
        if frame then frame:Hide() end
        return
    end
    if InCombatLockdown() then waiting = true; addon.blessWhy = "you are in combat, it shows after the fight"; return end
    waiting = false
    local avail = addon.BlessingsAvailable()
    if #avail == 0 then
        addon.blessWhy = "no blessing spells were found in your spellbook (/lazy blessings debug lists what it sees)"
        if frame then frame:Hide() end
        return
    end
    if not frame then frame = Build(); Place() end
    local members = Members(avail[1])
    lastOthers = OthersNow(members)
    local myName = UnitName("player")
    local function Covered(class, short) return addon.BlessCovered(class, short, myName, lastOthers) end
    local pick, bless, count = addon.BlessNext(members, avail, BuffsOf, function(class, short) return Covered(class, short) ~= nil end, addon.BlessRecently)
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
                local who = b and Covered(present[i], Short(b))
                r.coveredBy = who
                if who then
                    r.bless:SetText("|cff888888" .. Short(b) .. " (" .. who .. ")|r")           -- another paladin gives this one
                else
                    r.bless:SetText(b and Short(b) or L("none"))
                end
                r:Show()
            else
                r:Hide()
            end
        end
    end
    local hasOthers = next(lastOthers) ~= nil
    frame:SetHeight(48 + #present * 19 + (hasOthers and 22 or 0))
    -- with another paladin in the group: one click gives every class a blessing the others are not giving
    if hasOthers then
        if not frame.split then
            local sb = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            sb:SetSize(180, 18)
            sb:SetText(L("Split with the other paladins"))
            sb:SetScript("OnClick", function()
                local n = addon.BlessSplit()
                Print(n and n > 0 and string.format(L("blessings: %d classes changed so you do not repeat the other paladins"), n) or L("blessings: nothing to change, you already give different blessings"))
            end)
            sb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L("Picks, for each class, a blessing the other paladins are not giving it."), 1, 1, 1, true)
                GameTooltip:Show()
            end)
            sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            frame.split = sb
        end
        frame.split:ClearAllPoints()
        frame.split:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -48 - #present * 19)
        frame.split:Show()
    elseif frame.split then
        frame.split:Hide()
    end
    -- the button
    if pick and bless then
        -- a macro cast is the most dependable way to aim a spell at a unit from a secure button
        button:SetAttribute("type", "macro")
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext", "/cast [@" .. tostring(pick.unit) .. ",help,nodead] " .. bless)
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
        -- "everyone is blessed" is only true when somebody has a blessing chosen: with every class set to none there is nothing to do
        local assigned, covered = 0, 0
        for _, m in ipairs(members) do
            local b = addon.BlessingFor(m.class, avail)
            if b then
                if Covered(m.class, Short(b)) then covered = covered + 1 else assigned = assigned + 1 end
            end
        end
        if assigned == 0 and covered > 0 then button.text:SetText(L("the other paladins have everyone"))
        elseif assigned == 0 then button.text:SetText(L("no blessing chosen: click a class below"))
        else button.text:SetText(count > 0 and L("someone is out of range") or L("everyone is blessed")) end
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
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then HelloSoon() end       -- ask the other paladins for theirs
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
    Add("")
    Add("Sharing with other paladins: " .. ((DB() and DB().blessShare == false) and "OFF" or "on"))
    local any = false
    for name, e in pairs(lastOthers) do
        any = true
        Add("   " .. name .. " gives: " .. addon.BlessEncode(e.map))
    end
    if not any then Add("   no other paladin has told us what they give (they need Forever Lazy too)") end
    addon.ReportWindow(L("Forever Lazy: blessings"), lines)
end

-- /lazy blessings team: every paladin's blessing for every class, in one table
function addon.BlessTeam()
    local avail = addon.BlessingsAvailable()
    local members = Members(avail[1])
    local others = OthersNow(members)
    local lines = {}
    local names = { UnitName("player") }
    local rowsBy = { [UnitName("player")] = MyClaims(avail) }
    for name, o in pairs(others) do names[#names + 1] = name; rowsBy[name] = o.map end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    local seen, classes = {}, {}
    for _, m in ipairs(members) do if m.class and not seen[m.class] then seen[m.class] = true; classes[#classes + 1] = m.class end end
    lines[#lines + 1] = "Paladins: " .. table.concat(names, ", ") .. ((#names == 1) and "   (no other paladin has told us theirs)" or "")
    lines[#lines + 1] = ""
    for _, class in ipairs(classes) do
        local parts, gaps = {}, true
        for _, n in ipairs(names) do
            local b = rowsBy[n] and rowsBy[n][class]
            if b then gaps = false end
            parts[#parts + 1] = n .. ": " .. (b or "-")
        end
        lines[#lines + 1] = string.format("%-12s %s%s", ClassName(class), table.concat(parts, "    "), gaps and "     <- nobody blesses this class" or "")
    end
    addon.ReportWindow(L("Forever Lazy: paladin blessings in the group"), lines)
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "blessings" or c == "bless" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "debug" then db.blessDebug = nil; addon.blessClickDebug = true; addon.BlessingsDebug(); return true end
        if a == "on" then db.blessPanel = nil; Print(L("blessings: panel on (it shows for a paladin in a group, or when alone after /lazy blessings solo)"))
        elseif a == "off" then db.blessPanel = false; Print(L("blessings: panel off"))
        elseif a == "reset" then db.blessings = nil; Print(L("blessings: back to the usual choices (Might for fighters, Wisdom for casters)"))
        elseif a == "share off" then db.blessShare = false; Print(L("blessings: not sharing with other paladins (each paladin then casts what they chose)"))
        elseif a == "share on" or a == "share" then db.blessShare = nil; Print(L("blessings: sharing with other paladins who have Forever Lazy (the one first in the alphabet casts a blessing two paladins both chose)")); addon.BlessSend("H")
        elseif a == "split" then
            local n = addon.BlessSplit()
            Print(n and n > 0 and string.format(L("blessings: %d classes changed so you do not repeat the other paladins"), n) or L("blessings: nothing to change (no other paladin has told us theirs, or you already give different blessings)"))
        elseif a == "team" then addon.BlessTeam(); return true
        elseif a == "solo" then db.blessSolo = not db.blessSolo or nil; Print(L("blessings: the panel also shows when you are alone: ") .. tostring(db.blessSolo == true))
        else
            db.blessPanel = (db.blessPanel == false) and nil or false
            if db.blessPanel == false then Print(L("blessings: panel hidden")) else Print(L("blessings: panel on (it shows for a paladin in a group)")) end
        end
        if addon.RefreshOptions then addon.RefreshOptions() end
        local ok, err = pcall(Refresh)
        if not ok then Print(L("blessings: an error stopped the panel: ") .. tostring(err))
        elseif addon.blessWhy then Print(L("blessings: the panel is not showing because ") .. addon.blessWhy)
        elseif frame and frame:IsShown() then Print(L("blessings: the panel is showing (left side of the screen, drag its title to move it)")) end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Blessings.lua"] = true end end
