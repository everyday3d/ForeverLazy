-- Quest icons on nameplates, like Questie: a small sword next to a mob one of my quests needs killed, a small loot bag next to a
-- mob that drops an item one of my quests needs.
--   /lazy plates on|off     the icons
local ADDON, ns = ...
local addon = ns.addon
local data = ns.data
local Print = addon.Print

local SWORD = "Interface\\Icons\\INV_Sword_04"
local BAG = "Interface\\Icons\\INV_Misc_Bag_08"

local function DB() return addon.GetDB() end
local function On()
    local db = DB()
    return db and db.questPlates ~= false and addon.ModuleOn("quests")
end

-- npc id -> "kill" or "loot" for what my open quests need right now (rebuilt when the quest log changes)
local needs, dirty = {}, true

local function Rebuild()
    dirty = false
    needs = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives) then return end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local okO, objs = pcall(C_QuestLog.GetQuestObjectives, info.questID)
            local openKill, openItem = false, false
            if okO and type(objs) == "table" then
                for _, o in ipairs(objs) do
                    if not o.finished then
                        if o.type == "monster" then openKill = true
                        elseif o.type == "item" then openItem = true end
                    end
                end
            end
            local obj = (openKill or openItem) and data.Field("quests", info.questID, "objectives")
            if type(obj) == "table" then
                if openKill then
                    for _, g in ipairs({ 1, 5 }) do
                        for _, e in ipairs(obj[g] or {}) do
                            local ref = e[1]
                            if type(ref) == "table" then
                                for _, r in ipairs(ref) do needs[r] = needs[r] or "kill" end
                            elseif ref then
                                needs[ref] = needs[ref] or "kill"
                            end
                        end
                    end
                end
                if openItem then
                    for _, e in ipairs(obj[3] or {}) do
                        local d = e[1] and data.Field("items", e[1], "npcDrops")
                        if type(d) == "table" then
                            for _, n in pairs(d) do if type(n) == "number" then needs[n] = needs[n] or "loot" end end
                        end
                    end
                end
            end
        end
    end
end

-- mobs that drop an item which STARTS a quest: npc id -> list of quest ids (worked out from the quest data, a little at a time)
local starters = {}
do
    local DS = ns.dataset
    local ids, pos, itemQuest = nil, 0, {}
    local fi = {}
    local f = CreateFrame("Frame")
    local acc = 0
    f:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 5 then return end
        -- wait until the quest index has been built, so the game does not do both at once
        if not ids then
            if addon.QuestIndex then
                local _, done = addon.QuestIndex()
                if not done then acc = 0; return end
            end
            if not (DS and DS.quests) then self:SetScript("OnUpdate", nil); return end
            for i, name in ipairs((DS.fields and DS.fields.quests) or {}) do fi[name] = i end
            ids = {}
            for id in pairs(DS.quests) do ids[#ids + 1] = id end
        end
        local loader = loadstring or load
        local stop = math.min(#ids, pos + 200)
        while pos < stop do
            pos = pos + 1
            local id = ids[pos]
            local text = DS.quests[id]
            -- cheap test first: only quests that name a starting item are worth parsing
            local fn = text and loader("return " .. text)
            local ok, r = false, nil
            if fn then ok, r = pcall(fn) end
            local by = ok and type(r) == "table" and fi.startedBy and r[fi.startedBy]
            if type(by) == "table" and type(by[3]) == "table" then
                for _, item in pairs(by[3]) do
                    if type(item) == "number" then
                        local l = itemQuest[item]
                        if not l then l = {}; itemQuest[item] = l end
                        l[#l + 1] = id
                    end
                end
            end
        end
        if pos >= #ids then
            self:SetScript("OnUpdate", nil)
            for item, quests in pairs(itemQuest) do
                local d = data.Field("items", item, "npcDrops")
                if type(d) == "table" then
                    for _, n in pairs(d) do
                        if type(n) == "number" then
                            local l = starters[n]
                            if not l then l = {}; starters[n] = l end
                            for _, q in ipairs(quests) do l[#l + 1] = q end
                        end
                    end
                end
            end
            ids = nil
            dirty = true
        end
    end)
end

-- does this mob drop something that starts a quest I can take right now?
local function StartsQuest(npcId)
    local list = starters[npcId]
    if not list then return false end
    for _, q in ipairs(list) do
        if not (addon.QuestCompleted and addon.QuestCompleted(q)) and not (addon.QuestInLog and addon.QuestInLog(q))
           and not (data.WhyNot and data.WhyNot(q)) then
            return true
        end
    end
    return false
end

local function NpcId(guid)
    if type(guid) ~= "string" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

local icons = {}   -- nameplate frame -> icon frame

local function IconFor(plate)
    local f = icons[plate]
    if f then return f end
    f = CreateFrame("Frame", nil, plate)
    f:SetSize(20, 20)
    f:SetFrameStrata("HIGH")
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetPoint("TOPLEFT", -1, 1)
    f.ring:SetPoint("BOTTOMRIGHT", 1, -1)
    f.ring:SetColorTexture(1, 0.82, 0, 1)
    f.ring:SetDrawLayer("BACKGROUND")
    f.tex:SetDrawLayer("ARTWORK")
    f.mark = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.mark:SetPoint("CENTER", f, "TOPRIGHT", -1, -1)
    f.mark:SetText("!")
    f.mark:SetTextColor(1, 0.82, 0)
    f.mark:Hide()
    f:SetPoint("RIGHT", plate, "LEFT", 4, 0)
    f:Hide()
    icons[plate] = f
    return f
end

local function Update(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local f = icons[plate]
    if not On() then if f then f:Hide() end return end
    if dirty then Rebuild() end
    local kind
    local okU, guid = pcall(UnitGUID, unit)
    local id = okU and NpcId(guid)
    local dead = false
    local okD, d = pcall(UnitIsDead, unit)
    if okD and not (issecretvalue and issecretvalue(d)) and d then dead = true end
    if id and not dead and UnitCanAttack("player", unit) then
        kind = needs[id]
        if not kind and StartsQuest(id) then kind = "start" end
    end
    if not kind then if f then f:Hide() end return end
    f = f or IconFor(plate)
    f.tex:SetTexture(kind == "kill" and SWORD or BAG)
    f.mark:SetShown(kind == "start")
    f:Show()
end

local function UpdateAll()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then pcall(Update, unit) end
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local pending
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        pcall(Update, unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate and icons[plate] then icons[plate]:Hide() end
    else
        dirty = true
        if not pending and C_Timer and C_Timer.After then
            pending = true
            C_Timer.After(0.5, function() pending = false; UpdateAll() end)
        end
    end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "plates" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local db = DB()
        if a == "off" then db.questPlates = false elseif a == "on" then db.questPlates = nil end
        Print("quest icons on nameplates: " .. (db.questPlates == false and "OFF" or "on") .. "  (/lazy plates on|off)")
        UpdateAll()
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestPlates.lua"] = true end end
