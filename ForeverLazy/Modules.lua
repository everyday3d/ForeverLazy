-- Modules: every part of the addon can be switched off in the options (Modules at the top).
-- A module that is off does nothing, and its commands say so. This file loads last so it can stand in front of all of them.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

-- key, name shown in the options
addon.MODULES = {
    { "lazymode", "Lazy mode (one key: point me at the next thing)" },
    { "plan",     "Route planner, plan window and the route on the map" },
    { "follow",   "Follow arrow (point at someone in my group)" },
    { "books",    "Library books" },
    { "classq",   "Class quests" },
    { "dungeons", "Dungeons (quests, entrances, level fit)" },
    { "bag",      "Cozy Sleeping Bag guide" },
    { "zones",    "Next zone and journey" },
    { "services", "Find services and trainers (inn, repair, flight master, ...)" },
    { "go",       "Take me there (/lazy go <place>)" },
    { "boats",    "Boats and zeppelins" },
    { "travel",   "Hearthstone and flight points" },
    { "party",    "Group features (shared quests, share plan, duo mode)" },
    { "quests",   "Quest helpers (item button, chain, reward pick, farm)" },
    { "crafting", "Crafting (what to craft next, materials, bank)" },
    { "gather",   "Gathering routes and fishing spots" },
    { "pet",      "Hunter pet reminder" },
    { "flight",   "Flight timer" },
}
local LABEL = {}
for _, m in ipairs(addon.MODULES) do LABEL[m[1]] = m[2] end

-- which command belongs to which module
local COMMANDS = {
    lazymode = { "now" },
    plan = { "plan", "level", "levelzone", "steps", "step", "route!", "window", "list", "stops", "skip", "why", "own", "xpmap", "heat", "hotspots" },
    follow = { "follow" },
    books = { "books", "book", "arrow" },
    classq = { "class" },
    dungeons = { "dungeons", "dungeon" },
    bag = { "bag" },
    zones = { "nextzone", "journey", "guide" },
    boats = { "boat", "boats", "zeppelin" },
    go = { "go" },
    travel = { "hearth", "home", "fp", "flightpoint", "flightpoints" },
    party = { "party", "shareplan", "acceptplan", "duo" },
    quests = { "chain", "farm" },
    crafting = { "craft", "crafting" },
    gather = { "gather", "herb", "herbs", "ore", "fish", "fishing", "nodes", "node" },
    pet = { "pet" },
    flight = { "flighttimes", "flighttime" },
}
local OWNER = {}
for key, words in pairs(COMMANDS) do for _, w in ipairs(words) do OWNER[w] = key end end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    local key = OWNER[c]
    if c == "class" and ((rest or ""):lower():gsub("%s*%d+$", "")):match("^%s*trainer") then key = "services" end
    if not key and api.IsServiceCommand and api.IsServiceCommand(cmd, rest) then key = "services" end
    if key and not addon.ModuleOn(key) then
        Print(string.format("%s is switched off. Turn it on in the options, under Modules.", LABEL[key] or key))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- the planner itself
local origPlan = addon.PlanRoute
function addon:PlanRoute(...)
    if not addon.ModuleOn("plan") then return end
    return origPlan(self, ...)
end

-- switching a module off should show straight away: hide its windows and remove its arrows
local STOP_FLAG = { bag = "bag", boats = "boat", services = "service", travel = "hearth", quests = "farm", crafting = "craft", gather = "gather", go = "go" }

function addon.ModulesChanged()
    local db = DB()
    if not db then return end
    local wps = db.waypoints or {}
    for i = #wps, 1, -1 do
        local w = wps[i]
        for key, flag in pairs(STOP_FLAG) do
            if w[flag] and not addon.ModuleOn(key) then table.remove(wps, i); break end
        end
    end
    if not addon.ModuleOn("plan") then
        for i = #wps, 1, -1 do if wps[i].label then table.remove(wps, i) end end
    end
    for _, name in ipairs({ "ForeverLazy_PetAlert", "ForeverLazy_FlightTimer" }) do
        local f = _G[name]
        if f and f.Hide then f:Hide() end
    end
    if not addon.ModuleOn("plan") and _G.ForeverLazy_PlanWindow then _G.ForeverLazy_PlanWindow:Hide() end
    if addon.RefreshQuestItems then pcall(addon.RefreshQuestItems) end
    if addon.DrawRouteLines then pcall(addon.DrawRouteLines) end
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
end

--------------------------------------------------------------------------------
-- Presets: which modules are on
--   /lazy preset minimal | leveler | duo | full
--------------------------------------------------------------------------------
local PRESETS = {
    minimal = { "lazymode", "plan", "services" },
    leveler = { "lazymode", "plan", "follow", "books", "classq", "dungeons", "bag", "zones", "services", "boats", "go", "travel", "quests", "gather", "pet", "flight" },
    duo     = { "lazymode", "plan", "follow", "party", "classq", "dungeons", "bag", "zones", "services", "boats", "go", "travel", "quests", "gather", "pet", "flight" },
}

