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
function SaidList() return said end
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
    for _, f in ipairs(frames) do if f.scripts.OnUpdate and f.scripts.OnEvent then tick = f.scripts.OnUpdate end end
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
-- the element order on the bar is Earth, Fire, Water, Air
local function Menu(i) return _G["ForeverLazy_TotemMenu" .. i] end
local function Entry(i, j) return _G["ForeverLazy_TotemMenu" .. i .. "_" .. j] end
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
local function Rebuild()
    for _, s in ipairs({ "Stoneskin Totem", "Tremor Totem" }) do known[s] = true end
    class, combat = "SHAMAN", false
    addon.ShamanRefresh()
end

test("each element's menu lists every totem of it I know, then none, and each casts its own", function()
    Rebuild()
    assert(Entry(1, 1).totem == "Strength of Earth Totem" and Entry(1, 2).totem == "Stoneskin Totem" and Entry(1, 3).totem == "Tremor Totem" and Entry(1, 4).totem == "none")
    assert(Entry(1, 3).attrs.macrotext1 == "/cast Tremor Totem" and Entry(1, 4).attrs.macrotext1 == nil)
    assert(Menu(4).count == 0, "no air totems known: no menu")
end)

test("the enter script opens that menu, closes the others, and lets it close itself", function()
    assert(S.menusWorkInCombat == true)
    Menu(2):Show()
    combat = true
    Hover(Find("ForeverLazy_Totem1"))
    assert(Menu(1).shown and not Menu(2).shown and Menu(1).autoHide == 0.4 and Menu(1).alsoOver == Find("ForeverLazy_Totem1"))
    combat = false
end)

test("in a fight a menu click drops that totem and changes no button", function()
    combat = true                        -- SetAttribute fails the test if anything is changed now
    local cast = ClickEntry(Entry(1, 3), "LeftButton")
    assert(cast == "/cast Tremor Totem", tostring(cast))
    assert(ClickEntry(Entry(1, 2), "LeftButton") == "/cast Stoneskin Totem")
    combat = false
    assert(Find("ForeverLazy_Totem1").attrs.macrotext1 == "/cast Strength of Earth Totem")
    assert(Said("stays until you pick one outside a fight"))
end)

test("out of a fight, left-click drops and keeps it; right-click only keeps it; the press changes nothing", function()
    local b = Entry(1, 3)
    b.scripts.PostClick(b, "LeftButton", true)
    assert(Find("ForeverLazy_Totem1").attrs.macrotext1 == "/cast Strength of Earth Totem", "changed on the press")
    assert(ClickEntry(b, "LeftButton") == "/cast Tremor Totem")
    assert(Find("ForeverLazy_Totem1").attrs.macrotext1 == "/cast Tremor Totem" and not Menu(1).shown)
    assert(ClickEntry(Entry(1, 2), "RightButton") == nil)
    assert(Find("ForeverLazy_Totem1").attrs.macrotext1 == "/cast Stoneskin Totem")
    assert(Find("ForeverLazy_TotemSet").attrs.macrotext1:find("Stoneskin Totem"))
    ClickEntry(Entry(1, 4), "RightButton")
    assert(Find("ForeverLazy_Totem1").attrs.macrotext1 == nil)
end)

test("the panel takes over the arrows' size and lock once, then keeps its own", function()
    db.shamSplit, db.scale, db.locked = nil, 1.4, true
    S.Settings()
    assert(db.shamScale == 1.4 and db.shamLocked == true)
    db.scale, db.locked = 3, false
    S.Settings()
    assert(db.shamScale == 1.4 and db.shamLocked == true)
    db.shamScale = 9; assert(S.Scale() == 2)
    db.shamScale = 0.1; assert(S.Scale() == 0.5)
end)

