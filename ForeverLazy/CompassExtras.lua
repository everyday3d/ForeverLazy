-- Extras for the compass bar: direction letters, the distance under each marker, icons that say what a marker is (each off until
-- ticked, options, Compass), and a tooltip when the mouse is over a marker. The bar itself is made in Extras.lua, which calls
-- addon.CompassDraw after placing the markers. The compass is its own thing: it has its own switch, hiding rules, size and lock,
-- and nothing about the arrows changes it.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon

local function DB() return addon.GetDB() end

local ICON = {
    kill = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    give = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
}
-- my body is a tombstone (our own drawing, tools/build_tombstone.lua)
local TOMBSTONE = "Interface\\AddOns\\ForeverLazy\\media\\tombstone.tga"
-- facing is measured as the game does it: 0 is north and it grows to the left (west is a quarter turn)
local DIRECTIONS = { { "N", 0 }, { "W", math.pi / 2 }, { "S", math.pi }, { "E", 3 * math.pi / 2 } }
local CLOSE = 12          -- markers this near each other on the bar share a tooltip
local LABEL_ROOM = 40     -- a distance is left out when another one is written this near

--------------------------------------------------------------------------------
-- The rules (no game needed: tests/compass.lua)
--------------------------------------------------------------------------------
-- where on the bar something at this bearing goes: pixels from the middle, or nil when it is behind me
function addon.CompassOffset(bearing, facing, half)
    local rel = (bearing - facing + math.pi) % (2 * math.pi) - math.pi
    if math.abs(rel) > math.pi / 2 + 0.0001 then return nil end
    return -rel / (math.pi / 2) * half
end

local function Clean(label)
    return (tostring(label or ""):gsub("^%d+%.%s*", ""))
end

