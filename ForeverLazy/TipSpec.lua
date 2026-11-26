-- A player's spec on the tooltip when I point at them: "Spec: Holy (31/20/0)". Off until ticked (options, Extras).
--   /lazy spec              on or off now        /lazy spec on | off
--   /lazy spec check        with a player targeted: says what the game answers at each step (for when no spec shows)
-- This game keeps talents in one tree per class, with the three talent trees as groups in it (C_Traits), not in the old talent
-- functions. Another player's talents have to be asked for (NotifyInspect); the answer comes a moment later (INSPECT_READY)
-- and is read from the game's "inspect" talent set. Nothing is asked during a fight, or while the game's inspect window is open.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local KEEP = 600        -- seconds a spec is remembered
local RETRY = 30        -- after no answer, leave that player alone this long
local GAP = 1.5         -- at least this long between two questions
local WAIT = 4          -- how long an answer may take
local READS = { 0, 0.3, 1 }   -- the talents may arrive a moment after the answer: read again before believing "none"

local function DB() return addon.GetDB() end
local function On() local d = DB(); return d and d.tipSpec == true end
local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) or false end
local function Plain(v, kind) if v == nil or Secret(v) or type(v) ~= kind then return nil end return v end

--------------------------------------------------------------------------------
-- The rules (no game needed: tests/tipspec.lua)
--------------------------------------------------------------------------------
local T = {}
addon.TipSpec = T

