-- Fishing zone levels, the fishing route and the fish arrow (no game needed): lua tests/fishroute.lua
local function Frame()
    local f = { shown = true, scripts = {} }
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    f.SetShown = function(self, v) self.shown = v and true or false end
    f.SetText = function(self, t) self.text = t end
    f.SetScript = function(self, w, fn) self.scripts[w] = fn end
    f.CreateFontString = function() return Frame() end
    f.CreateTexture = function() return Frame() end
    setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    return f
end
local made = {}
CreateFrame = function(kind, name) local f = Frame(); f.kind = kind; made[#made + 1] = f; if name then made[name] = f end return f end
UIParent = Frame()

local mapNow, parents = 1429, {}
C_Map = { GetBestMapForUnit = function() return mapNow end, GetMapInfo = function(id) return { parentMapID = parents[id] } end }
local rank, max, level, faction = 1, 75, 5, "Alliance"
UnitLevel = function() return level end
UnitFactionGroup = function() return faction end

local db, said, went, commands = { waypoints = {} }, {}, {}, {}
local pools = {}
local hidden = true
local addon = {
    GetDB = function() return db end, Print = function(s) said[#said + 1] = s end,
    Fish = { Skill = function() return rank, max end },
    GoTo = function(map, zx, zy, name, kind) went[#went + 1] = { map = map, zx = zx, zy = zy, name = name, kind = kind } end,
    PoolSpots = function(cb) cb(pools); return true end,
    ArrowHidden = function() return hidden end,
}
function addon:HandleExtraCommand(cmd, rest)
    commands[#commands + 1] = cmd .. " " .. (rest or "")
    if cmd == "trainer" then table.insert(db.waypoints, 1, { name = "Fishing trainer", service = true }); return true end
end
local ns = { L = function(s) return s end, addon = addon }
assert(loadfile("ForeverLazy/FishRoute.lua"))("ForeverLazy", ns)
local R = addon.FishRoute

local passed, failed = 0, 0
local function test(label, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. label) else failed = failed + 1; print("FAIL  " .. label .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "differs") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end
local function names(list) local t = {}; for _, z in ipairs(list) do t[#t + 1] = z.name end return table.concat(t, ", ") end

test("a zone says its level, and what my skill means there", function()
    local red = R.Zone(1433)
    eq(red.need, 150); eq(red.least, 55)
    eq(R.Verdict(54, red), "none"); eq(R.Verdict(55, red), "some"); eq(R.Verdict(150, red), "good"); eq(R.Verdict(nil, red), nil)
    assert(R.Line(100, red, true):find("150 fishing", 1, true) and R.Line(100, red, true):find("some get away", 1, true))
    assert(R.Line(nil, nil):find("not known", 1, true))
    eq(R.Verdict(300, R.Zone(1452)), "some"); eq(R.Verdict(1, R.Zone(1452)), "some", "no lowest skill is claimed where none was given")
end)

test("every zone has a known level, and route zones have monster levels", function()
    local tiers = { [25] = true, [75] = true, [150] = true, [225] = true, [300] = true, [425] = true }
    local count = 0
    for map, z in pairs(R.ZONES) do
        count = count + 1
        assert(tiers[z[2]], map .. " has a strange level")
        if z[5] then assert(z[3] and z[4] and z[3] <= z[4], z[1] .. " needs monster levels") end
    end
    assert(count == 43, count)
end)

test("the map ids are the game's own, as our zone data has them", function()
    local data = { dataset = {} }
    setmetatable(data.dataset, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end })
    assert(loadfile("ForeverLazy/data/Zones.lua"))("ForeverLazy", data)
    local known = {}
    for _, v in pairs(data.dataset) do
        if type(v) == "table" and v.areaToMap then for _, map in pairs(v.areaToMap) do known[map] = true end end
    end
    for _, map in pairs(data.dataset.areaToMap or {}) do known[map] = true end
    for map, z in pairs(R.ZONES) do assert(known[map], z[1] .. ": map " .. map .. " is not in the zone data") end
end)

test("a new fisher starts at home, on their own side", function()
    local zones, tier, rough = R.Pick(1, "A", 5)
    eq(tier, 25); eq(rough, false); eq(names(zones), "Dun Morogh, Elwynn Forest, Teldrassil")
    zones = R.Pick(nil, "H", 5)
    eq(names(zones), "Durotar, Mulgore, Tirisfal Glades")
end)

test("the route moves up with skill, but not into monsters too strong", function()
    local zones, tier = R.Pick(80, "A", 20); eq(tier, 75); assert(names(zones):find("Westfall", 1, true), names(zones))
    zones, tier = R.Pick(160, "A", 30); eq(tier, 150); assert(names(zones):find("Duskwood", 1, true))
    zones, tier = R.Pick(230, "H", 12); eq(tier, 150, "level 12 can walk into Stonetalon"); eq(names(zones), "Stonetalon Mountains")
    zones, tier = R.Pick(230, "A", 8); eq(tier, 75, "level 8 can still go to the level 10 zones")
    zones, tier = R.Pick(300, "H", 60); eq(tier, 300); assert(not names(zones):find("Redridge", 1, true))
    for _, z in ipairs((R.Pick(300, "A", 60))) do assert(z.side:find("A", 1, true), z.name) end
end)

test("training: what comes next at each limit", function()
    local _, a = R.Training(nil, nil, 5); eq(a, "trainer")
    local words = R.Training(20, 75, 5); assert(words:find("fishing 50", 1, true), words)
    words = R.Training(75, 75, 20); assert(words:find("limit", 1, true) and words:find("Train Journeyman", 1, true), words)
    words, a = R.Training(130, 150, 30); eq(a, "heming"); assert(words:find("Old Man Heming", 1, true))
    words, a = R.Training(225, 225, 40); eq(a, "pagle"); assert(words:find("Nat Pagle", 1, true))
    words, a = R.Training(300, 300, 60); eq(a, nil)
end)

test("the spot is one in the middle of that zone's pools, not another zone's", function()
    local spots = { { uiMapId = 1436, zx = 0.1, zy = 0.1 }, { uiMapId = 1436, zx = 0.5, zy = 0.5 }, { uiMapId = 1436, zx = 0.9, zy = 0.9 },
                    { uiMapId = 1429, zx = 0.5, zy = 0.5 } }
    local s = R.BestSpot(spots, 1436); eq(s.zx, 0.5); eq(s.uiMapId, 1436)
    eq(R.BestSpot(spots, 1432), nil)
end)

test("going to a zone is a fish trip, with a word about the arrow", function()
    pools = { { uiMapId = 1436, zx = 0.3, zy = 0.4 } }
    went, said = {}, {}
    R.GoZone(1436)
    eq(went[1].map, 1436); eq(went[1].zx, 0.3); eq(went[1].kind, "fish")
    assert(table.concat(said, " "):find("/lazy arrow", 1, true))
    went, said, hidden = {}, {}, false
    R.GoZone(1436); eq(#said, 0)
    R.GoZone(1432); eq(#went, 1, "no spot: no arrow"); assert(said[1]:find("any water", 1, true), said[1])
    hidden = true
end)

test("the teachers: fish trips too", function()
    went = {}
    R.Train("heming"); eq(went[1].map, 1434); eq(went[1].kind, "fish")
    R.Train("pagle"); eq(went[2].map, 1445)
    commands, db.waypoints = {}, {}
    R.Train("trainer"); eq(commands[1], "trainer fishing"); eq(db.waypoints[1].fish, true)
end)

test("a cave inside a zone counts as that zone", function()
    mapNow, parents = 9999, { [9999] = 1429 }
    eq(R.Here().name, "Elwynn Forest")
    mapNow, parents = 9998, {}
    eq(R.Here(), nil)
    mapNow = 1429
end)

test("/lazy fish route opens and closes the window; other fish commands pass on", function()
    rank, max, level = 80, 150, 20
    eq(addon:HandleExtraCommand("fish", "route"), true)
    local win = made.ForeverLazy_FishRoute; assert(win and win.shown, "no window")
    local zoneButtons = {}
    for _, f in ipairs(made) do if f.kind == "Button" and f.map and f.shown then zoneButtons[#zoneButtons + 1] = f end end
    assert(#zoneButtons >= 2 and #zoneButtons <= 4, #zoneButtons)
    pools, went = { { uiMapId = zoneButtons[1].map, zx = 0.2, zy = 0.2 } }, {}
    zoneButtons[1].scripts.OnClick(zoneButtons[1]); eq(went[1].kind, "fish")
    eq(addon:HandleExtraCommand("fish", "route"), true); eq(win.shown, false)
    commands = {}; addon:HandleExtraCommand("fish", "2"); eq(commands[1], "fish 2")
end)

test("the arrow, the plan and the trip all know about the fish", function()
    local function Read(path) local f = assert(io.open(path, "rb")); local t = f:read("a"); f:close(); return t end
    assert(Read("ForeverLazy/ForeverLazy.lua"):find('MEDIA .. "arrow_fish"', 1, true))
    assert(Read("ForeverLazy/Go.lua"):find("fish = trip.dest.fish", 1, true))
    assert(Read("ForeverLazy/Extras.lua"):find("wp and wp.fish", 1, true))
    local tga = Read("ForeverLazy/media/arrow_fish.tga")
    eq(#tga, 18 + 64 * 64 * 4)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
