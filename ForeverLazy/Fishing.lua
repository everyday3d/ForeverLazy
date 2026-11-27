-- Fishing helpers. Everything here is off until you turn it on (options, the Fishing page) or give it a key.
--   a key that casts your line (it equips your pole first), and double right-click while the pole is on
--   a louder bobber splash while you fish; your sound settings go back afterwards
--   one button for pole on, weapons back
--   a lure warning and a button that puts your best lure on
--   picking up the catch, a catch log, your skill and the points gained, and pool spots on the world map
--   /lazy fish log [all|reset]    what you caught        /lazy fish status    your skill, pole and lure
-- Nothing clicks the bobber or casts by itself: you press the key or the button every time.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local F = {}
addon.Fish = F

local function DB() return addon.GetDB() end
local function Opt(key) local d = DB(); return d and d[key] == true end

local CAST_BINDING = "CLICK ForeverLazy_Fish:LeftButton"
local SWAP_BINDING = "CLICK ForeverLazy_PoleSwap:LeftButton"
F.CAST_BINDING, F.SWAP_BINDING = CAST_BINDING, SWAP_BINDING
_G["BINDING_NAME_" .. CAST_BINDING] = "Fishing: cast your line"
_G["BINDING_NAME_" .. SWAP_BINDING] = "Fishing: pole on, or weapons back"

--------------------------------------------------------------------------------
-- Rules (pure logic: tests/fishing.lua)
--------------------------------------------------------------------------------
-- best first. skill: the fishing skill the lure asks for
F.LURES = {
    { id = 6533, bonus = 100, skill = 100 },   -- Aquadynamic Fish Attractor
    { id = 6532, bonus = 75, skill = 100 },    -- Bright Baubles
    { id = 7307, bonus = 75, skill = 100 },    -- Flesh Eating Worm
    { id = 6530, bonus = 50, skill = 50 },     -- Nightcrawlers
    { id = 6811, bonus = 50, skill = 50 },     -- Aquadynamic Fish Lens
    { id = 6529, bonus = 25, skill = 1 },      -- Shiny Bauble
}

-- count(id): how many are in my bags. skill: my fishing skill, or nil when the game does not say
function F.BestLure(count, skill)
    for _, l in ipairs(F.LURES) do
        if (not skill or skill >= l.skill) and (count(l.id) or 0) > 0 then return l end
    end
end

function F.CastMacro(spell, poleOn, bagPole)
    if not poleOn and bagPole then return "/equipslot [nocombat] 16 item:" .. bagPole end
    return "/cast " .. spell
end

