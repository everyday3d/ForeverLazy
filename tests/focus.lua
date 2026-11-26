-- Clicking a quest to do it next (no game needed): lua tests/focus.lua
local function Frame() return setmetatable({}, { __index = function() return function() return Frame() end end }) end
CreateFrame = function() return Frame() end
UIParent, UISpecialFrames, GameTooltip = Frame(), {}, Frame()
tinsert = table.insert

local db = { waypoints = {} }
local plans, spawns, said = 0, {}, {}
local addon = { GetDB = function() return db end, Print = function(s) said[#said + 1] = s end, RefreshPins = function() end,
    LocalizeLabel = function(s) return s end }
function addon:AddWaypointZone(map, zx, zy, name) table.insert(db.waypoints, 1, { name = name, uiMapId = map, zx = zx, zy = zy, x = zx, y = zy, instance = 1 }) end
function addon:PlanRoute() plans = plans + 1 end
addon.QuestLogSpawns = function() return spawns end
local X = setmetatable({ PlainTitle = function(s) return s end, ApplyFocus = function() end, LastPlanAll = function() return false end }, { __index = function() return function() end end })
local ns = { L = function(s) return s end, addon = addon, extras = X, LocalizeLabel = function(s) return s end,
    api = { hbd = { GetPlayerWorldPosition = function() return 0, 0, 1 end } } }
assert(loadfile("ForeverLazy/PlanMenus.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

test("a quest with a stop in front gets no extra one", function()
    db.waypoints = { { name = "1. Wolves", quests = { { id = 7 } } } }
    addon:FocusQuest(7, "Wolves")
    assert(#db.waypoints == 1 and db.planFocus.id == 7)
end)
test("a quest the plan leaves out gets a stop of its own at the nearest spot", function()
    db.waypoints = { { name = "1. Wolves", quests = { { id = 7 } } } }
    spawns = { { id = 9, spawns = { { uiMapId = 2, x = 500, y = 0, zx = 0.5, zy = 0.5, instance = 1 }, { uiMapId = 2, x = 20, y = 0, zx = 0.2, zy = 0.2, instance = 1 } } } }
    addon:FocusQuest(9, "Bears")
    assert(#db.waypoints == 2 and db.waypoints[1].focusId == 9 and db.waypoints[1].zx == 0.2)
end)
test("clicking it again adds nothing, and picking another quest takes the old stop away", function()
    addon:FocusQuest(9, "Bears")
    assert(#db.waypoints == 2)
    addon:FocusQuest(7, "Wolves")
    assert(#db.waypoints == 1 and not db.waypoints[1].focusId)
end)
test("a quest with no known place says so", function()
    spawns = {}
    addon:FocusQuest(11, "Mystery")
    local told = false
    for _, s in ipairs(said) do if s:find("no place known") then told = true end end
    assert(told and #db.waypoints == 1)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
