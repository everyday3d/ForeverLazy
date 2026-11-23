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
os.exit((#errors == 0 and #missing == 0) and 0 or 1)
