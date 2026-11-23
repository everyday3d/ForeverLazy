-- Gear scoring: how much better is an item than what I wear in its slot, for my class and spec?
--   /lazy gear               which spec and weights I am scored with
--   /lazy gear stats [item]  the stat names the game gives for an item (a link, the item under the mouse, or my worn gear)
-- Stat priorities per spec come from the WoW Forever pre-raid priority list (WoWSims stat weights), turned into weights:
-- the first stat counts 1.0, the next 0.8, 0.65, 0.5 and so on. Hit counts only until the hit cap is reached. Spell
-- penetration is capped low on purpose: it tops the raid lists but does nothing for levelling.
-- addon.GearGain(link, slots, equipLoc, ilvl) -> gain, note   (nil when the item gives nothing to compare)
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

--------------------------------------------------------------------------------
-- The game's stat names, as short keys
--------------------------------------------------------------------------------
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI",
    ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP", ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "FAP",
    ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP",
    ITEM_MOD_HEALING_DONE_SHORT = "HEAL", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
    ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "CRIT",
    ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT", ITEM_MOD_HIT_RANGED_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "HIT",
    ITEM_MOD_HASTE_RATING_SHORT = "HASTE", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE", ITEM_MOD_HASTE_RANGED_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = "HASTE",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "EXPERTISE", ITEM_MOD_SPELL_PENETRATION_SHORT = "SPELLPEN",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF", ITEM_MOD_DODGE_RATING_SHORT = "DODGE", ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
    ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK", ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVAL",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS", RESISTANCE0_NAME = "ARMOR",
}
addon.GearStatKeys = STAT_KEYS

--------------------------------------------------------------------------------
-- What each kind of character needs besides its priority list
--------------------------------------------------------------------------------
local BASE = {
    melee  = { AP = 0.5, FAP = 0.5, STA = 0.3, STR = 0.7, AGI = 0.5, DPS = 4, ARMOR = 0.015 },
    ranged = { AP = 0.4, RAP = 0.5, STA = 0.3, AGI = 0.4, INT = 0.15, DPS = 6, ARMOR = 0.01 },
    caster = { SP = 0.6, INT = 0.4, SPI = 0.2, STA = 0.3, MP5 = 0.4, DPS = 2, ARMOR = 0.005 },
    healer = { HEAL = 0.8, SP = 0.5, INT = 0.5, SPI = 0.3, STA = 0.25, MP5 = 0.6, DPS = 1, ARMOR = 0.005 },
    tank   = { STA = 0.5, ARMOR = 0.04, STR = 0.2, AGI = 0.3, DPS = 3, BLOCKVAL = 0.3 },
}
local RANK = { 1.0, 0.8, 0.65, 0.5, 0.4, 0.3, 0.25 }
-- these never count much for levelling, wherever the raid lists put them
local CEILING = { SPELLPEN = 0.15, EXPERTISE = 0.7 }

-- the hit cap each kind of character wants (percent)
local CAP = { melee = 8, ranged = 8, tank = 8, caster = 17 }

local LABEL = { melee = "melee", ranged = "ranged", caster = "caster", healer = "healer", tank = "tank" }

