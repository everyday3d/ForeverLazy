-- Cozy Sleeping Bag quest chain (WoW Forever): guides you through it and makes the next spot stop 1
-- of your plan whenever you are in the zone that spot is in.
--   /lazy bag            the next step, how to get there, and a waypoint on it
--   /lazy bag start      I am starting the chain (before I have the first quest)
--   /lazy bag all        every step
--   /lazy bag done|off|on|reset
-- Spots and directions are from the Forever guides (method.gg, kami-labs.fr); the guides disagree a little on
-- the Stonetalon camp, so that one has its trail start listed too.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local MAPS = { Westfall = 1436, Barrens = 1413, Stonetalon = 1442, Loch = 1432, Hillsbrad = 1424 }
local MAPNAME = { [1436] = "Westfall", [1413] = "The Barrens", [1442] = "Stonetalon Mountains",
                  [1432] = "Loch Modan", [1424] = "Hillsbrad Foothills" }

-- the quest I hold at each stage (matched on part of its title), in order
local HELD = { "note you found", "stepping stones", "scramble", "wet job", "eagle", "must be the place" }

local function Spot(map, x, y, title, way) return { map = map, x = x, y = y, title = title, way = way } end

local ALLIANCE = {
    Spot(MAPS.Westfall, 37.1, 50.1, "Alexston Farmstead, Westfall: click the Burned-Out Remains",
        "In the broken cart at Alexston Farmstead (south Westfall). Click the Burned-Out Remains to start the chain."),
    Spot(MAPS.Barrens, 46.1, 74.3, "Burned tower south of Camp Taurajo, The Barrens",
        "Run to Duskwood (pick up a Torch there), through Stranglethorn Vale to Booty Bay, take the boat to Ratchet, "
        .. "then go south of Camp Taurajo to the Burned Tower. Click the Burned-Out Corpse to hand in the note."),
    Spot(MAPS.Stonetalon, 40.6, 52.4, "Abandoned camp, Stonetalon Mountains",
        "Head northwest from the tower and keep clear of the Crossroads. The trail starts about 50.9, 52.3 and ends at "
        .. "the abandoned camp (about 40.6, 52.4). Click the Pocket Litter on the crate to hand in Stepping Stones."),
    Spot(MAPS.Stonetalon, 39.6, 49.9, "Mound of Dirt, Stonetalon Mountains",
        "From the camp go north up the hill and jump onto the Mound of Dirt. If you fall into the ravine you are sent back down."),
    Spot(MAPS.Loch, 49.4, 12.9, "Dam, Loch Modan",
        "Hearthstone to Stormwind or Ironforge (the tram links them), then run to Loch Modan. Follow the northern dam to about "
        .. "the middle and drop down to the ledge below. Use the carved heads facing the Wetlands as steps up to the eagle figurine and click it."),
    Spot(MAPS.Hillsbrad, 87.4, 49.6, "Thoradin's Wall, Hillsbrad Foothills",
        "Go through the Wetlands and Arathi Highlands. Turn right at the entrance and follow the wall to the damaged section, "
        .. "then do the cart and wall jumping puzzles. Click the bag on top of the wall to hand in Eagle's Fist, then take the "
        .. "Cozy Sleeping Bag from the satchel or scroll just below it."),
}

local HORDE = {
    Spot(MAPS.Barrens, 46.1, 74.3, "Burned tower south of Camp Taurajo, The Barrens: click the Burned-Out Remains",
        "In the burnt scouting tower south of Camp Taurajo. Click the Burned-Out Remains to start the chain."),
    Spot(MAPS.Westfall, 37.1, 50.1, "Alexston Farmstead, Westfall",
        "Take the zeppelin from Orgrimmar to Grom'gol, jump into the ocean and swim to Westfall's south coast. "
        .. "Click the Burned-Out Remains in the cart wreckage to hand in the note."),
    Spot(MAPS.Stonetalon, 40.6, 52.4, "Abandoned camp, Stonetalon Mountains",
        "Swim back to Grom'gol, zeppelin to Orgrimmar, fly to the Crossroads and run west past Sun Rock Retreat. The trail "
        .. "starts about 50.9, 52.3 and ends at the abandoned camp (about 40.6, 52.4). Click the Pocket Litter on the crate."),
    ALLIANCE[4],
    Spot(MAPS.Loch, 49.4, 12.9, "Dam, Loch Modan",
        "Hearthstone to Undercity or Orgrimmar, zeppelin to Undercity, then run to Loch Modan (about 40 minutes without a mount). "
        .. "The dam guards will likely kill you. Go to the middle of the dam, drop to the ledge below and click the eagle figurine."),
    ALLIANCE[6],
}

