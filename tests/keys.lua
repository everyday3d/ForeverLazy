-- Offline test: keys get no item button.   lua tests/keys.lua
local root = (arg and arg[0] or "tests/keys.lua"):gsub("[/\\]tests[/\\]keys%.lua$", ""):gsub("^tests[/\\]keys%.lua$", ".")
local f = assert(io.open(root .. "/ForeverLazy/Tracker.lua", "rb")); local src = f:read("*a"); f:close()
local from = src:find("function addon.IsKeyItem", 1, true)
local to = src:find("local function SpecialItem", 1, true)
assert(from and to and to > from, "the key check is in Tracker.lua")
local db = {}
local addon = { GetDB = function() return db end }
local classes = { [277507] = 12, [1] = 13, [2] = 0 }          -- the Dalaran Sewer Key is a quest item (12), a normal key is class 13
local names = { [277507] = "Dalaran Sewer Key", [1] = "Skeleton Key", [2] = "Linen Cloth", [3] = "Key to the City" }
C_Item = { GetItemInfoInstant = function(id) return id, "t", "s", "", 0, classes[id] end }
function GetItemInfo(id) return names[id] end
assert(load(src:sub(from, to - 1), "keys", "t", setmetatable({ addon = addon, C_Item = C_Item, GetItemInfo = GetItemInfo, tostring = tostring, tonumber = tonumber, type = type, pcall = pcall }, { __index = _G })))()
local passed, failed = 0, 0
local function test(n, fn) local ok, e = pcall(fn); if ok then passed = passed + 1; print("ok    " .. n) else failed = failed + 1; print("FAIL  " .. n .. "\n      " .. tostring(e)) end end
test("a quest item named ... Key is a key", function() assert(addon.IsKeyItem("|cff|Hitem:277507::::|h[Dalaran Sewer Key]|h|r")) end)
test("the game's Key class is a key", function() assert(addon.IsKeyItem(1)) end)
test("a name that starts with Key to is a key", function() assert(addon.IsKeyItem(3)) end)
test("an ordinary item is not", function() assert(not addon.IsKeyItem(2)) assert(not addon.IsKeyItem(nil)) end)
test("/lazy keys show brings keys back", function() db.keyButtons = true; assert(not addon.IsKeyItem(277507)); db.keyButtons = nil end)
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)