--------------------------------------------------------------------------------
-- The specs: class -> talent tree number -> { name, kind, priority list }
--------------------------------------------------------------------------------
local SPECS = {
    WARRIOR = {
        { "Arms", "melee", { "HIT", "CRIT", "STR", "AGI", "EXPERTISE", "HASTE" } },
        { "Fury", "melee", { "EXPERTISE", "CRIT", "STR", "HASTE", "AGI", "HIT" } },
        { "Protection", "tank", { "DEF", "EXPERTISE", "STA", "BLOCKVAL", "AGI", "STR" } },
    },
    PALADIN = {
        { "Holy", "healer", { "HEAL", "MP5", "CRIT", "HASTE", "INT", "SPI" } },
        { "Protection", "tank", { "DEF", "BLOCK", "STA", "DODGE", "PARRY", "AGI" } },
        { "Retribution", "melee", { "HIT", "EXPERTISE", "CRIT", "STR", "SP", "AGI" } },
    },
    HUNTER = {
        { "Beast Mastery", "ranged", { "HIT", "CRIT", "AGI", "HASTE" } },
        { "Marksmanship", "ranged", { "CRIT", "HIT", "AGI", "HASTE" } },
        { "Survival", "ranged", { "CRIT", "HIT", "AGI", "HASTE" } },
    },
    ROGUE = {
        { "Assassination", "melee", { "HIT", "EXPERTISE", "AGI", "CRIT", "HASTE", "STR" } },
        { "Combat", "melee", { "EXPERTISE", "HIT", "AGI", "HASTE", "CRIT", "STR" } },
        { "Subtlety", "melee", { "EXPERTISE", "HIT", "AGI", "CRIT", "HASTE", "STR" } },
    },
    PRIEST = {
        { "Discipline", "healer", { "HEAL", "CRIT", "MP5", "INT", "SPI", "HASTE" } },
        { "Holy", "healer", { "HEAL", "MP5", "HASTE", "INT", "SPI", "CRIT" } },
        { "Shadow", "caster", { "HIT", "SP", "CRIT", "HASTE", "SPI" } },
    },
    SHAMAN = {
        { "Elemental", "caster", { "HASTE", "HIT", "SP", "CRIT", "INT" } },
        { "Enhancement", "melee", { "HIT", "EXPERTISE", "HASTE", "CRIT", "STR", "AGI" } },
        { "Restoration", "healer", { "HEAL", "MP5", "HASTE", "CRIT", "INT", "SPI" } },
    },
    MAGE = {
        { "Arcane", "caster", { "HASTE", "HIT", "SP", "INT", "CRIT" } },
        { "Fire", "caster", { "HIT", "SP", "CRIT", "HASTE", "INT" } },
        { "Frost", "caster", { "HIT", "HASTE", "SP", "CRIT", "INT" } },
    },
    WARLOCK = {
        { "Affliction", "caster", { "SP", "CRIT", "HIT", "INT", "HASTE" } },
        { "Demonology", "caster", { "HIT", "SP", "CRIT", "HASTE", "INT" } },
        { "Destruction", "caster", { "HIT", "SP", "CRIT", "INT", "HASTE" } },
    },
    DRUID = {
        { "Balance", "caster", { "HIT", "SP", "HASTE", "CRIT", "INT" } },
        { "Feral", "melee", { "AGI", "STR", "HIT", "CRIT", "EXPERTISE", "HASTE" } },
        { "Restoration", "healer", { "HEAL", "MP5", "SPI", "INT", "HASTE", "CRIT" } },
    },
}
-- the same, for a spec I pick by hand in Options (the old role list)
local ROLE_SPEC = {
    str_melee = { "Strength melee", "melee", { "STR", "HIT", "CRIT", "AGI" } },
    agi_melee = { "Agility melee", "melee", { "AGI", "HIT", "CRIT", "STR" } },
    hunter    = { "Hunter", "ranged", { "HIT", "CRIT", "AGI" } },
    caster    = { "Caster", "caster", { "HIT", "SP", "CRIT", "INT" } },
    healer    = { "Healer", "healer", { "HEAL", "MP5", "INT", "SPI" } },
    tank      = { "Tank", "tank", { "DEF", "STA", "BLOCK", "DODGE", "PARRY", "AGI" } },
}
-- before any talent point is spent (and for a class that has no tree named here)
local DEFAULT_TREE = { WARRIOR = 1, PALADIN = 3, HUNTER = 2, ROGUE = 2, PRIEST = 3, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 2 }

-- turn a priority list into weights
local function Weights(kind, priority)
    local w = {}
    for stat, v in pairs(BASE[kind]) do w[stat] = v end
    for i, stat in ipairs(priority) do
        local r = RANK[i] or 0.2
        if CEILING[stat] then r = math.min(r, CEILING[stat]) end
        if not w[stat] or r > w[stat] then w[stat] = r end
    end
    return w
end

