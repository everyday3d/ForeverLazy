-- Quest information: what a quest is (who gives it, who takes it, level, chain, why I cannot take it), shown when I hover a quest
-- link in chat, plus a list of every quest (a name index) for the quest search and the quest history windows.
--   addon.QuestInfoLines(id)  lines for a tooltip      addon.QuestChain(id)  the chain of quests this one is in
--   addon.QuestIndex()        the list of all quests   (built a little at a time, so the game never stutters)
--   /lazy links on|off        quest link tooltips
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local data = ns.data
local DS = ns.dataset
local Print = addon.Print

local function DB() return addon.GetDB() end
local function Q(id, field) return data.Field("quests", id, field) end

local function Completed(id)
    return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
end
local function InLog(id)
    if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return false end
    local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    return ok and i and i > 0 and true or false
end
addon.QuestCompleted, addon.QuestInLog = Completed, InLog

--------------------------------------------------------------------------------
-- Places and names
--------------------------------------------------------------------------------
-- "Goldshire, Elwynn Forest" (or just the zone) for an area id
function addon.AreaLabel(areaId)
    if not areaId then return nil end
    local zone
    local zm = data.Module and data.Module("ZoneDB")
    local uiMapId = zm and zm.GetUiMapIdByAreaId and zm:GetUiMapIdByAreaId(areaId)
    local info = uiMapId and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapId)
    zone = info and info.name
    local sub = addon.AreaName and addon.AreaName(areaId, uiMapId)
    if sub and zone then return sub .. ", " .. zone end
    return sub or zone
end

-- the first place a thing from a "started by" / "finished by" record can be found: "Name (Area)"
local function Who(by)
    if type(by) ~= "table" then return nil end
    local function from(kind, list)
        if type(list) ~= "table" then return nil end
        local id = list[1]
        if not id then return nil end
        local name = data.Field(kind, id, "name")
        if not name then return nil end
        local spawns = data.Field(kind, id, "spawns")
        local where
        if type(spawns) == "table" then
            local areaId = next(spawns)
            where = addon.AreaLabel(areaId)
        end
        return name .. (where and (" |cff888888(" .. where .. ")|r") or ""), kind
    end
    local s = from("npcs", by[1]) or from("objects", by[2])
    if s then return s end
    if type(by[3]) == "table" and by[3][1] then
        local name = data.Field("items", by[3][1], "name")
        if name then return "the item " .. name end
    end
    return nil
end
addon.QuestWho = Who

local function QuestName(id) return Q(id, "name") or ("quest " .. tostring(id)) end

