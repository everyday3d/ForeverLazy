-- Quest item sparkles: keeps the game's own loot sparkle switched on for quest items, so you never walk past one.
-- Graphics presets switch it off; this switches it back on at login and about a second after a graphics change.
--   /lazy sparkles on|off
-- The idea and the console variable come from Forever Loot Sparkles by Ashtar Senior (GPL-3.0-or-later,
-- https://www.curseforge.com/wow/addons/forever-loot-sparkles). This is a small re-write of its job inside Forever Lazy.
-- If that addon is installed too, it does the job and this one stays out of the way.
local ADDON, ns = ...
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

local CVAR = "outlineModeShowLootEffectWhenDisabled"

local function Handled()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverLootSparkles")
end

local function On()
    local db = DB()
    return db and db.questSparkles ~= false and not Handled()
end

local applying, pending, wasOn = false, false, false

local function SetCVar(value)
    local cur = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(CVAR)
    if cur == nil or cur == value then return end
    applying = true
    pcall(C_CVar.SetCVar, CVAR, value)
    applying = false
end

local function Apply()
    if not On() then return end
    if InCombatLockdown() then pending = true; return end
    wasOn = true
    SetCVar("1")
end

local function Later(sec)
    if C_Timer and C_Timer.After then C_Timer.After(sec, Apply) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(ev.RegisterEvent, ev, "CVAR_UPDATE")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        Apply(); Later(5)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then pending = false; Apply() end
    elseif not applying and type(arg1) == "string" then
        local k = arg1:lower()
        -- a graphics preset (or anything else) changed it: put it back a moment later
        if k == "graphicsquality" or k == "raidgraphicsquality" or k == CVAR:lower() then Later(1) end
    end
end)

-- called by the options checkbox and the command
addon.QuestSparklesRefresh = function()
    if On() then
        Apply()
    elseif wasOn and not Handled() then
        if not InCombatLockdown() then SetCVar("0") end
        Print("quest item sparkles: restart the game to remove them (/reload is not enough)")
    end
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "sparkles" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "off" then db.questSparkles = false elseif a == "on" then db.questSparkles = nil end
        Print("quest item sparkles: " .. (db.questSparkles == false and "OFF" or "on") .. "  (/lazy sparkles on|off). The game's own sparkle on quest items you can loot."
            .. (Handled() and " Forever Loot Sparkles is installed, so it does this job." or ""))
        addon.QuestSparklesRefresh()
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestSparkles.lua"] = true end end
