-- Shaman helpers. Everything is off until ticked (options, My class) and only works on a shaman.
--   totem bar      your four totems with time left; left-click an element drops the totem picked for it. Point at an element
--                  and all its totems pop out: left-click one drops it and keeps it as the pick, right-click only picks it.
--                  One more button drops the whole set, one totem a click. Three sets: Solo, Dungeon, Healing.
--   the panel      has its own size and lock, and can lie across or stand up and down
--   range          says so when I have walked away from my totems (outdoors only: the game gives no position inside)
--   weapon, shield buttons that light up when the weapon buff or the shield is missing or about to run out
--   ankhs          how many I carry and whether Reincarnation is ready, with a warning when they run low
--   cure           one button for me and each party member: it changes colour when there is a poison or disease to cure
--   purge          a mark on an enemy's nameplate while it has a magic buff Purge can take off
--   ghost wolf     a reminder on a long run
--   /lazy shaman              what is on     /lazy shaman all | off     turn everything on or off
-- The game's rules: every cast needs its own click, and addons cannot change what a button casts during a fight (colours and
-- numbers still update).
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function Opt(key) local d = DB(); return d and d[key] == true end

local KEYS = { "shamTotemBar", "shamTotemRange", "shamImbue", "shamShield", "shamAnkh", "shamCure", "shamPurge", "shamWolf" }

local function IsShaman()
    local _, class = UnitClass("player")
    return class == "SHAMAN"
end

-- the game's totem slots: 1 fire, 2 earth, 3 water, 4 air. Shown in the order Earth, Fire, Water, Air.
local ELEMENTS = {
    { key = "earth", slot = 2, name = "Earth", color = { 0.55, 0.4, 0.15 },
      totems = { "Strength of Earth Totem", "Stoneskin Totem", "Tremor Totem", "Earthbind Totem", "Stoneclaw Totem" } },
    { key = "fire", slot = 1, name = "Fire", color = { 0.7, 0.2, 0.1 },
      totems = { "Searing Totem", "Magma Totem", "Fire Nova Totem", "Flametongue Totem", "Frost Resistance Totem" } },
    { key = "water", slot = 3, name = "Water", color = { 0.1, 0.35, 0.7 },
      totems = { "Healing Stream Totem", "Mana Spring Totem", "Mana Tide Totem", "Poison Cleansing Totem", "Disease Cleansing Totem", "Fire Resistance Totem" } },
    { key = "air", slot = 4, name = "Air", color = { 0.35, 0.55, 0.65 },
      totems = { "Windfury Totem", "Grace of Air Totem", "Grounding Totem", "Windwall Totem", "Nature Resistance Totem", "Tranquil Air Totem", "Sentry Totem" } },
}
local SETS = { "Solo", "Dungeon", "Healing" }
local IMBUES = { "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon" }
local SHIELDS = { "Lightning Shield", "Water Shield" }
local RECALLS = { "Totemic Recall", "Totemic Call" }        -- brings my totems back; the name differs between versions
local ANKH = 17030
local RANGE = 20                 -- yards: how far most totems reach
local SOON = 10                  -- seconds left on a totem before its time turns red
local BUFF_SOON = 60             -- seconds left on a weapon buff or shield before its button lights up

--------------------------------------------------------------------------------
-- The rules (no game needed: tests/shaman.lua)
--------------------------------------------------------------------------------
local S = {}
addon.Shaman = S

-- what happened to one element's totem between two looks: before and after are { name, start, duration } or nil
function S.TotemEvent(before, after, now)
    if not before then return nil end
    if after then return nil end                                   -- the same one, or a new one I dropped over it
    local left = before.start + before.duration - now
    if left > 2 then return "gone" end                             -- destroyed or recalled early
    return "expired"
end

