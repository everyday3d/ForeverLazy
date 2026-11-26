-- A player's spec on the tooltip (no game needed): lua tests/tipspec.lua
-- A pretend game answers the inspect questions. It cannot say whether the real game gives these answers.
local now = 1000
GetTime = function() return now end
local combat = false
InCombatLockdown = function() return combat end
local timers = {}
C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = now + seconds, fn = fn } end }
local function Wait(seconds)                 -- let time pass, running what falls due in order
    local goal = now + seconds
    while true do
        local best
        for i, t in ipairs(timers) do if t.at <= goal and (not best or t.at < timers[best].at) then best = i end end
        if not best then break end
        local t = table.remove(timers, best)
        now = t.at
        t.fn()
    end
    now = goal
end

local onEvent
CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function(_, _, fn) onEvent = fn end }
end

local units = {
    mouseover = { guid = "P-1", player = true, level = 40 },
}
UnitExists = function(u) return units[u] ~= nil end
UnitIsPlayer = function(u) return units[u] and units[u].player end
UnitGUID = function(u) return units[u] and units[u].guid end
UnitLevel = function(u) return units[u] and units[u].level end
UnitIsUnit = function(a, b) return units[a] ~= nil and units[b] ~= nil and units[a].guid == units[b].guid end

-- the tooltip: a list of lines
local lines, hook = {}, nil
GameTooltip = {
    shown = true,
    IsShown = function(self) return self.shown end,
    Show = function() end,
    NumLines = function() return #lines end,
    AddLine = function(_, text)
        lines[#lines + 1] = text
        local n = #lines
        _G["GameTooltipTextLeft" .. n] = { SetText = function(_, t) lines[n] = t end }
    end,
    HookScript = function(_, _, fn) hook = fn end,
}
local function Point()                        -- the game builds the tooltip afresh and calls the hook
    lines = {}
    GameTooltip:AddLine("Some Player")
    hook(GameTooltip)
end
local function SpecLine() for _, l in ipairs(lines) do if l:find("^Spec: ") then return l end end end
local function SpecLines() local n = 0; for _, l in ipairs(lines) do if l:find("^Spec: ") then n = n + 1 end end return n end

local asked, cleared = {}, 0
CanInspect = function(u) return units[u] and units[u].far ~= true end
NotifyInspect = function(u) asked[#asked + 1] = units[u].guid end
ClearInspectPlayer = function() cleared = cleared + 1 end
hooksecurefunc = function(name, after)
    local real = _G[name]
    _G[name] = function(...) real(...); after(...) end
end

-- the talent set: three groups; nodes carry points
local spent = { { 31, "ranksPurchased" }, { 20, "ranksPurchased" }, { 0, "ranksPurchased" } }
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 900 } } end,
    GetGroupDisplayInfoByTreeID = function()
        return { { groupID = 12, orderIndex = 2, displayName = "Protection" }, { groupID = 11, orderIndex = 1, displayName = "Holy" },
                 { groupID = 13, orderIndex = 3, displayName = "Retribution" } }
    end,
    GetTreeNodes = function() return { 1, 2, 3 } end,
    GetNodeInfo = function(_, id)
        local s = spent[id]
        return { groupIDs = { 10 + id }, [s[2]] = s[1] }
    end,
}

