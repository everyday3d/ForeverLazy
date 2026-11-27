-- Offline tests for the nameplate colours (no game needed).
--   lua tests/platecolors.lua
local root = (arg and arg[0] or "tests/platecolors.lua"):gsub("[/\\]tests[/\\]platecolors%.lua$", ""):gsub("^tests[/\\]platecolors%.lua$", ".")

local db = { plateColors = true }
local addon = { Print = function() end, GetDB = function() return db end, ModuleOn = function() return true end }
local ns = { addon = addon, L = function(x) return x end }
local hookFn
function hooksecurefunc(name, fn) if name == "CompactUnitFrame_UpdateHealthColor" then hookFn = fn end end
function CompactUnitFrame_UpdateHealthColor() end
local scripts = {}
function CreateFrame() local f = setmetatable({}, { __index = function() return function() end end }); f.SetScript = function(_, n, fn) scripts[#scripts + 1] = { name = n, fn = fn } end; return f end

-- a mob, as the game would answer
local mob = { player = false, attackable = true, tapped = false, tanking = false, targetsMe = false, combat = false, reaction = 2 }
function UnitReaction() return mob.reaction end
function UnitIsPlayer() return mob.player end
function UnitCanAttack() return mob.attackable end
function UnitIsTapDenied() return mob.tapped end
function UnitDetailedThreatSituation() return mob.tanking, 3 end
function UnitIsUnit() return mob.targetsMe end
function UnitAffectingCombat() return mob.combat end

assert(loadfile(root .. "/ForeverLazy/PlateColors.lua"))("ForeverLazy", ns)
for _, s in ipairs(scripts) do if s.name == "OnEvent" then s.fn(nil, "PLAYER_LOGIN") end end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "differs") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end

local function Frame()
    local f = { unit = "nameplate1", healthBar = {} }
    f.healthBar.color = nil
    f.healthBar.SetStatusBarColor = function(self, r, g, b) self.color = { r, g, b } end
    return f
end
local function reset() mob.player, mob.attackable, mob.tapped, mob.tanking, mob.targetsMe, mob.combat, mob.reaction = false, true, false, false, false, false, 2 end

test("a mob attacking me is red, even if another addon painted it green", function()
    reset(); mob.tanking = true; mob.combat = true
    local f = Frame(); f.healthBar.color = { 0, 1, 0 }
    hookFn(f)
    eq(f.healthBar.color[1], 1); eq(f.healthBar.color[2], 0); eq(f.healthBar.color[3], 0)
end)

test("a mob that targets me counts as attacking me", function()
    reset(); mob.targetsMe = true; mob.combat = true
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color[1], 1); eq(f.healthBar.color[2], 0)
end)

test("a mob fighting someone else is orange, not the neutral yellow", function()
    reset(); mob.combat = true
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color[1], 1); eq(f.healthBar.color[2], 0.55)
end)

test("an AGGRESSIVE mob is red before any fight, so you can tell", function()
    reset(); mob.reaction = 2
    local f = Frame(); f.healthBar.color = { 1, 0.82, 0.1 }
    hookFn(f)
    eq(f.healthBar.color[1], 1); eq(f.healthBar.color[2], 0); eq(f.healthBar.color[3], 0)
end)

test("an aggressive quest mob stays red, the quest tint does not cover it", function()
    reset(); mob.reaction = 3
    addon.PlateQuestKind = function() return "kill" end
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color[1], 1); eq(f.healthBar.color[2], 0)
    addon.PlateQuestKind = nil
end)

test("a NEUTRAL quest mob that is not in a fight is purple", function()
    reset(); mob.reaction = 4
    addon.PlateQuestKind = function() return "loot" end
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color[1], 0.75)
    addon.PlateQuestKind = nil
end)

test("a neutral mob that is not a quest mob keeps the game's yellow", function()
    reset(); mob.reaction = 4
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color, nil)
end)

test("a neutral mob attacking me turns red", function()
    reset(); mob.reaction = 4; mob.targetsMe = true; mob.combat = true
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color[2], 0)
end)

test("the old yellow default for 'someone else' is changed to orange", function()
    db.plateColorOthers = { 1, 0.82, 0.1 }
    addon.PlateColorsRefresh()
    eq(db.plateColorOthers[2], 0.55)
end)
test("a quest starter is not tinted", function()
    reset(); mob.reaction = 4
    addon.PlateQuestKind = function() return "start" end
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color, nil)
    addon.PlateQuestKind = nil
end)

test("players, friendly mobs and tapped mobs keep the game's colour", function()
    for _, field in ipairs({ "player", "tapped" }) do
        reset(); mob[field] = true; mob.combat = true
        local f = Frame(); hookFn(f); eq(f.healthBar.color, nil, field)
    end
    reset(); mob.attackable = false; mob.combat = true
    local f = Frame(); hookFn(f); eq(f.healthBar.color, nil, "friendly")
end)

test("nothing happens when it is switched off, or for a frame that is not a nameplate", function()
    reset(); mob.combat = true
    db.plateColors = nil
    local f = Frame(); hookFn(f); eq(f.healthBar.color, nil)
    db.plateColors = true
    local g = Frame(); g.unit = "target"; hookFn(g); eq(g.healthBar.color, nil)
end)

test("the two parts can be switched off one by one", function()
    reset(); mob.combat = true; db.plateThreat = false
    local f = Frame(); hookFn(f); eq(f.healthBar.color, nil)
    db.plateThreat = nil
    reset(); mob.reaction = 4; db.plateQuest = false
    addon.PlateQuestKind = function() return "kill" end
    local g = Frame(); hookFn(g); eq(g.healthBar.color, nil)
    addon.PlateQuestKind = nil; db.plateQuest = nil
end)

test("the switch: a saved v1 tick with nothing else picked is still v1", function()
    db.plateStyle, db.plateTank = nil, nil
    eq(addon.PlateStyle(), "v1")
end)

test("with v2 picked the v1 colours wait, and the tank colours work, colour nothing idle and give the bar its colour back", function()
    db.plateColors, db.plateTank = true, true
    addon.SetPlateStyle("v2")
    reset()
    local f = Frame(); hookFn(f); eq(f.healthBar.color, nil, "an idle aggressive mob")
    mob.combat, mob.tanking = true, true
    f.healthBar.r, f.healthBar.g, f.healthBar.b = 0.9, 0.1, 0.1
    hookFn(f); eq(f.healthBar.color[2], 0.75, "green")
    reset(); hookFn(f); eq(f.healthBar.color[1], 0.9); eq(f.healthBar.color[2], 0.1)
    reset(); mob.reaction = 4
    addon.PlateQuestKind = function() return "kill" end
    local g = Frame(); hookFn(g); eq(g.healthBar.color, nil, "v2 has no quest tint")
    addon.PlateQuestKind = nil
end)

test("switching back to v1 brings its colours back, and the tank colours wait", function()
    addon.SetPlateStyle("v1")
    eq(db.plateColors, true); eq(db.plateTank, true)
    reset(); mob.combat, mob.tanking = true, true
    local f = Frame(); hookFn(f); eq(f.healthBar.color[1], 1); eq(f.healthBar.color[2], 0)
end)

test("/lazy platestyle and /lazy platecolors pick the kind", function()
    addon:HandleExtraCommand("platestyle", "v2"); eq(db.plateStyle, "v2")
    addon:HandleExtraCommand("platecolors", "on"); eq(db.plateStyle, "v1"); eq(db.plateColors, true)
    db.plateTank = nil
end)
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end