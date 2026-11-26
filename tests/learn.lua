-- Learning about creatures (no game needed): lua tests/learn.lua
-- The game blocks CheckInteractDistance during a fight, so it must not be asked then.
local combat, distanceAsked = false, 0
InCombatLockdown = function() return combat end
CheckInteractDistance = function() distanceAsked = distanceAsked + 1; return false end
local frames = {}
CreateFrame = function()
    local f = { events = {} }
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.UnregisterEvent = function() end
    f.SetScript = function(self, _, fn) self.on = fn end
    frames[#frames + 1] = f
    return f
end
UnitExists = function() return true end
UnitIsPlayer = function() return false end
UnitGUID = function() return "Creature-0-1-2-3-1234-0000000000" end
UnitName = function() return "Wolf" end
UnitLevel = function() return 12 end
strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
    return table.unpack(out)
end

local root = {}
local addon = { GetRoot = function() return root end, GetDB = function() return {} end, Print = function() end }
assert(loadfile("ForeverLazy/Learn.lua"))("ForeverLazy", { L = function(s) return s end, addon = addon, api = {} })
local on
for _, f in ipairs(frames) do if f.events.PLAYER_TARGET_CHANGED then on = f.on end end

local passed, failed = 0, 0
local function test(label, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. label) else failed = failed + 1; print("FAIL  " .. label .. "\n      " .. tostring(err)) end
end

test("out of a fight the distance is asked", function()
    on(nil, "PLAYER_TARGET_CHANGED")
    assert(distanceAsked == 1 and root.own.npcs[1234].name == "Wolf")
end)
test("in a fight it is never asked, and the creature is still remembered", function()
    combat, root.own = true, nil
    for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do on(nil, e, "nameplate1") end
    assert(distanceAsked == 1, "asked in combat")
    assert(root.own.npcs[1234].maxLevel == 12)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
