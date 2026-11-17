-- Hunter pet reminder: watches your pet's happiness and tells you when it needs feeding.
--   /lazy pet          status
--   /lazy pet on|off   turn the reminder on or off
--   /lazy pet test     show the reminder for a few seconds
local ADDON, ns = ...
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

local isHunter = false
local frame
local testUntil = 0
local lastNag = 0
local lastState

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
local function Scream(petName)
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
    scream.text:SetText("FEED ME!!!")
    scream.sub:SetText(petName and (petName .. " is starving") or "")
    scream:SetAlpha(1)
    scream:Show()
end
addon.PetScream = Scream
local function Update()
    local db = DB()
    if not db or not isHunter then return end
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
        frame.title:SetText("|cffff5555No pet out|r")
        frame.sub:SetText("Call your pet")
    elseif state == "dead" then
        frame.title:SetText("|cffff5555" .. name .. " is dead|r")
        frame.sub:SetText("Revive Pet")
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
                Print(string.format("%s needs feeding (%s)%s", name, state, diet and (" - eats " .. diet) or ""))
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

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "UNIT_PET")
pcall(ev.RegisterEvent, ev, "PET_BAR_UPDATE")
pcall(ev.RegisterEvent, ev, "UNIT_HAPPINESS")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        isHunter = select(2, UnitClass("player")) == "HUNTER"
    end
    if isHunter then Update() end
end)

local timer = 0
ev:SetScript("OnUpdate", function(_, dt)
    if not isHunter then return end
    timer = timer + dt
    if timer < 1 then return end
    timer = 0
    Update()
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
        if rest == "on" then db.petRemind = true; Print("pet reminder on")
        elseif rest == "off" then db.petRemind = false; Print("pet reminder off")
        elseif rest == "test" then
            testUntil = GetTime() + 6
            if not isHunter then Print("you are not a hunter - the reminder only runs for hunters, test shown anyway"); isHunter = true end
            Update()
        else
            if not isHunter then Print("you are not a hunter, so there is no pet to watch"); return true end
            Print(string.format("pet: %s, reminder %s", tostring(PetState() or "unknown"), db.petRemind == false and "off" or "on"))
            local diet = Diet()
            if diet then Print("eats: " .. diet) end
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Pet.lua"] = true end end
