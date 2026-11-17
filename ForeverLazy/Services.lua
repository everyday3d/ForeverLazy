-- Services and trainers: the nearest innkeeper, repair, flight master, bank, auction house, mailbox, class trainer or
-- profession trainer, with the arrow on it.
--   /lazy inn | repair | flight | bank | ah | mailbox | stable | spirit | battlemaster
--   /lazy trainer            my class trainer
--   /lazy cooking            profession trainer (also: first aid, fishing, mining, herbalism, skinning, blacksmithing,
--                            leatherworking, tailoring, engineering, alchemy, enchanting, riding)
--   add a number for the next nearest, for example /lazy inn 2
-- The lists come from Questie's database, so they need Questie loaded and ready.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end

local function Mod(name)
    local ql = _G.QuestieLoader
    if not ql then return nil end
    local ok, m = pcall(ql.ImportModule, ql, name)
    return ok and m or nil
end

local PROFESSIONS = {   -- words -> Questie profession key name
    { { "first aid", "firstaid", "aid" }, "FIRST_AID" }, { { "blacksmith", "blacksmithing", "smith" }, "BLACKSMITHING" },
    { { "leatherworking", "leather" }, "LEATHERWORKING" }, { { "alchemy", "alch" }, "ALCHEMY" },
    { { "herbalism", "herb", "herbs" }, "HERBALISM" }, { { "cooking", "cook" }, "COOKING" },
    { { "mining", "mine" }, "MINING" }, { { "tailoring", "tailor" }, "TAILORING" },
    { { "engineering", "engineer" }, "ENGINEERING" }, { { "enchanting", "enchant" }, "ENCHANTING" },
    { { "fishing", "fish" }, "FISHING" }, { { "skinning", "skin" }, "SKINNING" }, { { "riding", "ride" }, "RIDING" },
}

-- word -> { label, how to get the ids }; "object" ids are game objects (mailboxes), the rest are NPCs
local SERVICES = {}
local function Service(words, label, getter, object)
    for _, w in ipairs(words) do SERVICES[w] = { label = label, get = getter, object = object } end
end
local function Town(category)
    return function(T) return T.townsfolk and T.townsfolk[category] end
end
Service({ "inn", "innkeeper" }, "innkeeper", Town("Innkeeper"))
Service({ "repair", "repairs" }, "repair vendor", Town("Repair"))
Service({ "flight", "fm", "flightmaster", "taxi" }, "flight master", Town("Flight Master"))
Service({ "bank", "banker" }, "banker", Town("Banker"))
Service({ "ah", "auction", "auctioneer" }, "auctioneer", Town("Auctioneer"))
Service({ "battlemaster", "bg", "battleground" }, "battlemaster", Town("Battlemaster"))
Service({ "stable", "stablemaster" }, "stable master", function(T)
    local cls = select(2, UnitClass("player"))
    local c = T.classSpecificTownsfolk and T.classSpecificTownsfolk[cls]
    return (c and c["Stable Master"]) or (T.townsfolk and T.townsfolk["Stable Master"])
end)
Service({ "spirit", "graveyard", "spirithealer" }, "spirit healer", function(T)
    local f = T.factionSpecificTownsfolk and T.factionSpecificTownsfolk[UnitFactionGroup("player")]
    return f and f["Spirit Healer"]
end)
Service({ "mailbox", "mail" }, "mailbox", function(T)
    local f = T.factionSpecificTownsfolk and T.factionSpecificTownsfolk[UnitFactionGroup("player")]
    return f and f["Mailbox"]
end, true)

local function ClassTrainers(T)
    local cls = select(2, UnitClass("player"))
    local c = T.classSpecificTownsfolk and T.classSpecificTownsfolk[cls]
    return c and c["Class Trainer"]
end

local function ProfessionTrainers(T, key)
    local P = Mod("QuestieProfessions")
    local id = P and P.professionKeys and P.professionKeys[key]
    return id and T.professionTrainers and T.professionTrainers[id]
end

local function MapName(id)
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or "?"
end

