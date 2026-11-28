-- The fishing skill each zone asks for, and a route for raising your fishing.
--   the fishing bar can show what the zone you are in needs (off until you tick it); /lazy fish status says it too
--   /lazy fish route      a window: where to fish at your skill, what to train next, with buttons that point the arrow
--   while the arrow is taking me somewhere from that window, it is a fish
-- The zone numbers are from WoW Forever fishing guides (bytetavern, timesaver), which say they come from Classic.
-- Nothing in the game tells addons these numbers, and new Forever zones have none yet.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local R = {}
addon.FishRoute = R

--------------------------------------------------------------------------------
-- The numbers (pure logic: tests/fishroute.lua)
--------------------------------------------------------------------------------
-- need: the skill at which no fish gets away. least: the skill below which nothing is caught (nil: not given)
local LEAST = { [25] = 1, [75] = 1, [150] = 55, [225] = 130, [300] = 205 }
-- by map id: { English name, need, lowest and highest monster level, who the route sends there: A, H, AH or nil }
local ZONES = {
    [1429] = { "Elwynn Forest", 25, 1, 10, "A" }, [1426] = { "Dun Morogh", 25, 1, 10, "A" }, [1438] = { "Teldrassil", 25, 1, 10, "A" },
    [1411] = { "Durotar", 25, 1, 10, "H" }, [1412] = { "Mulgore", 25, 1, 10, "H" }, [1420] = { "Tirisfal Glades", 25, 1, 10, "H" },
    [1436] = { "Westfall", 75, 10, 20, "A" }, [1432] = { "Loch Modan", 75, 10, 20, "A" }, [1439] = { "Darkshore", 75, 10, 20, "A" },
    [1413] = { "The Barrens", 75, 10, 25, "H" }, [1421] = { "Silverpine Forest", 75, 10, 20, "H" },
    [1453] = { "Stormwind City", 75 }, [1455] = { "Ironforge", 75 }, [1457] = { "Darnassus", 75 },
    [1454] = { "Orgrimmar", 75 }, [1456] = { "Thunder Bluff", 75 }, [1458] = { "Undercity", 75 },
    [1433] = { "Redridge Mountains", 150, 15, 27, "A" }, [1431] = { "Duskwood", 150, 18, 30, "A" }, [1437] = { "Wetlands", 150, 20, 30, "A" },
    [1440] = { "Ashenvale", 150, 18, 30, "AH" }, [1424] = { "Hillsbrad Foothills", 150, 20, 30, "AH" },
    [1442] = { "Stonetalon Mountains", 150, 15, 27, "H" },
    [1441] = { "Thousand Needles", 225, 25, 35, "H" }, [1417] = { "Arathi Highlands", 225, 30, 40, "AH" },
    [1416] = { "Alterac Mountains", 225, 30, 40, "AH" }, [1443] = { "Desolace", 225, 30, 40, "AH" },
    [1434] = { "Stranglethorn Vale", 225, 30, 45, "AH" }, [1445] = { "Dustwallow Marsh", 225, 35, 45, "AH" },
    [1435] = { "Swamp of Sorrows", 225, 35, 45, "AH" },
    [1444] = { "Feralas", 300, 40, 50, "AH" }, [1446] = { "Tanaris", 300, 40, 50, "AH" }, [1425] = { "The Hinterlands", 300, 40, 50, "AH" },
    [1447] = { "Azshara", 300, 45, 55, "AH" }, [1448] = { "Felwood", 300, 48, 55, "AH" }, [1422] = { "Western Plaguelands", 300, 51, 58, "AH" },
    [1449] = { "Un'Goro Crater", 300 }, [1450] = { "Moonglade", 300 },
    -- only one of the guides gives these
    [1428] = { "Burning Steppes", 425 }, [1430] = { "Deadwind Pass", 425 }, [1423] = { "Eastern Plaguelands", 425 },
    [1451] = { "Silithus", 425 }, [1452] = { "Winterspring", 425 },
}
R.ZONES = ZONES
local TIERS = { 25, 75, 150, 225, 300 }

function R.Zone(map)
    local z = ZONES[map]
    if not z then return nil end
    return { map = map, name = z[1], need = z[2], least = LEAST[z[2]], low = z[3], high = z[4], side = z[5] }
end

-- "good": nothing gets away. "some": some do. "none": nothing can be caught. nil when my skill is not known
function R.Verdict(skill, zone)
    if not skill or not zone then return nil end
    if skill >= zone.need then return "good" end
    if zone.least and skill < zone.least then return "none" end
    return "some"
end

local COLOR = { good = "ff40c040", some = "ffffff00", none = "ffff4040" }
local WORDS = { good = "nothing gets away", some = "some get away", none = "too low to catch anything" }

