-- Making it easier to learn: a first-run tour, settings export and import, and a "what's new" window.
--   /lazy tour       the tour (it also starts by itself after the welcome window)
--   /lazy export     my settings as one line of text to share
--   /lazy import     paste a line of settings
--   /lazy new        what changed in this version
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function DB() return addon.GetDB() end

local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON, "Version") or "?"
end

--------------------------------------------------------------------------------
-- The tour
--------------------------------------------------------------------------------
local STEPS = {
    { text = "|cffffd100Welcome to Forever Lazy.|r This is a quick tour (8 short steps). It shows where the buttons are, so you never need to type a command. Press Next.",
      target = nil },
    { text = "|cffffd100The minimap button.|r Left-click: do the next best thing (Lazy Mode). Right-click: the menu with everything. Shift-click: the options.",
      target = function() return _G.ForeverLazy_MinimapButton end },
    { text = "|cffffd100The menu.|r This is what the right-click opens: go somewhere, plan your route, boats, journey, crafting, group, settings. Pick anything to try it.",
      target = nil, onShow = function() if addon.OpenMenu then addon:OpenMenu() end end, onHide = function() if _G.ForeverLazy_Menu then _G.ForeverLazy_Menu:Hide() end end },
    { text = "|cffffd100The world map.|r Press M. In the top right there is a search box (\"Go to...\") and a Lazy button. Type a place, a city, a dungeon or a flight point, and press Enter: the arrow plans the whole trip. Your route shows on the map with numbered stops.",
      target = function() local w = _G.WorldMapFrame; return w and w:IsShown() and w or nil end },
    { text = "|cffffd100The quest log.|r Press L. Under it: Plan my route, Do this next, Skip this. Right-clicking the main arrow does the same.",
      target = function() local q = _G.QuestLogFrame; return q and q:IsShown() and q or nil end },
    { text = "|cffffd100Professions.|r Open a profession window once. Beside it, a craft plan appears: what to craft, the materials counting your bags and bank, and where to get what is missing.",
      target = function() local p = _G.ForeverLazy_CraftPanel; return p and p:IsShown() and p or nil end },
    { text = "|cffffd100The options.|r /lazy opens them. At the top: Presets (Minimal, Leveler, Duo, Everything) and a switch for every module, so you only keep what you want.",
      target = nil, onShow = function() if addon.OpenOptions then addon:OpenOptions() end end },
    { text = "|cffffd100That is it.|r Lazy Mode (/lazy now, or left-click the minimap button) is the one to remember. /lazy tour shows this again, and /lazy check says if everything is working.",
      target = nil },
}

local tour, hl
local idx = 0

local function Highlight(frame)
    if not hl then
        hl = CreateFrame("Frame", nil, UIParent)
        hl:SetFrameStrata("TOOLTIP")
        hl.edges = {}
        for i = 1, 4 do
            local t = hl:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(1, 0.82, 0, 0.95)
            hl.edges[i] = t
        end
    end
    if not frame then hl:Hide(); return end
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
    hl:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
    local e = hl.edges
    e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(3)
    e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(3)
    e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(3)
    e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(3)
    hl:Show()
end

local function ShowStep()
    local step = STEPS[idx]
    if not step then return end
    tour.counter:SetText(string.format("%d of %d", idx, #STEPS))
    tour.text:SetText(step.text)
    tour.back:SetEnabled(idx > 1)
    tour.next:SetText(idx == #STEPS and "Done" or "Next")
    local target = step.target and step.target()
    Highlight(target)
    tour:ClearAllPoints()
    if target and target.GetCenter then
        local _, cy = target:GetCenter()
        if cy and cy > UIParent:GetHeight() / 2 then
            tour:SetPoint("TOP", target, "BOTTOM", 0, -16)
        else
            tour:SetPoint("BOTTOM", target, "TOP", 0, 16)
        end
    else
        tour:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    end
    tour:SetHeight(110 + tour.text:GetStringHeight())
    tour:Show()
    if step.onShow then pcall(step.onShow) end
end

local function Leave(step)
    if step and step.onHide then pcall(step.onHide) end
end

local function Finish()
    Leave(STEPS[idx])
    if tour then tour:Hide() end
    Highlight(nil)
    local root = addon.GetRoot()
    if root then root.tourDone = true end
    idx = 0
end

local function BuildTour()
    local f = CreateFrame("Frame", "ForeverLazy_Tour", UIParent)
    f:SetSize(360, 150)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.97)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -10); f.title:SetText("Forever Lazy tour")
    f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.counter:SetPoint("TOPRIGHT", -12, -14)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", 12, -36); f.text:SetWidth(336); f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP")
    f.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.back:SetSize(70, 22); f.back:SetPoint("BOTTOMLEFT", 12, 10); f.back:SetText("Back")
    f.back:SetScript("OnClick", function() Leave(STEPS[idx]); idx = math.max(1, idx - 1); ShowStep() end)
    f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.next:SetSize(80, 22); f.next:SetPoint("LEFT", f.back, "RIGHT", 6, 0)
    f.next:SetScript("OnClick", function()
        Leave(STEPS[idx])
        if idx >= #STEPS then Finish() else idx = idx + 1; ShowStep() end
    end)
    local skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    skip:SetSize(70, 22); skip:SetPoint("BOTTOMRIGHT", -12, 10); skip:SetText("Skip")
    skip:SetScript("OnClick", Finish)
    f:Hide()
    return f