-- which icon a target gets: "turnin", "give", "kill" (kill or collect) or nil (not a quest: it stays a coloured block)
function addon.CompassKind(name, quests)
    local labels = {}
    for _, q in ipairs(quests or {}) do labels[#labels + 1] = Clean(q.label) end
    if #labels == 0 then labels[1] = Clean(name) end
    local turnin, give = true, true
    for _, l in ipairs(labels) do
        if not l:find("^Turn in:") then turnin = false end
        if not (l:find("^Pick up:") or l:find("^Accept") or l:find("^Class quest:")) then give = false end
    end
    if turnin then return "turnin" end
    if give then return "give" end
    if quests and #quests > 0 then return "kill" end
    return nil
end

-- a stop made for a quest I picked carries only that quest's number: its icon comes from whether the quest is finished
local function PickedKind(wp)
    local id = wp and wp.focusId
    if not (id and C_QuestLog and C_QuestLog.IsComplete) then return nil end
    local ok, done = pcall(C_QuestLog.IsComplete, id)
    return (ok and done) and "turnin" or "kill"
end

function addon.CompassDistance(yards, units)
    if units == "steps" then return string.format("%d st", math.floor(yards / 0.8 + 0.001)) end
    local d = units == "m" and yards * 0.9144 or yards
    local mark = units == "m" and "m" or "yd"
    if d >= 1000 then return string.format("%.1fk %s", d / 1000, mark) end
    return string.format("%d %s", math.floor(d), mark)
end

-- the tooltip's lines for one marker's information: { who =, name =, wp =, yards = }
function addon.CompassLines(info, units)
    local lines = {}
    local quests = info.wp and info.wp.quests
    if quests and #quests > 1 then
        for _, q in ipairs(quests) do lines[#lines + 1] = Clean(q.label) end
    else
        lines[1] = Clean(info.name or (quests and quests[1] and quests[1].label) or "?")
    end
    local foot = {}
    if info.who then foot[#foot + 1] = L(info.who) end
    if info.yards then foot[#foot + 1] = addon.CompassDistance(info.yards, units) end
    if #foot > 0 then lines[#lines + 1] = table.concat(foot, "  -  ") end
    return lines
end

--------------------------------------------------------------------------------
-- The compass's own settings
--------------------------------------------------------------------------------
-- the compass used to follow the arrows' settings: the first time, it takes them over as they are, so nothing changes by itself
local function Own()
    local db = DB()
    if not db then return nil end
    if not db.compassSplit then
        db.compassSplit = true
        db.compassHideCombat = db.hideCombat == true
        db.compassHideResting = db.hideResting == true
        db.compassHideTaxi = db.hideTaxi == true
        db.compassHideInstance = db.hideInstance ~= false
        db.compassLocked = db.locked == true
        if db.mode == "off" then db.compassBar = false end      -- it was hidden along with the arrows
    end
    return db
end
addon.CompassSettings = Own

function addon.CompassHidden()
    local db = Own()
    if not db then return true end
    -- as a ghost it shows the way to my body, whatever would hide it while I am alive
    if UnitIsGhost and UnitIsGhost("player") then return false end
    if db.compassHideInstance and IsInInstance then
        local inside, kind = IsInInstance()
        if inside and (kind == "party" or kind == "raid") then return true end
    end
    if db.compassHideCombat and UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    if db.compassHideResting and IsResting and IsResting() then return true end
    if db.compassHideTaxi and UnitOnTaxi and UnitOnTaxi("player") then return true end
    return false
end

function addon.CompassLocked()
    local db = Own()
    return db ~= nil and db.compassLocked == true
end

function addon.CompassScale()
    local db = Own()
    return math.max(0.6, math.min(2, tonumber(db and db.compassScale) or 1))
end

-- right-click on the bar: the compass's own menu
function addon.CompassMenu()
    local db = Own()
    if not (db and addon.ShowMenu) then return end
    local function Switch(text, key)
        return { text = (db[key] == true and "|cff55ff55on|r   " or "off  ") .. L(text), fn = function()
            db[key] = db[key] ~= true
            if addon.RefreshOptions then addon.RefreshOptions() end
        end }
    end
    addon.ShowMenu({
        Switch("Directions (N, E, S, W)", "compassDirections"),
        Switch("Distance under the markers", "compassDistance"),
        Switch("Quest icons", "compassIcons"),
        Switch("Next stop in words", "compassText"),
        { text = (db.waypointArrowOff == false and "|cff55ff55on|r   " or "off  ") .. L("Main arrow"), fn = function()
            db.waypointArrowOff = db.waypointArrowOff == false          -- shown only when this is false
            if addon.RefreshOptions then addon.RefreshOptions() end
        end },
        Switch("Lock the compass", "compassLocked"),
        { text = L("Hide the compass"), fn = function()
            db.compassBar = false
            if addon.RefreshOptions then addon.RefreshOptions() end
            if addon.Print then addon.Print(L("compass bar off. /lazy compass brings it back.")) end
        end },
        { text = L("All the options"), fn = function() db.optPage = "Compass"; if addon.OpenOptions then addon:OpenOptions() end end },
    }, L("Compass"))
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
local function Clicked(_, button)
    if button == "RightButton" then addon.CompassMenu() end
end

local function ShowTip(bar, marker)
    if not GameTooltip then return end
    GameTooltip:SetOwner(marker, "ANCHOR_BOTTOM", 0, -14)
    local first = true
    for _, other in ipairs(bar.drawn or {}) do
        if math.abs(other.offset - (marker.offset or 0)) <= CLOSE and other.info then
            if not first then GameTooltip:AddLine(" ") end
            for i, line in ipairs(addon.CompassLines(other.info, DB().units)) do
                if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1) end
            end
            first = false
        end
    end
    if first then GameTooltip:Hide() else GameTooltip:Show() end
end

local function Prepare(bar, m)
    if m.ready then return end
    m.ready = true
    m.dist = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.dist:SetPoint("TOP", m, "BOTTOM", 0, -1)
    m:EnableMouse(true)
    m:SetScript("OnEnter", function(self) bar.hover = self; ShowTip(bar, self) end)
    m:SetScript("OnLeave", function() bar.hover = nil; if GameTooltip then GameTooltip:Hide() end end)
    m:SetScript("OnMouseUp", Clicked)
    -- a marker must not stop the bar being dragged
    m:RegisterForDrag("LeftButton")
    for _, what in ipairs({ "OnDragStart", "OnDragStop" }) do
        m:SetScript(what, function() local fn = bar:GetScript(what); if fn then fn(bar) end end)
    end
end

local function Directions(bar, facing, half)
    local on = DB().compassDirections == true and facing ~= nil
    if not bar.letters then
        if not on then return end
        bar.letters = {}
        for i, d in ipairs(DIRECTIONS) do
            local fs = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            fs:SetText(d[1])
            if d[1] == "N" then fs:SetTextColor(1, 0.35, 0.3) else fs:SetTextColor(0.85, 0.85, 0.85) end
            bar.letters[i] = fs
        end
    end
    for i, d in ipairs(DIRECTIONS) do
        local fs = bar.letters[i]
        local x = on and addon.CompassOffset(d[2], facing, half)
        if x then
            fs:ClearAllPoints(); fs:SetPoint("CENTER", bar, "CENTER", x, 0); fs:Show()
        else
            fs:Hide()
        end
    end
end

-- the words under the bar: what the next stop is and what to do there (off until ticked), for those who hide the arrow.
-- The two lines for a target: its name, and what to do with the distance after it
function addon.CompassTargetLines(wp, yards, units)
    local name = tostring(wp.name or wp.label or "")
    local detail = wp.detail
    if addon.WaypointDetail then
        local ok, d = pcall(addon.WaypointDetail, wp)
        if ok and d then detail = d end
    end
    local foot = {}
    if detail and detail ~= "" then foot[#foot + 1] = tostring(detail) end
    if yards then foot[#foot + 1] = addon.CompassDistance(yards, units) end
    return name, table.concat(foot, "  -  ")
end

-- my body, as the compass wants it: the marker (a tombstone), and the same spot for the words under the bar
function addon.CompassBody(inst, x, y, label)
    local name = label or L("Your corpse")
    return {
        source = { inst, x, y, { 1, 1, 1 }, nil, nil, { who = "Your body", name = name, kind = "corpse" } },
        stop = { instance = inst, x = x, y = y, name = name },
    }
end

function addon.CompassTargetText(bar, wp, px, py, pinst)
    local db = DB()
    if not (db.compassText == true and wp) then
        if bar.target then bar.target:Hide() end
        return
    end
    if not bar.target then
        bar.target = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        -- below the row the distances use
        bar.target:SetPoint("TOP", bar, "BOTTOM", 0, -17)
        bar.target:SetWidth(420)
        bar.target:SetJustifyH("CENTER")
        bar.target:SetShadowOffset(1, -1)
    end
    local yards = (px and pinst == wp.instance) and math.sqrt((wp.x - px) ^ 2 + (wp.y - py) ^ 2) or nil
    local name, foot = addon.CompassTargetLines(wp, yards, db.units)
    if ns.LocalizeLabel then name = ns.LocalizeLabel(name) end
    bar.target:SetText("|cffffd100" .. name .. "|r" .. (foot ~= "" and ("\n" .. foot) or ""))
    bar.target:Show()
end

-- drawn: the markers on the bar now, most important first: { { marker =, source =, offset = }, ... }
-- a source is { instance, x, y, colour, letter, raid icon, { who =, name =, wp = } }
function addon.CompassDraw(bar, drawn, facing, px, py)
    local db = DB()
    local half = bar:GetWidth() / 2 - 8
    if not bar.menuReady then bar.menuReady = true; bar:SetScript("OnMouseUp", Clicked) end
    Directions(bar, facing, half)
    local list, written = {}, {}
    for _, d in ipairs(drawn) do
        local m, s = d.marker, d.source
        Prepare(bar, m)
        local info = s[7]
        local yards = (px and s[2]) and math.sqrt((s[2] - px) ^ 2 + (s[3] - py) ^ 2) or nil
        m.offset = d.offset
        list[#list + 1] = { offset = d.offset, info = info and { who = info.who, name = info.name, wp = info.wp, yards = yards } or nil }
        -- icons: only on markers that are not already a person or a letter
        local kind = info and not s[5] and not s[6] and db.compassIcons == true
            and (PickedKind(info.wp) or addon.CompassKind(info.name, info.wp and info.wp.quests) or info.kind)
        if kind and ICON[kind] then
            m.tex:SetColorTexture(0, 0, 0, 0)
            m.icon:SetTexture(ICON[kind])
            m.icon:SetTexCoord(0, 1, 0, 1)
            m.icon:Show()
            m:SetSize(16, 18)
        end
        -- the tombstone does not wait for the icons option: it is the only thing on the bar then
        if info and info.kind == "corpse" then
            m.tex:SetColorTexture(0, 0, 0, 0)
            m.icon:SetTexture(TOMBSTONE)
            m.icon:SetTexCoord(0, 1, 0, 1)
            m.icon:Show()
            m:SetSize(18, 18)
        end
        local text = ""
        if (db.compassDistance == true or (info and info.kind == "corpse")) and yards then
            local room = true
            for _, x in ipairs(written) do if math.abs(x - d.offset) < LABEL_ROOM then room = false end end
            if room then
                written[#written + 1] = d.offset
                text = addon.CompassDistance(yards, db.units)
            end
        end
        m.dist:SetText(text)
    end
    bar.drawn = list
    -- the markers move as I turn: keep the tooltip right, and drop it when its marker has gone
    if bar.hover then
        local still = false
        for _, d in ipairs(drawn) do if d.marker == bar.hover then still = true end end
        if still then ShowTip(bar, bar.hover) else bar.hover = nil; if GameTooltip then GameTooltip:Hide() end end
    end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["CompassExtras.lua"] = true end end
