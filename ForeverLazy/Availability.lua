-- Which quests I can take right now, worked out from our own data set (level, race, class, prerequisites, chains, reputation,
-- professions, spells), so the source's available-quests list is not needed. Used by ns.data.Available().
--   ns.data.ComputeAvailable()   table whose keys are the ids of quests I may pick up (cached for a few seconds)
--   ns.data.WhyNot(id)           the first rule that rules a quest out, or nil when it is available
--   ns.data.VerifyAvailable()    lines comparing this with the source's own list
local ADDON, ns = ...
local addon = ns.addon
local data = ns.data
local DS = ns.dataset

local function Q(id, field) return data.Field("quests", id, field) end

local function Bit(mask, n)
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

local function Completed(id)
    return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
end

local function Active(id)
    if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return false end
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    return ok and idx and idx > 0 and true or false
end

local hiddenSet
local function Hidden(id)
    if not hiddenSet then
        hiddenSet = {}
        for _, v in ipairs(DS.hidden or {}) do hiddenSet[v] = true end
        -- the groups the source hides by its own settings: the Ahn'Qiraj war effort and the invasion events
        for _, list in pairs(DS.hiddenGroups or {}) do
            for _, v in ipairs(list) do hiddenSet[v] = true end
        end
    end
    return hiddenSet[id]
end

--------------------------------------------------------------------------------
-- The player
--------------------------------------------------------------------------------
local me = { rep = {}, skill = {} }
local function Refresh()
    me.level = UnitLevel and UnitLevel("player") or 1
    me.race = select(3, UnitRace("player"))
    me.class = select(3, UnitClass("player"))
    -- on Forever the grey cutoff comes from C_QuestLog.GetTrivialRange, elsewhere from GetQuestGreenRange
    if C_QuestLog and C_QuestLog.GetTrivialRange then
        local ok, v = pcall(C_QuestLog.GetTrivialRange)
        me.green = ok and tonumber(v) or nil
    end
    if not me.green then me.green = (GetQuestGreenRange and tonumber(GetQuestGreenRange("player"))) or 8 end
    -- reputation and skills, read once per pass
    me.rep, me.skill, me.skillById = {}, {}, {}
    if GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() do
            local _, _, _, _, _, earned, _, _, isHeader, _, _, _, _, factionId = GetFactionInfo(i)
            if factionId and not isHeader then me.rep[factionId] = earned or 0 end
        end
    end
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        -- open collapsed headers back to front, so lines listed under them show up
        if C_SkillInfo.ExpandSkillHeader then
            for i = C_SkillInfo.GetNumSkillLines(), 1, -1 do
                local line = C_SkillInfo.GetSkillLineInfo(i)
                if line and line.isHeader and line.isCollapsed then pcall(C_SkillInfo.ExpandSkillHeader, i) end
            end
        end
        for i = 1, C_SkillInfo.GetNumSkillLines() do
            local line = C_SkillInfo.GetSkillLineInfo(i)
            if line and not line.isHeader then
                if line.skillID then me.skillById[line.skillID] = line.rank or 0 end
                if line.name then me.skill[line.name:lower():gsub("[%s_]", "")] = line.rank or 0 end
            end
        end
    elseif GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank = GetSkillLineInfo(i)
            if name and not header then me.skill[name:lower():gsub("[%s_]", "")] = rank or 0 end
        end
    end
end

-- profession id -> name, from the key names ("FIRST_AID" = 129 -> "firstaid")
local skillName
local function SkillRank(skillId)
    if me.skillById and me.skillById[skillId] then return me.skillById[skillId] end
    if not skillName then
        skillName = {}
        local keys = DS.townsfolk and DS.townsfolk.professionKeys or {}
        for key, id in pairs(keys) do skillName[id] = key:lower():gsub("[%s_]", "") end
    end
    local n = skillName[skillId]
    if n then return me.skill[n] end
    return nil
end

