-- Offline test for the spell rank swap: an old rank on the bar is replaced by the newest rank in the spellbook.
--   lua tests/rankup.lua
local root = (arg and arg[0] or "tests/rankup.lua"):gsub("[/\\]tests[/\\]rankup%.lua$", ""):gsub("^tests[/\\]rankup%.lua$", ".")

local said = {}
local db = {}
local addon = { Print = function(m) said[#said + 1] = m end, GetDB = function() return db end }
local ns = { addon = addon }
ns.L = function(t) return t end

-- the game, as the Forever client shows it: a spellbook that lists every rank, bars that hold spell ids
local spells = {
    [100] = { name = "Seal of Command", sub = "Rank 1" }, [101] = { name = "Seal of Command", sub = "Rank 2" },
    [200] = { name = "Judgement", sub = "" },
    [300] = { name = "Holy Strike", sub = "Rank 3" }, [301] = { name = "Holy Strike", sub = "Rank 4" },
}
local book = { 100, 101, 200, 300, 301 }
local bars = {}
local cursor
local placed = {}
C_Spell = {
    GetSpellName = function(id) return spells[id] and spells[id].name end,
    GetSpellSubtext = function(id) return spells[id] and spells[id].sub end,
    PickupSpell = function(id) cursor = id end,
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end,
    GetSpellBookItemInfo = function(i)
        local id = book[i]
        return { spellID = id, name = spells[id].name, subName = spells[id].sub, isPassive = false }
    end,
}
Enum = { SpellBookSpellBank = { Player = 0 } }
function GetActionInfo(slot) local id = bars[slot]; if id then return "spell", id end end
function GetCursorInfo() if cursor then return "spell", cursor end end
function ClearCursor() cursor = nil end
function PlaceAction(slot) bars[slot] = cursor; placed[#placed + 1] = slot; cursor = nil end
function InCombatLockdown() return false end
local onEvent
function CreateFrame()
    local f = setmetatable({}, { __index = function() return function() end end })
    f.SetScript = function(_, n, fn) if n == "OnEvent" then onEvent = fn end end
    return f
end
C_Timer = { After = function(_, fn) fn() end }

assert(loadfile(root .. "/ForeverLazy/RankUp.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

test("an old rank on the bar is replaced by the newest rank", function()
    bars = { [1] = 100, [2] = 200, [3] = 300 }
    placed, said = {}, {}
    addon.RankUpRun()
    assert(bars[1] == 101, "Seal of Command should be rank 2 now, got " .. tostring(bars[1]))
    assert(bars[3] == 301, "Holy Strike should be rank 4 now, got " .. tostring(bars[3]))
    assert(bars[2] == 200, "a spell without ranks must stay")
    assert(#placed == 2, "two spells were swapped")
    assert(said[1] and said[1]:find("2 spells"), "it should say what it did: " .. tostring(said[1]))
end)

test("bars that already hold the newest rank are left alone", function()
    bars = { [1] = 101, [3] = 301 }
    placed, said = {}, {}
    addon.RankUpRun()
    assert(#placed == 0, "nothing should be swapped")
    assert(said[1] and said[1]:find("nothing to change"), "it should say so: " .. tostring(said[1]))
end)

test("the automatic swap is off by default: learning a spell changes nothing", function()
    db.rankUp = nil
    bars = { [1] = 100 }
    placed = {}
    onEvent(nil, "SPELLS_CHANGED")
    assert(bars[1] == 100 and #placed == 0, "nothing swapped on its own")
end)

test("with the automatic swap on, learning a spell swaps the bars", function()
    db.rankUp = true
    bars = { [1] = 100 }
    placed = {}
    onEvent(nil, "SPELLS_CHANGED")
    assert(bars[1] == 101, "swapped by itself: " .. tostring(bars[1]))
    db.rankUp = nil
end)

test("asking for it (the button or /lazy rankup) works even with the automatic swap off", function()
    db.rankUp = nil
    bars = { [1] = 100 }
    placed = {}
    addon.RankUpRun()
    assert(bars[1] == 101, "swapped when asked: " .. tostring(bars[1]))
end)

test("it waits when you are carrying something on the cursor", function()
    cursor = 999
    bars = { [1] = 100 }
    placed = {}
    addon.RankUpRun()
    assert(bars[1] == 100 and #placed == 0)
    cursor = nil
end)

test("a spell I chose to keep is left on its low rank, the others are still swapped", function()
    bars = { [1] = 100, [3] = 300 }
    placed = {}
    addon:HandleExtraCommand("rankup", "keep Seal of Command")
    addon.RankUpRun()
    assert(bars[1] == 100, "the kept spell must stay at rank 1")
    assert(bars[3] == 301, "the other spell is still swapped")
    addon:HandleExtraCommand("rankup", "unkeep Seal of Command")
    addon.RankUpRun()
    assert(bars[1] == 101, "after unkeep it is swapped again")
end)

test("a spell link works for keep", function()
    bars = { [3] = 300 }
    placed = {}
    addon:HandleExtraCommand("rankup", "keep |cff71d5ff|Hspell:300|h[Holy Strike]|h|r")
    addon.RankUpRun()
    assert(bars[3] == 300, "Holy Strike, kept through a link, stays at rank 3")
    db.rankKeep = nil
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end