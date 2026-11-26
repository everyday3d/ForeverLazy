-- Library book pins on the map: hover and right-click (no game needed): lua tests/bookpins.lua
local function Frame()
    local f = { scripts = {} }
    f.SetScript = function(self, w, fn) self.scripts[w] = fn end
    f.EnableMouse = function(self, v) self.mouse = v end
    f.CreateTexture = function() return Frame() end
    f.CreateFontString = function() return Frame() end
    setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    return f
end
local made = {}
CreateFrame = function() local f = Frame(); made[#made + 1] = f; return f end
UIParent, UISpecialFrames, SlashCmdList = Frame(), {}, {}
tinsert = table.insert
local tip = {}
GameTooltip = { SetOwner = function() tip = {} end, AddLine = function(_, t) tip[#tip + 1] = t end, Show = function() end, Hide = function() end }
UnitName = function() return "Tank" end
GetRealmName = function() return "Forever" end
UnitLevel = function() return 60 end
-- the game's map names, read from the book list itself
local zoneName = { [1436] = "Westfall" }
for zone, id in io.open("ForeverLazy/Books.lua", "rb"):read("a"):gmatch([[{ "([^"]+)",%s+(%d+),]]) do zoneName[tonumber(id)] = zone end
C_Map = { GetMapInfo = function(id) return zoneName[id] and { name = zoneName[id] } end, GetMapChildrenInfo = function() return {} end, GetAreaInfo = function() end }
local placed = {}
local pins = { RemoveAllWorldMapIcons = function() placed = {} end, AddWorldMapIconWorld = function(_, _, f) placed[#placed + 1] = f end }
local hbd = { GetWorldCoordinatesFromZone = function(_, x, y) return x * 1000, y * 1000, 1 end, GetPlayerWorldPosition = function() return 0, 0, 1 end,
    GetPlayerZone = function() return 1 end, GetLocalizedMap = function() return "x" end, GetAllMapIDs = function() return {} end }
LibStub = function(name) if tostring(name):find("Pins") then return pins end return setmetatable({}, { __index = function() return function() end end }) end

local db, root = { waypoints = {} }, {}
local said = {}
local addon = { GetDB = function() return db end, GetRoot = function() return root end, Print = function(s) said[#said + 1] = s end,
    RefreshPins = function() end, ModuleOn = function() return true end, RegisterComm = function() end }
local ns = { L = function(s) return s end, addon = addon, api = { hbd = hbd, D2 = function() return 0 end } }
local chunk = assert(loadfile("ForeverLazy/Books.lua"))
local ok, err = pcall(chunk, "ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local good, why = pcall(fn)
    if good then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(why)) end
end

test("the book file loads", function() assert(ok, err) end)

local entry = { "Westfall", 1436, 52.4, 53.1, "The Test Book (inside the tower)*" }
test("hovering says which book, where, and whether I have it", function()
    local f = Frame()
    addon.BookPinHover(f, entry)
    assert(f.mouse == true)
    f.scripts.OnEnter(f)
    assert(tip[1] == "The Test Book", tostring(tip[1]))
    assert(tip[2] == "Westfall  52, 53" and tip[3] == "inside the tower", table.concat(tip, " | "))
    assert(tip[4]:find("Not collected yet") and tip[5]:find("Right%-click"))
end)

test("right-click offers collected, not collected and the arrow; left-click does nothing", function()
    local f = Frame()
    addon.BookPinHover(f, entry)
    local items, title
    addon.ShowMenu = function(list, t) items, title = list, t end
    f.scripts.OnMouseUp(f, "LeftButton"); assert(not items)
    f.scripts.OnMouseUp(f, "RightButton")
    assert(items and #items == 3 and title == "The Test Book")
    db.waypoints = { { name = "x", book = "The Test Book" }, { name = "keep" } }
    items[1].fn()
    assert(addon.BookPinLines(entry)[4]:find("Collected") and not addon.BookPinLines(entry)[4]:find("Not"))
    assert(#db.waypoints == 1 and db.waypoints[1].name == "keep", "the collected book's waypoint should go")
    items[2].fn()
    assert(addon.BookPinLines(entry)[4]:find("Not collected yet"))
    items[3].fn()
    assert(db.waypoints[1].book == "The Test Book", "the arrow's waypoint is in front")
end)

test("a stop that is not a book only says its name, and has no menu", function()
    local f, opened = Frame(), false
    addon.ShowMenu = function() opened = true end
    addon.BookPinHover(f, nil, "3. Kill wolves")
    f.scripts.OnEnter(f)
    assert(#tip == 1 and tip[1] == "3. Kill wolves")
    f.scripts.OnMouseUp(f, "RightButton")
    assert(not opened)
    addon.BookPinHover(f, nil, nil)
    assert(f.mouse == false, "an empty pin must let the mouse through")
end)

test("every book pin on the world map gets a hover", function()
    addon.RefreshBookPins()
    assert(#placed > 10, "pins placed: " .. #placed)
    for _, f in ipairs(placed) do assert(f.mouse and f.bookEntry and f.scripts.OnEnter) end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
