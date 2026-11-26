-- The hand-in signal: message, sound and minimap ping (no game needed): lua tests/handin.lua
local tick
CreateFrame = function() return { SetScript = function(_, _, fn) tick = fn end } end
local clock, sounds, pings, shown = 100, 0, 0, {}
GetTime = function() return clock end
PlaySound = function(_, channel) assert(channel == "Master"); sounds = sounds + 1 end
Minimap = { PingLocation = function() pings = pings + 1 end }
UIErrorsFrame = { AddMessage = function(_, m) shown[#shown + 1] = m end }
local me, done = 1000, true
C_QuestLog = { GetNumQuestLogEntries = function() return 1 end, GetInfo = function() return { questID = 7, title = "Wolves" } end,
    IsComplete = function() return done end }
local db, said = {}, {}
local addon = { GetDB = function() return db end, Print = function(s) said[#said + 1] = s end }
local ns = { L = function(s) return s end, addon = addon, data = { Field = function() return { { 1 }, {} } end },
    api = { hbd = { GetPlayerWorldPosition = function() return me, 0, 1 end },
        AddNpcs = function(l) l[#l + 1] = { instance = 1, x = 0, y = 0 } end, D2 = function(a, b, c, d) return (a - c) ^ 2 + (b - d) ^ 2 end } }
assert(loadfile("ForeverLazy/HandInPing.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

test("walking up to a finished quest's person: message, sound and minimap ping", function()
    tick(nil, 2); assert(sounds == 0)
    me = 30; tick(nil, 2)
    assert(sounds == 1 and pings == 1 and shown[1] == "Hand in: Wolves", tostring(shown[1]))
end)
test("the compass reaching the same hand-in a moment later does not signal twice", function()
    clock = clock + 2
    assert(addon.HandInSignal({ name = "4. Turn in: Wolves" }) == true)
    assert(sounds == 1 and pings == 1)
end)
test("the compass signals by itself when nothing else has, with a clean name", function()
    clock = clock + 60
    addon.HandInSignal({ name = "4. Turn in: Bears" })
    assert(sounds == 2 and pings == 2 and shown[#shown] == "Hand in: Bears", tostring(shown[#shown]))
end)
test("with the ping off the compass is told, so the plain arrival sound is used", function()
    db.handInPing, clock = false, clock + 60
    assert(addon.HandInSignal({ name = "Turn in: Bears" }) == false and sounds == 2)
    db.handInPing = nil
end)
test("/lazy ping test plays it, /lazy ping check lists finished quests and distances", function()
    addon:HandleExtraCommand("ping", "test")
    assert(sounds == 3 and pings == 3)
    assert(table.concat(said, "\n"):find("Minimap ping: sent"), "the test does not report")
    said = {}
    addon:HandleExtraCommand("ping", "check")
    local all = table.concat(said, "\n")
    assert(all:find("Wolves %(7%): complete true") and all:find("nearest 30 yd") and all:find("already pinged true"), all)
    done = false; said = {}
    addon:HandleExtraCommand("ping", "check")
    assert(table.concat(said, "\n"):find("no finished quest"))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
