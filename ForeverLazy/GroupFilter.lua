-- Group finder filter: a window that lists the groups the group finder found, with filters the game's own list does not have.
--   open it with the "Filter groups" button on the group finder, or /lazy groups
--   Search in the group finder first (Browse tab); this window then filters and sorts what it found.
--   Filters: words (activity, leader, comment), groups or lone players, a role the group still needs, how new the listing is,
--   and "right level for me". Click a row to whisper the leader.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function Filt()
    local d = DB()
    if not d then return {} end
    d.lfgFilter = d.lfgFilter or {}
    return d.lfgFilter
end

--------------------------------------------------------------------------------
-- The rules (no game needed: tests/groupfilter.lua)
--------------------------------------------------------------------------------
-- r: { age (seconds), numMembers, leader, comment, name, activity, minLevel, maxSuggest, roleOpen = { TANK=n, HEALER=n, DAMAGER=n } }
-- f: { text, kind = "groups"|"players", role = "TANK"|"HEALER"|"DAMAGER", maxAge (minutes), fitLevel }
function addon.GroupMatches(r, f, myLevel)
    f = f or {}
    local n = r.numMembers or 1
    if f.kind == "groups" and n < 2 then return false end
    if f.kind == "players" and n >= 2 then return false end
    if (f.maxAge or 0) > 0 and (r.age or 0) > f.maxAge * 60 then return false end
    if f.fitLevel and myLevel then
        if (r.minLevel or 0) > 0 and myLevel < r.minLevel then return false end
        if (r.maxSuggest or 0) > 0 and myLevel > r.maxSuggest + 3 then return false end
    end
    if f.role and n >= 2 and type(r.roleOpen) == "table" then
        local open = r.roleOpen[f.role]
        if open ~= nil and open <= 0 then return false end
    end
    -- a lone player: the role they play (when the listing says which; a listing with no role is left in)
    if f.role and n < 2 and r.role and r.role ~= "" and r.role ~= "NONE" and r.role ~= f.role then return false end
    if f.class and n < 2 and r.class and r.class ~= "" and r.class ~= f.class then return false end
    local words = (f.text or ""):lower()
    if words ~= "" then
        local hay = ((r.activity or "") .. " " .. (r.leader or "") .. " " .. (r.comment or "") .. " " .. (r.name or "")):lower()
        for w in words:gmatch("%S+") do
            if not hay:find(w, 1, true) then return false end
        end
    end
    return true
end

function addon.GroupSort(list, mode)
    if mode == "size" then
        table.sort(list, function(a, b) if (a.numMembers or 1) ~= (b.numMembers or 1) then return (a.numMembers or 1) > (b.numMembers or 1) end return (a.age or 0) < (b.age or 0) end)
    elseif mode == "name" then
        table.sort(list, function(a, b) if (a.activity or "") ~= (b.activity or "") then return (a.activity or "") < (b.activity or "") end return (a.age or 0) < (b.age or 0) end)
    else
        table.sort(list, function(a, b) return (a.age or 0) < (b.age or 0) end)
    end
    return list
end

local function Ago(s)
    s = s or 0
    if s < 60 then return s .. "s" end
    if s < 3600 then return math.floor(s / 60) .. "m" end
    return math.floor(s / 3600) .. "h"
end
addon.GroupAgo = Ago

--------------------------------------------------------------------------------
-- Reading what the group finder found
--------------------------------------------------------------------------------
-- which roles a started group still needs: the game's own "remaining" numbers when it gives them, otherwise worked out for a
-- five-player dungeon (1 tank, 1 healer, the rest damage) from the roles already in it. Nil when it can not be told.
function addon.GroupRolesOpen(counts, maxPlayers)
    if type(counts) ~= "table" then return nil end
    if counts.TANK_REMAINING ~= nil then
        return { TANK = counts.TANK_REMAINING, HEALER = counts.HEALER_REMAINING, DAMAGER = counts.DAMAGER_REMAINING }
    end
    if not maxPlayers or maxPlayers < 2 or maxPlayers > 5 then return nil end
    local need = { TANK = 1, HEALER = 1, DAMAGER = maxPlayers - 2 }
    local open = {}
    for role, n in pairs(need) do open[role] = math.max(0, n - (counts[role] or 0)) end
    return open
end

