-- Waypoint sharing, the import / export window, the minimap right-click menu and the self-test.
-- Split out of Extras.lua; it needs nothing from there.
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local hbd = api.hbd
local state = addon.state
local Print = addon.Print
local X = ns.extras          -- what Extras.lua shares with the files split out of it

local function DB() return addon.GetDB() end
--------------------------------------------------------------------------------
-- Waypoint sharing (party) -- needs this addon on both sides
--------------------------------------------------------------------------------
local SHARE_PREFIX = "FLWP"

function addon:ShareWaypoint()
    local wp = DB().waypoints[1]
    if not wp then Print("no active waypoint to share"); return end
    if not IsInGroup() then Print("you are not in a party"); return end
    local data = self:Serialize({ name = wp.name, uiMapId = wp.uiMapId, zx = wp.zx, zy = wp.zy })
    self:SendCommMessage(SHARE_PREFIX, data, IsInRaid() and "RAID" or "PARTY")
    Print("sent waypoint to the group: " .. wp.name)
end

function addon:OnSharedWaypoint(prefix, message, distribution, sender)
    if prefix ~= SHARE_PREFIX then return end
    if (sender or ""):match("^([^%-]+)") == UnitName("player") then return end
    if not DB().acceptShared then return end
    local ok, t = self:Deserialize(message)
    if not ok or type(t) ~= "table" then return end
    if type(t.uiMapId) ~= "number" or type(t.zx) ~= "number" or type(t.zy) ~= "number" then return end
    if t.zx < 0 or t.zx > 1 or t.zy < 0 or t.zy > 1 then return end
    local from = (sender or "?"):match("^([^%-]+)") or sender
    local name = string.format("%s (from %s)", tostring(t.name or "Waypoint"):sub(1, 60), from)
    self:AddWaypointZone(t.uiMapId, t.zx, t.zy, name)
end
addon:RegisterComm(SHARE_PREFIX, "OnSharedWaypoint")

--------------------------------------------------------------------------------
-- Import / export dialog
--------------------------------------------------------------------------------
local io
local function MakeIO()
    local f = CreateFrame("Frame", "ForeverLazy_IOFrame", UIParent)
    f:SetSize(400, 250)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPLEFT", 14, -34)
    local ebBg = f:CreateTexture(nil, "BORDER")
    ebBg:SetPoint("TOPLEFT", 12, -52); ebBg:SetSize(376, 150); ebBg:SetColorTexture(0, 0, 0, 0.6)
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal or GameFontHighlight)
    eb:SetSize(364, 146)
    eb:SetPoint("TOPLEFT", 18, -56)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(8000)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.edit = eb
    f.action = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.action:SetSize(110, 24); f.action:SetPoint("BOTTOMLEFT", 14, 12)
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(90, 24); close:SetPoint("BOTTOMRIGHT", -14, 12); close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    return f
end

