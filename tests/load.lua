-- Loads every file of the addon in the order of its .toc, with stand-ins for the game, and reports any file that stops with a Lua
-- error while loading. It cannot say the addon WORKS, only that nothing breaks at load time (a moved local, a missing file, a typo).
--   lua tests/load.lua [folder with ForeverLazy.toc]
local dir = (arg and arg[1]) or "ForeverLazy"
dir = dir:gsub("\\", "/"):gsub("/$", "")

-- the game's functions: anything not defined answers like a harmless object (callable, indexable, never nil)
local standIn
standIn = setmetatable({}, {
    __index = function() return standIn end,
    __call = function() return standIn end,
    __newindex = function() end,
    __concat = function(a, b) return "" end,
    __len = function() return 0 end,
    __lt = function() return false end, __le = function() return false end,
    __unm = function() return 0 end,
    __add = function() return 0 end, __sub = function() return 0 end, __mul = function() return 0 end, __div = function() return 0 end,
    __mod = function() return 0 end, __pow = function() return 0 end,
})
setmetatable(_G, { __index = function(_, k) if type(k) == "string" and k:match("^[%a_]") then return standIn end end })
-- the libraries: only AceComm and AceSerializer put methods on the addon
LibStub = function(name)
    if tostring(name):find("AceComm") then
        return { Embed = function(_, t) t.RegisterComm = function() end; t.SendCommMessage = function() end; t.UnregisterComm = function() end end }
    elseif tostring(name):find("AceSerializer") then
        return { Embed = function(_, t) t.Serialize = function() return "" end; t.Deserialize = function() return false end end }
    end
    return standIn
end
strsplit = function(sep, s) return s end
tinsert, tremove, wipe, unpack = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end, table.unpack
format, strfind, strmatch, gsub, strsub, strlower, strupper, strlen = string.format, string.find, string.match, string.gsub, string.sub, string.lower, string.upper, string.len
floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt
bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end, bxor = function(a, b) return a ~ b end, lshift = function(a, b) return a << b end, rshift = function(a, b) return a >> b end }
GetTime = function() return 0 end
-- a few answers that must be real numbers or text, not stand-ins
UnitLevel = function() return 30 end
UnitClass = function() return "Paladin", "PALADIN" end
GetNumTalentTabs = function() return 3 end
GetTalentTabInfo = function(i) return "tab" .. i, "icon", i == 3 and 31 or 0 end
GetBuildInfo = function() return "1.15.0", "12345" end
GetLocale = function() return "enUS" end
InCombatLockdown = function() return false end
IsInInstance = function() return false, "none" end
C_AddOns = { GetNumAddOns = function() return 0 end, GetAddOnInfo = function() return nil end, IsAddOnLoaded = function() return false end, GetAddOnMetadata = function() return "test" end }
-- a frame answers every call, and lines of a tooltip count as none
CreateFrame = function() return setmetatable({ NumLines = function() return 0 end }, { __index = function() return standIn end }) end
time, date = os.time, os.date
UISpecialFrames = {}
SlashCmdList = {}
ForeverLazyDB = nil

-- the .toc: files in order
local files = {}
for line in io.lines(dir .. "/ForeverLazy.toc") do
    line = line:gsub("\r$", "")
    if line ~= "" and not line:find("^#") and line:find("%.lua$") then files[#files + 1] = line:gsub("\\", "/") end
end

local ns = {}
local errors = {}
local loaded = {}
for _, f in ipairs(files) do
    local chunk, err = loadfile(dir .. "/" .. f)
    if not chunk then
        errors[#errors + 1] = f .. ": SYNTAX " .. tostring(err)
    else
        local ok, e = pcall(chunk, "ForeverLazy", ns)
        if ok then loaded[#loaded + 1] = f else errors[#errors + 1] = f .. ": " .. tostring(e) end
    end
end

print(string.format("%d files in the .toc, %d loaded without an error, %d with one", #files, #loaded, #errors))
for _, e in ipairs(errors) do print("  " .. e) end

-- every file that sets a "loaded" marker should have reached its end
local marks = (ns.addon and ns.addon.loaded) or {}
local missing = {}
for _, f in ipairs(files) do
    local leaf = f:match("([^/]+)$")
    local text = io.open(dir .. "/" .. f, "rb"):read("*a")
    if text:find('loaded["' .. leaf .. '"]', 1, true) and not marks[leaf] then missing[#missing + 1] = leaf end
end
print(#missing .. " file(s) did not reach their own end marker" .. (#missing > 0 and (": " .. table.concat(missing, ", ")) or ""))
local fail = not (#errors == 0 and #missing == 0)

-- Build the windows once with a plain settings table, so a mistake inside a window builder (not only at load) shows up too.
local addon = ns.addon
if addon then
    local db = { pos = {}, waypoints = {}, modules = {}, scale = 1, alpha = 1, arrival = 10, routes = {}, optOpen = nil }
    addon.GetDB = function() return db end
    addon.GetRoot = function() return { chars = {}, profiles = {}, global = db } end
    local tries = {
        { "options window", function() return addon.OpenOptions and addon:OpenOptions() end },
        { "tour", function() return addon.StartTour and addon.StartTour() end },
        { "what's new", function() return addon.ShowWhatsNew and addon.ShowWhatsNew() end },
        { "commands list", function() return addon.CommandsReport and addon.CommandsReport() end },
        { "bug report", function() return addon.BugReport and addon.BugReport() end },
        { "game functions", function() return addon.ApisReport and addon.ApisReport() end },
        { "language report", function() return addon.LanguageReport and addon.LanguageReport() end },
    }
    local bad = {}
    for _, tr in ipairs(tries) do
        local ok, e = pcall(tr[2])
        if not ok then bad[#bad + 1] = tr[1] .. ": " .. tostring(e) end
    end
    print(#tries .. " windows built, " .. #bad .. " with an error")
    for _, e in ipairs(bad) do print("  " .. e) end
    if #bad > 0 or fail then os.exit(1) end
end
os.exit(fail and 1 or 0)