local said = {}
local db = {}
local addon = { GetDB = function() return db end, Print = function(s) said[#said + 1] = s end }
assert(loadfile("ForeverLazy/TipSpec.lua"))("ForeverLazy", { L = function(s) return s end, addon = addon })
local T = addon.TipSpec

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function Said(words) for _, s in ipairs(said) do if s:find(words, 1, true) then return true end end return false end
local function Ready(guid) onEvent(nil, "INSPECT_READY", guid) end
local function NewPlayer(guid) units.mouseover = { guid = guid, player = true, level = 40 }; Wait(10) end

test("the name is the tree with most points, with the three counts in the game's order", function()
    assert(T.Format({ { name = "Holy", points = 31 }, { name = "Protection", points = 20 }, { name = "Retribution", points = 0 } }) == "Holy (31/20/0)")
    assert(T.Format({ { name = "A", points = 0 }, { name = "B", points = 0 } }) == nil)
    local trees, total = T.Count({ { id = 2, order = 2, name = "B" }, { id = 1, order = 1, name = "A" } },
        { { groupIDs = { 99, 2 }, ranksPurchased = 3 }, { groupIDs = { 1 }, ranksPurchased = 1 }, { groupIDs = {}, ranksPurchased = 5 } })
    assert(total == 4 and trees[1].name == "A" and trees[1].points == 1 and trees[2].points == 3)
end)

test("off until turned on: no line and nobody is asked about", function()
    Point()
    assert(not SpecLine() and #asked == 0)
end)

test("pointing at a player asks once, then the same line shows the answer", function()
    db.tipSpec = true
    Point()
    assert(SpecLine() == "Spec: reading..." and #asked == 1)
    Point()
    assert(#asked == 1, "asked again while waiting")
    Ready("P-1")
    assert(SpecLine() == "Spec: Holy (31/20/0)", tostring(SpecLine()))
    assert(SpecLines() == 1 and cleared == 1)
end)

test("it is remembered: no second question", function()
    Wait(60)
    Point()
    assert(SpecLine() == "Spec: Holy (31/20/0)" and #asked == 1)
end)

test("an answer filled in only as 'active' ranks still counts", function()
    spent = { { 5, "activeRank" }, { 0, "activeRank" }, { 11, "activeRank" } }
    NewPlayer("P-2")
    Point(); Ready("P-2")
    assert(SpecLine() == "Spec: Retribution (5/0/11)", tostring(SpecLine()))
end)

test("talents that arrive a moment late are read again", function()
    spent = { { 0, "ranksPurchased" }, { 0, "ranksPurchased" }, { 0, "ranksPurchased" } }
    NewPlayer("P-3")
    Point(); Ready("P-3")
    assert(SpecLine() == "Spec: reading...")
    spent[2] = { 12, "ranksPurchased" }
    Wait(0.4)
    assert(SpecLine() == "Spec: Protection (0/12/0)", tostring(SpecLine()))
end)

test("a player with nothing spent says so, after the later reads", function()
    spent = { { 0, "ranksPurchased" }, { 0, "ranksPurchased" }, { 0, "ranksPurchased" } }
    NewPlayer("P-4")
    Point(); Ready("P-4"); Wait(2)
    assert(SpecLine() == "Spec: no talents spent", tostring(SpecLine()))
end)

test("no answer: says not available, and does not keep asking", function()
    NewPlayer("P-5")
    Point()
    local n = #asked
    Wait(5)
    assert(SpecLine() == "Spec: not available")
    Point()
    assert(#asked == n)
end)

test("if another addon asks about someone else, their talents are not pinned on this player", function()
    spent = { { 0, "ranksPurchased" }, { 0, "ranksPurchased" }, { 0, "ranksPurchased" } }
    NewPlayer("P-6")
    Point(); Ready("P-6")
    units.target = { guid = "P-OTHER", player = true, level = 40 }
    NotifyInspect("target")
    spent[1] = { 40, "ranksPurchased" }
    Wait(2)
    assert(SpecLine() == "Spec: reading...", tostring(SpecLine()))
    units.target = nil
end)

test("an answer about someone I no longer point at does not touch this tooltip", function()
    spent = { { 31, "ranksPurchased" }, { 20, "ranksPurchased" }, { 0, "ranksPurchased" } }
    NewPlayer("P-7")
    Point()
    units.mouseover = { guid = "NPC", player = false }
    Point()
    Ready("P-7")
    assert(not SpecLine())
end)

test("moving quickly between players spaces the questions out", function()
    NewPlayer("P-8"); Point()
    local n = #asked
    units.mouseover = { guid = "P-9", player = true, level = 40 }
    Point()
    assert(#asked == n, "asked too soon")
    Wait(2)
    assert(#asked == n + 1 and asked[#asked] == "P-9")
end)

test("nothing is asked in a fight, from too far away, or about players under 10", function()
    local n = #asked
    combat = true; NewPlayer("P-10"); Point(); combat = false
    assert(not SpecLine())
    NewPlayer("P-11"); units.mouseover.far = true; Point()
    assert(not SpecLine())
    NewPlayer("P-12"); units.mouseover.level = 6; Point()
    assert(not SpecLine() and #asked == n)
end)

test("my own tooltip shows my spec without asking", function()
    local n = #asked
    NewPlayer("ME"); units.player = units.mouseover
    Point()
    assert(SpecLine() == "Spec: Holy (31/20/0)" and #asked == n)
    units.player = nil
end)

test("/lazy spec turns it on and off, and check reports what the game answered", function()
    assert(addon:HandleExtraCommand("spec", "off") and db.tipSpec == nil)
    addon:HandleExtraCommand("spec", "")
    assert(db.tipSpec == true)
    addon:HandleExtraCommand("spec", "check")
    assert(Said("target a player first"))
    units.target = { guid = "P-20", player = true, level = 40 }
    Wait(10)
    addon:HandleExtraCommand("spec", "check")
    Ready("P-20")
    assert(Said("Holy 31, Protection 20, Retribution 0"))
    local real = C_Traits.GetConfigInfo
    C_Traits.GetConfigInfo = function() return nil end
    Wait(10)
    addon:HandleExtraCommand("spec", "check"); Ready("P-20"); Wait(2)
    assert(Said("no talent set"))
    C_Traits.GetConfigInfo = real
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
