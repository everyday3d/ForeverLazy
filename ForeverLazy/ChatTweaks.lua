-- Chat tweaks, a little like Prat: how messages look and how the chat windows behave. Everything is off until you turn it on in
-- the options (Chat), or with the preset button / `/lazy chat preset`.
--   look:      timestamps, class-coloured names, player levels next to names, short channel names, keyword highlight
--   behaviour: click a web link to copy it, a copy button on each window, input box on top, no fading, long history,
--              hidden side buttons, tabs that fade away, sticky channels, an extra whisper sound, font and size
--   /lazy chat                 what is on
--   /lazy chat preset          turn on the usual set
--   /lazy chat words a, b, c   the words to highlight (your own name is always one)
--   /lazy chat copy            put the text of the chat window you are using in a window you can copy from
-- Messages are changed on their way into the window, never the game's own chat data. Some changes need a /reload to undo.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function On(key) local db = DB(); return db and db[key] == true end
local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) or false end

local TIME_FORMATS = { "%H:%M", "%H:%M:%S", "%I:%M %p", "%I:%M:%S %p" }
local FONTS = {
    { "Default", nil }, { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" }, { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\SKURRI.TTF" }, { "Morpheus", "Fonts\\MORPHEUS.TTF" },
}
function addon.ChatTimeFormats() return TIME_FORMATS end
function addon.ChatFonts() return FONTS end

--------------------------------------------------------------------------------
-- Levels of the players I meet: from my group, target, mouseover, guild, friends and /who
--------------------------------------------------------------------------------
local levels = {}
local function Base(name) return name and (tostring(name):match("^([^%-]+)") or tostring(name)) or nil end

local function Learn(name, lvl)
    name = Base(name)
    lvl = tonumber(lvl)
    if not name or not lvl or lvl <= 0 or Secret(name) or Secret(lvl) then return end
    if levels[name] == lvl then return end
    levels[name] = lvl
    local root = addon.GetRoot and addon.GetRoot()
    if root then
        root.chatLevels = root.chatLevels or {}
        root.chatLevelCount = (root.chatLevelCount or 0) + 1
        if root.chatLevelCount > 4000 then root.chatLevels = {}; root.chatLevelCount = 0 end
        root.chatLevels[name] = lvl
    end
end

local function LearnUnit(unit)
    if UnitExists(unit) and UnitIsPlayer(unit) then Learn(UnitName(unit), UnitLevel(unit)) end
end

local function LearnGroup()
    LearnUnit("player")
    for i = 1, 4 do LearnUnit("party" .. i) end
    if IsInRaid and IsInRaid() then for i = 1, 40 do LearnUnit("raid" .. i) end end
end

local function LearnGuild()
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return end
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, _, _, level = GetGuildRosterInfo(i)
        if name then Learn(name, level) end
    end
end

local function LearnFriends()
    local FL = _G.C_FriendList
    if not (FL and FL.GetNumFriends and FL.GetFriendInfoByIndex) then return end
    for i = 1, (FL.GetNumFriends() or 0) do
        local info = FL.GetFriendInfoByIndex(i)
        if info and info.name then Learn(info.name, info.level) end
    end
end

local function LearnWho()
    local FL = _G.C_FriendList
    if not (FL and FL.GetNumWhoResults and FL.GetWhoInfo) then return end
    for i = 1, (FL.GetNumWhoResults() or 0) do
        local info = FL.GetWhoInfo(i)
        if info and info.fullName then Learn(info.fullName, info.level) end
    end
end

local lvEvents = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE", "UNIT_LEVEL",
                     "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "WHO_LIST_UPDATE", "PLAYER_LEVEL_UP" }) do
    pcall(lvEvents.RegisterEvent, lvEvents, e)
end
lvEvents:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        local root = addon.GetRoot and addon.GetRoot()
        if root and type(root.chatLevels) == "table" then for n, l in pairs(root.chatLevels) do levels[n] = l end end
        LearnGroup()
        if C_Timer and On("chatLevels") then
            C_Timer.After(6, function()
                if IsInGuild and IsInGuild() then
                    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
                end
                LearnFriends()
            end)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then LearnUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then LearnUnit("mouseover")
    elseif event == "GROUP_ROSTER_UPDATE" then LearnGroup()
    elseif event == "UNIT_LEVEL" then if arg1 then LearnUnit(arg1) end
    elseif event == "PLAYER_LEVEL_UP" then LearnUnit("player")
    elseif event == "GUILD_ROSTER_UPDATE" then LearnGuild()
    elseif event == "FRIENDLIST_UPDATE" then LearnFriends()
    elseif event == "WHO_LIST_UPDATE" then LearnWho()
    end
