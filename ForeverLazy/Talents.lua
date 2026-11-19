-- Talent and skill reminders. No build advice: it tells you when there is something to do and takes you to it.
--   a talent point to spend  -> a small box with a button that opens the talent window, a step at the top of the step window,
--                               and a line read aloud in couch mode
--   new skills at the trainer -> the same, with a button that sets the arrow on your trainer
--   /lazy talents            where my points are, and how many are left
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function DB() return addon.GetDB() end

--------------------------------------------------------------------------------
-- What the game says about my talents
--------------------------------------------------------------------------------
local function Unspent()
    if GetUnspentTalentPoints then
        local ok, n = pcall(GetUnspentTalentPoints)
        if ok and tonumber(n) then return tonumber(n) end
    end
    if UnitCharacterPoints then
        local ok, n = pcall(UnitCharacterPoints, "player")
        if ok and tonumber(n) then return tonumber(n) end
    end
    return 0
end
addon.TalentPointsUnspent = Unspent

-- { name, points } for each talent tree
local function Trees()
    local out = {}
    if GetNumTalentTabs and GetTalentTabInfo then
        for i = 1, (GetNumTalentTabs() or 0) do
            local ok, name, _, pts = pcall(GetTalentTabInfo, i)
            if ok and name then out[#out + 1] = { name = name, points = tonumber(pts) or 0 } end
        end
    end
    return out
end

local function OpenTalents()
    if ToggleTalentFrame then pcall(ToggleTalentFrame); return end
    if TalentFrame_LoadUI then pcall(TalentFrame_LoadUI) end
    if _G.PlayerTalentFrame and ShowUIPanel then pcall(ShowUIPanel, _G.PlayerTalentFrame) end
end

--------------------------------------------------------------------------------
-- The talents the levelling guide highlights, and which of them I still need
--------------------------------------------------------------------------------
-- every talent of mine by name: { tab, index, tier, rank, max, available }
local function MyTalents()
    local map = {}
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return map end
    for tab = 1, (GetNumTalentTabs() or 0) do
        local _, _, spent = GetTalentTabInfo(tab)
        for i = 1, (GetNumTalents(tab) or 0) do
            local ok, name, _, tier, _, rank, max, _, available = pcall(GetTalentInfo, tab, i)
            if ok and name then
                map[name] = { tab = tab, index = i, tier = tonumber(tier) or 1, rank = tonumber(rank) or 0, max = tonumber(max) or 1,
                              available = available, spent = tonumber(spent) or 0 }
            end
        end
    end
    return map
end

-- which of the guide's lists fits where my points are, and what is still to take from it (next ones first)
local function GuideFor()
    local G = addon.TalentGuide
    local class = select(2, UnitClass("player"))
    local data = G and class and G[class]
    if not data then return nil end
    local mine = MyTalents()
    local trees = Trees()
    local leadTab, leadPts = nil, 0
    for i, t in ipairs(trees) do if t.points > leadPts then leadTab, leadPts = i, t.points end end
    local best, bestScore
    for _, block in ipairs(data.blocks) do
        local score = 0
        for _, name in ipairs(block) do
            local m = mine[name]
            if m and (not leadTab or m.tab == leadTab) then score = score + 1 end
        end
        if not bestScore or score > bestScore then best, bestScore = block, score end
    end
    if not best then return nil end
    local todo, have = {}, {}
    for _, name in ipairs(best) do
        local m = mine[name]
        if m then
            if m.rank >= m.max then have[#have + 1] = name
            else
                -- can I take it now? (the game says so; or: enough points in its tree for its row)
                local can = m.available
                if can == nil then can = (m.spent >= (m.tier - 1) * 5) end
                todo[#todo + 1] = { name = name, tab = m.tab, tier = m.tier, can = can and true or false, rank = m.rank, max = m.max }
            end
        end
    end
    table.sort(todo, function(a, b)
        if a.can ~= b.can then return a.can end
        return a.tier < b.tier
    end)
    return { url = data.url, source = G.source, todo = todo, have = have, trees = trees, block = best }
end

-- one line for the reminder box
local function GuideHint()
    local g = GuideFor()
    if not g or #g.todo == 0 then return nil end
    local names = {}
    for _, t in ipairs(g.todo) do
        if t.can then
            names[#names + 1] = t.name .. (g.trees[t.tab] and (" (" .. g.trees[t.tab].name .. ")") or "")
            if #names >= 3 then break end
        end
    end
    if #names == 0 then return nil end
    return "The levelling guide highlights: " .. table.concat(names, ", ")
end

-- a small window with the guide's address, ready to copy
local linkWin
local function ShowLink(url, source)
    if not linkWin then
        local f = CreateFrame("Frame", "ForeverLazy_TalentLink", UIParent)
        f:SetSize(480, 90)
        f:SetPoint("CENTER", 0, 100)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.text:SetPoint("TOP", 0, -10)
        f.box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.box:SetSize(440, 24); f.box:SetPoint("TOP", 0, -34); f.box:SetAutoFocus(true)
        f.box:SetScript("OnEscapePressed", function() f:Hide() end)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
        table.insert(UISpecialFrames, "ForeverLazy_TalentLink")
        f:Hide()
        linkWin = f
    end
    linkWin.text:SetText((source or "Levelling guide") .. ": Ctrl+C to copy, then paste it in a browser")
    linkWin.box:SetText(url or "")
    linkWin:Show()
    linkWin.box:SetFocus(); linkWin.box:HighlightText()
end

--------------------------------------------------------------------------------
-- The reminder box
--------------------------------------------------------------------------------
local toast
local function Toast(title, body, buttonText, onClick)
    if not toast then
        local f = CreateFrame("Frame", "ForeverLazy_TalentToast", UIParent)
        f:SetSize(400, 110)
        f:SetPoint("TOP", 0, -200)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -12); f.title:SetWidth(376)
        f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.body:SetPoint("TOP", f.title, "BOTTOM", 0, -6); f.body:SetWidth(376)
        f.go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.go:SetSize(150, 22); f.go:SetPoint("BOTTOMLEFT", 20, 10)
        f.later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.later:SetSize(90, 22); f.later:SetPoint("LEFT", f.go, "RIGHT", 8, 0); f.later:SetText("Later")
        f.later:SetScript("OnClick", function() f:Hide() end)
        f.guide = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.guide:SetSize(100, 22); f.guide:SetPoint("LEFT", f.later, "RIGHT", 8, 0); f.guide:SetText("Guide link")
        f.guide:SetScript("OnClick", function()
            local g = GuideFor()
            if g then ShowLink(g.url, g.source) else Print("no levelling guide for your class yet") end
        end)
        f:Hide()
        toast = f
    end
    toast.title:SetText(title)
    toast.body:SetText(body)
    toast.go:SetText(buttonText)
    toast.go:SetScript("OnClick", function() toast:Hide(); if onClick then pcall(onClick) end end)
    toast:SetHeight(math.max(96, 70 + toast.body:GetStringHeight()))
    toast:Show()
    if C_Timer then C_Timer.After(40, function() if toast:IsShown() and toast.title:GetText() == title then toast:Hide() end end) end
end

local told = { points = 0, trainerLevel = 0 }

local function CheckPoints(force)
    local db = DB()
    if not db or db.talentReminder == false then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local n = Unspent()
    if n > 0 and (force or n ~= told.points) then
        told.points = n
        local trees = Trees()
        local lead
        for _, t in ipairs(trees) do if not lead or t.points > lead.points then lead = t end end
        local body = string.format("You have %d talent point%s to spend.", n, n == 1 and "" or "s")
        if lead and lead.points > 0 then body = body .. string.format("\nYour points so far are mostly in %s (%d).", lead.name, lead.points) end
        local hint = GuideHint()
        if hint then body = body .. "\n" .. hint end
        Toast("Talent point", body, "Open talents", OpenTalents)
        if db.couchSpeak and addon.CouchSpeak then addon.CouchSpeak(string.format("You have %d talent point%s to spend.", n, n == 1 and "" or "s")) end
        if addon.PlanLog then addon.PlanLog("talents", "reminded: " .. n .. " point(s) to spend") end
    elseif n == 0 then
        told.points = 0
    end
end

local function CheckTrainer()
    local db = DB()
    if not db or db.talentReminder == false then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local lvl = UnitLevel("player") or 1
    if lvl == told.trainerLevel then return end
    if addon.LazyTrainerDue and addon.LazyTrainerDue() then
        told.trainerLevel = lvl
        Toast("New skills", "Your class trainer has new skills for you at level " .. lvl .. ".", "Show me the trainer", function()
            local r = api.FindService and api.FindService("classtrainer")
            if r then addon:AddWaypointZone(r.spawn.uiMapId, r.spawn.zx, r.spawn.zy, "Trainer: " .. tostring(r.name or "class trainer"))
            else Print("I could not find your class trainer on this continent (needs Questie)") end
        end)
        if db.couchSpeak and addon.CouchSpeak then addon.CouchSpeak("Your class trainer has new skills for you.") end
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if not C_Timer then return end
    if event == "PLAYER_LEVEL_UP" then
        told.trainerLevel = 0
        C_Timer.After(3, function() pcall(CheckPoints); pcall(CheckTrainer) end)
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(15, function() pcall(CheckPoints) end)
    else
        C_Timer.After(2, function() pcall(CheckPoints) end)
    end
end)

--------------------------------------------------------------------------------
-- /lazy talents
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "talents" or (cmd or ""):lower() == "talent" then
        local n = Unspent()
        Print(string.format("talent points to spend: %d", n))
        for _, t in ipairs(Trees()) do Print(string.format("  %s: %d point%s", t.name, t.points, t.points == 1 and "" or "s")) end
        local g = GuideFor()
        if g then
            Print("the levelling guide highlights these for your points (" .. tostring(g.source) .. "):")
            for _, t in ipairs(g.todo) do
                Print(string.format("  to take: %s (%s)%s", t.name, g.trees[t.tab] and g.trees[t.tab].name or "?", t.can and "" or " - not open yet"))
            end
            for _, name in ipairs(g.have) do Print("  taken: " .. name) end
            if (rest or ""):lower():find("guide") then ShowLink(g.url, g.source) end
        end
        if n > 0 then CheckPoints(true) elseif not g then OpenTalents() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Talents.lua"] = true end end
