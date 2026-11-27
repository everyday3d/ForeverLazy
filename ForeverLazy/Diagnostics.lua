-- Help for finding problems and learning the commands:
--   /lazy report     a bug report in a window you can copy: version, client, settings, the plan and arrow, other addons, last errors
--   /lazy apis       which game functions the newer features need, and whether this client has them
--   /lazy commands   every command, in groups
-- Lua errors that mention Forever Lazy are remembered (the last 10) and go into the report. Nothing is sent anywhere.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

--------------------------------------------------------------------------------
-- Remember errors that come from this addon
--------------------------------------------------------------------------------
local errors = {}
local function Record(msg)
    msg = tostring(msg or "")
    if not msg:find("ForeverLazy", 1, true) then return end
    local short = msg:sub(1, 400)
    for _, e in ipairs(errors) do
        if e.msg == short then e.count = e.count + 1; e.t = time(); return end
    end
    table.insert(errors, 1, { msg = short, count = 1, t = time() })
    while #errors > 10 do table.remove(errors) end
    local db = DB()
    if db then
        db.lastErrors = {}
        for i, e in ipairs(errors) do db.lastErrors[i] = { msg = e.msg, count = e.count, t = e.t } end
    end
end

local function HookErrors()
    local db = DB()
    if db and type(db.lastErrors) == "table" then
        for i, e in ipairs(db.lastErrors) do if type(e) == "table" and e.msg then errors[#errors + 1] = e end end
    end
    if not (seterrorhandler and geterrorhandler) then return end
    local old = geterrorhandler()
    seterrorhandler(function(msg, ...)
        pcall(Record, msg)
        if old then return old(msg, ...) end
    end)
end

--------------------------------------------------------------------------------
-- /lazy apis: what this client has
--------------------------------------------------------------------------------
local function Has(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return false end
        v = v[part]
        if v == nil then return false end
    end
    return true
end

local APIS = {
    { "Gear advisor", {
        "GetItemStats", "C_Item.GetItemStats", "GetItemInfo", "IsEquippableItem", "IsUsableItem", "GetInventoryItemLink",
        "C_Container.GetContainerItemInfo", "C_Container.GetContainerNumSlots", "TooltipDataProcessor.AddTooltipPostCall",
        "MerchantFrame_UpdateMerchantInfo", "GetMerchantItemLink", "GetCombatRatingBonus", "CR_HIT_MELEE", "CR_HIT_SPELL",
        "GetTalentTabInfo", "GetNumTalentTabs" } },
    { "Range colours", { "ActionBarButtonEventsFrame", "ActionButton_UpdateRangeIndicator", "IsUsableAction", "IsActionInRange" } },
    { "Quest item sparkles", { "C_CVar.GetCVar", "C_CVar.SetCVar" } },
    { "Damage meter", { "C_DamageMeter", "C_DamageMeter.GetCombatSessionFromType", "Enum.DamageMeterType" } },
    { "Quests and the map", { "C_QuestLog.GetInfo", "C_QuestLog.GetLogIndexForQuestID", "C_Map.GetMapInfo", "C_SuperTrack" } },
    { "Bags", { "C_Container.UseContainerItem", "ContainerFrameCombinedBags", "C_Container.GetContainerNumFreeSlots" } },
}

function addon.ApisReport()
    local lines = { "Which game functions the newer features need (yes = this client has it)", "" }
    local missing = 0
    for _, group in ipairs(APIS) do
        lines[#lines + 1] = group[1] .. ":"
        for _, path in ipairs(group[2]) do
            local ok = Has(path)
            if not ok then missing = missing + 1 end
            lines[#lines + 1] = string.format("   %-8s %s", ok and "yes" or "MISSING", path)
        end
        lines[#lines + 1] = ""
    end
    -- what the gear advisor really gets from a worn item
    local link = GetInventoryItemLink and GetInventoryItemLink("player", 1)
    if link and addon.GearItemStats then
        local stats, source = addon.GearItemStats(link)
        lines[#lines + 1] = "Gear stats for the item in your head slot: " .. (stats and ("read from the " .. tostring(source)) or "NOT READ")
    end
    local sparkle = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("outlineModeShowLootEffectWhenDisabled")
    lines[#lines + 1] = "Loot sparkle setting right now: " .. tostring(sparkle)
    lines[#lines + 1] = ""
    lines[#lines + 1] = missing == 0 and "Everything the newer features need is here." or (missing .. " function(s) missing: a feature that needs one of them will not work, or will use a fallback.")
    addon.ReportWindow(L("Forever Lazy: game functions"), lines)
end

--------------------------------------------------------------------------------
-- /lazy lfg: what the group finder hands to addons (to see what a group finder filter could do)
--------------------------------------------------------------------------------
local function ShortValue(v)
    if issecretvalue and issecretvalue(v) then return "<hidden from addons>" end
    local t = type(v)
    if t == "string" then return '"' .. (v:sub(1, 40)) .. '"' end
    if t == "table" then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        return "table (" .. n .. " entries)"
    end
    if t == "function" then return "function" end
    return tostring(v)
end

local function SortedKeys(t, limit)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    if limit and #keys > limit then
        local n = #keys
        for i = n, limit + 1, -1 do keys[i] = nil end
        keys[#keys + 1] = "... and " .. (n - limit) .. " more"
    end
    return keys
end

function addon.LfgReport()
    local lines = { "What the group finder gives to addons. Open the group finder and run a search first, then run /lazy lfg again.", "" }
    local function Add(s) lines[#lines + 1] = s end
    -- the functions
    for _, name in ipairs({ "C_LFGList", "C_LFGInfo", "C_LFGBrowse", "C_PartyInfo" }) do
        local tbl = _G[name]
        if type(tbl) == "table" then
            local keys = SortedKeys(tbl)
            Add(name .. " has " .. #keys .. " functions:")
            Add("   " .. table.concat(keys, ", "))
        else
            Add(name .. ": not in this client")
        end
        Add("")
    end
    -- the windows
    for _, name in ipairs({ "LFGParentFrame", "LFGBrowseFrame", "LFGListFrame", "GroupFinderFrame", "PVEFrame" }) do
        local f = _G[name]
        if f then
            Add(string.format("%s: exists, %s", name, (f.IsShown and f:IsShown()) and "open now" or "closed"))
            if type(f) == "table" then
                local keys = SortedKeys(f, 70)
                Add("   fields and methods: " .. table.concat(keys, ", "))
            end
        else
            Add(name .. ": not in this client")
        end
    end
    Add("")
    -- global names that look like group finder code
    local found = {}
    for k in pairs(_G) do
        if type(k) == "string" and (k:find("^LFGBrowse") or k:find("^LFGParent") or k:find("^LFGList") or k:find("^GroupFinder") or k:find("^LFGVanilla")) then found[#found + 1] = k end
    end
    table.sort(found)
    Add(#found .. " global names that start with LFGBrowse, LFGParent, LFGList, GroupFinder or LFGVanilla:")
    Add("   " .. table.concat(found, ", "))
    Add("")
    -- what a search gives
    local api = _G.C_LFGList
    if api and api.GetSearchResults then
        local ok, count, results = pcall(api.GetSearchResults)
        Add("GetSearchResults: " .. (ok and ("count " .. ShortValue(count) .. ", results " .. ShortValue(results)) or ("ERROR " .. tostring(count))))
        local ids = type(results) == "table" and results or nil
        if ids and api.GetSearchResultInfo then
            for i = 1, math.min(3, #ids) do
                local okI, info = pcall(api.GetSearchResultInfo, ids[i])
                Add("   result " .. i .. " (id " .. tostring(ids[i]) .. "): " .. (okI and "" or ("ERROR " .. tostring(info))))
                if okI and type(info) == "table" then
                    for _, k in ipairs(SortedKeys(info)) do Add("      " .. k .. " = " .. ShortValue(info[k])) end
                end
                if api.GetSearchResultMemberInfo then
                    local okM, m = pcall(api.GetSearchResultMemberInfo, ids[i], 1)
                    Add("      first member: " .. (okM and (type(m) ~= "table" and ShortValue(m) or table.concat(SortedKeys(m), ", ")) or ("ERROR " .. tostring(m))))
                end
            end
            if #ids == 0 then Add("   no results right now: open the group finder, search for a dungeon, and run this again") end
        end
    else
        Add("C_LFGList.GetSearchResults: not in this client")
    end
    -- the Browse window's own results, if it keeps them
    local browse = _G.LFGBrowseFrame
    if browse then
        for _, key in ipairs({ "results", "searchResults", "SearchResults", "ScrollBox", "ScrollFrame", "List", "listings" }) do
            if browse[key] ~= nil then Add("LFGBrowseFrame." .. key .. " = " .. ShortValue(browse[key])) end
        end
    end
    addon.ReportWindow("Forever Lazy: group finder", lines)
end

--------------------------------------------------------------------------------
-- /lazy report
--------------------------------------------------------------------------------
local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON, "Version") or "?"
end

function addon.BugReport()
    local db = DB()
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    local build, buildNum = "?", "?"
    if GetBuildInfo then local v, b = GetBuildInfo(); build, buildNum = tostring(v), tostring(b) end
    local _, class = UnitClass("player")
    Add("Forever Lazy " .. Version() .. "   (game " .. build .. " build " .. buildNum .. ", language " .. tostring(GetLocale and GetLocale()) .. ")")
    Add(string.format("A level %d %s, in map %s", UnitLevel("player") or 0, tostring(class), tostring(addon.hbd and addon.hbd:GetPlayerZone() or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")))))
    Add("")
    -- modules and settings that were changed
    local off = {}
    if db and db.modules then for k, v in pairs(db.modules) do if v == false then off[#off + 1] = k end end end
    table.sort(off)
    Add("Modules switched off: " .. (#off > 0 and table.concat(off, ", ") or "none"))
    local keys = { "mode", "simpleArrows", "arrowNearest", "arrowSource", "planAuto", "planZoneOnly", "planBatch", "planPaused", "bagsReplace",
        "trackerOn", "huntPanel", "craftPanel", "meterOn", "gearAdvisor", "gearBar", "rangeColor", "questSparkles" }
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(db and db[k]) end
    Add("Settings: " .. table.concat(parts, ", "))
    Add("")
    -- the plan and the arrow
    local wps = db and db.waypoints or {}
    Add("Plan: " .. #wps .. " stops")
    for i = 1, math.min(5, #wps) do
        local w = wps[i]
        Add(string.format("   %d. %s (%.0f, %.0f)%s", i, tostring(w.name or w.label), w.x or 0, w.y or 0, w.guard and " [guard]" or ""))
    end
    if addon.ArrowTarget then
        local ok, at = pcall(addon.ArrowTarget)
        if not ok then Add("Arrow: ERROR " .. tostring(at))
        elseif at == false then Add("Arrow: none, the next stop is in another zone")
        elseif not at then Add("Arrow: no target")
        else Add(string.format("Arrow: %s (%.0f, %.0f), because: %s", tostring(at.name or at.label), at.x or 0, at.y or 0, tostring(addon.arrowWhy or "-"))) end
    end
    if addon.GearSpec then
        local s = addon.GearSpec()
        Add("Gear advisor scores as: " .. s.name .. " (" .. s.kind .. ")" .. (s.forced and ", set by hand" or ""))
    end
    Add("")
    -- other addons that touch the same things
    local names = {}
    local want = { Questie = 1, QuestieDB = 1, tullaRange = 1, ForeverLootSparkles = 1, Dominos = 1, Bagnon = 1, Details = 1, ElvUI = 1, Leatrix_Plus = 1,
        MaxDps = 1, Clique = 1, GTFO = 1, Auctionator = 1, WIM = 1, SexyMap = 1, Titan = 1, HandyNotes = 1, TomTom = 1, Pawn = 1 }
    if C_AddOns and C_AddOns.GetNumAddOns then
        for i = 1, C_AddOns.GetNumAddOns() do
            local name = C_AddOns.GetAddOnInfo(i)
            if name and want[name] and C_AddOns.IsAddOnLoaded(name) then names[#names + 1] = name end
        end
    end
    Add("Other addons loaded that matter here: " .. (#names > 0 and table.concat(names, ", ") or "none of the usual ones"))
    Add("")
    -- the last errors
    Add("Last errors from Forever Lazy: " .. (#errors == 0 and "none" or #errors))
    for i, e in ipairs(errors) do
        Add(string.format("   [%d] x%d, %s ago: %s", i, e.count, SecondsToTime and SecondsToTime(math.max(1, time() - (e.t or time()))) or "?", e.msg))
    end
    Add("")
    Add("Nothing here is sent anywhere. Copy it (Ctrl+A, Ctrl+C) and paste it when you report a problem.")
    addon.ReportWindow(L("Forever Lazy: bug report"), lines)
end

--------------------------------------------------------------------------------
-- /lazy commands
--------------------------------------------------------------------------------
local COMMANDS = {
    { "Everyday", {
        { "/lazy now", "Lazy Mode: point at the best next thing" },
        { "/lazy plan [all]", "Plan the most efficient quest route (all includes other zones)" },
        { "/lazy window", "The plan window" },
        { "/lazy skip, skip clear", "List or bring back quests you skipped" },
        { "/lazy tour, new, welcome", "The tour, what's new, the welcome window" },
        { "/lazy check", "Is everything loaded and working" },
        { "/lazy report", "A bug report you can copy" },
        { "/lazy apis", "Which game functions the newer features need" },
        { "/lazy commands", "This list" },
        { "/lazy lfg", "What the group finder gives to addons (for bug reports and filter ideas)" },
        { "/lazy steps, steps reset, steps show|hide, steps on|off", "The pedometer: how far you have walked" },
        { "/lazy shaman, shaman all, shaman off", "Shaman helpers (off until you turn them on)" },
        { "/lazy paladin, paladin all, paladin off", "Paladin helpers (off until you turn them on)" },
        { "/lazy version", "Which version you are running" },
        { "/lazy blessings on|off, blessings solo, blessings debug, blessings reset", "Paladin blessings: one button for the group, a blessing for each class" },
        { "/lazy l10n, l10n use <code>, l10n missing", "Languages: what is translated, pick one, list what needs translating" } } },
    { "Finding things", {
        { "/lazy go <place>", "Plan and follow a whole trip" },
        { "/lazy inn, repair, flight, bank, ah, mailbox, stable", "The nearest one" },
        { "/lazy boat <place>, hearth, fp", "Boats, hearthstone, flight points" },
        { "/lazy way <x> <y> [name], way here, way list", "Your own waypoints" },
        { "/lazy journey", "Your zone by zone route to 60" } } },
    { "Quests", {
        { "/lazy class, dungeons, bag, nextzone, chain, farm", "Class quests, dungeons, the sleeping bag chain, next zone, chains, farming" },
        { "/lazy hunt on|off", "The panel of mobs your quests need" },
        { "/lazy tracker", "Our quest tracker" },
        { "/lazy sparkles on|off", "Sparkles on quest items you can loot" },
        { "/lazy books, craft", "Library books, crafting plans" },
        { "/lazy rankup, rankup keep <spell>, rankup unkeep <spell>", "Put the newest spell rank on your bars, or keep a low rank on purpose" } } },
    { "Gear", {
        { "/lazy gear", "What you are scored as" },
        { "/lazy gear stats", "The stats it reads from your gear (a window)" },
        { "/lazy gear list", "The upgrades in your bags" },
        { "/lazy gear on|off, gear bar on|off, gear note on|off", "Switch the parts on or off" },
        { "/lazy bankslots, bankslots on|off", "The bank bag slots row under the bank window: buy a slot, put a bag in it" },
        { "/lazy sellgray on|off|now, fastloot on|off", "Sell grey loot at vendors, and empty the loot window faster (both off until you turn them on)" },
        { "/lazy range on|off", "Colour action buttons out of range, no mana, or unusable" },
        { "/lazy platestyle v1|v2", "Which nameplates to use: v1 (red, orange, purple colours) or v2 (tank colours and threat)" },
        { "/lazy platecolors on|off", "The Plates v1 health bar colours: red attacking me, orange someone else, purple a quest mob" },
        { "/lazy threat check", "Target a mob in a fight: says which threat details the game lets addons read (the threat helpers are under Combat, Plates v2)" },
        { "/lazy flash on|off, flash check", "Flash a mob's cast bar while your interrupt is ready; check says why nothing flashes" },
        { "/lazy fish status, fish log, fish log all", "Your fishing skill, pole and lure, and what you have caught (turn the helpers on under Fishing in the options)" },
        { "/lazy fish cook", "What you can cook from the fish in your bags, and which of those can still raise your cooking" } } },
    { "Group", {
        { "/lazy spec on|off, spec check", "A player's spec on their tooltip (off until you turn it on); check says why none shows" },
        { "/lazy follow [name]", "Follow a group member" },
        { "/lazy party, shareplan, acceptplan, duo", "Group features" } } },
    { "Meter, bags and the rest", {
        { "/lazy meter [on|off], dps, damage, healing, reset", "The damage meter tab" },
        { "/lazy bags replace on|off, bags debug", "Our bag window instead of the game's" },
        { "/lazy preset minimal, leveler, duo, full", "Switch modules in one go" },
        { "/lazy lock, unlock, scale <n>, reset", "Move and resize the arrows" } } },
}
addon.CommandList = COMMANDS

function addon.CommandsReport()
    local lines = { "Every command works as /lazy or /forever. Most are also in the options or on the minimap button's menu.", "" }
    for _, group in ipairs(COMMANDS) do
        lines[#lines + 1] = group[1]
        for _, c in ipairs(group[2]) do lines[#lines + 1] = string.format("   %-52s %s", c[1], c[2]) end
        lines[#lines + 1] = ""
    end
    addon.ReportWindow(L("Forever Lazy: commands"), lines)
end

--------------------------------------------------------------------------------
-- /lazy l10n: languages
--------------------------------------------------------------------------------
local function Languages()
    local list = { "auto", "enUS" }
    local have = {}
    for code in pairs(ns.locales or {}) do have[#have + 1] = code end
    table.sort(have)
    for _, c in ipairs(have) do if c ~= "enUS" then list[#list + 1] = c end end
    return list
end
addon.LanguageList = Languages

function addon.LanguageName()
    local db = DB()
    local set = db and db.language
    local loc = ns.CurrentLocale and ns.CurrentLocale() or "enUS"
    if not set or set == "auto" then return "Automatic (" .. loc .. ")" end
    return set
end

function addon.LanguageCycle()
    local db = DB()
    local list = Languages()
    local cur = db.language or "auto"
    local idx = 1
    for i, c in ipairs(list) do if c == cur then idx = i end end
    db.language = list[(idx % #list) + 1]
    if db.language == "auto" then db.language = nil end
    ns.localeOverride = db.language
    if addon.RefreshOptions then addon.RefreshOptions() end
end

function addon.LanguageReport(which)
    local loc, have, miss = ns.LocaleStats()
    if which == "missing" then
        local list = ns.LocaleMissing()
        local lines = { "Texts asked for in " .. loc .. " that have no translation yet (" .. #list .. "). Paste the ones you translate into Locales/" .. loc .. ".lua:", "" }
        for _, text in ipairs(list) do lines[#lines + 1] = string.format("    [%q] = \"\",", text) end
        addon.ReportWindow(L("Forever Lazy: texts to translate"), lines)
        return
    end
    local installed = {}
    for code, t in pairs(ns.locales or {}) do local n = 0; for _ in pairs(t) do n = n + 1 end; installed[#installed + 1] = code .. " (" .. n .. " texts)" end
    table.sort(installed)
    Print(string.format(L("language: %s. %d texts translated for it, %d asked for without a translation so far. Translations installed: %s."),
        addon.LanguageName(), have, miss, #installed > 0 and table.concat(installed, ", ") or "none yet"))
    Print(L("  /lazy l10n use <code>|auto picks a language, /lazy l10n missing lists what still needs a translation (see docs/LOCALIZATION.md)"))
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    pcall(HookErrors)
    local db = DB()
    if db and ns.localeOverride == nil then ns.localeOverride = db.language end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "report" then addon.BugReport(); return true end
    if c == "apis" then addon.ApisReport(); return true end
    if c == "lfg" then addon.LfgReport(); return true end
    if c == "commands" or c == "cmds" then addon.CommandsReport(); return true end
    if c == "l10n" or c == "language" then
        local a = ((rest or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        local verb, arg = a:match("^(%a+)%s*(.*)$")
        if verb == "missing" then addon.LanguageReport("missing")
        elseif verb == "use" and arg ~= "" then
            local db = DB()
            db.language = (arg:lower() == "auto") and nil or arg
            ns.localeOverride = db.language
            Print(L("language: ") .. addon.LanguageName() .. L(" (some texts are drawn once, /reload shows the rest)"))
            if addon.RefreshOptions then addon.RefreshOptions() end
        else addon.LanguageReport() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Diagnostics.lua"] = true; ns2.addon.loaded["Locale.lua"] = ns2.loadedFiles and ns2.loadedFiles["Locale.lua"] or nil end end
