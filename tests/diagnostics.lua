-- Offline tests for the bug report, the game functions list and the commands list (no game needed).
--   lua tests/diagnostics.lua
local root = (arg and arg[0] or "tests/diagnostics.lua"):gsub("[/\\]tests[/\\]diagnostics%.lua$", ""):gsub("^tests[/\\]diagnostics%.lua$", ".")

local db = { modules = { pet = false }, waypoints = { { name = "1. Turn in: X", label = "Turn in: X", x = 10, y = 20 } } }
local shown
local addon
addon = { Print = function() end, GetDB = function() return db end, ReportWindow = function(title, lines) shown = { title = title, text = table.concat(lines, "\n") } end,
    ArrowTarget = function() addon.arrowWhy = "a hand-in close by"; return { name = "Turn in: X", x = 10, y = 20 } end,
    GearSpec = function() return { name = "Retribution", kind = "melee" } end }
local ns = { addon = addon }

local scripts = {}
local frameMT = { __index = function() return function() end end }
function CreateFrame()
    local f = setmetatable({}, frameMT)
    f.SetScript = function(_, name, fn) scripts[#scripts + 1] = { name = name, fn = fn } end
    return f
end
function UnitClass() return "Paladin", "PALADIN" end
function UnitLevel() return 31 end
function GetBuildInfo() return "1.15.0", "12345" end
function GetLocale() return "enUS" end
function geterrorhandler() return function() end end
local handler
function seterrorhandler(h) handler = h end
function time() return 1000 end
C_Map = { GetBestMapForUnit = function() return 1437 end }

assert(loadfile(root .. "/ForeverLazy/Diagnostics.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function has(text, part) if not text:find(part, 1, true) then error("missing: " .. part .. "\n" .. text, 2) end end

test("the bug report names the version, the plan, the arrow and what is switched off", function()
    addon:HandleExtraCommand("report", "")
    has(shown.title, "bug report")
    has(shown.text, "Forever Lazy")
    has(shown.text, "pet")                       -- the module that is off
    has(shown.text, "Turn in: X")                -- the plan
    has(shown.text, "a hand-in close by")        -- why the arrow points there
    has(shown.text, "Retribution")
end)

test("errors from this addon are remembered and shown, others are not, and the old handler still runs", function()
    local passedOn = {}
    local old = geterrorhandler
    function geterrorhandler() return function(m) passedOn[#passedOn + 1] = m end end
    -- the login event installs the hook
    for _, s in ipairs(scripts) do if s.name == "OnEvent" then s.fn(nil, "PLAYER_LOGIN") end end
    assert(handler, "an error handler should have been installed")
    handler("Interface\\AddOns\\ForeverLazy\\Gear.lua:12: boom")
    handler("Interface\\AddOns\\SomethingElse\\x.lua:3: not ours")
    handler("Interface\\AddOns\\ForeverLazy\\Gear.lua:12: boom")      -- the same error again is counted, not listed twice
    addon:HandleExtraCommand("report", "")
    has(shown.text, "boom"); has(shown.text, "x2")
    assert(not shown.text:find("not ours", 1, true), "an error from another addon must not be in the report")
    assert(#passedOn == 3, "the game's own handler must still get every error")
    geterrorhandler = old
end)
test("the commands list has every group and no empty entry", function()
    addon:HandleExtraCommand("commands", "")
    has(shown.text, "Everyday"); has(shown.text, "Gear"); has(shown.text, "/lazy report")
    for _, group in ipairs(addon.CommandList) do
        assert(#group[2] > 0, group[1] .. " is empty")
        for _, c in ipairs(group[2]) do assert(c[1]:find("^/lazy") and #c[2] > 3, "bad entry " .. tostring(c[1])) end
    end
end)

test("the game functions list says what is missing", function()
    addon:HandleExtraCommand("apis", "")
    has(shown.text, "MISSING")        -- the stand-ins have almost none of the game's functions
    has(shown.text, "GetItemStats")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
