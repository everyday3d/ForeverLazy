-- Hunt panel: a small panel with one button per mob my quests need. Click a button to target that mob.
--   /lazy hunt on|off     show or hide the panel
-- Drag the title to move it (when the frames are not locked). It only shows while there is something to hunt.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On()
    local db = DB()
    return db and db.huntPanel ~= false and addon.ModuleOn("quests")
end

local MAX, BTN_W, BTN_H = 8, 190, 22
local frame
local buttons = {}
local shownSig = ""
local needRebuild = false

local function MakeFrame()
    local f = CreateFrame("Frame", "ForeverLazy_HuntPanel", UIParent)
    f:SetSize(BTN_W + 8, 40)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
    local title = CreateFrame("Button", nil, f)
    title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT"); title:SetHeight(16)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() if not DB().locked then f:StartMoving() end end)
    title:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        DB().pos.hunt = { point = point, x = x, y = y }
    end)
    f.title = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("LEFT", 6, 0)
    f.title:SetText(L("Hunt (click to target)"))
    f.title:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function()
        DB().huntPanel = false
        f:Hide()
        Print(L("hunt panel closed. /lazy hunt on (or the checkbox in the options) brings it back."))
    end)
    f:Hide()
    return f
end

local function Place()
    if not frame then return end
    local p = DB().pos.hunt or { point = "RIGHT", x = -20, y = 80 }
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    frame:SetScale(DB().scale or 1)
end

local function MakeButton(i)
    local b = CreateFrame("Button", "ForeverLazy_HuntButton" .. i, frame, "SecureActionButtonTemplate")
    b:SetSize(BTN_W, BTN_H)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -18 - (i - 1) * (BTN_H + 2))
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "macro")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.15, 0.15, 0.15, 0.85)
    b.bg = bg
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(BTN_H - 4, BTN_H - 4)
    b.icon:SetPoint("LEFT", 2, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    b.text:SetPoint("RIGHT", -34, 0)
    b.text:SetJustifyH("LEFT")
    b.prog = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.prog:SetPoint("RIGHT", -4, 0)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b:SetScript("OnEnter", function(self)
        if not self.quest then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(self.mob or "", 1, 1, 1)
        GameTooltip:AddLine(self.quest, 1, 0.82, 0)
        GameTooltip:AddLine(self.kind == "loot" and "Drops what a quest needs" or "A quest needs this killed", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end

-- mark the mob I have targeted right now
local function MarkTarget()
    local tname = UnitExists("target") and UnitName("target")
    if issecretvalue and tname and issecretvalue(tname) then tname = nil end
    for i = 1, #buttons do
        local b = buttons[i]
        if b:IsShown() then
            if tname and b.mob == tname then b.bg:SetColorTexture(0.5, 0.35, 0, 0.9) else b.bg:SetColorTexture(0.15, 0.15, 0.15, 0.85) end
        end
    end
end

-- rebuild the buttons (never in combat: they are secure buttons)
local function Rebuild()
    if not frame then frame = MakeFrame(); Place() end
    if InCombatLockdown() then needRebuild = true; return end
    needRebuild = false
    if not On() then frame:Hide(); shownSig = ""; return end       -- switched off (or closed with the X)
    local list = (On() and addon.HuntList and addon.HuntList()) or {}
    local shown = {}
    -- following someone's plan: the mobs of its current stop, even for quests I do not have
    local wps0 = DB().waypoints
    local extra = {}
    if On() and addon.planFromSet and wps0 and wps0[1] and addon.planFromSet[wps0[1]] and wps0[1].huntQuests and addon.HuntFromQuests then
        extra = addon.HuntFromQuests(wps0[1].huntQuests)
    end
    local have = {}
    for _, h in ipairs(extra) do have[h.name] = true; shown[#shown + 1] = h end
    for _, h in ipairs(list) do if h.kind == "kill" and not have[h.name] then shown[#shown + 1] = h end end
    for _, h in ipairs(list) do if h.kind ~= "kill" then shown[#shown + 1] = h end end
    while #shown > MAX do table.remove(shown) end
    -- the plan line: whose plan I am following (or mine) and how many stops are left
    local planLine
    local wps = DB().waypoints
    if wps and #wps > 0 then
        if addon.planFrom and addon.planFromSet and addon.planFromSet[wps[1]] then
            planLine = string.format("|cff66ff66Following %s's plan|r - %d stop%s left", addon.planFrom, #wps, #wps == 1 and "" or "s")
        elseif #shown > 0 then
            planLine = string.format("Your plan - %d stop%s left", #wps, #wps == 1 and "" or "s")
        end
    elseif addon.planFrom then
        addon.planFrom, addon.planFromSet = nil, nil
    end
    local sig = { planLine or "" }
    for _, h in ipairs(shown) do sig[#sig + 1] = h.name .. (h.progress or "") .. h.kind end
    sig = table.concat(sig, "|")
    if sig == shownSig and (#shown == 0 and not planLine) == (not frame:IsShown()) then MarkTarget(); return end
    shownSig = sig
    for i = 1, MAX do
        local h = shown[i]
        local b = buttons[i] or (h and MakeButton(i))
        if b then
            if h then
                b.mob, b.quest, b.kind = h.name, h.quest, h.kind
                -- target it, then put a skull on it (only if what I targeted really is that mob, and it has no skull yet)
                local q = h.name:gsub("\\", "\\\\"):gsub("\"", "\\\"")
                b:SetAttribute("macrotext", "/targetexact " .. h.name .. "\n/run if UnitExists(\"target\") and UnitName(\"target\")==\"" .. q ..
                    "\" and GetRaidTargetIndex(\"target\")~=8 then pcall(SetRaidTarget,\"target\",8) end")
                b.icon:SetTexture(h.kind == "loot" and "Interface\\Icons\\INV_Misc_Bag_08" or "Interface\\Icons\\INV_Sword_04")
                b.text:SetText(h.name)
                b.prog:SetText(h.progress or "")
                b:Show()
            else
                b:Hide()
            end
        end
    end
    if #shown == 0 and not planLine then
        frame:Hide()
    else
        frame.title:SetText(planLine or "Hunt (click to target)")
        frame:SetHeight(20 + #shown * (BTN_H + 2))
        frame:Show()
    end
    MarkTarget()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_TURNED_IN",
    "QUEST_WATCH_UPDATE", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
local pending
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        if frame and frame:IsShown() then MarkTarget() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if needRebuild then pcall(Rebuild) end
        return
    end
    if not pending and C_Timer and C_Timer.After then
        pending = true
        -- a moment after the event: the quest log and the nameplate module have settled by then
        C_Timer.After(1.5, function() pending = false; pcall(Rebuild) end)
    end
end)

-- apply the saved position again when the layout is re-applied (reset positions, profile switch)
local origLayout = addon.ApplyLayout
function addon:ApplyLayout()
    if origLayout then origLayout(self) end
    Place()
end
addon.HuntPanelRefresh = function() shownSig = ""; pcall(Rebuild) end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "hunt" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "off" then db.huntPanel = false elseif a == "on" then db.huntPanel = nil end
        Print(L("hunt panel: ") .. (db.huntPanel == false and "OFF" or "on") .. L("  (/lazy hunt on|off). It shows the mobs your quests need; click one to target it."))
        addon.HuntPanelRefresh()
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["HuntPanel.lua"] = true end end
