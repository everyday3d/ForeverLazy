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
local lastDrawn            -- what was last drawn (declared up here so everything below shares ONE variable)
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

local lastTabTry = 0
local cleaned = {}          -- chat tabs already stripped of message groups this session

-- a chat tab still counts only while it is still in the chat window list under our name
local function TabStillThere()
    local t = FindTab()
    return t ~= nil and t == frame
end

local function EnsureFrame()
    if frame then
        if usingTab then
            if TabStillThere() then
                -- other addons or the game may add message groups back: keep the tab ours (checked now and then)
                if not cleaned[frame] then
                    cleaned[frame] = true
                    if ChatFrame_RemoveAllMessageGroups then pcall(ChatFrame_RemoveAllMessageGroups, frame) end
                    if ChatFrame_RemoveAllChannels then pcall(ChatFrame_RemoveAllChannels, frame) end
                end
                return frame
            end
            -- the tab was closed or renamed: forget it and make (or find) one again
            frame = nil; usingTab = nil; lastDrawn = nil
        else
            -- in the small fallback window: try to get a real tab again once a minute (never in combat)
            if GetTime() - lastTabTry < 60 or (InCombatLockdown and InCombatLockdown()) then return frame end
            lastTabTry = GetTime()
            local t = FindTab()
            if not t and _G.FCF_OpenNewWindow then
                local ok, made = pcall(FCF_OpenNewWindow, TAB_NAME, true)
                if ok and made then t = made end
            end
            if not t then return frame end
            frame:Hide(); frame = nil; lastDrawn = nil
        end
    end
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
        cleaned[f] = true
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

--------------------------------------------------------------------------------
-- Hover a player: the moves they used and how much of the total each was
--------------------------------------------------------------------------------
local hovering = false      -- the mouse is on a name: do not redraw under it
local hoverSince = 0       -- when the hover started (a hover whose "leave" never came must not freeze the meter)
local rowInfo = {}          -- link number -> { guid, creatureID, name, class, amount, total, st, mt }

