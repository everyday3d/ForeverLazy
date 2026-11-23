-- Help for finding problems and learning the commands:
--   /lazy report     a bug report in a window you can copy: version, client, settings, the plan and arrow, other addons, last errors
--   /lazy apis       which game functions the newer features need, and whether this client has them
--   /lazy commands   every command, in groups
-- Lua errors that mention Forever Lazy are remembered (the last 10) and go into the report. Nothing is sent anywhere.
local ADDON, ns = ...
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
    addon.ReportWindow("Forever Lazy: game functions", lines)
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
        "trackerOn", "huntPanel", "questItemReminder", "craftPanel", "meterOn", "gearAdvisor", "gearBar", "rangeColor", "questSparkles" }
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
    addon.ReportWindow("Forever Lazy: bug report", lines)
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
        { "/lazy commands", "This list" } } },
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
        { "/lazy range on|off", "Colour action buttons out of range, no mana, or unusable" } } },
    { "Group", {
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
    addon.ReportWindow("Forever Lazy: commands", lines)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() pcall(HookErrors) end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "report" then addon.BugReport(); return true end
    if c == "apis" then addon.ApisReport(); return true end
    if c == "commands" or c == "cmds" then addon.CommandsReport(); return true end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Diagnostics.lua"] = true end end
