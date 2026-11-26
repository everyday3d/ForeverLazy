-- Paladin helpers, beside the blessing panel. Everything is off until ticked (options, My class) and only works on a paladin.
--   seal            a button for your seal: lights up when you have none. Point at it for a menu of your seals.
--   aura            the same for your aura: lights up when none of yours is on.
--   Righteous Fury  for tanking: lights up when it is missing, and says so when a fight starts without it.
--   cleanse         one button for me and each party member: it changes colour when there is something to take off.
--   /lazy paladin              what is on     /lazy paladin all | off     turn everything on or off
-- In the menus: left-click casts and keeps it as your pick, right-click only picks it. The game's rules: every cast needs its
-- own click, and addons cannot change what a button casts during a fight (colours and numbers still update).
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function Opt(key) local d = DB(); return d and d[key] == true end

local KEYS = { "palSeal", "palAura", "palFury", "palCleanse" }
local SEALS = { "Seal of Righteousness", "Seal of Command", "Seal of the Crusader", "Seal of Wisdom", "Seal of Light", "Seal of Justice", "Seal of Fury" }
local AURAS = { "Devotion Aura", "Retribution Aura", "Concentration Aura", "Sanctity Aura", "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" }
local FURY = "Righteous Fury"
-- what a button warns about when this little is left (seconds). Seals are short, so only the last few seconds
local KINDS = {
    seal = { option = "palSeal", pick = "palSealPick", list = SEALS, label = "Seal", soon = 5 },
    aura = { option = "palAura", pick = "palAuraPick", list = AURAS, label = "Aura", soon = 0, mine = true },
    fury = { option = "palFury", list = { FURY }, label = "Righteous Fury", soon = 60 },
}
local ORDER = { "seal", "aura", "fury" }

local function IsPaladin()
    local _, class = UnitClass("player")
    return class == "PALADIN"
end

--------------------------------------------------------------------------------
-- The rules (no game needed: tests/paladin.lua)
--------------------------------------------------------------------------------
local P = {}
addon.Paladin = P

-- what the button casts: my pick when I still know it, else the first one I know
function P.Pick(picked, list, known)
    if picked and known[picked] then return picked end
    for _, s in ipairs(list) do if known[s] then return s end end
    return nil
end

function P.MenuList(list, known)
    local out = {}
    for _, s in ipairs(list) do if known[s] then out[#out + 1] = s end end
    return out
end

-- which of a list is on me: buffs are { name =, left = seconds or nil, source = unit or nil }. mine: only one I cast counts
-- (another paladin's aura shows among my buffs too)
function P.Active(buffs, list, mine)
    for _, b in ipairs(buffs) do
        for _, s in ipairs(list) do
            if b.name == s and not (mine and b.source and b.source ~= "player") then return b end
        end
    end
    return nil
end

function P.Needs(found, soon)
    if not found then return true end
    return found.left ~= nil and found.left < soon
end

-- what a cleanse could take off someone: debuffs is a list of kinds. Poison first, then disease, then magic
function P.CleanseKind(kinds, canCure, canMagic)
    local has = {}
    for _, k in ipairs(kinds) do has[k] = true end
    if canCure and has.Poison then return "Poison" end
    if canCure and has.Disease then return "Disease" end
    if canMagic and has.Magic then return "Magic" end
    return nil
end

-- the panel's own size
local function Settings() return DB() end
function P.Scale()
    return math.max(0.5, math.min(2, tonumber(Settings() and Settings().palScale) or 1))
end

--------------------------------------------------------------------------------
-- Reading the game
--------------------------------------------------------------------------------
local function Plain(v) return not (issecretvalue and issecretvalue(v)) end

local known = {}
local function ReadSpells()
    if addon.SpellsKnown then known = addon.SpellsKnown() end
end

local function Texture(spell)
    return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell)) or (GetSpellTexture and GetSpellTexture(spell))
end

