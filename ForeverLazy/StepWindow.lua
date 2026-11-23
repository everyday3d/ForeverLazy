-- The step window: the plan as numbered steps, one thing at a time.
-- Split out of Extras.lua.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local hbd = api.hbd
local state = addon.state
local Print = addon.Print
local X = ns.extras          -- what Extras.lua shares with the files split out of it

local function DB() return addon.GetDB() end
local PlainTitle, GiverName, ObjectiveLines = X.PlainTitle, X.GiverName, X.ObjectiveLines

--------------------------------------------------------------------------------
-- The step window: the plan as numbered steps, one thing at a time (like a levelling guide)
--   !  accept a quest, from whom, where        -  do its objectives (kill, collect, go)        ?  turn it in
-- It ticks a step off by itself when it is done and shows the next few. The arrow already follows the first stop.
--------------------------------------------------------------------------------
local stepWin, stepRows = nil, {}
local stepHistory, stepSeen = {}, {}          -- steps just done (shown ticked for a while), and the ones seen last time
local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:14|t"

local function InLog(id)
    if not (id and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return false end
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    return ok and idx and idx > 0 and true or false
end

function addon.StepList(max)
    local db = DB()
    local steps = {}
    local pts = addon.TalentPointsUnspent and addon.TalentPointsUnspent() or 0
    if pts > 0 and db.talentReminder ~= false then
        steps[#steps + 1] = { kind = "go", key = "talents", text = "Spend " .. pts .. " talent point" .. (pts == 1 and "" or "s") .. " (press N)", done = false }
    end
    for si, w in ipairs(db.waypoints or {}) do
        if #steps >= (max or 12) then break end
        if w.lazy and not w.label then
            -- a service step Lazy mode or the autopilot added: sell and repair, visit the trainer, move on
            local nm = tostring(w.name or "Go"):gsub("^Lazy mode: ", "")
            steps[#steps + 1] = { kind = "go", key = "lazy:" .. si .. ":" .. nm, stop = si, text = "Go to " .. nm .. (w.detail and (" - " .. w.detail) or ""), done = false }
        end
        if w.label and not w.go and not w.gather and not w.guard then
            local where = w.zx and w.zy and string.format("%.0f, %.0f", w.zx * 100, w.zy * 100) or nil
            local acc, dos, trn = {}, {}, {}
            for _, q in ipairs(w.quests or {}) do
                local lbl = q.label or ""
                local title = PlainTitle(lbl)
                if lbl:find("^Turn in:") then
                    local npc = GiverName(q.id, "finishedBy")
                    trn[#trn + 1] = { kind = "turn", key = tostring(q.id) .. ":turn", stop = si, where = where,
                        text = "Turn in " .. title .. (npc and (" to " .. npc) or ""), done = not InLog(q.id), qid = q.id, label = q.label }
                elseif lbl:find("^Pick up:") or lbl:find("^Class quest:") then
                    local npc = GiverName(q.id, "startedBy")
                    acc[#acc + 1] = { kind = "accept", key = tostring(q.id) .. ":accept", stop = si, where = where,
                        text = "Accept " .. title .. (npc and (" from " .. npc) or ""), done = InLog(q.id), qid = q.id, label = q.label }
                else
                    local lines = ObjectiveLines(q.id, q.src)
                    local text = (#lines > 0) and (title .. ": " .. table.concat(lines, ", ", 1, math.min(#lines, 2))) or ("Do " .. title)
                    local finished = C_QuestLog and C_QuestLog.IsComplete and select(2, pcall(C_QuestLog.IsComplete, q.id)) or false
                    dos[#dos + 1] = { kind = "do", key = tostring(q.id) .. ":do", stop = si, where = where, text = text,
                        done = finished and true or false, qid = q.id, label = q.label }
                end
            end
            for _, t in ipairs(acc) do steps[#steps + 1] = t end
            for _, t in ipairs(dos) do steps[#steps + 1] = t end
            for _, t in ipairs(trn) do steps[#steps + 1] = t end
            if #w.quests == 0 then
                steps[#steps + 1] = { kind = "go", key = "go:" .. si .. ":" .. tostring(w.label), stop = si, where = where,
                    text = "Go to " .. PlainTitle(w.label), done = false }
            end
        end
    end
    return steps
end

local KIND_MARK = { accept = "|cffffd100!|r", ["do"] = "|cffffffff-|r", turn = "|cffffd100?|r", go = "|cff80c0ff>|r" }

local function StepScale()
    local db = DB()
    return math.min(2.6, math.max(0.7, tonumber(db.stepsScale) or tonumber(db.guideScale) or 1))
end

local function StepRefresh()
    local db = DB()
    if not stepWin then return end
    local steps = (db and not db.planPaused) and addon.StepList(14) or {}
    -- steps seen before that are gone now were done: keep a few ticked for a while
    local now, current = GetTime(), {}
    for _, s in ipairs(steps) do current[s.key] = true end
    for key, s in pairs(stepSeen) do
        if not current[key] and not s.gone then
            s.gone = now
            stepHistory[#stepHistory + 1] = s
        end
    end
    stepSeen = {}
    for _, s in ipairs(steps) do stepSeen[s.key] = s end
    for i = #stepHistory, 1, -1 do
        if now - stepHistory[i].gone > 20 or i < #stepHistory - 2 then table.remove(stepHistory, i) end
    end

    stepWin:SetScale(StepScale())
    local fixedHeight = db.pos and db.pos.stepsSize and db.pos.stepsSize.h        -- I sized it: as many steps as fit
    local width = math.max(160, stepWin:GetWidth() - 28)
    local rows, n = {}, 0
    for _, s in ipairs(stepHistory) do rows[#rows + 1] = { s = s, done = true } end
    local firstOpen = true
    for _, s in ipairs(steps) do
        if not fixedHeight and #rows >= 8 then break end
        rows[#rows + 1] = { s = s, done = s.done, current = (not s.done) and firstOpen }
        if not s.done then firstOpen = false end
    end
    local y, shown = 0, 0
    local room = fixedHeight and (fixedHeight - 40) or nil
    for i, r in ipairs(rows) do
        local row = stepRows[i]
        if not row then
            row = stepWin.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row:SetJustifyH("LEFT")
            stepRows[i] = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", stepWin.content, "TOPLEFT", 4, -y)
        row:SetWidth(width)
        local s = r.s
        local text = string.format("%s %s%s", r.done and CHECK or KIND_MARK[s.kind] or "-", s.text, s.where and ("  |cff999999(" .. s.where .. ")|r") or "")
        if r.done then text = "|cff55ff55" .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r"
        elseif r.current then text = "|cffffd100" .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r" end
        row:SetText(text)
        local h = row:GetStringHeight() + 6
        if room and shown > 0 and y + h > room then break end      -- no more room: the rest shows when there is
        row:Show()
        y = y + h
        shown = i
    end
    for i = shown + 1, #stepRows do stepRows[i]:Hide() end
    local zone = GetRealZoneText and GetRealZoneText() or ""
    stepWin.title:SetText(#rows > 0 and ("Steps  |cffaaaaaa" .. zone .. "|r") or "Steps")
    stepWin.empty:SetWidth(width)
    stepWin.empty:SetShown(#rows == 0)
    stepWin.content:SetSize(width, math.max(y, 20))
    if not fixedHeight and not stepWin.sizing then stepWin:SetHeight(math.max(70, 40 + y)) end
end

local function BuildStepWindow()
    local f = CreateFrame("Frame", "ForeverLazy_Steps", UIParent)
    local size = DB() and DB().pos and DB().pos.stepsSize
    f:SetSize(size and size.w or 300, size and size.h or 140)
    local saved = DB() and DB().pos and DB().pos.steps
    if saved then f:SetPoint(saved.point or "TOPRIGHT", UIParent, saved.rel or "TOPRIGHT", saved.x or 0, saved.y or 0)
    else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -250) end
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetResizable(true)
    pcall(f.SetResizeBounds, f, 190, 90, 900, 900)          -- newer clients
    pcall(f.SetMinResize, f, 190, 90)                       -- older ones
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        local db = DB()
        if db then db.pos = db.pos or {}; db.pos.steps = { point = point, rel = rel, x = x, y = y } end
    end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.04, 0.07, 0.85)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 8, -8)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() DB().stepsHidden = true; f:Hide() end)
    -- text size, like the guide window: A- smaller, A+ bigger
    local function SizeButton(text, anchor, delta)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(24, 18); b:SetText(text); b:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
        b:SetScript("OnClick", function()
            local db = DB()
            db.stepsScale = math.min(2.6, math.max(0.7, StepScale() + delta))
            StepRefresh()
        end)
        return b
    end
    local bigger = SizeButton("A+", close, 0.15)
    SizeButton("A-", bigger, -0.15)
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", 8, -28); f.content:SetSize(272, 20)
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.empty:SetPoint("TOPLEFT", 8, -30); f.empty:SetWidth(272); f.empty:SetJustifyH("LEFT")
    f.empty:SetText("No plan yet. /lazy plan or /lazy level makes one.")
    -- drag the corner to resize; the size is remembered. Shift + right-click on the title goes back to automatic height.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f.sizing = true; f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f.sizing = false
        local db = DB()
        if db then db.pos = db.pos or {}; db.pos.stepsSize = { w = f:GetWidth(), h = f:GetHeight() } end
        StepRefresh()
    end)
    f:SetScript("OnSizeChanged", function(self) if self.sizing then StepRefresh() end end)
    local reset = CreateFrame("Button", nil, f)
    reset:SetPoint("TOPLEFT", 0, 0); reset:SetPoint("TOPRIGHT", -70, 0); reset:SetHeight(24)
    reset:RegisterForClicks("RightButtonUp")
    reset:RegisterForDrag("LeftButton")                      -- the title strip still drags the whole window
    reset:SetScript("OnDragStart", function() f:StartMoving() end)
    reset:SetScript("OnDragStop", function() local h = f:GetScript("OnDragStop"); if h then h(f) end end)
    reset:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            local db = DB()
            if db and db.pos then db.pos.stepsSize = nil end
            f:SetSize(300, 140)
            StepRefresh()
        end
    end)
    f:Hide()
    return f
end
function addon.ToggleSteps(force)
    local db = DB()
    if not stepWin then stepWin = BuildStepWindow() end
    local show
    if force ~= nil then show = force else show = not stepWin:IsShown() end
    db.stepsHidden = not show
    if show then stepWin:Show(); StepRefresh() else stepWin:Hide() end
end

-- show it by itself while a plan is running (unless I closed it), keep it up to date
local stepAcc = 0
local stepTick = CreateFrame("Frame")
stepTick:SetScript("OnUpdate", function(_, dt)
    stepAcc = stepAcc + dt
    if stepAcc < 0.7 then return end
    stepAcc = 0
    local db = DB()
    if not db then return end
    local wantAuto = db.stepsAuto ~= false and not db.stepsHidden and not db.planPaused and addon.ModuleOn("plan")
    local has = false
    for _, w in ipairs(db.waypoints or {}) do if w.label and not w.go and not w.gather and not w.guard then has = true; break end end
    if not stepWin then
        if not (wantAuto and has) then return end
        stepWin = BuildStepWindow()
    end
    if (wantAuto and has) or (db.stepsHidden == false and stepWin:IsShown()) then
        if not stepWin:IsShown() then stepWin:Show() end
        pcall(StepRefresh)
    elseif stepWin:IsShown() and (not has or db.planPaused) then
        stepWin:Hide()
    end
end)

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["StepWindow.lua"] = true end end
