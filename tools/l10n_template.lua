-- Makes the list of every text that can be translated: one line per text, ready to fill in.
--   lua tools/l10n_template.lua [ForeverLazy folder] [out file]
-- The texts are the ones written as L("...") in the code. Copy the result to ForeverLazy/Locales/<code>.lua (for example deDE.lua),
-- wrap it as shown in docs/LOCALIZATION.md, and fill in the right-hand side. A text left as "" stays English.
local dir = (arg and arg[1]) or "ForeverLazy"
local out = (arg and arg[2]) or "docs/locale-template.lua"
dir = dir:gsub("\\", "/"):gsub("/$", "")

local function litEnd(s, i)
    local q = s:sub(i, i)
    local j = i + 1
    while j <= #s do
        local c = s:sub(j, j)
        if c == "\\" then j = j + 2 elseif c == q then return j else j = j + 1 end
    end
end

-- Lua escapes in the source -> the real text
local function unescape(lit)
    local f = load("return " .. lit)
    return f and f() or nil
end

local keys, order, where = {}, {}, {}
local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '\\*.lua"')
local names = {}
for line in p:lines() do names[#names + 1] = line end
p:close()
table.sort(names)
for _, name in ipairs(names) do
    local f = io.open(dir .. "/" .. name, "rb")
    local s = f:read("*a"); f:close()
    local from = 1
    while true do
        local a, b = s:find("L(", from, true)
        if not a then break end
        local prev = a > 1 and s:sub(a - 1, a - 1) or ""
        if not prev:match("[%w_%.:]") then
            local i = b + 1
            while s:sub(i, i):match("[ \t\n]") do i = i + 1 end
            if s:sub(i, i) == '"' then
                local e = litEnd(s, i)
                if e then
                    local text = unescape(s:sub(i, e))
                    if text and not keys[text] then keys[text] = true; order[#order + 1] = text; where[text] = name end
                end
            end
        end
        from = b + 1
    end
end

local o = assert(io.open(out, "wb"))
o:write("-- Every text of Forever Lazy that can be translated (", #order, " of them). Fill in the right-hand side, leave \"\" for English.\n")
o:write("-- Keep every %d, %s and |c...|r code exactly as it is in the English text, and keep the line breaks (\\n).\n")
o:write("-- Save the file as ForeverLazy/Locales/<code>.lua (deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW).\n")
o:write("local ADDON, ns = ...\nns.locales = ns.locales or {}\nns.locales[\"xxXX\"] = {\n")
table.sort(order, function(x, y) if where[x] ~= where[y] then return where[x] < where[y] end return x < y end)
local lastFile
for _, text in ipairs(order) do
    if where[text] ~= lastFile then o:write("\n    -- ", where[text], "\n"); lastFile = where[text] end
    o:write((string.format("    [%q] = \"\",\n", text):gsub("\\\n", "\\n")))
end
o:write("}\n")
o:close()
print(#order .. " texts written to " .. out)
