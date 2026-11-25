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

test("the blessings I give are sent as short text and read back", function()
    local text = addon.BlessEncode({ WARRIOR = "Might", PRIEST = "Wisdom" })
    eq(text, "PRIEST=Wisdom;WARRIOR=Might")
    local map = addon.BlessDecode(text)
    eq(map.WARRIOR, "Might"); eq(map.PRIEST, "Wisdom")
    eq(next(addon.BlessDecode("")), nil, "empty text is no claims")
end)
test("two paladins giving the same blessing: the one first in the alphabet casts it", function()
    local others = { Adam = { map = { WARRIOR = "Might" } } }
    eq(addon.BlessCovered("WARRIOR", "Might", "Zed", others), "Adam", "Zed skips")
    eq(addon.BlessCovered("WARRIOR", "Might", "Aaron", others), nil, "Aaron comes first, he casts")
end)
test("a different blessing for the same class is not covered", function()
    local others = { Adam = { map = { WARRIOR = "Kings" } } }
    eq(addon.BlessCovered("WARRIOR", "Might", "Zed", others), nil)
    eq(addon.BlessCovered("PRIEST", "Might", "Zed", others), nil, "a class he does not bless")
end)
test("the button skips a class another paladin covers", function()
    local members = { member("player", "PALADIN"), member("party1", "WARRIOR"), member("party2", "PRIEST") }
    local skip = function(class, short) return class == "WARRIOR" and short == "Might" end
    local pick, bless = addon.BlessNext(members, avail, buffsFrom({}), skip)
    eq(pick.unit, "player"); eq(bless, "Blessing of Might")
    members = { member("party1", "WARRIOR"), member("party2", "PRIEST") }
    pick = addon.BlessNext(members, avail, buffsFrom({}), skip)
    eq(pick.unit, "party2", "the warrior is left to the other paladin")
end)
test("a paladin who is dead or far away does not cover a class: my button does it", function()
    local others = { Adam = { map = { WARRIOR = "Might" }, active = false } }
    eq(addon.BlessCovered("WARRIOR", "Might", "Zed", others), nil)
    others.Adam.active = true
    eq(addon.BlessCovered("WARRIOR", "Might", "Zed", others), "Adam")
end)
test("splitting picks a blessing the others are not giving", function()
    local shorts = { "Might", "Wisdom", "Kings" }
    eq(addon.BlessSplitFor(shorts, {}, "Might"), "Might", "the usual one when free")
    eq(addon.BlessSplitFor(shorts, { Might = true }, "Might"), "Kings", "Kings is next")
    eq(addon.BlessSplitFor(shorts, { Might = true, Kings = true }, "Might"), "Wisdom")
    eq(addon.BlessSplitFor(shorts, { Might = true, Kings = true, Wisdom = true }, "Might"), nil, "nothing left to give")
    eq(addon.BlessSplitFor({ "Might" }, { Might = true }, "Might"), nil)
end)
test("a blessing just cast counts as given, so the button moves on to the next person", function()
    local members = { member("party1", "SHAMAN"), member("party2", "DRUID"), member("party3", "WARRIOR") }
    local recent = {}
    local function wasRecent(m, short) return recent[m.unit .. ":" .. short] end
    local pick, bless = addon.BlessNext(members, avail, buffsFrom({}), nil, wasRecent)
    eq(pick.unit, "party1", "first the shaman")
    recent["party1:Wisdom"] = true                      -- I clicked: the buff has not shown on him yet
    pick = addon.BlessNext(members, avail, buffsFrom({}), nil, wasRecent)
    eq(pick.unit, "party2", "then the druid, not the shaman again")
    recent["party2:Wisdom"] = true
    pick = addon.BlessNext(members, avail, buffsFrom({}), nil, wasRecent)
    eq(pick.unit, "party3", "then the warrior")
end)
test("a class row shows who needs the blessing and the shortest time left", function()
    local members = { member("party1", "WARRIOR"), member("party2", "WARRIOR"), member("party3", "MAGE") }
    local buffs = buffsFrom({
        party1 = { { name = "Blessing of Might", left = 200 } },
        party2 = { { name = "Blessing of Might", left = 400 } },
    })
    local total, missing, minLeft = addon.BlessClassState(members, "WARRIOR", "Might", buffs)
    eq(total, 2); eq(missing, 0); eq(minLeft, 200, "the shortest time")
    buffs = buffsFrom({ party1 = { { name = "Blessing of Might", left = 200 } } })
    total, missing, minLeft = addon.BlessClassState(members, "WARRIOR", "Might", buffs)
    eq(missing, 1, "one warrior has none")
    buffs = buffsFrom({ party1 = { { name = "Blessing of Might", left = 40 } }, party2 = { { name = "Blessing of Might" } } })
    total, missing = addon.BlessClassState(members, "WARRIOR", "Might", buffs)
    eq(missing, 1, "one is about to run out")
    buffs = buffsFrom({ party3 = {} })
    total, missing = addon.BlessClassState({ member("party3", "MAGE", { alive = false }) }, "MAGE", "Wisdom", buffs)
    eq(total, 0, "the dead are not counted")
end)

test("the time left reads like 4:05 or 35s", function()
    eq(addon.BlessTimeText(245), "4:05"); eq(addon.BlessTimeText(35), "35s"); eq(addon.BlessTimeText(nil), "")
end)
test("a cast that failed makes the button leave that player alone for a while", function()
    local now = 100
    GetTime = function() return now end
    UnitName = function(u) return u end
    local members = { member("party1", "SHAMAN"), member("party2", "DRUID") }
    local function wasRecent(m, short) return addon.BlessRecently(m, short) end
    local pick = addon.BlessNext(members, avail, buffsFrom({}), nil, wasRecent)
    eq(pick.unit, "party1")
    addon.BlessNoteCast("party1", "Blessing of Wisdom")
    now = 101; addon.BlessCastFailed()                                  -- out of range: the cast failed
    now = 115
    pick = addon.BlessNext(members, avail, buffsFrom({}), nil, wasRecent)
    eq(pick.unit, "party2", "still the druid 15 seconds later, not the shaman again")
    now = 140
    pick = addon.BlessNext(members, avail, buffsFrom({}), nil, wasRecent)
    eq(pick.unit, "party1", "the shaman is tried again after the wait")
end)
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end