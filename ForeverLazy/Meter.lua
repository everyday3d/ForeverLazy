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
local L = ns.L
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
        GameTooltip:AddLine(L("The moves are hidden while you fight"), 0.6, 0.6, 0.6)
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
                GameTooltip:AddLine(L("Moves used"), 0.7, 0.85, 1)
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
            GameTooltip:AddLine(L("No move list for this one"), 0.6, 0.6, 0.6)
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
    -- the players to list: the top ones, and me at the bottom when I am further down (like Details)
    local order = {}
    for i = 1, math.min(maxRows, #rows) do order[i] = i end
    if #rows > maxRows then
        for i = maxRows + 1, #rows do
            if rows[i].isLocalPlayer then order[maxRows] = i; break end
        end
    end
    for slot, i in ipairs(order) do
        local src = rows[i]
        local amount = tonumber(src.totalAmount) or 0
        local r, g, b, hex = ClassColour(src.classFilename)
        -- a Details-style bar: the class colour for the share of the top player, a dark track for the rest
        local BARW = 90
        local width = (maxAmount and maxAmount > 0) and math.max(2, math.floor(BARW * amount / maxAmount)) or 2
        local bar = string.format("|TInterface\\Buttons\\WHITE8X8:10:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t", width, r, g, b)
        if width < BARW then
            bar = bar .. string.format("|TInterface\\Buttons\\WHITE8X8:10:%d:0:0:8:8:0:8:0:8:50:50:55|t", BARW - width)
        end
        -- the class icon in front
        local icon = ""
        local tc = _G.CLASS_ICON_TCOORDS and src.classFilename and _G.CLASS_ICON_TCOORDS[src.classFilename]
        if tc then
            icon = string.format("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:14:14:0:0:256:256:%d:%d:%d:%d|t ",
                math.floor(tc[1] * 256), math.floor(tc[2] * 256), math.floor(tc[3] * 256), math.floor(tc[4] * 256))
        end
        local name = tostring(src.name or "?"):match("^([^%-]+)") or tostring(src.name or "?")
        local pct = (total > 0) and math.floor(amount / total * 100 + 0.5) or 0
        local per = tonumber(src.amountPerSecond)
        local isRate = (metric.enum == "Dps" or metric.enum == "Hps")
        local extra = ""        -- "total (per second, percent)" like Details; a rate metric has no separate per second
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
        local detail
        if per and per > 0 and not isRate then detail = string.format("%s, %d%%", Short(per), pct) else detail = string.format("%d%%", pct) end
        local nameCol = src.isLocalPlayer and "ffffd100" or hex
        lines[#lines + 1] = string.format("%s%s%d. |cff%s%s|r %s  %s |cff999999(%s)|r", icon, "", i, nameCol, linkName, bar, Short(amount), detail)
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
-- Live bars in a fight (optional: /lazy meter live on)
--------------------------------------------------------------------------------
-- In a fight the game hides the numbers from addons, so the Meter tab can only keep its last picture. A game bar can still be handed
-- a hidden number and draw it, so for the length of a fight a window of real bars sits over the Meter tab. It goes away when the
-- fight ends and the tab shows the full list again. The order is the game's own (highest first): hidden numbers cannot be sorted.
local ROWH = 16
local live
local liveWhy = "not tried yet"

local function LiveFrame()
    if live then return live end
    if not frame then return nil end
    local f = CreateFrame("Frame", "ForeverLazy_MeterLive", frame)
    f:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 4)
    f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -4)
    f:EnableMouse(false)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.04, 0.06, 0.94)
    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.head:SetPoint("TOPLEFT", 6, -3)
    f.bars = {}
    f:Hide()
    live = f
    return f
end