--------------------------------------------------------------------------------
-- The rules, in the order the source checks them. Returns nil when a quest is available, else why not.
--------------------------------------------------------------------------------
local function PreGroupOK(list)
    if not list or #list == 0 then return true end
    for _, pre in ipairs(list) do
        if pre < 0 then
            if not Completed(-pre) then return false end
        elseif not Completed(pre) then
            local ex = Q(pre, "exclusiveTo")
            if not ex then return false end
            local any
            for _, e in ipairs(ex) do if Completed(e) then any = true end end
            if not any then return false end
        end
    end
    return true
end

function data.WhyNot(id)
    if Completed(id) then return "already done" end
    if Hidden(id) then return "on the blacklist" end
    local rec = data.Record("quests", id)
    if not rec then return "unknown quest" end

    local races = Q(id, "requiredRaces")
    if races and races ~= 0 and me.race and not Bit(races, me.race) then return "race" end
    local single = Q(id, "preQuestSingle")
    if single and #single > 0 then
        local any
        for _, p in ipairs(single) do if Completed(p) then any = true; break end end
        if not any then return "needs one of its earlier quests" end
    end
    local classes = Q(id, "requiredClasses")
    if classes and classes ~= 0 and me.class and not Bit(classes, me.class) then return "class" end

    local minRep, maxRep = Q(id, "requiredMinRep"), Q(id, "requiredMaxRep")
    if minRep and (me.rep[minRep[1]] or 0) < minRep[2] then return "reputation too low" end
    if maxRep and (me.rep[maxRep[1]] or 0) >= maxRep[2] then return "reputation too high" end

    local skill = Q(id, "requiredSkill")
    if skill then
        local rank = SkillRank(skill[1])
        if not rank or rank < skill[2] then return "profession" end
    end
    local ranks = Q(id, "requiredRanks")
    if ranks then
        local ok
        for _, r in ipairs(ranks) do
            if r[2] > 0 then local rank = SkillRank(r[1]); if rank and rank >= r[2] then ok = true end end
        end
        if not ok then return "profession rank" end
    end

    if not single or #single == 0 then
        if not PreGroupOK(Q(id, "preQuestGroup")) then return "needs all of its earlier quests" end
    end

    local parent = Q(id, "parentQuest")
    if parent and parent ~= 0 and not Active(parent) then return "parent quest not active" end
    local nextQ = Q(id, "nextQuestInChain")
    if nextQ and nextQ ~= 0 and (Completed(nextQ) or Active(nextQ)) then return "later quest in the chain already started" end
    for _, e in ipairs(Q(id, "exclusiveTo") or {}) do
        if Completed(e) or Active(e) then return "a quest it excludes is done or active" end
    end

    local spec = Q(id, "requiredSpecialization")
    if spec and spec > 0 then return "specialisation" end
    local spell = Q(id, "requiredSpell")
    if spell and spell ~= 0 then
        local known = IsSpellKnown and IsSpellKnown(math.abs(spell))
        if spell > 0 and not known then return "spell not known" end
        if spell < 0 and known then return "spell already known" end
    end

    local crumbFor = Q(id, "breadcrumbForQuestId")
    if crumbFor and crumbFor ~= 0 and (Completed(crumbFor) or Active(crumbFor)) then return "its quest is already started" end
    for _, b in ipairs(Q(id, "breadcrumbs") or {}) do
        if Active(b) then return "a breadcrumb is active" end
    end
    local disabled = Q(id, "disabledByQuest")
    if disabled and disabled ~= 0 and Active(disabled) then return "disabled by another quest" end
    local untilDone = Q(id, "availableUntilCompleted")
    if untilDone and untilDone ~= 0 and Completed(untilDone) then return "closed after another quest" end
    local from = Q(id, "availableStartingWith")
    if from and from ~= 0 and not Completed(from) and not Active(from) then return "opens after another quest" end

    -- level, the way the source shows quests: not trivial (below my green range), not above my level
    local qLevel, reqLevel, maxReq = Q(id, "questLevel") or 0, Q(id, "requiredLevel") or 0, Q(id, "requiredMaxLevel") or 0
    local level = me.level
    if qLevel == -1 then
        if reqLevel > level then qLevel = reqLevel else qLevel = level; reqLevel = level end
    end
    if reqLevel == 0 then reqLevel = qLevel end
    local parentActive = parent and parent ~= 0 and Active(parent)
    if not parentActive then
        local minLevel, maxLevel = level - me.green, level
        if maxLevel >= qLevel then
            if minLevel > qLevel then return "too low (grey)" end
        elseif maxLevel < reqLevel then
            return "level too high for me"
        end
        if maxLevel < reqLevel then return "level too high for me" end
        if maxReq ~= 0 and level > maxReq then return "I am above its level range" end
    end
    return nil
