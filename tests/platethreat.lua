-- Threat on nameplates and the tank colours (no game needed): lua tests/platethreat.lua
-- Hidden values are stood in for by a table that fails if anything reads it. It cannot say what the real game hides.
local now = 1000
GetTime = function() return now end
local SECRET = setmetatable({}, { __eq = function() error("a hidden value was compared") end, __lt = function() error("a hidden value was compared") end,
    __le = function() error("a hidden value was compared") end, __index = function() error("a hidden value was read") end,
    __concat = function() error("a hidden value was joined") end })
issecretvalue = function(v) return rawequal(v, SECRET) end

local mob
local function Reset()
    mob = { combat = true, player = false, attackable = true, tanking = false, status = 0, scaled = 30, exists = true, targetName = "Ann Baker",
            targetClass = "MAGE", targetIsMe = false, inParty = true }
end
Reset()
UnitIsPlayer = function() return mob.player end
UnitCanAttack = function() return mob.attackable end
UnitIsTapDenied = function() return false end
UnitReaction = function() return 2 end
UnitAffectingCombat = function() return mob.combat end
UnitDetailedThreatSituation = function() return mob.tanking, mob.status, mob.scaled end
UnitExists = function() return mob.exists end
UnitIsUnit = function() return mob.targetIsMe end
UnitName = function() return mob.targetName end
UnitClass = function() return "x", mob.targetClass end
UnitInParty = function() return mob.inParty end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
local sounds = 0
PlaySound = function() sounds = sounds + 1 end

local function Frame()
    local f = { shown = true, scripts = {} }
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.SetText = function(self, t) self.text = t end
    f.SetFormattedText = function(self, fmt, v) if issecretvalue(v) then self.text = "hidden" else self.text = string.format(fmt, v) end end
    f.SetTextColor = function(self, r, g, b) self.color = { r, g, b } end
    f.SetScript = function(self, w, fn) self.scripts[w] = fn end
    f.CreateFontString = function() return Frame() end
    setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    return f
end
CreateFrame = function() return Frame() end
local plate = { UnitFrame = { unit = "nameplate1", healthBar = Frame(), GetFrameLevel = function() return 1 end }, namePlateUnitToken = "nameplate1" }
C_NamePlate = { GetNamePlateForUnit = function() return plate end, GetNamePlates = function() return { plate } end }

