-- Translations. Every text the player reads goes through ns.L: it looks the English text up in the table of the game's language
-- and gives it back unchanged when there is no translation. Nothing breaks when a text is missing; it simply stays English.
--
--   local L = ns.L
--   Print(L("planned a route"))                       -- a plain text
--   Print(string.format(L("%d stops left"), n))       -- a text with numbers or names in it: translate the whole line, keep the %d / %s
--
-- A translation file (Locales\xxXX.lua) is one table: ns.locales["deDE"] = { ["English text"] = "German text", ... }
-- See docs/LOCALIZATION.md. /lazy l10n says what is translated and /lazy l10n missing lists what still is not.
-- This file loads first and needs nothing else.
local ADDON, ns = ...

ns.locales = ns.locales or {}
ns.localeOverride = nil          -- set from the options (db.language) to force a language

local missing, missingCount = {}, 0
local MAX_MISSING = 3000

-- the language in use: the one set by hand, else the game's own
local function Current()
    local loc = ns.localeOverride
    if not loc or loc == "" or loc == "auto" then loc = (GetLocale and GetLocale()) or "enUS" end
    if loc == "enGB" then loc = "enUS" end
    return loc
end
ns.CurrentLocale = Current

local function L(text)
    if type(text) ~= "string" then return text end
    local loc = Current()
    if loc == "enUS" then return text end
    local t = ns.locales[loc]
    local hit = t and t[text]
    if hit and hit ~= "" then return hit end
    if not missing[text] and missingCount < MAX_MISSING then missing[text] = true; missingCount = missingCount + 1 end
    return text
end
ns.L = L

-- for the translator: how much of the texts seen so far has a translation
function ns.LocaleStats()
    local loc = Current()
    local t = ns.locales[loc]
    local have = 0
    if t then for _, v in pairs(t) do if v and v ~= "" then have = have + 1 end end end
    return loc, have, missingCount
end

-- the texts that were asked for but not found, sorted, ready to paste into a translation file
function ns.LocaleMissing()
    local list = {}
    for text in pairs(missing) do list[#list + 1] = text end
    table.sort(list)
    return list
end

-- a text with its English wording turned into the language of the player when it begins with one of the stop labels
-- ("Turn in: X", "Pick up: X", "Class quest: X"). The English wording stays what the code works with; this is only for showing it.
local PREFIXES = { "Turn in: ", "Pick up: ", "Class quest: " }
function ns.LocalizeLabel(label)
    if type(label) ~= "string" or Current() == "enUS" then return label end
    -- the number the plan puts in front ("3. Turn in: X")
    local num, rest = label:match("^(%d+%. )(.*)$")
    rest = rest or label
    for _, p in ipairs(PREFIXES) do
        if rest:sub(1, #p) == p then
            return (num or "") .. L(p) .. rest:sub(#p + 1)
        end
    end
    return label
end

-- reached the end of the file without an error (used by /lazy check)
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Locale.lua"] = true