-- the macro that drops a set one totem a click; nil when the set is empty
function S.Sequence(names)
    local list = {}
    for _, n in ipairs(names) do if n and n ~= "" then list[#list + 1] = n end end
    if #list == 0 then return nil end
    return "/castsequence reset=15/combat " .. table.concat(list, ", ")
end

-- what an element drops: my pick when I still know it, "none" when I want nothing, else the first one I know
function S.Pick(picked, totems, known)
    if picked == "none" then return nil end
    if picked and known[picked] then return picked end
    for _, t in ipairs(totems) do if known[t] then return t end end
    return nil
end

-- the next choice when right-clicking: every one I know, then none
function S.Next(current, totems, known, step)
    local list = {}
    for _, t in ipairs(totems) do if known[t] then list[#list + 1] = t end end
    list[#list + 1] = "none"
    local at = #list
    for i, v in ipairs(list) do if v == (current or "none") then at = i end end
    return list[(at - 1 + step) % #list + 1]
end

-- does a weapon buff or shield need doing again? has: it is on me; left: seconds left, nil when it has no end
function S.NeedsRefresh(has, left)
    if not has then return true end
    return left ~= nil and left < BUFF_SOON
end

-- what can be cured on someone: debuffs is a list of kinds ("Poison", "Disease", "Magic" ...)
function S.CureKind(debuffs, canPoison, canDisease)
    local poison, disease = false, false
    for _, kind in ipairs(debuffs) do
        if kind == "Poison" and canPoison then poison = true end
        if kind == "Disease" and canDisease then disease = true end
    end
    if poison then return "Poison" end
    if disease then return "Disease" end
    return nil
end

-- remind about Ghost Wolf? s: { ranFor, since (seconds since the last reminder), combat, mounted, indoors, wolf, taxi, swimming }
function S.WolfNudge(s)
    if s.combat or s.mounted or s.indoors or s.wolf or s.taxi or s.swimming then return false end
    return s.ranFor >= 8 and s.since >= 300
end

function S.TimeText(left)
    if not left or left <= 0 then return "" end
    if left >= 60 then return string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)) end
    return string.format("%d", math.ceil(left))
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

-- the kinds of aura on a unit: "HARMFUL" or "HELPFUL". Nil when the game hides them.
local function Auras(unit, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local out = {}
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok then return nil end
        if not a then break end
        if not (Plain(a.name) and Plain(a.dispelName) and Plain(a.expirationTime)) then return nil end
        out[#out + 1] = a
    end
    return out
end

local function TotemNow(slot)
    if not GetTotemInfo then return nil end
    local ok, have, name, start, duration, icon = pcall(GetTotemInfo, slot)
    if not ok or not (Plain(have) and Plain(name) and Plain(start) and Plain(duration)) then return nil, true end
    if not have or not name or name == "" or (duration or 0) <= 0 or start + duration <= GetTime() then return nil end
    return { name = name, start = start, duration = duration, icon = icon }
end

local function Position()
    local hbd = ns.api and ns.api.hbd
    if not hbd then return nil end
    return hbd:GetPlayerWorldPosition()
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------
local frame
local cells, cureCells = {}, {}
local setButton, dropButton, recallButton, imbueButton, shieldButton, ankhText
local recalledAt = -100            -- when I last recalled my totems: they are not "gone" then, I took them
local totems = {}          -- element key -> { name, start, duration, x, y, inst, warnedFar }
local waiting = false

-- the panel used to follow the arrows' size and lock: the first time, it takes them over as they are
local function Own()
    local d = DB()
    if not d then return nil end
    if not d.shamSplit then
        d.shamSplit = true
        d.shamScale = tonumber(d.scale) or 1
        d.shamLocked = d.locked == true
    end
    return d
end
S.Settings = Own
function S.Scale()
    local d = Own()
    return math.max(0.5, math.min(2, tonumber(d and d.shamScale) or 1))
end

local function SetName()
    local d = DB()
    return (d and d.shamSet) or SETS[1]
end
local function Choices()
    local d = DB()
    d.shamTotems = d.shamTotems or {}
    d.shamTotems[SetName()] = d.shamTotems[SetName()] or {}
    return d.shamTotems[SetName()]
end

local function Tip(owner, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i, line in ipairs(lines) do
        if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

-- a secure button with an icon, a line of text under or on it, and a tooltip
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

--------------------------------------------------------------------------------
-- The pop-out menu of an element's totems
--------------------------------------------------------------------------------
-- Opening a menu during a fight takes the game's own "secure" enter script, which runs these few lines for us. The menu closes
-- by itself a moment after the mouse leaves it and its button. Where the client has no such thing, the menu works between
-- fights only.
local ON_ENTER = [[
    for i = 1, 4 do
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
local menus = {}
local toldCombatPick = false

-- what the menu of an element lists: every totem of it I know, then "none"
function S.MenuList(totemList, knownSpells)
    local list = {}
    for _, t in ipairs(totemList) do if knownSpells[t] then list[#list + 1] = t end end
    if #list > 0 then list[#list + 1] = "none" end
    return list
end

-- a click in a menu has happened (the cast, if any, is already out): remember the pick. The game does not let an addon change
-- what a button casts during a fight, so then the old pick stays
local function Picked(element, totem)
    if InCombatLockdown() then
        if not toldCombatPick then
            toldCombatPick = true
            Print(L("dropped. Your usual totem for this slot stays until you pick one outside a fight."))
        end
        return
    end
    Choices()[element.key] = totem
    for _, m in ipairs(menus) do m:Hide() end
    addon.ShamanRefresh()
end

local function MenuButton(menu, element, i)
    local b = menu.buttons[i]
    if b then return b end
    b = Cell("ForeverLazy_TotemMenu" .. menu.index .. "_" .. i, 30, 30, function(self)
        if self.totem == "none" then return { L("None"), L("Leave this element out of the set.") } end
        return { self.totem or "", L("Left-click: drop it, and keep it as your pick. Right-click: only pick it.") }
    end, menu)
    -- only on the release: the spell goes out then, with what the button holds
    b:HookScript("PostClick", function(self, _, down)
        if down or not self.totem then return end
        Picked(element, self.totem)
    end)
    menu.buttons[i] = b
    return b
end

local function MakeMenu(index, element, cell)
    local ok, menu = pcall(CreateFrame, "Frame", "ForeverLazy_TotemMenu" .. index, cell, "SecureHandlerBaseTemplate")
    if not ok or not menu then menu = CreateFrame("Frame", "ForeverLazy_TotemMenu" .. index, cell) end
    menu:SetFrameStrata("HIGH")
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.85)
    menu.index, menu.element, menu.buttons = index, element, {}
    menu:Hide()
    menus[index] = menu
    return menu
end

-- tell each element button about the menus. Returns true when the menus can open during a fight too
local function WireMenus()
    local secure = SecureHandlerSetFrameRef ~= nil
    for i, c in ipairs(cells) do
        if secure and c.secureEnter then
            local ok = pcall(function()
                SecureHandlerSetFrameRef(c, "mine", menus[i])
                for j = 1, #menus do if j ~= i then SecureHandlerSetFrameRef(c, "menu" .. j, menus[j]) end end
                c:SetAttribute("_onenter", ON_ENTER)
            end)
            if not ok then secure = false end
        else
            secure = false
        end
    end
    if not secure then
        for i, c in ipairs(cells) do
            if not c.plainEnter then
                c.plainEnter = true
                c:HookScript("OnEnter", function()
                    if InCombatLockdown() then return end
                    for j, m in ipairs(menus) do m:SetShown(j == i and (m.count or 0) > 0) end
                end)
                local away = 0
                menus[i]:SetScript("OnUpdate", function(self, dt)
                    if InCombatLockdown() then return end
                    if (self.IsMouseOver and self:IsMouseOver()) or (c.IsMouseOver and c:IsMouseOver()) then away = 0
                    else away = away + dt; if away > 0.4 then away = 0; self:Hide() end end
                end)
            end
        end
    end
    S.menusWorkInCombat = secure
    return secure
end

-- fill a menu and lay it out beside its element button (between fights only)
local function FillMenu(menu, pick)
    local element = menu.element
    local list = S.MenuList(element.totems, known)
    menu.count = #list
    local d = Own()
    local sideways = d.shamVertical == true          -- a standing panel opens its menus to the side
    local flip = d.shamMenuFlip == true
    for i, totem in ipairs(list) do
        local b = MenuButton(menu, element, i)
        b.totem = totem
        local cast = totem ~= "none" and ("/cast " .. totem) or nil
        b:SetAttribute("type1", cast and "macro" or nil)
        b:SetAttribute("macrotext1", cast)
        b.icon:SetTexture(totem == "none" and "Interface\\Buttons\\UI-GroupLoot-Pass-Up" or Texture(totem))
        local chosen = totem == (pick or "none")
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
    local cell = menu:GetParent()
    menu:ClearAllPoints()
    if sideways then
        menu:SetSize(length, 34)
        if flip then menu:SetPoint("RIGHT", cell, "LEFT", 0, 0) else menu:SetPoint("LEFT", cell, "RIGHT", 0, 0) end
    else
        menu:SetSize(34, length)
        if flip then menu:SetPoint("TOP", cell, "BOTTOM", 0, 0) else menu:SetPoint("BOTTOM", cell, "TOP", 0, 0) end
    end
end

local function Build()
    local f = CreateFrame("Frame", "ForeverLazy_Shaman", UIParent)
    f:SetSize(176, 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
    local title = CreateFrame("Button", nil, f)
    title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT"); title:SetHeight(16)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() if not Own().shamLocked and not InCombatLockdown() then f:StartMoving() end end)
    title:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        DB().pos = DB().pos or {}
        DB().pos.shaman = { point = point, x = x, y = y }
    end)
    local label = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 6, 0); label:SetText(L("Shaman"))
    frame = f

    for i, e in ipairs(ELEMENTS) do
        local made, c = pcall(Cell, "ForeverLazy_Totem" .. i, 40, 40, nil, nil, "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate")
        if made and c then c.secureEnter = true else c = Cell("ForeverLazy_Totem" .. i, 40, 40, nil) end
        c.element = e
        c:HookScript("OnClick", function(self, mouse, down)
            if down or mouse ~= "RightButton" then return end
            if InCombatLockdown() then Print(L("totems can be picked again after the fight")); return end
            Choices()[e.key] = S.Next(self.pick or "none", e.totems, known, IsShiftKeyDown() and -1 or 1)
            addon.ShamanRefresh()
        end)
        cells[i] = c
        MakeMenu(i, e, c)
    end
    WireMenus()

    setButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    setButton:SetSize(66, 22)
    setButton:SetScript("OnClick", function()
        if InCombatLockdown() then Print(L("the totem set can be changed after the fight")); return end
        local at = 1
        for i, n in ipairs(SETS) do if n == SetName() then at = i end end
        DB().shamSet = SETS[at % #SETS + 1]
        addon.ShamanRefresh()
    end)
    setButton:SetScript("OnEnter", function(self) Tip(self, { L("Totem set"), L("Click to switch between Solo, Dungeon and Healing. Each remembers its own totems.") }) end)
    setButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    dropButton = Cell("ForeverLazy_TotemSet", 102, 22, function(self)
        local key = GetBindingKey and GetBindingKey("CLICK ForeverLazy_DropTotems:LeftButton")
        return { L("Drop the set"), L("Each click drops the next totem of the set. It starts over after 15 seconds or after a fight."), self.list or "",
            key and (L("Key: ") .. key) or L("To give it a key: game key bindings, AddOns, Forever Lazy.") }
    end)
    dropButton.icon:Hide()
    dropButton.bg:SetColorTexture(0.1, 0.35, 0.1, 0.9)
    dropButton.text:SetText(L("Drop the set"))

    recallButton = Cell("ForeverLazy_TotemRecall", 22, 22, function(self)
        return { self.spell or L("Recall"), L("Takes your totems back.") }
    end)
    recallButton.icon:ClearAllPoints()
    recallButton.icon:SetPoint("TOPLEFT", 1, -1); recallButton.icon:SetPoint("BOTTOMRIGHT", -1, 1)

    local function BuffButton(name, what, choices, dbKey)
        local b = Cell(name, 84, 26, function(self)
            return { L(what) .. ": " .. (self.pick or "-"), L("Left-click: cast it. Right-click: pick another (between fights).") }
        end)
        b.icon:ClearAllPoints(); b.icon:SetPoint("LEFT", 2, 0); b.icon:SetSize(22, 22)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 28, 0)
        b.choices, b.dbKey = choices, dbKey
        b:HookScript("OnClick", function(self, mouse, down)
            if down or mouse ~= "RightButton" then return end
            if InCombatLockdown() then Print(L("pick another one after the fight")); return end
            DB()[dbKey] = S.Next(self.pick or "none", choices, known, IsShiftKeyDown() and -1 or 1)
            addon.ShamanRefresh()
        end)
        return b
    end
    imbueButton = BuffButton("ForeverLazy_Imbue", "Weapon buff", IMBUES, "shamImbuePick")
    shieldButton = BuffButton("ForeverLazy_Shield", "Shield", SHIELDS, "shamShieldPick")

    ankhText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    for i, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        local c = Cell("ForeverLazy_Cure" .. i, 32, 24, function(self)
            return { (UnitExists(unit) and UnitName(unit)) or L("nobody here"),
                L("Left-click: Cure Poison. Right-click: Cure Disease. Green = poisoned, brown = diseased.") }
        end)
        c.icon:Hide()
        c.unit = unit
        cureCells[i] = c
    end
    f:Hide()
end

local function Place()
    local p = DB().pos and DB().pos.shaman or { point = "LEFT", x = 20, y = -80 }
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    frame:SetScale(S.Scale())
end

--------------------------------------------------------------------------------
-- Colours and numbers (allowed during a fight)
--------------------------------------------------------------------------------
local function PaintTotems()
    local now = GetTime()
    local px, py, inst = Position()
    for i, e in ipairs(ELEMENTS) do
        local c = cells[i]
        local t, hidden = TotemNow(e.slot)
        if not hidden then
            local before = totems[e.key]
            local event = S.TotemEvent(before, t, now)
            if event == "gone" and Opt("shamTotemBar") and now - recalledAt > 3 then Print(string.format(L("your %s is gone"), before.name)) end
            if t and (not before or before.start ~= t.start or before.name ~= t.name) then
                -- just dropped: it stands where I stand now
                totems[e.key] = { name = t.name, start = t.start, duration = t.duration, x = px, y = py, inst = inst }
            elseif not t then
                totems[e.key] = nil
            end
        end
        local mine = totems[e.key]
        local far = false
        if mine and Opt("shamTotemRange") and px and mine.x and mine.inst == inst then
            far = math.sqrt((px - mine.x) ^ 2 + (py - mine.y) ^ 2) > RANGE
            if far and not mine.warnedFar then
                mine.warnedFar = true
                Print(string.format(L("you are out of range of your %s"), mine.name))
            end
        end
        if c then
            if mine then
                local left = mine.start + mine.duration - now
                c.text:SetText((far and "|cffff9933" or left <= SOON and "|cffff4444" or "|cffffffff") .. S.TimeText(left) .. "|r")
                c.bg:SetColorTexture(far and 0.9 or e.color[1], far and 0.5 or e.color[2], far and 0 or e.color[3], 1)
                c.icon:SetAlpha(1)
            else
                c.text:SetText("")
                c.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
                c.icon:SetAlpha(0.45)
            end
        end
    end
end

local function PaintBuff(b, has, left)
    if not b then return end
    local need = S.NeedsRefresh(has, left)
    b.bg:SetColorTexture(need and 0.7 or 0.15, need and 0.15 or 0.15, need and 0.1 or 0.15, 0.9)
    return need
end

local function PaintBuffs()
    if Opt("shamImbue") and GetWeaponEnchantInfo then
        local ok, has, ms = pcall(GetWeaponEnchantInfo)
        if ok and Plain(has) and Plain(ms) then
            local left = (has and ms) and ms / 1000 or nil
            PaintBuff(imbueButton, has and true or false, left)
            imbueButton.text:SetText(has and S.TimeText(left or 0) or L("missing"))
        end
    end
    if Opt("shamShield") and shieldButton then
        local buffs = Auras("player", "HELPFUL")
        if buffs then
            local found
            for _, a in ipairs(buffs) do
                for _, s in ipairs(SHIELDS) do if a.name == s then found = a end end
            end
            local left = found and found.expirationTime and found.expirationTime > 0 and (found.expirationTime - GetTime()) or nil
            PaintBuff(shieldButton, found ~= nil, left)
            local charges = found and Plain(found.applications) and found.applications or 0
            shieldButton.text:SetText(found and ((charges > 0 and (charges .. "x ") or "") .. S.TimeText(left or 0)) or L("missing"))
        end
    end
end

local ankhWarned = false
local function PaintAnkhs()
    if not (Opt("shamAnkh") and ankhText and known["Reincarnation"]) then return end
    local n = GetItemCount and GetItemCount(ANKH) or 0
    local low = tonumber(DB().shamAnkhLow) or 3
    local ready = ""
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local c = C_Spell.GetSpellCooldown("Reincarnation")
        if type(c) == "table" then start, duration = c.startTime, c.duration end
    elseif GetSpellCooldown then
        start, duration = GetSpellCooldown("Reincarnation")
    end
    if start and duration and Plain(start) and Plain(duration) then
        local left = (start > 0 and duration > 2) and (start + duration - GetTime()) or 0
        ready = left > 0 and ("  -  " .. L("Reincarnation in ") .. S.TimeText(left)) or ("  -  |cff55ff55" .. L("ready") .. "|r")
    end
    ankhText:SetText((n < low and "|cffff4444" or "") .. L("Ankhs: ") .. n .. (n < low and "|r" or "") .. ready)
    if n < low and not ankhWarned and not InCombatLockdown() then
        ankhWarned = true
        Print(string.format(L("you are low on ankhs: %d left"), n))
    elseif n >= low then
        ankhWarned = false
    end
end

local function PaintCures()
    if not (Opt("shamCure") and cureCells[1]) then return end
    for _, c in ipairs(cureCells) do
        local unit = c.unit
        if UnitExists(unit) then
            local kinds = {}
            local debuffs = Auras(unit, "HARMFUL")
            for _, a in ipairs(debuffs or {}) do kinds[#kinds + 1] = a.dispelName end
            local kind = S.CureKind(kinds, known["Cure Poison"], known["Cure Disease"])
            local name = UnitName(unit)
            c.text:SetText(type(name) == "string" and Plain(name) and name:sub(1, 4) or "")
            if kind == "Poison" then c.bg:SetColorTexture(0.1, 0.75, 0.15, 1)
            elseif kind == "Disease" then c.bg:SetColorTexture(0.6, 0.4, 0.05, 1)
            else c.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
            c:SetAlpha(1)
        else
            c.text:SetText("")
            c.bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
        end
    end
end

local function Paint()
    if not frame or not frame:IsShown() then return end
    if Opt("shamTotemBar") or Opt("shamTotemRange") then PaintTotems() end
    PaintBuffs()
    PaintAnkhs()
    PaintCures()
end

--------------------------------------------------------------------------------
-- The game's own totem bar
--------------------------------------------------------------------------------
local gameBarHidden = false
local gameBarWasShown = false
-- hidden through the game's own visibility rule, so it stays hidden when the game tries to show it, and nothing of the game's is
-- moved or overwritten. Between fights only
local function GameBar(hide)
    local bar = _G.MultiCastActionBarFrame
    if not (bar and RegisterStateDriver and UnregisterStateDriver) then return end
    if hide and not gameBarHidden then
        gameBarWasShown = bar.IsShown and bar:IsShown() and true or false
        RegisterStateDriver(bar, "visibility", "hide")
        gameBarHidden = true
    elseif not hide and gameBarHidden then
        UnregisterStateDriver(bar, "visibility")
        if gameBarWasShown then bar:Show() end
        gameBarHidden = false
    end
end

--------------------------------------------------------------------------------
-- What the buttons cast and where they sit (between fights only: they are secure buttons)
--------------------------------------------------------------------------------
local function CastMacro(button, mouse, text)
    local n = mouse == "right" and "2" or "1"
    button:SetAttribute("type" .. n, text and "macro" or nil)
    button:SetAttribute("macrotext" .. n, text)
end

-- The key for "drop the set": set in the game's own key bindings (AddOns, Forever Lazy). It clicks a button of its own, which
-- is never seen, so the key works with the totem bar switched off too. It drops from the same set the panel shows.
local KEY_BINDING = "CLICK ForeverLazy_DropTotems:LeftButton"
_G["BINDING_NAME_" .. KEY_BINDING] = "Shaman: drop the totem set (one totem a press)"
local keyButton

local function BoundKey()
    local key = GetBindingKey and GetBindingKey(KEY_BINDING)
    return key
end

-- a pressed key, written the way the game's bindings write it; nil for Shift, Ctrl and Alt on their own
local MOUSE = { MiddleButton = "BUTTON3" }
function S.KeyName(key, alt, ctrl, shift)
    if not key or key == "UNKNOWN" or key:find("SHIFT$") or key:find("CTRL$") or key:find("ALT$") or key:find("META$") then return nil end
    key = MOUSE[key] or key:match("^Button(%d+)$") and ("BUTTON" .. key:match("%d+")) or key
    return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. key
end

-- give "drop the set" this key, or take its key away (nil). It goes into the game's own key bindings, so the two always agree.
-- true, or false and why not
function S.SetKey(key)
    if InCombatLockdown() then return false, L("keys can be changed after the fight") end
    if not (SetBinding and GetBindingKey) then return false, L("this client does not let an addon set keys: use the game's key bindings") end
    local old = { GetBindingKey(KEY_BINDING) }
    if key and not SetBinding(key, KEY_BINDING) then return false, L("the game would not take that key") end
    for _, k in ipairs(old) do if k ~= key then SetBinding(k) end end
    local save = SaveBindings or AttemptToSaveBindings
    if save and GetCurrentBindingSet then save(GetCurrentBindingSet()) end
    return true
end

-- what a key does now, when it is something else
local function UsedFor(key)
    local action = GetBindingAction and GetBindingAction(key)
    if not action or action == "" or action == KEY_BINDING then return nil end
    return _G["BINDING_NAME_" .. action] or action
end

-- turns an options button into "click me, then press a key". A key that already does something needs a second press.
function S.KeyCatcher(button)
    local listening, asked = false, nil
    local function Show()
        local key = BoundKey()
        button:SetText(listening and L("Press a key (Esc cancels)")
            or (key and (L("Drop the set key: ") .. key) or L("Click to set a drop the set key")))
    end
    local function Stop()
        if listening then
            listening, asked = false, nil
            button:SetScript("OnKeyDown", nil)
            button:SetScript("OnMouseWheel", nil)
            button:EnableKeyboard(false)
            button:EnableMouseWheel(false)
        end
        Show()
    end
    local function Take(raw)
        local key = S.KeyName(raw, IsAltKeyDown and IsAltKeyDown(), IsControlKeyDown and IsControlKeyDown(), IsShiftKeyDown and IsShiftKeyDown())
        if not key then return end
        local used = UsedFor(key)
        if used and asked ~= key then
            asked = key
            Print(string.format(L("%s is used for \"%s\". Press it again to use it for drop the set instead, or press another key."), key, used))
            return
        end
        local ok, why = S.SetKey(key)
        Print(ok and (L("drop the totem set is now on ") .. key) or why)
        Stop()
    end
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", function(_, mouse)
        if listening then
            if mouse == "LeftButton" or mouse == "RightButton" then Stop() else Take(mouse) end
            return
        end
        if mouse ~= "LeftButton" then return end
        if InCombatLockdown() then Print(L("keys can be changed after the fight")); return end
        listening = true
        button:SetScript("OnKeyDown", function(_, raw)
            if raw == "ESCAPE" then Stop() else Take(raw) end
        end)
        button:SetScript("OnMouseWheel", function(_, delta) Take(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
        button:EnableKeyboard(true)
        button:EnableMouseWheel(true)
        if button.SetPropagateKeyboardInput then button:SetPropagateKeyboardInput(false) end    -- the key stays here
        Show()
    end)
    -- never keep hold of the keyboard: closing the window or a fight starting ends it
    button:HookScript("OnHide", Stop)
    button:RegisterEvent("PLAYER_REGEN_DISABLED")
    button:RegisterEvent("UPDATE_BINDINGS")
    button:SetScript("OnEvent", function(_, event) if event == "PLAYER_REGEN_DISABLED" then Stop() else Show() end end)
    button.Refresh = Show
    Show()
end

local function SetSequence()
    local choices, names = Choices(), {}
    for _, e in ipairs(ELEMENTS) do names[#names + 1] = S.Pick(choices[e.key], e.totems, known) or "" end
    return S.Sequence(names)
end

-- between fights only
local function KeyButton()
    if not keyButton then
        keyButton = CreateFrame("Button", "ForeverLazy_DropTotems", UIParent, "SecureActionButtonTemplate")
        keyButton:RegisterForClicks("AnyUp", "AnyDown")
        keyButton:SetAttribute("useOnKeyDown", false)
    end
    local sequence = SetSequence()
    keyButton:SetAttribute("type1", sequence and "macro" or nil)
    keyButton:SetAttribute("macrotext1", sequence)
end

local function Refresh()
    local d = DB()
    if not d then return end
    if IsShaman() and not InCombatLockdown() then
        ReadSpells()
        KeyButton()
    end
    local showBar = Opt("shamTotemBar") or Opt("shamTotemRange")
    local showCure = Opt("shamCure")
    local wanted = IsShaman() and (showBar or Opt("shamImbue") or Opt("shamShield") or Opt("shamAnkh") or showCure)
    if InCombatLockdown() then waiting = true; return end
    waiting = false
    if not wanted then
        GameBar(false)
        if frame then frame:Hide() end
        return
    end
    ReadSpells()
    Own()
    if not frame then Build() end
    local y = -18

    local tall = Own().shamVertical == true
    frame:SetWidth(tall and 100 or 176)

    -- totems
    local names, any = {}, false
    local choices = Choices()
    for _, e in ipairs(ELEMENTS) do
        for _, t in ipairs(e.totems) do if known[t] then any = true end end
    end
    for i, e in ipairs(ELEMENTS) do
        local c = cells[i]
        local pick = S.Pick(choices[e.key], e.totems, known)
        c.pick = pick
        names[#names + 1] = pick or ""
        CastMacro(c, "left", pick and ("/cast " .. pick) or nil)
        c.icon:SetTexture(pick and Texture(pick) or "Interface\\Icons\\INV_Misc_QuestionMark")
        c.icon:SetShown(pick ~= nil)
        c:ClearAllPoints()
        if tall then
            c:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, y - (i - 1) * 42)
        else
            c:SetPoint("TOPLEFT", frame, "TOPLEFT", 5 + (i - 1) * 42, y)
        end
        c:SetShown(showBar and any)
        FillMenu(menus[i], pick)
    end
    local sequence = S.Sequence(names)
    CastMacro(dropButton, "left", sequence)
    dropButton.list = sequence and sequence:gsub("^/castsequence reset=15/combat ", "") or L("no totems yet")
    local recall
    for _, name in ipairs(RECALLS) do if known[name] then recall = name; break end end
    recallButton.spell = recall
    CastMacro(recallButton, "left", recall and ("/cast " .. recall) or nil)
    recallButton.icon:SetTexture(recall and Texture(recall) or "Interface\\Icons\\INV_Misc_QuestionMark")
    recallButton:SetShown(showBar and any and recall ~= nil)
    setButton:SetText(L(SetName()))
    setButton:SetShown(showBar and any); dropButton:SetShown(showBar and any)
    -- the game's bar only goes while mine is really there to take its place
    GameBar(Opt("shamHideGameBar") and showBar and any)
    if showBar and any then
        setButton:ClearAllPoints(); dropButton:ClearAllPoints(); recallButton:ClearAllPoints()
        if tall then
            y = y - 4 * 42 - 1
            setButton:SetSize(90, 22); setButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, y)
            y = y - 24
            dropButton:SetSize(recall and 66 or 90, 22); dropButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, y)
            if recall then recallButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 73, y) end
            y = y - 25
        else
            y = y - 43
            setButton:SetSize(66, 22); setButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, y)
            dropButton:SetSize(recall and 78 or 102, 22); dropButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 73, y)
            if recall then recallButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 153, y) end
            y = y - 25
        end
    end

    -- weapon buff and shield: side by side, or one above the other
    local x = 5
    for _, spec in ipairs({ { imbueButton, "shamImbue" }, { shieldButton, "shamShield" } }) do
        local b, key = spec[1], spec[2]
        local pick = S.Pick(d[b.dbKey], b.choices, known)
        b.pick = pick
        CastMacro(b, "left", pick and ("/cast " .. pick) or nil)
        b.icon:SetTexture(pick and Texture(pick) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local show = Opt(key) and pick ~= nil
        b:SetShown(show)
        if show then
            b:SetSize(tall and 90 or 84, 26)
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
            if tall then y = y - 29 else x = x + 86 end
        end
    end
    if x > 5 then y = y - 29 end

    -- ankhs
    local showAnkh = Opt("shamAnkh") and known["Reincarnation"]
    ankhText:SetShown(showAnkh and true or false)
    if showAnkh then
        ankhText:ClearAllPoints(); ankhText:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, y - 2)
        ankhText:SetWidth(tall and 90 or 166); ankhText:SetJustifyH("LEFT")
        y = y - (tall and 30 or 18)
    end

    -- cure buttons
    local canCure = showCure and (known["Cure Poison"] or known["Cure Disease"])
    for i, c in ipairs(cureCells) do
        CastMacro(c, "left", known["Cure Poison"] and ("/cast [@" .. c.unit .. ",help,nodead] Cure Poison") or nil)
        CastMacro(c, "right", known["Cure Disease"] and ("/cast [@" .. c.unit .. ",help,nodead] Cure Disease") or nil)
        c:SetShown(canCure and true or false)
        if canCure then
            c:SetSize(tall and 90 or 32, tall and 20 or 24)
            c:ClearAllPoints()
            if tall then c:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, y - (i - 1) * 22)
            else c:SetPoint("TOPLEFT", frame, "TOPLEFT", 5 + (i - 1) * 33.5, y) end
        end
    end
    if canCure then y = y - (tall and (#cureCells * 22 + 3) or 27) end
    if y == -18 then frame:Hide(); return end           -- nothing learned yet that the ticked helpers could use
    frame:SetHeight(-y + 3)
    Place()
    frame:Show()
    Paint()
end
addon.ShamanRefresh = Refresh

--------------------------------------------------------------------------------
-- Purge: a mark on an enemy with a magic buff
--------------------------------------------------------------------------------
local marks = {}
local function PurgeUpdate(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local m = marks[plate]
    local found
    if Opt("shamPurge") and IsShaman() and known["Purge"] and UnitCanAttack("player", unit) then
        for _, a in ipairs(Auras(unit, "HELPFUL") or {}) do
            if a.dispelName == "Magic" then found = a; break end
        end
    end
    if not found then if m then m:Hide() end return end
    if not m then
        m = CreateFrame("Frame", nil, plate)
        m:SetSize(18, 18)
        m:SetFrameStrata("HIGH")
        m:SetPoint("RIGHT", plate, "LEFT", 2, 0)
        local edge = m:CreateTexture(nil, "BACKGROUND")
        edge:SetPoint("TOPLEFT", -2, 2); edge:SetPoint("BOTTOMRIGHT", 2, -2)
        edge:SetColorTexture(0.7, 0.3, 1, 1)
        m.tex = m:CreateTexture(nil, "ARTWORK")
        m.tex:SetAllPoints(); m.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        marks[plate] = m
    end
    if found.icon and Plain(found.icon) then m.tex:SetTexture(found.icon) end
    m:Show()
end

--------------------------------------------------------------------------------
-- Ghost Wolf
--------------------------------------------------------------------------------
local ranFor, lastNudge = 0, -1000
local function WolfTick(dt)
    if not (Opt("shamWolf") and IsShaman() and known["Ghost Wolf"] and GetUnitSpeed) then return end
    local ok, speed = pcall(GetUnitSpeed, "player")
    if not ok or not Plain(speed) then ranFor = 0; return end
    if speed >= 6 then ranFor = ranFor + dt else ranFor = 0; return end
    local wolf = false
    for _, a in ipairs(Auras("player", "HELPFUL") or {}) do if a.name == "Ghost Wolf" then wolf = true end end
    if S.WolfNudge({ ranFor = ranFor, since = GetTime() - lastNudge, wolf = wolf,
            combat = UnitAffectingCombat and UnitAffectingCombat("player"), mounted = IsMounted and IsMounted(),
            indoors = IsIndoors and IsIndoors(), taxi = UnitOnTaxi and UnitOnTaxi("player"), swimming = IsSwimming and IsSwimming() }) then
        lastNudge = GetTime()
        Print(L("long run: Ghost Wolf would get you there faster"))
    end
end

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
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
    "PLAYER_TOTEM_UPDATE", "UNIT_AURA", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit, _, spellId)
    if not IsShaman() then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" or not spellId or not Plain(spellId) then return end
        local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId)) or (GetSpellInfo and GetSpellInfo(spellId))
        for _, r in ipairs(RECALLS) do if name == r then recalledAt = GetTime() end end
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate and marks[plate] then marks[plate]:Hide() end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        pcall(PurgeUpdate, unit)
    elseif event == "UNIT_AURA" then
        if type(unit) ~= "string" then return end
        if unit:sub(1, 9) == "nameplate" then pcall(PurgeUpdate, unit)
        elseif unit == "player" or unit:find("^party") then pcall(Paint) end
    elseif event == "PLAYER_TOTEM_UPDATE" then
        pcall(Paint)
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
    local passed = acc
    acc = 0
    if not IsShaman() then return end
    pcall(Paint)
    pcall(WolfTick, passed)
end)

--------------------------------------------------------------------------------
-- /lazy shaman
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "shaman" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        local db = DB()
        if a == "all" or a == "off" then
            for _, k in ipairs(KEYS) do db[k] = (a == "all") or nil end
            if addon.RefreshOptions then addon.RefreshOptions() end
        end
        local on = 0
        for _, k in ipairs(KEYS) do if db[k] == true then on = on + 1 end end
        Print(string.format(L("shaman helpers: %d of %d on (/lazy shaman all|off, or the options under My class)"), on, #KEYS))
        if not IsShaman() then Print(L("they only work on a shaman")) end
        pcall(Refresh)
        if IsShaman() then
            local key = BoundKey()
            Print(key and (L("drop the totem set is on the key ") .. key)
                or L("drop the totem set has no key yet: game key bindings, AddOns, Forever Lazy"))
        end
        if IsShaman() and not (recallButton and recallButton.spell) then
            Print(L("no totem recall spell was found in your spellbook (the button shows once you know it, with the totem bar on)"))
        end
        if frame and S.menusWorkInCombat ~= nil then
            Print(S.menusWorkInCombat and L("the totem menus are set up to open during fights")
                or L("this client would not set up the totem menus for fights: they open between fights only"))
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Shaman.lua"] = true end end
