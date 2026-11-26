-- Quest map spots (no game needed): lua tests/questmap.lua
CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
local addon = { GetDB = function() return {} end, Print = function() end }
local fields = {
    [1] = { npcDrops = {}, objectDrops = { 500 } },                     -- from the ground and from many mobs
}
for i = 1, 60 do fields[1].npcDrops[i] = 1000 + i end
local function Fill(list, n, map) for i = 1, n do list[#list + 1] = { uiMapId = map, zx = i / 1000, zy = 0.5 } end end
local ns = {
    L = function(s) return s end, addon = addon, dataset = {},
    data = { Field = function(_, id, field) return fields[id] and fields[id][field] end },
    api = {
        AddNpcs = function(list, ids) for _ in ipairs(ids) do Fill(list, 10, 1) end end,
        AddObjects = function(list, ids) if ids[1] == 500 then Fill(list, 200, 1); Fill(list, 20, 2) end end,
    },
}
assert(loadfile("ForeverLazy/QuestMap.lua"))("ForeverLazy", ns)
local S = addon.QuestMapSpots

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function count(list, map, object)
    local n = 0
    for _, s in ipairs(list) do if s.uiMapId == map and (s.object == true) == object then n = n + 1 end end
    return n
end

test("an item from mobs and from the ground keeps both", function()
    local l = S.Pick(S.Gather({ store = "items", ids = { 1 } }))
    assert(count(l, 1, true) == 150, "objects in zone 1: " .. count(l, 1, true))
    assert(count(l, 1, false) == 45, "mobs in zone 1: " .. count(l, 1, false))
end)
test("a full zone does not push out another zone's spots", function()
    local l = S.Pick(S.Gather({ store = "items", ids = { 1 } }))
    assert(count(l, 2, true) == 20)
end)
test("an object objective is marked as on the ground", function()
    local l = S.Gather({ store = "objects", ids = { 500 } })
    assert(#l == 220 and l[1].object)
end)
test("a kill objective is not", function()
    local l = S.Gather({ store = "npcs", ids = { 7 } })
    assert(#l == 10 and not l[1].object)
end)

test("a far quest is not hidden by many nearer spots", function()
    local l = {}
    for _ = 1, 700 do l[#l + 1] = { c = { kind = "object", title = "Near", uiMapId = 1 } } end
    local far = { c = { kind = "kill", title = "Far", uiMapId = 1 } }
    l[#l + 1] = far
    local out = addon.QuestMapBudget(l, 600, { [1] = true })
    assert(#out == 600 and out[600] == far)
end)
test("the zone on the map is served before other zones", function()
    local l = {}
    for _ = 1, 10 do l[#l + 1] = { c = { kind = "kill", title = "Other zone", uiMapId = 2 } } end
    for _ = 1, 10 do l[#l + 1] = { c = { kind = "kill", title = "Viewed", uiMapId = 1 } } end
    local out = addon.QuestMapBudget(l, 10, { [1] = true })
    assert(#out == 10)
    for _, e in ipairs(out) do assert(e.c.uiMapId == 1) end
end)
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
