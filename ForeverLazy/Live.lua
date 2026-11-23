-- The Hive, shared. All of this happens only while the Hive is ON (options > The Hive, or /lazy hive on).
-- It joins a small hidden chat channel and exchanges tiny hidden addon messages (nothing is shown in chat):
--   rare spawns:   "Name of a rare, where it was seen, in which zone". Others see a pin on the map. Never your name.
--   zone counts:   "somebody is in this zone, level band 10-14". Never who, and never where in the zone.
--   what was learned: drop counts (mob id, item ids, kill counts), quest times and zone XP rates, as plain numbers.
--                  Everyone who has the Hive on adds what others send to their own numbers.
-- It never sends your character name, guild, items, gold or anything you typed, and never a track of where you are:
-- the only places it shares are where a rare was seen and coarse map squares where a quest objective was done or someone died.
--   /lazy hive on|off      /lazy hive who      /lazy hive rares      /lazy hive rare (arrow to the nearest)
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local PREFIX = "FLHIVE"
local CHANNEL = "ForeverLazyHive"
local EXPIRE_RARE, EXPIRE_PLAYER = 1800, 240      -- seconds a sighting or a presence stays valid

local rares, players = {}, {}      -- what others told me
local sentRare = {}                -- rares I reported (npc id -> time)
local lastFrom = {}                -- sender -> time of their last message, for rate limiting
local told = {}                    -- rares already announced in chat

local function Enabled() local db = DB(); return db and db.hiveOn == true end

--------------------------------------------------------------------------------
-- The channel
--------------------------------------------------------------------------------
local function ChannelId()
    local id = GetChannelName and GetChannelName(CHANNEL)
    if type(id) == "number" and id > 0 then return id end
    return nil
end

local function Join()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, PREFIX) end
    if not ChannelId() and JoinChannelByName then pcall(JoinChannelByName, CHANNEL) end
    -- keep the channel out of every chat window
    if ChatFrame_RemoveChannel then
        for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
        end
    end
end

local function Leave()
    if LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
    rares, players = {}, {}
end

local function Send(msg)
    local id = ChannelId()
    if not id or #msg > 240 then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "CHANNEL", id)
    elseif SendAddonMessage then pcall(SendAddonMessage, PREFIX, msg, "CHANNEL", id) end
end

-- bigger batches (what was learned) are sent one message at a time, so the game's message limit is never hit
local queue = {}
local function Queue(list)
    for _, m in ipairs(list or {}) do
        if #queue < 120 then queue[#queue + 1] = m end
    end
end

--------------------------------------------------------------------------------
-- Receiving (everything is checked: anyone can write to a public channel)
--------------------------------------------------------------------------------
local function CleanName(s)
    s = tostring(s or ""):gsub("[^%w '%-,%.]", "")
    return s:sub(1, 32)
end

local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

local heardSnapshot, respondPending = false, false

