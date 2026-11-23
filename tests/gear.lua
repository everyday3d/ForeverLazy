-- Offline tests for the gear scorer (no game needed).
--   lua tests/gear.lua
local root = (arg and arg[0] or "tests/gear.lua"):gsub("[/\\]tests[/\\]gear%.lua$", ""):gsub("^tests[/\\]gear%.lua$", ".")

local db = { rewardRole = "auto" }
local addon = { Print = function() end, GetDB = function() return db end }
local ns = { addon = addon }
ns.L = function(t) return t end

-- stand-ins for the game ---------------------------------------------------------------------------------
local class, tabs = "MAGE", { 0, 0, 31 }
function UnitClass() return "Mage", class end
function GetNumTalentTabs() return #tabs end
function GetTalentTabInfo(i) return "tab" .. i, "icon", tabs[i] end
local items = {}       -- link -> { stats = {...}, loc = "INVTYPE_...", ilvl = n }
function GetItemStats(link) return items[link] and items[link].stats end
function GetItemInfo(link) local it = items[link]; if not it then return nil end return link, link, 1, it.ilvl or 10, 1, "", "", 1, it.loc end
local worn = {}
function GetInventoryItemLink(_, slot) return worn[slot] end
CR_HIT_MELEE, CR_HIT_SPELL, CR_HIT_RANGED = 6, 8, 7
local hitBonus = 0
function GetCombatRatingBonus() return hitBonus end
function GetCombatRating() return 0 end
function GetHitModifier() return 0 end
function GetSpellHitModifier() return 0 end

