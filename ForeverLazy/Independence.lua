-- Does the addon work without the quest data source (Questie)?
--   /lazy data questie off     pretend it is not installed (then /reload)
--   /lazy data questie on      back to normal (then /reload)
--   /lazy data selftest        checks the main pieces and says which work
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function Check(out, label, ok, detail)
    out[#out + 1] = string.format("%s  %s%s", ok and "ok    " or "FAILED", label, detail and (" - " .. tostring(detail)) or "")
    return ok
end

function addon.DataSelfTest()
    local out = {}
    local db = addon.GetDB()
    local real = _G.QuestieLoader and not db.noQuestie
    out[#out + 1] = real and "The source (Questie) is in use, with our own data set behind it." or
        (db.noQuestie and "Pretending the source is NOT installed: everything below runs on our own data."
            or "The source (Questie) is not installed: everything below runs on our own data.")

    local ready = api.QuestieReady and api.QuestieReady()
    Check(out, "quest data is ready", ready)
    local QDB = api.GetQuestie and api.GetQuestie()
    Check(out, "database object", QDB ~= nil, QDB and QDB.isOwnDatabase and "our own" or "the source's, wrapped")
    if QDB then
        Check(out, "a quest (Rethban Ore, 347)", QDB.QueryQuestSingle(347, "name") == "Rethban Ore", tostring(QDB.QueryQuestSingle(347, "name")))
        local giver = QDB.QueryQuestSingle(347, "startedBy")
        Check(out, "who gives it", type(giver) == "table" and type(giver[1]) == "table", giver and giver[1] and tostring(giver[1][1]))
        local npc = giver and giver[1] and giver[1][1]
        Check(out, "that creature", npc and QDB.QueryNPCSingle(npc, "name") ~= nil, npc and tostring(QDB.QueryNPCSingle(npc, "name")))
        local spawns = npc and QDB.QueryNPCSingle(npc, "spawns")
        Check(out, "where it stands", type(spawns) == "table" and next(spawns) ~= nil)
        local nq, nn = 0, 0
        for _ in pairs(QDB.QuestPointers or {}) do nq = nq + 1 end
        for _ in pairs(QDB.NPCPointers or {}) do nn = nn + 1 end
        Check(out, "quest and creature lists", nq > 5000 and nn > 10000, nq .. " quests, " .. nn .. " creatures")
        Check(out, "grey-quest check", QDB.IsTrivial ~= nil)
    end
    local zone = ns.data.Module("ZoneDB")
    Check(out, "zone data", zone and zone.GetUiMapIdByAreaId and zone:GetUiMapIdByAreaId(10) == 1431, "area 10 -> " .. tostring(zone and zone:GetUiMapIdByAreaId(10)))
    local T = ns.data.Module("Townsfolk")
    Check(out, "service lists (inns, repair ...)", T and T.townsfolk and T.townsfolk["Innkeeper"] and #T.townsfolk["Innkeeper"] > 20,
        T and T.townsfolk and T.townsfolk["Innkeeper"] and (#T.townsfolk["Innkeeper"] .. " innkeepers"))
    local avail = ns.data.Available()
    local n = 0
    for _ in pairs(avail or {}) do n = n + 1 end
    Check(out, "quests I can take", avail ~= nil and n > 0, n .. " available")
    Check(out, "quest XP", (ns.data.QuestXP(347) or 0) > 0, tostring(ns.data.QuestXP(347)))
    Check(out, "dungeon quest rule", api.IsDungeonQuest ~= nil and api.IsDungeonQuest(1442, false) == true, "Seeking the Kor Gem should count as a dungeon quest")
    Check(out, "plan", addon.PlanRoute ~= nil)
    out[#out + 1] = "Then try the real thing: /lazy plan, /lazy inn, /lazy level, the tracker and the step window."
    return out
end

-- One command does the whole test: /lazy selftest (or /lazy data test). It switches the source off, reloads the interface by itself,
-- and a few seconds after you are back shows the results in a window. /lazy selftest off switches the source back on the same way.
local function Reload(why)
    Print(why .. " Reloading the interface...")
    -- straight from the click or command (a timer is not allowed to reload)
    ReloadUI()
    -- only reached when the game refused: say what to do
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function() Print("The game would not reload by itself. Type /reload (the test is already set up and starts after it).") end)
    end
end

local boot = CreateFrame("Frame")
pcall(boot.RegisterEvent, boot, "PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local db = addon.GetDB()
    if not (db and db.selftestPending and C_Timer) then return end
    db.selftestPending = nil
    C_Timer.After(12, function()
        local lines = addon.DataSelfTest()
        lines[#lines + 1] = ""
        lines[#lines + 1] = "To go back to normal, type /lazy selftest off"
        if addon.ReportWindow then addon.ReportWindow("Test without the quest source", lines)
        else for _, l in ipairs(lines) do Print(l) end end
    end)
end)

-- start the test (off = false), or go back to normal (off = true). Used by the command and by the buttons in the options.
function addon.SelfTest(off)
    local db = addon.GetDB()
    if off then
        db.noQuestie = false
        db.selftestPending = nil
        Reload("Switching back to normal.")
    else
        db.noQuestie = true
        db.selftestPending = true
        Reload("Testing without the quest source (Questie stays installed, the addon just ignores it).")
    end
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "st" then c = "selftest" end
    local arg = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if c == "selftest" or (c == "data" and (arg == "test" or arg == "test off")) then
        local off = (c == "selftest" and arg == "off") or (c == "data" and arg == "test off")
        addon.SelfTest(off)
        return true
    end
    if c == "data" and (arg == "questie off" or arg == "questie on") then
        addon.GetDB().noQuestie = (arg == "questie off")
        Reload(arg == "questie off" and "Ignoring the quest source." or "Using the quest source again.")
        return true
    end
    if (cmd or ""):lower() == "data" then
        local a = arg
        if a == "selftest" then
            for _, l in ipairs(addon.DataSelfTest()) do Print(l) end
            return true
        end
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Independence.lua"] = true end end