end)

local function LevelText(name)
    local lv = levels[Base(name)]
    if not lv then return nil end
    local r, g, b = 0.7, 0.7, 0.7
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, lv)
        if ok and type(c) == "table" and c.r then r, g, b = c.r, c.g, c.b end
    end
    return string.format("|cff%02x%02x%02x%d|r", r * 255, g * 255, b * 255, lv)
end

--------------------------------------------------------------------------------
-- Changing a line on its way into a chat window
--------------------------------------------------------------------------------
local SHORT = {
    ["Guild"] = "G", ["Officer"] = "O", ["Party"] = "P", ["Party Leader"] = "PL", ["Party Guide"] = "PG", ["Raid"] = "R",
    ["Raid Leader"] = "RL", ["Raid Warning"] = "RW", ["Instance"] = "I", ["Instance Leader"] = "IL",
    ["Battleground"] = "BG", ["Battleground Leader"] = "BL",
}

local function ShortChannel(name)
    local n = name:match("^(%d+)%.")
    if n then return n end
    return SHORT[name] or name
end

local function Transform(text)
    if On("chatShortChannels") or On("chatNoBrackets") then
        text = text:gsub("(|Hchannel:[^|]*|h)%[(.-)%](|h)", function(open, name, close)
            if On("chatShortChannels") then name = ShortChannel(name) end
            if On("chatNoBrackets") then return open .. name .. close end
            return open .. "[" .. name .. "]" .. close
        end)
    end
    if On("chatLevels") then
        text = text:gsub("(|Hplayer:([^:|]+)[^|]*|h)(.-)(|h)", function(open, who, shown, close)
            local lv = LevelText(who)
            if not lv then return open .. shown .. close end
            if shown:find("%]$") then shown = shown:gsub("%]$", ":" .. lv .. "]")
            else shown = shown .. ":" .. lv end
            return open .. shown .. close
        end)
    end
    if On("chatTime") then
        local ts = GetCVar and GetCVar("showTimestamps")
        if not ts or ts == "none" then
            local fmt = TIME_FORMATS[tonumber(DB().chatTimeFormat) or 1] or TIME_FORMATS[1]
            text = "|cff8c8c8c" .. date(fmt) .. "|r " .. text
        end
    end
    return text
end

local wrapped = {}
local function Skip(frame)
    if frame == _G.COMBATLOG or frame.isCombatLog then return true end
    local id = frame.GetID and frame:GetID()
    local name = id and GetChatWindowInfo and GetChatWindowInfo(id)
    return name == "Combat Log" or name == "Meter"
end

local function Wrap(frame)
    if not frame or wrapped[frame] or type(frame.AddMessage) ~= "function" then return end
    wrapped[frame] = true
    local original = frame.AddMessage
    frame.AddMessage = function(self, text, ...)
        if type(text) == "string" and not Secret(text) and not Skip(self) then
            local ok, new = pcall(Transform, text)
            if ok and type(new) == "string" then text = new end
        end
        return original(self, text, ...)
    end
end

--------------------------------------------------------------------------------
-- Web links (click to copy) and keywords, done when the message arrives
--------------------------------------------------------------------------------
local function CopyBox(url)
    local f = _G.ForeverLazy_UrlBox
    if not f then
        f = CreateFrame("Frame", "ForeverLazy_UrlBox", UIParent)
        f:SetSize(460, 76)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.96)
        f.t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.t:SetPoint("TOPLEFT", 12, -10)
        f.t:SetText(L("Press Ctrl+C to copy the link, then Escape"))
        f.e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.e:SetSize(430, 24); f.e:SetPoint("TOPLEFT", 16, -34); f.e:SetAutoFocus(true)
        f.e:SetScript("OnEscapePressed", function() f:Hide() end)
        f.e:SetScript("OnEnterPressed", function() f:Hide() end)
        table.insert(UISpecialFrames, "ForeverLazy_UrlBox")
    end
    f:Show()
    f.e:SetText(url)
    f.e:SetFocus()
    f.e:HighlightText()
