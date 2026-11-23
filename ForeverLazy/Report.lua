-- Report window: the output of debug and report commands (/lazy data, moblevels, check, why, ...) shown in a window you can
-- scroll, resize, and copy from, instead of chat that scrolls by.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon

local function DB() return addon.GetDB() end

-- which commands show their output in a window (db.reportWindow == false sends them back to chat)
local PLAIN = { data = true, moblevels = true, moblevel = true, mobs = true, check = true, why = true, dungeons = true,
    drops = true, pace = true, session = true, grind = true, danger = true }
function addon.IsReportCommand(cmd, rest)
    local db = DB()
    if db and db.reportWindow == false then return false end
    cmd = (cmd or ""):lower()
    if PLAIN[cmd] then return true end
    if cmd == "plan" then
        local r = (rest or ""):lower()
        return (r:find("^debug") or r:find("^check") or r:find("^why")) and true or false
    end
    if cmd == "nodes" then return ((rest or ""):lower()):find("^debug") and true or false end
    return false
end

local win
local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_Report", UIParent)
    f:SetSize(580, 420)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then f:SetResizeBounds(360, 200, 1200, 900)
    elseif f.SetMinResize then f:SetMinResize(360, 200) end
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.hint:SetText(L("Click in the text, then Ctrl+A and Ctrl+C to copy it. Drag the corner to resize."))
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local scroll = CreateFrame("ScrollFrame", "ForeverLazy_ReportScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -52); scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlight")
    edit:SetWidth(520)
    edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    -- read-only: typing puts the report text back
    edit:SetScript("OnTextChanged", function(s) if s.ownText and s:GetText() ~= s.ownText then s:SetText(s.ownText) end end)
    scroll:SetScrollChild(edit)
    f.edit, f.scroll = edit, scroll
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    f:SetScript("OnSizeChanged", function(_, w) edit:SetWidth(math.max(200, w - 60)) end)
    table.insert(UISpecialFrames, "ForeverLazy_Report")
    f:Hide()
    return f
end

function addon.ReportWindow(title, lines)
    win = win or Build()
    local text = table.concat(lines, "\n")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
    win.title:SetText(title)
    win.edit.ownText = text
    win.edit:SetText(text)
    win.edit:SetCursorPosition(0)
    if win.scroll.SetVerticalScroll then win.scroll:SetVerticalScroll(0) end
    local scale = math.min(2.6, math.max(0.8, tonumber(DB().guideScale) or 1))
    win:SetScale(scale)
    win:Show()
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Report.lua"] = true end end