local cacheKey, cached
-- my spec: { name, kind, weights, cap, forced }
function addon.GearSpec()
    local db = DB()
    local pick = db and db.rewardRole
    local class = select(2, UnitClass("player"))
    local tree
    if not (pick and pick ~= "auto" and ROLE_SPEC[pick]) and SPECS[class] and GetNumTalentTabs and GetTalentTabInfo then
        local bestPts = 0
        for i = 1, (GetNumTalentTabs() or 0) do
            local ok, _, _, pts = pcall(GetTalentTabInfo, i)
            pts = ok and tonumber(pts) or 0
            if pts > bestPts then tree, bestPts = i, pts end
        end
    end
    local key = tostring(pick) .. "|" .. tostring(class) .. "|" .. tostring(tree)
    if key == cacheKey and cached then return cached end
    local def, forced
    if pick and pick ~= "auto" and ROLE_SPEC[pick] then def, forced = ROLE_SPEC[pick], true
    else
        local list = SPECS[class]
        def = list and (list[tree or DEFAULT_TREE[class] or 1])
        if not def then def = ROLE_SPEC.str_melee end
    end
    local name, kind, priority = def[1], def[2], def[3]
    cached = { name = name, kind = kind, priority = priority, weights = Weights(kind, priority), cap = CAP[kind] or 8, forced = forced, class = class }
    cacheKey = key
    return cached
end

--------------------------------------------------------------------------------
-- Scoring
--------------------------------------------------------------------------------
-- how much hit I still need: 1 while below the cap, close to 0 once I am at it
local function HitFactor(spec)
    if not (GetCombatRating and GetCombatRatingBonus) then return 1 end
    local id = (spec.kind == "caster" or spec.kind == "healer") and _G.CR_HIT_SPELL or (spec.kind == "ranged" and _G.CR_HIT_RANGED or _G.CR_HIT_MELEE)
    if not id then return 1 end
    local ok, pct = pcall(GetCombatRatingBonus, id)
    if not ok or type(pct) ~= "number" then return 1 end
    local mod = 0
    if spec.kind == "caster" or spec.kind == "healer" then
        if GetSpellHitModifier then mod = tonumber(GetSpellHitModifier()) or 0 end
    elseif GetHitModifier then mod = tonumber(GetHitModifier()) or 0 end
    local have = pct + mod
    if have >= spec.cap then return 0.1 end
    return 1
end

--------------------------------------------------------------------------------
-- Reading an item's stats: the game's own table when it gives one, else the words on the item's tooltip
--------------------------------------------------------------------------------
-- tooltip line patterns (English): { pattern, key }; the first number in the pattern is the amount
local PATTERNS = {
    { "^%+(%d+) Strength", "STR" }, { "^%+(%d+) Agility", "AGI" }, { "^%+(%d+) Stamina", "STA" },
    { "^%+(%d+) Intellect", "INT" }, { "^%+(%d+) Spirit", "SPI" },
    { "^(%d+) Armor", "ARMOR" }, { "%((%d+%.?%d*) damage per second%)", "DPS" },
    { "^%+(%d+) Spell Damage", "SP" }, { "^%+(%d+) Healing", "HEAL" },
    { "^%+(%d+) Attack Power", "AP" }, { "^%+(%d+) Haste", "HASTE" }, { "^%+(%d+) Critical Strike", "CRIT" }, { "^%+(%d+) Hit", "HIT" },
    { "attack power by (%d+) in Cat", "FAP" },
    { "ranged attack power by (%d+)", "RAP" },
    { "[Ii]ncreases attack power by (%d+)", "AP" },
    { "magical spells and effects by up to (%d+)", "SP" },
    { "damage done by %a+ spells and effects by up to (%d+)", "SP" },
    { "healing done by spells and effects by up to (%d+)", "HEAL" }, { "healing done by up to (%d+)", "HEAL" },
    { "hit rating by (%d+)", "HIT" }, { "chance to hit by (%d+)", "HIT" },
    { "critical strike rating by (%d+)", "CRIT" }, { "critical strike chance by (%d+)", "CRIT" },
    { "spell critical strike rating by (%d+)", "CRIT" }, { "haste rating by (%d+)", "HASTE" },
    { "expertise rating by (%d+)", "EXPERTISE" }, { "spell penetration by (%d+)", "SPELLPEN" },
    { "defense rating by (%d+)", "DEF" }, { "dodge rating by (%d+)", "DODGE" }, { "parry rating by (%d+)", "PARRY" },
    { "block rating by (%d+)", "BLOCK" }, { "block value of your shield by (%d+)", "BLOCKVAL" },
    { "(%d+) mana per 5 sec", "MP5" },
}

