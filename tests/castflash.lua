-- The cast bar flash command and interrupt detection (no game needed): lua tests/castflash.lua
-- A pretend game answers the questions. It cannot say whether the real game gives these answers.
local now = 100
GetTime = function() return now end
local frame = { RegisterEvent = function() end, SetScript = function() end }
CreateFrame = function() return frame end
UnitClass = function() return "Paladin", "PALADIN" end
local names = { [96231] = "Rebuke", [853] = "Hammer of Justice" }
C_Spell = { GetSpellName = function(id) return names[id] end,
            GetSpellCooldown = function() return { startTime = 0, duration = 0 } end }
local casting, target = nil, false
UnitExists = function() return target end
UnitCanAttack = function() return true end
UnitCastingInfo = function() if casting then return casting.name, "", 1, 0, 1, false, "id", casting.locked end end
UnitChannelInfo = function() end

local said, db, book = {}, {}, {}
local addon = { GetDB = function() return db end, Print = function(s) said[#said + 1] = s end,
                SpellsKnown = function() return book end }
assert(loadfile("ForeverLazy/NameplateCasts.lua"))("ForeverLazy", { L = function(s) return s end, addon = addon })

local passed, failed = 0, 0
local function test(label, fn)
    said = {}
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. label)
    else failed = failed + 1; print("FAIL  " .. label .. "\n      " .. tostring(err) .. "\n      " .. table.concat(said, " | ")) end
end
local function Said(words) for _, s in ipairs(said) do if s:find(words, 1, true) then return true end end return false end
local function Run(a) assert(addon:HandleExtraCommand("flash", a)) end

test("/lazy flash turns the option on and off", function()
    Run("on"); assert(db.castFlash == true)
    Run("off"); assert(db.castFlash == nil)
    Run(""); assert(db.castFlash == true)
    Run("off")
end)
test("check says when the flash is off and when no interrupt is found", function()
    Run("check")
    assert(Said("cast bar flash OFF") and Said("no interrupt found"))
end)
test("an interrupt in the spellbook is found even when no spell id test knows it", function()
    book = { ["Hammer of Justice"] = true }; now = now + 10
    Run("check")
    assert(Said("your interrupt is ready: Hammer of Justice"))
end)
test("on cooldown it says so", function()
    C_Spell.GetSpellCooldown = function() return { startTime = 90, duration = 60 } end
    Run("check")
    assert(Said("on cooldown, so no flash right now: Hammer of Justice"))
end)
test("with a target it reports the cast and whether it can be interrupted", function()
    target = true
    Run("check"); assert(Said("reports no cast"))
    casting = { name = "Heal", locked = false }; Run("check"); assert(Said("casting Heal (can be interrupted)"))
    casting = { name = "Roar", locked = true }; Run("check"); assert(Said("can not be interrupted"))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