end

function addon.StartTour()
    tour = tour or BuildTour()
    idx = 1
    ShowStep()
end

--------------------------------------------------------------------------------
-- Settings export and import
--------------------------------------------------------------------------------
local function Deflate() return LibStub and LibStub("LibDeflate", true) end

local function IsColor(v)
    if type(v) ~= "table" or #v ~= 3 then return false end
    for i = 1, 3 do if type(v[i]) ~= "number" or v[i] < 0 or v[i] > 1 then return false end end
    return true
end

local function Clean(db)
    local out = {}
    for k, v in pairs(db) do
        local t = type(v)
        if t == "boolean" or t == "number" or t == "string" then out[k] = v
        elseif k == "modules" and t == "table" then
            local m = {}
            for key, val in pairs(v) do if type(val) == "boolean" and type(key) == "string" then m[key] = val end end
            out[k] = m
        elseif IsColor(v) then out[k] = { v[1], v[2], v[3] } end
    end
    out.minimapAngle = nil
    return out
end

local function Export()
    local LD = Deflate()
    local ok, data = pcall(addon.Serialize, addon, Clean(DB()))
    if not ok or not data then return nil end
    if LD then
        local packed = LD:EncodeForPrint(LD:CompressDeflate(data))
        return "FL1:" .. packed
    end
    return "FL0:" .. data
end

local function Import(text)
    text = (text or ""):gsub("%s+", "")
    if #text < 8 or #text > 12000 then return false, "that does not look like a settings line" end
    local LD = Deflate()
    local data
    if text:sub(1, 4) == "FL1:" and LD then
        local raw = LD:DecodeForPrint(text:sub(5))
        data = raw and LD:DecompressDeflate(raw)
    elseif text:sub(1, 4) == "FL0:" then
        data = text:sub(5)
    end
    if not data then return false, "I could not read that line" end
    local ok, t = addon:Deserialize(data)
    if not ok or type(t) ~= "table" then return false, "that line is damaged" end
    local db = DB()
    local n = 0
    local current = Clean(db)
    for k, v in pairs(t) do
        if type(k) == "string" and (current[k] ~= nil or k == "modules") then
            local want = type(current[k])
            if k == "modules" and type(v) == "table" then
                db.modules = db.modules or {}
                for key, val in pairs(v) do if type(val) == "boolean" then db.modules[key] = val; n = n + 1 end end
            elseif type(v) == want and want ~= "table" then
                db[k] = v; n = n + 1
            elseif want == "table" and IsColor(v) then
                db[k] = { v[1], v[2], v[3] }; n = n + 1
            end
        end
    end
    return true, n
end

local box
local function BuildBox()
    local f = CreateFrame("Frame", "ForeverLazy_SettingsBox", UIParent)
    f:SetSize(420, 230)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -24)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPLEFT", 14, -36); f.hint:SetWidth(390); f.hint:SetJustifyH("LEFT")
    local ebBg = f:CreateTexture(nil, "BORDER")
    ebBg:SetPoint("TOPLEFT", 12, -62); ebBg:SetSize(396, 120); ebBg:SetColorTexture(0, 0, 0, 0.6)
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal or GameFontHighlight)
    eb:SetSize(384, 116); eb:SetPoint("TOPLEFT", 18, -66); eb:SetAutoFocus(false); eb:SetMaxLetters(12000)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.edit = eb
    f.action = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.action:SetSize(110, 24); f.action:SetPoint("BOTTOMLEFT", 14, 12)
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(90, 24); close:SetPoint("BOTTOMRIGHT", -14, 12); close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    return f
end

