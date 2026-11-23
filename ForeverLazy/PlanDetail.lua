-- The line under the plan arrow (what to do at this stop) and the zone plan written out.
-- Split out of Extras.lua.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local hbd = api.hbd
local state = addon.state
local Print = addon.Print
local X = ns.extras          -- what Extras.lua shares with the files split out of it

local function DB() return addon.GetDB() end
local mine = X.mine
local MatchesOpen = X.MatchesOpen

--------------------------------------------------------------------------------
-- The line under the plan arrow: what to do at this stop
--------------------------------------------------------------------------------
local function PlainTitle(label)
    local t = label or "?"
    t = t:gsub("^Turn in: ", ""):gsub("^Pick up: ", ""):gsub("^Class quest: ", "")
    return t
end

local npcNames = {}
local function GiverName(id, field)
    local key = id .. field
    if npcNames[key] ~= nil then return npcNames[key] or nil end
    local name
    local QDB = api.GetQuestie()
    local by = QDB and QDB.QueryQuestSingle(id, field)
    if by and by[1] and by[1][1] then name = QDB.QueryNPCSingle(by[1][1], "name") end
    if not name and by and by[2] and by[2][1] then name = QDB.QueryObjectSingle(by[2][1], "name") end
    npcNames[key] = name or false
    return name
end

