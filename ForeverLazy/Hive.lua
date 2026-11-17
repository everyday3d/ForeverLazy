-- The Hive, phase one: the addon learns from what really happens when you play, instead of trusting guesses.
--   Your pace:   how much XP you really earn per hour, per zone and level, from your own play.
--   Drop rates:  every corpse you loot is counted, so "where do I get Light Hide" can name the mob that really drops it.
-- Everything is kept on your computer. Nothing is sent to anyone (sharing may come later, and would be opt-in).
--   /lazy pace              your measured XP per hour and the time to your next level
--   /lazy drops <item>      the mobs you have seen drop an item, with the rate
--   /lazy hive              what has been learned so far (and /lazy hive reset to forget it)
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function Root()
    local r = addon.GetRoot()
    r.hive = r.hive or {}
    r.hive.xp = r.hive.xp or {}
    r.hive.drops = r.hive.drops or {}
    r.hive.grind = r.hive.grind or {}
    r.hive.rt = r.hive.rt or {}
    r.hive.rareDeath = r.hive.rareDeath or {}
    return r.hive
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- numbers other players shared with me (only while the Hive is on); kept apart from my own, an empty table until releases include some
local function Community() return Root().shared end

-- this play session, for /lazy session
local session = { t0 = time(), xp = 0, quests = 0, kills = 0, money0 = nil }
-- what I learned since I last shared it (only filled while the Hive is on)
local outbox = { drops = {}, quests = {}, pace = {}, grind = {}, rt = {} }

--------------------------------------------------------------------------------
-- XP per hour
--------------------------------------------------------------------------------
local lastXP, lastMax, lastLevel, lastT

local function Snap()
    lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
end

local function OnXP()
    local now = GetTime()
    if not lastXP then Snap(); lastT = now; return end
    local xp, lvl = UnitXP("player"), UnitLevel("player")
    local gain = 0
    if lvl == lastLevel then gain = xp - lastXP
    elseif lvl > lastLevel then gain = (lastMax - lastXP) + xp end
    local prevLevel = lastLevel
    Snap()
    local dt = lastT and (now - lastT) or 30
    lastT = now
    if gain <= 0 then return end
    session.xp = session.xp + gain
    -- a gap of more than 3 minutes means I was doing something else: count 30 seconds for this gain
    local secs = (dt <= 180) and dt or 30
    local zone = GetRealZoneText and GetRealZoneText() or "?"
    if zone == "" then zone = "?" end
    local h = Root().xp
    local ck = CharKey()
    h[ck] = h[ck] or {}
    h[ck][zone] = h[ck][zone] or {}
    local e = h[ck][zone][prevLevel] or { xp = 0, secs = 0 }
    h[ck][zone][prevLevel] = e
    e.xp = e.xp + gain
    e.secs = e.secs + secs
    if addon.HiveAddOutbox then addon.HiveAddOutbox("pace", zone, prevLevel, gain, secs) end
end

-- XP per hour near my level, in one zone or in all of them; nil until there are 5 active minutes of data
function addon.HivePace(zone)
    local data = Root().xp[CharKey()]
    if not data then return nil end
    local lvl = UnitLevel("player") or 1
    local xp, secs = 0, 0
    local function add(zd)
        for l, e in pairs(zd) do
            if math.abs(l - lvl) <= 3 then xp = xp + e.xp; secs = secs + e.secs end
        end
    end
    if zone and data[zone] then add(data[zone]) else for _, zd in pairs(data) do add(zd) end end
    if secs < 300 then return nil end
    return xp / secs * 3600, secs
end

-- minutes to my next level at my pace (this zone if I have data for it, else everywhere), and the pace
function addon.HiveTimeToLevel()
    local pace = addon.HivePace(GetRealZoneText and GetRealZoneText()) or addon.HivePace()
    if not pace or pace <= 0 then return nil end
    local left = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    if left <= 0 then return nil end
    return left / pace * 60, pace
end

--------------------------------------------------------------------------------
-- Drop rates
--------------------------------------------------------------------------------
local seenKill, seenItem, seenCount = {}, {}, 0

