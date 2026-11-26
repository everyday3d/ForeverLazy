-- Shaman helpers (no game needed): lua tests/shaman.lua
-- First the rules, then the whole panel is built and painted on stand-in frames for a pretend shaman, so a mistake in the
-- panel code shows up here. It cannot say how it looks or whether the game gives these answers.
local now = 1000
GetTime = function() return now end
tinsert, unpack = table.insert, table.unpack
local combat = false
InCombatLockdown = function() return combat end
local class = "SHAMAN"
UnitClass = function() return class, class end
local frames, events = {}, nil
local function Frame(name)
    local f = { shown = true, attrs = {}, scripts = {}, name = name }
    frames[#frames + 1] = f
    f.SetAttribute = function(self, k, v) assert(not combat, "a secure button was changed during a fight"); self.attrs[k] = v end
    f.GetAttribute = function(self, k) return self.attrs[k] end
    f.SetText = function(self, t) self.text = t end
    f.GetText = function(self) return self.text end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.SetShown = function(self, v) self.shown = v and true or false end
    f.IsShown = function(self) return self.shown end
    f.SetScript = function(self, w, fn) self.scripts[w] = fn end
    f.HookScript = f.SetScript
    f.CreateFontString = function() return Frame() end
    f.CreateTexture = function() return Frame() end
    setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    if name then _G[name] = f end
    return f
end
CreateFrame = function(_, name) local f = Frame(name); if not name then events = events or nil end return f end
UIParent, GameTooltip = Frame(), Frame()

local known = {}
local said = {}
local db = { pos = {}, scale = 1 }
local addon = { GetDB = function() return db end, Print = function(s) said[#said + 1] = s end, SpellsKnown = function() return known end }
local where = { 0, 0, 1 }
local ns = { L = function(s) return s end, addon = addon, api = { hbd = { GetPlayerWorldPosition = function() return table.unpack(where) end } } }

local totemInfo = {}
GetTotemInfo = function(slot) local t = totemInfo[slot]; if t then return true, t[1], t[2], t[3], "icon" end return false end
local weapon = { false }
GetWeaponEnchantInfo = function() return table.unpack(weapon) end
local auras = {}
C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter) local l = auras[unit .. filter]; return l and l[i] end }
local ankhs = 2
GetItemCount = function() return ankhs end
GetSpellCooldown = function() return 0, 0 end
UnitExists = function(u) return u == "player" or u == "party1" end
UnitName = function(u) return u == "player" and "Thrall" or "Rexxar" end

assert(loadfile("ForeverLazy/Shaman.lua"))("ForeverLazy", ns)
local S = addon.Shaman

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function Said(words) for _, s in ipairs(said) do if s:find(words, 1, true) then return true end end return false end

test("a totem that vanishes early is gone, one that ran its time is expired, a replaced one is neither", function()
    local a = { name = "Searing Totem", start = 990, duration = 55 }
    assert(S.TotemEvent(a, nil, 1000) == "gone")
    assert(S.TotemEvent(a, nil, 1046) == "expired")
    assert(S.TotemEvent(a, { name = "Magma Totem" }, 1000) == nil)
    assert(S.TotemEvent(nil, nil, 1000) == nil)
end)
test("the set drops one totem a click and skips empty elements", function()
    assert(S.Sequence({ "A", "", "C" }) == "/castsequence reset=15/combat A, C")
    assert(S.Sequence({ "", "" }) == nil)
end)
test("picking a totem: mine, else the first known; none stays none; right-click goes round", function()
    local list, have = { "A", "B", "C" }, { B = true, C = true }
    assert(S.Pick(nil, list, have) == "B" and S.Pick("C", list, have) == "C" and S.Pick("A", list, have) == "B")
    assert(S.Pick("none", list, have) == nil)
    assert(S.Next("B", list, have, 1) == "C" and S.Next("C", list, have, 1) == "none" and S.Next("none", list, have, 1) == "B")
    assert(S.Next("B", list, have, -1) == "none")
end)
test("weapon buff, shield, cure and Ghost Wolf rules", function()
    assert(S.NeedsRefresh(false) and S.NeedsRefresh(true, 30) and not S.NeedsRefresh(true, 600) and not S.NeedsRefresh(true, nil))
    assert(S.CureKind({ "Magic", "Disease", "Poison" }, true, true) == "Poison")
    assert(S.CureKind({ "Disease" }, true, false) == nil)
    assert(S.WolfNudge({ ranFor = 9, since = 400 }))
    assert(not S.WolfNudge({ ranFor = 9, since = 100 }) and not S.WolfNudge({ ranFor = 9, since = 400, indoors = true }))
end)

local function Find(name) return _G[name] end
test("nothing is built until something is ticked", function()
    addon.ShamanRefresh()
    assert(not Find("ForeverLazy_Shaman"))
end)
test("the panel builds for a shaman and its buttons cast the right things", function()
    for _, s in ipairs({ "Searing Totem", "Strength of Earth Totem", "Healing Stream Totem", "Rockbiter Weapon", "Lightning Shield",
        "Reincarnation", "Cure Poison" }) do known[s] = true end
    for _, k in ipairs({ "shamTotemBar", "shamTotemRange", "shamImbue", "shamShield", "shamAnkh", "shamCure" }) do db[k] = true end
    addon.ShamanRefresh()
    assert(Find("ForeverLazy_Shaman").shown)
    assert(Find("ForeverLazy_Totem1").attrs.macrotext1 == "/cast Strength of Earth Totem")
    assert(Find("ForeverLazy_TotemSet").attrs.macrotext1 == "/castsequence reset=15/combat Strength of Earth Totem, Searing Totem, Healing Stream Totem")
    assert(Find("ForeverLazy_Imbue").attrs.macrotext1 == "/cast Rockbiter Weapon")
    assert(Find("ForeverLazy_Shield").attrs.macrotext1 == "/cast Lightning Shield")
    assert(Find("ForeverLazy_Cure2").attrs.macrotext1 == "/cast [@party1,help,nodead] Cure Poison")
    assert(Find("ForeverLazy_Cure2").attrs.macrotext2 == nil, "no Cure Disease known")
    assert(Said("low on ankhs"))
end)
test("painting during a fight changes no button, and says when a totem is out of range or destroyed", function()
    totemInfo[1] = { "Searing Totem", now, 55 }
    local tick = nil
    for _, f in ipairs(frames) do if f.scripts.OnUpdate and f.scripts.OnEvent == nil then end end
    for _, f in ipairs(frames) do if f.scripts.OnUpdate then tick = f.scripts.OnUpdate end end
    combat = true
    auras["playerHELPFUL"] = { { name = "Lightning Shield", applications = 3, expirationTime = now + 500 } }
    auras["party1HARMFUL"] = { { name = "Venom", dispelName = "Poison", expirationTime = now + 10 } }
    weapon = { true, 400000 }
    tick(nil, 1)
    where = { 50, 0, 1 }
    tick(nil, 1)
    assert(Said("out of range of your Searing Totem"), "no range warning")
    totemInfo[1] = nil
    now = now + 5
    tick(nil, 1)
    assert(Said("Searing Totem is gone"), "no gone warning")
    addon.ShamanRefresh()                 -- asked for during the fight: it must wait, not touch the buttons
    combat = false
end)
test("a paladin sees no panel", function()
    class = "PALADIN"
    addon.ShamanRefresh()
    assert(not Find("ForeverLazy_Shaman").shown)
    class = "SHAMAN"
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