local function SpellLabel(id)
    local name, icon
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id); if ok then name = n end
        local ok2, t = pcall(C_Spell.GetSpellTexture, id); if ok2 then icon = t end
    elseif GetSpellInfo then
        local ok, n, _, t = pcall(GetSpellInfo, id); if ok then name, icon = n, t end
    end
    name = name or ("Spell " .. tostring(id))
    return (icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. name
end

local function ShowRowTooltip(owner, link)
    local n = tonumber(tostring(link):match("^flmeter:(%d+)"))
    local r = n and rowInfo[n]
    if not r then GameTooltip:Hide(); return end              -- that list has been replaced since: nothing stale on show
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    local _, _, _, hex = ClassColour(r.class)
    GameTooltip:AddLine("|cff" .. hex .. tostring(r.name) .. "|r")
    local pct = (r.total and r.total > 0) and (r.amount / r.total * 100) or 0
    GameTooltip:AddDoubleLine(r.label or "Total", string.format("%s  (%.1f%% of the group)", Short(r.amount), pct), 1, 0.82, 0, 1, 1, 1)
    if r.per and r.per > 0 then GameTooltip:AddDoubleLine("Per second", Short(r.per), 1, 0.82, 0, 1, 1, 1) end
    if inCombat then
        GameTooltip:AddLine("The moves are hidden while you fight", 0.6, 0.6, 0.6)
    else
        local DM = _G.C_DamageMeter
        local ok, src = false, nil
        if DM and DM.GetCombatSessionSourceFromType then
            ok, src = pcall(DM.GetCombatSessionSourceFromType, r.st, r.mt, r.guid, r.creatureID)
        end
        local spells = ok and type(src) == "table" and src.combatSpells
        if type(spells) == "table" and #spells > 0 then
            local list = {}
            local sum = 0
            for _, sp in ipairs(spells) do
                if IsSecret(sp.totalAmount) or IsSecret(sp.spellID) then list = nil; break end
                list[#list + 1] = sp
                sum = sum + (tonumber(sp.totalAmount) or 0)
            end
            if list then
                table.sort(list, function(a, b) return (a.totalAmount or 0) > (b.totalAmount or 0) end)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Moves used", 0.7, 0.85, 1)
                for i = 1, math.min(12, #list) do
                    local sp = list[i]
                    local amt = tonumber(sp.totalAmount) or 0
                    local p = sum > 0 and (amt / sum * 100) or 0
                    local extra = (tonumber(sp.amountPerSecond) or 0) > 0 and (" " .. Short(sp.amountPerSecond) .. "/s") or ""
                    GameTooltip:AddDoubleLine(SpellLabel(sp.spellID), string.format("%s  %.1f%%%s", Short(amt), p, extra), 1, 1, 1, 0.8, 0.8, 0.8)
                end
                if #list > 12 then GameTooltip:AddLine(string.format("... and %d more", #list - 12), 0.5, 0.5, 0.5) end
            end
        else
            GameTooltip:AddLine("No move list for this one", 0.6, 0.6, 0.6)
        end
    end
    GameTooltip:Show()
end

local hooked = {}
local function HookTooltips(f)
    if not f or hooked[f] then return end
    hooked[f] = true
    if f.SetHyperlinksEnabled then pcall(f.SetHyperlinksEnabled, f, true) end
    pcall(f.HookScript, f, "OnHyperlinkEnter", function(self, link)
        if tostring(link):find("^flmeter:") then hovering = true; hoverSince = GetTime(); pcall(ShowRowTooltip, self, link) end
    end)
    pcall(f.HookScript, f, "OnHyperlinkLeave", function(self, link)
        if tostring(link):find("^flmeter:") then hovering = false; GameTooltip:Hide() end
    end)
    -- a leave that never arrived (the mouse left the whole tab): hide the tooltip when the mouse is no longer over it
    pcall(f.HookScript, f, "OnUpdate", function(self)
        if not hovering then return end
        -- the mouse left the tab, or the hover has lasted so long a "leave" must have been missed: let the meter move again
        if not self:IsMouseOver() or GetTime() - hoverSince > 12 then hovering = false; GameTooltip:Hide() end
    end)
end

-- returns the lines to show, or nil with a reason when the numbers are hidden (in combat)
local function BuildLines()
    local s, err, metric = GetSession()
    if not s then return nil, err or "no data" end
    local list = s.combatSources
    if type(list) ~= "table" then return nil, "no data yet" end
    local db = DB()
    -- one hidden entry must not blank the whole list: skip just that one (and say so); only when none can be read is it "hidden"
    local rows, hiddenCount = {}, 0
    for _, src in ipairs(list) do
        if type(src) ~= "table" then
            hiddenCount = hiddenCount + 1
        elseif IsSecret(src.name) or IsSecret(src.totalAmount) or type(src.totalAmount) ~= "number" then
            hiddenCount = hiddenCount + 1
        else
            if IsSecret(src.amountPerSecond) then src.amountPerSecond = nil end
            if IsSecret(src.classFilename) then src.classFilename = nil end
            rows[#rows + 1] = src
        end
    end
    if #rows == 0 and hiddenCount > 0 then return nil, "the numbers are hidden while you fight" end
    table.sort(rows, function(a, b) return (a.totalAmount or 0) > (b.totalAmount or 0) end)
    local maxAmount = (rows[1] and rows[1].totalAmount) or 0
    -- the group total: the game's number when it can be read, else the sum of the rows shown
    local total = 0
    if not IsSecret(s.totalAmount) and type(s.totalAmount) == "number" then
        total = s.totalAmount
    else
        for _, r in ipairs(rows) do total = total + (r.totalAmount or 0) end
    end
    local seg = (db.meterSegment == "overall") and "Overall" or "Current fight"
    local dur = (not IsSecret(s.durationSeconds)) and tonumber(s.durationSeconds) or 0
    local lines = { string.format("|cffffd100%s|r  |cff888888%s, %d:%02d|r", metric.label, seg, math.floor(dur / 60), math.floor(dur % 60)) }
    local maxRows = math.min(20, math.max(3, tonumber(db.meterRows) or 8))
    -- the tooltip rows belong to THIS list only (an old list's players must never show under a new list's names)
    for k in pairs(rowInfo) do rowInfo[k] = nil end
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
        -- the name is a link, so hovering it gives the tooltip (guid and creature id are only used when readable)
        local guid = (not IsSecret(src.sourceGUID)) and src.sourceGUID or nil
        local linkName = name
        if guid or src.sourceCreatureID then
            rowInfo[i] = { guid = guid, creatureID = (not IsSecret(src.sourceCreatureID)) and src.sourceCreatureID or nil, name = name,
                class = src.classFilename, amount = amount, total = total, per = per, label = metric.label,
                st = (db.meterSegment == "overall") and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current,
                mt = Enum.DamageMeterType[metric.enum] }
            linkName = string.format("|Hflmeter:%d|h%s|h", i, name)
        end
        lines[#lines + 1] = string.format("%s%2d. %s |cff%s%s|r  %s%s |cff888888%d%%|r", src.isLocalPlayer and "|cffffd100>|r" or " ", i, bar, hex, linkName, Short(amount), extra, pct)
    end
    if #rows == 0 then lines[#lines + 1] = "|cff888888nothing recorded yet|r" end
    if hiddenCount > 0 then lines[#lines + 1] = string.format("|cff888888(%d hidden while you fight)|r", hiddenCount) end
    return lines
end

local function Draw(lines, note)
    local f = EnsureFrame()
    if not f then return end
    HookTooltips(f)
    -- same picture as before: leave it alone, a redraw would reset the hover and the tooltip
    local key = (lines and table.concat(lines, "\n") or "") .. "|" .. tostring(note)
    if key == lastDrawn then return end
    lastDrawn = key
    -- a chat frame can go bad under us (closed while we draw): never let that throw
    local ok = pcall(function()
        if f.Clear then f:Clear() elseif f.ClearAllMessages then f:ClearAllMessages() end
        if lines then
            for _, l in ipairs(lines) do f:AddMessage(l, 1, 1, 1) end
            if note then f:AddMessage("|cff888888" .. note .. "|r", 1, 1, 1) end
        else
            f:AddMessage("|cffffd100Forever Lazy meter|r", 1, 1, 1)
            f:AddMessage("|cff888888" .. tostring(note or "waiting") .. "|r", 1, 1, 1)
        end
    end)
    if not ok then lastDrawn = nil; frame = nil; usingTab = nil end       -- next time: find or make the tab again
end

local function Refresh()
    local db = DB()
    if not db or db.meterOn ~= true then return end
    if hovering then return end
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
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "DAMAGE_METER_COMBAT_SESSION_UPDATED",
                     "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- forget everything drawn: the next refresh starts from the game's data again
local function ForgetPicture()
    lastLines = nil
    lastDrawn = nil
    hovering = false
    for k in pairs(rowInfo) do rowInfo[k] = nil end
    if GameTooltip then GameTooltip:Hide() end
end

local lastInstanceKey
ev:SetScript("OnEvent", function(_, event)
    local db = DB()
    if event == "DAMAGE_METER_RESET" then
        -- the game cleared its data (reset button, /lazy meter reset, another addon): no old picture or tooltip survives
        ForgetPicture()
        if db and db.meterOn == true and C_Timer then C_Timer.After(0.3, function() pcall(Refresh) end) end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- zoning: a stale picture and a stuck hover go away; a NEW dungeon or raid starts a fresh meter (switch off: /lazy meter autoreset off)
        inCombat = false
        ForgetPicture()
        if db then
            local name, itype, _, _, _, _, _, instId = GetInstanceInfo and GetInstanceInfo()
            local key = (itype == "party" or itype == "raid") and (tostring(instId or name)) or nil
            if key and key ~= lastInstanceKey and lastInstanceKey ~= nil and db.meterAutoReset ~= false and db.meterOn == true
                and C_DamageMeter and C_DamageMeter.ResetAllCombatSessions and not (InCombatLockdown and InCombatLockdown()) then
                pcall(C_DamageMeter.ResetAllCombatSessions)
                Print("meter: new " .. tostring(name) .. ", so the meter starts fresh (/lazy meter autoreset off to keep old numbers)")
            end
            if key then lastInstanceKey = key elseif lastInstanceKey == nil then lastInstanceKey = "" end
            if db.meterOn == true and C_Timer then C_Timer.After(2, function() pcall(Refresh) end) end
        end
        return
    elseif event == "PLAYER_LOGIN" then
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
    lastDrawn = nil
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
        elseif a:match("^autoreset") then
            local v = a:match("^autoreset%s+(%a+)")
            if v == "off" then db.meterAutoReset = false elseif v == "on" then db.meterAutoReset = nil end
            Print("meter: a new dungeon or raid " .. ((db.meterAutoReset == false) and "keeps the old numbers" or "starts the meter fresh") .. " (/lazy meter autoreset on|off)")
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
