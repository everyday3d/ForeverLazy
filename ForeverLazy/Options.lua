-- Options panel for Forever Lazy
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon

local TITLE = "Forever Lazy"
local panel, standalone, category
local built = false
local refreshers = {}

local function DB() return addon.GetDB() end
-- a switch that is ON by default is stored as nil (on) or false (off). NOTE: 'v and nil or false' is always false, so it can never turn a switch back on.
local function OffFlag(v) if v then return nil end return false end
local function Changed() addon:ApplyAll() end

local function Refresh() for _, r in ipairs(refreshers) do r() end end
addon.RefreshOptions = Refresh

-- layout cursor
local y

-- Pages: every control made after a Header belongs to that subheading, and PAGES says which page a subheading is on (a title
-- used by several Headers is shown once, with all their controls). Inside a subheading the controls are kept in blocks (one
-- setting and what belongs to it), so the search box can show just the settings that match.
local PAGES = {
    { "Start here", { "Start here", "Help", "Settings", "Buttons in the game windows" } },
    { "Arrow and plan", { "Arrows", "My quest arrow", "The plan", "Hide arrows", "Travel and zones", "Journey", "Lazy mode", "My waypoints", "Text" } },
    { "Compass", { "Compass", "Compass size and place", "Hide the compass" } },
    { "Quests and map", { "Quest map", "Map pins", "Quest tracker", "Finding quests", "Quest hints", "Dungeons and class quests", "Quest sounds", "Library books" } },
    { "Combat", { "Nameplates", "Damage meter", "Gear", "Action bars" } },
    { "My class", { "Class options", "Paladin blessings", "Hunter pet", "Totems", "Shaman buffs", "Shaman helpers" } },
    { "Bags and items", { "Bags", "Selling and looting", "Item tooltips", "Crafting", "Ore and herb nodes" } },
    { "Chat and groups", { "Chat", "Sharing and party", "The Hive" } },
    { "Extras", { "Couch mode", "Alerts", "Talents and skills", "Pedometer" } },
    { "Advanced", { "Modules", "Quest data", "RestedXP friend (optional)" } },
}
local sections = {}
local shared = {}    -- the one scrolling page and its content
local cur            -- subheading being built
local topY           -- where the first subheading starts
local Layout         -- defined in BuildControls
local holding = false -- true while several controls are being made that belong to one block
local query = ""     -- what is typed in the search box