test("standing up and down still builds, with the same buttons casting the same things", function()
    db.shamVertical, db.shamMenuFlip = true, true
    Rebuild()
    assert(Find("ForeverLazy_Shaman").shown and Entry(1, 3).attrs.macrotext1 == "/cast Tremor Totem")
    db.shamVertical, db.shamMenuFlip = nil, nil
end)
test("the game's totem bar: left alone unless ticked, hidden only while mine shows, and given back", function()
    local bar = { shown = true, IsShown = function(self) return self.shown end, Show = function(self) self.shown = true end }
    local rules = {}
    MultiCastActionBarFrame = bar
    RegisterStateDriver = function(f, what, rule) assert(not combat); rules[f] = rule; f.shown = false end
    UnregisterStateDriver = function(f) assert(not combat); rules[f] = nil end
    Rebuild()
    assert(not rules[bar] and bar.shown, "touched without being ticked")
    db.shamHideGameBar = true
    Rebuild()
    assert(rules[bar] == "hide")
    local mine, range = db.shamTotemBar, db.shamTotemRange
    db.shamTotemBar, db.shamTotemRange = nil, nil
    Rebuild()
    assert(not rules[bar] and bar.shown, "my bar is off: the game's must be back")
    db.shamTotemBar, db.shamTotemRange = mine, range
    Rebuild()
    combat = true; addon.ShamanRefresh(); combat = false
    db.shamHideGameBar = nil
    Rebuild()
    assert(not rules[bar] and bar.shown, "unticking must give it back")
    MultiCastActionBarFrame = nil
end)
test("totem recall: a button once I know the spell, under either name, and recalled totems are not called gone", function()
    Rebuild()
    local b = Find("ForeverLazy_TotemRecall")
    assert(not b.shown and b.attrs.macrotext1 == nil, "a button without the spell")
    for _, name in ipairs({ "Totemic Call", "Totemic Recall" }) do
        known["Totemic Call"], known["Totemic Recall"] = nil, nil
        known[name] = true
        Rebuild()
        assert(b.shown and b.attrs.macrotext1 == "/cast " .. name, tostring(b.attrs.macrotext1))
    end
    local ev
    for _, f in ipairs(frames) do if f.scripts.OnUpdate and f.scripts.OnEvent then ev = f end end
    C_Spell = { GetSpellName = function(id) return id == 5 and "Totemic Recall" or "Lightning Bolt" end }
    totemInfo[1] = { "Searing Totem", now, 55 }
    ev.scripts.OnUpdate(nil, 1)
    ev.scripts.OnEvent(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 5)
    totemInfo[1] = nil
    now = now + 1
    local before = #SaidList()
    ev.scripts.OnUpdate(nil, 1)
    for i = before + 1, #SaidList() do assert(not SaidList()[i]:find("is gone"), "a recalled totem was called gone") end
    C_Spell = nil
end)
test("the drop-the-set key button follows the picked set, with the totem bar off too, and waits out a fight", function()
    Rebuild()
    local k = Find("ForeverLazy_DropTotems")
    assert(k and k.attrs.type1 == "macro" and k.attrs.macrotext1 == Find("ForeverLazy_TotemSet").attrs.macrotext1)
    local keep = {}
    for _, key in ipairs({ "shamTotemBar", "shamTotemRange", "shamImbue", "shamShield", "shamAnkh", "shamCure" }) do keep[key], db[key] = db[key], nil end
    db.shamSet = "Dungeon"
    db.shamTotems.Dungeon = { earth = "Tremor Totem", fire = "none", water = "none" }
    Rebuild()
    assert(k.attrs.macrotext1 == "/castsequence reset=15/combat Tremor Totem", tostring(k.attrs.macrotext1))
    combat = true; db.shamTotems.Dungeon.earth = "Stoneskin Totem"; addon.ShamanRefresh(); combat = false
    assert(k.attrs.macrotext1:find("Tremor"), "changed during a fight")
    db.shamSet = nil
    for key, v in pairs(keep) do db[key] = v end
    Rebuild()
end)
-- a pretend key table, and a stand-in options button
local binds = { W = "MOVEFORWARD" }
local saves = 0
GetBindingKey = function(action) local out = {}; for k, a in pairs(binds) do if a == action then out[#out + 1] = k end end return table.unpack(out) end
GetBindingAction = function(key) return binds[key] or "" end
SetBinding = function(key, action) assert(not combat, "keys changed during a fight"); binds[key] = action; return true end
GetCurrentBindingSet = function() return 2 end
SaveBindings = function(set) assert(set == 2); saves = saves + 1 end
local held = {}
IsShiftKeyDown = function() return held.shift end
IsControlKeyDown = function() return held.ctrl end
IsAltKeyDown = function() return held.alt end
local DROP = "CLICK ForeverLazy_DropTotems:LeftButton"

test("pressed keys are written the game's way; Shift on its own is not a key", function()
    assert(S.KeyName("F") == "F" and S.KeyName("F", true, true, true) == "ALT-CTRL-SHIFT-F")
    assert(S.KeyName("MiddleButton") == "BUTTON3" and S.KeyName("Button4", false, false, true) == "SHIFT-BUTTON4")
    assert(S.KeyName("LSHIFT", false, false, true) == nil and S.KeyName("RCTRL") == nil and S.KeyName("LALT") == nil)
end)

test("the options button: click, press, saved; the old key is let go; Esc cancels", function()
    local b = CreateFrame("Button", nil)
    local keyboard
    b.EnableKeyboard = function(_, v) keyboard = v end
    S.KeyCatcher(b)
    assert(b.text == "Click to set a drop the set key")
    b.scripts.OnClick(b, "LeftButton")
    assert(keyboard and b.text == "Press a key (Esc cancels)")
    held.shift = true; b.scripts.OnKeyDown(b, "LSHIFT"); assert(keyboard, "Shift alone ended it")
    b.scripts.OnKeyDown(b, "F"); held.shift = false
    assert(binds["SHIFT-F"] == DROP and saves == 1 and not keyboard and not b.scripts.OnKeyDown)
    assert(b.text == "Drop the set key: SHIFT-F")
    b.scripts.OnClick(b, "LeftButton"); b.scripts.OnKeyDown(b, "G")
    assert(binds.G == DROP and binds["SHIFT-F"] == nil, "two keys left")
    b.scripts.OnClick(b, "LeftButton"); b.scripts.OnKeyDown(b, "ESCAPE")
    assert(binds.G == DROP and not keyboard)
end)

test("a key in use needs a second press, and nothing changes during a fight", function()
    local b = CreateFrame("Button", nil)
    S.KeyCatcher(b)
    b.scripts.OnClick(b, "LeftButton")
    b.scripts.OnKeyDown(b, "W")
    assert(binds.W == "MOVEFORWARD" and Said("Press it again"))
    b.scripts.OnKeyDown(b, "W")
    assert(binds.W == DROP)
    assert(S.SetKey(nil) and binds.W == nil)
    combat = true
    b.scripts.OnClick(b, "LeftButton")
    assert(not b.scripts.OnKeyDown and S.SetKey("H") == false and binds.H == nil)
    combat = false
    b.scripts.OnClick(b, "LeftButton")
    b.scripts.OnEvent(b, "PLAYER_REGEN_DISABLED")
    assert(not b.scripts.OnKeyDown, "kept the keyboard into a fight")
end)

test("a paladin sees no panel", function()
    class = "PALADIN"
    addon.ShamanRefresh()
    assert(not Find("ForeverLazy_Shaman").shown)
    class = "SHAMAN"
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
