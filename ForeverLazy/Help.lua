-- Making it easier to learn: a first-run tour, settings export and import, and a "what's new" window.
--   /lazy tour       the tour (it also starts by itself after the welcome window)
--   /lazy export     my settings as one line of text to share
--   /lazy import     paste a line of settings
--   /lazy new        what changed in this version
local ADDON, ns = ...
local L = ns.L
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
    { text = "|cffffd100Welcome to Forever Lazy.|r This is a quick tour (11 short steps). It shows where the buttons are, so you never need to type a command. Press Next.",
      target = nil },
    { text = "|cffffd100The minimap button.|r Left-click: do the next best thing (Lazy Mode). Right-click: the menu with everything. Shift-click: the options.",
      target = function() return _G.ForeverLazy_MinimapButton end },
    { text = "|cffffd100The menu.|r This is what the right-click opens: go somewhere, plan your route, boats, journey, crafting, group, settings. Pick anything to try it.",
      target = nil, onShow = function() if addon.OpenMenu then addon:OpenMenu() end end, onHide = function() if _G.ForeverLazy_Menu then _G.ForeverLazy_Menu:Hide() end end },
    { text = "|cffffd100The compass and the arrow.|r The compass at the top shows your next stop. The big arrow is off until you type /lazy arrow. Both point the same way. The arrow points at your next stop. It goes to a finished quest you can hand in close by first, then to the closest stop, and it only points at stops in the zone you are in. Right-click it to skip a quest, put one off, or see why it chose this stop.",
      target = function() local a = _G.ForeverLazy_WaypointArrow; return a and a:IsShown() and a or nil end },
    { text = "|cffffd100The world map.|r Press M. In the top right there is a search box (\"Go to...\") and a Lazy button. Type a place, a city, a dungeon or a flight point, and press Enter: the arrow plans the whole trip. Your route shows on the map with numbered stops.",
      target = function() local w = _G.WorldMapFrame; return w and w:IsShown() and w or nil end },
    { text = "|cffffd100The quest log.|r Press L. Under it: Plan my route, Do this next, Skip this. Right-clicking the main arrow does the same. A skipped quest still gets its hand-in when it is close.",
      target = function() local q = _G.QuestLogFrame; return q and q:IsShown() and q or nil end },
    { text = "|cffffd100The hunt panel.|r When your quests need certain mobs, a small panel lists them. Click one to target it and put a skull on it. Close it with the X; the options bring it back.",
      target = function() local p = _G.ForeverLazy_HuntPanel; return p and p:IsShown() and p or nil end },
    { text = "|cffffd100Extras that are off until you want them.|r The craft planner (a plan beside your profession window), our own bag window and the damage meter tab are all in the options, along with range colours and quest item sparkles. Tick the ones you like. /lazy commands lists every command and /lazy report makes a bug report.",
      target = nil },
    { text = "|cffffd100Gear.|r Hover any item you could wear: a green Upgrade line says how much better it is for your class and spec. Upgrades in your bags get a green ^ in the bag window, and an optional gear bar (off until you turn it on in the options or with /lazy gear bar on) has a button that equips one when you click it. /lazy gear says what you are scored as.",
      target = function() local b = _G.ForeverLazyGearBar; return b and b:IsShown() and b or nil end },
    { text = "|cffffd100The options.|r /lazy opens them. There are eight pages, with buttons at the top; Start here has Just point me, Leveler, Duo and Everything. The search box finds a setting on any page. Switching a module off hides its options.",
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
    tour.text:SetText(L(step.text))
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
    f.title:SetPoint("TOPLEFT", 12, -10); f.title:SetText(L("Forever Lazy tour"))
    f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.counter:SetPoint("TOPRIGHT", -12, -14)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", 12, -36); f.text:SetWidth(336); f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP")
    f.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.back:SetSize(70, 22); f.back:SetPoint("BOTTOMLEFT", 12, 10); f.back:SetText(L("Back"))
    f.back:SetScript("OnClick", function() Leave(STEPS[idx]); idx = math.max(1, idx - 1); ShowStep() end)
    f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.next:SetSize(80, 22); f.next:SetPoint("LEFT", f.back, "RIGHT", 6, 0)
    f.next:SetScript("OnClick", function()
        Leave(STEPS[idx])
        if idx >= #STEPS then Finish() else idx = idx + 1; ShowStep() end
    end)
    local skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    skip:SetSize(70, 22); skip:SetPoint("BOTTOMRIGHT", -12, 10); skip:SetText(L("Skip"))
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
    close:SetSize(90, 24); close:SetPoint("BOTTOMRIGHT", -14, 12); close:SetText(L("Close"))
    close:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    return f
