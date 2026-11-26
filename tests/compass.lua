-- Compass bar extras (no game needed): lua tests/compass.lua
local function Frame()
    local f = { shown = true, scripts = {}, lines = {} }
    f.SetText = function(self, t) self.text = t end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.SetPoint = function(self, _, _, _, x) self.x = x end
    f.SetTexture = function(self, t) self.texture = t end
    f.SetScript = function(self, w, fn) self.scripts[w] = fn end
    f.GetScript = function(self, w) return self.scripts[w] end
    f.GetWidth = function() return 360 end
    f.CreateFontString = function() return Frame() end
    setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    return f
end
local tip = { lines = {} }
GameTooltip = { SetOwner = function() tip.lines = {}; tip.shown = false end, AddLine = function(_, t) tip.lines[#tip.lines + 1] = t end,
    Show = function() tip.shown = true end, Hide = function() tip.shown = false end }
local db = { units = "yd" }
local addon = { GetDB = function() return db end }
assert(loadfile("ForeverLazy/CompassExtras.lua"))("ForeverLazy", { L = function(s) return s end, addon = addon })

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local pi = math.pi

test("ahead is the middle, left is left, behind is nowhere", function()
    assert(addon.CompassOffset(0, 0, 170) == 0)
    assert(addon.CompassOffset(pi / 4, 0, 170) < 0, "a bearing to the left (west of north) goes left")
    assert(addon.CompassOffset(-pi / 4, 0, 170) > 0)
    assert(addon.CompassOffset(pi, 0, 170) == nil)
    assert(math.abs(addon.CompassOffset(0.1, 2 * pi - 0.1, 170) + 170 * 0.2 / (pi / 2)) < 0.001, "across north")
end)
test("which icon a target gets", function()
    assert(addon.CompassKind("3. Turn in: Wolves") == "turnin")
    assert(addon.CompassKind("Pick up: Bears") == "give")
    assert(addon.CompassKind("x", { { label = "Wolf Hunt" } }) == "kill")
    assert(addon.CompassKind("x", { { label = "Turn in: A" }, { label = "B" } }) == "kill")
    assert(addon.CompassKind("My own waypoint") == nil)
end)
test("distances in each unit", function()
    assert(addon.CompassDistance(120, "yd") == "120 yd" and addon.CompassDistance(120, "m") == "109 m")
    assert(addon.CompassDistance(1500, "yd") == "1.5k yd" and addon.CompassDistance(80, "steps") == "100 st")
end)

local bar = Frame()
local function Marker() local m = Frame(); m.tex = Frame(); m.icon = Frame(); return m end
local a, b = Marker(), Marker()
local function Draw()
    addon.CompassDraw(bar, {
        { marker = a, offset = 0, source = { 1, 100, 0, {}, nil, nil, { who = "Next stop", name = "2. Turn in: Wolves" } } },
        { marker = b, offset = 5, source = { 1, 300, 0, {}, nil, nil, { who = "My quest", name = "Bear Hunt", kind = "kill" } } },
    }, 0, 0, 0)
end
test("with everything off, nothing is added but the tooltip", function()
    Draw()
    assert(a.dist.text == "" and not a.icon.texture and not bar.letters)
    a.scripts.OnEnter(a)
    assert(tip.shown and tip.lines[1] == "Turn in: Wolves" and tip.lines[2] == "Next stop  -  100 yd", table.concat(tip.lines, " | "))
    assert(tip.lines[4] == "Bear Hunt", "a marker on top of it is listed too")
    a.scripts.OnLeave(a)
    assert(not tip.shown)
end)
test("distance and icons when ticked; the second of two close markers has no distance", function()
    db.compassDistance, db.compassIcons = true, true
    Draw()
    assert(a.dist.text == "100 yd" and b.dist.text == "")
    assert(a.icon.texture:find("ActiveQuestIcon") and b.icon.texture:find("RaidTargetingIcon_8"))
end)
test("direction letters: north in the middle when I face north, south hidden", function()
    db.compassDirections = true
    Draw()
    assert(bar.letters[1].shown and bar.letters[1].x == 0 and not bar.letters[3].shown)
    assert(bar.letters[2].x < 0 and bar.letters[4].x > 0, "west on the left, east on the right")
    db.compassDirections = nil
    Draw()
    assert(not bar.letters[1].shown)
end)
test("the tooltip goes when its marker leaves the bar", function()
    a.scripts.OnEnter(a)
    addon.CompassDraw(bar, {}, 0, 0, 0)
    assert(not tip.shown and not bar.hover)
end)

test("a picked quest's own stop gets an icon, ? once it is finished", function()
    local done = false
    C_QuestLog = { IsComplete = function() return done end }
    local m = Marker()
    local function One() addon.CompassDraw(bar, { { marker = m, offset = 0, source = { 1, 50, 0, {}, nil, nil, { who = "Next stop", name = "Gnome Improvement", wp = { focusId = 5 } } } } }, 0, 0, 0) end
    db.compassIcons = true
    One(); assert(m.icon.texture:find("RaidTargetingIcon_8"))
    done = true
    One(); assert(m.icon.texture:find("ActiveQuestIcon"))
    C_QuestLog = nil
end)
test("the first time, the compass takes over the arrows' settings; after that the arrows do not matter", function()
    db.compassSplit, db.compassBar = nil, true
    db.hideCombat, db.hideResting, db.locked, db.mode = true, false, true, "quest"
    addon.CompassSettings()
    assert(db.compassHideCombat and not db.compassHideResting and db.compassHideInstance and db.compassLocked and db.compassBar)
    db.hideCombat, db.hideResting, db.mode = false, true, "off"
    addon.CompassSettings()
    assert(db.compassHideCombat and not db.compassHideResting and db.compassBar, "an arrow setting changed the compass")
end)
test("someone who had the arrows off does not suddenly get a compass", function()
    db.compassSplit, db.compassBar, db.mode = nil, true, "off"
    addon.CompassSettings()
    assert(db.compassBar == false)
    db.mode = "quest"
end)
test("hiding follows the compass's own rules", function()
    db.compassSplit, db.compassHideCombat, db.compassHideResting, db.compassHideTaxi, db.compassHideInstance = true, false, false, false, false
    local fighting = true
    UnitAffectingCombat = function() return fighting end
    db.hideCombat = true
    assert(not addon.CompassHidden())
    db.compassHideCombat = true
    assert(addon.CompassHidden())
    fighting = false
    assert(not addon.CompassHidden())
end)
test("size stays within its limits, and the right-click menu switches things", function()
    db.compassScale = 9; assert(addon.CompassScale() == 2)
    db.compassScale = nil; assert(addon.CompassScale() == 1)
    local items
    addon.ShowMenu = function(list) items = list end
    db.compassDirections = nil
    bar.scripts.OnMouseUp(bar, "LeftButton"); assert(not items)
    bar.scripts.OnMouseUp(bar, "RightButton"); assert(items and #items == 8)
    items[1].fn(); assert(db.compassDirections == true)
    items[7].fn(); assert(db.compassBar == false)
    items[5].fn(); assert(db.waypointArrowOff == false, "the arrow starts off, so the menu turns it on")
    addon.CompassMenu(); items[5].fn(); assert(db.waypointArrowOff == true)
    items[4].fn(); assert(db.compassText == true)
end)
test("the next stop in words: only when ticked, with what to do and how far", function()
    local wp = { name = "Turn in: Wolves", detail = "talk to Marshal", x = 120, y = 0, instance = 1 }
    local host = Frame()
    local made
    host.CreateFontString = function() made = Frame(); return made end
    db.compassText = nil
    addon.CompassTargetText(host, wp, 0, 0, 1)
    assert(not made)
    db.compassText = true
    addon.CompassTargetText(host, wp, 0, 0, 1)
    assert(made.shown and made.text == "|cffffd100Turn in: Wolves|r\ntalk to Marshal  -  120 yd", made.text)
    addon.CompassTargetText(host, nil, 0, 0, 1)
    assert(not made.shown)
end)
test("as a ghost the compass stays up and shows my body, with its distance", function()
    local ghost = true
    UnitIsGhost = function() return ghost end
    UnitAffectingCombat = function() return true end
    db.compassSplit, db.compassHideCombat = true, true
    assert(not addon.CompassHidden(), "a hiding rule hid the way to my body")
    ghost = false
    assert(addon.CompassHidden())
    local body = addon.CompassBody(1, 200, 0)
    assert(body.stop.name == "Your corpse" and body.source[6] == nil)
    db.compassDistance, db.compassIcons = nil, nil
    local m = Marker()
    addon.CompassDraw(bar, { { marker = m, offset = 0, source = body.source } }, 0, 0, 0)
    assert(m.dist.text == "200 yd", tostring(m.dist.text))
    assert(m.icon.texture:find("tombstone"), "the body is not a tombstone")
    assert(io.open("ForeverLazy/media/tombstone.tga", "rb"):read("a"):len() == 18 + 64 * 64 * 4, "the picture is missing or the wrong size")
    m.scripts.OnEnter(m)
    assert(tip.lines[1] == "Your corpse" and tip.lines[2] == "Your body  -  200 yd", table.concat(tip.lines, " | "))
    UnitIsGhost = nil
end)
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