local function LiveRow(f, i)
    local r = f.bars[i]
    if r then return r end
    r = CreateFrame("StatusBar", nil, f)
    r:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    r:SetHeight(ROWH)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -18 - (i - 1) * (ROWH + 1))
    r:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(); r.bg:SetColorTexture(0.2, 0.2, 0.22, 0.8)
    r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.rank:SetPoint("LEFT", 3, 0)
    r.val = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.val:SetPoint("RIGHT", -3, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 18, 0); r.name:SetPoint("RIGHT", r.val, "LEFT", -4, 0)
    r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    f.bars[i] = r
    return r
end

local function HideLive()
    if live then live:Hide() end
end

function addon.MeterLiveOff() HideLive() end

local function LiveOn()
    local db = DB()
    return db and db.meterOn == true and db.meterLive == true
end

local function UpdateLive()
    if not (LiveOn() and inCombat) then HideLive(); return end
    local f = LiveFrame()
    if not f then liveWhy = "no Meter tab or window to sit over"; return end
    local s, err, metric = GetSession()
    if not s or type(s.combatSources) ~= "table" then liveWhy = tostring(err or "no data yet"); HideLive(); return end
    local db = DB()
    local list = s.combatSources
    local fit = math.max(1, math.floor(((f:GetHeight() or 120) - 22) / (ROWH + 1)))
    local n = math.min(#list, fit, math.min(20, math.max(3, tonumber(db.meterRows) or 8)))
    local drawn, failed = 0, 0
    for i = 1, n do
        local src, row = list[i], LiveRow(f, i)
        local ok = pcall(function()
            -- the biggest number sets the bar length: the game's own maximum, else the first player (the list comes highest first)
            row:SetMinMaxValues(0, s.maxAmount or list[1].totalAmount)
            row:SetValue(src.totalAmount)
            row.name:SetText(src.name)
            local text = src.totalAmount
            if _G.AbbreviateNumbers then text = _G.AbbreviateNumbers(src.totalAmount) end
            row.val:SetText(text)
        end)
        if ok then
            -- the class colour, when the class can be read (it can be hidden too)
            local okC = pcall(function()
                local c = RAID_CLASS_COLORS[src.classFilename]
                row:SetStatusBarColor(c.r, c.g, c.b)
            end)
            if not okC then row:SetStatusBarColor(0.35, 0.55, 0.9) end
            row.rank:SetText(tostring(i))
            row:Show()
            drawn = drawn + 1
        else
            failed = failed + 1
            row:Hide()
        end
    end
    for i = n + 1, #f.bars do f.bars[i]:Hide() end
    if drawn == 0 then
        -- nothing could be drawn live on this client: step aside so the tab shows its last picture
        liveWhy = failed > 0 and "this client would not draw the hidden numbers on a bar" or "nobody to show yet"
        HideLive()
        return
    end
    liveWhy = string.format("drawing %d bars (%d could not be drawn)", drawn, failed)
    f.head:SetText((metric and metric.label or "") .. "  |cff888888live|r")
    f:Show()
end

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
        HideLive()
        ForgetPicture()
        if db then
            local name, itype, _, _, _, _, _, instId = GetInstanceInfo and GetInstanceInfo()
            local key = (itype == "party" or itype == "raid") and (tostring(instId or name)) or nil
            if key and key ~= lastInstanceKey and lastInstanceKey ~= nil and db.meterAutoReset ~= false and db.meterOn == true
                and C_DamageMeter and C_DamageMeter.ResetAllCombatSessions and not (InCombatLockdown and InCombatLockdown()) then
                pcall(C_DamageMeter.ResetAllCombatSessions)
                Print(L("meter: new ") .. tostring(name) .. L(", so the meter starts fresh (/lazy meter autoreset off to keep old numbers)"))
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
        if LiveOn() then pcall(UpdateLive) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        HideLive()
        if C_Timer then C_Timer.After(0.6, function() pcall(Refresh) end) end
    elseif db and db.meterOn == true and C_Timer then
        C_Timer.After(0.3, function() pcall(Refresh) end)
        if inCombat then pcall(UpdateLive) end
    end
end)

