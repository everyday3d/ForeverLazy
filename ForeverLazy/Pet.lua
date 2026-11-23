-- Hunter pet reminder: watches your pet's happiness and tells you when it needs feeding.
--   /lazy pet          status
--   /lazy pet on|off   turn the reminder on or off
--   /lazy pet test     show the reminder for a few seconds
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

local isHunter = false
local frame
local testUntil = 0
local lastNag = 0
local lastState
local fakeHunter = false

local function MakeFrame()
    local f = CreateFrame("Frame", "ForeverLazy_PetAlert", UIParent)
    f:SetSize(280, 44)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not DB().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        DB().pos.pet = { point = point, x = x, y = y }
    end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(34, 34)
    f.icon:SetPoint("LEFT", 5, 0)
    f.icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastCall")
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 0)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, 0)
    f:Hide()
    return f
end

local function Place()
    if not frame then return end
    local p = DB().pos.pet or { point = "TOP", x = 0, y = -330 }
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    frame:SetScale(DB().scale or 1)
end

local function Diet()
    if not GetPetFoodTypes then return nil end
    local t = { GetPetFoodTypes() }
    if #t == 0 then return nil end
    return table.concat(t, ", ")
end

-- returns a state name: "unhappy", "content", "happy", "missing", "dead" or nil
local function PetState()
    if not UnitExists("pet") then return "missing" end
    if UnitIsDead and UnitIsDead("pet") then return "dead" end
    if GetPetHappiness then
        local h = GetPetHappiness()
        if h == 1 then return "unhappy" elseif h == 2 then return "content" elseif h == 3 then return "happy" end
    end
    return nil
end

local function NeedsAttention(state)
    local db = DB()
    if state == "unhappy" then return true end
    if state == "content" then return db.petOnlyUnhappy ~= true end
    if state == "missing" or state == "dead" then return db.petMissing == true end
    return false
end

-- The scream: big red "FEED ME!!!" in the middle of the screen that shakes for a few seconds.
local scream
local function Scream(petName, text, sub)
    if not scream then
        local f = CreateFrame("Frame", "ForeverLazy_Scream", UIParent)
        f:SetSize(700, 120)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetFont("Fonts\\FRIZQT__.TTF", 72, "OUTLINE")
        f.text:SetPoint("CENTER")
        f.text:SetTextColor(1, 0.1, 0.1)
        f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -4)
        f:Hide()
        f:SetScript("OnUpdate", function(self, dt)
            self.t = (self.t or 0) + dt
            if self.t > 3.5 then self:Hide(); return end
            local k = self.t < 2.5 and 1 or (3.5 - self.t)           -- shake hard, then fade out
            self:SetAlpha(k)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", (math.random() - 0.5) * 24 * k, 140 + (math.random() - 0.5) * 24 * k)
        end)
        scream = f
    end
    scream.t = 0
    scream.text:SetText(text or "FEED ME!!!")
    scream.sub:SetText(sub or (petName and (petName .. " is starving") or ""))
    scream:SetAlpha(1)
    scream:Show()
