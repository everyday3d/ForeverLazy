-- Offline tests for the paladin blessings: who needs which blessing, and what the choices do (no game needed).
--   lua tests/blessings.lua
local root = (arg and arg[0] or "tests/blessings.lua"):gsub("[/\\]tests[/\\]blessings%.lua$", ""):gsub("^tests[/\\]blessings%.lua$", ".")

local db = {}
local addon = { Print = function() end, GetDB = function() return db end, ReportWindow = function() end }
local ns = { addon = addon, L = function(x) return x end }
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function UnitClass() return "Paladin", "PALADIN" end

assert(loadfile(root .. "/ForeverLazy/Blessings.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "differs") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end

local known = { ["Blessing of Might"] = true, ["Blessing of Wisdom"] = true, ["Blessing of Kings"] = true, ["Blessing of Light"] = true, ["Blessing of Freedom"] = true, ["Judgement"] = true }
local avail = addon.BlessingsAvailable(known)

local function member(unit, class, extra)
    local m = { unit = unit, class = class, name = unit, alive = true, connected = true, inRange = true }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
end
local function buffsFrom(map) return function(unit) return map[unit] or {} end end

test("the blessings I can cast come in the usual order, without Freedom", function()
    eq(table.concat(avail, ","), "Blessing of Might,Blessing of Wisdom,Blessing of Kings,Blessing of Light")
end)

test("a class gets the usual blessing: Might for fighters, Wisdom for casters", function()
    db.blessings = nil
    eq(addon.BlessingFor("WARRIOR", avail), "Blessing of Might")
    eq(addon.BlessingFor("MAGE", avail), "Blessing of Wisdom")
end)

test("my choice for a class wins, and none means no blessing", function()
    db.blessings = { WARRIOR = "Blessing of Kings", MAGE = "none" }
    eq(addon.BlessingFor("WARRIOR", avail), "Blessing of Kings")
    eq(addon.BlessingFor("MAGE", avail), nil)
    db.blessings = nil
end)

test("the first player who is missing their blessing is next, and the count says how many", function()
    local members = { member("player", "PALADIN"), member("party1", "WARRIOR"), member("party2", "MAGE") }
    local buffs = buffsFrom({ player = { { name = "Blessing of Might", left = 600 } } })
    local pick, bless, count = addon.BlessNext(members, avail, buffs)
    eq(pick.unit, "party1"); eq(bless, "Blessing of Might"); eq(count, 2)
end)

test("someone who has the blessing, from anyone, is skipped", function()
    local members = { member("player", "PALADIN"), member("party1", "MAGE") }
    local buffs = buffsFrom({ player = { { name = "Blessing of Might", left = 900 } }, party1 = { { name = "Blessing of Wisdom", left = 900 } } })
    local pick, _, count = addon.BlessNext(members, avail, buffs)
    eq(pick, nil); eq(count, 0)
end)

test("a blessing that is about to run out counts as missing", function()
    local members = { member("party1", "WARRIOR") }
    local buffs = buffsFrom({ party1 = { { name = "Blessing of Might", left = 30 } } })
    local pick = addon.BlessNext(members, avail, buffs)
    assert(pick, "30 seconds left should be rebuffed")
end)

test("a blessing with no end time (permanent) is fine", function()
    local members = { member("party1", "WARRIOR") }
    local buffs = buffsFrom({ party1 = { { name = "Blessing of Might" } } })
    eq(addon.BlessNext(members, avail, buffs), nil)
end)

test("a Greater blessing counts for the same blessing", function()
    local members = { member("party1", "WARRIOR") }
    local buffs = buffsFrom({ party1 = { { name = "Greater Blessing of Might", left = 1200 } } })
    eq(addon.BlessNext(members, avail, buffs), nil)
end)

test("dead, offline and out of range players are not the next target", function()
    local members = { member("party1", "WARRIOR", { alive = false }), member("party2", "WARRIOR", { connected = false }),
        member("party3", "WARRIOR", { inRange = false }), member("party4", "ROGUE") }
    local pick, _, count = addon.BlessNext(members, avail, buffsFrom({}))
    eq(pick.unit, "party4"); eq(count, 2, "dead and offline do not count, the one out of range does")
end)

test("someone whose buffs cannot be read is left alone", function()
    local members = { member("party1", "WARRIOR") }
    local pick, _, count = addon.BlessNext(members, avail, function() return nil end)
    eq(pick, nil); eq(count, 0)
end)

test("a class set to none is never blessed", function()
    db.blessings = { WARRIOR = "none" }
    local members = { member("party1", "WARRIOR") }
    eq(addon.BlessNext(members, avail, buffsFrom({})), nil)
    db.blessings = nil
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end