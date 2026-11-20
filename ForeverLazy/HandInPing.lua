-- Hand-in ping: walk up to the person who takes a finished quest and a message flashes, a sound plays and the minimap pings
-- where you stand, once for each visit.
--   /lazy ping on|off
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local data = ns.data
local Print = addon.Print

local function DB() return addon.GetDB() end
local NEAR, FAR = 45, 130           -- yards: ping inside NEAR, ready again after I have been farther than FAR

local spots = {}                     -- quest id -> spawns where it is handed in
local pinged = {}                    -- quest id -> true while I stay near

local function Spots(id)
    local s = spots[id]
    if s then return s end
    s = {}
    local by = data.Field("quests", id, "finishedBy")
    if type(by) == "table" then
        if api.AddNpcs then pcall(api.AddNpcs, s, by[1]) end
        if api.AddObjects then pcall(api.AddObjects, s, by[2]) end
    end
    spots[id] = s
    return s
end

local function Ping(id, title, who)
    local msg = "Hand in: " .. tostring(title) .. (who and (" to " .. who) or "")
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 0.3, 1, 0.3, 1, 4) end
    pcall(PlaySound, (_G.SOUNDKIT and _G.SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) or 878, "Master")
    if Minimap and Minimap.PingLocation then pcall(Minimap.PingLocation, Minimap, 0, 0) end
end

local acc = 0
local ev = CreateFrame("Frame")
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1.2 then return end
    acc = 0
    local db = DB()
    if not db or db.handInPing == false then return end
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and api.hbd) then return end
    local px, py, pinst = api.hbd:GetPlayerWorldPosition()
    if not px then return end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and info.questID then
            local id = info.questID
            local okC, complete = pcall(C_QuestLog.IsComplete, id)
            if okC and complete then
                local nearest
                for _, s in ipairs(Spots(id)) do
                    if s.instance == pinst then
                        local d = math.sqrt(api.D2(s.x, s.y, px, py))
                        if not nearest or d < nearest then nearest = d end
                    end
                end
                if nearest then
                    if nearest <= NEAR and not pinged[id] then
                        pinged[id] = true
                        local by = data.Field("quests", id, "finishedBy")
                        local who = addon.QuestWho and addon.QuestWho(by)
                        if who then who = who:gsub("%s*|c%x%x%x%x%x%x%x%x.-|r", "") end
                        Ping(id, info.title, who)
                    elseif nearest > FAR then
                        pinged[id] = nil
                    end
                end
            else
                pinged[id] = nil
            end
        end
    end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "ping" then
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local db = DB()
        if a == "off" then db.handInPing = false elseif a == "on" then db.handInPing = nil end
        Print("hand-in ping: " .. (db.handInPing == false and "OFF" or "on") .. "  (/lazy ping on|off)")
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["HandInPing.lua"] = true end end