local function NpcId(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function OnLoot()
    if not GetNumLootItems or not GetLootSourceInfo then return end
    local drops = Root().drops
    if seenCount > 3000 then seenKill, seenItem, seenCount = {}, {}, 0 end
    for slot = 1, (GetNumLootItems() or 0) do
        local srcs = { GetLootSourceInfo(slot) }
        local itemId, qty
        if GetLootSlotType and GetLootSlotType(slot) == (_G.LOOT_SLOT_ITEM or 1) then
            local link = GetLootSlotLink and GetLootSlotLink(slot)
            itemId = link and tonumber(link:match("item:(%d+)"))
            qty = select(3, GetLootSlotInfo(slot))
        end
        for i = 1, #srcs, 2 do
            local guid = srcs[i]
            local npc = NpcId(guid)
            if npc then
                local e = drops[npc] or { kills = 0, items = {} }
                drops[npc] = e
                if not seenKill[guid] then
                    seenKill[guid] = true; seenCount = seenCount + 1
                    e.kills = e.kills + 1
                    session.kills = session.kills + 1
                    if addon.HiveAddOutbox then addon.HiveAddOutbox("drop", npc, 1) end
                end
                if itemId then
                    local k = guid .. ":" .. itemId
                    if not seenItem[k] then
                        seenItem[k] = true; seenCount = seenCount + 1
                        local n = tonumber(srcs[i + 1]) or tonumber(qty) or 1
                        e.items[itemId] = (e.items[itemId] or 0) + n
                        if addon.HiveAddOutbox then addon.HiveAddOutbox("drop", npc, 0, itemId, n) end
                    end
                end
            end
        end
    end
end

local function NpcName(npc)
    local ok, QDB = pcall(function() return api.GetQuestie and api.GetQuestie() end)
    if ok and QDB and QDB.QueryNPCSingle then
        local n = QDB.QueryNPCSingle(npc, "name")
        if n then return n end
    end
    return "creature " .. npc
end

-- the mobs I have seen drop this item: { { npc, name, rate, n, kills }, ... } best first
function addon.HiveDrops(itemId)
    local out = {}
    local mine, comm = Root().drops, Community()
    local done = {}
    -- my own counts and the shared ones add up
    local function consider(npc)
        if done[npc] then return end
        done[npc] = true
        local e = mine[npc]
        local c = comm and comm.drops and comm.drops[npc]
        local kills = (e and e.kills or 0) + (c and c.k or 0)
        local n = (e and e.items and e.items[itemId] or 0) + (c and c.i and c.i[itemId] or 0)
        if n > 0 and kills >= 3 then
            out[#out + 1] = { npc = npc, name = NpcName(npc), rate = n / kills, n = n, kills = kills,
                              community = (c and c.i and c.i[itemId]) and true or false }
        end
    end
    for npc in pairs(mine) do consider(npc) end
    if comm and comm.drops then for npc in pairs(comm.drops) do consider(npc) end end
    table.sort(out, function(a, b)
        -- a rate backed by more kills is trusted more
        local sa, sb = a.rate * math.min(1, a.kills / 10), b.rate * math.min(1, b.kills / 10)
        return sa > sb
    end)
    return out
end

-- the best mob to farm an item from, or nil
function addon.HiveBest(itemId)
    local list = addon.HiveDrops(itemId)
    local b = list[1]
    if b and b.kills >= 5 and b.rate >= 0.08 then return b end
    return nil
end

--------------------------------------------------------------------------------
-- Tooltip: where I have seen an item drop
--------------------------------------------------------------------------------
local function AddHive(tt, id)
    local db = addon.GetDB()
    if not db or db.hiveTooltip == false or not id or not tt or not tt.AddDoubleLine then return end
    if tt.flHive == id then return end
    local list = addon.HiveDrops(id)
    if #list == 0 then return end
    tt.flHive = id
    tt:AddLine(" ")
    local shared = false
    for _, d in ipairs(list) do if d.community then shared = true end end
    tt:AddLine(shared and "Seen dropping from (you and other players)" or "Seen dropping from (your own kills)", 0.6, 0.8, 1)
    for i = 1, math.min(3, #list) do
        local d = list[i]
        tt:AddDoubleLine(d.name, string.format("%d%%  (%d in %d kills)", math.floor(d.rate * 100 + 0.5), d.n, d.kills), 1, 1, 1, 0.8, 0.8, 0.8)
    end
    if tt.Show then tt:Show() end
end

local function Hook()
    local hooked = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
            local id = data and data.id
            if id then AddHive(tt, id) end
        end)
    end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tt = _G[name]
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) self.flHive = nil end)
            if not hooked then
                pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    local id = link and tonumber(link:match("item:(%d+)"))
                    if id then AddHive(self, id) end
                end)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- How long quests really take