-- short: for the fishing bar
function R.Line(skill, zone, short)
    if not zone then return L("Zone fishing level: not known here") end
    local text = string.format(L("This zone: %d fishing"), zone.need)
    local v = R.Verdict(skill, zone)
    if v then text = text .. " |c" .. COLOR[v] .. "(" .. L(WORDS[v]) .. ")|r" end
    if not short then text = text .. L(". Your pole, lure and fishing gear count too.") end
    return text
end

-- where to fish: the hardest water where nothing gets away that my side has and my level can walk in
-- side: "A" or "H". gives the zones (easiest monsters first), their tier, and true when even these are rough for my level
function R.Pick(skill, side, level)
    local best = 1
    for i, tier in ipairs(TIERS) do if (skill or 1) >= tier then best = i end end
    local function Of(tier)
        local list = {}
        for map, z in pairs(ZONES) do
            if z[2] == tier and z[5] and z[5]:find(side, 1, true) then list[#list + 1] = R.Zone(map) end
        end
        table.sort(list, function(a, b) if a.low ~= b.low then return a.low < b.low end return a.name < b.name end)
        return list
    end
    for i = best, 1, -1 do
        local safe = {}
        for _, z in ipairs(Of(TIERS[i])) do if not level or z.low <= level + 3 then safe[#safe + 1] = z end end
        if #safe > 0 then return safe, TIERS[i], false end
    end
    return Of(TIERS[1]), TIERS[1], true
end

-- the next, harder water; nil at the top
function R.NextTier(tier)
    for _, t in ipairs(TIERS) do if t > tier then return t end end
end

-- what to train next. gives words and what the button should do: "trainer", "heming", "pagle" or nil
function R.Training(rank, max, level)
    if not rank then return L("Learn Fishing from a fishing trainer, and buy a fishing pole."), "trainer" end
    max, level = max or 0, level or 60
    local stuck = (max > 0 and rank >= max) and L("Your skill is at its limit. ") or ""
    if max > 0 and max <= 75 then
        if rank >= 50 and level >= 10 then return stuck .. L("Train Journeyman at a fishing trainer."), "trainer" end
        return stuck .. L("Journeyman: a fishing trainer teaches it at fishing 50 and level 10."), "trainer"
    elseif max > 0 and max <= 150 then
        return stuck .. L("Expert: buy the book Expert Fishing - The Bass and You from Old Man Heming in Booty Bay (fishing 125, level 20, 1 gold)."), "heming"
    elseif max > 0 and max <= 225 then
        return stuck .. L("Artisan: Nat Pagle's quest in Dustwallow Marsh (fishing 225, level 35)."), "pagle"
    end
    return L("Nothing left to train.")
end

-- the pool spot to send me to: the one nearest the middle of the zone's pools, so the arrow lands where the water is
function R.BestSpot(spots, map)
    local mine, x, y = {}, 0, 0
    for _, s in ipairs(spots or {}) do
        if s.uiMapId == map and s.zx and s.zy then
            mine[#mine + 1] = s
            x, y = x + s.zx, y + s.zy
        end
    end
    if #mine == 0 then return nil end
    x, y = x / #mine, y / #mine
    local best, bestD
    for _, s in ipairs(mine) do
        local d = (s.zx - x) ^ 2 + (s.zy - y) ^ 2
        if not bestD or d < bestD then best, bestD = s, d end
    end
    return best
end

--------------------------------------------------------------------------------
-- What the game says
--------------------------------------------------------------------------------
-- the zone I am in, also from a cave or other small map inside it
function R.Here()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    for _ = 1, 4 do
        if not map then return nil end
        if ZONES[map] then return R.Zone(map) end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        map = info and info.parentMapID
    end
end

local function ZoneName(zone)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zone.map)
    return (info and info.name) or zone.name
end

local function Skill()
    if addon.Fish and addon.Fish.Skill then return addon.Fish.Skill() end
end

local function Side()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return faction == "Horde" and "H" or "A"
end

local function ArrowHint()
    if addon.ArrowHidden and addon.ArrowHidden() then Print(L("the compass shows the way. For the big fish arrow too: /lazy arrow")) end
end

function R.GoZone(map)
    local zone = R.Zone(map)
    if not zone then return end
    local name = ZoneName(zone)
    if not (addon.GoTo and addon.PoolSpots) then Print(L("I cannot set the arrow just now.")); return end
    local ready = addon.PoolSpots(function(spots)
        local spot = R.BestSpot(spots, map)
        if spot then
            addon.GoTo(map, spot.zx, spot.zy, L("Fishing in ") .. name, "fish")
            ArrowHint()
        else
            Print(string.format(L("I know no fishing spot to point at in %s: any water there will do."), name))
        end
    end)
    if not ready then Print(L("still loading, try again in a moment")) end
end

-- where the two teachers stand
local PEOPLE = {
    heming = { 1434, 0.2742, 0.7716, "Old Man Heming" },
    pagle = { 1445, 0.5861, 0.6006, "Nat Pagle" },
}

function R.Train(what)
    if what == "trainer" then
        addon:HandleExtraCommand("trainer", "fishing")
        -- the trainer search puts its stop first: that one is part of the fishing route, so its arrow is a fish
        local d = addon.GetDB()
        local first = d and d.waypoints and d.waypoints[1]
        if first and first.service then first.fish = true; ArrowHint() end
    elseif PEOPLE[what] and addon.GoTo then
        local p = PEOPLE[what]
        addon.GoTo(p[1], p[2], p[3], p[4], "fish")
        ArrowHint()
    end
end

-- everything the window says. gives { skill =, zones = { { map =, text = } }, warning =, next =, training =, action = }
function R.Plan(rank, max, side, level)
    local plan = {}
    plan.skill = rank and string.format(L("Your fishing: %d of %d"), rank, max or 0) or L("You have not learned fishing, or the game does not say your skill.")
    local zones, tier, rough = R.Pick(rank, side, level)
    plan.zones = {}
    for i = 1, math.min(4, #zones) do
        local z = zones[i]
        plan.zones[i] = { map = z.map, text = string.format(L("%s  (monsters %d-%d)"), ZoneName(z), z.low, z.high) }
    end
    if rough then plan.warning = L("Careful: the monsters there are above your level.") end
    local nextTier = R.NextTier(tier)
    if nextTier and (not rank or rank < nextTier) then
        plan.next = string.format(L("Move on to harder water at fishing %d."), nextTier)
    elseif nextTier then
        plan.next = L("Harder water is waiting once your level can handle it.")
    else
        plan.next = L("These are the last waters on the route.")
    end
    plan.training, plan.action = R.Training(rank, max, level)
    return plan
end

--------------------------------------------------------------------------------
-- The window (only when you ask for it)
--------------------------------------------------------------------------------
local win, texts, zoneButtons, trainButton, action

local function Build()
    if win then return end
    win = CreateFrame("Frame", "ForeverLazy_FishRoute", UIParent)
    win:SetSize(360, 360)
    win:SetPoint("CENTER", 0, 60)
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local bg = win:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.85)
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    texts = {}
    local function At(key, y, font)
        local fs = win:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
        fs:SetWidth(330)
        fs:SetJustifyH("LEFT")
        fs:SetPoint("TOPLEFT", 14, y)
        texts[key] = fs
    end
    At("title", -12, "GameFontNormalLarge")
    At("skill", -38)
    At("here", -54)
    At("fish", -86, "GameFontNormal")
    zoneButtons = {}
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetSize(330, 22)
        b:SetPoint("TOPLEFT", 14, -104 - (i - 1) * 25)
        b:SetScript("OnClick", function(self) if self.map then R.GoZone(self.map) end end)
        zoneButtons[i] = b
    end
    At("warning", -208)
    At("next", -224)
    At("training", -248)
    trainButton = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    trainButton:SetSize(200, 22)
    trainButton:SetPoint("TOPLEFT", 14, -296)
    trainButton:SetText(L("Point me there"))
    trainButton:SetScript("OnClick", function() if action then R.Train(action) end end)
    At("foot", -328, "GameFontDisableSmall")
    texts.title:SetText(L("Fishing route"))
    texts.fish:SetText(L("Fish in one of these (click to set the arrow):"))
    texts.foot:SetText(L("Zone numbers come from fishing guides and may be wrong on WoW Forever."))
    if UISpecialFrames and tinsert then tinsert(UISpecialFrames, "ForeverLazy_FishRoute") end
    win:Hide()
end

function R.Paint()
    if not win or not win:IsShown() then return end
    local rank, max = Skill()
    local plan = R.Plan(rank, max, Side(), UnitLevel and UnitLevel("player"))
    texts.skill:SetText(plan.skill)
    texts.here:SetText(R.Line(rank, R.Here()))
    for i, b in ipairs(zoneButtons) do
        local z = plan.zones[i]
        b.map = z and z.map
        b:SetText(z and z.text or "")
        b:SetShown(z ~= nil)
    end
    texts.warning:SetText(plan.warning or "")
    texts.next:SetText(plan.next or "")
    texts.training:SetText(plan.training or "")
    action = plan.action
    trainButton:SetShown(action ~= nil)
end

function R.Toggle()
    Build()
    if win:IsShown() then win:Hide(); return end
    win:Show()
    R.Paint()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "SKILL_LINES_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function() pcall(R.Paint) end)

--------------------------------------------------------------------------------
-- Commands: /lazy fish route (or fish guide)
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "fish" or c == "fishing" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "route" or a == "guide" then R.Toggle(); return true end
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["FishRoute.lua"] = true end end