assert(loadfile(root .. "/ForeverLazy/Gear.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "values differ") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end
local function gt(a, b, msg) if not (a > b) then error((msg or "not greater") .. ": " .. tostring(a) .. " vs " .. tostring(b), 2) end end

local function reset(c, t) class, tabs = c, t; worn = {}; items = {}; hitBonus = 0; db.rewardRole = "auto"; addon.GearClearStatCache() end

test("the spec comes from the talent tree with the most points", function()
    reset("PALADIN", { 3, 31, 17 })
    eq(addon.GearSpec().name, "Protection"); eq(addon.GearSpec().kind, "tank")
    tabs = { 31, 2, 0 }
    eq(addon.GearSpec().name, "Holy"); eq(addon.GearSpec().kind, "healer")
end)

test("with no talent points a class gets its usual levelling spec", function()
    reset("HUNTER", { 0, 0, 0 })
    eq(addon.GearSpec().kind, "ranged")
    reset("DRUID", { 0, 0, 0 })
    eq(addon.GearSpec().name, "Feral")
end)

test("a spell power item beats a strength item for a mage", function()
    reset("MAGE", { 0, 0, 31 })
    items.sp = { stats = { ITEM_MOD_SPELL_POWER_SHORT = 20, ITEM_MOD_INTELLECT_SHORT = 8 }, loc = "INVTYPE_CHEST" }
    items.str = { stats = { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 8 }, loc = "INVTYPE_CHEST" }
    gt(addon.GearScore("sp"), addon.GearScore("str"))
end)

test("an upgrade is a positive gain, a downgrade is not", function()
    reset("WARRIOR", { 31, 0, 0 })
    items.old = { stats = { ITEM_MOD_STRENGTH_SHORT = 5 }, loc = "INVTYPE_LEGS" }
    items.better = { stats = { ITEM_MOD_STRENGTH_SHORT = 12, ITEM_MOD_STAMINA_SHORT = 6 }, loc = "INVTYPE_LEGS" }
    items.worse = { stats = { ITEM_MOD_STRENGTH_SHORT = 2 }, loc = "INVTYPE_LEGS" }
    worn[7] = "old"
    gt(addon.GearGain("better"), 0)
    local g, note = addon.GearGain("worse")
    assert(g < 0 and note == nil, "a downgrade must give no note")
end)

test("a ring is compared with the weaker of the two worn", function()
    reset("ROGUE", { 0, 31, 0 })
    items.a = { stats = { ITEM_MOD_AGILITY_SHORT = 10 }, loc = "INVTYPE_FINGER" }
    items.b = { stats = { ITEM_MOD_AGILITY_SHORT = 2 }, loc = "INVTYPE_FINGER" }
    items.new = { stats = { ITEM_MOD_AGILITY_SHORT = 6 }, loc = "INVTYPE_FINGER" }
    worn[11], worn[12] = "a", "b"
    gt(addon.GearGain("new"), 0)
end)

test("a two-hander is compared with main hand plus off hand", function()
    reset("WARRIOR", { 31, 0, 0 })
    items.mh = { stats = { ITEM_MOD_STRENGTH_SHORT = 10 }, loc = "INVTYPE_WEAPON" }
    items.oh = { stats = { ITEM_MOD_STRENGTH_SHORT = 10 }, loc = "INVTYPE_WEAPON" }
    items.big = { stats = { ITEM_MOD_STRENGTH_SHORT = 15 }, loc = "INVTYPE_2HWEAPON" }
    worn[16], worn[17] = "mh", "oh"
    assert(addon.GearGain("big") < 0, "15 strength is worse than 10 + 10")
    items.huge = { stats = { ITEM_MOD_STRENGTH_SHORT = 30 }, loc = "INVTYPE_2HWEAPON" }
    gt(addon.GearGain("huge"), 0)
end)

test("a tank never wants a two-hander", function()
    reset("WARRIOR", { 0, 0, 31 })
    items.big = { stats = { ITEM_MOD_STRENGTH_SHORT = 99 }, loc = "INVTYPE_2HWEAPON" }
    eq(addon.GearGain("big"), nil)
end)

test("hit stops counting once the cap is reached", function()
    reset("MAGE", { 0, 0, 31 })
    items.hit = { stats = { ITEM_MOD_HIT_RATING_SHORT = 20 }, loc = "INVTYPE_HEAD" }
    hitBonus = 0
    local before = addon.GearScore("hit")
    hitBonus = 17
    local after = addon.GearScore("hit")
    gt(before, after * 5, "hit at the cap should be worth far less")
end)

test("spell penetration is not worth much for levelling", function()
    reset("MAGE", { 31, 0, 0 })
    items.pen = { stats = { ITEM_MOD_SPELL_PENETRATION_SHORT = 20 }, loc = "INVTYPE_HEAD" }
    items.sp = { stats = { ITEM_MOD_SPELL_POWER_SHORT = 20 }, loc = "INVTYPE_HEAD" }
    gt(addon.GearScore("sp"), addon.GearScore("pen") * 3)
end)

test("a role set by hand overrides the talents", function()
    reset("MAGE", { 0, 0, 31 })
    db.rewardRole = "tank"
    local s = addon.GearSpec()
    eq(s.kind, "tank"); eq(s.forced, true)
end)

test("an item the game gives no stats for falls back to item level", function()
    reset("MAGE", { 0, 0, 31 })
    items.plain = { loc = "INVTYPE_HEAD", ilvl = 30 }
    items.oldhat = { stats = { ITEM_MOD_INTELLECT_SHORT = 5 }, loc = "INVTYPE_HEAD", ilvl = 20 }
    worn[1] = "oldhat"
    local g = addon.GearGain("plain")
    eq(g, 10)
end)

test("stats are read from tooltip words when the game gives no table", function()
    local s = addon.GearParseLines({
        "Veteran's Silvered Chain Helm", "Binds when equipped", "Head   Mail", "232 Armor",
        "|cffffffff+8 Strength|r", "+11 Stamina", "Requires Level 28",
        "Equip: Increases attack power by 20.", "Equip: Improves hit rating by 9.", "Equip: Restores 4 mana per 5 sec.",
    })
    eq(s.STR, 8); eq(s.STA, 11); eq(s.ARMOR, 232); eq(s.AP, 20); eq(s.HIT, 9); eq(s.MP5, 4)
end)

test("weapon damage per second and feral attack power are read", function()
    local w = addon.GearParseLines({ "Arced War Axe", "One-Hand   Axe", "(14.2 damage per second)" })
    eq(w.DPS, 14.2)
    local f = addon.GearParseLines({ "Equip: Increases attack power by 40 in Cat, Bear, Dire Bear, and Moonkin forms." })
    eq(f.FAP, 40); eq(f.AP, nil)
end)

test("lines with no stats give nothing", function()
    eq(addon.GearParseLines({ "Squire's Shirt", "Shirt", "Requires Level 5" }), nil)
end)

test("a stat name we do not know is ignored", function()
    reset("MAGE", { 0, 0, 31 })
    items.odd = { stats = { ITEM_MOD_SOMETHING_NEW_SHORT = 50, ITEM_MOD_SPELL_POWER_SHORT = 10 }, loc = "INVTYPE_HEAD" }
    items.clean = { stats = { ITEM_MOD_SPELL_POWER_SHORT = 10 }, loc = "INVTYPE_HEAD" }
    eq(addon.GearScore("odd"), addon.GearScore("clean"))
end)

-- the gear advisor: when is an item flagged as an upgrade? ----------------------------------------------------
local frameMT = { __index = function() return function() end end }
function CreateFrame() return setmetatable({}, frameMT) end
UIParent = setmetatable({}, frameMT)
GameTooltip = setmetatable({}, frameMT)
local equippable, usable, myLevel = true, true, 30
function IsEquippableItem() return equippable end
function IsUsableItem() return usable end
function UnitLevel() return myLevel end
function GetItemInfo(link) local it = items[link]; if not it then return nil end return link, link, 1, it.ilvl or 10, it.minLevel or 1, "", "", 1, it.loc end
assert(loadfile(root .. "/ForeverLazy/GearAdvisor.lua"))("ForeverLazy", ns)

local function adv(c, t) reset(c, t); equippable, usable, myLevel = true, true, 30 end

test("a clear upgrade is flagged, with what it replaces", function()
    adv("WARRIOR", { 31, 0, 0 })
    items.old = { stats = { ITEM_MOD_STRENGTH_SHORT = 5 }, loc = "INVTYPE_LEGS" }
    items.new = { stats = { ITEM_MOD_STRENGTH_SHORT = 15 }, loc = "INVTYPE_LEGS" }
    worn[7] = "old"
    local up = addon.GearUpgrade("new")
    assert(up and up.gain > 0 and up.over == "old", "should be an upgrade over the old legs")
end)

test("a tiny gain is not flagged", function()
    adv("WARRIOR", { 31, 0, 0 })
    items.old = { stats = { ITEM_MOD_STRENGTH_SHORT = 100 }, loc = "INVTYPE_LEGS" }
    items.same = { stats = { ITEM_MOD_STRENGTH_SHORT = 101 }, loc = "INVTYPE_LEGS" }
    worn[7] = "old"
    eq(addon.GearUpgrade("same"), nil)
end)

test("an item I cannot use or equip yet is not flagged", function()
    adv("WARRIOR", { 31, 0, 0 })
    items.big = { stats = { ITEM_MOD_STRENGTH_SHORT = 50 }, loc = "INVTYPE_LEGS" }
    usable = false
    eq(addon.GearUpgrade("big"), nil)
    adv("WARRIOR", { 31, 0, 0 })
    items.big = { stats = { ITEM_MOD_STRENGTH_SHORT = 50 }, loc = "INVTYPE_LEGS", minLevel = 45 }
    eq(addon.GearUpgrade("big"), nil)
end)

test("an empty slot makes any usable item an upgrade", function()
    adv("MAGE", { 0, 0, 31 })
    items.hat = { stats = { ITEM_MOD_SPELL_POWER_SHORT = 12 }, loc = "INVTYPE_HEAD" }
    assert(addon.GearUpgrade("hat"), "an item for an empty slot is an upgrade")
end)

print(string.format("\n%d passed, %d failed (with the advisor)", passed, failed))
if failed > 0 then os.exit(1) end