--------------------------------------------------------------------------------
local function Quests()
    local h = Root()
    h.quests = h.quests or {}
    h.pending = h.pending or {}
    local ck = CharKey()
    h.quests[ck] = h.quests[ck] or {}
    h.pending[ck] = h.pending[ck] or {}
    return h.quests[ck], h.pending[ck]
end

local function OnAccepted(a, b)
    local id = tonumber(b) or tonumber(a)       -- some clients send (index, id), others just (id)
    if not id then return end
    local _, pending = Quests()
    pending[id] = time()
end

local function OnTurnedIn(id, xp)
    id = tonumber(id)
    if not id then return end
    session.quests = session.quests + 1
    local q, pending = Quests()
    local t0 = pending[id]
    pending[id] = nil
    if not t0 then return end
    local dt = time() - t0
    if dt < 20 or dt > 7200 then return end      -- under 20 seconds or over 2 hours is not a real measurement
    local e = q[id] or { n = 0, secs = 0, xp = 0 }
    q[id] = e
    e.n = e.n + 1
    e.secs = e.secs + dt
    e.xp = e.xp + (tonumber(xp) or 0)
    e.level = UnitLevel("player")
    if addon.HiveAddOutbox then addon.HiveAddOutbox("quest", id, dt, tonumber(xp) or 0) end
end

-- XP per minute a quest has given me from accept to turn-in (nil when I have not done it, or it gave no XP)
function addon.HiveQuestRate(id)
    local q = Quests()
    local e = q[id]
    if not e or e.secs <= 0 or e.xp <= 0 then
        -- not done by me yet: what other players measured, when the release carries it
        local comm = Community()
        local c = comm and comm.quests and comm.quests[id]
        if c and c.secs and c.secs > 0 and c.xp and c.xp > 0 then return c.xp / (c.secs / 60) end
        return nil
    end
    return e.xp / (e.secs / 60)
end

-- XP per hour other players typically get in a zone near my level (nil when the release has no data for it)
function addon.HiveCommunityPace(zone)
    local comm = Community()
    local zd = comm and comm.pace and comm.pace[zone]
    if not zd then return nil end
    local lvl = UnitLevel("player") or 1
    local xp, secs = 0, 0
    for l, e in pairs(zd) do
        if math.abs(l - lvl) <= 3 then xp = xp + e.xp; secs = secs + e.secs end
    end
    if secs < 1800 then return nil end
    return xp / secs * 3600
end

local function AverageQuestRate()
    local q = Quests()
    local xp, secs = 0, 0
    for _, e in pairs(q) do xp = xp + e.xp; secs = secs + e.secs end
    if secs < 600 then return nil end
    return xp / (secs / 60)
end

-- a quest that has been much slower for me than my usual: worth skipping next time
function addon.HiveQuestSlow(id)
    local r, avg = addon.HiveQuestRate(id), AverageQuestRate()
    return (r and avg and r < avg * 0.5) and true or false
end

--------------------------------------------------------------------------------
-- The zone I earn the most in
--------------------------------------------------------------------------------
-- returns: best zone, its pace, the zone I am in, its pace (needs 10 active minutes in a zone to count it)
function addon.HiveBestZone()
    local data = Root().xp[CharKey()]
    if not data then return nil end
    local best, bestPace
    for zone in pairs(data) do
        local pace, secs = addon.HivePace(zone)
        if pace and secs >= 600 and (not bestPace or pace > bestPace) then best, bestPace = zone, pace end
    end
    if not best then return nil end
    local here = GetRealZoneText and GetRealZoneText() or nil
    return best, bestPace, here, here and addon.HivePace(here) or nil
end

--------------------------------------------------------------------------------
-- Sharing, only while the Hive is ON. What other players send is checked and added to a separate cache, which the
-- drop rates, quest times and zone paces above read together with my own numbers. Nothing here ever holds a name.
--------------------------------------------------------------------------------
local SENDER_BUDGET = 400               -- records one sender may add per session (so one player cannot flood the cache)
local budget = {}