function addon.ApplyPreset(name)
    local db = DB()
    if not db then return end
    local set = {}
    if name == "full" then
        for _, m in ipairs(addon.MODULES) do set[m[1]] = true end
    elseif PRESETS[name] then
        for _, k in ipairs(PRESETS[name]) do set[k] = true end
    else
        Print("presets: minimal, leveler, duo, full")
        return
    end
    db.modules = {}
    for _, m in ipairs(addon.MODULES) do db.modules[m[1]] = set[m[1]] and true or false end
    if name == "duo" then db.duoCompass = true; db.duoAuto = nil end
    addon.ModulesChanged()
    local on = {}
    for _, m in ipairs(addon.MODULES) do if set[m[1]] then on[#on + 1] = m[1] end end
    Print(string.format("preset %s: %d modules on (%s)", name, #on, table.concat(on, ", ")))
end

local prevPreset = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "preset" then
        addon.ApplyPreset(((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")))
        return true
    end
    if prevPreset then return prevPreset(self, cmd, rest) end
end

--------------------------------------------------------------------------------
-- /lazy check: is everything loaded and working
--------------------------------------------------------------------------------
function addon.CheckInstall()
    local results = {}
    local function check(name, ok, hint)
        results[#results + 1] = { name = name, ok = ok and true or false, hint = hint }
    end
    local QDB = api.GetQuestie and api.GetQuestie()
    check("Questie is ready (planner, quests, services need it)", api.QuestieReady and api.QuestieReady(), "install Questie, or wait for it to finish loading")
    local T = _G.QuestieLoader and select(2, pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, "Townsfolk"))
    check("Questie's service lists are loaded", type(T) == "table" and T.townsfolk and next(T.townsfolk) ~= nil, "they fill in a minute after login")
    check("the map data works", hbd and hbd.GetWorldCoordinatesFromZone and hbd:GetWorldCoordinatesFromZone(0.5, 0.5, 1429) ~= nil, "HereBeDragons did not load")
    check("options page is registered in the AddOns list", addon.OptionsBuilt and addon.OptionsBuilt(), addon.OptionsError or "it is made 3 seconds after login; try /lazy check again in a moment")
    local parts = {
        { "planner", addon.PlanRoute }, { "plan window", addon.TogglePlanWindow }, { "route lines on the map", addon.DrawRouteLines },
        { "right-click skip menu", addon.OpenSkipMenu }, { "journey", addon.JourneyGenerate }, { "lazy mode", addon.LazyNow },
        { "macros", addon.MakeMacros }, { "modules", addon.ModuleOn }, { "services search", api.FindService },
        { "class quests", api.ClassGivers }, { "dungeon entrances", api.DungeonEntrance }, { "duo mode", addon.DuoRole },
        { "quest items", addon.RefreshQuestItems }, { "crafting", addon.CraftNeeds }, { "dock sharing", addon.NetShareDock },
        { "next zone", api.NextZone }, { "follow arrow", addon.FollowMember },
        { "levelling guide (Guide.lua)", addon.ToggleGuide }, { "damage meter (Meter.lua)", addon.MeterSet }, { "XP hot spots", addon.XPHotSpots }, { "arrow choice", addon.ArrowTarget },
        { "menu and buttons (UI.lua)", addon.ShowMenu }, { "tour and settings sharing (Help.lua)", addon.StartTour },
    }
    local FILES = { "ForeverLazy.lua", "Options.lua", "Extras.lua", "Books.lua", "Pet.lua", "Flight.lua", "NextZone.lua", "Dungeons.lua", "Bag.lua",
        "ClassQuests.lua", "Boats.lua", "Services.lua", "FlightData.lua", "Travel.lua", "Party.lua", "Quests.lua", "PlanWindow.lua", "Journey.lua",
        "Community.lua", "Crafting.lua", "Inventory.lua", "Hive.lua", "Live.lua", "Gather.lua", "Nodes.lua", "Protect.lua", "GuardPoi.lua", "PlanGuard.lua", "Tracker.lua", "Autopilot.lua", "Version.lua", "Go.lua", "LazyMode.lua", "UI.lua", "Help.lua", "Guide.lua", "Coach.lua", "Meter.lua", "Modules.lua" }
    for _, f in ipairs(FILES) do
        check("file loaded: " .. f, addon.loaded and addon.loaded[f], "this file stopped on a Lua error while loading. Turn errors on with /console scriptErrors 1, then /reload")
    end
    for _, p in ipairs(parts) do check("part loaded: " .. p[1], p[2] ~= nil, "its file did not load, check for a Lua error and the .toc list") end
    local fails = 0
    for _, r in ipairs(results) do if not r.ok then fails = fails + 1 end end
    Print(string.format("check: %d of %d passed. Version %s.", #results - fails, #results,
        ((C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata)("ForeverLazy", "Version") or "?"))
    for _, r in ipairs(results) do
        if not r.ok then Print("  |cffff5555FAILED|r " .. r.name .. (r.hint and (" - " .. r.hint) or "")) end
    end
    if fails == 0 then Print("  everything is in place.") end
end

local prevCheck = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "check" then
        addon.CheckInstall()
        return true
    end
    if prevCheck then return prevCheck(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Modules.lua"] = true end end
