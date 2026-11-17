-- Library book collection (WoW Forever): every known book location as waypoints.
-- Source: Wowhead "Collecting Library Books: Locations and Rewards" (updated 2026/11/13).
--   /lazy books          all books, nearest first
--   /lazy books zone     only books in the zone you are in
--   /lazy books turnin   waypoint to your faction's librarian
--   /lazy books list     show the book list
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local hbd = api.hbd
local Print = addon.Print

local function DB() return addon.GetDB() end

-- { zone, uiMapId, x, y, book name }   (* = from the Mage Rune guide)
local BOOKS = {
    { "Alterac Mountains",   1416, 48.4, 57.6, "Defensive Magics 101" },
    { "Arathi Highlands",    1417, 73.6, 65.2, "A Web of Lies: Debunking Myths and Legends" },
    { "Azshara",             1447, 20.7, 62.0, "Everyday Etiquette" },
    { "Badlands",            1418, 56.7, 39.9, "Mummies: A Guide to the Unsavory Undead" },
    { "The Barrens",         1413, 56.3,  8.8, "Arcanic Systems Manual" },
    { "The Barrens",         1413, 62.7, 36.3, "Baxtan: On Destructive Magics" },
    { "The Barrens",         1413, 46.0, 36.5, "Secrets of the Dreamers" },
    { "Blasted Lands",       1419, 55.4, 32.2, "Conjurer's Codex" },
    { "Burning Steppes",     1428, 29.0, 28.9, "Stonewrought Design" },
    { "Burning Steppes",     1428, 29.6, 28.2, "Magma or Lava?" },
    { "Darkshore",           1439, 59.6, 22.2, "Nar'thalas Almanac, Vol. 74" },
    { "Desolace",            1443, 55.1, 26.2, "Demons and You" },
    { "Duskwood",            1431, 16.6, 28.5, "Crimes Against Anatomy" },
    { "Dustwallow Marsh",    1445, 57.2, 20.8, "RwlRwlRwlRwl!" },
    { "Eastern Plaguelands", 1423, 71.8, 48.2, "A Study of the Light" },
    { "Eastern Plaguelands", 1423, 31.3, 21.0, "Scourge: Undead Menace or Misunderstood?*" },
    { "Eastern Plaguelands", 1423, 47.3, 42.3, "The Knight and the Lady" },
    { "Elwynn Forest",       1429, 65.4, 70.1, "Archmage Theocritus' Research Journal" },
    { "Felwood",             1448, 65.2,  3.3, "Northern Kalimdor - A Comprehensive Guide* (inside Timbermaw Hold)" },
    { "Feralas",             1444, 50.6, 15.7, "The Liminal and the Arcane*" },
    { "The Hinterlands",     1425, 36.0, 72.8, "Venomous Journeys" },
    { "Ironforge",           1455, 75.7, 10.5, "Archmage Antonidas: The Unabridged Autobiography" },
    { "Loch Modan",          1432, 77.4, 14.0, "Runes of the Sorcerer-Kings" },
    { "Orgrimmar",           1454, 38.7, 78.4, "The Lessons of Ta'zo*" },
    { "Searing Gorge",       1427, 37.8, 49.3, "A Mind of Metal" },
    { "Silverpine Forest",   1421, 43.4, 41.2, "Ataeric: On Arcane Curiosities*" },
    { "Silverpine Forest",   1421, 63.5, 63.1, "The Dalaran Digest, Vol. 23" },
    { "Stonetalon Mountains",1442, 74.4, 85.7, "Fury of the Land" },
    { "Stranglethorn Vale",  1434, 41.4, 50.9, "Basilisks: Should Petrification be Feared?" },
    { "Swamp of Sorrows",    1435, 61.4, 22.4, "A Luddite's Guide to Caring for Your Demonic Pet*" },
    { "Swamp of Sorrows",    1435, 70.0, 51.0, "Sanguine Sorcery" },
    { "Tanaris",             1446, 72.7, 47.8, "Legends of the Tidesages" },
    { "Thousand Needles",    1441, 34.4, 40.1, "Geomancy: The Stone-Cold Truth" },
    { "Tirisfal Glades",     1420, 59.4, 52.3, "The Apothecary's Metaphysical Primer" },
    { "Western Plaguelands", 1422, 69.4, 72.8, "Necromancy 101*" },
    { "Western Plaguelands", 1422, 38.3, 54.6, "Undead Potatoes*" },
    { "Westfall",            1436, 45.4, 70.5, "Bewitchments and Glamours" },
    { "Westfall",            1436, 52.7, 53.8, "Rumi of Gnomeregan: The Collected Works" },
    { "Wetlands",            1437, 33.6, 47.9, "Goaz Scrolls" },
    { "Winterspring",        1452, 60.7, 37.7, "Ka-Boom!*" },
}