--------------------------------------------------------------------------------
-- The chain a quest belongs to
--------------------------------------------------------------------------------
function addon.QuestChain(id)
    local back, cur = {}, id
    for _ = 1, 25 do
        local single = Q(cur, "preQuestSingle")
        local prev = type(single) == "table" and #single == 1 and single[1] or nil
        if not prev then
            local group = Q(cur, "preQuestGroup")
            if type(group) == "table" and #group == 1 then prev = group[1] end
        end
        prev = tonumber(prev)
        if not prev or prev <= 0 or prev == cur or Q(prev, "name") == nil then break end
        table.insert(back, 1, prev)
        cur = prev
    end
    local list = {}
    for _, v in ipairs(back) do list[#list + 1] = v end
    list[#list + 1] = id
    cur = id
    for _ = 1, 25 do
        local n = tonumber(Q(cur, "nextQuestInChain"))
        if not n or n <= 0 or n == cur or Q(n, "name") == nil then break end
        list[#list + 1] = n
        cur = n
    end
    if #list == 1 then return nil end
    return list, #back + 1
end

local function StatusText(id)
    if Completed(id) then return "|cff888888Done|r" end
    if InLog(id) then
        local ok, done = pcall(C_QuestLog.IsComplete, id)
        if ok and done then return "|cff55ff55In your log, ready to hand in|r" end
        return "|cffffd100In your log|r"
    end
    local why = data.WhyNot and data.WhyNot(id)
    if not why then return "|cff55ff55You can take it|r" end
    return "|cffff6060Not yet: " .. tostring(why) .. "|r"
end
addon.QuestStatusText = StatusText

-- the lines a quest tooltip shows (no name line: the caller has one)
function addon.QuestInfoLines(id)
    local lines = {}
    local level, req = tonumber(Q(id, "questLevel")), tonumber(Q(id, "requiredLevel"))
    local bit = level and level > 0 and ("Level " .. level) or nil
    if req and req > 0 and req ~= level then bit = (bit or "Quest") .. ", needs level " .. req end
    if bit then lines[#lines + 1] = "|cffffffff" .. bit .. "|r" end
    lines[#lines + 1] = StatusText(id)
    local starts, ends = Who(Q(id, "startedBy")), Who(Q(id, "finishedBy"))
    if starts then lines[#lines + 1] = "|cffffd100Starts:|r " .. starts end
    if ends then lines[#lines + 1] = "|cffffd100Ends:|r " .. ends end
    local zone = tonumber(Q(id, "zoneOrSort"))
    if zone and zone > 0 then
        local z = addon.AreaLabel(zone) or (C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(zone))
        if z then lines[#lines + 1] = "|cffffd100Zone:|r " .. z end
    end
    local chain, pos = addon.QuestChain(id)
    if chain then
        lines[#lines + 1] = string.format("|cff7fd0ffChain:|r step %d of %d", pos, #chain)
        if chain[pos - 1] then lines[#lines + 1] = "   before: " .. QuestName(chain[pos - 1]) .. (Completed(chain[pos - 1]) and " |cff888888(done)|r" or "") end
        if chain[pos + 1] then lines[#lines + 1] = "   next: " .. QuestName(chain[pos + 1]) end
        if not chain[pos + 1] then lines[#lines + 1] = "   |cff888888this is the last one|r" end
    end
    return lines
end

--------------------------------------------------------------------------------
-- Quest links in chat: hover for the details
--------------------------------------------------------------------------------
local function Wants()
    local db = DB()
    return db and db.questLinkTooltips ~= false
end

local function AddInfo(tt, link)
    if not Wants() or not tt or type(link) ~= "string" then return end
    local id = tonumber(link:match("quest:(%d+)"))
    if not id or tt.flqLinkShown == link then return end
    tt.flqLinkShown = link
    local ok, lines = pcall(addon.QuestInfoLines, id)
    if not (ok and type(lines) == "table") then return end
    tt:AddLine(" ")
    for _, l in ipairs(lines) do tt:AddLine(l, 1, 1, 1) end
    tt:AddLine(L("Forever Lazy"), 0.5, 0.5, 0.5)
    tt:Show()
end

for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and hooksecurefunc then
        pcall(hooksecurefunc, tt, "SetHyperlink", function(self, link) AddInfo(self, link) end)
        pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) self.flqLinkShown = nil end)
        pcall(tt.HookScript, tt, "OnHide", function(self) self.flqLinkShown = nil end)
    end
end

--------------------------------------------------------------------------------
-- The list of every quest: id, name, level, zone, and whether my race and class may take it
--------------------------------------------------------------------------------
local index, indexIds, indexPos, building
local me = {}

local function Mask(mask, n)
    if not mask or mask == 0 or not n then return true end
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

local function StartIndex()
    if building or index then return end
    me.race = select(3, UnitRace("player"))
    me.class = select(3, UnitClass("player"))
    index, indexIds, indexPos, building = {}, {}, 0, true
    for id in pairs(DS.quests or {}) do indexIds[#indexIds + 1] = id end
    table.sort(indexIds)
    local fi = {}
    for i, name in ipairs((DS.fields and DS.fields.quests) or {}) do fi[name] = i end
    local loader = loadstring or load
    local hidden = DS.hidden
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        local stop = math.min(#indexIds, indexPos + 250)
        while indexPos < stop do
            indexPos = indexPos + 1
            local id = indexIds[indexPos]
            local text = DS.quests[id]
            local fn = text and loader("return " .. text)
            local ok, r = false, nil
            if fn then ok, r = pcall(fn) end
            if ok and type(r) == "table" and r[fi.name] and not (type(hidden) == "table" and hidden[id] == true) then
                local races, classes = r[fi.requiredRaces], r[fi.requiredClasses]
                index[#index + 1] = {
                    id = id, name = r[fi.name], lname = tostring(r[fi.name]):lower(), level = r[fi.questLevel] or 0,
                    zone = r[fi.zoneOrSort] or 0,
                    mine = Mask(tonumber(races), me.race) and Mask(tonumber(classes), me.class),
                }
            end
        end
        if indexPos >= #indexIds then building = false; self:SetScript("OnUpdate", nil); indexIds = nil end
    end)
end

-- the index so far, whether it is finished, and how far along it is (0-1)
function addon.QuestIndex()
    StartIndex()
    local total = indexIds and #indexIds or 1
    return index or {}, not building, building and (indexPos / math.max(1, total)) or 1
end

--------------------------------------------------------------------------------
-- /lazy links
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "links" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local db = DB()
        if a == "off" then db.questLinkTooltips = false elseif a == "on" then db.questLinkTooltips = nil end
        Print(L("quest link tooltips: ") .. (db.questLinkTooltips == false and "OFF" or "on") .. L("  (/lazy links on|off)"))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["QuestInfo.lua"] = true end end