local function ExportText()
    local lines = {}
    for _, w in ipairs(DB().waypoints) do
        if w.uiMapId and w.zx and w.zy then
            lines[#lines + 1] = string.format("%d,%.4f,%.4f,%s", w.uiMapId, w.zx, w.zy, (w.name or ""):gsub("[\r\n]", " "))
        end
    end
    return table.concat(lines, "\n")
end

function addon:OpenIO(mode)
    io = io or MakeIO()
    io:Show()
    if mode == "export" then
        io.title:SetText("Export waypoints")
        io.hint:SetText("Select all (Ctrl+A) and copy (Ctrl+C). One waypoint per line.")
        io.edit:SetText(ExportText())
        io.edit:HighlightText()
        io.edit:SetFocus()
        io.action:SetText("Select all")
        io.action:SetScript("OnClick", function() io.edit:SetFocus(); io.edit:HighlightText() end)
    else
        io.title:SetText("Import waypoints")
        io.hint:SetText("Paste lines like:  mapId,x,y,name   (x and y between 0 and 1)")
        io.edit:SetText("")
        io.edit:SetFocus()
        io.action:SetText("Import")
        io.action:SetScript("OnClick", function()
            local found = {}
            for line in (io.edit:GetText() or ""):gmatch("[^\r\n]+") do
                local m, x, y, name = line:match("^%s*(%d+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,?%s*(.-)%s*$")
                m, x, y = tonumber(m), tonumber(x), tonumber(y)
                if m and x and y and x <= 1 and y <= 1 then found[#found + 1] = { m, x, y, name } end
            end
            -- add last first so the first line ends up active
            for i = #found, 1, -1 do
                local f = found[i]
                addon:AddWaypointZone(f[1], f[2], f[3], f[4])
            end
            Print(string.format("imported %d waypoints", #found))
            io:Hide()
        end)
    end
end

--------------------------------------------------------------------------------
-- Minimap right-click menu
--------------------------------------------------------------------------------
local menu
local function MakeMenu()
    local f = CreateFrame("Frame", "ForeverLazy_Menu", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.buttons = {}
    local items = {
        { function() return "Options" end, function() addon:OpenOptions() end },
        { function() return "Arrow mode: " .. DB().mode .. " (click to change)" end, function() addon:CycleMode() end },
        { function() return DB().showPanel and "Hide step panel" or "Show step panel" end, function() _G.ForeverLazy_TogglePanel() end },
        { function() return "Drop waypoint here" end, function() addon:DropWaypointHere() end },
        { function() return "Clear waypoints" end, function() addon:ClearWaypoints() end },
        { function() return "Follow next friend" end, function() addon:CycleFriend() end },
        { function() return "Run self-test" end, function() addon:RunSelfTest() end },
    }
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 20)
        b:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * 20)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 4, 0)
        b.fs = fs
        b.getText = it[1]
        b:SetScript("OnClick", function() it[2](); f:Hide() end)
        f.buttons[i] = b
    end
    f:SetSize(230, 12 + #items * 20)
    local away = 0
    f:SetScript("OnUpdate", function(self, dt)
        if MouseIsOver(self) or (self.anchorFrame and MouseIsOver(self.anchorFrame)) then away = 0
        else away = away + dt; if away > 0.8 then self:Hide() end end
    end)
    f:Hide()
    return f
end

function addon:OpenMenu(anchor)
    menu = menu or MakeMenu()
    for _, b in ipairs(menu.buttons) do b.fs:SetText(b.getText()) end
    menu.anchorFrame = anchor
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 10, 0)
    menu:Show()
end

--------------------------------------------------------------------------------
-- Self-test
--------------------------------------------------------------------------------
function addon:RunSelfTest()
    local function line(ok, text, detail)
        local tag = ok == nil and "|cffffd100--|r " or (ok and "|cff55ff55OK|r " or "|cffff5555FAIL|r ")
        print("  " .. tag .. text .. (detail and (" - " .. detail) or ""))
    end
    Print("self-test")
    local LS = _G.LibStub
    line(LS("AceComm-3.0", true) ~= nil, "AceComm library")
    line(LS("AceSerializer-3.0", true) ~= nil, "AceSerializer library")
    line(LS("LibDeflate", true) ~= nil, "LibDeflate library")
    line(LS("HereBeDragons-2.0", true) ~= nil, "HereBeDragons library")
    line(LS("HereBeDragons-Pins-2.0", true) ~= nil, "map pin library")

    local px, py, pinst = hbd:GetPlayerWorldPosition()
    line(px ~= nil, "your world position", px and string.format("%.0f, %.0f (instance %s)", px, py, tostring(pinst)) or "unreadable here")
    line(GetPlayerFacing() ~= nil, "your facing direction", GetPlayerFacing() and string.format("%.2f rad", GetPlayerFacing()) or "unreadable (mounted/flying?)")

    local zx, zy, zone = hbd:GetPlayerZonePosition()
    line(zx ~= nil, "zone position (for waypoints)", zx and string.format("%.1f, %.1f in map %s", zx * 100, zy * 100, tostring(zone)) or nil)
    if zx and zone then
        local wx, wy = hbd:GetWorldCoordinatesFromZone(zx, zy, zone)
        local ok = wx and px and math.abs(wx - px) < 25 and math.abs(wy - py) < 25
        line(ok and true or false, "map-to-world conversion round trip",
            wx and string.format("off by %.1f / %.1f yards", math.abs(wx - (px or 0)), math.abs(wy - (py or 0))) or "failed")
    end

    line(IsInGroup() and true or nil, "in a party", IsInGroup() and GetNumGroupMembers() .. " members" or "join your friend's party")
    if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered then
        line(C_ChatInfo.IsAddonMessagePrefixRegistered("RXPGComms") and true or false, "listening on RXPGComms")
    else
        line(nil, "listening on RXPGComms", "cannot be checked on this client")
    end
    local age = state.lastMsg and string.format("last one %ds ago", GetTime() - state.lastMsg) or "none yet"
    line(state.msgCount > 0 and true or nil, "friend step messages received", string.format("%d valid, %d total, %s", state.msgCount, state.rawCount, age))
    if state.msgCount == 0 then
        line(nil, "tip", "your friend needs RXP Beta features + Share active steps turned on, and must be in your party")
    end
    line(state.friend ~= nil, "following a friend", state.friend)

    line(api.QuestieReady() and true or false, "Questie database")
    line(api.IndexReady() and true or nil, "name index", string.format("%d%%", (state.index.progress or 0) * 100))
    line(#state.groups > 0 and true or nil, "map spots found for current step", string.format("%d groups, %d arrows", #state.groups, #state.chosen))
    line(api.IsMapHooked() and true or nil, "world map Ctrl+right-click hook")
    line(_G.TomTom ~= nil and true or nil, "TomTom installed (optional)")
    local lk = state.lastKnown
    line(lk ~= nil and true or nil, "friend position tracking", lk and string.format("seen %ds ago", GetTime() - lk.t) or "friend not in range yet")
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["ExtrasTools.lua"] = true end end