local LIBRARIANS = {
    Alliance = { "Stormwind City", 1453, 49.0, 86.4, "Librarian Garion Wendell (Mage Tower)" },
    Horde    = { "Undercity",      1458, 74.0, 32.4, "Librarian Owen Thadd (Magic Quarter)" },
}

-- The map id table above is from memory, so check the name and search if it is wrong.
local mapCache = {}
local function ResolveMap(zone, guess)
    if mapCache[zone] ~= nil then return mapCache[zone] or nil end
    local function nameOf(id)
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        return info and info.name
    end
    local found
    if nameOf(guess) == zone then
        found = guess
    else
        for id = 1400, 1500 do
            if nameOf(id) == zone then found = id; break end
        end
    end
    mapCache[zone] = found or false
    return found
end

-- plain book title: no "*" marker and no "(inside ...)" note
local function BookKey(e)
    local s = e[5]:gsub("%s*%b()", ""):gsub("%*", "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Entry(e)
    local mapId = ResolveMap(e[1], e[2])
    if not mapId then return nil end
    local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(e[3] / 100, e[4] / 100, mapId)
    if not wx then return nil end
    return { name = e[5] .. " (" .. e[1] .. ")", instance = inst, x = wx, y = wy,
             uiMapId = mapId, zx = e[3] / 100, zy = e[4] / 100, book = BookKey(e) }
end

--------------------------------------------------------------------------------
-- Which books I already have (kept per character)
--------------------------------------------------------------------------------
local function DoneTable()
    local root = addon.GetRoot()
    root.booksDone = root.booksDone or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    root.booksDone[key] = root.booksDone[key] or {}
    return root.booksDone[key]
end

local function IsDone(e) return DoneTable()[BookKey(e)] == true end

local RefreshBookPins   -- defined below

local function SetDone(e, value)
    DoneTable()[BookKey(e)] = value or nil
    if RefreshBookPins then RefreshBookPins() end
end

local function CountDone()
    local n = 0
    for _, e in ipairs(BOOKS) do if IsDone(e) then n = n + 1 end end
    return n
end

-- rough lowest level of each zone, used to leave out zones that are too dangerous
local ZONE_MIN = {
    ["Alterac Mountains"] = 30, ["Arathi Highlands"] = 30, ["Azshara"] = 45, ["Badlands"] = 35,
    ["The Barrens"] = 10, ["Blasted Lands"] = 45, ["Burning Steppes"] = 50, ["Darkshore"] = 10,
    ["Desolace"] = 30, ["Duskwood"] = 18, ["Dustwallow Marsh"] = 35, ["Eastern Plaguelands"] = 53,
    ["Elwynn Forest"] = 1, ["Felwood"] = 48, ["Feralas"] = 40, ["The Hinterlands"] = 40,
    ["Ironforge"] = 1, ["Loch Modan"] = 10, ["Orgrimmar"] = 1, ["Searing Gorge"] = 43,
    ["Silverpine Forest"] = 10, ["Stonetalon Mountains"] = 15, ["Stranglethorn Vale"] = 30,
    ["Swamp of Sorrows"] = 36, ["Tanaris"] = 40, ["Thousand Needles"] = 25, ["Tirisfal Glades"] = 1,
    ["Western Plaguelands"] = 51, ["Westfall"] = 10, ["Wetlands"] = 20, ["Winterspring"] = 53,
}
local LEVEL_SLACK = 4   -- allow zones up to this many levels above you

local function LoadBooks(onlyZone, append, includeDone)
    local list, skipped, tooHigh, haveIt = {}, 0, 0, 0
    local zoneId = onlyZone and hbd:GetPlayerZone()
    local myLevel = UnitLevel and UnitLevel("player") or 80
    local filter = (not onlyZone) and DB().bookLevelFilter ~= false
    for _, e in ipairs(BOOKS) do
        local w = Entry(e)
        if not includeDone and IsDone(e) then
            haveIt = haveIt + 1
        elseif filter and (ZONE_MIN[e[1]] or 1) > myLevel + LEVEL_SLACK then
            tooHigh = tooHigh + 1
        elseif not w then
            skipped = skipped + 1
        elseif not onlyZone or w.uiMapId == zoneId then
            list[#list + 1] = w
        end
    end
    if #list == 0 then
        if onlyZone and haveIt > 0 then
            Print("you already have every known book in this zone. /lazy books zone all shows them anyway.")
        else
            Print(onlyZone and "no known books in this zone" or "no books left to find, or none could be placed")
        end
        return
    end

    -- nearest first, starting from where you stand (greedy)
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local ordered = {}
    while #list > 0 do
        local best, bestD = 1, math.huge
        for i, w in ipairs(list) do
            local d = math.huge
            if px and w.instance == pinst then
                local dx, dy = w.x - px, w.y - py
                d = dx * dx + dy * dy
            end
            if d < bestD then best, bestD = i, d end
        end
        local w = table.remove(list, best)
        ordered[#ordered + 1] = w
        px, py, pinst = w.x, w.y, w.instance
    end

    if append then
        -- keep what is already there; skip books that already have a waypoint
        local have = {}
        for _, w in ipairs(DB().waypoints) do have[w.name] = true end
        for _, w in ipairs(ordered) do
            if not have[w.name] then table.insert(DB().waypoints, w) end
        end
    else
        DB().waypoints = ordered
    end
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    Print(string.format("%d book waypoint%s set, nearest first. Walk to the arrow and click the book.",
        #ordered, #ordered == 1 and "" or "s") ..
        (skipped > 0 and (" (" .. skipped .. " couldn't be placed)") or "") ..
        (tooHigh > 0 and (" " .. tooHigh .. " left out as too high for your level.") or "") ..
        (haveIt > 0 and (" " .. haveIt .. " already collected.") or ""))
end

local function Turnin()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local e = LIBRARIANS[faction or ""]
    if not e then Print("couldn't tell your faction"); return end
    local w = Entry(e)
    if not w then Print("couldn't place the librarian waypoint"); return end
    table.insert(DB().waypoints, 1, w)
    addon:RefreshPins()
    Print("waypoint set: " .. w.name)
end

local function ListBooks()
    Print(string.format("%d known library books, %d collected. Names ending in * come from the Mage Rune guide.",
        #BOOKS, CountDone()))
    for _, e in ipairs(BOOKS) do
        Print(string.format("%s %s %.1f, %.1f - %s", IsDone(e) and "|cff55ff55[x]|r" or "[ ]", e[1], e[3], e[4], e[5]))
    end
end

-- Mark the closest book (within ~60 yards) as collected, or one by part of its name.
local function MarkDone(value, nameBit)
    nameBit = (nameBit or ""):lower()
    if nameBit ~= "" then
        for _, e in ipairs(BOOKS) do
            if BookKey(e):lower():find(nameBit, 1, true) then
                SetDone(e, value)
                Print(string.format("%s marked as %s", BookKey(e), value and "collected" or "not collected"))
                if addon.RefreshOptions then addon.RefreshOptions() end
                return
            end
        end
        Print("no book with that in its name. /lazy books list shows them all")
        return
    end
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then Print("can't read your position"); return end
    local best, bestD
    for _, e in ipairs(BOOKS) do
        local w = Entry(e)
        if w and w.instance == pinst and IsDone(e) ~= value then
            local d = math.sqrt((w.x - px) ^ 2 + (w.y - py) ^ 2)
            if not bestD or d < bestD then best, bestD = e, d end
        end
    end
    if best and bestD <= 60 then
        SetDone(best, value)
        Print(string.format("%s marked as %s", BookKey(best), value and "collected" or "not collected"))
    else
        Print("no book within 60 yards. Stand next to it, or use /lazy books done <part of its name>")
    end
end

local function ResetDone()
    local t = DoneTable()
    for k in pairs(t) do t[k] = nil end
    if RefreshBookPins then RefreshBookPins() end
    Print("collected list cleared for this character")
end

-- Picking a book up shows in the loot messages: "You receive item: [Title]."
local lootFrame = CreateFrame("Frame")
pcall(lootFrame.RegisterEvent, lootFrame, "CHAT_MSG_LOOT")
lootFrame:SetScript("OnEvent", function(_, _, msg, _, _, _, _, _, _, _, _, _, _, guid)
    if type(msg) ~= "string" then return end
    if guid and UnitGUID and guid ~= UnitGUID("player") then return end
    local item = msg:match("%[(.-)%]")
    if not item then return end
    for _, e in ipairs(BOOKS) do
        if BookKey(e):lower() == item:lower() and not IsDone(e) then
            SetDone(e, true)
            Print(string.format("%s marked as collected", BookKey(e)))
            return
        end
    end
end)

--------------------------------------------------------------------------------
-- Telling the party
--------------------------------------------------------------------------------
local BOOK_PREFIX = "FLBK"
local pending   -- who offered us the book route

-- Offer the whole book route to party members who also run this addon.
-- They get a chat line and accept with /lazy books accept (nothing changes on their side until then).
function addon:ShareBooks()
    if not IsInGroup() then Print("you are not in a party"); return end
    self:SendCommMessage(BOOK_PREFIX, "offer", IsInRaid() and "RAID" or "PARTY")
    Print("offered the library book route to the group (only players with this addon see it)")
end

function addon:OnBooksComm(prefix, message, distribution, sender)
    if prefix ~= BOOK_PREFIX then return end
    local from = (sender or "?"):match("^([^%-]+)") or sender
    if from == UnitName("player") then return end
    if not DB().acceptShared then return end
    if message ~= "offer" then return end
    pending = from
    Print(string.format("%s shared the library book route. Type |cff55ff55/lazy books accept|r to load it as waypoints (replaces your current ones).", from))
end
addon:RegisterComm(BOOK_PREFIX, "OnBooksComm")

-- Post the books in the current zone to party chat, so people without the addon get the coordinates.
local function SayZoneBooks()
    if not IsInGroup() then Print("you are not in a party"); return end
    local zoneId = hbd:GetPlayerZone()
    local chan = IsInRaid() and "RAID" or "PARTY"
    local n = 0
    for _, e in ipairs(BOOKS) do
        if ResolveMap(e[1], e[2]) == zoneId then
            SendChatMessage(string.format("Library book: %s - %s /way %.1f %.1f", e[5], e[1], e[3], e[4]), chan)
            n = n + 1
        end
    end
    if n == 0 then Print("no known books in this zone") else Print("posted " .. n .. " book location(s) to " .. chan:lower() .. " chat") end
end

--------------------------------------------------------------------------------
-- Zone alert: tell me when I enter a zone that has books
--------------------------------------------------------------------------------
local told = {}   -- zones already announced this session
local function CountZoneBooks(zoneId)
    local n = 0
    for _, e in ipairs(BOOKS) do
        if ResolveMap(e[1], e[2]) == zoneId and not IsDone(e) then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- World map: every known book, whether or not I have it
--   book icon = still to find, green tick = collected
--------------------------------------------------------------------------------
local hbdp = LibStub("HereBeDragons-Pins-2.0", true)
local bookRef = {}
local bookFrames = {}

function RefreshBookPins()
    if addon.BooksChanged then pcall(addon.BooksChanged) end
    if not hbdp then return end
    pcall(hbdp.RemoveAllWorldMapIcons, hbdp, bookRef)
    if DB().bookPins == false or not addon.ModuleOn("books") then return end
    for i, e in ipairs(BOOKS) do
        local w = Entry(e)
        if w then
            local f = bookFrames[i]
            if not f then
                f = CreateFrame("Frame", nil, UIParent)
                f:SetSize(16, 16)
                f.tex = f:CreateTexture(nil, "OVERLAY")
                f.tex:SetAllPoints()
                f:Hide()
                bookFrames[i] = f
            end
            if IsDone(e) then
                f.tex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                f.tex:SetVertexColor(0.3, 1, 0.3)
            else
                f.tex:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
                f.tex:SetVertexColor(1, 1, 1)
            end
            pcall(hbdp.AddWorldMapIconWorld, hbdp, bookRef, f, w.instance, w.x, w.y, 1)
        end
    end
end
addon.RefreshBookPins = RefreshBookPins

local function CheckZone()
    local db = DB()
    if not addon.ModuleOn("books") then return end
    if db.bookAlert == false and not db.bookAuto then return end
    local zoneId = hbd:GetPlayerZone()
    if not zoneId or told[zoneId] then return end
    local n = CountZoneBooks(zoneId)
    if n == 0 then return end
    if db.bookLevelFilter ~= false then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zoneId)
        local min = info and ZONE_MIN[info.name] or 1
        if min > (UnitLevel("player") or 80) + LEVEL_SLACK then return end
    end
    told[zoneId] = true
    if db.bookAuto then
        Print(string.format("%d library book%s in this zone - adding waypoints.", n, n == 1 and "" or "s"))
        LoadBooks(true, true)
    else
        Print(string.format("%d library book%s in this zone. |cff55ff55/lazy books zone|r for arrows.", n, n == 1 and "" or "s"))
    end
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function(_, event)
    -- the map is not always ready the instant the event fires
    if C_Timer and C_Timer.After then
        C_Timer.After(2, CheckZone)
        if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(3, RefreshBookPins) end
    else
        CheckZone()
        if event == "PLAYER_ENTERING_WORLD" then RefreshBookPins() end
    end
end)

--------------------------------------------------------------------------------
-- Books drop-down list, and a Titan Panel button (through LibDataBroker)
--------------------------------------------------------------------------------
local sortedIdx
local function SortedBooks()
    if sortedIdx then return sortedIdx end
    sortedIdx = {}
    for i = 1, #BOOKS do sortedIdx[i] = i end
    table.sort(sortedIdx, function(a, b)
        local ea, eb = BOOKS[a], BOOKS[b]
        if ea[1] ~= eb[1] then return ea[1] < eb[1] end
        return BookKey(ea) < BookKey(eb)
    end)
    return sortedIdx
end

-- make one book the active waypoint (keeps the others, no duplicates)
local function TrackBook(e)
    local w = Entry(e)
    if not w then Print("couldn't place that book"); return end
    local wps = DB().waypoints
    for i = #wps, 1, -1 do
        if wps[i].name == w.name then table.remove(wps, i) end
    end
    table.insert(wps, 1, w)
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
    Print("tracking: " .. w.name)
end

local bookMenu, menuCatcher
local ROWS, ROWH = 16, 18

local function RefreshMenu()
    local f = bookMenu
    if not f then return end
    local idx = SortedBooks()
    f.offset = math.min(math.max(f.offset or 0, 0), math.max(0, #idx - ROWS))
    local myLevel = UnitLevel("player") or 80
    for r = 1, ROWS do
        local row = f.rows[r]
        local e = BOOKS[idx[f.offset + r]]
        if e then
            row.e = e
            local done = IsDone(e)
            local high = (ZONE_MIN[e[1]] or 1) > myLevel + LEVEL_SLACK
            local color = done and "|cff55ff55" or (high and "|cff888888" or "|cffffffff")
            row.fs:SetText(string.format("%s%s%s|r |cffaaaaaa- %s|r", done and "[x] " or "", color, BookKey(e), e[1]))
            row:Show()
        else
            row.e = nil
            row:Hide()
        end
    end
    f.title:SetText(string.format("Library books  %d / %d collected", CountDone(), #BOOKS))
end

local function MakeBookMenu()
    local f = CreateFrame("Frame", "ForeverLazy_BookMenu", UIParent)
    f:SetSize(380, ROWS * ROWH + 46)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("BOTTOMLEFT", 10, 8)
    f.hint:SetText("Click: track   Shift+click: mark collected   Wheel: scroll")
    f.offset = 0
    f.rows = {}
    local function wheel(_, delta) f.offset = (f.offset or 0) - delta * 3; RefreshMenu() end
    f:SetScript("OnMouseWheel", wheel)
    for r = 1, ROWS do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(360, ROWH)
        b:SetPoint("TOPLEFT", 10, -26 - (r - 1) * ROWH)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", wheel)
        b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.fs:SetPoint("LEFT", 2, 0)
        b.fs:SetJustifyH("LEFT")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
        b:SetScript("OnClick", function(self)
            if not self.e then return end
            if IsShiftKeyDown() then
                SetDone(self.e, not IsDone(self.e))
                RefreshMenu()
            else
                TrackBook(self.e)
                f:Hide()
            end
        end)
        f.rows[r] = b
    end
    -- click anywhere outside to close
    menuCatcher = CreateFrame("Button", nil, UIParent)
    menuCatcher:SetAllPoints(UIParent)
    menuCatcher:SetFrameStrata("FULLSCREEN")
    menuCatcher:Hide()
    menuCatcher:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnShow", function() menuCatcher:Show() end)
    f:SetScript("OnHide", function() menuCatcher:Hide() end)
    table.insert(UISpecialFrames, "ForeverLazy_BookMenu")
    f:Hide()
    return f
end

function addon:OpenBookMenu(anchor)
    bookMenu = bookMenu or MakeBookMenu()
    if bookMenu:IsShown() then bookMenu:Hide(); return end
    bookMenu.offset = 0
    bookMenu:ClearAllPoints()
    local cy
    if anchor and anchor.GetCenter then
        local _, y = anchor:GetCenter()
        cy = y
    end
    if cy then
        if cy < UIParent:GetHeight() / 2 then
            bookMenu:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
        else
            bookMenu:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
        end
    else
        bookMenu:SetPoint("CENTER")
    end
    bookMenu:Show()
    RefreshMenu()
end

local ldbObj
function addon.BooksChanged()
    if ldbObj then ldbObj.text = string.format("%d/%d", CountDone(), #BOOKS) end
    if bookMenu and bookMenu:IsShown() then RefreshMenu() end
end

local function SetupLDB()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB or ldbObj then return end
    ldbObj = LDB:NewDataObject("Forever Lazy Books", {
        type = "data source",
        label = "Books",
        text = string.format("%d/%d", CountDone(), #BOOKS),
        icon = "Interface\\Icons\\INV_Misc_Book_09",
        OnClick = function(self, button)
            if button == "LeftButton" then
                addon:OpenBookMenu(self)
            elseif button == "MiddleButton" then
                addon:HandleExtraCommand("arrow", "")
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Library books")
            tt:AddLine(string.format("%d of %d collected", CountDone(), #BOOKS), 1, 1, 1)
            local wp = DB().waypoints[1]
            if wp then tt:AddLine("Tracking: " .. wp.name, 0.6, 0.8, 1) end
            tt:AddLine(" ")
            tt:AddLine("Left-click: pick a book to track", 0.7, 0.7, 0.7)
            tt:AddLine("Middle-click: show / hide the waypoint arrow", 0.7, 0.7, 0.7)
        end,
    })
end

local ldbFrame = CreateFrame("Frame")
pcall(ldbFrame.RegisterEvent, ldbFrame, "PLAYER_LOGIN")
ldbFrame:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() pcall(SetupLDB); pcall(addon.BooksChanged) end)
    else
        pcall(SetupLDB)
    end
end)

-- hook into the slash handler
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd == "arrow" or (cmd == "books" and (rest or ""):lower() == "arrow") then
        local db = DB()
        db.waypointArrowOff = not db.waypointArrowOff
        Print("waypoint arrow " .. (db.waypointArrowOff and "hidden (waypoints are kept)" or "shown"))
        return true
    end
    if cmd == "books" or cmd == "book" then
        rest = (rest or ""):lower()
        if rest == "share" or rest == "send" then self:ShareBooks(); return true end
        if rest == "say" or rest == "post" then SayZoneBooks(); return true end
        if rest == "accept" then
            if pending then pending = nil; LoadBooks(false) else Print("nobody has offered you a book route") end
            return true
        end
        if rest == "done" or rest:match("^done%s") then MarkDone(true, rest:match("^done%s+(.*)$")); return true end
        if rest == "undone" or rest:match("^undone%s") then MarkDone(false, rest:match("^undone%s+(.*)$")); return true end
        if rest == "reset" then ResetDone(); return true end
        if rest == "menu" or rest == "pick" then self:OpenBookMenu(nil); return true end
        if rest == "pins" then
            DB().bookPins = (DB().bookPins == false)
            RefreshBookPins()
            Print("book icons on the world map " .. (DB().bookPins and "on" or "off"))
            return true
        end
        if rest == "zone all" or rest == "here all" then LoadBooks(true, false, true)
        elseif rest == "zone" or rest == "here" then LoadBooks(true)
        elseif rest == "turnin" or rest == "handin" or rest == "librarian" then Turnin()
        elseif rest == "list" then ListBooks()
        else LoadBooks(false) end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Books.lua"] = true end end