local function Receive(sender, text)
    if type(text) ~= "string" or #text > 240 then return end
    local who = (sender or "?"):match("^([^%-]+)") or sender
    if who == UnitName("player") then return end
    local now = GetTime()
    -- a small bucket per sender: bursts are fine, a steady flood is not (8 at once, then 1.5 a second)
    local bk = lastFrom[who]
    if not bk then bk = { tokens = 8, t = now }; lastFrom[who] = bk end
    bk.tokens = math.min(8, bk.tokens + (now - bk.t) * 1.5)
    bk.t = now
    if bk.tokens < 1 then return end
    bk.tokens = bk.tokens - 1
    local kind, a, b, c, d, e, f = strsplit("|", text)
    if kind == "K" or kind == "Q" or kind == "X" or kind == "G" or kind == "O" or kind == "T" then
        if addon.HiveMerge then addon.HiveMerge(kind, who, a, b, c, d, e, f) end
    elseif kind == "SK" or kind == "SQ" or kind == "SX" then
        heardSnapshot = true
        if addon.HiveMerge then addon.HiveMerge(kind, who, a, b, c, d) end
    elseif kind == "H" then
        -- someone just joined: one of us answers with a snapshot (the first to answer wins, the others stay quiet)
        if not respondPending and C_Timer and C_Timer.After then
            respondPending, heardSnapshot = true, false
            C_Timer.After(3 + math.random() * 11, function()
                respondPending = false
                if not heardSnapshot and Enabled() and addon.HiveSnapshot then Queue(addon.HiveSnapshot()) end
                heardSnapshot = false
            end)
        end
    elseif kind == "P" then
        local map, band = tonumber(a), tonumber(b)
        if map and band and map > 0 and map < 100000 and band >= 0 and band <= 80 and Count(players) < 800 then
            players[who] = { map = map, band = band, t = now }
        end
    elseif kind == "R" then
        local npc, map, zx, zy = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
        if npc and map and zx and zy and npc > 0 and npc < 10000000 and map > 0 and map < 100000
            and zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 and Count(rares) < 80 then
            local name = CleanName(e)
            if name ~= "" then
                if addon.HiveRareSeen then addon.HiveRareSeen(npc) end
                rares[npc] = { map = map, zx = zx, zy = zy, name = name, t = now }
                if addon.HiveLiveChanged then addon.HiveLiveChanged() end
                -- a word in chat if it is in the zone I am in
                local here = hbd:GetPlayerZone()
                if here == map and not told[npc] and DB().hiveRareAlert ~= false then
                    told[npc] = now
                    Print(string.format(L("rare seen nearby: %s (%d, %d). /lazy hive rare points an arrow at it"), name, zx * 100, zy * 100))
                end
            end
        end
    elseif kind == "D" then
        local npc = tonumber(a)
        if npc then
            if addon.HiveRareDeath then addon.HiveRareDeath(npc) end
            if rares[npc] then
                rares[npc].dead = true; rares[npc].deadAt = now; rares[npc].alerted = nil
                told[npc] = nil
                if addon.HiveLiveChanged then addon.HiveLiveChanged() end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------
