-- Offline test for the live meter bars in a fight (no game needed).
--   lua tests/meterlive.lua
local root = (arg and arg[0] or "tests/meterlive.lua"):gsub("[/\\]tests[/\\]meterlive%.lua$", ""):gsub("^tests[/\\]meterlive%.lua$", ".")

local db = { meterOn = true, meterLive = true, meterRows = 8 }
local said = {}
local addon = { Print = function(m) said[#said + 1] = m end, GetDB = function() return db end, RefreshOptions = function() end }
local ns = { addon = addon, L = function(x) return x end }

-- a frame that remembers what it was told
local frames, evFrames = {}, {}
local function NewFrame(name, parent)
    local f = { name = name, parent = parent, events = {}, scripts = {}, shown = false, texts = {}, values = {} }
    setmetatable(f, { __index = function(t, k)
        if k == "GetHeight" then return function() return 120 end end
        return function() end
    end })
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.SetScript = function(self, n, fn) self.scripts[n] = fn end
    f.HookScript = function() end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    f.SetText = function(self, t) self.text = t end
    f.SetValue = function(self, v) if type(v) == "table" then error("secret") end; self.value = v end
    f.CreateFontString = function(self) return NewFrame("fs", self) end
    f.CreateTexture = function(self) return NewFrame("tex", self) end
    f.AddMessage = function() end
    f.Clear = function() end
    frames[#frames + 1] = f
    return f
end
function CreateFrame(kind, name, parent) return NewFrame(name or kind, parent) end

local chat = NewFrame("ChatFrame1")
_G.ChatFrame1 = chat
_G.NUM_CHAT_WINDOWS = 1
function GetChatWindowInfo(i) return i == 1 and "Meter" or nil end
function GetTime() return 100 end
function InCombatLockdown() return false end
function GetInstanceInfo() return "Eastvale", "none" end
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" } }
Enum = { DamageMeterType = { Dps = 1 }, DamageMeterSessionType = { Current = 1, Overall = 0 } }
local sources = {
    { name = "Tank", totalAmount = 5000, classFilename = "WARRIOR" },
    { name = "Healer", totalAmount = 3000, classFilename = "PRIEST" },
}
C_DamageMeter = { GetCombatSessionFromType = function() return { combatSources = sources, maxAmount = 5000 } end }
function AbbreviateNumbers(n) return tostring(n) end
function issecretvalue(v) return false end

assert(loadfile(root .. "/ForeverLazy/Meter.lua"))("ForeverLazy", ns)

-- the frame that listens for fights
local listener
for _, f in ipairs(frames) do if f.events.PLAYER_REGEN_DISABLED then listener = f end end
assert(listener, "the meter listens for fights")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function liveFrame()
    for _, f in ipairs(frames) do if f.name == "ForeverLazy_MeterLive" then return f end end
end
local function bars(f)
    local out = {}
    for _, c in ipairs(frames) do if c.parent == f and c.name == "StatusBar" then out[#out + 1] = c end end
    return out
end

addon:HandleExtraCommand("meter", "on")

test("a fight starts: the bars appear over the Meter tab", function()
    listener.scripts.OnEvent(listener, "PLAYER_REGEN_DISABLED")
    local f = liveFrame()
    assert(f and f.shown, "the live window is shown")
    assert(f.parent == chat, "it sits on the Meter tab")
end)

test("the fight ends: the bars go away", function()
    listener.scripts.OnEvent(listener, "PLAYER_REGEN_ENABLED")
    assert(not liveFrame().shown)
end)

test("off by default and when switched off: nothing is drawn", function()
    db.meterLive = nil
    listener.scripts.OnEvent(listener, "PLAYER_REGEN_DISABLED")
    assert(not liveFrame().shown)
    listener.scripts.OnEvent(listener, "PLAYER_REGEN_ENABLED")
    db.meterLive = true
end)

test("a number the bar cannot take: the window steps aside instead of showing junk", function()
    sources[1].totalAmount = {}               -- stands in for a value the client would refuse
    sources[2].totalAmount = {}
    listener.scripts.OnEvent(listener, "PLAYER_REGEN_DISABLED")
    assert(not liveFrame().shown, "hidden so the tab shows its last picture")
    listener.scripts.OnEvent(listener, "PLAYER_REGEN_ENABLED")
    sources[1].totalAmount = 5000; sources[2].totalAmount = 3000
end)

test("the live commands", function()
    addon:HandleExtraCommand("meter", "live off"); assert(db.meterLive == nil)
    addon:HandleExtraCommand("meter", "live on"); assert(db.meterLive == true)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