local acc, liveAcc = 0, 0
ev:SetScript("OnUpdate", function(_, dt)
    liveAcc = liveAcc + dt
    if liveAcc >= 0.25 then liveAcc = 0; if inCombat and LiveOn() then pcall(UpdateLive) end end
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
        Print(usingTab and L("the damage meter is on: look for the Meter tab in your chat window")
            or L("the damage meter is on, in a small window (a chat tab could not be made") .. (problems.tab and (": " .. problems.tab) or "") .. ")")
        Refresh()
    else
        if frame and not usingTab then frame:Hide() end
        if frame and usingTab and frame.Clear then frame:Clear(); frame:AddMessage("|cff888888Forever Lazy meter is off (/lazy meter)|r", 1, 1, 1) end
        Print(L("the damage meter is off"))
    end
    if addon.RefreshOptions then addon.RefreshOptions() end
end

local function Debug()
    local DM = _G.C_DamageMeter
    Print(L("meter debug: C_DamageMeter ") .. (DM and "present" or "MISSING") .. L(", tab frame ") .. (FindTab() and "found" or "not found")
        .. L(", drawing in ") .. (frame and (usingTab and "a chat tab" or "the fallback window") or "nothing yet"))
    if problems.tab then Print(L("  tab problem: ") .. problems.tab) end
    Print(L("  live bars in combat: ") .. (LiveOn() and "on" or "off") .. " (" .. tostring(liveWhy) .. ")")
    local s, err = GetSession()
    if not s then Print(L("  session: ") .. tostring(err)); return end
    local list = s.combatSources
    Print(string.format(L("  session: %d sources, total %s, max %s, duration %s"), type(list) == "table" and #list or -1,
        IsSecret(s.totalAmount) and "hidden" or tostring(s.totalAmount), IsSecret(s.maxAmount) and "hidden" or tostring(s.maxAmount),
        IsSecret(s.durationSeconds) and "hidden" or tostring(s.durationSeconds)))
    if type(list) == "table" and list[1] then
        local a = list[1]
        Print(string.format(L("  first source: name %s, total %s, per second %s, class %s"), IsSecret(a.name) and "hidden" or tostring(a.name),
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
        elseif a == "live on" or a == "live" then db.meterLive = true; Print(L("meter: live bars in a fight are on (a window of bars over the Meter tab while you fight; it goes away when the fight ends)"))
        elseif a == "live off" then db.meterLive = nil; HideLive(); Print(L("meter: live bars in a fight are off"))
        elseif a:match("^autoreset") then
            local v = a:match("^autoreset%s+(%a+)")
            if v == "off" then db.meterAutoReset = false elseif v == "on" then db.meterAutoReset = nil end
            Print(L("meter: a new dungeon or raid ") .. ((db.meterAutoReset == false) and "keeps the old numbers" or "starts the meter fresh") .. L(" (/lazy meter autoreset on|off)"))
        elseif a == "reset" then
            if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then pcall(C_DamageMeter.ResetAllCombatSessions); lastLines = nil; Print(L("the game's damage meter data was cleared")); Refresh()
            else Print(L("this client has no damage meter to reset")) end
        elseif a == "current" or a == "overall" then
            db.meterSegment = a; Print(L("meter: showing ") .. (a == "overall" and "everything since the last reset" or "the current fight")); Refresh()
        elseif METRICS[a] then
            db.meterMetric = a; Print(L("meter: showing ") .. METRICS[a].label:lower()); Refresh()
        elseif a:match("^rows%s*(%d+)$") then
            db.meterRows = tonumber(a:match("^rows%s*(%d+)$")); Print(L("meter: listing ") .. db.meterRows .. L(" players")); Refresh()
        else
            Print(L("/lazy meter on|off|reset|debug|live on|live off, dps|damage|healing|hps|taken|interrupts|dispels|deaths, current|overall, rows <n>"))
        end
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Meter.lua"] = true end end
