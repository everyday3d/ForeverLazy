-- The Coach: what is the best thing to do right now, by measured XP per hour.
-- It compares the options the Hive has numbers for (your own play, and other players' when the Hive is on):
--   quests here      XP of the quests worth doing here, at the speed you really finish quests
--   grind here       the kind of mob that gave the most XP per hour near your level
--   another zone     a zone where you, or other players, earned more
--   /lazy coach      opens the window; each option has a button that sets it up for you
-- It is advice from numbers, not a rule: every option says what it rests on.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local DEFAULT_QUEST_SECS = 420      -- a quest takes about 7 minutes when I have not timed any yet

local function Round(n) return math.floor(n + 0.5) end

--------------------------------------------------------------------------------
-- Working out the options
--------------------------------------------------------------------------------
-- returns: options (best first), my current pace here (or nil)
function addon.CoachOptions()
    local opts = {}
    local zone = GetRealZoneText and GetRealZoneText() or "?"
    local zoneId = hbd:GetPlayerZone()
    local myPace = addon.HivePace and addon.HivePace(zone)

    -- 1. the quests worth doing here
    local hot = addon.XPHotSpots and zoneId and addon.XPHotSpots(zoneId)
    if hot and #hot > 0 then
        local xp, names, count = 0, {}, 0
        for _, p in ipairs(hot) do
            xp = xp + p.xp
            if p.name and not names[p.name] then names[p.name] = true; count = count + 1 end
        end
        if count > 0 and xp > 0 then
            local avg = addon.HiveAvgQuestSecs and addon.HiveAvgQuestSecs()
            local secs = avg or DEFAULT_QUEST_SECS
            opts[#opts + 1] = {
                key = "quests", label = "Do the quests here",
                rate = xp / (count * secs) * 3600,
                detail = string.format("%d quest%s worth about %d XP; %s", count, count == 1 and "" or "s", Round(xp),
                    avg and string.format("you finish one in about %d minutes", Round(avg / 60)) or "a guess of 7 minutes each, I have not timed yours yet"),
                act = function() if addon.PlanRoute then addon:PlanRoute() end end,
                actText = "Plan it",
            }
        end
    end

    -- 2. the best grind here
    local grind = addon.HiveBestGrind and addon.HiveBestGrind(zone)
    local g = grind and grind[1]
    if g then
        local zx, zy
        if addon.HiveKillSpot then zx, zy = addon.HiveKillSpot(zone, g.name) end
        opts[#opts + 1] = {
            key = "grind", label = "Grind " .. g.name,
            rate = g.rate,
            detail = string.format("%d XP a kill, %d kills seen near your level", Round(g.per), g.n),
            act = function()
                if zx and zoneId then
                    addon:AddWaypointZone(zoneId, zx, zy, "Grind: " .. g.name)
                    Print("arrow set on where you killed " .. g.name .. " most")
                else
                    Print("I have not seen where you killed " .. g.name .. " yet; look for it around here")
                end
            end,
            actText = zx and "Take me there" or "Show me",
        }
    end

    -- 3. a zone where I, or other players, earned more
    local segs = addon.JourneySegments and addon.JourneySegments() or {}
    local function hubOf(name)
        for _, s in ipairs(segs) do if s.zone == name and s.map then return s end end
    end
    local bestZone, bestPace = nil, nil
    if addon.HiveBestZone then bestZone, bestPace = addon.HiveBestZone() end
    if bestZone and bestZone ~= zone and bestPace then
        local hub = hubOf(bestZone)
        opts[#opts + 1] = {
            key = "zone", label = "Go back to " .. bestZone,
            rate = bestPace,
            detail = "your own pace there, measured while you played",
            act = function()
                if hub and addon.GoTo then addon.GoTo(hub.map, hub.zx, hub.zy, hub.zone) else Print("open the guide (/lazy guide) to be taken there") end
            end,
            actText = "Take me there",
        }
    end
    local level = UnitLevel("player") or 1
    local theirsZone, theirsPace
    for _, s in ipairs(segs) do
        if s.zone ~= zone and s.zone ~= bestZone and level >= s.from - 1 and level < s.to and addon.HiveCommunityPace then
            local p = addon.HiveCommunityPace(s.zone)
            if p and (not theirsPace or p > theirsPace) then theirsZone, theirsPace = s.zone, p end
        end
    end
    if theirsZone then
        local hub = hubOf(theirsZone)
        opts[#opts + 1] = {
            key = "community", label = "Try " .. theirsZone,
            rate = theirsPace,
            detail = "what other players typically earn there at your level",
            act = function()
                if hub and addon.GoTo then addon.GoTo(hub.map, hub.zx, hub.zy, hub.zone) end
            end,
            actText = "Take me there",
        }
    end

    table.sort(opts, function(a, b) return a.rate > b.rate end)
    return opts, myPace
end

-- one line for other windows: the best option and its rate, or nil
function addon.CoachBest()
    local ok, opts = pcall(addon.CoachOptions)
    if not ok or not opts or not opts[1] then return nil end
    local o = opts[1]
    return string.format("%s (about %d XP per hour)", o.label, Round(o.rate))
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local win, rows = nil, {}

local function Refresh()
    if not win then return end
    local scale = math.min(2.6, math.max(0.8, tonumber(DB().guideScale) or 1))
    win:SetScale(scale)
    local opts, myPace = addon.CoachOptions()
    local head
    if myPace then
        head = string.format("You have been earning about %d XP per hour here.", Round(myPace))
    else
        head = "I have not measured your pace in this zone yet (turn the Hive on and play for a few minutes)."
    end
    if not (DB() and DB().hiveOn) then head = head .. "\nThe Hive is off, so these come from the quest data and what is already stored." end
    win.head:SetText(head)
    local y = 0
    for i = 1, 4 do
        local o = opts[i]
        local r = rows[i]
        if not r then
            r = {}
            r.title = win.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            r.title:SetJustifyH("LEFT")
            r.detail = win.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.detail:SetJustifyH("LEFT")
            r.btn = CreateFrame("Button", nil, win.content, "UIPanelButtonTemplate")
            r.btn:SetSize(130, 22)
            rows[i] = r
        end
        if o then
            local colour = (i == 1) and "|cff55ff55" or "|cffffffff"
            r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -y)
            r.title:SetWidth(430)
            r.title:SetText(string.format("%s%d. %s: about %d XP per hour|r", colour, i, o.label, Round(o.rate)))
            r.title:Show()
            y = y + 26
            r.detail:ClearAllPoints(); r.detail:SetPoint("TOPLEFT", win.content, "TOPLEFT", 8, -y)
            r.detail:SetWidth(420)
            r.detail:SetText(o.detail)
            r.detail:Show()
            y = y + math.max(16, r.detail:GetStringHeight()) + 6
            r.btn:ClearAllPoints(); r.btn:SetPoint("TOPLEFT", win.content, "TOPLEFT", 8, -y)
            r.btn:SetText(o.actText or "Do it")
            r.btn:SetScript("OnClick", function() win:Hide(); pcall(o.act) end)
            r.btn:Show()
            y = y + 36
        else
            r.title:Hide(); r.detail:Hide(); r.btn:Hide()
        end
    end
    if not opts[1] then
        win.empty:Show()
    else
        win.empty:Hide()
    end
    win.content:SetHeight(math.max(y, 40))
