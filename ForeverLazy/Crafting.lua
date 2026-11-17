-- Crafting: what to craft next to raise a profession, the materials for it, and where to get what is missing.
-- It counts what is in my bags AND my bank (it remembers the bank from the last time I opened it).
--   open a profession window once          it reads the recipes I know
--   /lazy craft [profession] [skill goal]  the plan: best recipe, how many, materials, sources
--   /lazy craft go [n]                     arrow to where to get the n-th missing material
--   /lazy craft bank                       arrow to the nearest banker (when materials are waiting in the bank)
-- Recipes and their colours come from the game; vendors, drops and herb or ore spots come from Questie.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print
local hbd = api.hbd

local function DB() return addon.GetDB() end
local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

local function Section(name)
    local root = addon.GetRoot()
    root[name] = root[name] or {}
    root[name][CharKey()] = root[name][CharKey()] or {}
    return root[name][CharKey()]
end

local function MapName(id)
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or "?"
end

--------------------------------------------------------------------------------
-- Bags and bank
--------------------------------------------------------------------------------
local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
end

local function ItemAt(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount or 1 end
        return nil
    end
    if GetContainerItemLink then
        local link = GetContainerItemLink(bag, slot)
        if link then
            local _, count = GetContainerItemInfo(bag, slot)
            return tonumber(link:match("item:(%d+)")), count or 1
        end
    end
end

local bankOpen = false
local function ScanBank()
    local items = {}
    local bags = { _G.BANK_CONTAINER or -1 }
    local first = (_G.NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (_G.NUM_BANKBAGSLOTS or 7) - 1 do bags[#bags + 1] = b end
    for _, bag in ipairs(bags) do
        for slot = 1, NumSlots(bag) do
            local id, count = ItemAt(bag, slot)
            if id then items[id] = (items[id] or 0) + count end
        end
    end
    local s = Section("bank")
    s.items, s.t = items, time()
end

local function InBags(id)
    return GetItemCount(id, false) or 0
end

-- nil when I have never opened my bank
local function InBank(id)
    local s = Section("bank")
    if not s.items then return nil end
    return s.items[id] or 0
end

local bankEv = CreateFrame("Frame")
bankEv:RegisterEvent("BANKFRAME_OPENED")
bankEv:RegisterEvent("BANKFRAME_CLOSED")
bankEv:RegisterEvent("BAG_UPDATE_DELAYED")
bankEv:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        if C_Timer then C_Timer.After(0.5, function() if bankOpen then pcall(ScanBank) end end) end
    elseif event == "BANKFRAME_CLOSED" then
        pcall(ScanBank)
        bankOpen = false
    elseif bankOpen then
        pcall(ScanBank)
    end
end)

--------------------------------------------------------------------------------
-- The recipes I know (read when a profession window is open)
--------------------------------------------------------------------------------
local lastProfession
local reading

local function ReadRecipes()
    if reading or not (GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo) then return end
    local prof, rank, maxRank = GetTradeSkillLine()
    if not prof or prof == "" or prof == "UNKNOWN" then return end
    reading = true
    -- recipes under a closed heading are not listed, so open them all first
    if ExpandTradeSkillSubClass then
        for i = GetNumTradeSkills(), 1, -1 do
            local name, kind, _, expanded = GetTradeSkillInfo(i)
            if kind == "header" and not expanded then pcall(ExpandTradeSkillSubClass, i) end
        end
    end
    local recipes = {}
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" then
            local r = { name = name, kind = kind, reagents = {} }
            for j = 1, (GetTradeSkillNumReagents(i) or 0) do
                local rn, _, rc = GetTradeSkillReagentInfo(i, j)
                local link = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j)
                r.reagents[#r.reagents + 1] = { name = rn, count = rc or 1, id = link and tonumber(link:match("item:(%d+)")) }
            end
            recipes[#recipes + 1] = r
        end
    end
    Section("crafting")[prof] = { rank = rank, max = maxRank, recipes = recipes, t = time() }
    lastProfession = prof
    reading = false
end

-- Enchanting has its own window (the "craft" window) with the same kind of data
local function ReadCrafts()
    if reading or not (GetCraftDisplaySkillLine and GetNumCrafts and GetCraftInfo) then return end
    local prof, rank, maxRank = GetCraftDisplaySkillLine()
    if not prof or prof == "" then return end
    reading = true
    if ExpandCraftSkillLine then
        for i = GetNumCrafts(), 1, -1 do
            local _, _, kind, _, expanded = GetCraftInfo(i)
            if kind == "header" and not expanded then pcall(ExpandCraftSkillLine, i) end
        end
    end
    local recipes = {}
    for i = 1, GetNumCrafts() do
        local name, _, kind = GetCraftInfo(i)
        if name and kind ~= "header" then
            local r = { name = name, kind = kind, reagents = {} }
            for j = 1, (GetCraftNumReagents(i) or 0) do
                local rn, _, rc = GetCraftReagentInfo(i, j)
                local link = GetCraftReagentItemLink and GetCraftReagentItemLink(i, j)
                r.reagents[#r.reagents + 1] = { name = rn, count = rc or 1, id = link and tonumber(link:match("item:(%d+)")) }
            end
            recipes[#recipes + 1] = r
        end
    end
    Section("crafting")[prof] = { rank = rank, max = maxRank, recipes = recipes, t = time() }
    lastProfession = prof
    reading = false
end

--------------------------------------------------------------------------------
-- Where to get a material
--------------------------------------------------------------------------------
local function NearestSource(QDB, id)
    local px, py, pinst = hbd:GetPlayerWorldPosition()
    if not px then return nil end
    local here = { x = px, y = py }
    local function nearest(spawns)
        local best, bd
        for _, s in ipairs(spawns) do
            if s.instance == pinst then
                local d = Dist(here, s)
                if not bd or d < bd then best, bd = s, d end
            end
        end
        return best, bd
    end
    -- 1. a vendor sells it
    local vendors = QDB.QueryItemSingle(id, "vendors")
    if type(vendors) == "table" then
        local bestS, bestD, bestName
        for _, npc in pairs(vendors) do
            if QDB.IsFriendlyToPlayer(QDB.QueryNPCSingle(npc, "friendlyToFaction")) then
                local sp = {}
                api.AddNpcs(sp, { npc })
                local s, d = nearest(sp)
                if s and (not bestD or d < bestD) then bestS, bestD, bestName = s, d, QDB.QueryNPCSingle(npc, "name") end
            end
        end
        if bestS then return { kind = "vendor", name = bestName, spawn = bestS, d = bestD } end
    end
    -- 2. an herb, ore or other node
    local objs = QDB.QueryItemSingle(id, "objectDrops")
    if type(objs) == "table" then
        local bestS, bestD, bestName
        for _, o in pairs(objs) do
            local sp = {}
            api.AddObjects(sp, { o })
            local s, d = nearest(sp)
            if s and (not bestD or d < bestD) then bestS, bestD, bestName = s, d, QDB.QueryObjectSingle(o, "name") end
        end
        if bestS then return { kind = "node", name = bestName, spawn = bestS, d = bestD } end
    end
    -- 3. a creature drops it
    local drops = QDB.QueryItemSingle(id, "npcDrops")
    if type(drops) == "table" then
        local bestS, bestD, bestName, n = nil, nil, nil, 0
        for _, npc in pairs(drops) do
            n = n + 1
            if n > 40 then break end
            local sp = {}
            api.AddNpcs(sp, { npc })
            local s, d = nearest(sp)
            if s and (not bestD or d < bestD) then bestS, bestD, bestName = s, d, QDB.QueryNPCSingle(npc, "name") end
        end
        if bestS then return { kind = "drop", name = bestName, spawn = bestS, d = bestD } end
    end
    return nil
end

local function IsVendorSold(QDB, id)
    local v = QDB.QueryItemSingle(id, "vendors")
    return type(v) == "table" and next(v) ~= nil
end

--------------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------------
local CHANCE = { optimal = 1.0, medium = 0.5, easy = 0.2, trivial = 0 }
local COLOR = { optimal = "orange", medium = "yellow", easy = "green", trivial = "grey" }
local TARGETS = { 75, 150, 225, 300 }

local needs = {}      -- the shopping list of the last plan, for /lazy craft go
function addon.CraftNeeds() return needs end

local function Pick(profData)
    local QDB = (api.QuestieReady and api.QuestieReady()) and api.GetQuestie() or nil
    local best, bestScore
    for _, r in ipairs(profData.recipes) do
        local chance = CHANCE[r.kind] or 0
        if chance > 0 then
            -- cheap to make: few materials, and ones I can simply buy
            local cost = 0
            for _, re in ipairs(r.reagents) do
                local weight = (QDB and re.id and IsVendorSold(QDB, re.id)) and 1 or 3
                cost = cost + (re.count or 1) * weight
            end
            if cost == 0 then cost = 1 end
            local score = chance / cost
            if not bestScore or score > bestScore then best, bestScore = r, score end
        end
    end
    return best
end

local capture, lastIds = nil, {}
local function Say(s) if capture then capture[#capture + 1] = s else Print(s) end end
function addon.CraftReagentIds() return lastIds end

local function Plan(profName, goalArg)
    local data = Section("crafting")
    local prof
    if profName and profName ~= "" then
        for name in pairs(data) do
            if name:lower():find(profName:lower(), 1, true) then prof = name; break end
        end
        if not prof then
            Say("I don't know your " .. profName .. " recipes yet. Open the profession window once, then try again.")
            return
        end
    else
        prof = lastProfession
        if not prof then
            for name in pairs(data) do prof = name; break end
        end
    end
    if not prof then Say("open a profession window once so I can read your recipes, then /lazy craft"); return end
    local pd = data[prof]
    local rank, maxRank = pd.rank or 0, pd.max or 300
    local goal = tonumber(goalArg)
    if not goal then
        for _, t in ipairs(TARGETS) do if t > rank and t <= maxRank then goal = t; break end end
        goal = goal or maxRank
    end
    if rank >= goal then Say(string.format("%s is already %d, past %d", prof, rank, goal)); return end
    Say(string.format("%s %d/%d, planning up to %d (recipes as of the last time you opened the window)", prof, rank, maxRank, goal))

    local r = Pick(pd)
    if not r then
        Say("nothing you know gives skill points right now. Learn new recipes from the profession trainer: /lazy " .. prof:lower())
        return
    end
    local chance = CHANCE[r.kind]
    local points = goal - rank
    local crafts = math.min(60, math.max(1, math.ceil(points / chance)))
    Say(string.format("  craft %d x %s (%s, about %d skill points). Open the window again afterwards and plan again as it turns green.",
        crafts, r.name, COLOR[r.kind] or r.kind, math.floor(crafts * chance)))

    needs = {}
    lastIds = {}
    for _, re in ipairs(r.reagents) do if re.id then lastIds[re.id] = true end end
    local QDB = (api.QuestieReady and api.QuestieReady()) and api.GetQuestie() or nil
    local anyBank, bankKnown = false, nil
    for _, re in ipairs(r.reagents) do
        local total = (re.count or 1) * crafts
        local inBags = re.id and InBags(re.id) or 0
        local inBank = re.id and InBank(re.id)
        local bankN = inBank or 0
        local fromBank = math.min(bankN, math.max(0, total - inBags))
        local missing = math.max(0, total - inBags - fromBank)
        if inBank == nil then bankKnown = false end
        if fromBank > 0 then anyBank = true end

        local line = string.format("  %s: need %d, %d in your bags", re.name or "?", total, inBags)
        if inBank ~= nil then line = line .. string.format(", %d in your bank", inBank) end
        if missing == 0 and fromBank == 0 then
            line = line .. "  |cff55ff55ok|r"
        else
            if fromBank > 0 then line = line .. string.format("  |cffffd100take %d from the bank|r", fromBank) end
            if missing > 0 then
                line = line .. string.format("  |cffff8800%d still to get|r", missing)
                local src = QDB and re.id and NearestSource(QDB, re.id)
                if src then
                    line = line .. string.format(" (%s: %s, %s %.0f, %.0f, about %d yards)", src.kind, src.name or "?",
                        MapName(src.spawn.uiMapId), src.spawn.zx * 100, src.spawn.zy * 100, src.d)
                    needs[#needs + 1] = { name = re.name, src = src }
                else
                    line = line .. " (made from other materials, or Questie has no source on this continent)"
                end
            end
        end
        Say(line)
    end
    if anyBank then Say("  some of it is waiting in your bank: /lazy craft bank takes you to the nearest banker") end
    if bankKnown == false then Say("  I have never seen inside your bank. Open it once and I will count it too.") end
    if #needs > 0 then Say("  /lazy craft go points at where to get the first missing material") end
end


function addon.CraftPlanText(profName, goal)
    capture = {}
    local ok = pcall(Plan, profName, goal)
    local out = capture
    capture = nil
    return out
end

local function Go(n)
    local item = needs[tonumber(n) or 1]
    if not item then Print("nothing missing to go to, or no plan yet: /lazy craft"); return end
    local s = item.src.spawn
    addon:AddWaypointZone(s.uiMapId, s.zx, s.zy, string.format("Get %s: %s", item.name or "material", item.src.name or item.src.kind))
    local w = DB().waypoints[1]
    if w then w.craft = true; w.detail = string.format("%s: %s", item.src.kind, item.src.name or "?") end
end

--------------------------------------------------------------------------------
-- Events and commands
--------------------------------------------------------------------------------
local pending
local ev = CreateFrame("Frame")
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_UPDATE")
pcall(ev.RegisterEvent, ev, "CRAFT_SHOW")
pcall(ev.RegisterEvent, ev, "CRAFT_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if not addon.ModuleOn("crafting") or reading or pending or not C_Timer then return end
    pending = true
    C_Timer.After(0.6, function()
        pending = false
        if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then pcall(ReadCrafts) else pcall(ReadRecipes) end
        if (event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW") and DB().craftHint ~= false and lastProfession then
            local pd = Section("crafting")[lastProfession]
            local r = pd and Pick(pd)
            if r then
                Print(string.format("best next craft for %s: %s (%s). /lazy craft plans the whole stretch.", lastProfession, r.name, COLOR[r.kind] or r.kind))
            end
        end
    end)
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local word = (cmd or ""):lower()
    if word == "craft" or word == "crafting" then
        local arg = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if arg:match("^go") then
            Go(arg:match("^go%s*(%d*)"))
        elseif arg == "bank" then
            local r = api.FindService and api.FindService("bank")
            if r then
                addon:AddWaypointZone(r.spawn.uiMapId, r.spawn.zx, r.spawn.zy, "Bank: " .. (r.name or "banker"))
            else
                Print("I could not find a banker on this continent (needs Questie)")
            end
        else
            local goal = arg:match("(%d+)%s*$")
            local name = (arg:gsub("%s*%d+%s*$", ""))
            Plan(name, goal)
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end
