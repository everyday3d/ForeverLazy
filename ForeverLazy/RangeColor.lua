-- Out-of-range colouring for the action bars: a button turns red-orange when the target is out of range, blue when you lack the
-- mana, grey when it cannot be used. Works with the game's bars and with bar addons built on them (Dominos and the like).
--   /lazy range on|off
-- Adapted from tullaRange by Tuller (MIT licence, see media/CREDITS.txt for the notice). If tullaRange is installed it does
-- the job and this one stays out of the way, so the two never fight over the colours.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

local function Handled()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("tullaRange")
end
local function On()
    local db = DB()
    return db and db.rangeColor ~= false and not Handled()
end

-- r, g, b, a, desaturate
local COLORS = {
    normal   = { 1, 1, 1, 1, false },
    oor      = { 1, 0.3, 0.1, 1, true },
    oom      = { 0.1, 0.3, 1, 1, true },
    unusable = { 0.4, 0.4, 0.4, 1, false },
}

local states = setmetatable({}, { __mode = "k" })

local function Paint(icon, key)
    local c = COLORS[key]
    icon:SetVertexColor(c[1], c[2], c[3], c[4])
    icon:SetDesaturated(c[5])
end

local function State(slot)
    local isUsable, notEnoughMana = IsUsableAction(slot)
    local outOfRange = IsActionInRange(slot) == false
    if isUsable then return outOfRange and "oor" or "normal", outOfRange end
    return notEnoughMana and "oom" or "unusable", outOfRange
end

-- a button drew itself: colour its icon and its key text
local function Update(button)
    if not On() then return end
    local icon, slot = button.icon, button.action
    if not icon or type(slot) ~= "number" then return end
    local key, oor = State(slot)
    states[icon] = key
    Paint(icon, key)
    local hot = button.HotKey
    if hot then
        local hk = oor and "oor" or "normal"
        states[hot] = hk
        hot:SetVertexColor(COLORS[hk][1], COLORS[hk][2], COLORS[hk][3])
    end
end

-- the game says a button went in or out of range
local function UpdateRange(button, checksRange, inRange)
    if not On() then return end
    local icon = button and button.icon
    if not icon then return end
    local oor = checksRange and not inRange
    local cur = states[icon]
    local new
    if cur == "normal" and oor then new = "oor" elseif cur == "oor" and not oor then new = "normal" end
    if new then states[icon] = new; Paint(icon, new) end
    local hot = button.HotKey
    local hc = hot and states[hot]
    local hn
    if hc == "normal" and oor then hn = "oor" elseif hc == "oor" and not oor then hn = "normal" end
    if hn then states[hot] = hn; hot:SetVertexColor(COLORS[hn][1], COLORS[hn][2], COLORS[hn][3]) end
end

local registered = {}
local function Register(button)
    if registered[button] then return end
    registered[button] = true
    if button.UpdateUsable then pcall(hooksecurefunc, button, "UpdateUsable", function(b) pcall(Update, b) end) end
end

local enabled = false
local function Enable()
    if enabled then return end
    local frame = _G.ActionBarButtonEventsFrame
    if not (frame and frame.ForEachFrame) then return end
    enabled = true
    pcall(frame.ForEachFrame, frame, Register)
    pcall(hooksecurefunc, frame, "RegisterFrame", function(_, button) pcall(Register, button) end)
    if _G.ActionButton_UpdateRangeIndicator then
        pcall(hooksecurefunc, "ActionButton_UpdateRangeIndicator", function(...) pcall(UpdateRange, ...) end)
    end
end

-- paint every button again (after switching on or off)
local function Repaint()
    local frame = _G.ActionBarButtonEventsFrame
    if not (frame and frame.ForEachFrame) then return end
    pcall(frame.ForEachFrame, frame, function(button)
        if On() then
            pcall(Update, button)
        else
            if button.icon then button.icon:SetVertexColor(1, 1, 1, 1); button.icon:SetDesaturated(false) end
            if button.HotKey then button.HotKey:SetVertexColor(1, 1, 1) end
            if button.UpdateUsable then pcall(button.UpdateUsable, button) end     -- the game paints it its own way again
        end
    end)
end

addon.RangeColorRefresh = function() Enable(); Repaint() end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then C_Timer.After(1, function() Enable(); Repaint() end) else Enable() end
end)

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "range" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "off" then db.rangeColor = false elseif a == "on" then db.rangeColor = nil end
        Print(L("action button range colours: ") .. (db.rangeColor == false and "OFF" or "on") .. L("  (/lazy range on|off): red = out of range, blue = no mana, grey = cannot use.")
            .. (Handled() and " tullaRange is installed, so it does this job." or ""))
        addon.RangeColorRefresh()
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["RangeColor.lua"] = true end end