-- "Defias Pillager slain: 3/8" becomes "Kill 5 more Defias Pillager (3/8)"
local function ObjectiveLines(id, src)
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return out end
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
    if not ok or type(objs) ~= "table" then return out end
    -- only the objective this stop is for ("talk to X" at X's stop, not the one in another city)
    local mine
    if src then
        for _, o in ipairs(objs) do
            if not o.finished and o.text and MatchesOpen({ o.text:lower() }, src) then mine = true end
        end
    end
    for _, o in ipairs(objs) do
        if not o.finished and o.text and o.text ~= "" and (not mine or MatchesOpen({ o.text:lower() }, src)) then
            local have, need = o.numFulfilled, o.numRequired
            local name = o.text:match("^(.-):%s*%d+/%d+") or o.text
            local slain = name:find(" slain$") ~= nil
            name = name:gsub(" slain$", "")
            local multi = have and need and need > 1
            local line
            if slain then
                -- a real kill objective
                line = multi and string.format("Kill %d more %s (%d/%d)", need - have, name, have, need) or ("Kill " .. name)
            elseif o.type == "item" then
                line = multi and string.format("Collect %d more %s (%d/%d)", need - have, name, have, need) or ("Get " .. name)
            else
                -- talk to, explore, use, escort...: the quest's own wording says it best
                line = multi and string.format("%s (%d/%d)", name, have, need) or name
            end
            out[#out + 1] = line
        end
    end
    return out
end

local detailCache = setmetatable({}, { __mode = "k" })
function addon.WaypointDetail(wp)
    if not wp then return nil end
    local c = detailCache[wp]
    local now = GetTime()
    if c and now - c.t < 1 then return c.text end
    local text = wp.detail
    if wp.quests and #wp.quests > 0 then
        local parts = {}
        for i, q in ipairs(wp.quests) do
            if i > 2 then parts[#parts + 1] = string.format("+%d more", #wp.quests - 2); break end
            local title = PlainTitle(q.label)
            local lbl = q.label or ""
            if lbl:find("^Turn in:") then
                local npc = GiverName(q.id, "finishedBy")
                parts[#parts + 1] = "Turn in " .. title .. (npc and (" to " .. npc) or "")
            elseif lbl:find("^Pick up:") or lbl:find("^Class quest:") then
                local npc = GiverName(q.id, "startedBy")
                parts[#parts + 1] = "Pick up " .. title .. (npc and (" from " .. npc) or "")
            else
                local lines = ObjectiveLines(q.id, q.src)
                local part
                if #lines > 0 then
                    part = table.concat(lines, ", ", 1, math.min(#lines, 2))
                else
                    part = title
                end
                -- meant for a group: say so, and say when a green one can be done alone
                if q.grp and q.grp > 1 then
                    if q.tier == "green" and (GetNumGroupMembers and GetNumGroupMembers() or 0) < 2 then
                        part = part .. " [group quest, but green: you can likely solo it]"
                    else
                        part = part .. " [group quest]"
                    end
                end
                parts[#parts + 1] = part
            end
        end
        text = table.concat(parts, "; ")
    end
    detailCache[wp] = { t = now, text = text }
    return text
end

-- The zone plan written out: for each stop, what to pick up and from whom, what to kill or collect and where, and what to
-- hand in. The plan already keeps quests of an area open and hands them in together, so this reads top to bottom.
local zpWin, zpRows = nil, {}

function addon.ZonePlanLines(maxStops)
    local out = {}
    local db = DB()
    local n = 0
    for i, w in ipairs(db.waypoints or {}) do
        if w.label and not w.go and not w.gather and not w.guard then
            n = n + 1
            if n > (maxStops or 25) then break end
            local head = string.format("%d. %s", i, PlainTitle(w.label))
            if w.zx and w.zy then head = head .. string.format("   |cffaaaaaa(%.0f, %.0f)|r", w.zx * 100, w.zy * 100) end
            local lines = {}
            for _, q in ipairs(w.quests or {}) do
                local title = PlainTitle(q.label)
                local lbl = q.label or ""
                if lbl:find("^Turn in:") then
                    local npc = GiverName(q.id, "finishedBy")
                    lines[#lines + 1] = "|cffffd100?|r Hand in " .. title .. (npc and (" to " .. npc) or "")
                elseif lbl:find("^Pick up:") or lbl:find("^Class quest:") then
                    local npc = GiverName(q.id, "startedBy")
                    lines[#lines + 1] = "|cffffd100!|r Get " .. title .. (npc and (" from " .. npc) or "")
                else
                    local objs = ObjectiveLines(q.id, q.src)
                    if #objs > 0 then
                        for _, o in ipairs(objs) do lines[#lines + 1] = "- " .. title .. ": " .. o end
                    else
                        lines[#lines + 1] = "- " .. title
                    end
                end
            end
            if #lines == 0 then lines[1] = "- " .. PlainTitle(w.label) end
            out[#out + 1] = { head = head, lines = lines }
        end
    end
    return out
end

function addon.ZonePlanWindow()
    if not zpWin then
        local f = CreateFrame("Frame", "ForeverLazy_ZonePlan", UIParent)
        f:SetSize(540, 500)
        f:SetPoint("CENTER", 0, 20)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.sub:SetPoint("TOPLEFT", 16, -46); f.sub:SetWidth(500); f.sub:SetJustifyH("LEFT")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", "ForeverLazy_ZonePlanScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -84); scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        f.content = CreateFrame("Frame", nil, scroll)
        f.content:SetSize(480, 10)
        scroll:SetScrollChild(f.content)
        table.insert(UISpecialFrames, "ForeverLazy_ZonePlan")
        f:Hide()
        zpWin = f
    end
    local scale = math.min(2.6, math.max(0.8, tonumber(DB().guideScale) or 1))
    zpWin:SetScale(scale)
    local zone = GetRealZoneText and GetRealZoneText() or "this zone"
    zpWin.title:SetText("Level " .. zone)
    zpWin.sub:SetText("In order. Get the quests, do their objectives together, and the plan hands them in in one go, unless a hand-in opens the next quest of a chain. Stop 1 is where the arrow points now.")
    for _, r in ipairs(zpRows) do r.head:Hide(); r.body:Hide() end
    local steps = addon.ZonePlanLines(25)
    local y = 0
    for i, s in ipairs(steps) do
        local r = zpRows[i]
        if not r then
            r = {}
            r.head = zpWin.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.head:SetJustifyH("LEFT")
            r.body = zpWin.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.body:SetJustifyH("LEFT")
            zpRows[i] = r
        end
        r.head:ClearAllPoints(); r.head:SetPoint("TOPLEFT", zpWin.content, "TOPLEFT", 0, -y)
        r.head:SetWidth(470); r.head:SetText(s.head); r.head:Show()
        y = y + math.max(18, r.head:GetStringHeight()) + 2
        r.body:ClearAllPoints(); r.body:SetPoint("TOPLEFT", zpWin.content, "TOPLEFT", 10, -y)
        r.body:SetWidth(455); r.body:SetText(table.concat(s.lines, "\n")); r.body:Show()
        y = y + r.body:GetStringHeight() + 10
    end
    if #steps == 0 then
        local r = zpRows[1]
        if not r then
            r = { head = zpWin.content:CreateFontString(nil, "OVERLAY", "GameFontNormal"), body = zpWin.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight") }
            zpRows[1] = r
        end
        r.head:ClearAllPoints(); r.head:SetPoint("TOPLEFT", zpWin.content, "TOPLEFT", 0, 0); r.head:SetWidth(470)
        r.head:SetText("There is no plan yet. /lazy level makes one for this zone."); r.head:Show()
        y = 30
    end
    zpWin.content:SetHeight(math.max(y, 40))
    zpWin:Show()
end


-- shared with the step window and the plan menus
X.PlainTitle, X.GiverName, X.ObjectiveLines = PlainTitle, GiverName, ObjectiveLines

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["PlanDetail.lua"] = true end end