local db, said = {}, {}
local addon = { GetDB = function() return db end, Print = function(s) said[#said + 1] = s end }
local ns = { L = function(s) return s end, addon = addon }
assert(loadfile("ForeverLazy/PlateColors.lua"))("ForeverLazy", ns)
assert(loadfile("ForeverLazy/PlateThreat.lua"))("ForeverLazy", ns)
local T = addon.PlateThreat

local passed, failed = 0, 0
local function test(label, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. label) else failed = failed + 1; print("FAIL  " .. label .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "differs") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end
local function Paint() return T.PaintUnit("nameplate1") end

test("all off: nothing is put on a nameplate", function() eq(Paint(), nil) end)
test("who it is attacking: the first name in the class colour, and YOU when it is me", function()
    db.plateTargetName = true
    local p = Paint()
    eq(p.target.text, "Ann"); eq(p.target.color[1], 0.25); eq(p.target.shown, true)
    eq(p.number.shown, false); eq(p.warn.shown, false)
    mob.targetIsMe = true; p = Paint(); eq(p.target.text, "YOU")
    mob.targetIsMe = false; mob.exists = false; p = Paint(); eq(p.target.shown, false)
    Reset()
end)
test("a mob that is not in a fight shows nothing", function()
    db.plateThreatNum = true
    local p = Paint(); eq(p.target.shown, true)
    mob.combat = false; Paint(); eq(p.target.shown, false); eq(p.number.shown, false)
    Reset()
end)
test("my threat as a percentage, and nothing when I am not on its list", function()
    local p = Paint(); eq(p.number.text, "30%")
    mob.scaled, mob.status, mob.tanking = nil, nil, nil
    p = Paint(); eq(p.number.shown, false)
    Reset()
end)
test("the pull warning shows from 80 percent, with one sound for each pull", function()
    db.platePullWarn = true; sounds = 0
    local p = Paint(); eq(p.warn.shown, false)
    mob.scaled = 85; p = Paint(); eq(p.warn.shown, true); Paint(); Paint(); eq(sounds, 1)
    mob.scaled = 20; Paint(); eq(p.warn.shown, false)
    now = now + 10; mob.scaled, mob.status = 60, 1; Paint(); eq(p.warn.shown, true); eq(sounds, 2)
    mob.tanking, mob.scaled = true, 100; Paint(); eq(p.warn.shown, false)
    Reset()
end)
test("no warning with the tank colours on", function()
    db.plateTank = true; mob.scaled = 95
    local p = Paint(); eq(p.warn.shown, false)
    db.plateTank = nil; Reset()
end)
test("hidden values are shown but never read: no warning, no error", function()
    mob.tanking, mob.status, mob.scaled, mob.targetName, mob.targetClass, mob.targetIsMe, mob.combat = SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET
    sounds = 0
    local p = Paint()
    assert(rawequal(p.target.text, SECRET), "the hidden name is handed to the game")
    eq(p.number.text, "hidden"); eq(p.warn.shown, false); eq(sounds, 0)
    Reset()
end)
test("switching it off takes the words away", function()
    local p = Paint(); eq(p.number.shown, true)
    db.plateTargetName, db.plateThreatNum, db.platePullWarn = nil, nil, nil
    addon.PlateThreatRefresh()
    eq(p.number.shown, false); eq(p.target.shown, false)
end)
test("tank colours: holding, slipping, got away, someone else's fight", function()
    local S = function(info) info.hostileNpc = true; info.reaction = info.reaction or 2; return addon.PlateColorState(info, nil, nil, true) end
    eq(S({ inCombat = true, tankingMe = true, status = 3, onList = true }), "safe")
    eq(S({ inCombat = true, tankingMe = true, status = 2, onList = true }), "slipping")
    eq(S({ inCombat = true, targetsMe = true }), "safe")
    eq(S({ inCombat = true, onList = true, status = 1 }), "lost")
    eq(S({ inCombat = true, targetsGroup = true }), "lost")
    eq(S({ inCombat = true }), "others")
    eq(S({ inCombat = false }), "me", "aggressive and idle is still red")
end)
test("when the game hides who a mob is on, its own colour is left alone", function()
    local info = { hostileNpc = true, reaction = 2, inCombat = true, unsure = true }
    eq(addon.PlateColorState(info, nil, nil, true), nil)
    eq(addon.PlateColorState(info, nil, nil, false), nil)
    info.tankingMe = true
    eq(addon.PlateColorState(info, nil, nil, false), "me")
end)
test("/lazy threat check says what is hidden", function()
    mob.scaled, mob.targetName = SECRET, SECRET
    said = {}; addon:HandleExtraCommand("threat", "check")
    local text = table.concat(said, " / ")
    assert(text:find("my threat percent: hidden by the game", 1, true), text)
    assert(text:find("its target's name: hidden by the game", 1, true), text)
    assert(text:find("threat status: 0", 1, true), text)
    Reset()
end)

test("with Plates v1 picked, nothing of v2 shows", function()
    db.plateTargetName, db.plateThreatNum, db.plateStyle = true, true, "v1"
    eq(Paint(), nil)
    db.plateStyle = "v2"
    eq(Paint().number.shown, true)
end)
test("the words move out past the quest icon and the interrupt marker, and back", function()
    local icon, marker = {}, {}
    local p = Paint()
    local at = {}
    p.number.SetPoint = function(_, _, to) at.number = to end
    p.target.SetPoint = function(_, _, to) at.target = to end
    addon.QuestPlateIcon = function() return icon end
    addon.CastMarkerFor = function() return marker end
    Paint(); assert(rawequal(at.number, icon), "number beside the quest icon"); assert(rawequal(at.target, marker), "name beside the marker")
    addon.QuestPlateIcon, addon.CastMarkerFor = nil, nil
    Paint(); assert(rawequal(at.number, p.holder) and rawequal(at.target, p.holder))
    db.plateTargetName, db.plateThreatNum, db.plateStyle = nil, nil, nil
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