local function Sanitize(zone)
    zone = tostring(zone or ""):gsub("[^%w '%-%.:]", "")
    return zone:sub(1, 40)
end

local function SharedCache()
    local h = Root()
    h.shared = h.shared or {}
    h.shared.drops = h.shared.drops or {}
    h.shared.quests = h.shared.quests or {}
    h.shared.pace = h.shared.pace or {}
    return h.shared
end

local function TableSize(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

-- parse "id:n,id:n" into { [id] = n } (nil when anything is out of range)
local function ParseItems(text, kills)
    local items, count = {}, 0
    for id, n in tostring(text or ""):gmatch("(%d+):(%d+)") do
        id, n = tonumber(id), tonumber(n)
        if id < 1 or id > 9999999 or n < 1 or n > 600 or n > math.max(kills, 1) * 30 then return nil end
        items[id] = n
        count = count + 1
        if count > 40 then break end
    end
    return items
end

-- kind: K Q X add up (a few minutes of play from one player); SK SQ SX are snapshots, merged by taking the larger number
function addon.HiveMerge(kind, who, a, b, c, d, e, f)
    local db = addon.GetDB()
    if not db or not db.hiveOn then return end
    budget[who] = (budget[who] or SENDER_BUDGET) - 1
    if budget[who] < 0 then return end
    local S = SharedCache()
    local snapshot = kind:sub(1, 1) == "S"
    local base = snapshot and kind:sub(2) or kind
    if base == "K" then
        local npc, kills = tonumber(a), tonumber(b)
        if not npc or not kills or npc < 1 or npc > 9999999 or kills < 0 or kills > (snapshot and 100000 or 60) then return end
        local items = ParseItems(c, kills)
        if not items then return end
        local e = S.drops[npc]
        if not e then
            if kills < 1 or TableSize(S.drops) > 4000 then return end
            e = { k = 0, i = {} }
            S.drops[npc] = e
        end
        if snapshot then
            e.k = math.max(e.k, kills)
            for id, n in pairs(items) do e.i[id] = math.max(e.i[id] or 0, n) end
        else
            e.k = e.k + kills
            for id, n in pairs(items) do e.i[id] = (e.i[id] or 0) + n end
        end
    elseif base == "Q" then
        local id, n, secs, xp = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
        if not (id and n and secs and xp) or id < 1 or id > 9999999 or n < 1 or n > (snapshot and 100000 or 10) then return end
        if secs < 20 * n or secs > 7200 * n or xp < 0 or xp > 200000 * n then return end
        local e = S.quests[id]
        if not e then
            if TableSize(S.quests) > 6000 then return end
            e = { n = 0, secs = 0, xp = 0 }
            S.quests[id] = e
        end
        if snapshot then e.n, e.secs, e.xp = math.max(e.n, n), math.max(e.secs, secs), math.max(e.xp, xp)
        else e.n, e.secs, e.xp = e.n + n, e.secs + secs, e.xp + xp end
    elseif base == "G" then
        local zone, lvl, name, n, xp, secs = Sanitize(a), tonumber(b), Sanitize(c), tonumber(d), tonumber(e), tonumber(f)
        if zone == "" or name == "" or not (lvl and n and xp and secs) or lvl < 1 or lvl > 80 then return end
        if n < 1 or n > (snapshot and 100000 or 80) or secs < 5 * n or secs > (snapshot and 36000000 or 900) then return end
        if xp < 0 or xp / n > 20000 or xp / secs * 3600 > 400000 then return end
        S.grind = S.grind or {}
        S.grind[zone] = S.grind[zone] or {}
        local m = S.grind[zone][name]
        if not m then
            if TableSize(S.grind) > 600 then return end
            m = {}
            S.grind[zone][name] = m
        end
        local g = m[lvl]
        if not g then g = { n = 0, xp = 0, secs = 0 }; m[lvl] = g end
        if snapshot then g.n, g.xp, g.secs = math.max(g.n, n), math.max(g.xp, xp), math.max(g.secs, secs)
        else g.n, g.xp, g.secs = g.n + n, g.xp + xp, g.secs + secs end
    elseif base == "T" and not snapshot then
        local npc, secs = tonumber(a), tonumber(b)
        if not npc or not secs or npc < 1 or npc > 9999999 or secs < 300 or secs > 259200 then return end
        S.rt = S.rt or {}
        local list = S.rt[npc] or {}
        S.rt[npc] = list
        list[#list + 1] = secs
        while #list > 9 do table.remove(list, 1) end
    elseif base == "X" then
        local zone, lvl, xp, secs = Sanitize(a), tonumber(b), tonumber(c), tonumber(d)
        if zone == "" or not (lvl and xp and secs) or lvl < 1 or lvl > 80 or secs < 30 or xp < 0 then return end
        if secs > (snapshot and 3600000 or 600) or xp / secs * 3600 > 300000 then return end
        S.pace[zone] = S.pace[zone] or {}
        local e = S.pace[zone][lvl]
        if not e then
            if TableSize(S.pace) > 1500 then return end
            e = { xp = 0, secs = 0 }
            S.pace[zone][lvl] = e
        end
        if snapshot then e.xp, e.secs = math.max(e.xp, xp), math.max(e.secs, secs)
        else e.xp, e.secs = e.xp + xp, e.secs + secs end
    end
end

-- what I learned since my last broadcast, as messages to send; empties the outbox
function addon.HiveOutbox()
    local msgs = {}
    for npc, e in pairs(outbox.drops) do
        local items = {}
        for id, n in pairs(e.i) do items[#items + 1] = id .. ":" .. n end
        local kills, chunk = e.k, {}
        local function flush()
            msgs[#msgs + 1] = string.format("K|%d|%d|%s", npc, kills, table.concat(chunk, ","))
            chunk, kills = {}, 0
        end
        for _, it in ipairs(items) do
            chunk[#chunk + 1] = it
            if #table.concat(chunk, ",") > 150 then flush() end
        end
        if #chunk > 0 or kills > 0 then flush() end
    end
    for id, e in pairs(outbox.quests) do msgs[#msgs + 1] = string.format("Q|%d|%d|%d|%d", id, e.n, e.secs, e.xp) end
    for key, e in pairs(outbox.pace) do
        local zone, lvl = key:match("^(.*)\t(%d+)$")
        if zone then msgs[#msgs + 1] = string.format("X|%s|%d|%d|%d", zone, tonumber(lvl), math.floor(e.xp), math.floor(e.secs)) end
    end
    for key, e in pairs(outbox.grind) do
        local zone, name, lvl = key:match("^(.-)\t(.-)\t(%d+)$")
        if zone then msgs[#msgs + 1] = string.format("G|%s|%d|%s|%d|%d|%d", zone, tonumber(lvl), name, e.n, math.floor(e.xp), math.floor(e.secs)) end
    end
    for npc, secs in pairs(outbox.rt) do msgs[#msgs + 1] = string.format("T|%d|%d", npc, secs) end
    outbox = { drops = {}, quests = {}, pace = {}, grind = {}, rt = {} }
    -- never more than 40 messages at once; the rest is simply not shared (it is still in my own numbers)
    while #msgs > 40 do table.remove(msgs) end
    return msgs
end

-- a snapshot of the best of what I know (my numbers and the shared cache together), for a player who just joined
function addon.HiveSnapshot()
    local msgs = {}
    local S, mine = SharedCache(), Root()
    local mobs = {}
    local seen = {}
    for npc, e in pairs(mine.drops) do seen[npc] = true; mobs[#mobs + 1] = npc end
    for npc in pairs(S.drops) do if not seen[npc] then mobs[#mobs + 1] = npc end end
    local function kills(npc) return (mine.drops[npc] and mine.drops[npc].kills or 0) + (S.drops[npc] and S.drops[npc].k or 0) end
    table.sort(mobs, function(x, y) return kills(x) > kills(y) end)
    for i = 1, math.min(30, #mobs) do
        local npc = mobs[i]
        local items = {}
        local mi = mine.drops[npc] and mine.drops[npc].items or {}
        local si = S.drops[npc] and S.drops[npc].i or {}
        local ids = {}
        for id in pairs(mi) do ids[id] = true end
        for id in pairs(si) do ids[id] = true end
        for id in pairs(ids) do items[#items + 1] = { id, (mi[id] or 0) + (si[id] or 0) } end
        table.sort(items, function(x, y) return x[2] > y[2] end)
        local parts = {}
        for j = 1, math.min(10, #items) do parts[#parts + 1] = items[j][1] .. ":" .. items[j][2] end
        if #parts > 0 then msgs[#msgs + 1] = string.format("SK|%d|%d|%s", npc, kills(npc), table.concat(parts, ",")) end
    end
    return msgs
end

local function AddOutbox(kind, a, b, c, d, e)
    if kind == "drop" then
        local e = outbox.drops[a] or { k = 0, i = {} }
        outbox.drops[a] = e
        e.k = e.k + (b or 0)
        if c then e.i[c] = (e.i[c] or 0) + (d or 1) end
    elseif kind == "quest" then
        local e = outbox.quests[a] or { n = 0, secs = 0, xp = 0 }
        outbox.quests[a] = e
        e.n = e.n + 1; e.secs = e.secs + b; e.xp = e.xp + c
    elseif kind == "grind" then
        local key = a .. "\t" .. b .. "\t" .. c
        local g = outbox.grind[key] or { n = 0, xp = 0, secs = 0 }
        outbox.grind[key] = g
        g.n = g.n + 1; g.xp = g.xp + d; g.secs = g.secs + e
    elseif kind == "pace" then
        local key = a .. "\t" .. b
        local e = outbox.pace[key] or { xp = 0, secs = 0 }
        outbox.pace[key] = e
        e.xp = e.xp + c; e.secs = e.secs + d
    end
end
addon.HiveAddOutbox = AddOutbox
--------------------------------------------------------------------------------
-- Best grind: how much XP per hour each kind of mob really gives me (kills only, with the time between kills)
--------------------------------------------------------------------------------
local lastKillT

local function OnKillXP(msg)
    local name, xp = tostring(msg or ""):match("^(.-) dies, you gain (%d+) experience")
    xp = tonumber(xp)
    if not name or not xp or xp <= 0 then return end
    name = Sanitize(name)
    if name == "" then return end
    local now = GetTime()
    local dt = lastKillT and (now - lastKillT) or 20
    lastKillT = now
    local secs = (dt <= 120) and math.max(dt, 5) or 20          -- a long gap means I was doing something else
    local zone = GetRealZoneText and GetRealZoneText() or "?"
    if zone == "" then zone = "?" end
    local lvl = UnitLevel("player") or 1
    local g = Root().grind
    local ck = CharKey()
    g[ck] = g[ck] or {}
    g[ck][zone] = g[ck][zone] or {}
    g[ck][zone][name] = g[ck][zone][name] or {}
    local e = g[ck][zone][name][lvl] or { n = 0, xp = 0, secs = 0 }
    g[ck][zone][name][lvl] = e
    e.n = e.n + 1; e.xp = e.xp + xp; e.secs = e.secs + secs
    if addon.HiveAddOutbox then addon.HiveAddOutbox("grind", zone, name, lvl, xp, secs) end
end

-- the mobs in a zone ranked by XP per hour near my level (mine and other players' numbers together), best first
function addon.HiveBestGrind(zone)
    local lvl = UnitLevel("player") or 1
    local sums = {}
    local function add(byName)
        for name, levels in pairs(byName or {}) do
            for l, e in pairs(levels) do
                if math.abs(l - lvl) <= 2 then
                    local s = sums[name] or { n = 0, xp = 0, secs = 0 }
                    sums[name] = s
                    s.n = s.n + e.n; s.xp = s.xp + e.xp; s.secs = s.secs + e.secs
                end
            end
        end
    end
    local mine = Root().grind[CharKey()]
    add(mine and mine[zone])
    local S = Root().shared
    add(S and S.grind and S.grind[zone])
    local out = {}
    for name, s in pairs(sums) do
        if s.n >= 5 and s.secs >= 60 then out[#out + 1] = { name = name, rate = s.xp / s.secs * 3600, n = s.n, per = s.xp / s.n } end
    end
    table.sort(out, function(x, y) return x.rate > y.rate end)
    return out
end

--------------------------------------------------------------------------------
-- Rare timers: how long a rare takes to come back, learned from deaths and later sightings
--------------------------------------------------------------------------------
local function Median(list)
    local c = {}
    for _, v in ipairs(list) do c[#c + 1] = v end
    table.sort(c)
    return c[math.ceil(#c / 2)]
end

-- seconds a rare usually takes to come back, and how many measurements it rests on (nil when unknown)
function addon.HiveRareEstimate(npc)
    local all = {}
    local own = Root().rt[npc]
    for _, v in ipairs(own or {}) do all[#all + 1] = v end
    local S = Root().shared
    for _, v in ipairs((S and S.rt and S.rt[npc]) or {}) do all[#all + 1] = v end
    if #all == 0 then return nil end
    return Median(all), #all
end

-- a rare died (I looted it, or someone reported it)
function addon.HiveRareDeath(npc)
    local deaths = Root().rareDeath
    deaths[npc] = time()
    local n = 0
    for _ in pairs(deaths) do n = n + 1 end
    if n > 200 then
        local cutoff = time() - 259200
        for k, v in pairs(deaths) do if v < cutoff then deaths[k] = nil end end
    end
end

-- a rare was seen alive: if I know when it died, the gap is one more measurement (an upper bound on the respawn)
function addon.HiveRareSeen(npc)
    local deaths = Root().rareDeath
    local t0 = deaths[npc]
    if not t0 then return end
    deaths[npc] = nil
    local dt = time() - t0
    if dt < 300 or dt > 259200 then return end
    local rt = Root().rt
    local list = rt[npc] or {}
    rt[npc] = list
    list[#list + 1] = dt
    while #list > 9 do table.remove(list, 1) end
    if addon.GetDB().hiveOn then outbox.rt[npc] = dt end
end
--------------------------------------------------------------------------------
-- Events and commands
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_XP_UPDATE", "LOOT_OPENED", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_XP_GAIN" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a, b)
    local db = addon.GetDB()
    if event == "PLAYER_LOGIN" then
        Snap(); lastT = GetTime()
        session.t0 = time(); session.money0 = GetMoney and GetMoney() or nil
        pcall(Hook)
    elseif not (db and db.hiveOn) then
        return
    elseif event == "PLAYER_XP_UPDATE" then
        pcall(OnXP)
    elseif event == "LOOT_OPENED" then
        pcall(OnLoot)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        pcall(OnKillXP, a)
    elseif event == "QUEST_ACCEPTED" then
        pcall(OnAccepted, a, b)
    elseif event == "QUEST_TURNED_IN" then
        pcall(OnTurnedIn, a, b)
    end
end)

local function Clock(minutes)
    if minutes >= 120 then return string.format("%.1f hours", minutes / 60) end
    return string.format("%d minutes", math.floor(minutes + 0.5))
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    local arg = ((rest or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if word == "grind" then
        local zone = (arg ~= "" and arg) or (GetRealZoneText and GetRealZoneText()) or "?"
        local list = addon.HiveBestGrind(zone)
        if #list == 0 then
            Print("no grind data for " .. zone .. " yet: I need at least 5 kills of a kind of mob near your level (turn the Hive on and kill some)")
            return true
        end
        Print("best grind in " .. zone .. " near your level (XP per hour, with the time between kills):")
        for i = 1, math.min(5, #list) do
            Print(string.format("  %s: about %d XP/hr (%d XP a kill, %d kills seen)", list[i].name, list[i].rate, list[i].per, list[i].n))
        end
        return true
    end
    if word == "session" then
        local mins = math.max(1, (time() - session.t0) / 60)
        local gold = (GetMoney and session.money0) and (GetMoney() - session.money0) or nil
        Print(string.format("this session (%s): %d XP (about %d per hour), %d quest%s turned in, %d kill%s looted%s",
            mins >= 120 and string.format("%.1f hours", mins / 60) or string.format("%d minutes", math.floor(mins + 0.5)),
            session.xp, math.floor(session.xp / mins * 60), session.quests, session.quests == 1 and "" or "s",
            session.kills, session.kills == 1 and "" or "s",
            gold and string.format(", %s%s", gold >= 0 and "+" or "-", (GetCoinTextureString and GetCoinTextureString(math.abs(gold))) or tostring(math.abs(gold))) or ""))
        return true
    end
    if word == "pace" and arg:lower() == "quests" then
        local q = Quests()
        local rows = {}
        for id, e in pairs(q) do
            local r = addon.HiveQuestRate(id)
            if r then
                local QDB = api.GetQuestie and api.GetQuestie()
                local name = QDB and QDB.QueryQuestSingle and QDB.QueryQuestSingle(id, "name") or ("quest " .. id)
                rows[#rows + 1] = { name, r, e.n }
            end
        end
        if #rows == 0 then Print("no timed quests yet: I time each quest from accepting it to turning it in"); return true end
        table.sort(rows, function(a, b) return a[2] > b[2] end)
        Print("your quests by XP per minute (accept to turn-in):")
        for i = 1, math.min(5, #rows) do Print(string.format("  fast: %s - %d XP/min", rows[i][1], rows[i][2])) end
        for i = #rows, math.max(#rows - 2, 6), -1 do Print(string.format("  slow: %s - %d XP/min", rows[i][1], rows[i][2])) end
        return true
    end
    if word == "pace" then
        local data = Root().xp[CharKey()]
        local any
        if data then
            local rows = {}
            for zone, zd in pairs(data) do
                local pace = addon.HivePace(zone)
                if pace then rows[#rows + 1] = { zone, pace } end
            end
            table.sort(rows, function(a, b) return a[2] > b[2] end)
            for i = 1, math.min(8, #rows) do
                any = true
                Print(string.format("  %s: about %d XP per hour near your level", rows[i][1], rows[i][2]))
            end
        end
        local best, bestPace, here, herePace = addon.HiveBestZone()
        if best and here and best ~= here and herePace and herePace < bestPace * 0.7 then
            Print(string.format("  you have earned more in %s (%d XP/hr) than here in %s (%d XP/hr)", best, bestPace, here, herePace))
        end
        local mins, pace = addon.HiveTimeToLevel()
        if mins then
            Print(string.format("at your pace (%d XP/hr) you reach the next level in about %s", pace, Clock(mins)))
        elseif not any then
            Print("not enough data yet: play for a few minutes and earn some XP, and I will start measuring")
        end
        return true
    elseif word == "drops" then
        if arg == "" then Print("/lazy drops <part of an item name>, for example /lazy drops light hide"); return true end
        local want = arg:lower()
        local seen, found = {}, 0
        for _, e in pairs(Root().drops) do
            for id in pairs(e.items or {}) do
                if not seen[id] then
                    seen[id] = true
                    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
                    if name and name:lower():find(want, 1, true) then
                        local list = addon.HiveDrops(id)
                        if #list > 0 then
                            found = found + 1
                            local bits = {}
                            for i = 1, math.min(3, #list) do
                                bits[#bits + 1] = string.format("%s %d%% (%d in %d)", list[i].name, math.floor(list[i].rate * 100 + 0.5), list[i].n, list[i].kills)
                            end
                            Print(name .. ": " .. table.concat(bits, "; "))
                        end
                    end
                end
            end
        end
        if found == 0 then Print("I have not seen anything like that drop yet (I count the corpses you loot, and need at least 3 kills of a mob)") end
        return true
    elseif word == "hive" then
        if arg:lower() == "reset" then
            local r = addon.GetRoot()
            r.hive = { xp = {}, drops = {} }
            seenKill, seenItem, seenCount = {}, {}, 0
            Print("everything the hive learned has been forgotten")
            return true
        end
        local mobs, items, kills = 0, 0, 0
        for _, e in pairs(Root().drops) do
            mobs = mobs + 1; kills = kills + (e.kills or 0)
            for _ in pairs(e.items or {}) do items = items + 1 end
        end
        local zones, secs = 0, 0
        for _, zd in pairs(Root().xp[CharKey()] or {}) do
            zones = zones + 1
            for _, e in pairs(zd) do secs = secs + e.secs end
        end
        Print(string.format("the hive has learned from %d kills of %d kinds of mob (%d item drops seen), and %d minutes of XP in %d zones for this character", kills, mobs, items, math.floor(secs / 60), zones))
        Print("the Hive is " .. ((addon.GetDB() and addon.GetDB().hiveOn) and "ON" or "OFF") .. ". /lazy hive on|off, /lazy pace, /lazy drops <item>, /lazy hive reset")
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Hive.lua"] = true end end
