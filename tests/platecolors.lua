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
local mob = { player = false, attackable = true, tapped = false, tanking = false, targetsMe = false, combat = false }
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
local function reset() mob.player, mob.attackable, mob.tapped, mob.tanking, mob.targetsMe, mob.combat = false, true, false, false, false, false end

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

test("a mob fighting someone else is yellow", function()
    reset(); mob.combat = true
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color[1], 1); eq(f.healthBar.color[2], 0.82)
end)

test("a quest mob that is not in a fight is purple", function()
    reset()
    addon.PlateQuestKind = function() return "kill" end
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color[1], 0.75)
    addon.PlateQuestKind = nil
end)

test("a quest mob that is attacking me stays red, not purple", function()
    reset(); mob.tanking = true; mob.combat = true
    addon.PlateQuestKind = function() return "kill" end
    local f = Frame(); hookFn(f)
    eq(f.healthBar.color[1], 1); eq(f.healthBar.color[2], 0)
    addon.PlateQuestKind = nil
end)

test("a quest starter is not tinted", function()
    reset()
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

test("an idle mob that is no quest mob keeps the game's colour", function()
    reset()
    local f = Frame(); hookFn(f); eq(f.healthBar.color, nil)
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
    reset(); db.plateQuest = false
    addon.PlateQuestKind = function() return "kill" end
    local g = Frame(); hookFn(g); eq(g.healthBar.color, nil)
    addon.PlateQuestKind = nil; db.plateQuest = nil
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end