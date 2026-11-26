-- A real click on the blessing button (no game needed): lua tests/blessclick.lua
-- The panel is built on stand-in frames and clicked the way the game does it: one run of the scripts for the press and one for
-- the release, with the spell cast on the release (useOnKeyDown is false), using whatever the button holds at that moment.
local now = 1000
GetTime = function() return now end
tinsert, unpack = table.insert, table.unpack
InCombatLockdown = function() return false end
local frames = {}
local function Frame(name)
    local f = { shown = true, attrs = {}, scripts = {} }
    f.SetAttribute = function(self, k, v) self.attrs[k] = v end
    f.GetAttribute = function(self, k) return self.attrs[k] end
    f.SetText = function(self, t) self.text = t end
    f.GetText = function(self) return self.text end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    f.SetScript = function(self, w, fn) self.scripts[w] = fn end
    f.HookScript = f.SetScript
    f.CreateFontString = function() return Frame() end
    f.CreateTexture = function() return Frame() end
    setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    if name then frames[name] = f end
    return f
end
CreateFrame = function(_, name) return Frame(name) end
UIParent, GameTooltip, UISpecialFrames = Frame(), Frame(), {}
IsShiftKeyDown = function() return false end
IsInGroup = function() return true end
IsInRaid = function() return false end
UnitIsDeadOrGhost = function() return false end
UnitIsConnected = function() return true end
UnitIsUnit = function(a, b) return a == b end
local group = { player = { "Tank", "PALADIN" } }
UnitExists = function(u) return group[u] ~= nil end
UnitName = function(u) return group[u] and group[u][1] end
UnitClass = function(u) local g = group[u] or group.player; return g[2], g[2] end
-- the buffs from the report: tracking, an aura, and a world buff with "Might" in its name that is not the blessing
local buffs = { player = { { name = "Find Minerals" }, { name = "Devotion Aura" }, { name = "Might of Stormwind", expirationTime = 4000 } } }
C_UnitAuras = { GetBuffDataByIndex = function(u, i) return buffs[u] and buffs[u][i] end }
C_Spell = { IsSpellInRange = function() return true end, GetSpellTexture = function() return "icon" end }
local book = { "Blessing of Might" }
GetNumSpellTabs = function() return 1 end
GetSpellTabInfo = function() return "Holy", "i", 0, #book end
GetSpellBookItemName = function(i) return book[i] end
local db = { pos = {}, blessPanel = true, blessSolo = true }
local addon = { GetDB = function() return db end, Print = function() end }
assert(loadfile("ForeverLazy/Blessings.lua"))("ForeverLazy", { L = function(s) return s end, addon = addon })
addon.BlessingsRefresh()
local button = frames.ForeverLazyBlessButton

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

local function Edge(b, mouse, down, cast)
    if b.scripts.OnClick then b.scripts.OnClick(b, mouse, down) end
    local did
    if cast and not down then did = b.attrs.macrotext1 or b.attrs.macrotext end          -- the game casts what it finds now
    if b.scripts.PostClick then b.scripts.PostClick(b, mouse, down) end
    return did
end
local function Click(b) Edge(b, "LeftButton", true, true); return Edge(b, "LeftButton", false, true) end

test("a world buff with Might in its name is not the blessing", function()
    assert(button and button.attrs.macrotext == "/cast [@player,help,nodead] Blessing of Might", tostring(button and button.attrs.macrotext))
end)

test("one click casts the blessing it shows", function()
    local cast = Click(button)
    assert(cast == "/cast [@player,help,nodead] Blessing of Might", "the release cast: " .. tostring(cast))
end)

test("after the click the button moves on, and a second click casts nothing", function()
    assert(button.attrs.macrotext == nil)
    assert(Click(button) == nil)
end)

test("with two players, the first click casts on the first, the next on the second", function()
    now = now + 100
    group.party1 = { "Healer", "PRIEST" }
    book = { "Blessing of Might", "Blessing of Wisdom" }
    addon.BlessingsRefresh()
    local first = Click(button)
    local second = Click(button)
    assert(first == "/cast [@player,help,nodead] Blessing of Might", "first: " .. tostring(first))
    assert(second == "/cast [@party1,help,nodead] Blessing of Wisdom", "second: " .. tostring(second))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
