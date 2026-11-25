-- Offline test for the bank bag slots row: which state each slot is in.   lua tests/bankslots.lua
local root = (arg and arg[0] or "tests/bankslots.lua"):gsub("[/\\]tests[/\\]bankslots%.lua$", ""):gsub("^tests[/\\]bankslots%.lua$", ".")
local addon = { Print = function() end, GetDB = function() return {} end }
local ns = { addon = addon, L = function(x) return x end }
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
assert(loadfile(root .. "/ForeverLazy/BankSlots.lua"))("ForeverLazy", ns)
local passed, failed = 0, 0
local function test(n, fn) local ok, e = pcall(fn); if ok then passed = passed + 1; print("ok    " .. n) else failed = failed + 1; print("FAIL  " .. n .. "\n      " .. tostring(e)) end end
local function eq(a, b, m) if a ~= b then error((m or "differs") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end

test("slots I own are bags or empty, the next one is for sale, the rest are locked", function()
    local s = addon.BankSlotStates(3, 7, function(i) return i == 1 or i == 3 end)
    eq(s[1], "bag"); eq(s[2], "empty", "bought but nothing in it: put a bag here"); eq(s[3], "bag")
    eq(s[4], "buy"); eq(s[5], "locked"); eq(s[7], "locked")
end)
test("no slots bought: the first one is for sale", function()
    local s = addon.BankSlotStates(0, 7, nil)
    eq(s[1], "buy"); eq(s[2], "locked")
end)
test("all bought: nothing is for sale", function()
    local s = addon.BankSlotStates(7, 7, function() return true end)
    for i = 1, 7 do eq(s[i], "bag") end
end)
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)