-- the auras on a unit ("HELPFUL" or "HARMFUL"); nil when the game hides them
local function Read(unit, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local out = {}
    local now = GetTime()
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok then return nil end
        if not a then break end
        if not (Plain(a.name) and Plain(a.dispelName) and Plain(a.expirationTime) and Plain(a.sourceUnit)) then return nil end
        local left = (a.expirationTime and a.expirationTime > 0) and (a.expirationTime - now) or nil
        out[#out + 1] = { name = a.name, left = left, source = a.sourceUnit, kind = a.dispelName }
    end
    return out
end

local function TimeText(left)
    if not left or left <= 0 then return "" end
    if left >= 60 then return string.format("%dm", math.floor(left / 60)) end
    return string.format("%d", math.ceil(left))
end

--------------------------------------------------------------------------------
-- The panel and its pop-out menus
--------------------------------------------------------------------------------
local frame
local buttons, menus, cleanse = {}, {}, {}
local waiting, toldCombatPick = false, false

local function Tip(owner, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i, line in ipairs(lines) do
        if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

local function Cell(name, width, height, tip, parent, template)
    local b = CreateFrame("Button", name, parent or frame, template or "SecureActionButtonTemplate")
    b:SetSize(width, height)
    -- secure buttons fire on the key-down or key-up edge depending on the ActionButtonUseKeyDown setting, so listen for both
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(); b.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    -- hooked, not set: some buttons carry the game's own enter and leave scripts, which must stay
    if tip then
        b:HookScript("OnEnter", function(self) Tip(self, tip(self)) end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

local function CastMacro(button, mouse, text)
    local n = mouse == "right" and "2" or "1"
    button:SetAttribute("type" .. n, text and "macro" or nil)
    button:SetAttribute("macrotext" .. n, text)
end

-- opening a menu during a fight takes the game's own "secure" enter script, which runs these lines for us
local ON_ENTER = [[
    for i = 1, 2 do
        local other = self:GetFrameRef("menu" .. i)
        if other then other:Hide() end
    end
    local menu = self:GetFrameRef("mine")
    if menu then
        menu:Show()
        menu:UnregisterAutoHide()
        menu:RegisterAutoHide(0.4)
        menu:AddToAutoHide(self)
    end
]]

local function Picked(kind, spell)
    if InCombatLockdown() then
        if not toldCombatPick then
            toldCombatPick = true
            Print(L("cast. Your usual one stays until you pick another outside a fight."))
        end
        return
    end
    DB()[KINDS[kind].pick] = spell
    for _, m in pairs(menus) do m:Hide() end
    addon.PaladinRefresh()
end

local function MenuButton(menu, i)
    local b = menu.buttons[i]
    if b then return b end
    b = Cell("ForeverLazy_PaladinMenu_" .. menu.kind .. i, 30, 30, function(self)
        return { self.spell or "", L("Left-click: cast it, and keep it as your pick. Right-click: only pick it.") }
    end, menu)
    -- only on the release: the spell goes out then, with what the button holds
    b:HookScript("PostClick", function(self, _, down)
        if down or not self.spell then return end
        Picked(menu.kind, self.spell)
    end)
    menu.buttons[i] = b
    return b
end

local function MakeMenu(index, kind, button)
    local name = "ForeverLazy_PaladinMenu_" .. kind
    local ok, menu = pcall(CreateFrame, "Frame", name, button, "SecureHandlerBaseTemplate")
    if not ok or not menu then menu = CreateFrame("Frame", name, button) end
    menu:SetFrameStrata("HIGH")
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.85)
    menu.index, menu.kind, menu.buttons = index, kind, {}
    menu:Hide()
    menus[kind] = menu
    return menu
end

local function WireMenus()
    local secure = SecureHandlerSetFrameRef ~= nil
    local list = { "seal", "aura" }
    for i, kind in ipairs(list) do
        local b = buttons[kind]
        if secure and b.secureEnter then
            local ok = pcall(function()
                SecureHandlerSetFrameRef(b, "mine", menus[kind])
                for j, other in ipairs(list) do if j ~= i then SecureHandlerSetFrameRef(b, "menu" .. j, menus[other]) end end
                b:SetAttribute("_onenter", ON_ENTER)
            end)
            if not ok then secure = false end
        else
            secure = false
        end
    end
    if not secure then
        for _, kind in ipairs(list) do
            local b, away = buttons[kind], 0
            b:HookScript("OnEnter", function()
                if InCombatLockdown() then return end
                for k, m in pairs(menus) do m:SetShown(k == kind and (m.count or 0) > 0) end
            end)
            menus[kind]:SetScript("OnUpdate", function(self, dt)
                if InCombatLockdown() then return end
                if (self.IsMouseOver and self:IsMouseOver()) or (b.IsMouseOver and b:IsMouseOver()) then away = 0
                else away = away + dt; if away > 0.4 then away = 0; self:Hide() end end
            end)
        end
    end
    P.menusWorkInCombat = secure
end

local function FillMenu(menu, pick)
    local list = P.MenuList(KINDS[menu.kind].list, known)
    menu.count = #list
    local d = DB()
    local sideways, flip = d.palVertical == true, d.palMenuFlip == true
    for i, spell in ipairs(list) do
        local b = MenuButton(menu, i)
        b.spell = spell
        CastMacro(b, "left", "/cast " .. spell)
        b.icon:SetTexture(Texture(spell))
        local chosen = spell == pick
        b.bg:SetColorTexture(chosen and 1 or 0.15, chosen and 0.82 or 0.15, chosen and 0 or 0.15, 1)
        b:ClearAllPoints()
        if sideways then
            if flip then b:SetPoint("RIGHT", menu, "RIGHT", -2 - (i - 1) * 32, 0) else b:SetPoint("LEFT", menu, "LEFT", 2 + (i - 1) * 32, 0) end
        else
            if flip then b:SetPoint("TOP", menu, "TOP", 0, -2 - (i - 1) * 32) else b:SetPoint("BOTTOM", menu, "BOTTOM", 0, 2 + (i - 1) * 32) end
        end
        b:Show()
    end
    for i = #list + 1, #menu.buttons do menu.buttons[i]:Hide() end
    local length = #list * 32 + 2
    local anchor = buttons[menu.kind]
    menu:ClearAllPoints()
    if sideways then
        menu:SetSize(length, 34)
        if flip then menu:SetPoint("RIGHT", anchor, "LEFT", 0, 0) else menu:SetPoint("LEFT", anchor, "RIGHT", 0, 0) end
    else
        menu:SetSize(34, length)
        if flip then menu:SetPoint("TOP", anchor, "BOTTOM", 0, 0) else menu:SetPoint("BOTTOM", anchor, "TOP", 0, 0) end
    end
end

local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_Paladin", UIParent)
    f:SetSize(176, 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
    local title = CreateFrame("Button", nil, f)
    title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT"); title:SetHeight(16)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() if not DB().palLocked and not InCombatLockdown() then f:StartMoving() end end)
    title:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        DB().pos = DB().pos or {}
        DB().pos.paladin = { point = point, x = x, y = y }
    end)
    local label = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 6, 0); label:SetText(L("Paladin"))
    frame = f

    for _, kind in ipairs(ORDER) do
        local k = KINDS[kind]
        local hasMenu = kind ~= "fury"
        local name = "ForeverLazy_Paladin_" .. kind
        local b
        if hasMenu then
            -- no tooltip on these: the menu takes its place
            local made, c = pcall(Cell, name, 40, 40, nil, nil, "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate")
            if made and c then b = c; b.secureEnter = true else b = Cell(name, 40, 40, nil) end
        else
            b = Cell(name, 40, 40, function(self) return { L(k.label), L("Click: cast it. Red means it is not on you.") } end)
        end
        b.kind = kind
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.name:SetPoint("TOP", b, "BOTTOM", 0, -1)
        b.name:SetText(L(kind == "fury" and "Fury" or k.label))
        buttons[kind] = b
        if hasMenu then MakeMenu(kind == "seal" and 1 or 2, kind, b) end
    end
    WireMenus()

    for i, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        local c = Cell("ForeverLazy_Cleanse" .. i, 32, 24, function()
            return { (UnitExists(unit) and UnitName(unit)) or L("nobody here"),
                L("Click: take it off. Green = poison, brown = disease, blue = magic.") }
        end)
        c.icon:Hide()
        c.unit = unit
        cleanse[i] = c
    end
    f:Hide()
end

local function Place()
    local p = DB().pos and DB().pos.paladin or { point = "LEFT", x = 20, y = -80 }
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    frame:SetScale(P.Scale())
end

--------------------------------------------------------------------------------
-- Colours and numbers (allowed during a fight)
--------------------------------------------------------------------------------
local furyMissing = false

local function Paint()
    if not frame or not frame:IsShown() then return end
    local buffs = Read("player", "HELPFUL")
    for _, kind in ipairs(ORDER) do
        local b, k = buttons[kind], KINDS[kind]
        if b and Opt(k.option) and b.spell then
            if not buffs then
                b.bg:SetColorTexture(0.35, 0.35, 0.35, 0.9)          -- the game is hiding buffs: neither red nor fine
                b.text:SetText("?")
                if kind == "fury" then furyMissing = false end
            else
                local found = P.Active(buffs, k.list, k.mine)
                local need = P.Needs(found, k.soon)
                b.bg:SetColorTexture(need and 0.75 or 0.15, need and 0.15 or 0.55, need and 0.1 or 0.15, 0.95)
                b.text:SetText(found and TimeText(found.left) or "")
                if kind == "fury" then furyMissing = not found end
            end
        end
    end
    if Opt("palCleanse") and cleanse[1] then
        local canMagic = known["Cleanse"] and true or false
        local canCure = canMagic or (known["Purify"] and true or false)
        for _, c in ipairs(cleanse) do
            if UnitExists(c.unit) then
                local kinds = {}
                for _, a in ipairs(Read(c.unit, "HARMFUL") or {}) do kinds[#kinds + 1] = a.kind end
                local kind = P.CleanseKind(kinds, canCure, canMagic)
                local name = UnitName(c.unit)
                c.text:SetText(type(name) == "string" and Plain(name) and name:sub(1, 4) or "")
                if kind == "Poison" then c.bg:SetColorTexture(0.1, 0.75, 0.15, 1)
                elseif kind == "Disease" then c.bg:SetColorTexture(0.6, 0.4, 0.05, 1)
                elseif kind == "Magic" then c.bg:SetColorTexture(0.15, 0.4, 0.9, 1)
                else c.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
            else
                c.text:SetText("")
                c.bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- What the buttons cast and where they sit (between fights only: they are secure buttons)
--------------------------------------------------------------------------------
local function Refresh()
    local d = DB()
    if not d then return end
    local wanted = IsPaladin() and (Opt("palSeal") or Opt("palAura") or Opt("palFury") or Opt("palCleanse"))
    if InCombatLockdown() then waiting = true; return end
    waiting = false
    if not wanted then
        if frame then frame:Hide() end
        return
    end
    ReadSpells()
    if not frame then Build() end
    local tall = d.palVertical == true
    local y, shownRow = -18, 0
    for _, kind in ipairs(ORDER) do
        local b, k = buttons[kind], KINDS[kind]
        local pick = P.Pick(k.pick and d[k.pick], k.list, known)
        b.spell = pick
        CastMacro(b, "left", pick and ("/cast " .. pick) or nil)
        b.icon:SetTexture(pick and Texture(pick) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local show = Opt(k.option) and pick ~= nil
        b:SetShown(show)
        if show then
            b:ClearAllPoints()
            if tall then b:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, y - shownRow * 54)
            else b:SetPoint("TOPLEFT", frame, "TOPLEFT", 5 + shownRow * 46, y) end
            shownRow = shownRow + 1
        end
        if menus[kind] then FillMenu(menus[kind], pick) end
    end
    if shownRow > 0 then y = y - (tall and shownRow * 54 or 54) end

    local spell = (known["Cleanse"] and "Cleanse") or (known["Purify"] and "Purify") or nil
    local showCleanse = Opt("palCleanse") and spell ~= nil
    for i, c in ipairs(cleanse) do
        CastMacro(c, "left", spell and ("/cast [@" .. c.unit .. ",help,nodead] " .. spell) or nil)
        c:SetShown(showCleanse)
        if showCleanse then
            c:SetSize(tall and 90 or 32, tall and 20 or 24)
            c:ClearAllPoints()
            if tall then c:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, y - (i - 1) * 22)
            else c:SetPoint("TOPLEFT", frame, "TOPLEFT", 5 + (i - 1) * 33.5, y) end
        end
    end
    if showCleanse then y = y - (tall and (#cleanse * 22 + 3) or 27) end

    if y == -18 then frame:Hide(); return end           -- nothing learned yet that the ticked helpers could use
    frame:SetSize(tall and 100 or 176, -y + 3)
    Place()
    frame:Show()
    Paint()
end
addon.PaladinRefresh = Refresh

--------------------------------------------------------------------------------
-- Keeping it fresh
--------------------------------------------------------------------------------
local pending
local function Soon()
    if pending or not (C_Timer and C_Timer.After) then return end
    pending = true
    C_Timer.After(0.5, function() pending = false; pcall(Refresh) end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE", "UNIT_AURA" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if not IsPaladin() then return end
    if event == "UNIT_AURA" then
        if type(unit) == "string" and (unit == "player" or unit:find("^party")) then pcall(Paint) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        pcall(Paint)
        if Opt("palFury") and known[FURY] and furyMissing then Print(L("you are fighting without Righteous Fury")) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if waiting then Soon() end
    else
        pcall(ReadSpells)
        Soon()
    end
end)
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    if IsPaladin() then pcall(Paint) end
end)

--------------------------------------------------------------------------------
-- /lazy paladin
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "paladin" or c == "pally" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "all" or a == "off" then
            for _, k in ipairs(KEYS) do db[k] = (a == "all") or nil end
            if addon.RefreshOptions then addon.RefreshOptions() end
        end
        local on = 0
        for _, k in ipairs(KEYS) do if db[k] == true then on = on + 1 end end
        Print(string.format(L("paladin helpers: %d of %d on (/lazy paladin all|off, or the options under My class)"), on, #KEYS))
        if not IsPaladin() then Print(L("they only work on a paladin")) end
        pcall(Refresh)
        if frame and P.menusWorkInCombat ~= nil then
            Print(P.menusWorkInCombat and L("the seal and aura menus are set up to open during fights")
                or L("this client would not set up the menus for fights: they open between fights only"))
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Paladin.lua"] = true end end
