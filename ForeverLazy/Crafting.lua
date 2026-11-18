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

-- an item's name, from whichever item function this client has (nil if it is not loaded yet)
local function ItemName(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(id)
        if n then return n end
    end
    if GetItemInfo then
        local n = GetItemInfo(id)
        if n then return n end
    end
    return nil
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
pcall(bankEv.RegisterEvent, bankEv, "BANKFRAME_OPENED")
pcall(bankEv.RegisterEvent, bankEv, "BANKFRAME_CLOSED")
pcall(bankEv.RegisterEvent, bankEv, "BAG_UPDATE_DELAYED")
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
    -- 1b. a mob I have seen drop it myself (the hive counts the corpses I loot)
    local hb = addon.HiveBest and addon.HiveBest(id)
    if hb then
        local sp = {}
        api.AddNpcs(sp, { hb.npc })
        local s, d = nearest(sp)
        if s then
            return { kind = "drop", name = string.format("%s, %d%% of the kills I have seen", hb.name or "?", math.floor(hb.rate * 100 + 0.5)),
                     spawn = s, d = d }
        end
    end
    -- 2. an herb, ore or other node
    local objs = QDB.QueryItemSingle(id, "objectDrops")
    if type(objs) == "table" then
        local bestS, bestD, bestName
        for _, o in pairs(objs) do
            local oname = tostring(QDB.QueryObjectSingle(o, "name") or "")
            local low = oname:lower()
            -- chests, crates and the like are random loot, not a place to farm a material
            local container = low:find("chest") or low:find("crate") or low:find("barrel") or low:find("box")
                or low:find("cache") or low:find("footlocker") or low:find("trunk") or low:find("sack")
            if not container then
                local sp = {}
                api.AddObjects(sp, { o })
                local s, d = nearest(sp)
                if s and (not bestD or d < bestD) then bestS, bestD, bestName = s, d, oname end
            end
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
    -- orange recipes always give a skill point, so choose among those when there are any
    local hasOrange = false
    for _, r in ipairs(profData.recipes) do
        if r.kind == "optimal" then hasOrange = true; break end
    end
    for _, r in ipairs(profData.recipes) do
        local chance = CHANCE[r.kind] or 0
        if chance > 0 and (not hasOrange or r.kind == "optimal") then
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
local lastPick
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
            Say(capture and "Click |cffffd100Plan it|r below to read your recipes." or ("I don't know your " .. profName .. " recipes yet. Open the profession window once, then try again."))
            return
        end
    else
        prof = lastProfession
        if not prof then
            for name in pairs(data) do prof = name; break end
        end
    end
    if not prof then Say(capture and "Click |cffffd100Plan it|r below to read your recipes." or "open a profession window once so I can read your recipes, then /lazy craft"); return end
    local pd = data[prof]
    local rank, maxRank = pd.rank or 0, pd.max or 300
    local goal = tonumber(goalArg)
    if not goal then
        for _, t in ipairs(TARGETS) do if t > rank and t <= maxRank then goal = t; break end end
        goal = goal or maxRank
    end
    if rank >= goal then Say(string.format("%s is already %d, past %d", prof, rank, goal)); return end
    -- Training changes the plan: new recipes open up and the best one to craft changes. So the plan stops where the
    -- trainer next has something (as last seen), and never runs more than one batch before it asks me to look again.
    local stopNote
    local tr = Section("crafttrain")[prof]
    if tr then
        if (tr.learnNow or 0) > 0 then
            stopNote = string.format("the trainer had %d recipe%s you could learn right away: train first, it may change what is best",
                tr.learnNow, tr.learnNow == 1 and "" or "s")
        end
        local nextReq
        for _, rq in ipairs(tr.reqs or {}) do
            if rq > rank and (not nextReq or rq < nextReq) then nextReq = rq end
        end
        if nextReq and nextReq < goal then
            goal = nextReq
            stopNote = (stopNote and (stopNote .. ". ") or "")
                .. string.format("this stops at skill %d, where the trainer has more: visit the trainer, then plan again", nextReq)
        end
    else
        stopNote = "I have not seen your trainer's recipe list yet; visit the profession trainer once so I can stop where new recipes open up"
    end
    local BATCH = 25
    if goal - rank > BATCH then
        goal = rank + BATCH
        stopNote = (stopNote and (stopNote .. ". ") or "")
            .. string.format("one batch only (to %d): the colours change as your skill rises, so open the window and plan again after it", goal)
    end
    Say(string.format("%s %d/%d, planning up to %d (recipes as of the last time you opened the window)", prof, rank, maxRank, goal))

    local r = Pick(pd)
    if not r then
        Say("nothing you know gives skill points right now. Learn new recipes from the profession trainer: /lazy " .. prof:lower())
        return
    end
    local chance = CHANCE[r.kind]
    local points = goal - rank
    local crafts = math.min(60, math.max(1, math.ceil(points / chance)))
    lastPick = { id = r.id, crafts = crafts, prof = prof }
    Say(string.format("  craft %d x %s (%s, about %d skill points). Open the window again afterwards and plan again as it turns green.",
        crafts, r.name, COLOR[r.kind] or r.kind, math.floor(crafts * chance)))
    if stopNote then Say("  " .. stopNote) end

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

        local rname = ItemName(re.id) or re.name or "?"
        local line = string.format("  %s: need %d, %d in your bags", rname, total, inBags)
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
                    local nm = tostring(re.name or ""):lower()
                    local hint
                    local ZONES = {
                        { "light leather", "skin beasts in Elwynn Forest, Westfall, Dun Morogh, Durotar, Mulgore or Tirisfal Glades" },
                        { "light hide", "skin beasts in Elwynn Forest, Westfall, Dun Morogh, Durotar, Mulgore or Tirisfal Glades" },
                        { "medium", "skin beasts in Redridge, Duskwood, Darkshore, the Barrens or Ashenvale" },
                        { "heavy", "skin beasts in Wetlands, Hillsbrad, Arathi, Stonetalon or Desolace" },
                        { "thick", "skin beasts in Stranglethorn, Badlands, Swamp of Sorrows, Feralas, Dustwallow or Tanaris" },
                        { "rugged", "skin beasts in Un'Goro, Winterspring, Burning Steppes, Eastern Plaguelands or Silithus" },
                        { "copper", "mine it in Elwynn Forest, Dun Morogh, Durotar or Mulgore" },
                        { "tin", "mine it in Westfall, Loch Modan, the Barrens, Silverpine or Darkshore" },
                        { "iron", "mine it in Hillsbrad, Ashenvale, Arathi, Wetlands or Stonetalon" },
                        { "mithril", "mine it in Stranglethorn, Badlands, Desolace, Feralas or Tanaris" },
                        { "thorium", "mine it in Un'Goro, Silithus, Winterspring or Burning Steppes" },
                        { "linen", "loot humanoids in Elwynn Forest, Westfall, Durotar or Tirisfal Glades" },
                        { "wool", "loot humanoids in Redridge, Duskwood, the Barrens or Ashenvale" },
                        { "silk", "loot humanoids in Hillsbrad, Arathi, Wetlands or Stranglethorn" },
                        { "mageweave", "loot humanoids in Stranglethorn, Badlands, Tanaris or Feralas" },
                        { "runecloth", "loot humanoids in the Plaguelands, Winterspring or Silithus" },
                    }
                    for _, z in ipairs(ZONES) do
                        if nm:find("%f[%a]" .. z[1] .. "%f[%A]") then hint = z[2] .. ", or buy it at the auction house"; break end
                    end
                    if hint then
                        -- zone hint found
                    elseif nm:find("leather") or nm:find("hide") or nm:find("scale") then
                        hint = "skin beasts of about your level, or buy it at the auction house"
                    elseif nm:find("ore") or nm:find("bar") or nm:find("stone") then
                        hint = "mine it, or buy it at the auction house"
                    elseif nm:find("cloth") or nm:find("bolt") then
                        hint = "loot it from humanoids, or buy it at the auction house"
                    else
                        hint = "buy it at the auction house, or it is made from other materials"
                    end
                    line = line .. " (" .. hint .. ")"
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
    local ok, err = pcall(Plan, profName, goal)
    local out = capture
    capture = nil
    if not ok then out[#out + 1] = "|cffff5555error: " .. tostring(err) .. "|r" end
    -- when there is no plan, say why right in the panel
    local d = addon.CraftDiag
    if #out <= 1 and d then
        out[#out + 1] = "|cff888888read: profession " .. tostring(d.profession) .. ", " .. tostring(d.total or "?") .. " recipes listed, "
            .. tostring(d.recipes or 0) .. " known" .. (d.note and (", " .. d.note) or "") .. "|r"
        if d.sample then out[#out + 1] = "|cff888888fields: " .. d.sample .. "|r" end
    elseif #out <= 1 then
        out[#out + 1] = "|cff888888no read was attempted yet|r"
    end
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

-- The newer professions window (this client): recipes come from C_TradeSkillUI
local function ReadModern()
    local diag = { when = time() }
    addon.CraftDiag = diag
    if reading then diag.note = "already reading"; return end
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then
        diag.note = "this client has no C_TradeSkillUI recipe functions"
        return
    end
    -- which profession is open, and my skill in it
    local prof, rank, maxRank
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local b = C_TradeSkillUI.GetBaseProfessionInfo()
        if type(b) == "table" then prof = b.professionName or b.parentProfessionName; rank = b.skillLevel; maxRank = b.maxSkillLevel end
    end
    if (not prof or prof == "") and C_TradeSkillUI.GetTradeSkillLine then
        local _, name, r, m = C_TradeSkillUI.GetTradeSkillLine()
        prof, rank, maxRank = name, r, m
    end
    if (not prof or prof == "") and _G.ProfessionsFrame and ProfessionsFrame.GetTitleText then
        prof = ProfessionsFrame:GetTitleText()
    end
    diag.profession = prof
    if not prof or prof == "" then diag.note = "could not tell which profession is open"; return end

    reading = true
    local ok, err = pcall(function()
        local E = Enum and Enum.TradeskillRelativeDifficulty
        local function kindOf(d)
            if E then
                if d == E.Optimal then return "optimal" elseif d == E.Medium then return "medium" elseif d == E.Easy then return "easy" end
                return "trivial"
            end
            return ({ [0] = "optimal", [1] = "medium", [2] = "easy" })[d] or "trivial"
        end
        local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
        local ids = C_TradeSkillUI.GetAllRecipeIDs() or {}
        if #ids == 0 and C_TradeSkillUI.GetFilteredRecipeIDs then ids = C_TradeSkillUI.GetFilteredRecipeIDs() or {} end
        diag.total = #ids
        if ids[1] then
            local first = C_TradeSkillUI.GetRecipeInfo(ids[1])
            if type(first) == "table" then
                local keys = {}
                for k in pairs(first) do keys[#keys + 1] = tostring(k) end
                table.sort(keys)
                diag.sample = table.concat(keys, ", "):sub(1, 220)
            else
                diag.sample = "GetRecipeInfo gave " .. type(first)
            end
        end
        local recipes = {}
        for _, id in ipairs(ids) do
            local info = C_TradeSkillUI.GetRecipeInfo(id)
            if info and info.name and info.learned ~= false then
                local r = { id = id, name = info.name, kind = kindOf(info.relativeDifficulty), reagents = {} }
                local okS, schem = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
                if okS and type(schem) == "table" and schem.reagentSlotSchematics then
                    for _, slot in ipairs(schem.reagentSlotSchematics) do
                        local first = slot.reagents and slot.reagents[1]
                        if first and first.itemID and (basic == nil or slot.reagentType == nil or slot.reagentType == basic) then
                            r.reagents[#r.reagents + 1] = { name = ItemName(first.itemID) or ("item " .. first.itemID),
                                                            count = slot.quantityRequired or 1, id = first.itemID }
                        end
                    end
                end
                recipes[#recipes + 1] = r
            end
        end
        diag.recipes = #recipes
        if #recipes > 0 then
            Section("crafting")[prof] = { rank = rank or 0, max = maxRank or 300, recipes = recipes, t = time() }
            lastProfession = prof
        else
            diag.note = diag.total == 0 and "the window listed no recipes yet (it may still be loading)" or "no learned recipes found"
        end
    end)
    reading = false
    if not ok then diag.note = "error: " .. tostring(err) end
end

-- whichever window this client has; the newer one first
local function ReadAny()
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        ReadModern()
        local d = addon.CraftDiag
        if d and d.recipes and d.recipes > 0 then return end
    end
    if GetTradeSkillLine and GetNumTradeSkills then return ReadRecipes() end
end
function addon.ReadProfession() pcall(ReadAny) end

--------------------------------------------------------------------------------
-- Events and commands
--------------------------------------------------------------------------------
local pending
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_SHOW")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_UPDATE")
pcall(ev.RegisterEvent, ev, "CRAFT_SHOW")
pcall(ev.RegisterEvent, ev, "CRAFT_UPDATE")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_LIST_UPDATE")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_DATA_SOURCE_CHANGED")
ev:SetScript("OnEvent", function(_, event)
    if not addon.ModuleOn("crafting") or reading or pending or not C_Timer then return end
    pending = true
    C_Timer.After(0.6, function()
        pending = false
        if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then pcall(ReadCrafts) else pcall(ReadAny) end
        if (event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED") and DB().craftHint ~= false and lastProfession
            and (not addon.lastCraftHint or GetTime() - addon.lastCraftHint > 60) then
            addon.lastCraftHint = GetTime()
            local pd = Section("crafting")[lastProfession]
            local r = pd and Pick(pd)
            if r then
                Print(string.format("best next craft for %s: %s (%s). /lazy craft plans the whole stretch.", lastProfession, r.name, COLOR[r.kind] or r.kind))
            end
        end
    end)
end)

-- a profession trainer's list: what I could learn right now, and the skill at which each recipe opens
local function ReadProfessionTrainer()
    if not (IsTradeskillTrainer and IsTradeskillTrainer() and GetNumTrainerServices and GetTrainerServiceInfo) then return end
    local n = GetNumTrainerServices() or 0
    if n == 0 then return end
    local prof = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(1)
    if not prof then return end
    local reqs, learnNow = {}, 0
    for i = 1, n do
        local name, _, category = GetTrainerServiceInfo(i)
        if name and category ~= "header" and category ~= "used" then
            if category == "available" then learnNow = learnNow + 1 end
            if GetTrainerServiceSkillReq then
                local _, lvl = GetTrainerServiceSkillReq(i)
                if tonumber(lvl) then reqs[#reqs + 1] = tonumber(lvl) end
            end
        end
    end
    table.sort(reqs)
    Section("crafttrain")[prof] = { t = time(), learnNow = learnNow, reqs = reqs }
end
local trainEv = CreateFrame("Frame")
pcall(trainEv.RegisterEvent, trainEv, "TRAINER_SHOW")
pcall(trainEv.RegisterEvent, trainEv, "TRAINER_UPDATE")
trainEv:SetScript("OnEvent", function()
    if C_Timer then C_Timer.After(0.4, function() pcall(ReadProfessionTrainer) end) else pcall(ReadProfessionTrainer) end
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

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Crafting.lua"] = true end end

-- for the profession window: the recipe to craft next, how many, and the ones that still give skill-ups
function addon.CraftHighlights()
    local pd = lastProfession and Section("crafting")[lastProfession]
    local useful = {}
    if pd then
        for _, r in ipairs(pd.recipes) do
            if r.id and (r.kind == "optimal" or r.kind == "medium") then useful[r.id] = r.kind end
        end
    end
    return lastPick and lastPick.id, lastPick and lastPick.crafts, useful
end