function addon.ExportSettings()
    box = box or BuildBox()
    local s = Export()
    box.title:SetText("Export my settings")
    box.hint:SetText("Copy this line (Ctrl+A, Ctrl+C) and send it. The other player pastes it under Import.")
    box.edit:SetText(s or "I could not make the line")
    box.action:SetText("Select all")
    box.action:SetScript("OnClick", function() box.edit:SetFocus(); box.edit:HighlightText() end)
    box:Show()
end

function addon.ImportSettings()
    box = box or BuildBox()
    box.title:SetText("Import settings")
    box.hint:SetText("Paste a settings line here (Ctrl+V) and press Apply. Your waypoints and quests are not touched.")
    box.edit:SetText("")
    box.action:SetText("Apply")
    box.action:SetScript("OnClick", function()
        local ok, n = Import(box.edit:GetText())
        if ok then
            Print(string.format("imported %d settings", n))
            if addon.ApplyAll then pcall(addon.ApplyAll, addon) end
            if addon.ModulesChanged then pcall(addon.ModulesChanged) end
            box:Hide()
        else
            Print(n)
        end
    end)
    box:Show()
    box.edit:SetFocus()
end

--------------------------------------------------------------------------------
-- What is new
--------------------------------------------------------------------------------
local NEW = {
    { "0.15.2", {
        "JOB'S DONE!! Quest sounds from the game itself: a sound effect when a quest step is done, and the Job's done voice when the quest is ready to hand in. Pick them in the options!",
        "Hover a quest giver and the tooltip lists the quests they GIVE (! ) and the ones you can hand in to them (? ).",
        "CLICK the quest map! Click a pin or a coloured area and the arrow points right there. Hover it for the QUEST LEVEL, the MOB LEVELS and the named area, like Goldshire!",
        "The arrow and the plan name the AREA of each stop, not just the zone.",
        "The damage meter: hover a name and see the MOVES they used, with amounts and percents. It no longer flickers or sticks.",
        "FIXED: fly to a new zone and the arrow now updates by itself!",
    } },
    { "0.15.1", {
        "DROP RATES WITHOUT QUESTIE!! The real chance that every creature drops every quest item, from Questie's own tables. The best place to farm an item is a REAL answer now, not a guess!",
    } },
    { "0.15.0", {
        "Forever Lazy no longer needs Questie: it carries its own quest data and rules, checked against Questie's. Questie still works as a second source. The addon is now GPL-3.0.",
        "The quest map: where your quests' mobs, items and objects are, on the world map and minimap, with coloured areas, a yellow ! for quests to pick up and a yellow ? for hand-ins. The route lines are gone.",
        "Quest tooltips: hover a mob, object or item a quest needs and it says which quest, in bold gold, and how far along you are. In a group it shows each person's progress too, including people who run Questie.",
        "Turn-ins come first in an area that has them. Yellow quests rank above orange. The Ready line in the tracker is green.",
        "Couch mode (/lazy couch), talent reminders (/lazy talents), come back to a quest later, a tracker grouped by zone, mob level ranges (/lazy moblevels), and an update notice with a What's new button.",
    } },    { "0.14.0", {
        "Forever Lazy's own quest tracker (/lazy tracker): your quests in plan order with XP, live objectives and who to turn in to. Click to do one next, right-click for more. It can replace WoW's, has a no-background option, scrolls, resizes and fits its text.",
        "Autopilot (/lazy autopilot on): vendor and trainer stops between quests, then the next zone and a plan for it, by itself.",
        "The arrow points at the nearest spot where the kills or items are, and moves on when you have cleared it.",
        "A step window (/lazy steps) lists the plan as steps and ticks them off. The plan only moves on when a step is really done.",
        "The planner weighs XP for the time, counts nearby quests and leaves small ones out. Quest rewards are picked for your class and spec.",
        "Making sure the plan is right: /lazy plan log shows every change and why, /lazy plan check fixes broken steps, and it asks if you are stuck.",
        "In a group, entering a dungeon your quests need something in shows what you need there. /lazy dungeons here shows it any time.",
    } },
    { "0.13.0", {
        "Level a zone: /lazy level (or /lazy level ashenvale). Plans every quest worth doing in the zone and opens a window of what to get, where to kill and what to hand in.",
        "Ask a guard where something is and the arrow takes you there, then goes away.",
        "Class quests: a pop-up when you enter a zone that has something for one, /lazy class quest for what to do, /lazy class here for this zone.",
        "Plans never include dungeon quests, and the plan rebuilds by itself when you change continent.",
        "Walk close to a quest you can hand in and the plan puts it next. A stop for a quest you have not finished no longer clears just because you arrived.",
        "The craft plan stops where the trainer has new recipes, one batch at a time.",
        "A protected item that is sold anyway puts a big message on the screen. Node pins show a hover tooltip on the minimap too, and fade while the node respawns.",
        "Fixes: skip works again, the arrow menu keeps its skip option, and the craft panel no longer covers the tabs.",
    } },
    { "0.12.0", {
        "A damage meter in its own chat tab called Meter (/lazy meter). It reads the game's built-in meter, so no other addon is needed.",
        "The Hive learns how long each kind of mob takes to kill and what it costs you (/lazy grind), and where players die: you get a word when you walk into a place where people keep dying (/lazy danger).",
        "Ore and herb nodes you gather are marked on the map and minimap, and the arrow can farm them (/lazy nodes farm). /lazy nodes silver lists the zones that have it.",
        "Turn the plan off and keep your place: /lazy plan off, /lazy plan on. The route lines, markers and quest item bar go away while it is off.",
        "Protect items from vendors: /lazy keep <item>. Your Cozy Sleeping Bag is protected from the start; a sale gets bought back.",
        "Fix: the craft plan panel no longer covers the profession window tabs.",
    } },
    { "0.11.2", {
        "Fix: a trip step by tram, boat or flight now finishes when it has taken you away from where you boarded, so the arrow no longer points back at the boarding spot.",
    } },
    { "0.11.1", {
        "Fix: the measured XP per hour was too high (a big quest hand-in after a long walk counted as 30 seconds). The time since your last XP now counts, up to 15 minutes. /lazy pace reset clears the old numbers.",
    } },
    { "0.11.0", {
        "The Coach (/lazy coach, or Ask the Coach in the menus): compares doing the quests here, the best grind and other zones by measured XP per hour and tells you the best thing to do now, with a button to set it up.",
        "Real quest spots: with the Hive on, the addon learns where quest objectives are really done and the plan uses those places instead of the original data. Grind advice can point at where you killed a mob most.",
        "A far-off plan stop starts a flight trip by itself when a flight is quicker.",
        "Fix: a quest handed in out of order, or dropped, is taken out of the plan at once, so the arrow no longer sends you back to its giver.",
    } },
    { "0.10.2", {
        "The plan finishes the quests in an area before walking back to hand any in, unless handing one in continues a chain (Options > Extras to turn it off).",
        "This window now has Sam on it.",
    } },
    { "0.10.1", {
        "The craft plan panel beside the profession window now always appears (it could be missed when another addon loaded that window first), and says why in chat if it cannot.",
    } },
    { "0.10.0", {
        "The Hive: the addon learns from your own play. Your real XP per hour (/lazy pace), the drops you loot (/lazy drops, item tooltips, the crafting plan), how long each quest really takes you, and a session report (/lazy session).",
        "Best grind (/lazy grind): which mobs give the most XP per hour near your level. Rare pins turn into timers after a kill, with how long the rare usually takes to come back.",
        "The guide and the new-zone box show your measured pace and your fastest zone, and quests that were slow for you are marked in the skip menu.",
        "Turn the Hive on (Options > The Hive) to share what it learns with other players who have it on: drop rates, quest times and zone paces, rare spawns on the map, and how many players are in a zone. Only ids and numbers, never your name, and never a track of where you are.",
    } },
    { "0.9.2", {
        "Item tooltips say how many you have in bags, bank, mail, worn and the guild bank, and what your other characters have (/lazy has <item>).",
        "Hunters are warned when ammo runs low, and when a better kind of arrow or bullet opens up for their level.",
    } },
    { "0.9.1", {
        "You can now point the arrow at the nearest library book (right-click the arrow).",
    } },
    { "0.9.0", {
        "The levelling guide: /lazy guide opens your journey to 60 with where you are, quests worth doing, dungeons that fit and a Take me there button. Its text size scales for the couch and TV (A-, A+, TV).",
        "XP hot spots: a light heat layer on the zone map (the XP button, or /lazy xpmap) showing where the quests worth doing for your level are.",
        "One arrow: right-click it and pick what it points at (what is next, my plan, my nearest quest, my partner, my friend's quest). It switches at once.",
    } },
    { "0.8.9", {
        "Hunter pets: a huge shaking FEED ME!!! across the screen when your pet is hungry (it can be turned off), and your own sound clip plays if you put one in media\\custom.",
    } },
    { "0.8.8", {
        "New zone: after you have stayed a little while, a small box offers to plan it. It stays quiet while you are just passing through, and when every quest there is red or grey.",
    } },
    { "0.8.7", {
        "One Forever Lazy button for Titan Panel and other bars: an icon, your next stop, and the whole menu when you hover.",
        "Your route is drawn on the minimap too, and trips are drawn on the world map and minimap with flights, boats and walks in different colours.",
        "A far-off stop: Lazy Mode sends you to a flight master and says where to fly, and the flight map rings that destination.",
        "Lazy Mode skips the trainer when there is nothing to learn. Collected library books turn into a green tick.",
    } },
    { "0.8.6", {
        "A Sam Kinison minimap button.",
        "The services menu on the arrow adapts: in a city it offers every service in the city, in the open world only those within a walk.",
        "This what's new window scrolls.",
    } },
    { "0.8.5", {
        "Right-click the arrow for a short menu: services near me (repair, inn, bank and more, only the ones close by), skip or do this quest next, and Lazy Mode.",
        "The addon's macros have their own icons, and any older ones are renamed to Lazy ... on login.",
    } },
    { "0.8.4", {
        "The craft plan shows how many to make on the recipe row, names the zones to get materials, and has a Clear button.",
        "The old LRXP name is gone: commands are /lazy, macros are called Lazy ..., and your settings carry over. /lrxp still works.",
    } },
    { "0.8.3", {
        "Fixes for this client: crafting and the window buttons now load, and the craft plan reads your recipes.",
        "The recommended recipe lights up in the profession window, with a Show it button.",
        "/lazy check now names any file that failed to load, and errors in commands show in chat.",
    } },
    { "0.8.2", {
        "Buttons and menus in the game windows: a menu on the minimap button, a search box on the world map, quest log buttons, a craft plan beside your profession window.",
        "Numbered stop markers on the route drawn on the world map.",
        "A tour of all this, settings export and import, and this window.",
    } },
    { "0.8.0", {
        "Take me there: /lazy go <place> plans a whole trip by flight path, boat, tram and hearthstone.",
        "Every Forever flight point is built in; boat routes updated.",
    } },
    { "0.7.0", {
        "Lazy Mode, crafting with bank counting, journey, gathering routes, fishing spots, duo mode, modules and presets.",
    } },
}

