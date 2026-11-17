-- The levelling guide: your journey from now to 60 in one window, with where you are, what is worth doing,
-- the dungeons that fit, and a button to take you to each stretch.
--   /lazy guide             open or close it
--   /lazy guide bigger      bigger text (also: smaller, tv, normal)
-- The whole window scales, so it can be made big enough to read from the couch on a TV.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function DB() return addon.GetDB() end

local SCALE_MIN, SCALE_MAX, SCALE_TV = 0.8, 2.6, 1.8
local W, H = 540, 620

local function Run(cmd, rest)
    local ok, err = pcall(addon.HandleExtraCommand, addon, cmd, rest)
    if not ok then Print("error in /" .. cmd .. ": " .. tostring(err)) end
end

local function GetScale()
    local s = tonumber(DB().guideScale) or 1
    return math.min(SCALE_MAX, math.max(SCALE_MIN, s))
end

local win, rows = nil, {}

--------------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------------
local function Colour(status)
    if status == "done" then return "|cff888888" end
    if status == "now" then return "|cff55ff55" end
    return "|cffffffff"
end

local function Describe(seg, status, level)
    local parts = {}
    if status == "done" then
        parts[#parts + 1] = "|cff888888Finished.|r"
    else
        -- what is worth doing there right now, from Questie
        if seg.map and addon.XPHotSpots then
            local hot = addon.XPHotSpots(seg.map)
            if hot and #hot > 0 then
                local sum = 0
                for _, p in ipairs(hot) do sum = sum + p.xp end
                parts[#parts + 1] = string.format("Quests worth doing right now: %d, about %d XP.", #hot, sum)
            end
        end
        if addon.HivePace then
            local pace = addon.HivePace(seg.zone)
            if pace then
                local bz = addon.HiveBestZone and addon.HiveBestZone()
                parts[#parts + 1] = string.format("Your measured pace here: about %d XP per hour.%s", pace, bz == seg.zone and " Your fastest zone lately." or "")
            end
        end
        if addon.HiveBestGrind then
            local best = addon.HiveBestGrind(seg.zone)[1]
            if best then
                parts[#parts + 1] = string.format("Best grind here for your level: %s (about %d XP per hour).", best.name, best.rate)
            end
        end
        if addon.HiveCommunityPace then
            local typical = addon.HiveCommunityPace(seg.zone)
            if typical then parts[#parts + 1] = string.format("Other players typically get about %d XP per hour here.", typical) end
        end
        if seg.dungeons and #seg.dungeons > 0 then
            local lv = api.DungeonLevels or {}
            local names = {}
            for i = 1, math.min(#seg.dungeons, 3) do
                local n = seg.dungeons[i]
                local r = lv[n]
                names[#names + 1] = r and string.format("%s (%d-%d)", n, r[1], r[2]) or n
            end
            parts[#parts + 1] = "Dungeons that fit: " .. table.concat(names, ", ") .. "."
        end
        if status == "now" then
            local left = seg.to - level
            parts[#parts + 1] = string.format("%d level%s to go before the next stretch.", left, left == 1 and "" or "s")
        end
    end
    if #parts == 0 then parts[1] = "|cffaaaaaaNothing more to say about this one yet.|r" end
    return table.concat(parts, "\n")
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = {}
    r.header = win.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.header:SetJustifyH("LEFT")
    r.detail = win.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.detail:SetJustifyH("LEFT"); r.detail:SetJustifyV("TOP")
    r.go = CreateFrame("Button", nil, win.content, "UIPanelButtonTemplate")
    r.go:SetSize(130, 22); r.go:SetText("Take me there")
    r.plan = CreateFrame("Button", nil, win.content, "UIPanelButtonTemplate")
    r.plan:SetSize(130, 22); r.plan:SetText("Plan this zone")
    rows[i] = r
    return r
end

local function Refresh()
    if not win then return end
    local segs = addon.JourneySegments and addon.JourneySegments()
    local level = UnitLevel("player") or 1
    win:SetScale(GetScale())
    win.scaleText:SetText(string.format("Text size %d%%", math.floor(GetScale() * 100 + 0.5)))

    -- the top line
    local even = (level % 2 == 0) and level or level + 1
    local head = string.format("You are level %d.  Class trainer: every even level (next at %d).", level, even)
    -- how fast I really level, measured from my own play (the hive)
    if addon.HiveTimeToLevel then
        local mins, pace = addon.HiveTimeToLevel()
        if mins then
            local when = mins >= 120 and string.format("%.1f hours", mins / 60) or string.format("%d minutes", math.floor(mins + 0.5))
            head = head .. string.format("\nYour pace: about %d XP per hour, so about %s to level %d.", pace, when, level + 1)
        end
    end
    local bestZone, bestPace, hereZone, herePace
    if addon.HiveBestZone then bestZone, bestPace, hereZone, herePace = addon.HiveBestZone() end
    if bestZone and bestPace then
        head = head .. string.format("\nFastest zone for you lately: %s (about %d XP per hour).", bestZone, bestPace)
        if hereZone and bestZone ~= hereZone and herePace and herePace < bestPace * 0.7 then
            head = head .. string.format(" You are earning about %d here.", herePace)
        end
    end
    if addon.CoachBest then
        local best = addon.CoachBest()
        if best then head = head .. "\nCoach says: " .. best .. "  (/lazy coach)" end
    end
    win.head:SetText(head)

    local width = W - 70
    local y = 0
    if not segs or #segs == 0 then
        for _, r in ipairs(rows) do r.header:Hide(); r.detail:Hide(); r.go:Hide(); r.plan:Hide() end
        win.empty:Show()
        win.content:SetHeight(60)
        return
    end
    win.empty:Hide()
    for i, seg in ipairs(segs) do
        local status = (level >= seg.to) and "done" or ((level >= seg.from) and "now" or "next")
        local r = Row(i)
        r.header:ClearAllPoints()
        r.header:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -y)
        r.header:SetWidth(width)
        r.header:SetText(string.format("%s%d. Level %d-%d: %s%s|r", Colour(status), i, seg.from, seg.to, seg.zone,
            status == "now" and "   <- you are here" or ""))
        r.header:Show()
        y = y + 26
        r.detail:ClearAllPoints()
        r.detail:SetPoint("TOPLEFT", win.content, "TOPLEFT", 8, -y)
        r.detail:SetWidth(width - 8)
        r.detail:SetText(Describe(seg, status, level))
        r.detail:Show()
        y = y + math.max(18, r.detail:GetStringHeight()) + 6
        if status ~= "done" then
            r.go:ClearAllPoints()
            r.go:SetPoint("TOPLEFT", win.content, "TOPLEFT", 8, -y)
            r.go:SetScript("OnClick", function()
                if addon.GoTo and seg.map and addon.ModuleOn("go") then addon.GoTo(seg.map, seg.zx, seg.zy, seg.zone)
                else Run("journey", "go " .. i) end
            end)
            r.go:Show()
            if status == "now" then
                r.plan:ClearAllPoints()
                r.plan:SetPoint("LEFT", r.go, "RIGHT", 8, 0)
                r.plan:SetScript("OnClick", function() if addon.PlanRoute then addon:PlanRoute() end end)
                r.plan:Show()
            else
                r.plan:Hide()
            end
            y = y + 30
        else
            r.go:Hide(); r.plan:Hide()
        end
        y = y + 14
    end
    for i = #segs + 1, #rows do
        rows[i].header:Hide(); rows[i].detail:Hide(); rows[i].go:Hide(); rows[i].plan:Hide()
    end
    win.content:SetHeight(y + 10)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local function SetScaleTo(s)
    DB().guideScale = math.min(SCALE_MAX, math.max(SCALE_MIN, s))
    Refresh()
end

local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_Guide", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetText("Levelling guide")
    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.head:SetPoint("TOPLEFT", 16, -44)
    f.head:SetWidth(W - 32); f.head:SetJustifyH("LEFT")

    -- text size: the whole window scales, so it works on a TV across the room
    local smaller = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    smaller:SetSize(34, 22); smaller:SetText("A-"); smaller:SetPoint("TOPRIGHT", -70, -14)
    smaller:SetScript("OnClick", function() SetScaleTo(GetScale() - 0.2) end)
    local bigger = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    bigger:SetSize(34, 22); bigger:SetText("A+"); bigger:SetPoint("LEFT", smaller, "RIGHT", 2, 0)
    bigger:SetScript("OnClick", function() SetScaleTo(GetScale() + 0.2) end)
    local tv = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tv:SetSize(40, 22); tv:SetText("TV"); tv:SetPoint("RIGHT", smaller, "LEFT", -2, 0)
    tv:SetScript("OnClick", function() SetScaleTo(SCALE_TV) end)
    tv:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Big text for the couch and TV")
        GameTooltip:Show()
    end)
    tv:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.scaleText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.scaleText:SetPoint("TOPRIGHT", smaller, "BOTTOMRIGHT", 40, -2)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local scroll = CreateFrame("ScrollFrame", "ForeverLazy_GuideScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -80); scroll:SetPoint("BOTTOMRIGHT", -34, 56)
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(W - 70, 10)
    scroll:SetScrollChild(f.content)
    f.empty = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("TOPLEFT", 0, 0); f.empty:SetWidth(W - 70); f.empty:SetJustifyH("LEFT")
    f.empty:SetText("There is no journey yet. Click Rebuild to make one from your level, or wait until the game has loaded the zone data.")

    local now = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    now:SetSize(150, 26); now:SetText("Do the next thing"); now:SetPoint("BOTTOMLEFT", 16, 16)
    now:SetScript("OnClick", function() Run("now") end)
    local rebuild = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rebuild:SetSize(100, 26); rebuild:SetText("Rebuild"); rebuild:SetPoint("LEFT", now, "RIGHT", 6, 0)
    rebuild:SetScript("OnClick", function() Run("journey", "regenerate"); Refresh() end)
    local heat = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    heat:SetSize(120, 26); heat:SetText("XP hot spots"); heat:SetPoint("LEFT", rebuild, "RIGHT", 6, 0)
    heat:SetScript("OnClick", function() Run("xpmap") end)

    table.insert(UISpecialFrames, "ForeverLazy_Guide")
    f:SetScript("OnShow", Refresh)
    f:Hide()
    return f
end

local function Toggle()
    if not win then win = Build() end
    if win:IsShown() then win:Hide() else win:Show(); Refresh() end
end
addon.ToggleGuide = Toggle

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function() if win and win:IsShown() then Refresh() end end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "guide" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "bigger" or a == "larger" or a == "+" then
            SetScaleTo(GetScale() + 0.2); Print(string.format("guide text size %d%%", math.floor(GetScale() * 100 + 0.5)))
        elseif a == "smaller" or a == "-" then
            SetScaleTo(GetScale() - 0.2); Print(string.format("guide text size %d%%", math.floor(GetScale() * 100 + 0.5)))
        elseif a == "tv" or a == "couch" then
            SetScaleTo(SCALE_TV); Print("guide text size set for the TV")
        elseif a == "normal" or a == "reset" then
            SetScaleTo(1); Print("guide text size back to normal")
        else
            Toggle()
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Guide.lua"] = true end end