local function NpcId(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function CheckUnit(unit)
    if not Enabled() or not unit or not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return end
    local cls = UnitClassification and UnitClassification(unit)
    if cls ~= "rare" and cls ~= "rareelite" then return end
    local npc = NpcId(UnitGUID(unit))
    if not npc then return end
    if addon.HiveRareSeen then addon.HiveRareSeen(npc) end
    local now = GetTime()
    if sentRare[npc] and now - sentRare[npc] < 300 then return end
    local zx, zy, map = hbd:GetPlayerZonePosition()
    if not zx or not map then return end
    sentRare[npc] = now
    local name = CleanName(UnitName(unit))
    if name == "" then return end
    rares[npc] = { map = map, zx = zx, zy = zy, name = name, t = now }
    Send(string.format("R|%d|%d|%.3f|%.3f|%s", npc, map, zx, zy, name))
    if addon.HiveLiveChanged then addon.HiveLiveChanged() end
end

-- a rare I reported was looted: it is dead now
local function OnLoot()
    if not Enabled() or not GetNumLootItems or not GetLootSourceInfo then return end
    for slot = 1, (GetNumLootItems() or 0) do
        local srcs = { GetLootSourceInfo(slot) }
        for i = 1, #srcs, 2 do
            local npc = NpcId(srcs[i])
            if npc and (sentRare[npc] or rares[npc]) then
                Send("D|" .. npc)
                if addon.HiveRareDeath then addon.HiveRareDeath(npc) end
                if rares[npc] then rares[npc].dead = true; rares[npc].deadAt = GetTime(); rares[npc].alerted = nil end
                sentRare[npc] = nil; told[npc] = nil
                if addon.HiveLiveChanged then addon.HiveLiveChanged() end
            end
        end
    end
end

local function SendPresence()
    local db = DB()
    if not Enabled() or db.hiveShareZone == false then return end
    local map = hbd:GetPlayerZone()
    local level = UnitLevel("player") or 1
    if map then Send(string.format("P|%d|%d", map, math.floor(level / 5) * 5)) end
end

--------------------------------------------------------------------------------
-- What the map and the commands show
--------------------------------------------------------------------------------
local function Prune()
    local now = GetTime()
    for k, r in pairs(rares) do
        if r.dead then
            local est = addon.HiveRareEstimate and addon.HiveRareEstimate(k)
            local keep = est and math.min(est * 1.3, 10800) or 1200
            if now - (r.deadAt or r.t) > keep then rares[k] = nil end
        elseif now - r.t > EXPIRE_RARE then
            rares[k] = nil
        end
    end
    for k, p in pairs(players) do if now - p.t > EXPIRE_PLAYER then players[k] = nil end end
end

-- how many other players are in a zone, by level band: { total = n, bands = { [10] = n, ... } }
function addon.LiveCounts(map)
    Prune()
    local total, bands = 0, {}
    for _, p in pairs(players) do
        if p.map == map then total = total + 1; bands[p.band] = (bands[p.band] or 0) + 1 end
    end
    return { total = total, bands = bands }
end

local hbdp = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local pinRef, pinFrames = {}, {}

local function RefreshPins()
    if not hbdp then return end
    pcall(hbdp.RemoveAllWorldMapIcons, hbdp, pinRef)
    local db = DB()
    if not Enabled() or db.hiveRarePins == false then return end
    Prune()
    local i = 0
    for npc, r in pairs(rares) do
        i = i + 1
        local f = pinFrames[i]
        if not f then
            f = CreateFrame("Frame", nil, UIParent)
            f:SetSize(18, 18)
            f:EnableMouse(true)
            f.tex = f:CreateTexture(nil, "OVERLAY")
            f.tex:SetAllPoints()
            f.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
            f:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.rare and self.rare.name or "Rare", 1, 0.82, 0)
                local r = self.rare
                if r and r.dead then
                    local ago = math.floor((GetTime() - (r.deadAt or r.t)) / 60)
                    GameTooltip:AddLine(string.format("Killed %d minutes ago", ago), 1, 0.5, 0.5, true)
                    local est = addon.HiveRareEstimate and addon.HiveRareEstimate(self.npc)
                    if est then
                        local left = math.floor(est / 60) - ago
                        GameTooltip:AddLine(left > 0 and string.format("Usually back after about %d minutes (back in about %d)", math.floor(est / 60), left) or string.format("Usually back after about %d minutes: it may be up now", math.floor(est / 60)), 1, 1, 1, true)
                    else
                        GameTooltip:AddLine(L("Nobody has timed its respawn yet."), 0.7, 0.7, 0.7, true)
                    end
                elseif r then
                    GameTooltip:AddLine(string.format("Seen %d minutes ago by another Forever Lazy player", math.floor((GetTime() - r.t) / 60)), 1, 1, 1, true)
                    GameTooltip:AddLine(L("It may have moved or died since."), 0.7, 0.7, 0.7, true)
                end
                GameTooltip:Show()
            end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f:Hide()
            pinFrames[i] = f
        end
        f.rare = r
        f.npc = npc
        f.tex:SetDesaturated(r.dead and true or false)
        f.tex:SetAlpha(r.dead and 0.6 or 1)
        local x, y, inst = hbd:GetWorldCoordinatesFromZone(r.zx, r.zy, r.map)
        if x then pcall(hbdp.AddWorldMapIconWorld, hbdp, pinRef, f, inst, x, y, _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2) end
    end
end

function addon.HiveLiveChanged() RefreshPins() end