local newWin
local function ShowNew(current, newer, who)
    newWin = newWin or (function()
        local f = CreateFrame("Frame", "ForeverLazy_New", UIParent)
        f:SetSize(420, 380)
        f:SetPoint("CENTER", 0, 80)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", 14, -24)
        f.title:SetWidth(320); f.title:SetJustifyH("LEFT")
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4); f.sub:SetWidth(320); f.sub:SetJustifyH("LEFT")
        -- Sam, top right (photo: media\CREDITS.txt, CC BY-SA 2.0)
        local face = f:CreateTexture(nil, "ARTWORK")
        face:SetSize(56, 56)
        face:SetPoint("TOPRIGHT", -14, -12)
        face:SetTexture("Interface\\AddOns\\ForeverLazy\\media\\kinison.tga")
        face:SetTexCoord(62 / 256, 186 / 256, 28 / 256, 152 / 256)
        local ohh = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ohh:SetPoint("TOP", face, "BOTTOM", 0, -2)
        ohh:SetText("|cffff3333OH Oh OHH|r")
        local by = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        by:SetPoint("TOPLEFT", 14, -6); by:SetWidth(330); by:SetJustifyH("LEFT")
        by:SetText("Brought to you by Sam Skinison and Tank Hanks")
        local credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        credit:SetPoint("BOTTOM", 0, 14)
        credit:SetWidth(170)
        credit:SetText("Photo: The World Famous Comedy Store, CC BY-SA 2.0 (Wikimedia Commons)")
        -- the list sits in a scroll area so a long history never runs off the window
        f.scroll = CreateFrame("ScrollFrame", "ForeverLazy_NewScroll", f, "UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT", 14, -92); f.scroll:SetPoint("BOTTOMRIGHT", -34, 46)
        f.content = CreateFrame("Frame", nil, f.scroll)
        f.content:SetSize(360, 10)
        f.scroll:SetScrollChild(f.content)
        f.text = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 0, 0); f.text:SetWidth(360); f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP")
        -- shown when a newer version exists: where to get it (select the line and copy it)
        f.url = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.url:SetSize(300, 20); f.url:SetPoint("BOTTOMLEFT", 20, 44); f.url:SetAutoFocus(false)
        f.url:SetText("https://github.com/everyday3d/ForeverLazy/releases")
        f.url:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        f.url:SetScript("OnTextChanged", function(s, user) if user then s:SetText("https://github.com/everyday3d/ForeverLazy/releases") end end)
        f.url:Hide()
        local tourBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        tourBtn:SetSize(120, 24); tourBtn:SetPoint("BOTTOMLEFT", 14, 12); tourBtn:SetText("Take the tour")
        tourBtn:SetScript("OnClick", function() f:Hide(); addon.StartTour() end)
        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetSize(90, 24); close:SetPoint("BOTTOMRIGHT", -14, 12); close:SetText("Close")
        close:SetScript("OnClick", function() f:Hide() end)
        f:Hide()
        return f
    end)()
    local lines = {}
    for _, v in ipairs(NEW) do
        lines[#lines + 1] = "|cffffd100" .. v[1] .. "|r"
        for _, item in ipairs(v[2]) do lines[#lines + 1] = "  - " .. item end
        lines[#lines + 1] = ""
    end
    newWin.title:SetText("What's new new |cffff3333NEWWW!|r")
    newWin.sub:SetText("Forever Lazy " .. (current or Version()) .. " (installed)")
    if newer then
        newWin.sub:SetText("You have Forever Lazy " .. (current or Version()) .. ". Version " .. newer .. " is out" .. (who and (" (" .. who .. " runs it)") or "") ..
            ". Get it from the link below (select it, Ctrl+C), then reload. The list shows what your installed version has.")
        newWin.url:Show()
        newWin.scroll:SetPoint("TOPLEFT", 14, -160); newWin.scroll:SetPoint("BOTTOMRIGHT", -34, 72)
    else
        newWin.url:Hide()
        newWin.scroll:SetPoint("TOPLEFT", 14, -104); newWin.scroll:SetPoint("BOTTOMRIGHT", -34, 46)
    end
    newWin.text:SetText(table.concat(lines, "\n"))
    newWin.content:SetHeight(newWin.text:GetStringHeight() + 10)
    if newWin.scroll.SetVerticalScroll then newWin.scroll:SetVerticalScroll(0) end
    newWin:Show()
end
function addon.ShowWhatsNew() ShowNew(Version(), addon.newerVersion, addon.newerFrom) end

--------------------------------------------------------------------------------
-- When these show by themselves
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if not C_Timer then return end
    C_Timer.After(8, function()
        local root = addon.GetRoot()
        if not root then return end
        local current = Version()
        if root.welcomed and not root.tourDone and not root.tourOffered then
            root.tourOffered = true
            Print("a quick tour of the buttons: /lazy tour")
        end
        if root.seenVersion and root.seenVersion ~= current and root.welcomed then
            ShowNew(current)
        end
        root.seenVersion = current
    end)
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    if word == "tour" then addon.StartTour(); return true
    elseif word == "export" then addon.ExportSettings(); return true
    elseif word == "import" then addon.ImportSettings(); return true
    elseif word == "new" or word == "whatsnew" then addon.ShowWhatsNew(); return true
    elseif word == "welcome" then if addon.ShowWelcome then addon.ShowWelcome() end; return true end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Help.lua"] = true end end