-- what to do at each spot (shown under the arrow), and for Alliance the towns to use on the way
ALLIANCE[1].todo = "Outdoors: click the Burned-Out Remains in the broken cart."
ALLIANCE[2].todo = "Burned tower: click the Burned-Out Corpse at its foot. If you cannot see it, look inside the tower."
ALLIANCE[3].todo = "Outdoors: click the Pocket Litter on the crate in the camp."
ALLIANCE[4].todo = "Climb the hill north of the camp and jump onto the Mound of Dirt. Falling into the ravine sends you back."
ALLIANCE[5].todo = "On the dam: drop to the ledge below, use the carved heads facing the Wetlands as steps up to the eagle figurine, click it."
ALLIANCE[6].todo = "Climb Thoradin's Wall, do the cart and wall jumps, click the bag on the wall, then loot the satchel below it."
ALLIANCE[2].legs = {
    { map = MAPS.Westfall, x = 56.4, y = 47.5, title = "Sentinel Hill, Westfall",
      detail = "Travel to Booty Bay: take the gryphon from the Sentinel Hill flight master (about 3 minutes), or run via Duskwood." },
    { map = 1434, npc = 2496, title = "Booty Bay, Stranglethorn Vale",
      detail = "Travel to Ratchet: go to the docks and board The Maiden's Fancy (the dock guards tell you which boat goes where)." },
}
HORDE[1].todo = "Inside the burnt scouting tower: click the Burned-Out Remains."
HORDE[2].todo = "Outdoors: click the Burned-Out Remains in the cart wreckage."
HORDE[3].todo = ALLIANCE[3].todo
HORDE[5].todo = ALLIANCE[5].todo
HORDE[6].todo = ALLIANCE[6].todo

local function Steps()
    return (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and HORDE or ALLIANCE
end

--------------------------------------------------------------------------------
-- Where am I in the chain (kept per character)
--------------------------------------------------------------------------------
local function State()
    local root = addon.GetRoot()
    root.bag = root.bag or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    root.bag[key] = root.bag[key] or {}
    return root.bag[key]
end

-- returns the number of the spot I should go to (1-6), or nil when the chain is not under way
local function Current()
    if not addon.ModuleOn("bag") then return nil end
    local st = State()
    if st.done then return nil end
    if GetItemCount and GetItemCount("Cozy Sleeping Bag") > 0 then st.done = true; return nil end
    local held
    if api.ReadQuestLog then
        for _, q in ipairs(api.ReadQuestLog()) do
            local t = (q.title or ""):lower()
            for i, part in ipairs(HELD) do
                if t:find(part, 1, true) and (not held or i > held) then held = i end
            end
        end
    end
    if held then st.started = true; return math.min(held + 1, 6) end
    if st.started then return 1 end
    return nil
end

--------------------------------------------------------------------------------
-- The stop in the plan
--------------------------------------------------------------------------------
local function Renumber(wps)
    for i, w in ipairs(wps) do
        if w.label then w.name = i .. ". " .. w.label end
    end
end

local function Place(force)
    local db = DB()
    if not db then return end
    local wps = db.waypoints
    local removed
    for i = #wps, 1, -1 do
        if wps[i].bag then table.remove(wps, i); removed = true end
    end
    local idx = (db.bagGuide ~= false or force) and Current()
    local step = idx and Steps()[idx]
    if not step then
        if removed then Renumber(wps); addon:RefreshPins() end
        return
    end
    -- in the zone of the spot: the spot itself. In a zone on the way: the boat or flight point to use there.
    local zone = hbd:GetPlayerZone()
    local stop
    if zone == step.map then
        stop = { map = step.map, x = step.x, y = step.y, title = step.title, detail = step.todo }
    elseif step.legs then
        for _, leg in ipairs(step.legs) do
            if leg.map == zone then stop = leg end
        end
    end
    if not stop and force then
        stop = { map = step.map, x = step.x, y = step.y, title = step.title, detail = step.todo }
    end
    if not stop then
        if removed then Renumber(wps); addon:RefreshPins() end
        return
    end
    local wx, wy, inst, zx, zy, uiMapId
    if stop.npc then
        -- position taken from Questie's data for a known NPC (the town's landmark)
        local sp = {}
        api.AddNpcs(sp, { stop.npc })
        local s = sp[1]
        if s then wx, wy, inst, zx, zy, uiMapId = s.x, s.y, s.instance, s.zx, s.zy, s.uiMapId end
    else
        wx, wy, inst = hbd:GetWorldCoordinatesFromZone(stop.x / 100, stop.y / 100, stop.map)
        zx, zy, uiMapId = stop.x / 100, stop.y / 100, stop.map
    end
    if not wx then
        if removed then Renumber(wps); addon:RefreshPins() end
        return
    end
    if not force then
        -- standing on it already: do not put it back after arriving
        local px, py, pinst = hbd:GetPlayerWorldPosition()
        if px and pinst == inst and math.sqrt((px - wx) ^ 2 + (py - wy) ^ 2) < 25 then
            if removed then Renumber(wps); addon:RefreshPins() end
            return
        end
    end
    local label = "Sleeping bag: " .. stop.title
    table.insert(wps, 1, { name = "", label = label, bag = true, instance = inst, x = wx, y = wy,
                           uiMapId = uiMapId, zx = zx, zy = zy, detail = stop.detail })
    Renumber(wps)
    wps[1].name = "1. " .. label
    addon:RefreshPins()
    if addon.RefreshOptions then addon.RefreshOptions() end
