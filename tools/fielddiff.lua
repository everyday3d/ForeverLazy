-- per field: how many records differ between two dumps (nil and 0 counted separately and together)
local OLD, NEW, KIND = arg[1], arg[2], arg[3] or "quests"
ForeverLazyDB = nil; dofile(OLD); local old = ForeverLazyDB.exportDump
ForeverLazyDB = nil; dofile(NEW); local new = ForeverLazyDB.exportDump
local fields = old.fields[KIND]
local function ser(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local p = {}
    for _, k in ipairs(keys) do p[#p + 1] = tostring(k) .. "=" .. ser(v[k]) end
    return "{" .. table.concat(p, ",") .. "}"
end
local strict, loose = {}, {}
local ex = {}
for id, text in pairs(old[KIND]) do
    local nt = new[KIND][id]
    if nt then
        local a, b = load("return " .. text)(), load("return " .. nt)()
        for i = 1, #fields do
            local x, y = a[i], b[i]
            local sx, sy = ser(x), ser(y)
            if sx ~= sy then
                strict[i] = (strict[i] or 0) + 1
                local nx, ny = (x == nil or x == 0) and "0" or sx, (y == nil or y == 0) and "0" or sy
                if nx ~= ny then
                    loose[i] = (loose[i] or 0) + 1
                    ex[i] = ex[i] or {}
                    if #ex[i] < 3 then ex[i][#ex[i] + 1] = id .. ": " .. sx:sub(1, 60) .. "  ->  " .. sy:sub(1, 60) end
                end
            end
        end
    end
end
for i = 1, #fields do
    print(string.format("%-22s differs %5d   (not counting nil vs 0: %5d)", fields[i], strict[i] or 0, loose[i] or 0))
    for _, e in ipairs(ex[i] or {}) do print("      " .. e) end
end