-- lines of text -> { KEY = amount }
function addon.GearParseLines(lines)
    local out, any, unmatched = {}, false, {}
    for _, raw in ipairs(lines or {}) do
        local line = tostring(raw):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local found
        for _, pat in ipairs(PATTERNS) do
            local n = line:match(pat[1])
            if n then
                out[pat[2]] = (out[pat[2]] or 0) + tonumber(n)
                any, found = true, true
                break
            end
        end
        -- a line that looks like a stat but no pattern knew it: shown by /lazy gear stats so the patterns can be completed
        if not found and (line:find("^%+%d") or line:find("^Equip:") or line:find("^Use:") or line:find("^Chance on")) then unmatched[#unmatched + 1] = line end
    end
    return any and out or nil, unmatched
end

local scanTip
local function ScanLines(link)
    if not (CreateFrame and link) then return nil end
    if not scanTip then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "ForeverLazyGearScan", nil, "GameTooltipTemplate")
        if not ok or not tip then return nil end
        scanTip = tip
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    if not pcall(scanTip.SetHyperlink, scanTip, link) then return nil end
    local lines = {}
    for i = 1, (scanTip:NumLines() or 0) do
        local fs = _G["ForeverLazyGearScanTextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText()
        if text then lines[#lines + 1] = text end
    end
    return lines
end

local warnedLanguage
local statCache = {}
function addon.GearClearStatCache() statCache = {} end
-- { KEY = amount }, where it came from ("table" or "tooltip"), and the game's stat names we do not score
function addon.GearItemStats(link)
    if not link then return nil end
    local hit = statCache[link]
    if hit then return hit.stats, hit.source, hit.unknown end
    local raw
    if GetItemStats then local ok, s = pcall(GetItemStats, link); if ok and type(s) == "table" and next(s) then raw = s end end
    if not raw and C_Item and C_Item.GetItemStats then
        local ok, s = pcall(C_Item.GetItemStats, link)
        if ok and type(s) == "table" and next(s) then raw = s end
    end
    local stats, source, unknown
    if raw then
        stats, source, unknown = {}, "table", {}
        for name, v in pairs(raw) do
            local key = STAT_KEYS[name]
            if key then stats[key] = (stats[key] or 0) + (tonumber(v) or 0) else unknown[#unknown + 1] = name end
        end
    else
        local lines = ScanLines(link)
        local un
        stats, un = addon.GearParseLines(lines)
        if not stats and not warnedLanguage and GetLocale and GetLocale() ~= "enUS" then
            warnedLanguage = true
            Print(L("gear advisor: item stats can only be read from the tooltip in English, so on this game language it compares item levels when the game gives no stat table"))
        end
        source = "tooltip"
        unknown = {}
        for _, l in ipairs(un or {}) do unknown[#unknown + 1] = "line not understood: " .. l end
    end
    if stats then statCache[link] = { stats = stats, source = source, unknown = unknown } end    -- only kept once there is something (item data may still be loading)
    return stats, source, unknown
end

-- the stat points of an item for a spec (nil when no stats can be read)
function addon.GearScore(link, spec)
    local stats = addon.GearItemStats(link)
    if not stats then return nil end
    spec = spec or addon.GearSpec()
    local w = spec.weights
    local hitFactor = HitFactor(spec)
    local score = 0
    for key, v in pairs(stats) do
        local weight = w[key]
        if weight then
            if key == "HIT" then weight = weight * hitFactor end
            score = score + v * weight
        end
    end
    return score
end
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}
addon.GearSlots = SLOTS

local function WornLevel(slots)
    local lowest
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        local lvl = 0
        if link then lvl = select(4, GetItemInfo(link)) or 0 end
        if not lowest or lvl < lowest then lowest = lvl end
    end
    return lowest or 0
end

-- how much better is this item than what I wear in its slot, for my spec? (nil when it is not gear that can be compared)
function addon.GearGain(link, slots, equipLoc, ilvl)
    if not link then return nil end
    if not (slots and equipLoc) then
        local _, _, _, il, _, _, _, _, loc = GetItemInfo(link)
        equipLoc = equipLoc or loc
        ilvl = ilvl or il
        slots = slots or SLOTS[equipLoc or ""]
    end
    if not slots then return nil end
    local spec = addon.GearSpec()
    if spec.kind == "tank" and equipLoc == "INVTYPE_2HWEAPON" then return nil end          -- a tank wants a one-hander and shield
    local mine = addon.GearScore(link, spec)
    if not mine then
        local gain = (ilvl or 0) - WornLevel(slots)                                          -- no stat data on this client
        return gain, gain > 0 and string.format("likely upgrade (item level +%d)", gain) or nil
    end
    local worn, wornLink
    if equipLoc == "INVTYPE_2HWEAPON" then
        -- a two-hander takes the place of the main hand AND the off hand
        local a = GetInventoryItemLink("player", 16)
        local b = GetInventoryItemLink("player", 17)
        worn = (a and addon.GearScore(a, spec) or 0) + (b and addon.GearScore(b, spec) or 0)
        wornLink = a
    else
        for _, slot in ipairs(slots) do
            local l = GetInventoryItemLink("player", slot)
            local s = l and addon.GearScore(l, spec) or 0
            if not worn or s < worn then worn, wornLink = s, l end
        end
    end
    local gain = mine - (worn or 0)
    return gain, gain > 0 and string.format("best for your %s %s%s (+%.0f stat points over what you wear)", spec.name, LABEL[spec.kind] or spec.kind,
        spec.forced and ", as you set it" or "", gain) or nil, wornLink, worn or 0
end

--------------------------------------------------------------------------------
-- /lazy gear
--------------------------------------------------------------------------------
-- the stats of one item, as text (a name the scorer does not know is marked)
local function StatsText(link)
    local name = GetItemInfo and GetItemInfo(link) or tostring(link)
    local stats, source, unknown = addon.GearItemStats(link)
    if not stats then return tostring(name) .. ": no stats could be read (the game's table is empty and no stat words were found on its tooltip)" end
    local keys = {}
    for k in pairs(stats) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = string.format("%s = %s", k, tostring(stats[k])) end
    for _, k in ipairs(unknown or {}) do parts[#parts + 1] = (k:find("^line not understood") and k or string.format("%s   <-- NOT SCORED", k)) end
    return tostring(name) .. "   [read from the " .. tostring(source) .. "]\n    " .. table.concat(parts, "\n    ")
end
-- the answer goes into a window you can select and copy from (Ctrl-A, Ctrl-C), not into chat
local function ShowPopup(title, lines)
    local text = table.concat(lines, "\n")
    if addon.ShowTextPopup then addon.ShowTextPopup(title, text)
    else for _, l in ipairs(lines) do Print(l) end end
end
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "gear" then
        local a = ((rest or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        if a:lower():find("^stats") then
            local arg = a:sub(6):gsub("^%s+", "")
            local link = arg:match("|H(item:[^|]+)|h") and arg:match("(|c%x+|H.-|h.-|h|r)") or nil
            local lines = {}
            local spec = addon.GearSpec()
            lines[#lines + 1] = string.format("Scoring as: %s (%s)%s", spec.name, spec.kind, spec.forced and ", set by hand" or ", from your talents")
            lines[#lines + 1] = "Stat order: " .. table.concat(spec.priority, " > ")
            lines[#lines + 1] = ""
            if link then
                lines[#lines + 1] = StatsText(link)
            else
                local _, tipLink = GameTooltip and GameTooltip.GetItem and GameTooltip:GetItem()
                if tipLink then
                    lines[#lines + 1] = StatsText(tipLink)
                else
                    lines[#lines + 1] = "The stats read from the gear you wear (a name marked NOT SCORED is missing from the scorer):"
                    lines[#lines + 1] = ""
                    for slot = 1, 18 do
                        local l = GetInventoryItemLink("player", slot)
                        if l then lines[#lines + 1] = StatsText(l) end
                    end
                end
            end
            ShowPopup("Forever Lazy: gear stats", lines)
            return true
        end        local spec = addon.GearSpec()
        local top = {}
        for i, s in ipairs(spec.priority) do top[#top + 1] = s end
        Print(string.format(L("gear: scoring as %s %s%s. Stat order: %s. Hit cap %d%%."), spec.name, LABEL[spec.kind] or spec.kind,
            spec.forced and " (set by hand in Options)" or " (from your talents)", table.concat(top, " > "), spec.cap))
        Print(L("  /lazy gear stats shows the stat names the game gives for your gear (to check nothing is missed)."))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Gear.lua"] = true end end
