-- Chat name highlighting (no game needed): lua tests/chatname.lua
local now = 100
GetTime = function() return now end
local made = {}
local function Stub()
    local f = { scripts = {}, events = {} }
    f.SetScript = function(self, what, fn) self.scripts[what] = fn end
    f.RegisterEvent = function(self, e) self.events[e] = true end
    made[#made + 1] = f
    return setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
end
CreateFrame = function() return Stub() end
local name, surname = "Tank", "Hanks"
UnitName = function() return name, surname end
GetRealmName = function() return "Some Realm" end
local sounds = 0
PlaySound = function() sounds = sounds + 1 end
local filter
ChatFrame_AddMessageEventFilter = function(_, fn) filter = fn end

local db = { chatWordsOn = true, chatWords = "" }
local root = {}
local addon = { GetDB = function() return db end, GetRoot = function() return root end, Print = function() end }
assert(loadfile("ForeverLazy/ChatTweaks.lua"))("ForeverLazy", { L = function(s) return s end, addon = addon })

local passed, failed = 0, 0
local function test(label, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. label) else failed = failed + 1; print("FAIL  " .. label .. "\n      " .. tostring(err)) end
end
-- true when the line was highlighted, and it must have made a sound exactly then
local function Hit(msg, author)
    now = now + 10
    local before = sounds
    local _, changed = filter(nil, "CHAT_MSG_CHANNEL", msg, author or "Rexxar Smith")
    local lit = changed ~= nil and changed:find("|cffffff00", 1, true) ~= nil
    assert(lit == (sounds > before), "sound and colour disagree for: " .. msg)
    return lit, changed
end

test("my name is first name and surname together", function()
    assert(addon.ChatMyName() == "Tank Hanks", tostring(addon.ChatMyName()))
end)
test("the first name or surname alone is left alone", function()
    for _, m in ipairs({ "LF Tank for Stockade", "need a tank", "tanks?", "Hanks for the help", "TankHanks" }) do
        assert(not Hit(m), m)
    end
end)
test("my full name is highlighted, in any case and with punctuation round it", function()
    for _, m in ipairs({ "Tank Hanks", "hey tank hanks, you there?", "TANK HANKS!", "grats (Tank Hanks)", "Tank Hanks's loot" }) do
        assert(Hit(m), m)
    end
    local _, changed = Hit("hi Tank Hanks")
    assert(changed == "hi |cffffff00Tank Hanks|r", changed)
end)
test("a longer word that only holds my name does not count, but a later real one does", function()
    assert(not Hit("Tank Hankson"))
    assert(not Hit("ShermanTank Hanks"))
    assert(Hit("Tank Hankson meet Tank Hanks"))
end)
test("my own messages are skipped, another Tank's are not", function()
    assert(not Hit("Tank Hanks here", "Tank Hanks"))
    assert(Hit("where is Tank Hanks", "Tank Meta"))
end)
test("words I added work as before", function()
    db.chatWords = "dps, healer"
    assert(Hit("LF DPS") and Hit("healers wanted") and not Hit("LF tank"))
    db.chatWords = ""
end)
test("with no surname the one name counts, only as a whole word", function()
    name, surname = "Thrall", nil
    assert(Hit("hi Thrall") and not Hit("Thrallmar is far"))
    surname = "Some Realm"
    assert(addon.ChatMyName() == "Thrall")
end)

-- levels next to names: what is learned from a unit must be found again under the name chat links carry
test("levels are saved under the full name, so people who share a first name stay apart", function()
    local units = { target = { "Tank", "Meta", 33 }, mouseover = { "Tank", "Hanks", 35 }, party1 = { "Salty Bowls", "Bowls", 16 },
                    party2 = { "Stump", nil, 25 } }
    UnitExists = function(u) return units[u] ~= nil end
    UnitIsPlayer = UnitExists
    UnitName = function(u) return units[u][1], units[u][2] end
    UnitLevel = function(u) return units[u][3] end
    local on
    for _, f in ipairs(made) do if f.scripts.OnEvent and f.events.PLAYER_TARGET_CHANGED then on = f.scripts.OnEvent end end
    assert(on, "no level event frame")
    for _, e in ipairs({ { "PLAYER_TARGET_CHANGED" }, { "UPDATE_MOUSEOVER_UNIT" }, { "UNIT_LEVEL", "party1" }, { "UNIT_LEVEL", "party2" } }) do
        on(nil, e[1], e[2])
    end
    assert(root.chatLevels["Tank Meta"] == 33 and root.chatLevels["Tank Hanks"] == 35, "first names overwrote each other")
    assert(root.chatLevels["Tank"] == nil)
    assert(root.chatLevels["Salty Bowls"] == 16 and root.chatLevels["Salty Bowls Bowls"] == nil, "surname written twice")
    assert(root.chatLevels["Stump"] == 25)
end)
test("on a realm without surnames the second answer is a realm and is left off", function()
    RegionalUniqueNamesEnabled = function() return false end
    UnitName = function() return "Thrall", "Other Realm" end
    assert(addon.ChatMyName() == "Thrall")
    RegionalUniqueNamesEnabled = nil
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
