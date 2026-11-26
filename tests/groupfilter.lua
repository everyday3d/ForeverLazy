-- Offline tests for the group finder filter rules (no game needed).
--   lua tests/groupfilter.lua
local root = (arg and arg[0] or "tests/groupfilter.lua"):gsub("[/\\]tests[/\\]groupfilter%.lua$", ""):gsub("^tests[/\\]groupfilter%.lua$", ".")

local db = {}
local addon = { Print = function() end, GetDB = function() return db end }
local ns = { addon = addon, api = {}, L = function(x) return x end }
function CreateFrame()
    local f = setmetatable({}, { __index = function() return function() end end })
    f.SetScript = function() end
    return f
end
function UnitLevel() return 25 end
function select2() end
assert(loadfile(root .. "/ForeverLazy/GroupFilter.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local M = addon.GroupMatches

local solo = { age = 30, numMembers = 1, leader = "Valtos", comment = "", activity = "The Stockade", minLevel = 22, maxSuggest = 30 }
local group = { age = 400, numMembers = 3, leader = "Serj", comment = "need healer, Stockade run", activity = "The Stockade", minLevel = 22, maxSuggest = 30,
                roleOpen = { TANK = 0, HEALER = 1, DAMAGER = 1 } }

test("no filter shows everything", function() assert(M(solo, {}, 25) and M(group, {}, 25)) end)
test("groups only / players only", function()
    assert(not M(solo, { kind = "groups" }, 25)); assert(M(group, { kind = "groups" }, 25))
    assert(M(solo, { kind = "players" }, 25)); assert(not M(group, { kind = "players" }, 25))
end)
test("age limit in minutes", function()
    assert(M(solo, { maxAge = 5 }, 25)); assert(not M(group, { maxAge = 5 }, 25)); assert(M(group, { maxAge = 15 }, 25))
end)
test("a needed role: a full role is hidden, an open one shown", function()
    assert(not M(group, { role = "TANK" }, 25)); assert(M(group, { role = "HEALER" }, 25))
end)
test("a role filter never hides a lone player", function() assert(M(solo, { role = "TANK" }, 25)) end)
test("a role filter keeps a group with no role data", function()
    local g = { age = 1, numMembers = 4, leader = "x", activity = "y" }
    assert(M(g, { role = "TANK" }, 25))
end)
test("right level for me", function()
    assert(M(solo, { fitLevel = true }, 25))
    assert(not M(solo, { fitLevel = true }, 15), "below the minimum")
    assert(not M(solo, { fitLevel = true }, 40), "far above the suggested range")
    assert(M(solo, { fitLevel = true }, 32), "a little above is fine")
end)
test("words match activity, leader and comment, all of them", function()
    assert(M(group, { text = "stockade healer" }, 25))
    assert(M(group, { text = "SERJ" }, 25))
    assert(not M(group, { text = "stockade tank" }, 25))
end)
test("sorting", function()
    local l = addon.GroupSort({ group, solo }, "new"); assert(l[1] == solo)
    l = addon.GroupSort({ solo, group }, "size"); assert(l[1] == group)
end)
test("age text", function()
    assert(addon.GroupAgo(30) == "30s"); assert(addon.GroupAgo(648) == "10m"); assert(addon.GroupAgo(7300) == "2h")
end)

test("roles a started five-player group still needs", function()
    local o = addon.GroupRolesOpen({ TANK = 1, HEALER = 0, DAMAGER = 2 }, 5)
    assert(o.TANK == 0 and o.HEALER == 1 and o.DAMAGER == 1)
    assert(addon.GroupNeeds(o) == "healer, dps")
    assert(M({ numMembers = 3, roleOpen = o }, { role = "HEALER" }, 25))
    assert(not M({ numMembers = 3, roleOpen = o }, { role = "TANK" }, 25))
end)
test("the game's own remaining numbers win", function()
    local o = addon.GroupRolesOpen({ TANK_REMAINING = 0, HEALER_REMAINING = 1, DAMAGER_REMAINING = 0, TANK = 5 }, 5)
    assert(o.HEALER == 1 and o.TANK == 0)
end)
test("a raid or unknown size is left unknown", function()
    assert(addon.GroupRolesOpen({ TANK = 1 }, 10) == nil)
    assert(addon.GroupRolesOpen({ TANK = 1 }, nil) == nil)
    assert(addon.GroupNeeds(nil) == nil)
end)
test("a group that only needs a healer", function()
    local o = addon.GroupRolesOpen({ TANK = 1, HEALER = 0, DAMAGER = 3 }, 5)
    assert(addon.GroupNeeds(o) == "healer")
end)
test("a role filter on a lone player: only the role they play", function()
    local p = { numMembers = 1, role = "DAMAGER", class = "MAGE" }
    assert(M(p, { role = "DAMAGER" }, 25)); assert(not M(p, { role = "TANK" }, 25))
    assert(M({ numMembers = 1 }, { role = "TANK" }, 25))   -- a listing that does not say is kept
end)
test("the role of a lone player is read from a table or from values", function()
    local old = C_LFGList
    C_LFGList = { GetSearchResultPlayerInfo = function() return { assignedRole = "DAMAGER", classFilename = "mage" } end }
    local r, c = addon.GroupPlayerRole(1, {}); assert(r == "DAMAGER" and c == "MAGE")
    C_LFGList = { GetSearchResultPlayerInfo = function() return "TANK", "WARRIOR" end }
    r, c = addon.GroupPlayerRole(1, {}); assert(r == "TANK" and c == "WARRIOR")
    C_LFGList = old
end)
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
