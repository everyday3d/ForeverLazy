-- A damage meter that lives in its own chat tab, so it is out of the way. It reads the game's built-in damage meter
-- (C_DamageMeter), the same source Details! uses on this client, and draws a bar and a number for each player.
--   /lazy meter                    make or show the tab (and turn the meter on)
--   /lazy meter off                turn it off
--   /lazy meter dps|damage|healing|hps|taken|interrupts|dispels|deaths     what to show
--   /lazy meter current|overall    this fight, or everything since the last reset
--   /lazy meter rows 8             how many players to list
--   /lazy meter reset              clear the game's meter data
--   /lazy meter debug              what the meter API gave back (for bug reports)
-- In combat the game hides the numbers from addons, so the tab keeps the last picture until the fight is over.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function DB() return addon.GetDB() end

local TAB_NAME = "Meter"
local METRICS = {
    damage     = { enum = "DamageDone",   label = "Damage done" },
    dps        = { enum = "Dps",          label = "Damage per second" },
    healing    = { enum = "HealingDone",  label = "Healing done" },
    hps        = { enum = "Hps",          label = "Healing per second" },
    taken      = { enum = "DamageTaken",  label = "Damage taken" },
    interrupts = { enum = "Interrupts",   label = "Interrupts" },
    dispels    = { enum = "Dispels",      label = "Dispels" },
    deaths     = { enum = "Deaths",       label = "Deaths" },
}

local function IsSecret(v)
    return _G.issecretvalue and _G.issecretvalue(v) or false
end