-- a small label on the world map: other players in the zone being looked at
local label
local function UpdateLabel()
    local wm = _G.WorldMapFrame
    if not (wm and wm:IsShown()) or not Enabled() or DB().hiveShareZone == false then
        if label then label:Hide() end
        return
    end
    local map = wm.GetMapID and wm:GetMapID()
    local c = map and addon.LiveCounts(map)
    if not c or c.total == 0 then if label then label:Hide() end; return end
    if not label then
        label = CreateFrame("Frame", nil, wm)
        label:SetFrameStrata("HIGH")
        label.bg = label:CreateTexture(nil, "BACKGROUND")
        label.bg:SetAllPoints(); label.bg:SetColorTexture(0, 0, 0, 0.6)
        label.text = label:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label.text:SetPoint("CENTER")
    end
    local bands = {}
    for b, n in pairs(c.bands) do bands[#bands + 1] = b end
    table.sort(bands)
    local parts = {}
    for _, b in ipairs(bands) do parts[#parts + 1] = string.format("%d-%d: %d", b, b + 4, c.bands[b]) end
    label.text:SetText(string.format("Other Forever Lazy players here: %d  (%s)", c.total, table.concat(parts, ", ")))
    label:SetSize(label.text:GetStringWidth() + 20, 20)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", wm.ScrollContainer or wm, "TOPLEFT", 10, -8)
    label:Show()
end

--------------------------------------------------------------------------------
-- Switching it on and off
--------------------------------------------------------------------------------
local joinTries = 0
local function Enable()
    Join()
    joinTries = 0
    local function check()
        if not Enabled() then return end
        if ChannelId() then
            SendPresence()
            -- say hello a bit later: players who have the Hive on answer with what they know
            C_Timer.After(20, function() if Enabled() then Send("H|1") end end)
            return
        end
        joinTries = joinTries + 1
        if joinTries <= 6 then
            Join()
            C_Timer.After(15, check)
        else
            Print(L("live sharing: I could not join the shared channel. Try /lazy hive live off, then on again later."))
        end
    end
    C_Timer.After(5, check)
end

function addon.HiveLiveSet(on)
    local db = DB()
    db.hiveOn = on and true or false
    if on then
        if C_Timer then Enable() end
        Print(L("the Hive is ON: it learns from your play and shares numbers, rares and zone counts with other players who have it on (never your name, and never a track of where you are). /lazy hive off stops it."))
    else
        Leave()
        queue = {}
        RefreshPins()
        if label then label:Hide() end
        Print(L("the Hive is off: nothing is learned or shared"))
    end
    if addon.RefreshOptions then addon.RefreshOptions() end
end
addon.HiveSet = addon.HiveLiveSet

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
                     "NAME_PLATE_UNIT_ADDED", "LOOT_OPENED", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a, b, c, d)
    if event == "PLAYER_LOGIN" then
        -- the old separate switches became one: the Hive on means learning and sharing
        local db = DB()
        if db and db.hiveOn == nil and (db.hiveLive == true) then db.hiveOn = true end
        if Enabled() and C_Timer then C_Timer.After(8, Enable) end
    elseif not Enabled() then
        return
    elseif event == "CHAT_MSG_ADDON" then
        if a == PREFIX and c == "CHANNEL" then pcall(Receive, d, b) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        CheckUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        CheckUnit(a)
    elseif event == "LOOT_OPENED" then
        pcall(OnLoot)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if C_Timer then C_Timer.After(3, SendPresence) end
    end
end)

