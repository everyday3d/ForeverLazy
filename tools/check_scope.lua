-- tools/check_scope.lua: finds a name that a file declares as a local further down but reads as a global above it
-- (the mistake behind "attempt to call a nil value"). usage: lua tools/check_scope.lua <lua file> [...]
local bad = 0
for _, path in ipairs(arg) do
    local f = assert(io.open(path, "rb")); local src = f:read("*a"); f:close()
    local declared = {}
    for name in src:gmatch("local%s+function%s+([%w_]+)") do declared[name] = true end
    for names in src:gmatch("\nlocal%s+([%w_,%s]-)%s*=") do for name in names:gmatch("[%w_]+") do declared[name] = true end end
    for names in src:gmatch("\nlocal%s+([%w_,%s]-)\n") do for name in names:gmatch("[%w_]+") do declared[name] = true end end
    local p = io.popen('luac -l -l -p "' .. path .. '" 2>&1')
    local out = p:read("*a"); p:close()
    local seen = {}
    for line, name in out:gmatch("%[(%d+)%][^\n]-GETTABUP[^\n]-_ENV \"([%w_]+)\"") do
        if declared[name] and not seen[name] then seen[name] = true; bad = bad + 1; print(string.format("%s: '%s' is read as a global at line %s but the file declares it as a local", path:match("[^/\\]+$"), name, line)) end
    end
end
print(bad == 0 and "no scope mistakes found" or (bad .. " possible scope mistake(s)"))
os.exit(bad == 0 and 0 or 1)