-- weapons: { main =, off = } item ids from before the pole went on. nil when there is nothing to swap to
function F.SwapMacro(poleOn, bagPole, weapons)
    if not poleOn then
        return bagPole and ("/equipslot [nocombat] 16 item:" .. bagPole) or nil
    end
    local lines = {}
    if weapons and weapons.main then lines[#lines + 1] = "/equipslot 16 item:" .. weapons.main end
    if weapons and weapons.off then lines[#lines + 1] = "/equipslot 17 item:" .. weapons.off end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

function F.LureMacro(lure) return lure and ("/use item:" .. lure.id .. "\n/use 16") or nil end

-- two clicks of the right button, close together
function F.DoubleClick(last, now) return last ~= nil and now - last >= 0.05 and now - last <= 0.4 end

function F.Record(log, zone, name, count, price)
    local z = log[zone]
    if not z then z = {}; log[zone] = z end
    local e = z[name]
    if not e then e = { n = 0, price = 0 }; z[name] = e end
    e.n = e.n + (count or 1)
    if price and price > 0 then e.price = price end
end

-- fish: { name = { n, price } }. Most caught first; also how many and what a vendor would pay
function F.Summary(fish)
    local list, total, value = {}, 0, 0
    for name, e in pairs(fish or {}) do
        list[#list + 1] = { name = name, n = e.n, value = e.n * (e.price or 0) }
        total, value = total + e.n, value + e.n * (e.price or 0)
    end
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    return list, total, value
end

-- a pool you can fish in, by its name in the data (so zeppelin wreckage and such stay out)
function F.IsPoolName(name)
    local n = (name or ""):lower()
    return (n:find("school", 1, true) or n:find("swarm", 1, true) or n:find("oil spill", 1, true)
        or n:find("floating wreckage", 1, true) or n:find("floating debris", 1, true)) and true or false
end

--------------------------------------------------------------------------------
-- What the game says
--------------------------------------------------------------------------------
local function SpellName()
    local name
    if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(7620) end
    if not name and GetSpellInfo then name = GetSpellInfo(7620) end
    return type(name) == "string" and name or "Fishing"
end

local function IsPole(item)
    if not item then return false end
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not info then return false end
    local _, _, _, _, _, class, sub = info(item)
    return class == 2 and sub == 20
end

local function Worn(slot) return GetInventoryItemID and GetInventoryItemID("player", slot) or nil end
local function PoleOn() return IsPole(Worn(16)) end

local function CharKey() return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?") end
-- what this character wears for fishing and for everything else
local function Gear()
    local d = DB()
    d.fishGear = d.fishGear or {}
    local k = CharKey()
    d.fishGear[k] = d.fishGear[k] or {}
    return d.fishGear[k]
end

local function BagPole()
    local want = Gear().pole
    local found
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return nil end
    for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and IsPole(id) then
                if id == want then return id end
                found = found or id
            end
        end
    end
    return found
end

local function Remember()
    local g = Gear()
    local main = Worn(16)
    if IsPole(main) then
        g.pole = main
    elseif main or Worn(17) then
        g.weapons = { main = main, off = Worn(17) }
    end
end

local function ItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return fn and fn(id) or 0
end

local function ItemName(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = fn and fn(id)
    return name or ("item " .. id)
end

-- my fishing skill and its cap, or nil when the game does not say
function F.Skill()
    local want = SpellName():lower()
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        for i = 1, C_SkillInfo.GetNumSkillLines() do
            local line = C_SkillInfo.GetSkillLineInfo(i)
            if line and not line.isHeader and (line.skillID == 356 or (line.name and line.name:lower() == want)) then
                return line.rank or line.skillRank, line.maxRank or line.skillMaxRank
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
            if name and not header and name:lower() == want then return rank, max end
        end
    end
    if GetProfessions and GetProfessionInfo then
        local _, _, _, fishing = GetProfessions()
        if fishing then
            local _, _, rank, max = GetProfessionInfo(fishing)
            return rank, max
        end
    end
end

local startSkill
local function Gained()
    local rank = F.Skill()
    if not rank then return nil end
    startSkill = startSkill or rank
    return rank - startSkill
end

local function LureLeft()
    if not GetWeaponEnchantInfo then return nil end
    local has, ms = GetWeaponEnchantInfo()
    if not has then return 0 end
    return math.max(1, math.floor((ms or 0) / 1000))
end

local function Clock(seconds) return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60)) end

local function Money(copper) return addon.LootMoney and addon.LootMoney(copper) or (math.floor(copper) .. "c") end

local function Notice(text)
    Print(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end

--------------------------------------------------------------------------------
-- A louder splash
--------------------------------------------------------------------------------
-- what to set while fishing: effects up and on, music and background noise down
local BOOST = { Sound_EnableSFX = "1", Sound_SFXVolume = "1", Sound_MusicVolume = "0", Sound_AmbienceVolume = "0" }
local soundToken = 0

local function ReadCVar(name)
    local fn = (C_CVar and C_CVar.GetCVar) or GetCVar
    if fn then local ok, v = pcall(fn, name); if ok then return v end end
end
local function WriteCVar(name, v)
    local fn = (C_CVar and C_CVar.SetCVar) or SetCVar
    if fn then pcall(fn, name, v) end
end

-- the settings from before are kept in the saved settings, so a crash or a reload cannot lose them
function F.SoundUp()
    soundToken = soundToken + 1
    local d = DB()
    if d.fishSoundSaved then return end
    local saved = {}
    for name in pairs(BOOST) do saved[name] = ReadCVar(name) end
    d.fishSoundSaved = saved
    for name, v in pairs(BOOST) do if saved[name] ~= nil then WriteCVar(name, v) end end
end

function F.SoundBack()
    soundToken = soundToken + 1
    local d = DB()
    if not (d and d.fishSoundSaved) then return end
    for name, v in pairs(d.fishSoundSaved) do WriteCVar(name, v) end
    d.fishSoundSaved = nil
end

-- a few seconds after the line comes out, unless you have cast again
local function SoundBackSoon()
    soundToken = soundToken + 1
    local mine = soundToken
    if C_Timer and C_Timer.After then
        C_Timer.After(8, function() if mine == soundToken then F.SoundBack() end end)
    else
        F.SoundBack()
    end
end

--------------------------------------------------------------------------------
-- The catch
--------------------------------------------------------------------------------
local session = {}                 -- name -> { n, price }
local channeling, lineOut = false, -100
local lootSeen = false

local function ZoneName()
    local z = GetRealZoneText and GetRealZoneText()
    return (z and z ~= "") and z or "?"
end

local function FishingLoot()
    if IsFishingLoot then return IsFishingLoot() and true or false end
    return channeling or GetTime() - lineOut < 3
end

function F.OnLoot()
    if lootSeen or not FishingLoot() then return end
    lootSeen = true
    local count = GetNumLootItems and GetNumLootItems() or 0
    if Opt("fishLog") and GetLootSlotInfo then
        local d = DB()
        d.fishCatch = d.fishCatch or {}
        local zone = ZoneName()
        for slot = 1, count do
            local _, name, quantity = GetLootSlotInfo(slot)
            local link = GetLootSlotLink and GetLootSlotLink(slot)
            if link and name then
                local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                local price = info and select(11, info(link))
                F.Record(d.fishCatch, zone, name, quantity, price)
                F.Record({ s = session }, "s", name, quantity, price)
            end
        end
    end
    if Opt("fishAutoLoot") and LootSlot then
        for slot = count, 1, -1 do pcall(LootSlot, slot) end
    end
end

local function ShowLog(all)
    local d = DB()
    local log = d.fishCatch or {}
    local fish, title
    if all then
        fish, title = {}, L("every zone")
        for _, z in pairs(log) do
            for name, e in pairs(z) do F.Record({ a = fish }, "a", name, e.n, e.price) end
        end
    else
        title = ZoneName()
        fish = log[title]
    end
    local list, total, value = F.Summary(fish)
    if total == 0 then
        Print(string.format(L("no catches written down for %s yet"), title)
            .. (d.fishLog == true and "" or L(" (the catch log is off: turn it on in the options, under Fishing)")))
    else
        Print(string.format(L("caught in %s: %d, worth %s to a vendor"), title, total, Money(value)))
        for i = 1, math.min(12, #list) do Print(string.format("  %d x %s  (%s)", list[i].n, list[i].name, Money(list[i].value))) end
        if #list > 12 then Print(string.format(L("  ... and %d more kinds"), #list - 12)) end
    end
    local _, now, worth = F.Summary(session)
    if now > 0 then Print(string.format(L("this session: %d, worth %s"), now, Money(worth))) end
end

local function Status()
    local rank, max = F.Skill()
    Print(rank and string.format(L("fishing skill %d of %d, %d gained this session"), rank, max or 0, Gained() or 0)
        or L("the game does not tell me your fishing skill (have you learned fishing?)"))
    Print(PoleOn() and L("your pole is on") or (BagPole() and L("your pole is in your bags") or L("no fishing pole in your bags")))
    if PoleOn() then
        local left = LureLeft()
        if left then Print(left > 0 and (L("lure: ") .. Clock(left) .. L(" left")) or L("no lure on your pole")) end
    end
    local key = GetBindingKey and GetBindingKey(CAST_BINDING)
    Print(key and (L("cast key: ") .. key) or L("no cast key set (options, under Fishing)"))
end

--------------------------------------------------------------------------------
-- Lure warnings
--------------------------------------------------------------------------------
local warnedNone, warnedLow = false, false
function F.LureWarning()
    if not Opt("fishLure") or not PoleOn() then return end
    local left = LureLeft()
    if not left then return end
    if left == 0 then
        warnedLow = false
        if not warnedNone and F.BestLure(ItemCount, (F.Skill())) then
            warnedNone = true
            Notice(L("No lure on your pole"))
        end
    else
        warnedNone = false
        if left > 60 then
            warnedLow = false
        elseif not warnedLow then
            warnedLow = true
            Notice(L("Your lure is about to wear off"))
        end
    end
end

--------------------------------------------------------------------------------
-- The buttons (secure: what they do can only be changed between fights)
--------------------------------------------------------------------------------
local castKey, swapKey
local bar, barCast, barSwap, barLure, skillText, catchText

local function Secure(name, parent, template)
    local b = CreateFrame("Button", name, parent, template or "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    return b
end

local function SetMacro(b, text)
    b:SetAttribute("type1", text and "macro" or nil)
    b:SetAttribute("macrotext1", text)
end

local function Tip(b, lines)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for i, line in ipairs(lines()) do
            if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0, true) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function BarButton(name)
    local b = Secure(name, bar, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    b:SetSize(104, 24)
    return b
end

local function BuildBar()
    if bar then return end
    bar = CreateFrame("Frame", "ForeverLazy_FishBar", UIParent)
    bar:SetSize(336, 62)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not Opt("fishLocked") and not InCombatLockdown() then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        local d = DB()
        d.pos = d.pos or {}
        d.pos.fishing = { point, x, y }
    end)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
    skillText = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    skillText:SetPoint("TOPLEFT", 6, -6)
    catchText = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    catchText:SetPoint("TOPRIGHT", -6, -6)
    barCast = BarButton("ForeverLazy_FishBarCast")
    barSwap = BarButton("ForeverLazy_FishBarSwap")
    barLure = BarButton("ForeverLazy_FishBarLure")
    Tip(barCast, function() return { L("Cast your line"), L("With the pole in your bags, the first press puts it on.") } end)
    Tip(barSwap, function()
        local w = Gear().weapons
        if not PoleOn() then return { L("Pole on"), L("Puts your fishing pole on (not during a fight).") } end
        if not w then return { L("Weapons back"), L("I have not seen your weapons yet: put them on once yourself.") } end
        return { L("Weapons back"), w.main and ItemName(w.main) or "", w.off and ItemName(w.off) or "" }
    end)
    Tip(barLure, function()
        local lure = F.BestLure(ItemCount, (F.Skill()))
        if not lure then return { L("Lure"), L("No lure in your bags that you can use.") } end
        return { L("Lure"), ItemName(lure.id) .. " (+" .. lure.bonus .. ")", L("Click to put it on your pole.") }
    end)
    local since = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since < 1 then return end
        since = 0
        F.Paint()
        F.LureWarning()
    end)
    bar:Hide()
end

function F.Paint()
    if not bar then return end
    if barLure then
        local left = LureLeft()
        barLure:SetText((left and left > 0) and (L("Lure ") .. Clock(left)) or L("Put a lure on"))
    end
    local parts = ""
    if Opt("fishSkill") then
        local rank, max = F.Skill()
        if rank then
            local gained = Gained() or 0
            parts = string.format(L("Fishing %d/%d"), rank, max or 0) .. (gained > 0 and ("  +" .. gained) or "")
        end
    end
    skillText:SetText(parts)
    local _, total, value = F.Summary(session)
    catchText:SetText((Opt("fishLog") and total > 0) and string.format(L("%d caught, %s"), total, Money(value)) or "")
end

local function BarWanted()
    if Opt("fishSwap") then return true end                          -- the button has to be there to put the pole on
    return (Opt("fishLure") or Opt("fishSkill") or Opt("fishLog")) and PoleOn()
end

local pending = false
-- sets what the buttons do and what is on show. In a fight it waits until the fight is over
function F.Update()
    local d = DB()
    if not d then return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    if not castKey then
        castKey = Secure("ForeverLazy_Fish", UIParent)
        swapKey = Secure("ForeverLazy_PoleSwap", UIParent)
        castKey:SetScript("PostClick", function(_, _, down) if not down then F.ReleaseRightClick() end end)
    end
    local poleOn = PoleOn()
    local bagPole = not poleOn and BagPole() or nil
    local cast = F.CastMacro(SpellName(), poleOn, bagPole)
    local swap = F.SwapMacro(poleOn, bagPole, Gear().weapons)
    SetMacro(castKey, cast)
    SetMacro(swapKey, swap)

    if not BarWanted() then
        if bar then bar:Hide() end
        return
    end
    BuildBar()
    bar:ClearAllPoints()
    local p = d.pos and d.pos.fishing
    if p then bar:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180) end
    bar:SetScale(tonumber(d.fishScale) or 1)
    SetMacro(barCast, cast)
    barCast:SetText(L("Cast"))
    SetMacro(barSwap, swap)
    barSwap:SetText(poleOn and L("Weapons") or L("Pole"))
    SetMacro(barLure, poleOn and F.LureMacro(F.BestLure(ItemCount, (F.Skill()))) or nil)
    local x = 6
    for _, e in ipairs({ { barCast, true }, { barSwap, Opt("fishSwap") }, { barLure, Opt("fishLure") } }) do
        e[1]:SetShown(e[2])
        if e[2] then
            e[1]:ClearAllPoints()
            e[1]:SetPoint("BOTTOMLEFT", x, 6)
            x = x + 110
        end
    end
    F.Paint()
    bar:Show()
end
addon.FishingRefresh = F.Update

function F.ResetBar()
    local d = DB()
    if d.pos then d.pos.fishing = nil end
    F.Update()
end

--------------------------------------------------------------------------------
-- Double right-click
--------------------------------------------------------------------------------
local clicker, lastRight
local holdingRight = false

function F.ReleaseRightClick()
    if holdingRight and not InCombatLockdown() and ClearOverrideBindings then
        holdingRight = false
        ClearOverrideBindings(clicker)
    end
end

-- the second click is lent to the cast button, and given straight back
function F.RightDown()
    if not Opt("fishDoubleClick") or InCombatLockdown() or not SetOverrideBindingClick then return end
    local now = GetTime()
    local double = F.DoubleClick(lastRight, now)
    lastRight = now
    if not double or not castKey or not PoleOn() then return end
    if UnitExists and UnitExists("mouseover") then return end        -- clicking someone, not the water
    lastRight = nil
    clicker = clicker or CreateFrame("Frame")
    holdingRight = true
    SetOverrideBindingClick(clicker, true, "BUTTON2", "ForeverLazy_Fish", "LeftButton")
    if C_Timer and C_Timer.After then C_Timer.After(1, F.ReleaseRightClick) end
end

if WorldFrame and WorldFrame.HookScript then
    WorldFrame:HookScript("OnMouseDown", function(_, button) if button == "RightButton" then F.RightDown() end end)
end

--------------------------------------------------------------------------------
-- Pool spots on the world map
--------------------------------------------------------------------------------
local OWNER = "ForeverLazyFishPools"
local poolFrames, poolsDrawn, poolTries = {}, false, 0

local function PoolPin(i, name)
    local f = poolFrames[i]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(12, 12)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        t:SetTexture("Interface\\Icons\\Trade_Fishing")
        f:EnableMouse(true)
        f:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.pool, 1, 0.82, 0)
            GameTooltip:AddLine(L("A known pool spot. The pool may not be there right now."), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        poolFrames[i] = f
    end
    f.pool = name
    return f
end

function F.DrawPools()
    local pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    if not pins then return end
    if not Opt("fishPools") then
        if poolsDrawn then pins:RemoveAllWorldMapIcons(OWNER); poolsDrawn = false end
        return
    end
    if poolsDrawn or not addon.PoolSpots then return end
    local started = addon.PoolSpots(function(spots)
        if poolsDrawn or not Opt("fishPools") then return end
        poolsDrawn = true
        for i, s in ipairs(spots) do
            pcall(pins.AddWorldMapIconMap, pins, OWNER, PoolPin(i, s.name), s.uiMapId, s.zx, s.zy)
        end
    end)
    -- right after logging in the data may still be loading
    if not started and poolTries < 6 and C_Timer and C_Timer.After then
        poolTries = poolTries + 1
        C_Timer.After(10, F.DrawPools)
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local function Mine()
    if not UnitChannelInfo then return false end
    local ok, same = pcall(function() return UnitChannelInfo("player") == SpellName() end)
    return ok and same
end

local remembering = false
local function GearChanged()
    if remembering then return end
    remembering = true
    local function Done()
        remembering = false
        Remember()
        if not PoleOn() then F.SoundBack() end
        F.Update()
    end
    -- a swap arrives one hand at a time: wait until it is all there
    if C_Timer and C_Timer.After then C_Timer.After(0.5, Done) else Done() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "UNIT_SPELLCAST_CHANNEL_START",
                     "UNIT_SPELLCAST_CHANNEL_STOP", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
function F.OnEvent(_, event, unit)
    if not DB() then return end
    if event == "PLAYER_LOGIN" then
        F.SoundBack()                                                -- left over from a crash or a reload mid-cast
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() Remember(); F.Update(); Gained() end)
            C_Timer.After(8, F.DrawPools)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_EQUIPMENT_CHANGED" then
        GearChanged()
    elseif event == "BAG_UPDATE_DELAYED" or event == "SKILL_LINES_CHANGED" then
        F.Update()
    elseif event == "PLAYER_REGEN_DISABLED" then
        F.SoundBack()
        F.ReleaseRightClick()                                        -- still allowed at this moment
    elseif event == "PLAYER_REGEN_ENABLED" then
        F.ReleaseRightClick()
        if pending then F.Update() end
    elseif event == "PLAYER_LOGOUT" then
        F.SoundBack()
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if unit == "player" and Mine() then
            channeling = true
            if Opt("fishSound") then F.SoundUp() end
            F.LureWarning()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if unit == "player" and channeling then
            channeling = false
            lineOut = GetTime()
            SoundBackSoon()
        end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        F.OnLoot()
        F.Paint()
    elseif event == "LOOT_CLOSED" then
        lootSeen = false
    end
end
ev:SetScript("OnEvent", function(...) pcall(F.OnEvent, ...) end)

--------------------------------------------------------------------------------
-- Commands: /lazy fish and /lazy fish 2 (nearest pools) stay with Gather.lua
--------------------------------------------------------------------------------
local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    if c == "fish" or c == "fishing" then
        local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if a == "log" then ShowLog(false); return true
        elseif a == "log all" then ShowLog(true); return true
        elseif a == "log reset" then
            DB().fishCatch, session = nil, {}
            Print(L("catch log emptied"))
            F.Paint()
            return true
        elseif a == "status" then Status(); return true
        elseif a == "help" then
            Print(L("/lazy fish (nearest pool), /lazy fish status, /lazy fish log, /lazy fish log all, /lazy fish log reset. Turn the helpers on in the options, under Fishing."))
            return true
        end
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Fishing.lua"] = true end end