end

-- when a plan is built, the bag spot goes in front
local origPlan = addon.PlanRoute
function addon:PlanRoute(...)
    origPlan(self, ...)
    pcall(Place)
end

--------------------------------------------------------------------------------
-- Keep up with the quest log and the zone
--------------------------------------------------------------------------------
local lastIdx, pending
local function Refresh()
    pending = false
    local idx = Current()
    if idx ~= lastIdx then
        lastIdx = idx
        local step = idx and Steps()[idx]
        if step then
            Print(string.format(L("sleeping bag, step %d of 6: %s"), idx, step.title))
            Print(L("  /lazy bag  for the way there"))
        end
    end
    Place()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA",
                     "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function()
    if pending or not (C_Timer and C_Timer.After) then return end
    pending = true
    C_Timer.After(2, function() pcall(Refresh); pending = false end)
end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
local function Describe(i, step)
    return string.format("step %d of 6 - %s (%s %.1f, %.1f)", i, step.title, MAPNAME[step.map] or "?", step.x, step.y)
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd ~= "bag" then
        if prev then return prev(self, cmd, rest) end
        return
    end
    local db, st = DB(), State()
    rest = (rest or ""):lower()
    local steps = Steps()
    if rest == "start" then
        st.started, st.done = true, nil
        lastIdx = nil
        Print(L("sleeping bag chain started, I will guide you"))
        Refresh()
    elseif rest == "done" then
        st.done = true
        Place()
        Print(L("sleeping bag chain marked as done"))
    elseif rest == "reset" then
        st.started, st.done = nil, nil
        lastIdx = nil
        Place()
        Print(L("sleeping bag chain reset"))
    elseif rest == "off" then
        db.bagGuide = false
        Place()
        Print(L("sleeping bag guide off (/lazy bag on turns it back on)"))
    elseif rest == "on" then
        db.bagGuide = true
        Refresh()
        Print(L("sleeping bag guide on"))
    elseif rest == "all" then
        Print(L("Cozy Sleeping Bag chain, ") .. ((UnitFactionGroup and UnitFactionGroup("player")) or "Alliance") .. ":")
        for i, s in ipairs(steps) do Print("  " .. Describe(i, s)) end
    else
        local idx = Current()
        if not idx then
            Print(L("the sleeping bag chain is not under way. /lazy bag start begins it, /lazy bag all lists the steps"))
            return true
        end
        local step = steps[idx]
        Print(Describe(idx, step))
        Print(L("  way: ") .. step.way)
        Place(true)
    end
    return true
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Bag.lua"] = true end end