end

if hooksecurefunc then
    pcall(hooksecurefunc, "SetItemRef", function(link)
        if type(link) == "string" and link:find("^flurl:") then CopyBox((link:gsub("^flurl:", ""))) end
    end)
end

-- split a message into the parts that are plain text and the parts that are not (links, colour codes, textures)
local function MapPlain(text, fn)
    local out, pos = {}, 1
    local n = #text
    while pos <= n do
        local best, bestE
        for _, pat in ipairs({ "|H.-|h.-|h", "|c%x%x%x%x%x%x%x%x", "|r", "|T.-|t" }) do
            local s, e = text:find(pat, pos)
            if s and (not best or s < best) then best, bestE = s, e end
        end
        if not best then out[#out + 1] = fn(text:sub(pos)); break end
        if best > pos then out[#out + 1] = fn(text:sub(pos, best - 1)) end
        out[#out + 1] = text:sub(best, bestE)
        pos = bestE + 1
    end
    return table.concat(out)
end

local function Linkify(seg)
    return (seg:gsub("%S+", function(tok)
        local pre, core, post = tok:match("^([%(%[<\"']*)(.-)([%.,;:!%?%)%]>\"']*)$")
        if not core then return tok end
        local low = core:lower()
        if (low:find("^https?://") or low:find("^www%.")) and core:find("%.") then
            local clean = core:gsub("|", "")
            return pre .. "|Hflurl:" .. clean .. "|h|cff4db8ff[" .. clean .. "]|r|h" .. post
        end
        return tok
    end))
end

local function Words()
    local db = DB()
    local list, seen = {}, {}
    local function add(w)
        w = tostring(w or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #w >= 2 and not seen[w:lower()] then seen[w:lower()] = true; list[#list + 1] = w end
    end
    add(UnitName("player"))
    for w in tostring(db.chatWords or ""):gmatch("[^,]+") do add(w) end
    return list
end

local function Highlight(seg, words)
    local low = seg:lower()
    local out, pos, hit = {}, 1, false
    while pos <= #seg do
        local bs, be
        for _, w in ipairs(words) do
            local s, e = low:find(w:lower(), pos, true)
            if s and (not bs or s < bs) then bs, be = s, e end
        end
        if not bs then out[#out + 1] = seg:sub(pos); break end
        out[#out + 1] = seg:sub(pos, bs - 1)
        out[#out + 1] = "|cffffff00" .. seg:sub(bs, be) .. "|r"
        hit = true
        pos = be + 1
    end
    return table.concat(out), hit
end

local lastWordSound = 0
local function EventFilter(_, event, msg, author, ...)
    if type(msg) ~= "string" or Secret(msg) then return false end
    local changed = msg
    if On("chatLinks") then changed = MapPlain(changed, Linkify) end
    if On("chatWordsOn") and event ~= "CHAT_MSG_WHISPER_INFORM" and event ~= "CHAT_MSG_BN_WHISPER_INFORM" then
        local me = UnitName("player")
        if not (type(author) == "string" and not Secret(author) and Base(author) == me) then
            local words = Words()
            if #words > 0 then
                local hit
                changed = MapPlain(changed, function(seg)
                    local s, h = Highlight(seg, words)
                    if h then hit = true end
                    return s
                end)
                if hit and GetTime() - lastWordSound > 3 then
                    lastWordSound = GetTime()
                    pcall(PlaySound, (_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959, "Master")
                end
            end
        end
    end
    if changed ~= msg then return false, changed, author, ... end
    return false
end

if ChatFrame_AddMessageEventFilter then
    for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
                         "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
                         "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
                         "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER" }) do
        pcall(ChatFrame_AddMessageEventFilter, e, EventFilter)
    end
end

local whisper = CreateFrame("Frame")
pcall(whisper.RegisterEvent, whisper, "CHAT_MSG_WHISPER")
pcall(whisper.RegisterEvent, whisper, "CHAT_MSG_BN_WHISPER")
whisper:SetScript("OnEvent", function()
    if On("chatWhisperSound") then pcall(PlaySound, (_G.SOUNDKIT and _G.SOUNDKIT.TELL_MESSAGE) or 3081, "Master") end
end)

--------------------------------------------------------------------------------
-- Copy the text of a window
--------------------------------------------------------------------------------
function addon.ChatCopy(frame)
    frame = frame or _G.SELECTED_CHAT_FRAME or _G.ChatFrame1
    if not frame then return end
    local lines = {}
    local n = frame.GetNumMessages and frame:GetNumMessages() or 0
    for i = math.max(1, n - 400), n do
        local ok, text = pcall(frame.GetMessageInfo, frame, i)
        if ok and type(text) == "string" and not Secret(text) then lines[#lines + 1] = text end
    end
    local id = frame.GetID and frame:GetID()
    local name = id and GetChatWindowInfo and GetChatWindowInfo(id) or "chat"
    if #lines == 0 then lines[1] = "nothing to copy in this window yet" end
    if addon.ReportWindow then addon.ReportWindow("Chat: " .. tostring(name), lines) end
end

--------------------------------------------------------------------------------
-- How the windows behave
--------------------------------------------------------------------------------
local copyButtons = {}
local function CopyButton(frame)
    if copyButtons[frame] then return copyButtons[frame] end
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(18, 18)
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    b:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(); b.tex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    b:SetAlpha(0.25)
    b:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(L("Copy this chat window")); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:SetAlpha(0.25); GameTooltip:Hide() end)
    b:SetScript("OnClick", function() addon.ChatCopy(frame) end)
    copyButtons[frame] = b
    return b
end

-- a grip in the bottom-right corner to drag a window bigger or smaller, locked or not
local grips = {}
local function Grip(frame)
    if grips[frame] then return grips[frame] end
    local g = CreateFrame("Button", nil, frame)
    g:SetSize(16, 16)
    g:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    g:SetFrameLevel((frame:GetFrameLevel() or 1) + 6)
    g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    g:SetAlpha(0.3)
    g:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    g:SetScript("OnLeave", function(self) self:SetAlpha(0.3) end)
    g:SetScript("OnMouseDown", function() if frame.StartSizing then frame:StartSizing("BOTTOMRIGHT") end end)
    g:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        if FCF_SavePositionAndDimensions then pcall(FCF_SavePositionAndDimensions, frame) end
        if FCF_DockUpdate then pcall(FCF_DockUpdate) end
    end)
    grips[frame] = g
    return g
end

local hiddenButtons = {}
local function HideForever(obj)
    if not obj or hiddenButtons[obj] then return end
    hiddenButtons[obj] = true
    obj:Hide()
    if hooksecurefunc and obj.Show then pcall(hooksecurefunc, obj, "Show", function(self) self:Hide() end) end
end

local STICKY = { "SAY", "YELL", "EMOTE", "PARTY", "RAID", "RAID_WARNING", "GUILD", "OFFICER", "WHISPER", "BN_WHISPER", "CHANNEL", "INSTANCE_CHAT" }
local COLOUR = { "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "ACHIEVEMENT", "WHISPER", "WHISPER_INFORM", "PARTY",
                 "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "BATTLEGROUND", "BATTLEGROUND_LEADER", "INSTANCE_CHAT",
                 "INSTANCE_CHAT_LEADER" }

function addon.ChatApply()
    local db = DB()
    if not db then return end
    local n = _G.NUM_CHAT_WINDOWS or 10

    if db.chatClassColor == true and _G.ChatTypeInfo then
        for _, t in ipairs(COLOUR) do if ChatTypeInfo[t] then ChatTypeInfo[t].colorNameByClass = true end end
        for i = 1, 20 do if ChatTypeInfo["CHANNEL" .. i] then ChatTypeInfo["CHANNEL" .. i].colorNameByClass = true end end
    end
    if db.chatSticky == true and _G.ChatTypeInfo then
        for _, t in ipairs(STICKY) do if ChatTypeInfo[t] then ChatTypeInfo[t].sticky = 1 end end
    end
    if db.chatTabFade == true then
        _G.CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0
        _G.CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0
        _G.CHAT_FRAME_TAB_ALERTING_NOMOUSE_ALPHA = 0
    end
    if db.chatHideButtons == true then
        HideForever(_G.ChatFrameMenuButton)
        HideForever(_G.ChatFrameChannelButton)
        HideForever(_G.QuickJoinToastButton)
    end

    for i = 1, n do
        local frame = _G["ChatFrame" .. i]
        if frame then
            Wrap(frame)
            CopyButton(frame):SetShown(db.chatLinks == true)
            if db.chatResize == true then
                if frame.SetResizable then pcall(frame.SetResizable, frame, true) end
                local sw, sh = GetScreenWidth() or 1920, GetScreenHeight() or 1080
                if frame.SetResizeBounds then pcall(frame.SetResizeBounds, frame, 120, 60, sw, sh)
                else
                    if frame.SetMinResize then pcall(frame.SetMinResize, frame, 120, 60) end
                    if frame.SetMaxResize then pcall(frame.SetMaxResize, frame, sw, sh) end
                end
                Grip(frame):Show()
            elseif grips[frame] then
                grips[frame]:Hide()
            end
            if db.chatNoFade == true and frame.SetFading then pcall(frame.SetFading, frame, false) end
            if db.chatHistory == true and frame.SetMaxLines and not Skip(frame) then pcall(frame.SetMaxLines, frame, 1000) end
            if db.chatHideButtons == true then HideForever(_G["ChatFrame" .. i .. "ButtonFrame"]) end
            if db.chatEditTop == true then
                local eb = _G["ChatFrame" .. i .. "EditBox"]
                if eb then
                    eb:ClearAllPoints()
                    eb:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -5, 30)
                    eb:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 5, 30)
                end
            end
            -- size and font
            local size = tonumber(db.chatFontSize)
            if size and FCF_SetChatWindowFontSize then pcall(FCF_SetChatWindowFontSize, nil, frame, size) end
            local fontIdx = tonumber(db.chatFont) or 1
            local font = FONTS[fontIdx] and FONTS[fontIdx][2]
            if (font or db.chatFontOutline == true) and frame.SetFont then
                local _, curSize = frame:GetFont()
                pcall(frame.SetFont, frame, font or select(1, frame:GetFont()), size or curSize or 14, db.chatFontOutline == true and "OUTLINE" or "")
            end
        end
    end
end

-- windows made later (whisper tabs, new tabs) get the same treatment
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "UPDATE_CHAT_WINDOWS" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
    if C_Timer then C_Timer.After(event == "PLAYER_LOGIN" and 2 or 0.5, function() pcall(addon.ChatApply) end) else pcall(addon.ChatApply) end
end)
if hooksecurefunc then
    for _, fn in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow" }) do
        if _G[fn] then pcall(hooksecurefunc, fn, function() if C_Timer then C_Timer.After(0.2, function() pcall(addon.ChatApply) end) end end) end
    end
end

-- the usual set
function addon.ChatPreset()
    local db = DB()
    for _, k in ipairs({ "chatTime", "chatClassColor", "chatLevels", "chatShortChannels", "chatWordsOn", "chatLinks", "chatNoFade",
                         "chatHideButtons", "chatSticky", "chatHistory", "chatResize" }) do db[k] = true end
    addon.ChatApply()
    if addon.RefreshOptions then addon.RefreshOptions() end
    Print(L("chat: the usual set is on (timestamps, class colours, levels, short channels, keywords, copyable links, no fading, no side buttons, sticky channels, long history). Input box on top, tab fading, font and an extra whisper sound are in the options."))
end

--------------------------------------------------------------------------------
-- /lazy chat
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "chat" then
        local a, b = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
        a = (a or ""):lower()
        local db = DB()
        if a == "preset" then addon.ChatPreset(); return true
        elseif a == "copy" then addon.ChatCopy(); return true
        elseif a == "words" then
            db.chatWords = b
            db.chatWordsOn = true
            Print(L("chat keywords: ") .. (b ~= "" and b or "(only your own name)"))
            return true
        end
        local function s(k) return db[k] == true and "on" or "off" end
        Print(string.format(L("chat: timestamps %s, class colours %s, levels %s, short channels %s, keywords %s, copy links %s, input on top %s, no fade %s, sticky %s"),
            s("chatTime"), s("chatClassColor"), s("chatLevels"), s("chatShortChannels"), s("chatWordsOn"), s("chatLinks"), s("chatEditTop"), s("chatNoFade"), s("chatSticky")))
        Print(L("  /lazy chat preset   /lazy chat words a, b, c   /lazy chat copy   (all of it is in the options under Chat)"))
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["ChatTweaks.lua"] = true end end