-- nearest few spots for these ids
local function Nearest(QDB, ids, object, limit)
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    local found = {}
    for _, id in ipairs(ids) do
        local ok = true
        if not object then
            local fr = QDB.QueryNPCSingle(id, "friendlyToFaction")
            ok = QDB.IsFriendlyToPlayer(fr)
        end
        if ok then
            local sp = {}
            if object then api.AddObjects(sp, { id }) else api.AddNpcs(sp, { id }) end
            local best, bd
            for _, s in ipairs(sp) do
                if px and s.instance == pinst then
                    local d = math.sqrt((s.x - px) ^ 2 + (s.y - py) ^ 2)
                    if not bd or d < bd then best, bd = s, d end
                end
            end
            if best then
                found[#found + 1] = { id = id, spawn = best, d = bd,
                                      name = object and (QDB.QueryObjectSingle(id, "name") or "Mailbox") or QDB.QueryNPCSingle(id, "name"),
                                      sub = (not object) and QDB.QueryNPCSingle(id, "subName") or nil }
            end
        end
    end
    table.sort(found, function(a, b) return a.d < b.d end)
    -- the same spot twice (two NPCs side by side) is one result
    local out = {}
    for _, f in ipairs(found) do
        local dup
        for _, o in ipairs(out) do
            if math.abs(o.spawn.x - f.spawn.x) < 15 and math.abs(o.spawn.y - f.spawn.y) < 15 and o.name == f.name then dup = true end
        end
        if not dup then out[#out + 1] = f end
        if #out >= limit then break end
    end
    return out
end

local function Go(r, label)
    local wps = DB().waypoints
    for i = #wps, 1, -1 do if wps[i].service then table.remove(wps, i) end end
    addon:AddWaypointZone(r.spawn.uiMapId, r.spawn.zx, r.spawn.zy, label .. ": " .. r.name)
    local w = DB().waypoints[1]
    if w then
        w.service = true
        w.detail = r.sub and (r.name .. ", " .. r.sub) or r.name
    end
end

local function Search(label, getter, object, pick)
    local T = Mod("Townsfolk")
    local QDB = api.GetQuestie()
    if not (T and QDB and api.QuestieReady and api.QuestieReady()) then Print("needs Questie loaded and ready"); return end
    local ids = getter(T)
    if not ids or #ids == 0 then
        Print("Questie has no " .. label .. " list yet (it is still loading, try again in a minute)")
        return
    end
    local list = Nearest(QDB, ids, object, 5)
    if #list == 0 then Print("no " .. label .. " found on this continent"); return end
    pick = math.min(math.max(tonumber(pick) or 1, 1), #list)
    for i, r in ipairs(list) do
        if i <= 3 or i == pick then
            Print(string.format("%s%d. %s%s - %s %.0f, %.0f (about %d yards)", i == pick and "> " or "  ", i, r.name,
                r.sub and (" (" .. r.sub .. ")") or "", MapName(r.spawn.uiMapId), r.spawn.zx * 100, r.spawn.zy * 100, r.d))
        end
    end
    Go(list[pick], label:gsub("^%l", string.upper))
    if #list > 1 and pick == 1 then Print("  add a number for the next nearest, for example /lazy inn 2") end
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    local arg = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local num = tonumber(arg:match("(%d+)$"))
    local text = (word .. " " .. arg):gsub("%s*%d+$", "")

    local svc = SERVICES[word]
    if svc then
        Search(svc.label, svc.get, svc.object, num)
        return true
    end
    -- class trainer, or a profession trainer with or without the word "trainer"
    local what = text
    local rest2 = arg:gsub("%s*%d+$", "")
    if word == "classtrainer" or (word == "class" and rest2 == "trainer")
        or ((word == "trainer" or word == "trainers") and (rest2 == "" or rest2 == "class")) then
        Search("class trainer", ClassTrainers, false, num)
        return true
    end
    if word == "trainer" or word == "trainers" then what = rest2 end
    for _, p in ipairs(PROFESSIONS) do
        for _, w in ipairs(p[1]) do
            if what == w or what == w .. " trainer" then
                Search(p[1][1] .. " trainer", function(T) return ProfessionTrainers(T, p[2]) end, false, num)
                return true
            end
        end
    end
    if prev then return prev(self, cmd, rest) end
end

-- lets the module switch (Modules.lua) know which commands belong here
function api.IsServiceCommand(cmd, rest)
    local word = (cmd or ""):lower()
    local arg = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if SERVICES[word] or word == "classtrainer" or word == "trainer" or word == "trainers" then return true end
    if word == "class" and (arg:gsub("%s*%d+$", "")) == "trainer" then return true end
    local what = ((word .. " " .. arg):gsub("%s*%d+$", ""))
    for _, p in ipairs(PROFESSIONS) do
        for _, w in ipairs(p[1]) do
            if what == w or what == w .. " trainer" then return true end
        end
    end
    return false
end

-- used by Lazy Mode: the nearest one of a kind, or nil
function api.FindService(word)
    local T = Mod("Townsfolk")
    local QDB = api.GetQuestie()
    if not (T and QDB and api.QuestieReady and api.QuestieReady()) then return nil end
    local ids, object
    if word == "classtrainer" then
        ids = ClassTrainers(T)
    else
        local svc = SERVICES[word]
        if not svc then return nil end
        ids, object = svc.get(T), svc.object
    end
    if not ids or #ids == 0 then return nil end
    local list = Nearest(QDB, ids, object, 1)
    return list[1]
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Services.lua"] = true end end