-- a block starts at the cursor and holds one setting
local function NewBlock(kind)
    if not cur or holding then return end
    cur.blocks[#cur.blocks + 1] = { kind = kind, top = y, items = {} }
end

local function Track(obj, x, yy, text)
    if not cur then return end
    if #cur.blocks == 0 then NewBlock("label") end
    local block = cur.blocks[#cur.blocks]
    local item = { obj = obj, x = x, y = yy - block.top, text = text }
    block.items[#block.items + 1] = item
    return item
end

-- how wide the page is: the game's Settings window and my own window differ
local function PageWidth(w)
    if type(w) ~= "number" or w < 200 then return 520 end
    return math.max(480, math.min(720, w))
end

local function TextHeight(fs)
    local h = fs and fs.GetStringHeight and fs:GetStringHeight()
    return type(h) == "number" and h or 0
end

-- Wraps a block's long text to the page and says how much lower each of its controls has to go, and how much taller the block
-- gets. The room made for a text when it was written is the space down to the next control under it.
local function Wrap(block, height, width)
    local shift, down = 0, {}
    for n, it in ipairs(block.items) do
        down[n] = shift
        if it.wrap then
            it.wrap:SetWidth(width - it.x - (it.indent or 0) - 8)
            local need, room = TextHeight(it.wrap), nil
            if it.indent then
                room = 16                                      -- one line beside a tick box
            else
                local nextY = -height
                for m = n + 1, #block.items do
                    local other = block.items[m].y
                    if other < it.y and other > nextY then nextY = other end
                end
                room = it.y - nextY
                need = need + 6
            end
            if need > room then shift = shift + (need - room) end
        end
    end
    return down, shift
end

-- every word typed has to be somewhere in the text
local function Matches(haystack, words)
    haystack = haystack:lower()
    for w in words:lower():gmatch("%S+") do
        if not haystack:find(w, 1, true) then return false end
    end
    return true
end

local function BlockText(block)
    local parts = {}
    for _, it in ipairs(block.items) do
        local t = it.text
        if (not t or t == "") and it.obj.GetText then t = it.obj:GetText() end
        if type(t) == "string" then parts[#parts + 1] = t end
    end
    -- colour codes are not words
    return (table.concat(parts, " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- groups that belong to one module: they are hidden while that module is switched off
local SECTION_MODULE = {
    ["Lazy mode"] = "lazymode",
    ["Journey"] = "zones",
    ["Hunter pet"] = "pet",
    ["Ore and herb nodes"] = "gather",
    ["Library books"] = "books",
    ["Gear"] = "gear",
}
-- subheadings made for one class: they only show on that class, unless "show every class" is ticked
local SECTION_CLASS = {
    ["Paladin blessings"] = "PALADIN",
    ["Hunter pet"] = "HUNTER",
    ["Totems"] = "SHAMAN",
    ["Shaman buffs"] = "SHAMAN",
    ["Shaman helpers"] = "SHAMAN",
}
local function OtherClass(title)
    local c = SECTION_CLASS[title]
    if not c or DB().optAllClasses == true then return false end
    local _, mine = UnitClass("player")
    return mine ~= c
end

local function SectionModuleOff(s)
    if OtherClass(s.title) then return true end
    local m = SECTION_MODULE[s.title]
    return m ~= nil and addon.ModuleOn and not addon.ModuleOn(m)
end

-- what to show: { { page =, title =, parts = { { section, blocks } } } }. With words typed it looks through every page and
-- keeps the settings that match (or everything under a subheading whose name matches); without, it is the page picked.
local function Plan(pageName, words)
    local searching = words:match("%S") ~= nil
    local out = {}
    for _, page in ipairs(PAGES) do
        if searching or page[1] == pageName then
            for _, title in ipairs(page[2]) do
                local entry = { page = page[1], title = title, parts = {} }
                for _, s in ipairs(sections) do
                    if s.title == title and not SectionModuleOff(s) then
                        local whole = not searching or Matches(L(title), words)
                        local blocks = {}
                        for i, block in ipairs(s.blocks) do
                            if whole or Matches(BlockText(block), words) then blocks[#blocks + 1] = i end
                        end
                        if #blocks > 0 then entry.parts[#entry.parts + 1] = { s, blocks } end
                    end
                end
                if #entry.parts > 0 then out[#out + 1] = entry end
            end
        end
    end
    return out
end

local function CurrentPage()
    local want = DB().optPage
    for _, p in ipairs(PAGES) do if p[1] == want then return want end end
    return PAGES[1][1]
end

local function Header(parent, text)
    if cur then cur.bodyEnd = y end
    y = y - 12
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(480, 24)
    b:SetPoint("TOPLEFT", 16, y)
    b.fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    b.fs:SetPoint("LEFT", 0, 0)
    b:Hide()
    y = y - 26
    cur = { title = text, header = b, bodyY = y, blocks = {} }
    sections[#sections + 1] = cur
end

local function Label(parent, text, x)
    NewBlock("label")
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x or 16, y)
    fs:SetText(text)
    local item = Track(fs, x or 16, y)
    fs:SetJustifyH("LEFT")
    if item then item.wrap = fs end
    return fs
end

-- hovering a tick box or a slider says what it does. extra: a line for the state it is in now
local function HoverTip(obj, title, about, state)
    obj:SetScript("OnEnter", function(self)
        local text = about()
        if not (text and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local short = tostring(title):gsub("^%.%.%.%s*", ""):gsub("%s*[:(].*$", "")
        GameTooltip:AddLine(short, 1, 0.82, 0, true)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        if state then GameTooltip:AddLine(state(self), 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    obj:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local checkId = 0
local radioLabel                -- the question the radio choices being made answer
local noConfirm = false
local function Check(parent, text, x, get, set, advance)
    checkId = checkId + 1
    local quiet = noConfirm
    local name = "ForeverLazy_Check" .. checkId
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x or 16, y)
    NewBlock("check")
    local item = Track(cb, x or 16, y, text)
    local fs = _G[name .. "Text"]
    if fs then fs:SetText(text) end
    -- a long line wraps beside the box (not the radio choices: those sit side by side)
    if fs and item and not holding then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", cb, "TOPRIGHT", 2, -9)
        fs:SetJustifyH("LEFT")
        item.wrap, item.indent = fs, 30
    end
    cb.Refresh = function() cb:SetChecked(get()) end
    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        set(v)
        -- say what happened, so a tick is never silent (not for the radio choices: those are not on/off)
        if not quiet and addon.Print and text and text ~= "" then
            local short = tostring(text):gsub("%s*[:(].*$", "")
            if #short > 56 then short = short:sub(1, 53) .. "..." end
            addon.Print(short .. ": " .. (v and "on" or "off"))
        end
    end)
    local group = holding and radioLabel or nil
    HoverTip(cb, text, function()
        if group then return L("Pick one. ") .. group .. " " .. tostring(text) end
        return addon.OptionTip and addon.OptionTip(text)
    end, not group and function(self) return self:GetChecked() and L("Now: on. Click to turn it off.") or L("Now: off. Click to turn it on.") end or nil)
    refreshers[#refreshers + 1] = cb.Refresh
    if advance ~= false then y = y - 26 end
    return cb
end

local sliderId = 0
local function Slider(parent, text, minV, maxV, step, fmt, get, set)
    sliderId = sliderId + 1
    local name = "ForeverLazy_Slider" .. sliderId
    NewBlock("slider")
    y = y - 14
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 24, y)
    Track(s, 24, y, text)
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
    HoverTip(s, text, function() return addon.OptionTip and addon.OptionTip(text) end)
    refreshers[#refreshers + 1] = s.Refresh
    y = y - 34
    return s
end

local function Button(parent, text, x, w, onClick, advance)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    -- a button goes with the words or the buttons just above it
    local last = cur and cur.blocks[#cur.blocks]
    if not (last and (last.kind == "label" or last.kind == "button")) then NewBlock("button")
    elseif not holding then last.kind = "button" end
    Track(b, x, y)
    b:SetSize(w, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if advance then y = y - 32 end
    return b
end

-- Row of mutually exclusive choices drawn as check buttons
local function Radio(parent, labelText, key, choices)
    NewBlock("radio")
    holding = true
    radioLabel = labelText
    Label(parent, labelText)
    y = y - 22
    local boxes = {}
    local col = 0
    local wasNo = noConfirm
    noConfirm = true
    for _, ch in ipairs(choices) do
        local value, text = ch[1], ch[2]
        local cb = Check(parent, text, 16 + col * 150, function() return DB()[key] == value end,
            function() DB()[key] = value; for _, b in ipairs(boxes) do b.Refresh() end; Changed() end, false)
        boxes[#boxes + 1] = cb
        col = col + 1
        if col == 3 then col = 0; y = y - 26 end
    end
    if col ~= 0 then y = y - 26 end
    noConfirm = wasNo
    holding = false
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
    NewBlock("color")
    Track(b, 20, y, text)
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
    local intro = Label(content, L("Never think about where to go next: arrows, a quest route planner, guides and collections."))
    y = y - 24

    sections, cur, query = {}, nil, ""
    shared.scroll, shared.content = scroll, content
    shared.tabs = {}
    local search
    for i, page in ipairs(PAGES) do
        local tab = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        tab:SetSize(122, 24)
        tab:SetPoint("TOPLEFT", 16 + ((i - 1) % 4) * 125, y - math.floor((i - 1) / 4) * 27)
        tab:SetText(L(page[1]))
        tab:SetScript("OnClick", function()
            DB().optPage = page[1]
            query = ""
            if search then search:SetText(""); search:ClearFocus() end
            Layout()
            scroll:SetVerticalScroll(0)
        end)
        shared.tabs[page[1]] = tab
    end
    y = y - math.ceil(#PAGES / 4) * 27 - 8
    local searchLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", 16, y - 4); searchLabel:SetText(L("Search all settings:"))
    search = CreateFrame("EditBox", "ForeverLazy_OptionsSearch", content, "InputBoxTemplate")
    search:SetSize(240, 22)
    search:SetPoint("TOPLEFT", 170, y)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        local typed = self:GetText()
        if type(typed) ~= "string" or typed == query then return end
        query = typed
        Layout()
        scroll:SetVerticalScroll(0)
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    y = y - 28
    local nothing = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    nothing:SetPoint("TOPLEFT", 16, y - 16); nothing:SetText(L("No setting matches that."))
    nothing:Hide()
    shared.nothing = nothing
    topY = y

    ---------------------------------------------------------------- Start here
    Header(content, "Start here")
    Label(content, L("New? Pick how much help you want. One click sets which parts are on, and you can change any of them afterwards."))
    y = y - 22
    Button(content, L("Just point me"), 16, 120, function() if addon.ApplyPreset then addon.ApplyPreset("minimal") end end, false)
    Button(content, "Leveler", 146, 100, function() if addon.ApplyPreset then addon.ApplyPreset("leveler") end end, false)
    Button(content, "Duo", 256, 80, function() if addon.ApplyPreset then addon.ApplyPreset("duo") end end, false)
    Button(content, "Everything", 346, 110, function() if addon.ApplyPreset then addon.ApplyPreset("full") end end, true)
    Label(content, L("Just point me = the arrow, the route plan and services. Leveler = the usual levelling helpers. Duo = Leveler plus group features."))
    y = y - 34

    ---------------------------------------------------------------- Modules
    Header(content, "Buttons in the game windows")
    Label(content, L("Adds a search box and menu to the world map, and buttons under the quest log."))
    y = y - 22
    Check(content, L("Show Forever Lazy buttons and panels in the game windows"), 16,
        function() return DB().uiButtons ~= false end, function(v) DB().uiButtons = v end)
    Label(content, L("The minimap button: left-click = Lazy Mode, right-click = the menu, shift-click = options."))
    y = y - 26

    Header(content, "Help")
    Button(content, L("Take the tour"), 16, 130, function() if addon.StartTour then addon.StartTour() end end, false)
    Button(content, L("What's new"), 156, 110, function() if addon.ShowWhatsNew then addon.ShowWhatsNew() end end, false)
    Button(content, L("Export settings"), 276, 130, function() if addon.ExportSettings then addon.ExportSettings() end end, false)
    Button(content, L("Import settings"), 416, 130, function() if addon.ImportSettings then addon.ImportSettings() end end, true)
    Button(content, L("All commands"), 16, 130, function() if addon.CommandsReport then addon.CommandsReport() end end, false)
    Button(content, L("Bug report"), 156, 110, function() if addon.BugReport then addon.BugReport() end end, false)
    Button(content, L("Game functions"), 276, 130, function() if addon.ApisReport then addon.ApisReport() end end, true)
    local langBtn
    langBtn = Button(content, "", 16, 330, function() if addon.LanguageCycle then addon.LanguageCycle() end end, true)
    refreshers[#refreshers + 1] = function() if addon.LanguageName then langBtn:SetText(L("Language") .. ": " .. addon.LanguageName()) end end

    Header(content, "Quest sounds")
    Label(content, L("Sounds from the game, nothing to install. A quest ready to hand in plays a voice (Peasant 'Job's done!' for the Alliance, Peon 'Work complete!' for the Horde). A finished quest step plays an effect."))
    y = y - 22
    Check(content, L("Play sounds for finished steps and quests ready to hand in"), 16,
        function() return DB().questSound ~= false end, function(v) DB().questSound = OffFlag(v) end)
    Check(content, L("Announce in party chat when I complete a quest (not every step)"), 16,
        function() return DB().questAnnounce ~= false end, function(v) DB().questAnnounce = OffFlag(v) end)
    Label(content, L("|cffffd100Step done|r (all its items or kills): a sound effect"))
    y = y - 22
    Button(content, L("Hear it"), 16, 90, function() if addon.QuestSoundTryStep then addon.QuestSoundTryStep() end end, false)
    Button(content, L("Change the sound"), 116, 150, function() if addon.QuestSoundNextStep then addon.QuestSoundNextStep() end end, true)
    Label(content, L("|cffffd100Ready to hand in|r: the Job's done voice"))
    y = y - 22
    Button(content, L("Hear it"), 16, 90, function() if addon.QuestSoundTryDone then addon.QuestSoundTryDone() end end, false)
    Button(content, L("Change the voice"), 116, 150, function() if addon.QuestSoundNextDone then addon.QuestSoundNextDone() end end, true)

    Header(content, "Quest map")
    Label(content, L("Shows where your quests' mobs, items and objects are, on the world map and minimap. Coloured area = where to kill or collect (a colour for each quest), green dot = click it on the ground, yellow ! = quest to pick up, yellow ? = ready to hand in. Hover a pin for the quest."))
    y = y - 22
    Check(content, L("Show quest objectives on the map and minimap"), 16,
        function() return DB().questMap ~= false and DB().questMapObjectives ~= false end,
        function(v) DB().questMapObjectives = OffFlag(v); if v then DB().questMap = nil end; if addon.QuestMapRefresh then addon.QuestMapRefresh() end end)
    Check(content, L("Coloured areas where the quest mobs are (world map)"), 16,
        function() return DB().questMap ~= false and DB().questMapAreas ~= false end,
        function(v) DB().questMapAreas = OffFlag(v); if v then DB().questMap = nil end; if addon.QuestMapRefresh then addon.QuestMapRefresh() end end)
    Check(content, L("Skull and diamond icons on mob spots"), 16,
        function() return DB().questMapIcons == true end,
        function(v) DB().questMapIcons = v and true or nil; if addon.QuestMapRefresh then addon.QuestMapRefresh() end end)
    Check(content, L("Show quest givers (!) and hand-ins (?) on the map"), 16,
        function() return DB().questMap ~= false and DB().questMapGivers ~= false end,
        function(v) DB().questMapGivers = OffFlag(v); if v then DB().questMap = nil end; if addon.QuestMapRefresh then addon.QuestMapRefresh() end end)
    Slider(content, L("Hide pick-ups more levels above me than"), 0, 10, 1, "%d",
        function() return tonumber(DB().questMapGiverAbove) or 10 end,
        function(v) DB().questMapGiverAbove = v; if addon.QuestMapRefresh then addon.QuestMapRefresh() end end)
    Label(content, L("(10 means show everything)"))
    y = y - 22
    Slider(content, L("Pin size"), 0.5, 2, 0.1, "%.1f",
        function() return tonumber(DB().questMapScale) or 1 end,
        function(v) DB().questMapScale = v; if addon.QuestMapRefresh then addon.QuestMapRefresh() end end)

    Header(content, "Quest map")
    Check(content, L("Quest item sparkles: the game's own sparkle on quest items you can loot"), 16,
        function() return DB().questSparkles ~= false end, function(v) DB().questSparkles = OffFlag(v); if addon.QuestSparklesRefresh then addon.QuestSparklesRefresh() end end)
    Header(content, "Paladin blessings")
    Check(content, L("Paladin blessings: one button blesses the next player who needs it (shows for a paladin in a group)"), 16,
        function() return DB().blessPanel == true end, function(v) DB().blessPanel = v and true or false; if addon.BlessingsRefresh then addon.BlessingsRefresh() end end)
    Header(content, "Bags")
    Check(content, L("Our bag window instead of the game's bags"), 16,
        function() return DB().bagsReplace == true end, function(v) DB().bagsReplace = v or nil; if addon.BagSyncWrappers then addon.BagSyncWrappers(true) end end)
    Header(content, "Selling and looting")
    Check(content, L("Sell grey loot when a vendor opens (off until you tick it; items you protect with /lazy keep are never sold)"), 16,
        function() return DB().sellGray == true end, function(v) DB().sellGray = v or nil end)
    Check(content, L("Faster auto loot: empty the loot window the moment it opens (needs auto loot on in the game's options)"), 16,
        function() return DB().fastLoot == true end, function(v) DB().fastLoot = v or nil end)
    Header(content, "Action bars")
    Check(content, L("Colour action buttons: red out of range, blue no mana, grey cannot use"), 16,
        function() return DB().rangeColor == true end, function(v) DB().rangeColor = v or nil; if addon.RangeColorRefresh then addon.RangeColorRefresh() end end)
    Header(content, "Pedometer")
    Check(content, L("Pedometer: count how far I walk on foot"), 16,
        function() return DB().pedometer ~= false end, function(v) DB().pedometer = OffFlag(v); if addon.PedometerRefresh then addon.PedometerRefresh() end end)
    Check(content, L("Show the pedometer readout on the screen (click it for all the numbers)"), 16,
        function() return DB().pedoShow == true end, function(v) DB().pedoShow = v or nil; if addon.PedometerRefresh then addon.PedometerRefresh() end end)
    Header(content, "Arrows")
    Check(content, L("The arrow says why it points where it does"), 16,
        function() return DB().arrowWhy ~= false end, function(v) DB().arrowWhy = OffFlag(v) end)

    Header(content, "Finding quests")
    Label(content, L("Hover a quest link in chat for who gives it, who takes it, its level and chain, and why you cannot take it. The buttons find any quest by name or show what you finished in each zone."))
    y = y - 22
    Check(content, L("Quest link tooltips in chat"), 16,
        function() return DB().questLinkTooltips ~= false end, function(v) DB().questLinkTooltips = OffFlag(v) end)
    Check(content, L("Ping when I am near someone I can hand a quest in to"), 16,
        function() return DB().handInPing ~= false end, function(v) DB().handInPing = OffFlag(v) end)
    Button(content, L("Find a quest"), 16, 120, function() if addon.QuestSearchOpen then addon.QuestSearchOpen() end end, false)
    Button(content, L("Quest history"), 146, 120, function() if addon.QuestHistoryOpen then addon.QuestHistoryOpen() end end, true)

    Header(content, "Gear")
    local gearNow = Label(content, "")
    refreshers[#refreshers + 1] = function()
        local s = addon.GearSpec and addon.GearSpec()
        if s then
            gearNow:SetText(string.format("Scored as: |cffffd100%s|r (%s)%s. Stat order: %s.", s.name, s.kind, s.forced and ", set by hand" or ", from your talents", table.concat(s.priority, " > ")))
        end
    end
    y = y - 22
    Label(content, L("Which gear is an upgrade for your class and spec. It shows in tooltips, in the bag window and at vendors, and in the gear bar."))
    y = y - 22
    Check(content, L("Gear advisor: upgrade line in tooltips"), 16,
        function() return DB().gearAdvisor ~= false end, function(v) DB().gearAdvisor = OffFlag(v); if addon.GearAdvisorRefresh then addon.GearAdvisorRefresh() end end)
    Check(content, L("A green ^ on upgrades in the bag window and at vendors"), 16,
        function() return DB().gearArrows ~= false end, function(v) DB().gearArrows = OffFlag(v); if addon.GearAdvisorRefresh then addon.GearAdvisorRefresh() end end)
    Check(content, L("Gear bar: a button that equips an upgrade from my bags"), 16,
        function() return DB().gearBar == true end, function(v) DB().gearBar = v or nil; if addon.GearAdvisorRefresh then addon.GearAdvisorRefresh() end end)
    Check(content, L("Tell me in chat when I loot or buy an upgrade"), 16,
        function() return DB().gearNote == true end, function(v) DB().gearNote = v or nil end)
    Radio(content, L("Score gear as:"), "rewardRole", {
        { "auto", "My class and talents (automatic)" }, { "str_melee", "Strength melee" }, { "agi_melee", "Agility melee" },
        { "hunter", "Hunter" }, { "caster", "Caster" }, { "healer", "Healer" }, { "tank", "Tank" } })
    Button(content, L("Show the stats it reads from my gear"), 16, 250, function() addon:HandleExtraCommand("gear", "stats") end, true)

    Header(content, "Nameplates")
    Check(content, L("Quest icons on nameplates (sword, loot bag, gold !)"), 16,
        function() return DB().questPlates ~= false end, function(v) DB().questPlates = OffFlag(v); if addon.QuestPlatesRefresh then addon.QuestPlatesRefresh() end end)
    Check(content, L("Hunt panel: buttons for the mobs my quests need, click one to target it"), 16,
        function() return DB().huntPanel ~= false end, function(v) DB().huntPanel = OffFlag(v); if addon.HuntPanelRefresh then addon.HuntPanelRefresh() end end)
    Check(content, L("Interrupt marker when a mob casts (green ready, red on cooldown, grey none)"), 16,
        function() return DB().nameplateCasts ~= false end, function(v) DB().nameplateCasts = OffFlag(v) end)
    Check(content, L("... flash the mob's cast bar while my interrupt is ready"), 40,
        function() return DB().castFlash == true end, function(v) DB().castFlash = v or nil end)

    Check(content, L("Colour hostile plates: red = aggressive or attacking me, orange = fighting someone else"), 16,
        function() return DB().plateColors == true end, function(v) DB().plateColors = v or nil; if addon.PlateColorsRefresh then addon.PlateColorsRefresh() end end)
    Check(content, L("... colour aggressive mobs red before the fight, and by who is being attacked"), 40,
        function() return DB().plateThreat ~= false end, function(v) DB().plateThreat = OffFlag(v); if addon.PlateColorsRefresh then addon.PlateColorsRefresh() end end)
    Check(content, L("... tint neutral quest mobs that are not in a fight (purple)"), 40,
        function() return DB().plateQuest ~= false end, function(v) DB().plateQuest = OffFlag(v); if addon.PlateColorsRefresh then addon.PlateColorsRefresh() end end)
    ColorRow(content, L("An aggressive mob, or one attacking me"), "plateColorMe")
    ColorRow(content, L("A mob fighting someone else (not the neutral yellow)"), "plateColorOthers")
    ColorRow(content, L("A neutral quest mob"), "plateColorQuest")

    Header(content, "Action bars")
    Check(content, L("Swap in the newest spell rank on my action bars when I learn it"), 16,
        function() return DB().rankUp == true end, function(v) DB().rankUp = v or nil end)
    Button(content, L("Fix my bars now"), 16, 130, function() if addon.RankUpRun then addon.RankUpRun() end end, true)
    Label(content, L("Want a low rank on purpose? /lazy rankup keep <spell name> leaves that spell alone. /lazy rankup keep lists them, /lazy rankup unkeep <spell name> undoes it."))
    y = y - 26

    Header(content, "Chat")
    Label(content, L("Chat tweaks, a little like Prat. All off until you turn them on, and changes show on new lines. Undoing input box on top, hidden buttons or no fading needs a /reload."))
    y = y - 22
    local function ChatCheck(text, key)
        Check(content, text, 16, function() return DB()[key] == true end,
            function(v) DB()[key] = v and true or false; if addon.ChatApply then addon.ChatApply() end end)
    end
    Button(content, L("Turn on the usual set"), 16, 170, function() if addon.ChatPreset then addon.ChatPreset() end end, true)
    Label(content, L("|cffffd100How messages look|r"))
    y = y - 22
    ChatCheck(L("Timestamps in front of every line"), "chatTime")
    local tfb
    tfb = Button(content, L("Time format"), 16, 200, function()
        local n = #(addon.ChatTimeFormats and addon.ChatTimeFormats() or { 1 })
        DB().chatTimeFormat = ((tonumber(DB().chatTimeFormat) or 1) % n) + 1
        tfb:SetText("Time format: " .. date((addon.ChatTimeFormats()[DB().chatTimeFormat])))
    end, true)
    refreshers[#refreshers + 1] = function()
        if addon.ChatTimeFormats then tfb:SetText("Time format: " .. date(addon.ChatTimeFormats()[tonumber(DB().chatTimeFormat) or 1] or "%H:%M")) end
    end
    ChatCheck(L("Class-coloured names in every channel"), "chatClassColor")
    ChatCheck(L("Player levels next to names (from group, guild, friends, target, /who)"), "chatLevels")
    ChatCheck(L("Short channel names ([Guild] becomes [G], [1. General] becomes [1])"), "chatShortChannels")
    ChatCheck(L("No brackets around channel names"), "chatNoBrackets")
    ChatCheck(L("Highlight your name and these words (with a sound):"), "chatWordsOn")
    do
        local eb = CreateFrame("EditBox", "ForeverLazy_ChatWords", content, "InputBoxTemplate")
        eb:SetSize(330, 22)
        eb:SetPoint("TOPLEFT", 40, y)
        Track(eb, 40, y)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEnterPressed", function(s) DB().chatWords = s:GetText(); s:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", function(s) DB().chatWords = s:GetText() end)
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        refreshers[#refreshers + 1] = function() eb:SetText(DB().chatWords or "") end
        y = y - 30
    end
    Label(content, L("|cffffd100How the windows behave|r"))
    y = y - 22
    ChatCheck(L("Click a web link to copy it, and a copy button on each window"), "chatLinks")
    ChatCheck(L("Resize chat windows by dragging the bottom-right corner"), "chatResize")
    ChatCheck(L("Input box on top of the chat window"), "chatEditTop")
    ChatCheck(L("Chat text never fades"), "chatNoFade")
    ChatCheck(L("Long chat history (1000 lines)"), "chatHistory")
    ChatCheck(L("Hide the chat side buttons"), "chatHideButtons")
    ChatCheck(L("Chat tabs never fade: General, Combat Log and the others stay fully visible"), "chatTabsSolid")
    ChatCheck(L("Tabs fade away until the mouse is over them"), "chatTabFade")
    ChatCheck(L("Sticky channels (the input box remembers say, yell, guild, raid ...)"), "chatSticky")
    ChatCheck(L("An extra sound when someone whispers me"), "chatWhisperSound")
    Slider(content, L("Chat font size"), 8, 24, 1, "%d",
        function() return tonumber(DB().chatFontSize) or 14 end,
        function(v) DB().chatFontSize = v; if addon.ChatApply then addon.ChatApply() end end)
    local fb
    fb = Button(content, "Font", 16, 220, function()
        local fonts = addon.ChatFonts()
        DB().chatFont = ((tonumber(DB().chatFont) or 1) % #fonts) + 1
        fb:SetText("Font: " .. fonts[DB().chatFont][1])
        if addon.ChatApply then addon.ChatApply() end
    end, true)
    refreshers[#refreshers + 1] = function()
        if addon.ChatFonts then fb:SetText("Font: " .. (addon.ChatFonts()[tonumber(DB().chatFont) or 1] or addon.ChatFonts()[1])[1]) end
    end
    ChatCheck(L("Outline the chat font"), "chatFontOutline")
    Button(content, L("Copy the chat window I'm using"), 16, 220, function() if addon.ChatCopy then addon.ChatCopy() end end, true)

    Header(content, "Quest data")
    Label(content, L("Forever Lazy has its own quest data and does not need Questie. To test it: ignore Questie, reload, and a results window shows a few seconds later."))
    y = y - 22
    Button(content, L("Test without Questie"), 16, 170, function() if addon.SelfTest then addon.SelfTest(false) end end, false)
    Button(content, L("Back to normal"), 196, 130, function() if addon.SelfTest then addon.SelfTest(true) end end, false)
    Button(content, L("Compare with Questie"), 336, 170, function() SlashCmdList["FOREVERLAZY"]("data verify") end, true)

    Header(content, "Modules")
    Label(content, L("Switch off what you do not want. A module that is off does nothing, and its options are hidden."))
    y = y - 22
    for _, m in ipairs(addon.MODULES or {}) do
        Check(content, m[2], 16,
            function() return addon.ModuleOn(m[1]) end,
            function(v)
                local db = DB()
                db.modules = db.modules or {}
                db.modules[m[1]] = v and true or false
                if addon.ModulesChanged then addon.ModulesChanged() end
                Refresh()          -- the options of a module that is now off go away (or come back)
            end)
    end

    ---------------------------------------------------------------- Journey
    ---------------------------------------------------------------- Lazy mode
    Header(content, "Lazy mode")
    Label(content, L("One press and the arrow points at the best next thing: vendor, trainer, your plan, or the next zone."))
    y = y - 22
    Button(content, L("Do the next thing now"), 16, 190, function() if addon.LazyNow then addon.LazyNow() end end, true)
    Check(content, L("Keep going: pick the next thing by itself when I reach it"), 16,
        function() return DB().lazyKeepGoing == true end, function(v) DB().lazyKeepGoing = v end)
    Label(content, L("Also: /lazy now, the macro Lazy Now (/lazy macros), or a key under Key Bindings > Forever Lazy."))
    y = y - 26
    Header(content, "Journey")
    Label(content, L("The zones to level in, in order, from your level to 60. Saved for each character."))
    y = y - 22
    Button(content, L("Generate my journey"), 16, 170, function() if addon.JourneyGenerate then addon.JourneyGenerate() end end, false)
    Button(content, "Regenerate", 196, 110, function() if addon.JourneyRegenerate then addon.JourneyRegenerate() end end, false)
    Button(content, L("Show it"), 316, 90, function() if addon.JourneyShow then addon.JourneyShow() end end, true)
    Check(content, L("Include dungeons that fit each stretch"), 16,
        function() return DB().journeyDungeons ~= false end, function(v) DB().journeyDungeons = v end)
    Check(content, L("Tell me when I have outgrown a stop and where to go next"), 16,
        function() return DB().journeyHint ~= false end, function(v) DB().journeyHint = v end)

    ----------------------------------------------------------------- Arrows
    Header(content, "Text")
    Slider(content, L("Guide text size (1.8 is big, for the TV)"), 0.8, 2.6, 0.1, "%.1f", function() return DB().guideScale or 1 end,
        function(v) DB().guideScale = v; if _G.ForeverLazy_Guide and _G.ForeverLazy_Guide:IsShown() then _G.ForeverLazy_Guide:SetScale(v) end end)

    Header(content, "Arrows")
    Check(content, L("Show the main arrow (off until you tick it)"), 16,
        function() return DB().waypointArrowOff == false end, function(v) DB().waypointArrowOff = not v end)
    Check(content, L("Simple arrows: one main arrow, plus the ghost and follow arrows. The rest show on the compass."), 16,
        function() return DB().simpleArrows ~= false end, function(v) DB().simpleArrows = v; Changed() end)
    Radio(content, L("Arrow style:"), "style", {
        { "minimap", "Classic" }, { "chevron", "Chevron" }, { "thick", "Thick" } })
    ColorRow(content, L("Route plan arrow color"), "colorWaypoint")
    ColorRow(content, L("My quests arrow color"), "colorMine")
    Slider(content, L("Arrow size"), 0.5, 3, 0.1, "%.1f", function() return DB().scale end,
        function(v) DB().scale = v; Changed() end)
    Slider(content, L("Arrow opacity"), 0.2, 1, 0.05, "%.2f", function() return DB().alpha end,
        function(v) DB().alpha = v; Changed() end)
    Slider(content, L("Count as arrived within (yards)"), 3, 40, 1, "%d", function() return DB().arrival end,
        function(v) DB().arrival = v end)
    Check(content, L("Lock positions (untick to drag the arrows and panels)"), 16,
        function() return DB().locked end, function(v) DB().locked = v end)

    ---------------------------------------------------------------- Display
    Header(content, "Text")
    Check(content, L("Show the name under the arrow"), 16,
        function() return DB().showText end, function(v) DB().showText = v end)
    Check(content, L("Show distance"), 16, function() return DB().showDistance end, function(v) DB().showDistance = v end)
    Radio(content, L("Distance units:"), "units", { { "yd", "Yards" }, { "m", "Meters" }, { "steps", "Steps" } })

    ---------------------------------------------------------------- Alerts
    Header(content, "Alerts")
    Check(content, L("Sound when I arrive at the quest spot"), 16,
        function() return DB().arrivalSound end, function(v) DB().arrivalSound = v end)

    ------------------------------------------------------------- Visibility
    Header(content, "Hide arrows")
    Check(content, L("In combat"), 16, function() return DB().hideCombat end, function(v) DB().hideCombat = v end)
    Check(content, L("In cities and inns (resting)"), 16,
        function() return DB().hideResting end, function(v) DB().hideResting = v end)
    Check(content, L("On a flight path"), 16, function() return DB().hideTaxi end, function(v) DB().hideTaxi = v end)
    Check(content, L("Inside a dungeon or raid (the ghost arrow to your corpse still shows)"), 16,
        function() return DB().hideInstance ~= false end, function(v) DB().hideInstance = v end)

    ------------------------------------------------------------- Following
    Check(content, L("When I am a ghost, point the arrow at my corpse (other arrows hide)"), 16,
        function() return DB().ghostArrow ~= false end, function(v) DB().ghostArrow = v end)

    ------------------------------------------------- RestedXP friend (optional)
    -- everything that needs a friend running RestedXP lives here; the rest of the addon works without it
    Header(content, "RestedXP friend (optional)")
    Label(content, L("Only for following a friend who runs RestedXP. Nothing else in the addon needs it."))
    y = y - 22
    Check(content, L("Listen to a friend's RestedXP steps"), 16,
        function() return DB().rxpListen ~= false end, function(v) DB().rxpListen = v; Changed() end)
    Radio(content, L("Arrows shown:"), "mode", {
        { "both", "Quest + friend" }, { "quest", "Quest only" }, { "friend", "Friend only" }, { "off", "Off" } })
    ColorRow(content, L("Friend's quest arrow color"), "colorQuest")
    ColorRow(content, L("Friend arrow color"), "colorFriend")
    Slider(content, L("Extra quest arrows (nearest other targets)"), 0, 2, 1, "%d", function() return DB().extraTargets end,
        function(v) DB().extraTargets = v end)
    Check(content, L("Show friend's current step in a box"), 16,
        function() return DB().showPanel end, function(v) DB().showPanel = v end)
    Slider(content, L("Step panel size"), 0.5, 2, 0.1, "%.1f", function() return DB().panelScale end,
        function(v) DB().panelScale = v; Changed() end)
    Check(content, L("Show earlier steps in the step panel"), 16,
        function() return DB().showHistory end, function(v) DB().showHistory = v; Changed() end)
    Check(content, L("Chat message when friend's step changes"), 16,
        function() return DB().alertChat end, function(v) DB().alertChat = v end)
    Check(content, L("Sound when friend's step changes"), 16,
        function() return DB().alertSound end, function(v) DB().alertSound = v end)
    Check(content, L("Keep pointing at friend's last seen spot when too far away"), 16,
        function() return DB().followLastSeen end, function(v) DB().followLastSeen = v end)
    Check(content, L("Warn me if my friend hasn't moved for 3 minutes"), 16,
        function() return DB().stuckAlert end, function(v) DB().stuckAlert = v end)
    Label(content, L("Several friends: right-click the step panel to switch, /lazy friend <name> to pin."))
    y = y - 26

    Header(content, "My quest arrow")
    Check(content, L("Show an arrow for my own quest log (turn-ins and objectives)"), 16,
        function() return DB().ownQuests end, function(v) DB().ownQuests = v; Changed() end)
    Check(content, L("Skip grey quests, and red ones unless they are just a turn-in"), 16,
        function() return DB().questColorFilter ~= false end,
        function(v) DB().questColorFilter = v; Changed() end)
    Check(content, L("Follow the quest I have selected or tracked (otherwise the nearest of all)"), 16,
        function() return DB().ownFocus ~= false end, function(v) DB().ownFocus = v; Changed() end)
    Header(content, "The plan")
    Check(content, L("Leave small quests out of the plan when the XP is not worth the time"), 16,
        function() return DB().planWorth ~= false end, function(v) DB().planWorth = v end)
    Check(content, L("Autopilot: visit the vendor or trainer between quests, and move on to the next zone when this one is done"), 16,
        function() return DB().autopilot == true end, function(v) DB().autopilot = v end)
    Header(content, "My quest arrow")
    Check(content, L("For kills and items, point the arrow at the nearest spot and move on when it is cleared"), 16,
        function() return DB().arrowSpots ~= false end, function(v) DB().arrowSpots = v end)
    Check(content, L("Closest first: the arrow goes to the nearest of my next stops, not strictly plan order"), 16,
        function() return DB().arrowNearest ~= false end, function(v) DB().arrowNearest = OffFlag(v) end)
    Header(content, "The plan")
    Check(content, L("Plan for quests I have not taken yet that are right here (about 600 yards)"), 16,
        function() return DB().planNearby ~= false end, function(v) DB().planNearby = v end)
    Check(content, L("Show the step window while a plan is running"), 16,
        function() return DB().stepsAuto ~= false end,
        function(v) DB().stepsAuto = v; if v then DB().stepsHidden = false end end)
    Button(content, L("Plan this zone for the fastest levelling"), 16, 270, function() addon.PlanZone() end, true)
    Label(content, L("Same as /lazy level (or /lazy level ashenvale for another zone). Takes you there, then plans every quest worth taking in the zone, not just the ones in your log."))
    y = y - 26
    Button(content, L("Plan my route (replaces waypoints)"), 16, 240, function() addon:PlanRoute() end, true)
    Label(content, L("Same as /lazy plan. Orders your quest spots into a walking route, one waypoint each."))
    y = y - 26
    do
        local b
        local function show() b:SetText(DB().planPaused and "Plan is OFF: turn it back on" or "Turn the plan off (keeps my place)") end
        b = Button(content, "", 16, 240, function()
            if DB().planPaused then addon.PlanResume() else addon.PlanPause() end
            show()
        end, true)
        refreshers[#refreshers + 1] = show
        show()
    end
    Label(content, L("Off stops all planning and keeps your remaining stops. On puts them back. Same as /lazy plan off and /lazy plan on."))
    y = y - 26
    Check(content, L("Plan for XP: the quests with the most XP for the walking come first"), 16,
        function() return DB().planXP ~= false end, function(v) DB().planXP = v end)
    Check(content, L("Keep the plan to the zone I am in (/lazy plan all ignores this)"), 16,
        function() return DB().planZoneOnly ~= false end, function(v) DB().planZoneOnly = v end)
    Check(content, L("Leave grey (too low level) quests out of the plan"), 16,
        function() return DB().planSkipGrey ~= false end, function(v) DB().planSkipGrey = v end)
    Check(content, L("Add a new quest to the plan where it costs the least walking"), 16,
        function() return DB().planAuto ~= false end, function(v) DB().planAuto = v end)

    Header(content, "Class options")
    Label(content, L("Settings made for one class. You see the ones for your own class: paladins, hunters and shamans have some."))
    y = y - 22
    Check(content, L("Show every class's settings"), 16,
        function() return DB().optAllClasses == true end,
        function(v) DB().optAllClasses = v and true or nil; if Layout then Layout() end end)

    local function ShamanCheck(text, key, x)
        Check(content, text, x or 16, function() return DB()[key] == true end,
            function(v) DB()[key] = v and true or nil; if addon.ShamanRefresh then addon.ShamanRefresh() end end)
    end
    Header(content, "Totems")
    ShamanCheck(L("Totem bar: four totems with time left, and a button that drops your set"), "shamTotemBar")
    ShamanCheck(L("Tell me when I walk out of range of a totem (outdoors only)"), "shamTotemRange")
    Label(content, L("On the bar, left-click an element to drop its totem and right-click to pick another. Each set (Solo, Dungeon, Healing) remembers its own."))
    y = y - 36
    Button(content, L("Show my totem quests"), 16, 200, function() if addon.ClassWindow then addon.ClassWindow() end end, true)

    Header(content, "Shaman buffs")
    ShamanCheck(L("Weapon buff button: lights up when it is missing or about to run out"), "shamImbue")
    ShamanCheck(L("Shield button: lights up when your shield is missing or about to run out"), "shamShield")
    ShamanCheck(L("Ankh count and Reincarnation, with a warning when you run low"), "shamAnkh")
    Slider(content, L("Warn me below this many ankhs"), 1, 20, 1, "%d", function() return tonumber(DB().shamAnkhLow) or 3 end,
        function(v) DB().shamAnkhLow = v end)

    Header(content, "Shaman helpers")
    ShamanCheck(L("Cure buttons for you and your party: they change colour for poison or disease"), "shamCure")
    ShamanCheck(L("Mark enemy nameplates that have a magic buff you can Purge"), "shamPurge")
    ShamanCheck(L("Remind me to use Ghost Wolf on a long run"), "shamWolf")
    Label(content, L("The interrupt cast bar flash for Earth Shock is under Combat, Nameplates."))
    y = y - 26

    Header(content, "Hunter pet")
    Check(content, L("Remind me when my pet needs feeding"), 16,
        function() return DB().petRemind ~= false end, function(v) DB().petRemind = v end)
    Check(content, L("Only remind when it is unhappy (not when it is just content)"), 16,
        function() return DB().petOnlyUnhappy == true end, function(v) DB().petOnlyUnhappy = v end)
    Check(content, L("Also remind me when I have no pet out or it is dead"), 16,
        function() return DB().petMissing == true end, function(v) DB().petMissing = v end)
    Check(content, L("Play a sound with the reminder"), 16,
        function() return DB().petSound == true end, function(v) DB().petSound = v end)
    Check(content, L("Hunters: warn me when I am low on arrows or bullets"), 16,
        function() return DB().ammoRemind ~= false end, function(v) DB().ammoRemind = v end)
    Check(content, L("Hunters: tell me when a better kind of ammo opens up for my level"), 16,
        function() return DB().ammoUpgrade ~= false end, function(v) DB().ammoUpgrade = v end)
    Slider(content, L("Warn me below this much ammo"), 50, 1000, 50, "%d", function() return DB().ammoLow or 200 end,
        function(v) DB().ammoLow = v end)
    Check(content, L("Scream FEED ME!!! across the screen when my pet is hungry"), 16,
        function() return DB().petScream ~= false end, function(v) DB().petScream = v end)
    Button(content, L("Test the pet reminder"), 16, 170, function() addon:HandleExtraCommand("pet", "test") end, true)

    Header(content, "Arrows")
    Check(content, L("Animate arrows (pulse when near, dim when facing away)"), 16,
        function() return DB().animate end, function(v) DB().animate = v end)
    Header(content, "Travel and zones")
    Check(content, L("Flight timer: how long a flight takes (learned the first time)"), 16,
        function() return DB().flightTimer ~= false end, function(v) DB().flightTimer = v end)
    Check(content, L("Suggest the next zone when I have outgrown the one I am in"), 16,
        function() return DB().nextZoneHint ~= false end, function(v) DB().nextZoneHint = v end)
    Header(content, "Dungeons and class quests")
    Check(content, L("Tell me when I reach a dungeon entrance my quests need"), 16,
        function() return DB().dungeonHint ~= false end, function(v) DB().dungeonHint = v end)
    Check(content, L("Cozy Sleeping Bag chain: guide me, with its next spot as stop 1"), 16,
        function() return DB().bagGuide ~= false end, function(v) DB().bagGuide = v end)
    Check(content, L("Tell me when a new class quest opens up"), 16,
        function() return DB().classAlert ~= false end, function(v) DB().classAlert = v end)
    Check(content, L("Pop-up when I enter a zone with something for a class quest (/lazy class here)"), 16,
        function() return DB().classZoneAlert ~= false end, function(v) DB().classZoneAlert = v end)
    Check(content, L("In a group, a pop-up when I enter a dungeon my quests need (/lazy dungeons here)"), 16,
        function() return DB().dungeonQuestPopup ~= false end, function(v) DB().dungeonQuestPopup = v end)
    Check(content, L("Put class quest givers in my plan when they are in this zone"), 16,
        function() return DB().planClass ~= false end, function(v) DB().planClass = v end)
    Header(content, "Travel and zones")
    Check(content, L("Start a flight trip by itself when the next stop is far and flying is quicker"), 16,
        function() return DB().autoTrip == true end, function(v) DB().autoTrip = v end)
    Header(content, "The plan")
    Check(content, L("Finish the quests in an area before walking back to hand any in (unless it continues a chain)"), 16,
        function() return DB().planBatch ~= false end, function(v) DB().planBatch = v end)
    Header(content, "Map pins")
    Check(content, L("Show my plan's numbered stops on the world map"), 16,
        function() return DB().mapRoute ~= false end, function(v) DB().mapRoute = v; if addon.DrawRouteLines then addon.DrawRouteLines() end end)
    Check(content, L("... and draw lines between them"), 16,
        function() return DB().mapRouteLines == true end, function(v) DB().mapRouteLines = v; if addon.DrawRouteLines then addon.DrawRouteLines() end end)
    Header(content, "Item tooltips")
    Check(content, L("Item tooltips show how many I have in bags, bank, mail and worn"), 16,
        function() return DB().itemTooltip ~= false end, function(v) DB().itemTooltip = v end)
    Check(content, L("... and how many my other characters have"), 16,
        function() return DB().itemTooltipAlts ~= false end, function(v) DB().itemTooltipAlts = v end)
    Header(content, "Map pins")
    Check(content, L("XP hot spots on the world map (where the best quests for my level are)"), 16,
        function() return DB().xpHeat == true end, function(v) DB().xpHeat = v; if addon.DrawXPHeat then addon.DrawXPHeat() end end)
    Check(content, L("Draw my route on the minimap (numbered stops joined by lines)"), 16,
        function() return DB().minimapLine == true end, function(v) DB().minimapLine = v end)
    Header(content, "Travel and zones")
    Check(content, L("Offer to plan a new zone once I have stayed in it a while"), 16,
        function() return DB().zonePrompt ~= false end, function(v) DB().zonePrompt = v end)
    Header(content, "Sharing and party")
    Check(content, L("Share boat docks I learn with my guild and group (nothing shows in chat)"), 16,
        function() return DB().community == true end, function(v) DB().community = v end)
    Header(content, "Crafting")
    Check(content, L("Craft planner: a panel beside the profession window"), 16,
        function() return DB().craftPanel == true end, function(v) DB().craftPanel = v or nil; if addon.CraftPanelRefresh then addon.CraftPanelRefresh() end end)
    Check(content, L("When I open a profession window, tell me the best next craft"), 16,
        function() return DB().craftHint ~= false end, function(v) DB().craftHint = v end)
    Header(content, "Quest hints")
    Check(content, L("Tell me what comes next after I hand in a quest in a chain"), 16,
        function() return DB().chainHint ~= false end, function(v) DB().chainHint = v end)
    Check(content, L("Mark the best quest reward (likely upgrade or best price)"), 16,
        function() return DB().rewardPick ~= false end, function(v) DB().rewardPick = v end)
    Header(content, "The plan")
    Check(content, L("Leave group quests out of my plan while I am solo"), 16,
        function() return DB().planSkipGroup ~= false end, function(v) DB().planSkipGroup = v end)
    Check(content, L("Favour quests I share with someone in my group"), 16,
        function() return DB().planShared ~= false end, function(v) DB().planShared = v end)
    Header(content, "Travel and zones")
    Check(content, L("Tell me when my hearthstone would save a long walk"), 16,
        function() return DB().hearthNudge ~= false end, function(v) DB().hearthNudge = v end)
    Header(content, "Compass")
    Label(content, L("The compass works on its own: turning the arrows off or hiding them does nothing to it. Right-click the bar for a quick menu, and hover a marker to see what it is."))
    y = y - 36
    Check(content, L("Compass bar at the top of the screen"), 16,
        function() return DB().compassBar end, function(v) DB().compassBar = v end)
    Check(content, L("... show the directions N, E, S and W"), 40,
        function() return DB().compassDirections == true end, function(v) DB().compassDirections = v and true or nil end)
    Check(content, L("... show the distance under each marker"), 40,
        function() return DB().compassDistance == true end, function(v) DB().compassDistance = v and true or nil end)
    Check(content, L("... icons instead of blocks for quest targets"), 40,
        function() return DB().compassIcons == true end, function(v) DB().compassIcons = v and true or nil end)
    Check(content, L("... show the next stop in words under the compass"), 40,
        function() return DB().compassText == true end, function(v) DB().compassText = v and true or nil end)
    Check(content, L("Also show the big arrow to your next stop"), 16,
        function() return DB().waypointArrowOff == false end, function(v) DB().waypointArrowOff = not v end)
    Check(content, L("In duo mode, show my partner on the compass (even when the arrows are off)"), 16,
        function() return DB().duoCompass ~= false end, function(v) DB().duoCompass = v end)
    Radio(content, L("Marker for my partner on the compass:"), "compassIcon", {
        { 3, "Diamond" }, { 1, "Star" }, { 2, "Circle" }, { 4, "Triangle" }, { 5, "Moon" } })
    Header(content, "Compass size and place")
    Slider(content, L("Compass size"), 0.6, 2, 0.1, "%.1f", function() addon.CompassSettings(); return tonumber(DB().compassScale) or 1 end,
        function(v) DB().compassScale = v end)
    Check(content, L("Lock the compass (untick to drag it)"), 16,
        function() addon.CompassSettings(); return DB().compassLocked == true end, function(v) DB().compassLocked = v and true or false end)

    Header(content, "Hide the compass")
    local function CompassHide(text, key)
        Check(content, text, 16, function() addon.CompassSettings(); return DB()[key] == true end,
            function(v) addon.CompassSettings(); DB()[key] = v and true or false end)
    end
    CompassHide(L("Hide the compass in combat"), "compassHideCombat")
    CompassHide(L("Hide the compass in cities and inns (resting)"), "compassHideResting")
    CompassHide(L("Hide the compass on a flight path"), "compassHideTaxi")
    CompassHide(L("Hide the compass inside a dungeon or raid"), "compassHideInstance")
    Header(content, "Sharing and party")
    Check(content, L("Accept waypoints my party sends me"), 16,
        function() return DB().acceptShared end, function(v) DB().acceptShared = v end)
    Label(content, L("Shift + click the friend arrow to tell the party 'On my way!'."))
    y = y - 26
    Button(content, L("Run self-test"), 16, 120, function() addon:RunSelfTest() end, false)
    Button(content, L("Share waypoint"), 146, 120, function() addon:ShareWaypoint() end, false)
    Button(content, "Export", 276, 80, function() addon:OpenIO("export") end, false)
    Button(content, "Import", 366, 80, function() addon:OpenIO("import") end, true)
    Label(content, L("Routes: /lazy route save|load|delete <name>.  Profiles: /lazy profile list|new|use|delete."))
    y = y - 26

    Header(content, "The Hive")
    Label(content, L("The Hive learns from how you play and shares with other players who have it on."))
    y = y - 26
    -- one on/off button that shows its state
    local function Toggle(x, w, name, get, set, advance)
        local b
        local function show() b:SetText(name .. ": " .. (get() and "|cff55ff55ON|r" or "|cffff5555OFF|r")) end
        b = Button(content, "", x, w, function() set(not get()); show() end, advance)
        refreshers[#refreshers + 1] = show
        show()
        return b
    end
    Toggle(16, 200, "The Hive", function() return DB().hiveOn == true end,
        function(v) if addon.HiveLiveSet then addon.HiveLiveSet(v) else DB().hiveOn = v end end, true)
    Label(content, L("ON: it learns your real XP per hour, the drops you loot and how long quests take, and exchanges those numbers, rare spawns and zone counts with other players who have it on, as hidden addon messages. It never sends your name, guild, items or chat, and never a track of where you are. The only places shared are rare sightings and coarse map squares where a quest objective was done or someone died (no name, no time). OFF: nothing is learned or shared."))
    y = y - 70
    Check(content, L("Use the places where quest objectives were really done instead of the original data"), 16,
        function() return DB().hiveSpots ~= false end, function(v) DB().hiveSpots = v end)
    Check(content, L("Item tooltips show the mobs seen dropping the item"), 16,
        function() return DB().hiveTooltip ~= false end, function(v) DB().hiveTooltip = v end)
    Check(content, L("Warn me when I walk into a place where players keep dying"), 16,
        function() return DB().dangerAlert ~= false end, function(v) DB().dangerAlert = v end)
    Check(content, L("Tell me when a rare shows up in my zone"), 16,
        function() return DB().hiveRareAlert ~= false end, function(v) DB().hiveRareAlert = v end)
    Check(content, L("Show reported rares as pins on the world map"), 16,
        function() return DB().hiveRarePins ~= false end, function(v) DB().hiveRarePins = v; if addon.HiveLiveChanged then addon.HiveLiveChanged() end end)
    Check(content, L("Share which zone I am in (as a count, never who)"), 16,
        function() return DB().hiveShareZone ~= false end, function(v) DB().hiveShareZone = v end)
    Button(content, L("What has it learned?"), 16, 150, function() addon:HandleExtraCommand("hive", "") end, false)
    Button(content, L("My pace"), 176, 90, function() addon:HandleExtraCommand("pace", "") end, false)
    Button(content, L("This session"), 276, 110, function() addon:HandleExtraCommand("session", "") end, true)
    Label(content, L("Commands: /lazy hive on|off, /lazy hive, /lazy pace, /lazy drops <item>, /lazy session, /lazy hive who, /lazy hive rares."))
    y = y - 26

    Header(content, "Ore and herb nodes")
    Label(content, L("Every node you mine or pick is marked on the world map. Hover a pin to see what it is. The arrow can lead you from node to node to farm them (right-click the arrow, or /lazy nodes farm)."))
    y = y - 50
    Check(content, L("Show my found nodes on the world map"), 16,
        function() return DB().nodePins ~= false end, function(v) DB().nodePins = v; if addon.RefreshNodePins then addon.RefreshNodePins() end end)
    Check(content, L("Also show them on the minimap"), 16,
        function() return DB().nodeMini ~= false end, function(v) DB().nodeMini = v; if addon.RefreshNodePins then addon.RefreshNodePins() end end)
    Radio(content, L("Show and farm:"), "nodeFilter", { { "all", "Ore and herbs" }, { "ore", "Ore only" }, { "herb", "Herbs only" } })
    Button(content, L("Farm them with the arrow"), 16, 190, function() addon:HandleExtraCommand("nodes", "farm " .. (DB().nodeFilter or "all")) end, false)
    Button(content, L("What do I have?"), 216, 130, function() addon:HandleExtraCommand("nodes", "") end, true)

    Header(content, "Quest tracker")
    Label(content, L("Forever Lazy's own tracker: your quests in plan order with XP, live objectives and who to turn in to. Click a quest to do it next (the arrow goes to it) and open it in your quest log, ctrl-click to share it, right-click for more. Questie has its own tracker: turn it off in Questie's options."))
    y = y - 50
    Check(content, L("Use Forever Lazy's quest tracker"), 16,
        function() return DB().trackerOn == true end, function(v) if addon.TrackerSet then addon.TrackerSet(v) else DB().trackerOn = v end end)
    Check(content, L("Hide WoW's own quest tracker while mine is on"), 16,
        function() return DB().trackerHideBlizzard ~= false end,
        function(v) DB().trackerHideBlizzard = v; if addon.TrackerSet and DB().trackerOn then addon.TrackerSet(true, v) end end)
    Check(content, L("Minimized (just the title, the zones and quests fold away)"), 16,
        function() return DB().trackerCollapsed == true end,
        function(v) DB().trackerCollapsed = v; if addon.HandleExtraCommand and DB().trackerOn then addon:HandleExtraCommand("tracker", "refresh") end end)
    Check(content, L("Hide the tracker while I am in combat"), 16,
        function() return DB().trackerHideCombat ~= false end, function(v) DB().trackerHideCombat = v end)
    Check(content, L("Compact: objectives only for the quest I am on, the others take one line"), 16,
        function() return DB().trackerCompact == true end, function(v) DB().trackerCompact = v; if addon.HandleExtraCommand and DB().trackerOn then addon:HandleExtraCommand("tracker", "refresh") end end)
    Check(content, L("No background (just the text, with an outline)"), 16,
        function() return DB().trackerNoBg == true end,
        function(v) DB().trackerNoBg = v; if addon.HandleExtraCommand and DB().trackerOn then addon:HandleExtraCommand("tracker", "refresh") end end)
    Button(content, L("Put the tracker back at the top right"), 16, 250, function() addon:HandleExtraCommand("tracker", "reset") end, true)

    Header(content, "Talents and skills")
    Check(content, L("Remind me about unspent talent points and new skills at my trainer (/lazy talents)"), 16,
        function() return DB().talentReminder ~= false end, function(v) DB().talentReminder = v end)

    Header(content, "Couch mode")
    Label(content, L("For playing on the TV with a controller: big text, quests accept and hand in by themselves, and steps are read aloud. A reward is never picked for you; the best one for your class is starred. Hold Shift to do it by hand."))
    y = y - 50
    Check(content, L("Couch mode (big text, auto accept and hand in, steps read aloud)"), 16,
        function() return DB().couch == true end, function(v) if addon.CouchSet then addon.CouchSet(v) end end)
    Check(content, L("Accept and hand in quests by myself (not dungeon, skipped or grey ones, and never choosing a reward)"), 16,
        function() return DB().couchAuto == true end, function(v) DB().couchAuto = v end)
    Check(content, L("Read the steps aloud as they change"), 16,
        function() return DB().couchSpeak == true end, function(v) DB().couchSpeak = v end)
    Slider(content, L("Voice speed"), -5, 5, 1, "%d", function() return DB().couchRate or 0 end, function(v) DB().couchRate = v end)
    Check(content, L("Inside a dungeon, point the arrow at what my quests need there"), 16,
        function() return DB().dungeonArrow ~= false end, function(v) DB().dungeonArrow = v end)

    Header(content, "Damage meter")
    Label(content, L("A damage meter in its own chat tab called Meter, laid out like Details: class icon, rank, name, a class-coloured bar, and total, per second and percent. Hover a name for that player's moves. It reads the game's built-in meter (the same source Details uses on this client). In combat the game hides the numbers, so the window keeps the last picture until the fight ends."))
    y = y - 50
    local function MeterToggle()
        local b
        local function show() b:SetText("Damage meter: " .. ((DB().meterOn == true) and "|cff55ff55ON|r" or "|cffff5555OFF|r")) end
        b = Button(content, "", 16, 200, function() if addon.MeterSet then addon.MeterSet(not (DB().meterOn == true)) end; show() end, false)
        refreshers[#refreshers + 1] = show
        show()
    end
    MeterToggle()
    Button(content, L("Clear the data"), 226, 130, function() addon:HandleExtraCommand("meter", "reset") end, false)
    Button(content, L("What does it see?"), 366, 150, function() addon:HandleExtraCommand("meter", "debug") end, true)
    Radio(content, "Show:", "meterMetric", {
        { "dps", "Damage per second" }, { "damage", "Damage done" }, { "healing", "Healing done" }, { "taken", "Damage taken" },
        { "hps", "Healing per second" }, { "interrupts", "Interrupts" }, { "deaths", "Deaths" } })
    Radio(content, "Fight:", "meterSegment", { { "current", "This fight" }, { "overall", "Everything since the last reset" } })
    Slider(content, L("Players listed"), 3, 20, 1, "%d", function() return DB().meterRows or 8 end, function(v) DB().meterRows = v end)
    Check(content, L("Live bars while I fight (a window over the Meter tab; the numbers are hidden from addons in a fight, so this is a try)"), 16,
        function() return DB().meterLive == true end, function(v) DB().meterLive = v or nil; if not v and addon.MeterLiveOff then addon.MeterLiveOff() end end)
    Header(content, "My waypoints")
    Label(content, L("Set one with /lazy way <x> <y> [name], /lazy way here, or Ctrl + right-click on the world map."))
    y = y - 26
    Check(content, L("Remove a waypoint automatically when I arrive"), 16,
        function() return DB().waypointAutoClear end, function(v) DB().waypointAutoClear = v end)
    Button(content, L("Drop at my position"), 16, 150, function() addon:DropWaypointHere() end, false)
    Button(content, L("Skip active"), 176, 110, function() addon:RemoveWaypoint(1) end, false)
    Button(content, L("Clear all"), 296, 100, function() addon:ClearWaypoints() end, true)
    Label(content, L("List them with /lazy way list, make one active with /lazy way <number>."))
    y = y - 26

    Header(content, "Library books")
    Label(content, L("Sets a waypoint for every known library book, nearest first. Replaces your current waypoints."))
    y = y - 26
    Check(content, L("Tell me in chat when I enter a zone that has books"), 16,
        function() return DB().bookAlert ~= false end, function(v) DB().bookAlert = v end)
    Check(content, L("Automatically add that zone's books as waypoints (keeps my other waypoints)"), 16,
        function() return DB().bookAuto == true end, function(v) DB().bookAuto = v end)
    Check(content, L("Leave out zones that are too high for my level (All books and auto)"), 16,
        function() return DB().bookLevelFilter ~= false end, function(v) DB().bookLevelFilter = v end)
    Check(content, L("Show every book on the world map (book = to find, green tick = collected)"), 16,
        function() return DB().bookPins ~= false end,
        function(v) DB().bookPins = v; if addon.RefreshBookPins then addon.RefreshBookPins() end end)
    Button(content, L("Mark nearest as collected"), 16, 190, function() addon:HandleExtraCommand("books", "done") end, false)
    Button(content, L("Mark nearest as not collected"), 216, 210, function() addon:HandleExtraCommand("books", "undone") end, false)
    Button(content, L("Clear collected list"), 436, 150, function() addon:HandleExtraCommand("books", "reset") end, true)
    Button(content, L("This zone (even collected)"), 16, 190, function() addon:HandleExtraCommand("books", "zone all") end, true)
    Button(content, L("All books"), 16, 100, function() addon:HandleExtraCommand("books", "") end, false)
    Button(content, L("This zone only"), 126, 130, function() addon:HandleExtraCommand("books", "zone") end, false)
    Button(content, L("Go to librarian"), 266, 130, function() addon:HandleExtraCommand("books", "turnin") end, false)
    Button(content, L("List books"), 406, 100, function() addon:HandleExtraCommand("books", "list") end, true)
    Button(content, L("Offer route to party"), 16, 160, function() addon:HandleExtraCommand("books", "share") end, false)
    Button(content, L("Post this zone in party chat"), 186, 190, function() addon:HandleExtraCommand("books", "say") end, true)
    Label(content, L("Offer: party members with this addon get a prompt to load it. Post: plain /way lines anyone can use."))
    y = y - 26
    Label(content, L("Same as /lazy books, books zone, books turnin, books list, books share, books say, books accept."))
    y = y - 26

    Header(content, "Map pins")
    Check(content, L("Quest pins on the world map"), 16,
        function() return DB().mapPins end, function(v) DB().mapPins = v; Changed() end)
    Check(content, L("Quest pins on the minimap"), 16,
        function() return DB().minimapPins end, function(v) DB().minimapPins = v; Changed() end)
    Check(content, L("Also set a TomTom waypoint (needs TomTom)"), 16,
        function() return DB().tomtom end, function(v) DB().tomtom = v; Changed() end)
    Check(content, L("Show minimap button"), 16,
        function() return DB().minimapButton end, function(v) DB().minimapButton = v; Changed() end)

    -------------------------------------------------------------- Profiles
    Header(content, "Settings")
    Check(content, L("Use separate settings for this character"), 16,
        function() return addon.GetRoot().useChar end,
        function(v)
            addon.GetRoot().useChar = v
            addon:SelectProfile()
            Changed()
            Refresh()
        end)

    y = y - 6
    Button(content, L("Reset positions"), 16, 130, function()
        local d = DB()
        d.pos = {}
        for k, v in pairs(addon.DEFAULTS.pos) do d.pos[k] = { point = v.point, x = v.x, y = v.y } end
        Changed()
    end, false)
    Button(content, L("Test quest arrow"), 156, 130, function()
        addon:SetStepText(nil, "Accept Buzzbox 827")
        addon.Print(L("simulated step: Accept Buzzbox 827"))
    end, false)
    Button(content, L("Test kill arrow"), 296, 130, function()
        addon:SetStepText(nil, "Kill Mottled Boar")
        addon.Print(L("simulated step: Kill Mottled Boar"))
    end, true)

    Label(content, L("Slash commands: /lazy (opens this), /lazy status, /lazy test <text>"))
    y = y - 30
    cur.bodyEnd = y

    Layout = function()
        local page = CurrentPage()
        local searching = query:match("%S") ~= nil
        for name, tab in pairs(shared.tabs) do tab:SetEnabled(searching or name ~= page) end
        for _, s in ipairs(sections) do
            s.header:Hide()
            for _, block in ipairs(s.blocks) do
                for _, it in ipairs(block.items) do it.obj:Hide() end
            end
        end
        local pos = topY
        local width = PageWidth(scroll.GetWidth and scroll:GetWidth())
        content:SetWidth(width)
        local plan = Plan(page, query)
        for _, entry in ipairs(plan) do
            pos = pos - 12
            local h = entry.parts[1][1].header
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 16, pos)
            h.fs:SetText(searching and (L(entry.page) .. "  >  " .. L(entry.title)) or L(entry.title))
            h:Show()
            pos = pos - 26
            for _, part in ipairs(entry.parts) do
                local s = part[1]
                for _, i in ipairs(part[2]) do
                    local block, after = s.blocks[i], s.blocks[i + 1]
                    local height = block.top - (after and after.top or s.bodyEnd)
                    local down, more = Wrap(block, height, width)
                    for n, it in ipairs(block.items) do
                        it.obj:ClearAllPoints()
                        it.obj:SetPoint("TOPLEFT", it.x, pos + it.y - down[n])
                        it.obj:Show()
                    end
                    pos = pos - height - more
                end
            end
        end
        if searching and #plan == 0 then shared.nothing:Show(); pos = pos - 30 else shared.nothing:Hide() end
        content:SetHeight(-pos + 10)
    end
    addon.OptionsModel = { pages = PAGES, sections = sections, Plan = Plan, Matches = Matches, BlockText = BlockText }   -- for the offline tests
    -- switching a module on or off (or a preset) shows or hides its options at once
    refreshers[#refreshers + 1] = function() if Layout then Layout() end end
end

-- put the shared scrolling page onto a Settings page and show the right group
local function AttachTo(page)
    local scroll = shared.scroll
    scroll:SetParent(page)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    scroll:Show()
    Layout()
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
    panel:SetScript("OnShow", function() AttachTo(panel) end)

    if _G.Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
        Settings.RegisterAddOnCategory(category)

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
        panel:SetScript("OnShow", function() AttachTo(panel) end)
    end
    standalone:SetShown(not standalone:IsShown())
    panel:Show()
    AttachTo(panel)
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
        caption:SetText(L("|cffff3333OH Oh OHH|r"))

        local by = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        by:SetPoint("TOP", caption, "BOTTOM", 0, -6)
        by:SetText(L("Brought to you by Sam Skinison and Tank Hanks"))

        local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOP", by, "BOTTOM", 0, -14)
        text:SetWidth(360); text:SetJustifyH("CENTER")
        text:SetText("|cff4db8ffWelcome to Forever Lazy!|r\n\n"
            .. "A compass at the top of the screen points at your quests and your next stop (/lazy arrow adds a big arrow). Click OK to open the options, "
            .. "where you can turn features on and off, and take a quick tour of the buttons.\n\n"
            .. "I have also added a few shared macros (type |cffffd100/macro|r and look for |cffffd100Lazy|r) that you can drag to your action bars.\n\n"
            .. "|cffaaaaaaTip: |cffffd100/lazy now|r|cffaaaaaa (or left-click the minimap button) points at the best next thing, and |cffffd100/lazy|r|cffaaaaaa opens the options any time.|r")

        local credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        credit:SetPoint("BOTTOM", 0, 46)
        credit:SetText(L("Photo: The World Famous Comedy Store, CC BY-SA 2.0 (via Wikimedia Commons)"))

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

-- put Forever Lazy in the AddOns list of the game's options from the start (it used to appear only after
-- the options had been opened once in a session)
local registerEv = CreateFrame("Frame")
pcall(registerEv.RegisterEvent, registerEv, "PLAYER_LOGIN")
registerEv:SetScript("OnEvent", function()
    local function go()
        local ok, err = pcall(Build)
        if not ok then addon.OptionsError = tostring(err) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(3, go) else go() end
end)
function addon.OptionsBuilt() return built and true or false end

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