end
addon.PetScream = Scream
local function Update()
    local db = DB()
    if not db or not isHunter then return end
    if fakeHunter and GetTime() >= testUntil then       -- the test is over: go back to not being a hunter
        fakeHunter = false; isHunter = false
        if frame then frame:Hide() end
        return
    end
    if not addon.ModuleOn("pet") then if frame then frame:Hide() end; return end
    if not frame then frame = MakeFrame(); Place() end

    local testing = GetTime() < testUntil
    if db.petRemind == false and not testing then frame:Hide(); return end

    local state = testing and "unhappy" or PetState()
    local need = testing or NeedsAttention(state)
    if not need then
        frame:Hide()
        lastState = state
        return
    end

    local name = UnitName("pet") or "your pet"
    if state == "missing" then
        frame.title:SetText(L("|cffff5555No pet out|r"))
        frame.sub:SetText(L("Call your pet"))
    elseif state == "dead" then
        frame.title:SetText("|cffff5555" .. name .. " is dead|r")
        frame.sub:SetText(L("Revive Pet"))
    else
        local color = state == "unhappy" and "|cffff5555" or "|cffffd100"
        frame.title:SetText(string.format("%sFeed %s|r", color, name))
        local diet = Diet()
        frame.sub:SetText(string.format("It is %s%s", state == "unhappy" and "unhappy" or "only content",
            diet and (" - eats: " .. diet) or ""))
    end
    frame:Show()

    -- chat line (and sound) when it first happens, then every minute while it stays that way
    local now = GetTime()
    if state ~= lastState or now - lastNag > 60 then
        lastState = state
        lastNag = now
        if not (InCombatLockdown and InCombatLockdown()) then
            if state == "unhappy" or state == "content" then
                local diet = Diet()
                Print(string.format(L("%s needs feeding (%s)%s"), name, state, diet and (" - eats " .. diet) or ""))
            end
        end
        if db.petScream ~= false and (state == "unhappy" or state == "content") then pcall(Scream, name) end
        if db.petSound then
            -- your own clip first (media\custom\feedme.ogg or .mp3, never shipped with the addon), else the raid warning sound
            local played = PlaySoundFile and (PlaySoundFile("Interface\\AddOns\\ForeverLazy\\media\\custom\\feedme.ogg", "Master")
                or PlaySoundFile("Interface\\AddOns\\ForeverLazy\\media\\custom\\feedme.mp3", "Master"))
            if not played then PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959) end
        end
    end
end

--------------------------------------------------------------------------------
-- Ammo: a hunter running low on arrows or bullets gets told, before it is too late
--------------------------------------------------------------------------------
local lastAmmoState, lastAmmoNag = nil, 0

local function AmmoInfo()
    if not GetInventoryItemID then return nil end
    local ok, id = pcall(GetInventoryItemID, "player", 0)          -- slot 0 is the ammo slot
    if not ok then id = nil end
    if not id then
        local ranged = GetInventoryItemID("player", 18)
        if ranged then return { count = 0, word = "ammo" } end      -- a bow or gun but nothing in the ammo slot
        return nil
    end
    local count = (GetItemCount and GetItemCount(id, false)) or 0
    local inSlot = GetInventoryItemCount and GetInventoryItemCount("player", 0) or 0
    count = math.max(count, tonumber(inSlot) or 0)
    local name, _, _, _, _, _, subType = GetItemInfo(id)
    local word = (subType == "Arrow" and "arrows") or (subType == "Bullet" and "bullets") or "ammo"
    return { count = count, word = word, id = id, name = name, subType = subType }
end

local function AmmoCheck(test)
    local db = DB()
    if not db or db.ammoRemind == false then return end
    local a = AmmoInfo()
    if test and not a then Print(L("no ranged weapon or ammo found on you, so there is nothing to count")); return end
    if not a then return end
    local low = db.ammoLow or 200
    local state = (a.count <= 0 and "out") or (a.count <= low and "low") or "ok"
    if state == "ok" and not test then lastAmmoState = "ok"; return end
    if InCombatLockdown and InCombatLockdown() and not test then return end
    local now = GetTime()
    if test or state ~= lastAmmoState or now - lastAmmoNag > 120 then
        lastAmmoState, lastAmmoNag = state, now
        if state == "out" then
            Print(L("OUT OF AMMO: your ammo slot is empty"))
            pcall(Scream, nil, "OUT OF AMMO!!!", "Buy " .. a.word .. " now")
        else
            Print(string.format(L("low on ammo: %d %s left"), a.count, a.word))
            pcall(Scream, nil, "LOW ON AMMO", string.format("%d %s left", a.count, a.word))
        end
        PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959)
    end
end
-- The next kind of ammo: better arrows and bullets open up at certain levels (vanilla levels). When I can use a
-- better kind than the one in my ammo slot, say so, and say whether I already carry some.
local AMMO_TIERS = {
    Arrow  = { { 1, "Rough Arrow" }, { 10, "Sharp Arrow" }, { 25, "Razor Arrow" }, { 40, "Jagged Arrow" } },
    Bullet = { { 1, "Light Shot" }, { 10, "Compact Shot" }, { 25, "Heavy Shot" }, { 40, "Solid Shot" } },
}
local lastUpgradeKey, lastUpgradeNag = nil, 0

