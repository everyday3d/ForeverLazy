-- Offline tests for the translation lookup (no game needed).
--   lua tests/l10n.lua
local root = (arg and arg[0] or "tests/l10n.lua"):gsub("[/\\]tests[/\\]l10n%.lua$", ""):gsub("^tests[/\\]l10n%.lua$", ".")

local gameLocale = "enUS"
function GetLocale() return gameLocale end
local ns = {}
assert(loadfile(root .. "/ForeverLazy/Locale.lua"))("ForeverLazy", ns)
local L = ns.L

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "values differ") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end

ns.locales["deDE"] = {
    ["Take the tour"] = "Zur Tour",
    ["%d stops left"] = "noch %d Halte",
    ["Turn in: "] = "Abgeben: ",
    ["Pick up: "] = "Annehmen: ",
    ["empty one"] = "",
}

test("English is returned as it is", function()
    gameLocale = "enUS"
    eq(L("Take the tour"), "Take the tour")
    eq(L("something new"), "something new")
end)

test("a translation is used when the game is in that language", function()
    gameLocale = "deDE"
    eq(L("Take the tour"), "Zur Tour")
end)

test("a text with a number keeps working through string.format", function()
    gameLocale = "deDE"
    eq(string.format(L("%d stops left"), 3), "noch 3 Halte")
end)

test("a text without a translation stays English and is remembered", function()
    gameLocale = "deDE"
    eq(L("not translated yet"), "not translated yet")
    local list = ns.LocaleMissing()
    local found = false
    for _, t in ipairs(list) do if t == "not translated yet" then found = true end end
    assert(found, "the missing text should be listed")
end)

test("an empty translation counts as none", function()
    gameLocale = "deDE"
    eq(L("empty one"), "empty one")
end)

test("a language without a table stays English", function()
    gameLocale = "frFR"
    eq(L("Take the tour"), "Take the tour")
end)

test("the language can be set by hand", function()
    gameLocale = "enUS"
    ns.localeOverride = "deDE"
    eq(L("Take the tour"), "Zur Tour")
    ns.localeOverride = nil
    eq(L("Take the tour"), "Take the tour")
end)

test("enGB counts as English", function()
    gameLocale = "enGB"
    eq(ns.CurrentLocale(), "enUS")
end)

test("a stop label is translated for showing, the numbering stays", function()
    gameLocale = "deDE"
    eq(ns.LocalizeLabel("3. Turn in: The Lost Ingots"), "3. Abgeben: The Lost Ingots")
    eq(ns.LocalizeLabel("Pick up: Bride"), "Annehmen: Bride")
    eq(ns.LocalizeLabel("Kill the wolves"), "Kill the wolves")
    gameLocale = "enUS"
    eq(ns.LocalizeLabel("3. Turn in: X"), "3. Turn in: X")
end)

test("a thing that is not text passes through", function()
    gameLocale = "deDE"
    eq(L(nil), nil); eq(L(5), 5)
    eq(ns.LocalizeLabel(nil), nil)
end)

-- every translation file that ships must keep the % codes of the English text, or string.format would break
local function Specs(s)
    local out = {}
    for spec in tostring(s):gmatch("%%[%d%.%-]*[sdfgxqc%%]") do out[#out + 1] = spec end
    table.sort(out)
    return table.concat(out, " ")
end
test("shipped translations keep the % codes of the English text", function()
    local p = io.popen('dir /b "' .. (root .. "/ForeverLazy/Locales"):gsub("/", "\\") .. '\\*.lua" 2>nul')
    local n, bad = 0, {}
    for name in p:lines() do
        local sandbox = { locales = {} }
        local chunk = assert(loadfile(root .. "/ForeverLazy/Locales/" .. name))
        chunk("ForeverLazy", sandbox)
        for code, t in pairs(sandbox.locales) do
            for en, tr in pairs(t) do
                if tr ~= "" then
                    n = n + 1
                    if Specs(en) ~= Specs(tr) then bad[#bad + 1] = name .. ": " .. en end
                end
            end
        end
    end
    p:close()
    assert(#bad == 0, "% codes differ in:\n      " .. table.concat(bad, "\n      "))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