end

-- one quest, with my details read fresh (at most every couple of seconds)
local meAt = 0
function data.WhyNotNow(id)
    if GetTime() - meAt > 2 then Refresh(); meAt = GetTime() end
    return data.WhyNot(id)
end

--------------------------------------------------------------------------------
-- The whole list
--------------------------------------------------------------------------------
local cache, cacheAt, cacheKey = nil, 0, nil
function data.ComputeAvailable()
    local key = (UnitLevel and UnitLevel("player") or 0)
    if cache and cacheKey == key and GetTime() - cacheAt < 5 then return cache end
    Refresh(); meAt = GetTime()
    local out = {}
    for id in pairs(DS.quests) do
        -- a quest already in my log is not offered again
        if not Active(id) and not data.WhyNot(id) then out[id] = true end
    end
    cache, cacheAt, cacheKey = out, GetTime(), key
    return out
end

local inval = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "UPDATE_FACTION" }) do
    pcall(inval.RegisterEvent, inval, e)
end
inval:SetScript("OnEvent", function() cache = nil end)

--------------------------------------------------------------------------------
-- Against the source's own list
--------------------------------------------------------------------------------
function data.VerifyAvailable()
    local out = {}
    local ql = _G.QuestieLoader
    local ok, AQ = false, nil
    if ql then ok, AQ = pcall(ql.ImportModule, ql, "AvailableQuests") end
    local theirs = ok and AQ and AQ.__availableQuests
    if type(theirs) ~= "table" or not next(theirs) then
        out[1] = "available quests: the source has no list yet (wait a minute after login)"
        return out
    end
    cache = nil
    local mine = data.ComputeAvailable()
    local both, onlyMine, onlyTheirs, nTheirs, nMine = 0, {}, {}, 0, 0
    for id in pairs(theirs) do
        nTheirs = nTheirs + 1
        if mine[id] then both = both + 1 else onlyTheirs[#onlyTheirs + 1] = id end
    end
    for id in pairs(mine) do
        nMine = nMine + 1
        if not theirs[id] then onlyMine[#onlyMine + 1] = id end
    end
    table.sort(onlyTheirs); table.sort(onlyMine)
    out[#out + 1] = string.format("available quests: source %d, ours %d, in both %d, only theirs %d, only ours %d", nTheirs, nMine, both, #onlyTheirs, #onlyMine)
    for i = 1, math.min(6, #onlyTheirs) do
        local id = onlyTheirs[i]
        out[#out + 1] = string.format("   only the source: %d %s (lvl %s) - we say: %s", id, tostring(Q(id, "name")), tostring(Q(id, "questLevel")), tostring(data.WhyNot(id) or "available?"))
    end
    for i = 1, math.min(6, #onlyMine) do
        local id = onlyMine[i]
        out[#out + 1] = string.format("   only ours: %d %s (lvl %s, needs %s)", id, tostring(Q(id, "name")), tostring(Q(id, "questLevel")), tostring(Q(id, "requiredLevel")))
    end
    return out
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Availability.lua"] = true end end