local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = acc  - 1
    if not Enabled() then return end
    local now = GetTime()
    ev.nextPresence = ev.nextPresence or (now + 30)
    if now >= ev.nextPresence then
        ev.nextPresence = now + 90
        pcall(SendPresence)
    end
    -- what I learned in the last few minutes goes out in small messages
    ev.nextShare = ev.nextShare or (now + 150)
    if now >= ev.nextShare then
        ev.nextShare = now + 150
        if ChannelId() and addon.HiveOutbox then Queue(addon.HiveOutbox()) end
    end
    pcall(UpdateLabel)
    -- a rare that should be back about now, in the zone I am in
    ev.nextTimer = ev.nextTimer or (now + 30)
    if now >= ev.nextTimer then
        ev.nextTimer = now + 30
        local here = hbd:GetPlayerZone()
        for npc, r in pairs(rares) do
            if r.dead and not r.alerted and r.map == here and addon.HiveRareEstimate and DB().hiveRareAlert ~= false then
                local est = addon.HiveRareEstimate(npc)
                if est and now - (r.deadAt or r.t) >= est then
                    r.alerted = true
                    Print(string.format(L("%s should be back about now (it usually takes about %d minutes). /lazy hive rare points an arrow at the spot"), r.name, math.floor(est / 60)))
                end
            end
        end
    end
end)

-- one queued message every third of a second
local qacc = 0
local qframe = CreateFrame("Frame")
qframe:SetScript("OnUpdate", function(_, dt)
    qacc = qacc + dt
    if qacc < 0.35 then return end
    qacc = 0
    if #queue == 0 then return end
    if not Enabled() then queue = {}; return end
    Send(table.remove(queue, 1))
end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
local function NearestRare()
    Prune()
    local here = hbd:GetPlayerZone()
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local best, bestD
    for npc, r in pairs(rares) do
        if r.map == here and px then
            local x, y, inst = hbd:GetWorldCoordinatesFromZone(r.zx, r.zy, r.map)
            if x and inst == pinst then
                local d = (x - px) ^ 2 + (y - py) ^ 2
                if not bestD or d < bestD then best, bestD = r, d end
            end
        end
    end
    return best
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "hive" then
        local arg = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if arg == "on" or arg == "live on" or arg == "live" then addon.HiveLiveSet(true); return true end
        if arg == "off" or arg == "live off" then addon.HiveLiveSet(false); return true end
        if arg == "who" then
            if not Enabled() then Print(L("live sharing is off. /lazy hive live on turns it on")); return true end
            Prune()
            local perMap = {}
            for _, p in pairs(players) do perMap[p.map] = (perMap[p.map] or 0) + 1 end
            local rows = {}
            for map, n in pairs(perMap) do
                local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
                rows[#rows + 1] = { (info and info.name) or ("zone " .. map), n }
            end
            table.sort(rows, function(x, y) return x[2] > y[2] end)
            if #rows == 0 then Print(L("no other Forever Lazy players have shown up yet (they appear once they share their zone)")) end
            for i = 1, math.min(8, #rows) do Print(string.format(L("  %s: %d player%s"), rows[i][1], rows[i][2], rows[i][2] == 1 and "" or "s")) end
            return true
        end
        if arg == "rares" then
            if not Enabled() then Print(L("live sharing is off. /lazy hive live on turns it on")); return true end
            Prune()
            local n = 0
            for npc, r in pairs(rares) do
                n = n + 1
                local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r.map)
                local when = string.format("seen %d min ago", math.floor((GetTime() - r.t) / 60))
                if r.dead then
                    local ago = math.floor((GetTime() - (r.deadAt or r.t)) / 60)
                    local est = addon.HiveRareEstimate and addon.HiveRareEstimate(npc)
                    when = est and string.format("killed %d min ago, usually back after about %d", ago, math.floor(est / 60)) or string.format("killed %d min ago", ago)
                end
                Print(string.format("  %s - %s (%d, %d), %s", r.name, (info and info.name) or "?", r.zx * 100, r.zy * 100, when))
            end
            if n == 0 then Print(L("no rares reported lately")) end
            return true
        end
        if arg == "rare" then
            local r = NearestRare()
            if not r then Print(L("no rare reported in this zone lately")); return true end
            addon:AddWaypointZone(r.map, r.zx, r.zy, "Rare: " .. r.name)
            Print(L("arrow set on ") .. r.name .. L(" (where it was last seen)"))
            return true
        end
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Live.lua"] = true end end
