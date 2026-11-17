-- Options panel for Forever Lazy
local ADDON, ns = ...
local addon = ns.addon

local TITLE = "Forever Lazy"
local panel, standalone, category
local built = false
local refreshers = {}

local function DB() return addon.GetDB() end
local function Changed() addon:ApplyAll() end

local function Refresh() for _, r in ipairs(refreshers) do r() end end
addon.RefreshOptions = Refresh

-- layout cursor
local y

-- Collapsible groups: every control made after a Header belongs to that group.
-- Controls remember where they sit inside their group, and Layout() puts the
-- groups one under the other, hiding the controls of collapsed ones.
local sections = {}
local shared = {}    -- the one scrolling page and its content, reused by every Settings page
local cur            -- group being built
local topY           -- where the first group starts
local Layout         -- defined in BuildControls

local function Track(obj, x, yy)
    if cur then cur.items[#cur.items + 1] = { obj = obj, x = x, y = yy - cur.bodyY } end
end

local function IsOpen(title)
    local t = DB().optOpen
    if t == nil then return sections[1] ~= nil and sections[1].title == title end
    return t[title] == true
end

local function SetOpen(title, open)
    local t = DB().optOpen
    if t == nil then
        t = {}
        if sections[1] then t[sections[1].title] = true end
        DB().optOpen = t
    end
    t[title] = open and true or false
end

local function Header(parent, text)
    if cur then cur.bodyEnd = y end
    y = y - 12
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(480, 24)
    b:SetPoint("TOPLEFT", 16, y)
    b.fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    b.fs:SetPoint("LEFT", 0, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    y = y - 26
    cur = { title = text, header = b, bodyY = y, items = {} }
    sections[#sections + 1] = cur
    local mine = cur
    b:SetScript("OnClick", function()
        if shared.split then return end
        SetOpen(mine.title, not IsOpen(mine.title))
        if Layout then Layout() end
    end)
end

local function Label(parent, text, x)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x or 16, y)
    fs:SetText(text)
    Track(fs, x or 16, y)
    return fs
end

local checkId = 0
local function Check(parent, text, x, get, set, advance)
    checkId = checkId + 1
    local name = "ForeverLazy_Check" .. checkId
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x or 16, y)
    Track(cb, x or 16, y)
    local fs = _G[name .. "Text"]
    if fs then fs:SetText(text) end
    cb.Refresh = function() cb:SetChecked(get()) end
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    refreshers[#refreshers + 1] = cb.Refresh
    if advance ~= false then y = y - 26 end
    return cb
end

local sliderId = 0
local function Slider(parent, text, minV, maxV, step, fmt, get, set)
    sliderId = sliderId + 1
    local name = "ForeverLazy_Slider" .. sliderId
    y = y - 14
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 24, y)
    Track(s, 24, y)
    s:SetWidth(240)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    _G[name .. "Low"]:SetText(string.format(fmt, minV))
    _G[name .. "High"]:SetText(string.format(fmt, maxV))
    local title = _G[name .. "Text"]
    s.Refresh = function()
        s.refreshing = true
        s:SetValue(get())
        title:SetText(text .. ": " .. string.format(fmt, get()))
        s.refreshing = false
    end
    s:SetScript("OnValueChanged", function(self, v)
        if self.refreshing then return end
        v = math.floor(v / step + 0.5) * step
        set(v)
        title:SetText(text .. ": " .. string.format(fmt, v))
    end)
    refreshers[#refreshers + 1] = s.Refresh
    y = y - 34
    return s
end

local function Button(parent, text, x, w, onClick, advance)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    Track(b, x, y)
    b:SetSize(w, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if advance then y = y - 32 end
    return b
end

-- Row of mutually exclusive choices drawn as check buttons
local function Radio(parent, labelText, key, choices)
    Label(parent, labelText)
    y = y - 22
    local boxes = {}
    local col = 0
    for _, ch in ipairs(choices) do
        local value, text = ch[1], ch[2]
        local cb = Check(parent, text, 16 + col * 150, function() return DB()[key] == value end,
            function() DB()[key] = value; for _, b in ipairs(boxes) do b.Refresh() end; Changed() end, false)
        boxes[#boxes + 1] = cb
        col = col + 1
        if col == 3 then col = 0; y = y - 26 end
    end
    if col ~= 0 then y = y - 26 end
end

local function OpenPicker(get, set)
    local r, g, b = unpack(get())
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = function() set({ ColorPickerFrame:GetColorRGB() }) end,
            cancelFunc = function(prev) set({ prev.r, prev.g, prev.b }) end,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame.func = function() set({ ColorPickerFrame:GetColorRGB() }) end
        ColorPickerFrame.cancelFunc = function(prev) set({ prev.r, prev.g, prev.b }) end
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function ColorRow(parent, text, key)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b:SetPoint("TOPLEFT", 20, y)
    Track(b, 20, y)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(); border:SetColorTexture(1, 1, 1, 1)
    local sw = b:CreateTexture(nil, "ARTWORK")
    sw:SetPoint("TOPLEFT", 2, -2); sw:SetPoint("BOTTOMRIGHT", -2, 2)
    b.Refresh = function() sw:SetColorTexture(unpack(DB()[key])) end
    b:SetScript("OnClick", function()
        OpenPicker(function() return DB()[key] end,
            function(c) DB()[key] = c; b.Refresh(); Changed() end)
    end)
    local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", b, "RIGHT", 8, 0)
    fs:SetText(text)
    refreshers[#refreshers + 1] = b.Refresh
    y = y - 30
end

local function BuildControls(parent)
    local scroll = CreateFrame("ScrollFrame", "ForeverLazy_OptionsScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(520, 1500)
    scroll:SetScrollChild(content)

    y = -10
    local t = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, y); t:SetText(TITLE)
    y = y - 30
    local intro = Label(content, "Never think about where to go next: arrows, a quest route planner, guides and collections.")
    y = y - 24

    sections, cur = {}, nil
    local function setAll(open)
        for _, s in ipairs(sections) do SetOpen(s.title, open) end
        Layout()
    end
    local b1 = Button(content, "Expand all", 16, 100, function() setAll(true) end, false)
    local b2 = Button(content, "Collapse all", 126, 100, function() setAll(false) end, true)
    shared.scroll, shared.content = scroll, content
    shared.top = { t, intro, b1, b2 }
    topY = y

    ----------------------------------------------------------------- Arrows
    ---------------------------------------------------------------- Modules
    Header(content, "Buttons in the game windows")
    Label(content, "Forever Lazy adds a search box and menu to the world map, buttons under the quest log, a craft plan beside your profession window, and more.")
    y = y - 22
    Check(content, "Show Forever Lazy buttons and panels in the game windows", 16,
        function() return DB().uiButtons ~= false end, function(v) DB().uiButtons = v end)
    Label(content, "The minimap button: left-click = Lazy Mode, right-click = the menu, shift-click = options.")
    y = y - 26

    Header(content, "Help")
    Button(content, "Take the tour", 16, 130, function() if addon.StartTour then addon.StartTour() end end, false)
    Button(content, "What's new", 156, 110, function() if addon.ShowWhatsNew then addon.ShowWhatsNew() end end, false)
    Button(content, "Export settings", 276, 130, function() if addon.ExportSettings then addon.ExportSettings() end end, false)
    Button(content, "Import settings", 416, 130, function() if addon.ImportSettings then addon.ImportSettings() end end, true)

    Header(content, "Presets")
    Label(content, "One click sets which modules are on. Change any of them below afterwards.")
    y = y - 22
    Button(content, "Minimal", 16, 90, function() if addon.ApplyPreset then addon.ApplyPreset("minimal") end end, false)
    Button(content, "Leveler", 116, 90, function() if addon.ApplyPreset then addon.ApplyPreset("leveler") end end, false)
    Button(content, "Duo", 216, 90, function() if addon.ApplyPreset then addon.ApplyPreset("duo") end end, false)
    Button(content, "Everything", 316, 110, function() if addon.ApplyPreset then addon.ApplyPreset("full") end end, true)

    Header(content, "Modules")
    Label(content, "Switch off the parts you do not want. A module that is off does nothing, and its commands say so.")
    y = y - 22
    for _, m in ipairs(addon.MODULES or {}) do
        Check(content, m[2], 16,
            function() return addon.ModuleOn(m[1]) end,
            function(v)
                local db = DB()
                db.modules = db.modules or {}
                db.modules[m[1]] = v and true or false
                if addon.ModulesChanged then addon.ModulesChanged() end
            end)
    end

    ---------------------------------------------------------------- Journey
    ---------------------------------------------------------------- Lazy mode
    Header(content, "Lazy mode")
    Label(content, "One press and the arrow points at the best next thing: vendor, trainer, your plan, or the next zone.")
    y = y - 22
    Button(content, "Do the next thing now", 16, 190, function() if addon.LazyNow then addon.LazyNow() end end, true)
    Check(content, "Keep going: pick the next thing by itself when I reach it", 16,
        function() return DB().lazyKeepGoing == true end, function(v) DB().lazyKeepGoing = v end)
    Label(content, "Also: /lazy now, the macro Lazy Now (/lazy macros), or a key under Key Bindings > Forever Lazy.")
    y = y - 26
    Header(content, "Journey")
    Label(content, "Which zones to level in, in order, from your level to 60. It is kept for each character.")
    y = y - 22
    Button(content, "Generate my journey", 16, 170, function() if addon.JourneyGenerate then addon.JourneyGenerate() end end, false)
    Button(content, "Regenerate", 196, 110, function() if addon.JourneyRegenerate then addon.JourneyRegenerate() end end, false)
    Button(content, "Show it", 316, 90, function() if addon.JourneyShow then addon.JourneyShow() end end, true)
    Check(content, "Include dungeons that fit each stretch", 16,
        function() return DB().journeyDungeons ~= false end, function(v) DB().journeyDungeons = v end)
    Check(content, "Tell me when I have outgrown a stop and where to go next", 16,
        function() return DB().journeyHint ~= false end, function(v) DB().journeyHint = v end)

    ----------------------------------------------------------------- Arrows
    Header(content, "Arrows")
    Check(content, "Simple arrows: one main arrow (plus the ghost and follow arrows). Everything else shows on the compass.", 16,
        function() return DB().simpleArrows ~= false end, function(v) DB().simpleArrows = v; Changed() end)
    Radio(content, "Arrow style:", "style", {
        { "minimap", "Classic" }, { "chevron", "Chevron" }, { "thick", "Thick" } })
    ColorRow(content, "Route plan arrow color", "colorWaypoint")
    ColorRow(content, "My quests arrow color", "colorMine")
    Slider(content, "Arrow size", 0.5, 3, 0.1, "%.1f", function() return DB().scale end,
        function(v) DB().scale = v; Changed() end)
    Slider(content, "Arrow opacity", 0.2, 1, 0.05, "%.2f", function() return DB().alpha end,
        function(v) DB().alpha = v; Changed() end)
    Slider(content, "Count as arrived within (yards)", 3, 40, 1, "%d", function() return DB().arrival end,
        function(v) DB().arrival = v end)
    Check(content, "Lock positions (uncheck to drag arrows and panel)", 16,
        function() return DB().locked end, function(v) DB().locked = v end)

    ---------------------------------------------------------------- Display
    Header(content, "Text")
    Check(content, "Show quest / player name under arrow", 16,
        function() return DB().showText end, function(v) DB().showText = v end)
    Check(content, "Show distance", 16, function() return DB().showDistance end, function(v) DB().showDistance = v end)
    Radio(content, "Distance units:", "units", { { "yd", "Yards" }, { "m", "Meters" }, { "steps", "Steps" } })

    ---------------------------------------------------------------- Alerts
    Header(content, "Alerts")
    Check(content, "Sound when I arrive at the quest spot", 16,
        function() return DB().arrivalSound end, function(v) DB().arrivalSound = v end)

    ------------------------------------------------------------- Visibility
    Header(content, "Hide arrows")
    Check(content, "In combat", 16, function() return DB().hideCombat end, function(v) DB().hideCombat = v end)
    Check(content, "In cities and inns (resting)", 16,
        function() return DB().hideResting end, function(v) DB().hideResting = v end)
    Check(content, "On a flight path", 16, function() return DB().hideTaxi end, function(v) DB().hideTaxi = v end)
    Check(content, "Inside a dungeon or raid (the ghost arrow to your corpse still shows)", 16,
        function() return DB().hideInstance ~= false end, function(v) DB().hideInstance = v end)

    ------------------------------------------------------------- Following
    Check(content, "When I am a ghost, point the arrow at my corpse (other arrows hide)", 16,
        function() return DB().ghostArrow ~= false end, function(v) DB().ghostArrow = v end)

    ------------------------------------------------- RestedXP friend (optional)
    -- everything that needs a friend running RestedXP lives here; the rest of the addon works without it
    Header(content, "RestedXP friend (optional)")
    Label(content, "Only for following a friend who runs RestedXP. Nothing else in the addon needs it.")
    y = y - 22
    Check(content, "Listen to a friend's RestedXP steps", 16,
        function() return DB().rxpListen ~= false end, function(v) DB().rxpListen = v; Changed() end)
    Radio(content, "Arrows shown:", "mode", {
        { "both", "Quest + friend" }, { "quest", "Quest only" }, { "friend", "Friend only" }, { "off", "Off" } })
    ColorRow(content, "Friend's quest arrow color", "colorQuest")
    ColorRow(content, "Friend arrow color", "colorFriend")
    Slider(content, "Extra quest arrows (nearest other targets)", 0, 2, 1, "%d", function() return DB().extraTargets end,
        function(v) DB().extraTargets = v end)
    Check(content, "Show friend's current step in a box", 16,
        function() return DB().showPanel end, function(v) DB().showPanel = v end)
    Slider(content, "Step panel size", 0.5, 2, 0.1, "%.1f", function() return DB().panelScale end,
        function(v) DB().panelScale = v; Changed() end)
    Check(content, "Show earlier steps in the step panel", 16,
        function() return DB().showHistory end, function(v) DB().showHistory = v; Changed() end)
    Check(content, "Chat message when friend's step changes", 16,
        function() return DB().alertChat end, function(v) DB().alertChat = v end)
    Check(content, "Sound when friend's step changes", 16,
        function() return DB().alertSound end, function(v) DB().alertSound = v end)
    Check(content, "Keep pointing at friend's last seen spot when too far away", 16,
        function() return DB().followLastSeen end, function(v) DB().followLastSeen = v end)
    Check(content, "Warn me if my friend hasn't moved for 3 minutes", 16,
        function() return DB().stuckAlert end, function(v) DB().stuckAlert = v end)
    Label(content, "Several friends: right-click the step panel to switch, /lazy friend <name> to pin.")
    y = y - 26

    Header(content, "My own quests")
    Check(content, "Show an arrow for my own quest log (turn-ins and objectives)", 16,
        function() return DB().ownQuests end, function(v) DB().ownQuests = v; Changed() end)
    Check(content, "Skip grey quests, and red ones unless they are just a turn-in", 16,
        function() return DB().questColorFilter ~= false end,
        function(v) DB().questColorFilter = v; Changed() end)
    Check(content, "Follow the quest I have selected or tracked (otherwise the nearest of all)", 16,
        function() return DB().ownFocus ~= false end, function(v) DB().ownFocus = v; Changed() end)
    ColorRow(content, "My quests arrow color", "colorMine")
    Button(content, "Plan my route (replaces waypoints)", 16, 240, function() addon:PlanRoute() end, true)
    Label(content, "Same as /lazy plan. Orders your quest spots into a walking route, one waypoint each.")
    y = y - 26
    Check(content, "Plan for XP: do the quests that give the most XP for the walking first", 16,
        function() return DB().planXP ~= false end, function(v) DB().planXP = v end)
    Check(content, "Keep the plan to the zone I'm in (/lazy plan all ignores this)", 16,
        function() return DB().planZoneOnly ~= false end, function(v) DB().planZoneOnly = v end)
    Check(content, "Leave grey (too low level) quests out of the plan", 16,
        function() return DB().planSkipGrey ~= false end, function(v) DB().planSkipGrey = v end)
    Check(content, "When I take a new quest, add it to the plan where it costs the least walking", 16,
        function() return DB().planAuto ~= false end, function(v) DB().planAuto = v end)

    Header(content, "Hunter pet")
    Check(content, "Remind me when my pet needs feeding", 16,
        function() return DB().petRemind ~= false end, function(v) DB().petRemind = v end)
    Check(content, "Only remind when it is unhappy (not when it is just content)", 16,
        function() return DB().petOnlyUnhappy == true end, function(v) DB().petOnlyUnhappy = v end)
    Check(content, "Also remind me when I have no pet out or it is dead", 16,
        function() return DB().petMissing == true end, function(v) DB().petMissing = v end)
    Check(content, "Play a sound with the reminder", 16,
        function() return DB().petSound == true end, function(v) DB().petSound = v end)
    Check(content, "Hunters: warn me when I am low on arrows or bullets", 16,
        function() return DB().ammoRemind ~= false end, function(v) DB().ammoRemind = v end)
    Check(content, "Hunters: tell me when a better kind of ammo opens up for my level", 16,
        function() return DB().ammoUpgrade ~= false end, function(v) DB().ammoUpgrade = v end)
    Slider(content, "Warn me below this much ammo", 50, 1000, 50, "%d", function() return DB().ammoLow or 200 end,
        function(v) DB().ammoLow = v end)
    Check(content, "Scream FEED ME!!! across the screen when my pet is hungry", 16,
        function() return DB().petScream ~= false end, function(v) DB().petScream = v end)
    Button(content, "Test the pet reminder", 16, 170, function() addon:HandleExtraCommand("pet", "test") end, true)

    Header(content, "Extras")
    Check(content, "Animate arrows (pulse when near, dim when facing away)", 16,
        function() return DB().animate end, function(v) DB().animate = v end)
    Check(content, "Flight timer: show how long a flight takes (learns each route the first time)", 16,
        function() return DB().flightTimer ~= false end, function(v) DB().flightTimer = v end)
    Check(content, "Suggest the next zone when I have outgrown the one I am in", 16,
        function() return DB().nextZoneHint ~= false end, function(v) DB().nextZoneHint = v end)
    Check(content, "Tell me when I reach a dungeon entrance my quests need", 16,
        function() return DB().dungeonHint ~= false end, function(v) DB().dungeonHint = v end)
    Check(content, "Cozy Sleeping Bag chain: guide me, and make its next spot stop 1 in the zone it is in", 16,
        function() return DB().bagGuide ~= false end, function(v) DB().bagGuide = v end)
    Check(content, "Tell me when a new class quest opens up", 16,
        function() return DB().classAlert ~= false end, function(v) DB().classAlert = v end)
    Check(content, "Put class quest givers in my plan when they are in this zone", 16,
        function() return DB().planClass ~= false end, function(v) DB().planClass = v end)
    Check(content, "Draw my plan's route on the world map", 16,
        function() return DB().mapRoute ~= false end, function(v) DB().mapRoute = v; if addon.DrawRouteLines then addon.DrawRouteLines() end end)
    Slider(content, "Levelling guide text size (for the couch and TV, 1.8 is big)", 0.8, 2.6, 0.1, "%.1f", function() return DB().guideScale or 1 end,
        function(v) DB().guideScale = v; if _G.ForeverLazy_Guide and _G.ForeverLazy_Guide:IsShown() then _G.ForeverLazy_Guide:SetScale(v) end end)
    Check(content, "Item tooltips say how many I have in my bags, bank, mail and worn", 16,
        function() return DB().itemTooltip ~= false end, function(v) DB().itemTooltip = v end)
    Check(content, "... and how many my other characters have", 16,
        function() return DB().itemTooltipAlts ~= false end, function(v) DB().itemTooltipAlts = v end)
    Check(content, "Show XP hot spots on the world map (where the quests worth doing for my level are)", 16,
        function() return DB().xpHeat == true end, function(v) DB().xpHeat = v; if addon.DrawXPHeat then addon.DrawXPHeat() end end)
    Check(content, "Draw my route on the minimap (numbered stops joined in order)", 16,
        function() return DB().minimapLine ~= false end, function(v) DB().minimapLine = v end)
    Check(content, "Offer to plan a new zone once I have stayed in it a while", 16,
        function() return DB().zonePrompt ~= false end, function(v) DB().zonePrompt = v end)
    Check(content, "Share boat docks I teach with my guild and group (hidden addon messages, nothing shows in chat)", 16,
        function() return DB().community == true end, function(v) DB().community = v end)
    Check(content, "When I open a profession window, tell me the best next craft", 16,
        function() return DB().craftHint ~= false end, function(v) DB().craftHint = v end)
    Check(content, "Show a button for quest items I need to use", 16,
        function() return DB().questItemButton ~= false end, function(v) DB().questItemButton = v; if addon.RefreshQuestItems then addon.RefreshQuestItems() end end)
    Check(content, "Tell me what comes next after I hand in a quest in a chain", 16,
        function() return DB().chainHint ~= false end, function(v) DB().chainHint = v end)
    Check(content, "Mark the best quest reward (likely upgrade, or highest vendor price)", 16,
        function() return DB().rewardPick ~= false end, function(v) DB().rewardPick = v end)
    Check(content, "Leave group quests out of my plan while I am solo", 16,
        function() return DB().planSkipGroup ~= false end, function(v) DB().planSkipGroup = v end)
    Check(content, "Favour quests I share with someone in my group", 16,
        function() return DB().planShared ~= false end, function(v) DB().planShared = v end)
    Check(content, "Tell me when my hearthstone would save a long walk", 16,
        function() return DB().hearthNudge ~= false end, function(v) DB().hearthNudge = v end)
    Check(content, "In duo mode, show my partner on the compass (even when the arrows are off)", 16,
        function() return DB().duoCompass ~= false end, function(v) DB().duoCompass = v end)
    Radio(content, "Marker for my partner on the compass:", "compassIcon", {
        { 3, "Diamond" }, { 1, "Star" }, { 2, "Circle" }, { 4, "Triangle" }, { 5, "Moon" } })
    Check(content, "Compass bar at the top of the screen", 16,
        function() return DB().compassBar end, function(v) DB().compassBar = v end)
    Check(content, "Accept waypoints my party sends me", 16,
        function() return DB().acceptShared end, function(v) DB().acceptShared = v end)
    Label(content, "Shift + click the friend arrow to tell the party 'On my way!'.")
    y = y - 26
    Button(content, "Run self-test", 16, 120, function() addon:RunSelfTest() end, false)
    Button(content, "Share waypoint", 146, 120, function() addon:ShareWaypoint() end, false)
    Button(content, "Export", 276, 80, function() addon:OpenIO("export") end, false)
    Button(content, "Import", 366, 80, function() addon:OpenIO("import") end, true)
    Label(content, "Routes: /lazy route save|load|delete <name>.  Profiles: /lazy profile list|new|use|delete.")
    y = y - 26

    Header(content, "My waypoints")
    Label(content, "Set one with /lazy way <x> <y> [name], /lazy way here, or Ctrl + right-click on the world map.")
    y = y - 26
    ColorRow(content, "Waypoint arrow color", "colorWaypoint")
    Check(content, "Remove a waypoint automatically when I arrive", 16,
        function() return DB().waypointAutoClear end, function(v) DB().waypointAutoClear = v end)
    Button(content, "Drop at my position", 16, 150, function() addon:DropWaypointHere() end, false)
    Button(content, "Skip active", 176, 110, function() addon:RemoveWaypoint(1) end, false)
    Button(content, "Clear all", 296, 100, function() addon:ClearWaypoints() end, true)
    Label(content, "List them with /lazy way list, make one active with /lazy way <number>.")
    y = y - 26

    Header(content, "Library books")
    Label(content, "Sets a waypoint for every known library book, nearest first. Replaces your current waypoints.")
    y = y - 26
    Check(content, "Tell me in chat when I enter a zone that has books", 16,
        function() return DB().bookAlert ~= false end, function(v) DB().bookAlert = v end)
    Check(content, "Automatically add that zone's books as waypoints (keeps my other waypoints)", 16,
        function() return DB().bookAuto == true end, function(v) DB().bookAuto = v end)
    Check(content, "Leave out zones that are too high for my level (All books and auto)", 16,
        function() return DB().bookLevelFilter ~= false end, function(v) DB().bookLevelFilter = v end)
    Check(content, "Show every book on the world map (book = to find, green tick = collected)", 16,
        function() return DB().bookPins ~= false end,
        function(v) DB().bookPins = v; if addon.RefreshBookPins then addon.RefreshBookPins() end end)
    Button(content, "Mark nearest as collected", 16, 190, function() addon:HandleExtraCommand("books", "done") end, false)
    Button(content, "Mark nearest as not collected", 216, 210, function() addon:HandleExtraCommand("books", "undone") end, false)
    Button(content, "Clear collected list", 436, 150, function() addon:HandleExtraCommand("books", "reset") end, true)
    Button(content, "This zone (even collected)", 16, 190, function() addon:HandleExtraCommand("books", "zone all") end, true)
    Button(content, "All books", 16, 100, function() addon:HandleExtraCommand("books", "") end, false)
    Button(content, "This zone only", 126, 130, function() addon:HandleExtraCommand("books", "zone") end, false)
    Button(content, "Go to librarian", 266, 130, function() addon:HandleExtraCommand("books", "turnin") end, false)
    Button(content, "List books", 406, 100, function() addon:HandleExtraCommand("books", "list") end, true)
    Button(content, "Offer route to party", 16, 160, function() addon:HandleExtraCommand("books", "share") end, false)
    Button(content, "Post this zone in party chat", 186, 190, function() addon:HandleExtraCommand("books", "say") end, true)
    Label(content, "Offer: party members with this addon get a prompt to load it. Post: plain /way lines anyone can use.")
    y = y - 26
    Label(content, "Same as /lazy books, books zone, books turnin, books list, books share, books say, books accept.")
    y = y - 26

    Header(content, "Map pins")
    Check(content, "Quest pins on the world map", 16,
        function() return DB().mapPins end, function(v) DB().mapPins = v; Changed() end)
    Check(content, "Quest pins on the minimap", 16,
        function() return DB().minimapPins end, function(v) DB().minimapPins = v; Changed() end)
    Check(content, "Also set a TomTom waypoint (needs TomTom)", 16,
        function() return DB().tomtom end, function(v) DB().tomtom = v; Changed() end)
    Check(content, "Show minimap button", 16,
        function() return DB().minimapButton end, function(v) DB().minimapButton = v; Changed() end)

    -------------------------------------------------------------- Profiles
    Header(content, "Settings")
    Check(content, "Use separate settings for this character", 16,
        function() return addon.GetRoot().useChar end,
        function(v)
            addon.GetRoot().useChar = v
            addon:SelectProfile()
            Changed()
            Refresh()
        end)

    y = y - 6
    Button(content, "Reset positions", 16, 130, function()
        local d = DB()
        d.pos = {}
        for k, v in pairs(addon.DEFAULTS.pos) do d.pos[k] = { point = v.point, x = v.x, y = v.y } end
        Changed()
    end, false)
    Button(content, "Test quest arrow", 156, 130, function()
        addon:SetStepText(nil, "Accept Buzzbox 827")
        addon.Print("simulated step: Accept Buzzbox 827")
    end, false)
    Button(content, "Test kill arrow", 296, 130, function()
        addon:SetStepText(nil, "Kill Mottled Boar")
        addon.Print("simulated step: Kill Mottled Boar")
    end, true)

    Label(content, "Slash commands: /lazy (opens this), /lazy status, /lazy test <text>")
    y = y - 30
    cur.bodyEnd = y

    -- one long page with fold-away groups (used when the Settings window has no sub-categories)
    Layout = function()
        shared.split = false
        for _, w in ipairs(shared.top) do w:Show() end
        local pos = topY
        for _, s in ipairs(sections) do
            local open = IsOpen(s.title)
            pos = pos - 12
            s.header:Show()
            s.header:ClearAllPoints()
            s.header:SetPoint("TOPLEFT", 16, pos)
            s.header.fs:SetText((open and "[-]  " or "[+]  ") .. s.title)
            local body = pos - 26
            for _, it in ipairs(s.items) do
                if open then
                    it.obj:ClearAllPoints()
                    it.obj:SetPoint("TOPLEFT", it.x, body + it.y)
                    it.obj:Show()
                else
                    it.obj:Hide()
                end
            end
            pos = open and (body - (s.bodyY - s.bodyEnd)) or body
        end
        content:SetHeight(-pos + 10)
    end
end

-- one group at a time, each shown on its own page in the Settings list
local function LayoutSplit(sec)
    shared.split = true
    for _, w in ipairs(shared.top) do w:Hide() end
    for _, s in ipairs(sections) do
        if s == sec then
            s.header:Show()
            s.header:ClearAllPoints()
            s.header:SetPoint("TOPLEFT", 16, -10)
            s.header.fs:SetText(s.title)
            local body = -10 - 26
            for _, it in ipairs(s.items) do
                it.obj:ClearAllPoints()
                it.obj:SetPoint("TOPLEFT", it.x, body + it.y)
                it.obj:Show()
            end
            shared.content:SetHeight(-(body - (s.bodyY - s.bodyEnd)) + 10)
        else
            s.header:Hide()
            for _, it in ipairs(s.items) do it.obj:Hide() end
        end
    end
end

-- put the shared scrolling page onto a Settings page and show the right group
local function AttachTo(page, sec)
    local scroll = shared.scroll
    scroll:SetParent(page)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    scroll:Show()
    if sec then LayoutSplit(sec) else Layout() end
    scroll:SetVerticalScroll(0)
    Refresh()
end

local function Build()
    if built then return end
    built = true
    panel = CreateFrame("Frame", "ForeverLazy_OptionsPanel")
    panel:Hide()      -- a new frame counts as shown; the Settings window needs to Show() it to fire OnShow
    panel.name = TITLE
    BuildControls(panel)
    panel:SetScript("OnShow", function() AttachTo(panel, nil) end)

    if _G.Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
        Settings.RegisterAddOnCategory(category)

        -- every group gets its own entry under the addon name in the list on the left
        if Settings.RegisterCanvasLayoutSubcategory and #sections > 1 then
            local ok = pcall(function()
                for i = 2, #sections do
                    local sec = sections[i]
                    local page = CreateFrame("Frame")
                    page:Hide()
                    page.name = sec.title
                    page:SetScript("OnShow", function(self) AttachTo(self, sec) end)
                    Settings.RegisterCanvasLayoutSubcategory(category, page, sec.title)
                end
            end)
            if ok then
                panel:SetScript("OnShow", function() AttachTo(panel, sections[1]) end)
            end
        end
    elseif _G.InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function addon:OpenOptions()
    Build()
    if category and Settings and Settings.OpenToCategory then
        local id = category.GetID and category:GetID() or category.ID
        if pcall(Settings.OpenToCategory, id) then return end
    end
    if _G.InterfaceOptionsFrame_OpenToCategory and not category then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
        return
    end
    if not standalone then
        standalone = CreateFrame("Frame", "ForeverLazy_OptionsWindow", UIParent, "BasicFrameTemplateWithInset")
        standalone:SetSize(560, 560)
        standalone:SetPoint("CENTER")
        standalone:SetMovable(true)
        standalone:EnableMouse(true)
        standalone:RegisterForDrag("LeftButton")
        standalone:SetScript("OnDragStart", standalone.StartMoving)
        standalone:SetScript("OnDragStop", standalone.StopMovingOrSizing)
        if standalone.TitleText then standalone.TitleText:SetText(TITLE) end
        panel:SetParent(standalone)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", 4, -24)
        panel:SetPoint("BOTTOMRIGHT", -4, 4)
        tinsert(UISpecialFrames, "ForeverLazy_OptionsWindow")
        -- the stand-alone window shows everything on one page with fold-away groups
        panel:SetScript("OnShow", function() AttachTo(panel, nil) end)
    end
    standalone:SetShown(not standalone:IsShown())
    panel:Show()
    AttachTo(panel, nil)
end

--------------------------------------------------------------------------------
-- Macros the addon makes for you (account-wide, find them with /macro)
--------------------------------------------------------------------------------
local MACROS = {
    { name = "Lazy Plan",       body = "/lazy plan",        icon = "INV_Misc_Map_01" },
    { name = "Lazy Now",        body = "/lazy now",         icon = "Ability_Tracking" },
    { name = "Lazy Next",       body = "/lazy way next",    icon = "INV_Misc_Note_01" },
    { name = "Lazy Arrows",     body = "/lazy toggle",      icon = "Ability_Hunter_SniperShot" },
    { name = "Lazy Books",      body = "/lazy books",       icon = "INV_Misc_Book_09" },
    { name = "Lazy Book Arrow", body = "/lazy arrow",       icon = "INV_Misc_Book_11" },
    { name = "Lazy Share",      body = "/lazy books share", icon = "INV_Letter_02" },
}

function addon.MakeMacros()
    local say = addon.Print or print
    if InCombatLockdown and InCombatLockdown() then say("macros can't be made in combat, try /lazy macros again after the fight"); return end
    if not (CreateMacro and GetMacroIndexByName) then return end
    local made, updated = 0, 0
    for _, m in ipairs(MACROS) do
        local idx = GetMacroIndexByName(m.name)
        if not (idx and idx > 0) then
            -- an older version called these "LRXP ..."; rename it instead of making a second copy
            local oldIdx = GetMacroIndexByName((m.name:gsub("^Lazy ", "LRXP ")))
            if oldIdx and oldIdx > 0 and EditMacro then
                EditMacro(oldIdx, m.name, nil, m.body)
                idx = oldIdx
            end
        end
        if idx and idx > 0 then
            local _, icon, body = GetMacroInfo(idx)
            if body ~= m.body then
                EditMacro(idx, m.name, nil, m.body)
                updated = updated + 1
            end
            -- only swap the question mark, so an icon you picked yourself stays
            if icon == 134400 or icon == "INV_Misc_QuestionMark" or (type(icon) == "string" and icon:find("QuestionMark")) then
                if not pcall(EditMacro, idx, m.name, m.icon, m.body) then pcall(EditMacro, idx, m.name, "Interface\\Icons\\" .. m.icon, m.body) end
            end
        else
            local account = GetNumMacros()
            if account >= (_G.MAX_ACCOUNT_MACROS or 120) then say("your macro list is full, some macros were not made"); break end
            if not pcall(CreateMacro, m.name, m.icon, m.body, false) then       -- false: shared by all characters
                CreateMacro(m.name, 134400, m.body, false)
            end
            made = made + 1
        end
    end
    say(string.format("macros ready: %d new, %d updated. Drag them from /macro to your action bars: %s", made, updated,
        "Lazy Plan, Next, Arrows, Books, Book Arrow, Share"))
end

function addon.RemoveMacros()
    local say = addon.Print or print
    if InCombatLockdown and InCombatLockdown() then say("not in combat, please"); return end
    local n = 0
    for _, m in ipairs(MACROS) do
        local idx = GetMacroIndexByName and GetMacroIndexByName(m.name)
        if idx and idx > 0 then DeleteMacro(idx); n = n + 1 end
    end
    say(string.format("%d addon macro%s removed", n, n == 1 and "" or "s"))
end

--------------------------------------------------------------------------------
-- Welcome pop-up, the very first time the addon loads
--------------------------------------------------------------------------------
-- A custom window instead of the plain pop-up, so it can carry a picture.
-- The photo is media\kinison.tga (credit in media\CREDITS.txt: CC BY-SA 2.0, The World Famous Comedy Store).
local welcomeFrame
local function ShowWelcome()
    if not welcomeFrame then
        local f = CreateFrame("Frame", "ForeverLazy_Welcome", UIParent)
        f:SetSize(400, 520)
        f:SetPoint("CENTER", 0, 20)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.97)

        local pic = f:CreateTexture(nil, "ARTWORK")
        pic:SetSize(135, 215)
        pic:SetPoint("TOP", 0, -16)
        pic:SetTexture("Interface\\AddOns\\ForeverLazy\\media\\kinison.tga")
        pic:SetTexCoord(60 / 256, 195 / 256, 20 / 256, 235 / 256)

        local caption = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        caption:SetPoint("TOP", pic, "BOTTOM", 0, -8)
        caption:SetText("|cffff3333OH Oh OHH|r")

        local by = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        by:SetPoint("TOP", caption, "BOTTOM", 0, -6)
        by:SetText("Brought to you by Sam Skinison")

        local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOP", by, "BOTTOM", 0, -14)
        text:SetWidth(360); text:SetJustifyH("CENTER")
        text:SetText("|cff4db8ffWelcome to Forever Lazy!|r\n\n"
            .. "Arrows that point at your quests, your party and your next best XP. Click OK to open the options, "
            .. "where you can turn features on and off, and take a quick tour of the buttons.\n\n"
            .. "I have also added a few shared macros (type |cffffd100/macro|r and look for |cffffd100Lazy|r) that you can drag to your action bars.\n\n"
            .. "|cffaaaaaaTip: |cffffd100/lazy now|r|cffaaaaaa (or left-click the minimap button) points at the best next thing, and |cffffd100/lazy|r|cffaaaaaa opens the options any time.|r")

        local credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        credit:SetPoint("BOTTOM", 0, 46)
        credit:SetText("Photo: The World Famous Comedy Store, CC BY-SA 2.0 (via Wikimedia Commons)")

        local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ok:SetSize(110, 24); ok:SetPoint("BOTTOM", 0, 14); ok:SetText(OKAY or "OK")
        ok:SetScript("OnClick", function()
            f:Hide()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.2, function() addon:OpenOptions() end)
                C_Timer.After(1.5, function() if addon.StartTour then addon.StartTour() end end)
            else
                addon:OpenOptions()
            end
        end)
        table.insert(UISpecialFrames, "ForeverLazy_Welcome")
        f:Hide()
        welcomeFrame = f
    end
    welcomeFrame:Show()
end
addon.ShowWelcome = ShowWelcome

local welcome = CreateFrame("Frame")
pcall(welcome.RegisterEvent, welcome, "PLAYER_ENTERING_WORLD")
welcome:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(4, function()
        local root = addon.GetRoot and addon.GetRoot()
        if not root or root.welcomed then return end
        if InCombatLockdown and InCombatLockdown() then
            -- not in the middle of a fight: try again after the next loading screen
            pcall(welcome.RegisterEvent, welcome, "PLAYER_ENTERING_WORLD")
            return
        end
        root.welcomed = true
        if root.autoMacros ~= false then pcall(addon.MakeMacros) end
        ShowWelcome()
    end)
end)

-- macros made by an older version are renamed once, on login, so no "LRXP ..." titles are left
local renamer = CreateFrame("Frame")
pcall(renamer.RegisterEvent, renamer, "PLAYER_ENTERING_WORLD")
renamer:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if not C_Timer or not C_Timer.After or not GetMacroIndexByName then return end
    C_Timer.After(6, function()
        if InCombatLockdown and InCombatLockdown() then return end
        local root = addon.GetRoot and addon.GetRoot()
        if root and root.autoMacros == false then return end
        for _, m in ipairs(MACROS) do
            local old = m.name:gsub("^Lazy ", "LRXP ")
            if (GetMacroIndexByName(old) or 0) > 0 then pcall(addon.MakeMacros); return end
            local idx = GetMacroIndexByName(m.name) or 0
            if idx > 0 then
                local _, icon = GetMacroInfo(idx)
                if icon == 134400 then pcall(addon.MakeMacros); return end
            end
        end
    end)
end)

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Options.lua"] = true end end