local function Short(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
    if n >= 1000 then return string.format("%.1fK", n / 1000) end
    return tostring(math.floor(n + 0.5))
end

--------------------------------------------------------------------------------
-- Where it is drawn: a chat tab named "Meter", else a small window of its own
--------------------------------------------------------------------------------
local frame, usingTab
local problems = {}

local function FindTab()
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local name = GetChatWindowInfo and GetChatWindowInfo(i)
        if name == TAB_NAME then return _G["ChatFrame" .. i] end
    end
end

local function MakeFallback()
    local f = CreateFrame("ScrollingMessageFrame", "ForeverLazy_MeterWindow", UIParent)
    f:SetSize(340, 200)
    f:SetPoint("BOTTOMLEFT", 20, 200)
    f:SetFontObject(ChatFontNormal or GameFontHighlight)
    f:SetJustifyH("LEFT")
    f:SetFading(false)
    f:SetMaxLines(60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
    return f
end

local function EnsureFrame()
    if frame then return frame end
    local f = FindTab()
    if not f and _G.FCF_OpenNewWindow then
        local prev = _G.SELECTED_CHAT_FRAME
        local ok, made = pcall(FCF_OpenNewWindow, TAB_NAME, true)
        if ok and made then
            f = made
            -- nothing else should ever be written into this tab
            if ChatFrame_RemoveAllMessageGroups then pcall(ChatFrame_RemoveAllMessageGroups, f) end
            if ChatFrame_RemoveAllChannels then pcall(ChatFrame_RemoveAllChannels, f) end
            if prev and FCF_SelectDockFrame then pcall(FCF_SelectDockFrame, prev) end
        else
            problems.tab = "could not make a chat tab: " .. tostring(made)
        end
    end
    if f then
        usingTab = true
        if f.SetFading then pcall(f.SetFading, f, false) end
        if f.SetMaxLines then pcall(f.SetMaxLines, f, 120) end
        frame = f
    else
        usingTab = false
        frame = MakeFallback()
    end
    return frame
end

--------------------------------------------------------------------------------
-- Reading the game's meter and drawing it
--------------------------------------------------------------------------------
local function GetSession()
    local DM = _G.C_DamageMeter
    if not (DM and DM.GetCombatSessionFromType and Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then
        return nil, "this client has no built-in damage meter"
    end
    local db = DB()
    local metric = METRICS[db.meterMetric or "dps"] or METRICS.dps
    local mt = Enum.DamageMeterType[metric.enum]
    if mt == nil then return nil, "this client does not know " .. metric.label end
    local st = (db.meterSegment == "overall") and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
    local ok, s = pcall(DM.GetCombatSessionFromType, st, mt)
    if not ok then return nil, tostring(s) end
    return s, nil, metric
end

local inCombat = false
local lastLines

local function ClassColour(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), c.colorStr and c.colorStr:sub(3) or "ffffff" end
    return 200, 200, 200, "c8c8c8"
end

-- returns the lines to show, or nil with a reason when the numbers are hidden (in combat)
local function BuildLines()
    local s, err, metric = GetSession()
    if not s then return nil, err or "no data" end
    local list = s.combatSources
    if type(list) ~= "table" then return nil, "no data yet" end
    local db = DB()
    local rows = {}
    for _, src in ipairs(list) do
        if IsSecret(src.name) or IsSecret(src.totalAmount) or IsSecret(src.amountPerSecond) then
            return nil, "the numbers are hidden while you fight"
        end
        rows[#rows + 1] = src
    end
    if IsSecret(s.totalAmount) or IsSecret(s.maxAmount) or IsSecret(s.durationSeconds) then
        return nil, "the numbers are hidden while you fight"
    end
    table.sort(rows, function(a, b) return (a.totalAmount or 0) > (b.totalAmount or 0) end)
    local maxAmount = (rows[1] and rows[1].totalAmount) or s.maxAmount or 0
    local total = s.totalAmount or 0
    local seg = (db.meterSegment == "overall") and "Overall" or "Current fight"
    local dur = tonumber(s.durationSeconds) or 0
    local lines = { string.format("|cffffd100%s|r  |cff888888%s, %d:%02d|r", metric.label, seg, math.floor(dur / 60), math.floor(dur % 60)) }
    local maxRows = math.min(20, math.max(3, tonumber(db.meterRows) or 8))
    for i = 1, math.min(maxRows, #rows) do
        local src = rows[i]
        local amount = tonumber(src.totalAmount) or 0
        local r, g, b, hex = ClassColour(src.classFilename)
        local width = (maxAmount and maxAmount > 0) and math.max(2, math.floor(110 * amount / maxAmount)) or 2
        local bar = string.format("|TInterface\\Buttons\\WHITE8X8:9:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t", width, r, g, b)
        local name = tostring(src.name or "?"):match("^([^%-]+)") or tostring(src.name or "?")
        local pct = (total > 0) and math.floor(amount / total * 100 + 0.5) or 0
        local per = tonumber(src.amountPerSecond)
        local extra = (per and per > 0 and metric.enum ~= "Dps" and metric.enum ~= "Hps") and string.format(" |cff888888%s/s|r", Short(per)) or ""
        lines[#lines + 1] = string.format("%s%2d. %s |cff%s%s|r  %s%s |cff888888%d%%|r", src.isLocalPlayer and "|cffffd100>|r" or " ", i, bar, hex, name, Short(amount), extra, pct)
    end
    if #rows == 0 then lines[#lines + 1] = "|cff888888nothing recorded yet|r" end
    return lines
end

local function Draw(lines, note)
    local f = EnsureFrame()
    if not f then return end
    if f.Clear then f:Clear() elseif f.ClearAllMessages then f:ClearAllMessages() end
    if lines then
        for _, l in ipairs(lines) do f:AddMessage(l, 1, 1, 1) end
        if note then f:AddMessage("|cff888888" .. note .. "|r", 1, 1, 1) end
    else
        f:AddMessage("|cffffd100Forever Lazy meter|r", 1, 1, 1)
        f:AddMessage("|cff888888" .. tostring(note or "waiting") .. "|r", 1, 1, 1)
    end
end

local function Refresh()
    local db = DB()
    if not db or db.meterOn ~= true then return end
    local lines, why = BuildLines()
    if lines then
        lastLines = lines
        Draw(lines)
    elseif lastLines and inCombat then
        Draw(lastLines, "(" .. tostring(why) .. "; the last picture is shown)")
    else
        Draw(nil, why)
    end
end

--------------------------------------------------------------------------------
-- Keeping it fresh
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "DAMAGE_METER_COMBAT_SESSION_UPDATED",
                     "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    local db = DB()
    if event == "PLAYER_LOGIN" then
        if db then db.meterMetric = db.meterMetric or "dps"; db.meterSegment = db.meterSegment or "current" end
        if db and db.meterOn == true and C_Timer then C_Timer.After(5, function() pcall(Refresh) end) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if C_Timer then C_Timer.After(0.6, function() pcall(Refresh) end) end
    elseif db and db.meterOn == true and C_Timer then
        C_Timer.After(0.3, function() pcall(Refresh) end)
    end
end)

local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1.5 then return end
    acc = 0
    local db = DB()
    if db and db.meterOn == true then pcall(Refresh) end
end)

--------------------------------------------------------------------------------
-- On, off, and the commands
--------------------------------------------------------------------------------
function addon.MeterSet(on)
    local db = DB()
    db.meterOn = on and true or false
    if on then
        local f = EnsureFrame()
        Print(usingTab and "the damage meter is on: look for the Meter tab in your chat window"
            or "the damage meter is on, in a small window (a chat tab could not be made" .. (problems.tab and (": " .. problems.tab) or "") .. ")")
        Refresh()
    else
        if frame and not usingTab then frame:Hide() end
        if frame and usingTab and frame.Clear then frame:Clear(); frame:AddMessage("|cff888888Forever Lazy meter is off (/lazy meter)|r", 1, 1, 1) end
        Print("the damage meter is off")
    end
    if addon.RefreshOptions then addon.RefreshOptions() end
end

local function Debug()
    local DM = _G.C_DamageMeter
    Print("meter debug: C_DamageMeter " .. (DM and "present" or "MISSING") .. ", tab frame " .. (FindTab() and "found" or "not found")
        .. ", drawing in " .. (frame and (usingTab and "a chat tab" or "the fallback window") or "nothing yet"))
    if problems.tab then Print("  tab problem: " .. problems.tab) end
    local s, err = GetSession()
    if not s then Print("  session: " .. tostring(err)); return end
    local list = s.combatSources
    Print(string.format("  session: %d sources, total %s, max %s, duration %s", type(list) == "table" and #list or -1,
        IsSecret(s.totalAmount) and "hidden" or tostring(s.totalAmount), IsSecret(s.maxAmount) and "hidden" or tostring(s.maxAmount),
        IsSecret(s.durationSeconds) and "hidden" or tostring(s.durationSeconds)))
    if type(list) == "table" and list[1] then
        local a = list[1]
        Print(string.format("  first source: name %s, total %s, per second %s, class %s", IsSecret(a.name) and "hidden" or tostring(a.name),
            IsSecret(a.totalAmount) and "hidden" or tostring(a.totalAmount), IsSecret(a.amountPerSecond) and "hidden" or tostring(a.amountPerSecond),
            tostring(a.classFilename)))
    end
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "meter" then
        local db = DB()
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "" or a == "on" then addon.MeterSet(true)
        elseif a == "off" then addon.MeterSet(false)
        elseif a == "debug" then Debug()
        elseif a == "reset" then
            if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then pcall(C_DamageMeter.ResetAllCombatSessions); lastLines = nil; Print("the game's damage meter data was cleared"); Refresh()
            else Print("this client has no damage meter to reset") end
        elseif a == "current" or a == "overall" then
            db.meterSegment = a; Print("meter: showing " .. (a == "overall" and "everything since the last reset" or "the current fight")); Refresh()
        elseif METRICS[a] then
            db.meterMetric = a; Print("meter: showing " .. METRICS[a].label:lower()); Refresh()
        elseif a:match("^rows%s*(%d+)$") then
            db.meterRows = tonumber(a:match("^rows%s*(%d+)$")); Print("meter: listing " .. db.meterRows .. " players"); Refresh()
        else
            Print("/lazy meter on|off|reset|debug, dps|damage|healing|hps|taken|interrupts|dispels|deaths, current|overall, rows <n>")
        end
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Meter.lua"] = true end end
