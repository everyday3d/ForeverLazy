-- Battleground helpers (no game needed): lua tests/battleground.lua
-- The game is stood in for here, so this cannot say what WoW Forever's battlegrounds really send.
local now = 1000
GetTime = function() return now end
local shift = false
IsShiftKeyDown = function() return shift end

local function Frame()
    local f = { shown = true, scripts = {} }
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.SetShown = function(self, v) self.shown = v and true or false end
    f.SetScript = function(self, w, fn) self.scripts[w] = fn end
    f.GetPoint = function() return "CENTER", nil, nil, 1, 2 end
    f.CreateFontString = function() return Frame() end
    f.CreateTexture = function() return Frame() end
    setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    return f
end
local buttons = {}
CreateFrame = function(kind) local f = Frame(); if kind == "Button" then buttons[#buttons + 1] = f end return f end
UIParent = Frame()

local world = { id = 0, kind = "none" }
GetInstanceInfo = function() return "somewhere", world.kind, 0, "", 0, 0, false, world.id end
local ticker
C_Timer = { NewTicker = function(_, fn) ticker = { fn = fn, Cancel = function(self) self.cancelled = true end }; return ticker end }
local points = {}
C_Map = { GetBestMapForUnit = function() return 1 end }
C_AreaPoiInfo = {
    GetAreaPOIForMap = function() local ids = {}; for i = 1, #points do ids[i] = i end; return ids end,
    GetAreaPOIInfo = function(_, i) return { name = points[i][1], textureIndex = points[i][2] } end,
}
local score = { 0, 0, 2000 }
local clockText
C_UIWidgetManager = {
    GetDoubleStatusBarWidgetVisualizationInfo = function() return { leftBarValue = score[1], rightBarValue = score[2], leftBarMax = score[3] } end,
    GetIconAndTextWidgetVisualizationInfo = function(id) if id == 6 and clockText then return { text = clockText } end end,
}
local queue = {}
GetMaxBattlefieldID = function() return 2 end
GetBattlefieldStatus = function(i) if i == 1 and queue.status then return queue.status, "Warsong Gulch" end return "none" end
GetBattlefieldEstimatedWaitTime = function() return queue.estimate or 0 end
GetBattlefieldTimeWaited = function() return queue.waited or 0 end
GetBattlefieldPortExpiration = function() return queue.expires or 0 end
local sent = {}
SendChatMessage = function(text, channel) sent[#sent + 1] = channel .. ": " .. text end
local capping = false
C_AddOns = { IsAddOnLoaded = function(name) return capping and name == "Capping" end }

local db, said = {}, {}
local addon = { GetDB = function() return db end, Print = function(s) said[#said + 1] = s end }
local ns = { L = function(s) return s end, addon = addon }
assert(loadfile("ForeverLazy/Battleground.lua"))("ForeverLazy", ns)
local B = addon.BG

local passed, failed = 0, 0
local function test(label, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. label) else failed = failed + 1; print("FAIL  " .. label .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "differs") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end
local function Event(...) B.OnEvent(nil, ...) end
local function Enter(id, kind) world.id, world.kind = id, kind or "pvp"; Event("PLAYER_ENTERING_WORLD") end
local ALL = { "bgQueue", "bgNodes", "bgFlag", "bgTime", "bgScore", "bgCall", "bgAV" }
local function AllOn() for _, k in ipairs(ALL) do db[k] = true end end
local function AllOff() for _, k in ipairs(ALL) do db[k] = nil end; B.Update() end

test("the clock reads minutes and seconds", function() eq(B.Clock(0), "0:00"); eq(B.Clock(65.4), "1:05"); eq(B.Clock(-3), "0:00") end)

test("with everything off, nothing shows", function()
    queue = { status = "confirm", expires = 40 }
    Enter(529)
    points = { { "Farm", 31 } }; Event("AREA_POIS_UPDATED")
    points = { { "Farm", 32 } }; Event("AREA_POIS_UPDATED")
    Event("START_TIMER", 1, 90, 120)
    Event("CHAT_MSG_BG_SYSTEM_HORDE", "Ann captured the flag!")
    eq(#B.Sorted(now), 0)
    queue = {}; Enter(0, "none")
end)

test("queue: expected wait, then accept, then gone", function()
    AllOn()
    queue = { status = "queued", estimate = 120000, waited = 20000 }
    Event("UPDATE_BATTLEFIELD_STATUS")
    local bar = B.Bar("queue1"); eq(bar.kind, "queue"); eq(bar.ends, now + 100); eq(bar.total, 120)
    queue = { status = "confirm", expires = 40 }; Event("UPDATE_BATTLEFIELD_STATUS")
    eq(B.Bar("queue1").kind, "accept"); eq(B.Bar("queue1").ends, now + 40)
    queue = {}; Event("UPDATE_BATTLEFIELD_STATUS")
    eq(B.Bar("queue1"), nil)
end)

test("queue: past the expected wait it counts up and stays", function()
    queue = { status = "queued", estimate = 60000, waited = 90000 }; Event("UPDATE_BATTLEFIELD_STATUS")
    eq(B.Bar("queue1").countFrom, now - 90)
    now = now + 500; B.Sorted(now)
    assert(B.Bar("queue1"), "a counting bar must not run out")
    queue = {}; Event("UPDATE_BATTLEFIELD_STATUS")
end)

test("the start countdown shows in a battleground only", function()
    Enter(0, "none"); Event("START_TIMER", 1, 60, 60); eq(B.Bar("start"), nil)
    Enter(529); Event("START_TIMER", 1, 60, 60); eq(B.Bar("start").ends, now + 60)
end)

test("a base: no timer for what was already being taken, one when it starts, gone when it ends", function()
    Enter(0, "none"); Enter(529)
    points = { { "Farm", 32 }, { "Mine", 16 } }; Event("AREA_POIS_UPDATED")
    eq(B.Bar("node:Farm"), nil)
    points = { { "Farm", 32 }, { "Mine", 19 } }; Event("AREA_POIS_UPDATED")
    local bar = B.Bar("node:Mine"); eq(bar.ends, now + 60); eq(bar.color, "horde"); eq(bar.label, "Mine (Horde)")
    now = now + 10; Event("AREA_POIS_UPDATED"); eq(B.Bar("node:Mine").ends, now + 50, "an unchanged map does not restart it")
    points = { { "Farm", 32 }, { "Mine", 17 } }; Event("AREA_POIS_UPDATED")
    eq(B.Bar("node:Mine").color, "alliance"); eq(B.Bar("node:Mine").ends, now + 60, "retaken: a new timer")
    points = { { "Farm", 32 }, { "Mine", 18 } }; Event("AREA_POIS_UPDATED")
    eq(B.Bar("node:Mine"), nil)
end)

test("an empty map is not taken as the first look", function()
    local state = {}
    B.ScanNodes(state, {}); eq(state.seen, nil)
    eq(#(B.ScanNodes(state, { { name = "Farm", icon = 32 } })), 0)
end)

test("Alterac Valley takes five minutes, and the ticker reads the map too", function()
    Enter(0, "none"); Enter(30)
    points = { { "Tower Point", 10 } }; ticker.fn()
    points = { { "Tower Point", 9 } }; ticker.fn()
    eq(B.Bar("node:Tower Point").ends, now + 300)
end)

test("leaving takes the battleground's bars with it", function()
    local t = ticker
    Enter(0, "none")
    eq(B.Bar("node:Tower Point"), nil); eq(t.cancelled, true); eq(B.Zone(), nil)
end)

test("an instance that is not a battleground is ignored", function()
    Enter(529, "party"); eq(B.Zone(), nil); Enter(0, "none")
end)

test("the flag: 12 seconds in Warsong Gulch, 23 on Darkspear Islands", function()
    Enter(489); Event("CHAT_MSG_BG_SYSTEM_ALLIANCE", "Ann captured the Horde flag!")
    eq(B.Bar("flag").ends, now + 12)
    Enter(0, "none"); Enter(2997); Event("CHAT_MSG_BG_SYSTEM_HORDE", "Bob captured the flag!")
    eq(B.Bar("flag").ends, now + 23)
    Enter(0, "none")
end)

test("a message about taking a base is not the flag", function()
    assert(not B.IsFlagCapture("Bob captured the Ruins!", { Ruins = 1 }))
    assert(B.IsFlagCapture("Bob captured the flag at the Ruins!", { Ruins = 1 }))
    assert(not B.IsFlagCapture("Bob picked up the flag!"))
end)

test("Warsong time left, only when the game says it", function()
    Enter(489); clockText = nil
    for _ = 1, 5 do ticker.fn() end
    eq(B.Bar("clock"), nil)
    clockText = "Time Remaining 12:30"
    for _ = 1, 5 do ticker.fn() end
    eq(B.Bar("clock").ends, now + 750)
    clockText = nil; Enter(0, "none")
end)

test("score guess: needs a few steps, then says who wins and when", function()
    local race = B.NewRace()
    local t = 0
    B.Sample(race, t, 0, 0, 2000)
    eq(B.Predict(race, t), nil)
    for i = 1, 4 do t = i * 10; B.Sample(race, t, i * 100, i * 50, 2000) end
    local winner, left, top, other = B.Predict(race, t)
    eq(winner, "alliance"); eq(left, 160); eq(top, 2000); eq(other, 1000)
end)

test("score guess: one flag bonus does not change the speed", function()
    local race = B.NewRace()
    local a = 0
    B.Sample(race, 0, 0, 0, 2000)
    for i, gain in ipairs({ 100, 100, 100, 400, 100 }) do a = a + gain; B.Sample(race, i * 10, a, i * 10, 2000) end
    local winner, left = B.Predict(race, 50)
    eq(winner, "alliance"); eq(left, (2000 - a) / 10)
end)

test("score guess: a side that stopped scoring counts as standing still", function()
    local race = B.NewRace()
    B.Sample(race, 0, 0, 300, 2000)
    for i = 1, 6 do B.Sample(race, i * 10, i * 100, 300, 2000) end
    local winner, _, _, other = B.Predict(race, 60)
    eq(winner, "alliance"); eq(other, 300)
end)

test("score guess: after a base changes it measures again", function()
    local race = B.NewRace()
    B.Sample(race, 0, 0, 0, 2000)
    for i = 1, 4 do B.Sample(race, i * 10, i * 100, i * 50, 2000) end
    B.Forget(race)
    eq(B.Predict(race, 40), nil)
    B.Sample(race, 50, 430, 220, 2000)
    eq(B.Predict(race, 50), nil, "the first step after a change only starts the clock")
end)

test("the score guess shows as one bar, from the game's score widget", function()
    Enter(2997)
    for i = 0, 5 do
        score = { i * 100, i * 50, 2000 }
        Event("UPDATE_UI_WIDGET", { widgetID = 7467 })
        now = now + 10
    end
    local bar = B.Bar("score"); assert(bar, "no bar"); eq(bar.color, "alliance"); assert(bar.label:find("Alliance 2000", 1, true), bar.label)
    local count = 0
    for _, i in ipairs(B.Sorted(now)) do if i.e.kind == "score" then count = count + 1 end end
    eq(count, 1)
    db.bgScore = nil; B.Update(); eq(B.Bar("score"), nil); db.bgScore = true
    Enter(0, "none")
end)

test("shift-click says a bar in battleground chat, and only then", function()
    Enter(529)
    B.StartBar("node:Farm", "Farm (Horde)", 42, "horde", { kind = "node" })
    eq(B.CallText("node:Farm"), "Farm (Horde): 0:42")
    B.StartBar("queue9", "waiting", 42, "queue", { kind = "queue" })
    eq(B.CallText("queue9"), nil)
    sent = {}
    B.Paint()
    eq(#sent, 0)
    local row
    for _, f in ipairs(buttons) do if f.key == "node:Farm" and f.shown then row = f end end
    assert(row, "no row for the base")
    row.scripts.OnClick(row); eq(#sent, 0, "a plain click says nothing")
    shift = true; row.scripts.OnClick(row); shift = false
    eq(sent[1], "INSTANCE_CHAT: Farm (Horde): 0:42")
    Enter(0, "none"); B.StopBar("queue9")
end)

test("with Capping loaded, ours stays out of the way", function()
    capping = true
    Enter(529); points = { { "Farm", 31 } }; ticker.fn(); points = { { "Farm", 32 } }; ticker.fn()
    eq(B.Bar("node:Farm"), nil)
    said = {}; addon:HandleExtraCommand("pvp", "status")
    assert(table.concat(said, " "):find("Capping", 1, true))
    capping = false; Enter(0, "none")
end)

test("Alterac Valley: supplies, then an upgrade, then the bigger hand-in I can afford", function()
    local bag = { [17423] = 6 }
    local function count(item) return bag[item] or 0 end
    local what, id = B.AVPick({ 30904 }, { 6881 }, { { id = 6985, complete = true } }, count)
    eq(what, "active"); eq(id, 6985)
    what, id = B.AVPick({ 30904 }, { 6881 }, {}, count); eq(what, "option"); eq(id, 30904)
    what, id = B.AVPick({}, { 6881, 7386 }, {}, count); eq(what, "available"); eq(id, 7386)
    bag[17423] = 3; what, id = B.AVPick({}, { 7386, 6881 }, {}, count); eq(id, 6881)
    bag[17423] = 0; eq(B.AVPick({}, { 7386, 6881 }, {}, count), nil)
end)

test("Alterac Valley: nothing unknown is ever picked", function()
    eq(B.AVPick({ 96890, 30406, 12345 }, { 999 }, { { id = 999, complete = true } }, function() return 99 end), nil)
end)

test("Alterac Valley: only its own quests are completed, with no reward choice, and shift stops it", function()
    local quest, choices, done = 999, 0, {}
    GetQuestID = function() return quest end
    IsQuestCompletable = function() return true end
    CompleteQuest = function() done[#done + 1] = "complete" end
    GetNumQuestChoices = function() return choices end
    GetQuestReward = function() done[#done + 1] = "reward" end
    Enter(30)
    Event("QUEST_PROGRESS"); Event("QUEST_COMPLETE"); eq(#done, 0)
    quest = 6781
    shift = true; Event("QUEST_PROGRESS"); eq(#done, 0); shift = false
    Event("QUEST_PROGRESS"); Event("QUEST_COMPLETE"); eq(table.concat(done, " "), "complete reward")
    done = {}; choices = 2; Event("QUEST_COMPLETE"); eq(#done, 0)
    Enter(0, "none"); choices = 0; Event("QUEST_PROGRESS"); eq(#done, 0, "not outside Alterac Valley")
end)

test("hidden values are left alone", function()
    local SECRET = {}
    issecretvalue = function(v) return v == SECRET end
    Enter(489)
    Event("CHAT_MSG_BG_SYSTEM_HORDE", SECRET); eq(B.Bar("flag"), nil)
    points = { { SECRET, 32 }, { "Farm", SECRET } }; ticker.fn(); ticker.fn()
    score = { SECRET, SECRET, SECRET }; Event("UPDATE_UI_WIDGET", { widgetID = 7467 })
    assert(#B.CheckLines() > 0)
    Enter(0, "none"); issecretvalue = nil
end)

test("/lazy pvp: status, check, sample timers; other commands pass on", function()
    AllOff(); said = {}
    eq(addon:HandleExtraCommand("pvp", ""), true)
    assert(table.concat(said, " "):find("are off", 1, true), said[1])
    eq(addon:HandleExtraCommand("pvp", "check"), true)
    eq(addon:HandleExtraCommand("pvp", "test"), true)
    assert(B.Bar("test1"))
    eq(addon:HandleExtraCommand("bg", ""), nil)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