-- "tank, healer" for a group that is missing those
function addon.GroupNeeds(roleOpen)
    if type(roleOpen) ~= "table" then return nil end
    local out = {}
    if (roleOpen.TANK or 0) > 0 then out[#out + 1] = "tank" end
    if (roleOpen.HEALER or 0) > 0 then out[#out + 1] = "healer" end
    if (roleOpen.DAMAGER or 0) > 0 then out[#out + 1] = (roleOpen.DAMAGER > 1) and (roleOpen.DAMAGER .. " dps") or "dps" end
    return #out > 0 and table.concat(out, ", ") or nil
end

-- the role and class of a lone player's listing: "TANK"/"HEALER"/"DAMAGER" and a class file name such as "MAGE" (nil when not told).
-- The game gives this either as a table or as several values, and some clients put it on the listing itself.
function addon.GroupPlayerRole(id, info)
    local role, class
    if C_LFGList and C_LFGList.GetSearchResultPlayerInfo then
        local ok, a, b = pcall(C_LFGList.GetSearchResultPlayerInfo, id, 1)
        if ok then
            if type(a) == "table" then
                role = a.assignedRole or a.role
                class = a.classFilename or a.classFileName or a.class
            else
                role, class = a, b
            end
        end
    end
    if type(info) == "table" then
        role = role or info.assignedRole or info.role
        class = class or info.classFilename or info.classFileName
        if not role and type(info.roles) == "table" then
            role = (info.roles.tank and "TANK") or (info.roles.healer and "HEALER") or (info.roles.dps and "DAMAGER") or (info.roles.damage and "DAMAGER") or nil
        end
    end
    if type(role) ~= "string" then role = nil end
    if type(class) ~= "string" then class = nil end
    if role == "DPS" or role == "DAMAGE" then role = "DAMAGER" end
    return role, class and class:upper() or nil
end

local actCache = {}
local function Activity(aid)
    if not aid then return "?", 0, 0, nil end
    local c = actCache[aid]
    if c then return c[1], c[2], c[3], c[4] end
    local name, minL, maxS, maxP = nil, 0, 0, nil
    if C_LFGList and C_LFGList.GetActivityInfoTable then
        local ok, a = pcall(C_LFGList.GetActivityInfoTable, aid)
        if ok and type(a) == "table" then
            name = a.fullName or a.shortName
            minL = a.minLevel or a.minLevelSuggestion or 0
            maxS = a.maxLevelSuggestion or 0
            maxP = a.maxNumPlayers
        end
    end
    if not name and C_LFGList and C_LFGList.GetActivityFullName then
        local ok, n = pcall(C_LFGList.GetActivityFullName, aid)
        if ok then name = n end
    end
    name = name or "?"
    actCache[aid] = { name, minL, maxS, maxP }
    return name, minL, maxS, maxP
end

local function ReadResults()
    local out = {}
    if not (C_LFGList and C_LFGList.GetSearchResults) then return out end
    local ok, a, b = pcall(C_LFGList.GetSearchResults)
    if not ok then return out end
    local results = type(b) == "table" and b or (type(a) == "table" and a) or nil
    if not results then return out end
    for _, e in ipairs(results) do
        local info = e
        if type(e) ~= "table" then
            local ok2, i = pcall(C_LFGList.GetSearchResultInfo, e)
            info = ok2 and i or nil
        end
        if type(info) == "table" and not info.isDelisted then
            local id = info.searchResultID or e
            local aid = (type(info.activityIDs) == "table" and info.activityIDs[1]) or info.activityID
            local act, minL, maxS, maxP = Activity(aid)
            local r = {
                id = id, age = info.age or 0, numMembers = info.numMembers or 1, leader = info.leaderName or "?",
                comment = info.comment or "", name = info.name or "", activity = act, minLevel = minL, maxSuggest = maxS,
                itemLevel = info.requiredItemLevel or 0, voice = info.voiceChat or "",
            }
            if (r.numMembers or 1) < 2 then
                r.role, r.class = addon.GroupPlayerRole(id, info)
            end
            if C_LFGList.GetSearchResultMemberCounts and (r.numMembers or 1) >= 2 then
                local ok3, counts = pcall(C_LFGList.GetSearchResultMemberCounts, id)
                if ok3 and type(counts) == "table" then
                    r.counts = counts
                    r.roleOpen = addon.GroupRolesOpen(counts, maxP)
                end
            end
            out[#out + 1] = r
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local ROWS, ROWH = 16, 18
local KINDS = { { nil, "Everyone" }, { "groups", "Groups" }, { "players", "Players looking" } }
-- for a group: the role it still needs. For a lone player: the role they play (so a leader looking for damage picks "Damage")
local ROLES = { { nil, "Any role" }, { "TANK", "Role: tank" }, { "HEALER", "Role: healer" }, { "DAMAGER", "Role: damage" } }
local AGES = { 0, 5, 15, 30, 60 }
local SORTS = { { "new", "Newest first" }, { "size", "Biggest first" }, { "name", "By activity" } }

local win
local offset = 0
local shown = {}

local function IndexOf(list, key, pos)
    for i, e in ipairs(list) do
        local k = e
        if type(e) == "table" then k = e[pos or 1] end
        if k == key then return i end
    end
    return 1
end

local function Whisper(name)
    if not name or name == "" or name == "?" then return end
    if ChatFrame_SendTell then pcall(ChatFrame_SendTell, name) end
end

local function UpdateInner()
    local f = Filt()
    local me = UnitLevel and UnitLevel("player") or nil
    local all = ReadResults()
    local list = {}
    for _, r in ipairs(all) do if addon.GroupMatches(r, f, me) then list[#list + 1] = r end end
    addon.GroupSort(list, f.sort or "new")
    shown = list
    local maxOffset = math.max(0, #list - ROWS)
    if offset > maxOffset then offset = maxOffset end
    for i = 1, ROWS do
        local row, r = win.rows[i], list[offset + i]
        if r then
            row.r = r
            row.age:SetText(Ago(r.age))
            row.size:SetText(tostring(r.numMembers or 1))
            row.act:SetText(r.activity or "?")
            row.leader:SetText(r.leader or "?")
            local text = r.comment ~= "" and r.comment or r.name
            local needs = addon.GroupNeeds(r.roleOpen)
            if needs and (r.numMembers or 1) >= 2 then text = "|cff66ff66needs " .. needs .. "|r  " .. text end
            if (r.numMembers or 1) < 2 and (r.role or r.class) then
                local rn = ({ TANK = "tank", HEALER = "healer", DAMAGER = "dps" })[r.role or ""]
                local cn = r.class and (r.class:sub(1, 1) .. r.class:sub(2):lower()) or nil
                text = "|cff66ff66" .. table.concat({ cn or "", rn or "" }, (cn and rn) and " " or "") .. "|r  " .. text
            end
            if r.itemLevel and r.itemLevel > 0 then text = "(" .. r.itemLevel .. " ilvl) " .. text end
            row.comment:SetText(text)
            row:Show()
        else
            row.r = nil
            row:Hide()
        end
    end
    local total = #all
    if total == 0 then
        win.foot:SetText(L("Nothing to filter yet: open the Browse tab of the group finder, pick a category and search."))
    elseif #list == 0 then
        win.foot:SetText(string.format(L("No group matches (%d found by the search)."), total))
    else
        win.foot:SetText(string.format(L("%d-%d of %d matching (%d found by the search). Click a row to whisper the leader."), offset + 1, math.min(offset + ROWS, #list), #list, total))
    end
    for _, b in ipairs({ win.bKind, win.bRole, win.bAge, win.bSort }) do
        if b.flRefresh then b.flRefresh() end
    end
    win.fit:SetChecked(f.fitLevel == true)
end

local function Update()
    if not (win and win:IsShown()) then return end
    local ok, err = pcall(UpdateInner)
    if not ok then
        -- show what went wrong right in the window, so it can be reported
        if win.foot then win.foot:SetText("|cffff5555error: " .. tostring(err) .. "|r") end
    end
end

local function Cycle(key, list, pos)
    local f = Filt()
    local i = IndexOf(list, f[key], pos)
    i = i % #list + 1
    local e = list[i]
    if type(e) == "table" then f[key] = e[pos or 1] else f[key] = e end
    offset = 0
    Update()
end

local function Build()
    local w = CreateFrame("Frame", "ForeverLazy_GroupFilter", UIParent, "BackdropTemplate")
    w:SetSize(700, 420)
    w:SetPoint("CENTER", 0, 20)
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
    if w.SetBackdrop then
        w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        w:SetBackdropColor(0.05, 0.05, 0.08, 0.96); w:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    else
        local bg = w:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    end
    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(L("Group finder filter"))
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    table.insert(UISpecialFrames, "ForeverLazy_GroupFilter")

    -- search box
    local lbl = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", 14, -40); lbl:SetText(L("Words:"))
    local eb = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    eb:SetSize(160, 20); eb:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    eb:SetAutoFocus(false)
    eb:SetText(Filt().text or "")
    eb:SetScript("OnTextChanged", function(self, user)
        if user then Filt().text = self:GetText(); offset = 0; Update() end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    w.eb = eb

    -- a drop-down list (the game's own menu); the old click-to-cycle button is used when this client has no such list
    local function Choice(width, anchor, point, rel, dx, dy, entries, get, set)
        local dd
        local okC, made = pcall(CreateFrame, "DropdownButton", nil, w, "WowStyle1DropdownTemplate")
        if okC and made and made.SetupMenu then
            dd = made
            dd:SetWidth(width)
            dd:SetupMenu(function(_, root)
                for _, e in ipairs(entries) do
                    root:CreateRadio(L(e.label), function() return get() == e.key end, function() set(e.key); offset = 0; Update() end)
                end
            end)
            dd.flRefresh = function() if dd.GenerateMenu then dd:GenerateMenu() end end
        else
            dd = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
            dd:SetSize(width, 22)
            dd:SetScript("OnClick", function()
                local cur = 1
                for i, e in ipairs(entries) do if e.key == get() then cur = i end end
                set(entries[cur % #entries + 1].key); offset = 0; Update()
            end)
            dd.flRefresh = function()
                for _, e in ipairs(entries) do if e.key == get() then dd:SetText(L(e.label)) end end
            end
        end
        dd:SetPoint(point, anchor, rel, dx, dy)
        return dd
    end
    local ageEntries = {}
    for _, m in ipairs(AGES) do ageEntries[#ageEntries + 1] = { key = m, label = m == 0 and "Any age" or ("Newer than " .. m .. " min") } end
    local kindEntries, roleEntries, sortEntries = {}, {}, {}
    for _, e in ipairs(KINDS) do kindEntries[#kindEntries + 1] = { key = e[1], label = e[2] } end
    for _, e in ipairs(ROLES) do roleEntries[#roleEntries + 1] = { key = e[1], label = e[2] } end
    for _, e in ipairs(SORTS) do sortEntries[#sortEntries + 1] = { key = e[1], label = e[2] } end
    w.bKind = Choice(130, eb, "LEFT", "RIGHT", 6, 0, kindEntries, function() return Filt().kind end, function(v) Filt().kind = v end)
    w.bRole = Choice(130, w.bKind, "LEFT", "RIGHT", 2, 0, roleEntries, function() return Filt().role end, function(v) Filt().role = v end)
    w.bAge = Choice(130, w.bRole, "LEFT", "RIGHT", 2, 0, ageEntries, function() return Filt().maxAge or 0 end, function(v) Filt().maxAge = v end)
    w.bSort = Choice(130, w, "TOPLEFT", "TOPLEFT", 12, -66, sortEntries, function() return Filt().sort or "new" end, function(v) Filt().sort = v end)    w.fit = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
    w.fit:SetSize(24, 24)
    w.fit:SetPoint("LEFT", w.bSort, "RIGHT", 14, 0)
    w.fit:SetScript("OnClick", function(self) Filt().fitLevel = self:GetChecked() and true or nil; offset = 0; Update() end)
    local fitText = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fitText:SetPoint("LEFT", w.fit, "RIGHT", 2, 0); fitText:SetText(L("Right level for me"))
    local reload = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    reload:SetSize(110, 22); reload:SetPoint("TOPRIGHT", -14, -68); reload:SetText(L("Update list"))
    reload:SetScript("OnClick", function() Update() end)
    local clear = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    clear:SetSize(110, 22); clear:SetPoint("RIGHT", reload, "LEFT", -4, 0); clear:SetText(L("Clear filters"))
    clear:SetScript("OnClick", function()
        local d = DB(); if d then d.lfgFilter = {} end
        eb:SetText(""); offset = 0; Update()
    end)

    -- headings
    local function Head(text, x, width)
        local h = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", x, -98); h:SetWidth(width); h:SetJustifyH("LEFT"); h:SetText(text)
    end
    Head(L("Age"), 14, 36); Head(L("Size"), 54, 30); Head(L("Activity"), 90, 190); Head(L("Leader"), 290, 120); Head(L("Comment"), 414, 270)

    -- rows
    w.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, w)
        row:SetSize(676, ROWH)
        row:SetPoint("TOPLEFT", 10, -114 - (i - 1) * ROWH)
        row:RegisterForClicks("LeftButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
        if i % 2 == 0 then local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04) end
        local function Col(x, width, font)
            local fs = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
            fs:SetPoint("LEFT", x, 0); fs:SetWidth(width); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
            return fs
        end
        row.age = Col(4, 36); row.size = Col(44, 30); row.act = Col(80, 190); row.leader = Col(280, 120); row.comment = Col(404, 268, "GameFontDisableSmall")
        row:SetScript("OnClick", function(self) if self.r then Whisper(self.r.leader) end end)
        row:SetScript("OnEnter", function(self)
            local r = self.r
            if not r then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.activity or "?", 1, 0.82, 0)
            GameTooltip:AddLine(string.format("%s  (%d)", r.leader or "?", r.numMembers or 1), 1, 1, 1)
            if r.name ~= "" then GameTooltip:AddLine(r.name, 0.8, 0.8, 0.8, true) end
            if r.comment ~= "" then GameTooltip:AddLine(r.comment, 0.8, 0.8, 0.8, true) end
            if r.itemLevel and r.itemLevel > 0 then GameTooltip:AddLine(L("Item level needed: ") .. r.itemLevel, 1, 0.5, 0.5) end
            if r.voice ~= "" then GameTooltip:AddLine(L("Voice chat: ") .. r.voice, 0.6, 0.8, 1) end
            if r.counts then
                GameTooltip:AddLine(string.format(L("Tanks %s, healers %s, damage %s"), tostring(r.counts.TANK or 0), tostring(r.counts.HEALER or 0), tostring(r.counts.DAMAGER or 0)), 0.6, 0.8, 0.6)
            end
            GameTooltip:AddLine(L("Click: whisper the leader."), 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        w.rows[i] = row
    end
    w:EnableMouseWheel(true)
    w:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #shown - ROWS), offset - delta * 3))
        Update()
    end)
    w.foot = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.foot:SetPoint("BOTTOMLEFT", 14, 12); w.foot:SetWidth(672); w.foot:SetJustifyH("LEFT")
    w:SetScript("OnShow", function() offset = 0; Update() end)
    w:Hide()
    return w
end

function addon.GroupFilterToggle(show)
    if not win then win = Build() end
    if show == nil then show = not win:IsShown() end
    if show then win:Show(); Update() else win:Hide() end
end

--------------------------------------------------------------------------------
-- Keeping it fresh, and a button on the group finder
--------------------------------------------------------------------------------
local pending
local function Soon()
    if not (win and win:IsShown()) then return end
    if pending or not (C_Timer and C_Timer.After) then pcall(Update); return end
    pending = true
    C_Timer.After(0.3, function() pending = false; pcall(Update) end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", Soon)

local button
local function AddButton()
    local parent = _G.LFGParentFrame
    if button then
        if not (DB() and DB().lfgFilterButton == false) then button:Show() end
        return true
    end
    if not parent then return false end
    local d = DB()
    if d and d.lfgFilterButton == false then return true end
    button = CreateFrame("Button", "ForeverLazy_GroupFilterButton", parent, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, 2)
    button:SetText(L("Filter groups"))
    button:SetScript("OnClick", function() addon.GroupFilterToggle() end)
    return true
end

local login = CreateFrame("Frame")
pcall(login.RegisterEvent, login, "PLAYER_LOGIN")
login:SetScript("OnEvent", function()
    -- the group finder window is built on demand: look for it for a while
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(2, function(t) if AddButton() then t:Cancel() end end, 300)
    else
        pcall(AddButton)
    end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "groups" or c == "lfgfilter" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "debug" then
            local n = 0
            for _, r in ipairs(ReadResults()) do
                n = n + 1
                if n <= 5 then Print(string.format("%s: members %d, role %s, class %s", r.leader or "?", r.numMembers or 1, tostring(r.role), tostring(r.class))) end
            end
            Print(string.format("%d results. GetSearchResultPlayerInfo: %s", n, tostring(C_LFGList and C_LFGList.GetSearchResultPlayerInfo ~= nil)))
        elseif a == "button on" then DB().lfgFilterButton = nil; AddButton(); Print(L("group filter: button shown on the group finder"))
        elseif a == "button off" then DB().lfgFilterButton = false; if button then button:Hide() end; Print(L("group filter: button hidden (/lazy groups still opens it)"))
        else addon.GroupFilterToggle() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["GroupFilter.lua"] = true end end