local function CarryingAmmo(name)
    for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
        local n
        if C_Container and C_Container.GetContainerNumSlots then n = C_Container.GetContainerNumSlots(bag)
        else n = GetContainerNumSlots and GetContainerNumSlots(bag) end
        for slot = 1, (n or 0) do
            local id
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                id = info and info.itemID
            elseif GetContainerItemLink then
                local link = GetContainerItemLink(bag, slot)
                id = link and tonumber(link:match("item:(%d+)"))
            end
            if id then
                local iname = GetItemInfo(id)
                if iname and iname:find(name, 1, true) then return true end
            end
        end
    end
    return false
end

local function UpgradeCheck(test)
    local db = DB()
    if not db or db.ammoUpgrade == false then return end
    local a = AmmoInfo()
    if not a or not a.name or not a.subType then
        if test then Print(L("ammo upgrade: no ammo in your ammo slot to compare")) end
        return
    end
    local tiers = AMMO_TIERS[a.subType]
    if not tiers then return end
    local level = UnitLevel("player") or 1
    local have, best = 0, 0
    for i, t in ipairs(tiers) do
        if a.name:find(t[2], 1, true) then have = i end
        if t[1] <= level then best = i end
    end
    if have == 0 then
        if test then Print(L("ammo upgrade: I do not know the kind of ammo you are using (") .. tostring(a.name) .. ")") end
        return
    end
    if have >= best then
        lastUpgradeKey = nil
        if test then Print(string.format(L("ammo upgrade: %s is the best kind you can use at level %d"), a.name, level)) end
        return
    end
    if InCombatLockdown and InCombatLockdown() and not test then return end
    local nextTier = tiers[best]
    local key = a.subType .. best
    local now = GetTime()
    if test or key ~= lastUpgradeKey or now - lastUpgradeNag > 600 then
        lastUpgradeKey, lastUpgradeNag = key, now
        local carrying = CarryingAmmo(nextTier[2])
        local what = nextTier[2] .. "s"
        local advice = carrying and "you already carry some: put them in your ammo slot" or "buy some from a vendor"
        Print(string.format(L("ammo upgrade: you can use %s now (level %d): %s."), what, nextTier[1], advice))
        pcall(Scream, nil, "AMMO UPGRADE", string.format("%s (level %d): %s", what, nextTier[1], advice))
        PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959)
    end
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "PLAYER_LEVEL_UP")
pcall(ev.RegisterEvent, ev, "UNIT_PET")
pcall(ev.RegisterEvent, ev, "PET_BAR_UPDATE")
pcall(ev.RegisterEvent, ev, "UNIT_HAPPINESS")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        isHunter = select(2, UnitClass("player")) == "HUNTER"
    end
    if isHunter then Update(); pcall(AmmoCheck); pcall(UpgradeCheck) end
end)

local timer = 0
ev:SetScript("OnUpdate", function(_, dt)
    if not isHunter then return end
    timer = timer + dt
    if timer < 1 then return end
    timer = 0
    Update()
    pcall(AmmoCheck)
    pcall(UpgradeCheck)
end)

-- apply the saved position again when the layout is re-applied (reset positions, profile switch)
local origLayout = addon.ApplyLayout
function addon:ApplyLayout()
    origLayout(self)
    Place()
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if cmd == "pet" then
        local db = DB()
        rest = (rest or ""):lower()
        if rest == "on" then db.petRemind = true; Print(L("pet reminder on"))
        elseif rest == "off" then db.petRemind = false; Print(L("pet reminder off"))
        elseif rest == "ammo" then
            if not isHunter then Print(L("you are not a hunter")); return true end
            AmmoCheck(true)
            UpgradeCheck(true)
        elseif rest == "test" then
            testUntil = GetTime() + 6
            if not isHunter then Print(L("you are not a hunter - the reminder only runs for hunters, test shown anyway")); isHunter = true; fakeHunter = true end
            Update()
        else
            if not isHunter then Print(L("you are not a hunter, so there is no pet to watch")); return true end
            Print(string.format(L("pet: %s, reminder %s"), tostring(PetState() or "unknown"), db.petRemind == false and "off" or "on"))
            local diet = Diet()
            if diet then Print(L("eats: ") .. diet) end
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Pet.lua"] = true end end