end

function addon.ExportSettings()
    box = box or BuildBox()
    local s = Export()
    box.title:SetText(L("Export my settings"))
    box.hint:SetText(L("Copy this line (Ctrl+A, Ctrl+C) and send it. The other player pastes it under Import."))
    box.edit:SetText(s or "I could not make the line")
    box.action:SetText(L("Select all"))
    box.action:SetScript("OnClick", function() box.edit:SetFocus(); box.edit:HighlightText() end)
    box:Show()
end

function addon.ImportSettings()
    box = box or BuildBox()
    box.title:SetText(L("Import settings"))
    box.hint:SetText(L("Paste a settings line here (Ctrl+V) and press Apply. Your waypoints and quests are not touched."))
    box.edit:SetText("")
    box.action:SetText(L("Apply"))
    box.action:SetScript("OnClick", function()
        local ok, n = Import(box.edit:GetText())
        if ok then
            Print(string.format(L("imported %d settings"), n))
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
    { "0.27.0", {
        "PALADINS, FIXED: the big blessing button now casts what it shows. One click could cast nothing when you were alone, or skip a player in a group.",
        "SHAMANS: point at a totem on the bar and all its totems pop out, so you click the one you want. It is set up to work in a fight too: please tell us if it does.",
        "SHAMANS: the panel has its own size, lock and layout (across or up and down), a totem recall button, and an option to hide the game's totem bar (off until you tick it).",
        "HAND-INS: a turn-in counts as reached from 20 yards, with the hand-in message, sound and minimap ping. The arrow and compass now find a hand-in close by from much farther off, as they were meant to.",
    } },
    { "0.26.0", {
        "RESTART THE GAME after updating if you want the new tombstone picture.",
        "THE BIG ARROW is now OFF until you turn it on: /lazy arrow. The compass shows the way: it points at the same stop the arrow would, and reaching a stop counts without the arrow.",
        "COMPASS ONLY? Under Compass you can show the next stop in words under the bar (off until you tick it).",
        "AS A GHOST the compass shows your body as a tombstone. Died in a dungeon? It leads to the entrance.",
        "LIBRARY BOOKS on the world map say which book they are when you hover, and right-click marks them collected or not. Other stops are no longer drawn as books.",
        "DUNGEONS: five more entrances (Alcaz Prison, Blackmaw Hold, The Drowned City, Krol'dok Stronghold, Shaper's Terrace), and names written as OpenMap writes them.",
    } },
    { "0.25.0", {
        "RESTART THE GAME after updating (not just /reload): this version has new files.",
        "THE OPTIONS are now pages with a search box that finds any setting. Point at a tick box or slider and it says what it does.",
        "THE COMPASS has its own page and its own rules: turning the arrows off no longer hides it. New: N E S W, distances, quest icons (each off until you tick it), hover a marker to see what it is, right-click for a menu.",
        "SHAMANS get helpers under My class: totem bar with timers and sets, range warning, weapon and shield buttons, ankh count, cure buttons, a Purge mark and a Ghost Wolf reminder. All off until you tick them.",
        "PALADINS: the blessing panel is now OFF until you turn it on: /lazy blessings on, or the options under My class.",
        "CLICK A QUEST in the tracker and the arrow goes to it (and it still opens in your quest log).",
        "A new option under Nameplates flashes a mob's cast bar while your interrupt is ready. Hammer of Justice counts as a paladin interrupt.",
    } },
    { "0.24.8", {
        "THE MAP is less crowded: where to kill or collect is now shown as coloured areas, one colour for each quest, without skulls and diamonds on top (they are an option under Quest map). Pins are smaller.",
        "THINGS ON THE GROUND you need to click for a quest show as small green dots. They could be missing when mobs also dropped the item.",
        "FAR AWAY QUESTS no longer wait until you walk up to them to show on the world map.",
        "PALADINS: when everyone is blessed, the big button no longer casts on the last player again.",
        "GROUP FINDER FILTER: picking a role now works for players looking too, so a leader can look for just damage, a healer or a tank.",
    } },
    { "0.24.7", {
        "THE HUNT WINDOW works again: clicking a mob in it targets the mob and puts a skull on it. The buttons did not react to the click on some setups.",
    } },
    { "0.24.6", {
        "PEOPLE WITH QUESTIE can see your quest progress again: we sent them a message type their Questie did not know, so it showed an error line in their chat and ignored it. Now it is one they read.",
        "THE ARROW goes to a finished quest you can hand in nearby (within about 450 yards) even when your plan has no stop for it, for example a plan that is only library books.",
    } },
    { "0.24.5", {
        "PALADIN BLESSINGS: each class row now shows who still needs the blessing, or the shortest time left on it (amber under 2 minutes). LEFT-CLICK a class row to bless the next person of that class who needs it. RIGHT-CLICK cycles that class's blessing (shift-right-click goes back), which used to be the left-click.",
        "The blessing button no longer keeps trying a player a cast failed on (out of range, out of sight): it steps past them for 30 seconds.",
    } },
    { "0.24.4", {
        "BANK BAG SLOTS now work from our own bank window: a small box under it shows your eight bank bag slots. Click an empty slot with a bag on your cursor to put the bag in, click a filled one to take it out, and the green + buys the next slot (the game asks you to confirm, and the price shows when you hover). /lazy bankslots window brings the game's own bank window forward if you want it.",
    } },
    { "0.24.3", {
        "The CHAT INPUT BOX ON TOP no longer covers the chat tabs: it sits above the row of tabs now, so General, Combat Log and the others stay clickable.",
        "CHAT TABS NEVER FADE (off until you turn it on: /lazy chat tabs solid, or the tickbox under Chat in the options): General, Combat Log and the other tabs stay fully visible instead of dimming when the mouse is away. /lazy chat tabs default puts the game's own fading back.",
    } },
    { "0.24.2", {
        "THE BANK WINDOW counts the right containers now: it said 32 free when the game said the bank was full. It redraws when a bank slot is bought, and the item counts never count your bags as bank.",
        "BANK BAG SLOTS: a button under the bank window brings the game's own bank window forward, where you buy slots and put bags in them. /lazy bankslots says what this client offers.",
        "The row of text tabs at the top of the bag window (All, Quest, Equipment...) is off by default, since the sections already name each kind of item. The window's settings (the ... button) have Category tabs on top to bring it back.",
    } },
    { "0.24.1", {
        "SPELL RANK UPGRADES are off until you turn them on (the Newest spell rank tickbox in the options). /lazy rankup, or the Fix my bars now button, still does it once whenever you ask.",
        "The QUEST ITEM BAR is gone: the strip of quest item buttons near the bottom of the screen and the pop-up bar for quest items. The quest tracker still shows an item button beside a quest that has one.",
    } },
    { "0.24.0", {
        "SELL GREY LOOT (off until you turn it on: the Sell grey loot tickbox in the options, or /lazy sellgray on): when a vendor opens, the grey items in your bags are sold and the total is said in chat. Items you protect with /lazy keep are never sold. /lazy sellgray now sells at an open vendor any time.",
        "FASTER AUTO LOOT (off until you turn it on: /lazy fastloot on): the loot window empties the moment it opens, when auto loot is on in the game's options.",
    } },
    { "0.23.2", {
        "The item tooltip no longer says your bank holds what is in your bags. The bank scan counted a container you carry as bank. Open your bank once on each character to refresh its saved bank, and /lazy inventory lists what is counted as bags and bank.",
    } },
    { "0.23.1", {
        "FRESH QUEST DATA from QuestieDB 1.1.6: one new quest, fixes to about 65 quests (chains, quest spots, the Tattered Journal starter), moved creature spawns, new objects, two corrected drop chances, faction fixes for four NPCs and five new quest XP values.",
    } },
    { "0.23.0", {
        "LIVE METER BARS (off until you turn them on: the Live bars tickbox under Damage meter, or /lazy meter live on). The game hides damage numbers from addons while you fight, so the Meter tab could only show its last picture. For the length of a fight a window of real bars now sits over the Meter tab and moves as you fight, then the tab shows the full list again.",
        "RANGE COLOURS are off until you turn them on (the Colour action buttons tickbox in the options, or /lazy range on).",
    } },
    { "0.22.4", {
        "The BLESSINGS button moves on to the next person after each click, so it no longer blesses the same player again and again, and it moves on when a cast did not land.",
        "KEYS no longer get an item button: a key that a quest gives you (like the Dalaran Sewer Key) opens a gate when you walk up to it. /lazy keys show brings the buttons back.",
    } },
    { "0.22.3", {
        "Item tooltips list each of your characters once. A character that had been saved under several realm spellings showed up as extra lines (for example Bad, Bad Altitude and Bad-CAMWOW) and was counted twice.",
    } },
    { "0.22.2", {
        "The GEAR BAR is off until you turn it on (tick Gear bar in the options, or /lazy gear bar on). The green ^ arrows in the bags and at vendors and the Upgrade line in tooltips are not affected.",
    } },
    { "0.22.1", {
        "GROUP FINDER FILTER: open the Browse tab, search, then click Filter groups (or /lazy groups). Drop-down lists pick groups or lone players, a role a started group still needs (a healer, say), how new the listing is and the sort order, and you can search words and fit your level. Click a row to whisper the leader.",
        "PALADIN BLESSINGS now work with other paladins who have Forever Lazy: if two of you give the same blessing to a class, the one first in the alphabet casts it. A Split button gives every class a blessing the others are not giving, /lazy blessings team shows everyone's choices, and the button covers a class when the other paladin is dead or far away. The Blessings button casts now.",
        "NAMEPLATES: an aggressive mob is red BEFORE it attacks you, not just in a fight; a mob fighting someone else is orange.",
        "GEAR ADVISOR: green ^ arrows now show in the standard bag windows too, and /lazy gear why explains each piece of gear in your bags.",
        "The quest tracker inside a dungeon lists only that dungeon's quests, and /lazy dungeons here now finds a dungeon this server does not label as one.",
        "The PEDOMETER counts now (it was reading only part of your position), and so do a few quest and map spots that had the same mistake.",
        "Item tooltips no longer list your own character twice, and after an update you get one line in chat instead of a window.",
    } },
    { "0.22.0", {
        "PEDOMETER! It adds up how far you walk on foot (not mounted, not on a flight): this session, today, this level and in total, plus the zones you walk the most. /lazy steps shows it, /lazy steps show puts a small readout on the screen. The unit follows your distance setting (yards, meters or steps).",
        "PALADIN BLESSINGS: for a paladin in a group, one button blesses the next player who needs it, and you pick the blessing for each class by clicking it (Might for fighters and Wisdom for casters to start with). /lazy blessings shows or hides the panel, /lazy blessings debug shows what it sees.",
        "NAMEPLATE COLOURS (off until you turn them on, in the options under Nameplates): a hostile mob attacking you is RED, one fighting someone else is yellow, and a quest mob that is not in a fight is purple. You pick the colours. /lazy platecolors on|off.",
        "/lazy lfg shows what the group finder gives to addons, to see what a group finder filter could do.",
    } },
    { "0.21.0", {
        "TRANSLATIONS are possible now: every text goes through one lookup, so a language file only has to list the texts. About 940 are ready to translate (docs/LOCALIZATION.md). Until a language is added, everything stays English. /lazy l10n shows the state, and the options have a Language button.",
        "Stop labels like Turn in: and Pick up: are shown in your language once translated, while the rules that use them keep working on the English words.",
    } },
    { "0.20.0", {
        "GEAR ADVISOR! Hover an item and a green line says if it is an upgrade for your class and spec (stat priorities from the WoW Forever lists). Upgrades in your bags get a green ^ in the bag window and a button on the gear bar: click it to equip. /lazy gear shows what you are scored as, /lazy gear stats shows what it reads from your gear.",
        "QUEST ITEM SPARKLES: the game's own sparkle on quest items you can loot stays on, even after a graphics preset (credit: Forever Loot Sparkles by Ashtar Senior).",
        "RANGE COLOURS: action buttons turn red out of range, blue without mana, grey when unusable (credit: tullaRange by Tuller). Both step aside if those addons are installed.",
        "The quest reward star uses the same gear scoring now.",
        "The SPELL RANK SWAP works now (it stopped on an event this game does not know). /lazy rankup keep <spell> keeps a low rank on purpose.",
        "Something wrong? /lazy report makes a bug report you can copy (nothing is sent), /lazy commands lists every command, /lazy apis checks the game functions the new features need.",
    } },
    { "0.19.1", {
        "FRESH QUEST DATA from Questie 12.13.0 (QuestieDB 1.1.5): new quests and objects, moved creature spawns, and updated quest flags (repeatable and daily quests).",
        "Seven quest titles that showed in Title Case (Look To The Stars) are spelled like the game now (Look to the Stars).",
    } },
    { "0.19.0", {
        "ARROW AND PLAN: a finished quest you can hand in CLOSE BY now goes first (not the ones back in town), the arrow clears the stop it points at when you arrive, and the arrow says why it points where it does. A quest you skipped still gets its hand-in when it is close.",
        "THE TRACKER: click a quest to open it in the quest log, shift-click to move the plan and arrow to it, ctrl-click to share it. Quest item buttons work again.",
        "THE OPTIONS open on a Start here page (Just point me, Leveler, Duo, Everything), with the extras you can tick on or off, and show only the basics until you press Show all options. A module that is off hides its options.",
        "The DAMAGE METER tab looks more like Details: class icon, rank, name, a bar, total, per second and percent.",
        "The quest item bar is off by default, and the whole options text got a plain-words pass.",
        "FRESH QUEST DATA from Questie 12.12.0 (QuestieDB 1.1.4): about 100 new quests, many fixes to levels, zones, drops and names. Rebuilt without needing the game.",
    } },
    { "0.17.7", {
        "Party announcements show [Forever Lazy] in YELLOW for everyone running the addon.",
    } },
    { "0.17.6", {
        "HUNT PANEL! A little panel with a button for every mob your quests need. Click one to target it and put a skull on it. Follow a friend's plan and it names the mobs for their stop too. Close it with the X.",
        "The ARROW goes to the CLOSEST stop in your zone, and hands in quests that are about to turn grey first.",
        "PLAN SHARING calms down: no more asking you to accept a new plan after every kill, and shared plans carry their quest ids.",
        "The BAG WINDOW is off by default (the game has its own one-bag view). Turning ours off turns the game's Combine Bags on. Free slots count is the game's own number.",
        "The minimap button sits on the outer edge of any minimap, trainer visits only at even levels, the craft planner is off by default, and the what's-new window fades after 5 seconds.",
    } },
    { "0.17.5", {
        "FREE SLOTS ON TOP! The bag window shows your empty slots first, so you can drop things in right away.",
        "/lazy pet test no longer leaves the pet reminder stuck on when you are not a hunter.",
        "CREDITS: thanks to Questie, whose quest data this addon builds on. See media/CREDITS.txt.",
    } },
    { "0.17.4", {
        "OPTIONS FIXED! Eleven checkboxes (quest sounds, the quest map switches, nameplate icons, the interrupt marker, the spell rank swap and more) could only turn OFF, never back ON. Now they work both ways. OHHHH!",
        "The bag settings for auto sort, quest border and item level had the same bug. Fixed too.",
        "SPELL RANK SWAP talks now: Fix my bars now, or /lazy rankup, tells you why nothing changed. /lazy rankup debug shows what the bars look like.",
    } },
    { "0.17.3", {
        "BAG BUG FIXED! An error popped up after every bag change since 0.17.1 (the auto sort). GONE!",
        "PLAN SPAM FIXED! A group plan is only sent, and only announced, when it actually changes.",
        "The ARROW stays in the zone you are in. It no longer picks a kill spot over the border.",
        "FEWER ! on nameplates: only mobs that really drop a quest starter, and not when you already carry the item or did the quest.",
        "A TOUGHER DAMAGE METER: one hidden player no longer blanks the list, the Meter tab comes back if you close it, hover tooltips never go stale, and a new dungeon starts a fresh meter (/lazy meter autoreset off to keep old numbers).",
    } },
    { "0.17.2", {
        "PLAN SPAM FIXED! A group plan is only sent, and only announced, when it actually changes. No more same message over and over!",
        "The release zip is cleaner (just the ForeverLazy folder). Download ForeverLazy-0.17.2.zip, not GitHub's Source code.",
    } },
    { "0.17.1", {
        "THE BANK IS A SECOND WINDOW!! Open the bank and your bags sit on the right, the bank on the left. Move stuff across. OHHHH!",
        "Your HEARTHSTONE has its own TRAVEL section at the very top of the bag.",
        "Right-click an item in the bag to USE it again (recipes, food, the sleeping bag).",
        "OPENMAP PLAYS NICE: quest areas, skulls, diamonds, ! and ? show on its big map, and quest givers show for the map you are LOOKING at, not just where you stand.",
        "/lazy questmap debug opens a popup you can copy. /lazy tracker debug does the same for the tracker.",
    } },
    { "0.17.0", {
        "THE BAG HAS REAL SECTIONS NOW!! Equipment, Food and drink, Potions, Bandages, Consumables, Trade goods, Reagents, Recipes, Gems, Ammo, Bags, Keys, Misc and Junk. A section only shows up when you carry something for it! OHHHH!",
        "The bag SCROLLS now, so a full bag is not a giant window. The category buttons are plain text tabs, and the section names are bigger.",
        "NEW SPELL RANK? It goes on your action bars BY ITSELF, in place of the old rank. Switch it off in the options if you hate fun.",
        "INTERRUPT MARKER on nameplates! A mob casts, you see the spell. GREEN border, your interrupt is ready. RED, it is on cooldown. GREY, you have none.",
        "QUEST ITEM REMINDER! Stand where a quest wants an item used and a BUTTON with the item pops up. Click it. Shift-drag to move it.",
        "Quest starter mobs get a BIG gold ! above the nameplate. Pick up a quest from an item drop and your party hears about it!",
        "Click a quest on the game's world map and the arrow points to it. A pin you click in another zone no longer vanishes.",
        "The arrow no longer points at a quest in ANOTHER zone. It waits until you are there, or shows the next stop that is here.",
        "FIXED: nameplate swords and loot bags go away when the quest needs no more of that mob.",
    } },
    { "0.16.0", {
        "ONE BAG WINDOW!! All your bags in ONE window with search, category buttons, quality borders, auto sort and the bank too. Press B! Turn Bagnon OFF and this takes over. OHHHH!",
        "Look inside your OTHER characters' bags, bank and mail from the same window. Full names, like Tank Hanks!",
        "Pick LAYOUT BY CATEGORY in the ... settings and your stuff sorts into Quest, Gear, Consumables, Trade goods, Misc and Junk!",
        "NAMEPLATE ICONS like Questie! A SWORD on mobs you need to kill, a LOOT BAG on mobs that drop what you need, a bag with a ! on mobs that drop a quest STARTER.",
        "The party hears about it! Finish a quest and Forever Lazy tells your group what you did.",
        "QUEST SEARCH, QUEST HISTORY, QUEST CHAINS and quest link tooltips in chat. A ping when you stand next to the person who takes your finished quest!",
        "The coach finds NEW zones and dungeons by itself, so the levelling guide keeps up with WoW Forever. The guide text no longer overlaps.",
        "CHAT TWEAKS like Prat: timestamps, class colours, short channel names, keyword highlight, copy chat, links you can click, and chat windows you can RESIZE. All off until you turn them on in the options!",
        "FIXED: drop rates over 100% in item tooltips now say about 1.5 per kill. Other characters show their full names in item tooltips, and one character no longer shows up twice.",
    } },
    { "0.15.4", {
        "QUEST STARTER ITEMS GO AWAY!! An item that only STARTED a quest no longer sits on your quest item button once the quest is in your log. OHHHH!",
    } },
    { "0.15.3", {
        "CLICK A QUEST in the tracker and it OPENS in your quest log! Ctrl-click to do it next. Yeah!",
        "The tracker title counts your quests out of 40, like 16/40. OHHHH!",
    } },
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
        "Turn the plan off and keep your place: /lazy plan off, /lazy plan on. The route lines and markers go away while it is off.",
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
-- autoFade: the window that comes up by itself after an update fades away after 5 seconds (staying put while the mouse is on it)
local function ShowNew(current, newer, who, autoFade)
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
        -- Sam, top right (photo: media/CREDITS.txt, CC BY-SA 2.0)
        local face = f:CreateTexture(nil, "ARTWORK")
        face:SetSize(56, 56)
        face:SetPoint("TOPRIGHT", -14, -12)
        face:SetTexture("Interface\\AddOns\\ForeverLazy\\media\\kinison.tga")
        face:SetTexCoord(62 / 256, 186 / 256, 28 / 256, 152 / 256)
        local ohh = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ohh:SetPoint("TOP", face, "BOTTOM", 0, -2)
        ohh:SetText(L("|cffff3333OH Oh OHH|r"))
        local by = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        by:SetPoint("TOPLEFT", 14, -6); by:SetWidth(330); by:SetJustifyH("LEFT")
        by:SetText(L("Brought to you by Sam Skinison and Tank Hanks"))
        local credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        credit:SetPoint("BOTTOM", 0, 14)
        credit:SetWidth(170)
        credit:SetText(L("Photo: The World Famous Comedy Store, CC BY-SA 2.0 (Wikimedia Commons)"))
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
        tourBtn:SetSize(120, 24); tourBtn:SetPoint("BOTTOMLEFT", 14, 12); tourBtn:SetText(L("Take the tour"))
        tourBtn:SetScript("OnClick", function() f:Hide(); addon.StartTour() end)
        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetSize(90, 24); close:SetPoint("BOTTOMRIGHT", -14, 12); close:SetText(L("Close"))
        close:SetScript("OnClick", function() f:Hide() end)
        f:SetScript("OnUpdate", function(self, dt)
            if not self.fadeLeft then return end
            if self:IsMouseOver() then self.fadeLeft = 5; self:SetAlpha(1); return end       -- reading it: it stays
            self.fadeLeft = self.fadeLeft - dt
            if self.fadeLeft <= 0 then
                self.fadeLeft = nil; self:Hide(); self:SetAlpha(1)
            elseif self.fadeLeft < 1 then
                self:SetAlpha(self.fadeLeft)                                                 -- the last second fades out
            end
        end)
        f:SetScript("OnHide", function(self) self.fadeLeft = nil; self:SetAlpha(1) end)
        f:Hide()
        return f
    end)()
    newWin.fadeLeft = nil
    newWin:SetAlpha(1)
    local lines = {}
    for _, v in ipairs(NEW) do
        lines[#lines + 1] = "|cffffd100" .. v[1] .. "|r"
        for _, item in ipairs(v[2]) do lines[#lines + 1] = "  - " .. L(item) end
        lines[#lines + 1] = ""
    end
    newWin.title:SetText(L("What's new new |cffff3333NEWWW!|r"))
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
    if autoFade and not newer then newWin.fadeLeft = 5 end
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
            Print(L("a quick tour of the buttons: /lazy tour"))
        end
        if root.seenVersion and root.seenVersion ~= current and root.welcomed then
            -- a line in chat, not a window that gets in the way (the full list is one command away)
            Print(string.format(L("Updated to v%s: type /lazy new to see what's new, or use the What's new button in the options."), (tostring(current):gsub("^v", ""))))
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
    elseif word == "new" or word == "whatsnew" then
        if ((rest or ""):lower():gsub("%s", "")) == "test" then
            -- shows the line a player gets after an update, so it can be seen without updating
            Print(string.format(L("Updated to v%s: type /lazy new to see what's new, or use the What's new button in the options."), (tostring(Version()):gsub("^v", ""))))
        else addon.ShowWhatsNew() end
        return true
    elseif word == "welcome" then if addon.ShowWelcome then addon.ShowWelcome() end; return true end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Help.lua"] = true end end