end

local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_Coach", UIParent)
    f:SetSize(500, 440)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetText("The Coach")
    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.head:SetPoint("TOPLEFT", 16, -46); f.head:SetWidth(468); f.head:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local scroll = CreateFrame("ScrollFrame", "ForeverLazy_CoachScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -96); scroll:SetPoint("BOTTOMRIGHT", -34, 52)
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(440, 10)
    scroll:SetScrollChild(f.content)
    f.empty = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("TOPLEFT", 0, 0); f.empty:SetWidth(430); f.empty:SetJustifyH("LEFT")
    f.empty:SetText("I have nothing to compare yet. Turn the Hive on (Options > The Hive), play for a while, and come back: I need your pace, your kills and your quest times.")
    local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refresh:SetSize(100, 24); refresh:SetText("Refresh"); refresh:SetPoint("BOTTOMLEFT", 16, 14)
    refresh:SetScript("OnClick", Refresh)
    local note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("LEFT", refresh, "RIGHT", 10, 0); note:SetWidth(330); note:SetJustifyH("LEFT")
    note:SetText("Advice from measured numbers. Each line says what it rests on.")
    table.insert(UISpecialFrames, "ForeverLazy_Coach")
    f:SetScript("OnShow", Refresh)
    f:Hide()
    return f
end

local function Toggle()
    if not win then win = Build() end
    if win:IsShown() then win:Hide() else win:Show() end
end
addon.ToggleCoach = Toggle

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "coach" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "say" or a == "text" then
            local opts = addon.CoachOptions()
            if not opts[1] then Print("coach: nothing to compare yet (turn the Hive on and play a while)"); return true end
            for i = 1, math.min(3, #opts) do
                Print(string.format("coach %d. %s: about %d XP per hour (%s)", i, opts[i].label, Round(opts[i].rate), opts[i].detail))
            end
        else
            Toggle()
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Coach.lua"] = true end end
