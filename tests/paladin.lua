-- Paladin helpers (no game needed): lua tests/paladin.lua
-- First the rules, then the whole panel is built and painted on stand-in frames for a pretend paladin, so a mistake in the
-- panel code shows up here. It cannot say how it looks or whether the game gives these answers.
local now = 1000
GetTime = function() return now end
tinsert, unpack = table.insert, table.unpack
local combat = false
InCombatLockdown = function() return combat end
local class = "PALADIN"
UnitClass = function() return class, class end
local frames = {}
local function Frame(name)
    local f = { shown = true, attrs = {}, scripts = {}, name = name }
    frames[#frames + 1] = f
    f.SetAttribute = function(self, k, v) assert(not combat, "a secure button was changed during a fight"); self.attrs[k] = v end
    f.GetAttribute = function(self, k) return self.attrs[k] end
    f.SetText = function(self, t) self.text = t end
    f.GetText = function(self) return self.text end
    f.SetColorTexture = function(self, r, g, b) self.color = { r, g, b } end
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
local refs = {}
SecureHandlerSetFrameRef = function(owner, key, other) refs[owner] = refs[owner] or {}; refs[owner][key] = other end
CreateFrame = function(_, name, parent)
    local f = Frame(name)
    f.parent = parent
    f.GetParent = function(self) return self.parent end
    f.GetFrameRef = function(self, key) return refs[self] and refs[self][key] end
    f.RegisterAutoHide = function(self, s) self.autoHide = s end
    f.UnregisterAutoHide = function(self) self.autoHide = nil end
    f.AddToAutoHide = function(self, other) self.alsoOver = other end
    return f
end
UIParent, GameTooltip = Frame(), Frame()

local known, said = {}, {}
local db = { pos = {} }
local addon = { GetDB = function() return db end, Print = function(s) said[#said + 1] = s end, SpellsKnown = function() return known end }
local ns = { L = function(s) return s end, addon = addon }
local auras = {}
C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter) local l = auras[unit .. filter]; return l and l[i] end }
UnitExists = function(u) return u == "player" or u == "party1" end
UnitName = function(u) return u == "player" and "Tank" or "Rexxar" end

assert(loadfile("ForeverLazy/Paladin.lua"))("ForeverLazy", ns)
local P = addon.Paladin

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function Said(words) for _, s in ipairs(said) do if s:find(words, 1, true) then return true end end return false end
local function Find(name) return _G[name] end
local function Events()
    for _, f in ipairs(frames) do if f.scripts.OnUpdate and f.scripts.OnEvent then return f end end
end
local function Colour(button) return button.bg.color[1] > 0.5 and "red" or (button.bg.color[2] > 0.5 and "green" or "other") end

test("picking: mine when I still know it, else the first I know", function()
    local list, have = { "A", "B", "C" }, { B = true, C = true }
    assert(P.Pick(nil, list, have) == "B" and P.Pick("C", list, have) == "C" and P.Pick("A", list, have) == "B")
    assert(P.Pick(nil, list, {}) == nil)
    assert(table.concat(P.MenuList(list, have), ",") == "B,C")
end)

test("another paladin's aura does not count as mine, and a seal about to run out needs doing again", function()
    local theirs = { { name = "Devotion Aura", source = "party1" } }
    assert(P.Active(theirs, { "Devotion Aura" }, true) == nil)
    assert(P.Active(theirs, { "Devotion Aura" }, false))
    assert(P.Active({ { name = "Devotion Aura", source = "player" } }, { "Devotion Aura" }, true))
    assert(P.Active({ { name = "Devotion Aura" } }, { "Devotion Aura" }, true), "no source given: count it")
    assert(P.Needs(nil, 5) and P.Needs({ left = 3 }, 5) and not P.Needs({ left = 20 }, 5) and not P.Needs({}, 0))
end)

test("cleanse takes poison first, then disease, then magic, and Purify cannot take magic", function()
    assert(P.CleanseKind({ "Magic", "Disease", "Poison" }, true, true) == "Poison")
    assert(P.CleanseKind({ "Magic", "Disease" }, true, true) == "Disease")
    assert(P.CleanseKind({ "Magic" }, true, true) == "Magic")
    assert(P.CleanseKind({ "Magic" }, true, false) == nil)
    assert(P.CleanseKind({ "Curse" }, true, true) == nil)
    assert(P.CleanseKind({ "Poison" }, false, false) == nil)
end)

test("everything is off to begin with: nothing is built", function()
    addon.PaladinRefresh()
    assert(not Find("ForeverLazy_Paladin"))
end)

test("other classes see nothing, even with everything ticked", function()
    for _, k in ipairs({ "palSeal", "palAura", "palFury", "palCleanse" }) do db[k] = true end
    class = "SHAMAN"
    addon.PaladinRefresh()
    assert(not Find("ForeverLazy_Paladin"))
    class = "PALADIN"
end)

test("the panel builds for a paladin and its buttons cast the right things", function()
    for _, s in ipairs({ "Seal of Righteousness", "Seal of the Crusader", "Devotion Aura", "Retribution Aura", "Righteous Fury", "Purify" }) do
        known[s] = true
    end
    addon.PaladinRefresh()
    assert(Find("ForeverLazy_Paladin").shown)
    assert(Find("ForeverLazy_Paladin_seal").attrs.macrotext1 == "/cast Seal of Righteousness")
    assert(Find("ForeverLazy_Paladin_aura").attrs.macrotext1 == "/cast Devotion Aura")
    assert(Find("ForeverLazy_Paladin_fury").attrs.macrotext1 == "/cast Righteous Fury")
    assert(Find("ForeverLazy_Cleanse2").attrs.macrotext1 == "/cast [@party1,help,nodead] Purify")
    assert(Find("ForeverLazy_PaladinMenu_seal2").attrs.macrotext1 == "/cast Seal of the Crusader")
    assert(Find("ForeverLazy_PaladinMenu_aura2").attrs.macrotext1 == "/cast Retribution Aura")
    assert(Find("ForeverLazy_PaladinMenu_seal").count == 2)
end)

test("learning Cleanse takes over from Purify", function()
    known["Cleanse"] = true
    addon.PaladinRefresh()
    assert(Find("ForeverLazy_Cleanse1").attrs.macrotext1 == "/cast [@player,help,nodead] Cleanse")
end)

test("painting in a fight changes no button: red when missing, green when on, cleanse colours", function()
    combat = true                        -- SetAttribute fails the test if anything is changed now
    auras["playerHELPFUL"] = {
        { name = "Seal of Righteousness", expirationTime = now + 25 },
        { name = "Devotion Aura", sourceUnit = "party1" },
    }
    auras["party1HARMFUL"] = { { name = "Curse of Pain", dispelName = "Magic", expirationTime = now + 10 } }
    Events().scripts.OnUpdate(nil, 1)
    assert(Colour(Find("ForeverLazy_Paladin_seal")) == "green")
    assert(Colour(Find("ForeverLazy_Paladin_aura")) == "red", "someone else's aura counted as mine")
    assert(Colour(Find("ForeverLazy_Paladin_fury")) == "red")
    local c = Find("ForeverLazy_Cleanse2").bg.color
    assert(c[3] > 0.8, "magic should be blue")
    addon.PaladinRefresh()               -- asked for during the fight: it must wait, not touch the buttons
    combat = false
end)

test("a fight that starts without Righteous Fury is said, and one with it is not", function()
    local ev = Events()
    ev.scripts.OnEvent(ev, "PLAYER_REGEN_DISABLED")
    assert(Said("without Righteous Fury"))
    local before = #said
    auras["playerHELPFUL"] = { { name = "Righteous Fury", expirationTime = now + 900, sourceUnit = "player" } }
    ev.scripts.OnEvent(ev, "PLAYER_REGEN_DISABLED")
    assert(#said == before)
    assert(Colour(Find("ForeverLazy_Paladin_fury")) == "green")
end)

test("when the game hides buffs the buttons say ? and nothing is warned", function()
    local real = C_UnitAuras.GetAuraDataByIndex
    C_UnitAuras.GetAuraDataByIndex = function() error("hidden") end
    local before = #said
    local ev = Events()
    ev.scripts.OnEvent(ev, "PLAYER_REGEN_DISABLED")
    assert(Find("ForeverLazy_Paladin_fury").text.text == "?")
    assert(#said == before)
    C_UnitAuras.GetAuraDataByIndex = real
end)

local function Hover(cell)               -- what the game does: runs the button's secure enter script, in a fight too
    assert(cell.attrs._onenter, "no secure enter script")
    assert(load("local self = ...\n" .. cell.attrs._onenter))(cell)
end
local function ClickEntry(b, mouse)      -- press then release; the game casts on the release with what the button holds
    if b.scripts.PostClick then b.scripts.PostClick(b, mouse, true) end
    local cast = mouse == "LeftButton" and b.attrs.macrotext1 or nil
    if b.scripts.PostClick then b.scripts.PostClick(b, mouse, false) end
    return cast
end
local function Menu(kind) return Find("ForeverLazy_PaladinMenu_" .. kind) end

test("pointing at a button opens its menu and closes the other, in a fight too", function()
    assert(P.menusWorkInCombat == true)
    Menu("aura"):Show()
    combat = true
    Hover(Find("ForeverLazy_Paladin_seal"))
    assert(Menu("seal").shown and not Menu("aura").shown and Menu("seal").autoHide == 0.4)
    assert(Menu("seal").alsoOver == Find("ForeverLazy_Paladin_seal"))
    Hover(Find("ForeverLazy_Paladin_aura"))
    assert(Menu("aura").shown and not Menu("seal").shown)
    combat = false
end)

test("in a fight a menu click casts and changes no button", function()
    combat = true
    assert(ClickEntry(Find("ForeverLazy_PaladinMenu_seal2"), "LeftButton") == "/cast Seal of the Crusader")
    combat = false
    assert(Find("ForeverLazy_Paladin_seal").attrs.macrotext1 == "/cast Seal of Righteousness")
    assert(Said("usual one stays"))
end)

test("out of a fight, left-click casts and keeps it; right-click only keeps it; the press changes nothing", function()
    local b = Find("ForeverLazy_PaladinMenu_seal2")
    b.scripts.PostClick(b, "LeftButton", true)
    assert(Find("ForeverLazy_Paladin_seal").attrs.macrotext1 == "/cast Seal of Righteousness", "changed on the press")
    assert(ClickEntry(b, "LeftButton") == "/cast Seal of the Crusader")
    assert(db.palSealPick == "Seal of the Crusader")
    assert(Find("ForeverLazy_Paladin_seal").attrs.macrotext1 == "/cast Seal of the Crusader")
    assert(ClickEntry(Find("ForeverLazy_PaladinMenu_aura2"), "RightButton") == nil)
    assert(Find("ForeverLazy_PaladinMenu_aura2").attrs.macrotext2 == nil, "right-click must not cast")
    assert(Find("ForeverLazy_Paladin_aura").attrs.macrotext1 == "/cast Retribution Aura")
end)

test("unticking one hides just that button; unticking all hides the panel", function()
    db.palFury = nil
    addon.PaladinRefresh()
    assert(not Find("ForeverLazy_Paladin_fury").shown and Find("ForeverLazy_Paladin_seal").shown)
    db.palSeal, db.palAura, db.palCleanse = nil, nil, nil
    addon.PaladinRefresh()
    assert(not Find("ForeverLazy_Paladin").shown)
end)

test("/lazy paladin all and off, and standing up and down still builds", function()
    assert(addon:HandleExtraCommand("paladin", "all"))
    assert(db.palSeal and db.palAura and db.palFury and db.palCleanse and Find("ForeverLazy_Paladin").shown)
    db.palVertical, db.palMenuFlip = true, true
    addon.PaladinRefresh()
    assert(Find("ForeverLazy_Paladin_seal").attrs.macrotext1 == "/cast Seal of the Crusader")
    db.palScale = 9; assert(P.Scale() == 2)
    db.palScale = 0.1; assert(P.Scale() == 0.5)
    addon:HandleExtraCommand("pally", "off")
    assert(not db.palSeal and not Find("ForeverLazy_Paladin").shown)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