-- trees: { { name =, points = }, ... } in the game's order. The name is the tree with the most points
function T.Format(trees)
    if type(trees) ~= "table" or #trees == 0 then return nil end
    local best, parts = nil, {}
    for _, t in ipairs(trees) do
        parts[#parts + 1] = tostring(t.points)
        if t.points > 0 and (not best or t.points > best.points) then best = t end
    end
    if not best then return nil end
    return string.format("%s (%s)", best.name, table.concat(parts, "/"))
end

-- the points in each group of the tree. groups: { { id =, name =, order = } }, nodes: { { groupIDs =, ranksPurchased =, activeRank = } }.
-- Inspect answers sometimes leave "purchased" empty and only fill "active", so that is the second try
function T.Count(groups, nodes)
    local sorted = {}
    for i, g in ipairs(groups) do sorted[i] = g end
    table.sort(sorted, function(a, b) return a.order < b.order end)
    local function By(field)
        local trees, index, total = {}, {}, 0
        for i, g in ipairs(sorted) do trees[i] = { name = g.name, points = 0 }; index[g.id] = trees[i] end
        for _, n in ipairs(nodes) do
            local ranks = Plain(n[field], "number") or 0
            if ranks > 0 then
                for _, id in ipairs(n.groupIDs or {}) do
                    if index[id] then index[id].points = index[id].points + ranks; total = total + ranks; break end
                end
            end
        end
        return trees, total
    end
    local trees, total = By("ranksPurchased")
    if total == 0 then trees, total = By("activeRank") end
    return trees, total
end

--------------------------------------------------------------------------------
-- Reading the game's talent set
--------------------------------------------------------------------------------
-- trees, total; or nil and the step that failed (shown by /lazy spec check)
function T.Read(configID)
    local C = C_Traits
    if not (C and C.GetConfigInfo and C.GetTreeNodes and C.GetNodeInfo and C.GetGroupDisplayInfoByTreeID) then return nil, "no talent functions" end
    if not configID then return nil, "no talent set id" end
    local ok, config = pcall(C.GetConfigInfo, configID)
    local treeID = ok and type(config) == "table" and type(config.treeIDs) == "table" and Plain(config.treeIDs[1], "number")
    if not treeID then return nil, "no talent set" end
    local okG, displays = pcall(C.GetGroupDisplayInfoByTreeID, treeID)
    if not okG or type(displays) ~= "table" then return nil, "no tree names" end
    local groups = {}
    for _, d in ipairs(displays) do
        if type(d) == "table" and Plain(d.groupID, "number") then
            groups[#groups + 1] = { id = d.groupID, order = Plain(d.orderIndex, "number") or (#groups + 1),
                name = Plain(d.displayName, "string") or ("Tree " .. (#groups + 1)) }
        end
    end
    if #groups == 0 then return nil, "no tree names" end
    local okN, ids = pcall(C.GetTreeNodes, treeID)
    if not okN or type(ids) ~= "table" then return nil, "no talent list" end
    local nodes = {}
    for _, id in ipairs(ids) do
        local okI, info = pcall(C.GetNodeInfo, configID, id)
        if okI and type(info) == "table" then nodes[#nodes + 1] = info end
    end
    if #nodes == 0 then return nil, "no talent list" end
    return T.Count(groups, nodes)
end

local function InspectConfig()
    return (Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID) or -1
end

--------------------------------------------------------------------------------
-- Asking, remembering and putting it on the tooltip
--------------------------------------------------------------------------------
local cache = {}            -- guid -> { text =, till = }
local pending               -- { guid =, at = }: the one question I am waiting on
local lastAsked             -- who anyone (me or another addon) asked about last: the inspect talents are theirs
local lastSent = -100
local check                 -- the guid /lazy spec check is following

local function GuidOf(unit)
    if not unit then return nil end
    return Plain(UnitGUID(unit), "string")
end

-- the unit under the tooltip, when it is a player
local function TipUnit()
    local unit
    if GameTooltip.GetUnit then
        local ok, _, u = pcall(GameTooltip.GetUnit, GameTooltip)
        if ok then unit = Plain(u, "string") end
    end
    unit = unit or "mouseover"
    if not UnitExists(unit) then return nil end
    local player = UnitIsPlayer(unit)
    if Secret(player) or not player then return nil end
    return unit
end

-- my line on the tooltip: added once for a hover, rewritten when the answer comes
local line                  -- { guid =, number = }
local function SetLine(guid, text)
    local full = L("Spec: ") .. text
    if line and line.guid == guid then
        local fs = _G["GameTooltipTextLeft" .. line.number]
        if fs then fs:SetText(full); GameTooltip:Show(); return end
    end
    GameTooltip:AddLine(full, 0.45, 0.8, 1)
    line = { guid = guid, number = GameTooltip:NumLines() }
    GameTooltip:Show()
end

local function Remember(guid, text, seconds) cache[guid] = { text = text, till = GetTime() + seconds } end

-- the answer is known: remember it, and show it if I am still pointing at them
local function Answer(guid, text, seconds)
    Remember(guid, text, seconds)
    local unit = On() and GameTooltip:IsShown() and TipUnit()
    if unit and GuidOf(unit) == guid then SetLine(guid, text) end
end

local function CanAsk(unit)
    if InCombatLockdown() then return false, "in a fight" end
    if not (NotifyInspect and CanInspect) then return false, "no inspect functions" end
    if _G.InspectFrame and _G.InspectFrame:IsShown() then return false, "the game's inspect window is open" end
    local ok, can = pcall(CanInspect, unit)
    if not ok or Secret(can) or not can then return false, "the game will not inspect them (too far, or the other side)" end
    return true
end

local function Ask(unit, guid)
    local now = GetTime()
    if pending and now - pending.at < WAIT and pending.guid == guid then return end
    local wait = GAP - (now - lastSent)
    if wait > 0 then
        -- pointed at someone new too soon: ask in a moment, if I am still on them
        if C_Timer then C_Timer.After(wait + 0.05, function()
            local u = On() and GameTooltip:IsShown() and TipUnit()
            if u and GuidOf(u) == guid and not cache[guid] and CanAsk(u) then Ask(u, guid) end
        end) end
        return
    end
    lastSent = now
    local mine = { guid = guid, at = now }
    pending = mine
    lastAsked = guid
    if not pcall(NotifyInspect, unit) then pending = nil; return end
    if C_Timer then C_Timer.After(WAIT, function()
        if pending ~= mine then return end
        pending = nil
        if check == guid then check = nil; Print(L("spec check: no answer from the game")) end
        Answer(guid, L("not available"), RETRY)
    end) end
end

local function OnTooltip()
    if not On() then return end
    local unit = TipUnit()
    if not unit then return end
    local guid = GuidOf(unit)
    if not guid then return end
    line = nil                              -- the tooltip was just built again: my old line is gone
    local level = Plain(UnitLevel(unit), "number")
    if level and level > 0 and level < 10 then return end
    local me = UnitIsUnit(unit, "player")
    if not Secret(me) and me then
        local config = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
        local trees = config and T.Read(config)
        local text = trees and T.Format(trees)
        if text then SetLine(guid, text) end
        return
    end
    local known = cache[guid]
    if known and GetTime() < known.till then SetLine(guid, known.text); return end
    cache[guid] = nil
    if CanAsk(unit) then
        SetLine(guid, L("reading..."))
        Ask(unit, guid)
    end
end

local function ReadAnswer(guid, step)
    if lastAsked ~= guid then return end          -- someone else has been asked about since: the talents are no longer theirs
    local trees, total = T.Read(InspectConfig())
    local text = trees and T.Format(trees)
    if not text and step < #READS and C_Timer then
        C_Timer.After(READS[step + 1] - READS[step], function() pcall(ReadAnswer, guid, step + 1) end)
        return
    end
    if check == guid then
        check = nil
        if not trees then Print(L("spec check: the answer came, but: ") .. tostring(total))
        else
            local parts = {}
            for _, t in ipairs(trees) do parts[#parts + 1] = t.name .. " " .. t.points end
            Print(L("spec check: ") .. table.concat(parts, ", "))
        end
    end
    if text then Answer(guid, text, KEEP)
    elseif trees and total == 0 then Answer(guid, L("no talents spent"), RETRY)
    else Answer(guid, L("not available"), RETRY) end
    -- let the game drop the inspect data, unless its own window is using it
    if ClearInspectPlayer and not (_G.InspectFrame and _G.InspectFrame:IsShown()) then pcall(ClearInspectPlayer) end
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "INSPECT_READY")
ev:SetScript("OnEvent", function(_, _, guid)
    guid = Plain(guid, "string")
    if not guid or not pending or pending.guid ~= guid then return end
    pending = nil
    pcall(ReadAnswer, guid, 1)
end)

if hooksecurefunc and NotifyInspect then
    pcall(hooksecurefunc, "NotifyInspect", function(unit)
        local ok, guid = pcall(GuidOf, unit)
        lastAsked = ok and guid or nil
    end)
end

local function Hook()
    local modern = GameTooltip and type(GameTooltip.GetPrimaryTooltipData) == "function" and TooltipDataProcessor
        and type(TooltipDataProcessor.AddTooltipPostCall) == "function" and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    if modern then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt)
            if tt == GameTooltip then pcall(OnTooltip) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function() pcall(OnTooltip) end)
    end
end
Hook()

--------------------------------------------------------------------------------
-- /lazy spec
--------------------------------------------------------------------------------
local function Check()
    if not UnitExists("target") or not UnitIsPlayer("target") then Print(L("spec check: target a player first")); return end
    if UnitIsUnit("target", "player") then
        local config = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
        local trees, why = T.Read(config)
        Print(L("spec check (me): ") .. (trees and (T.Format(trees) or L("no talents spent")) or tostring(why)))
        return
    end
    local ok, why = CanAsk("target")
    if not ok then Print(L("spec check: ") .. why); return end
    local guid = GuidOf("target")
    if not guid then Print(L("spec check: the game hides who this is")); return end
    cache[guid], pending, lastSent = nil, nil, -100
    check = guid
    Print(L("spec check: asked, waiting for the answer..."))
    Ask("target", guid)
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "spec" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "check" then Check(); return true end
        local d = DB()
        if a == "on" then d.tipSpec = true
        elseif a == "off" then d.tipSpec = nil
        elseif a == "" then d.tipSpec = (d.tipSpec ~= true) or nil end
        Print(L("spec on player tooltips: ") .. (d.tipSpec == true and "on" or "off") .. L("  (/lazy spec on|off|check)"))
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["TipSpec.lua"] = true end end
