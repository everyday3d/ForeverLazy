-- Two small loot helpers, both off until you turn them on (options, or the commands):
--   Sell grey loot: when a vendor opens, the grey (junk) items in your bags are sold, one by one, and the total is said in chat.
--       /lazy sellgray on|off      /lazy sellgray now   (sell them at the open vendor, even with the automatic part off)
--       Items on your protect list (/lazy keep) are never sold.
--   Faster auto loot: when auto loot is on in the game, the loot window is emptied the moment it opens instead of after its delay.
--       /lazy fastloot on|off
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end

--------------------------------------------------------------------------------
-- Grey items (pure logic: tests/loot.lua)
--------------------------------------------------------------------------------
-- slots: { { bag =, slot =, quality =, price = (copper each), count =, locked =, name = }, ... }
-- returns the ones to sell, in order, and the copper they are worth. isKept(name): on the protect list.
function addon.GraySelection(slots, isKept, limit)
    local out, value = {}, 0
    for _, s in ipairs(slots) do
        if #out >= (limit or 120) then break end
        if s.quality == 0 and (s.price or 0) > 0 and not s.locked and not (isKept and s.name and isKept(s.name)) then
            out[#out + 1] = s
            value = value + s.price * (s.count or 1)
        end
    end
    return out, value
end

local function Money(copper)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 or g > 0 then parts[#parts + 1] = s .. "s" end
    parts[#parts + 1] = c .. "c"
    return table.concat(parts, " ")
end
addon.LootMoney = Money

local function BagIds()
    local list = {}
    for b = 0, (_G.NUM_BAG_SLOTS or 4) + (_G.NUM_REAGENTBAG_SLOTS or 0) do list[#list + 1] = b end
    return list
end

local function ReadBags()
    local slots = {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return slots end
    for _, bag in ipairs(BagIds()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == 0 and not info.hasNoValue then
                local name, price
                if info.hyperlink and GetItemInfo then
                    local n, _, _, _, _, _, _, _, _, _, p = GetItemInfo(info.hyperlink)
                    name, price = n, p
                end
                slots[#slots + 1] = { bag = bag, slot = slot, quality = 0, price = price or 0, count = info.stackCount or 1,
                                      locked = info.isLocked, name = name }
            end
        end
    end
    return slots
end

local selling = false
local function MerchantOpen() return _G.MerchantFrame and MerchantFrame:IsShown() end

local function SellGray(announceNone)
    if selling then return end
    if not MerchantOpen() then Print(L("sell grey: open a vendor first")); return end
    local list, value = addon.GraySelection(ReadBags(), addon.IsKeptItem)
    if #list == 0 then
        if announceNone then Print(L("sell grey: no grey items to sell")) end
        return
    end
    selling = true
    local i, sold = 0, 0
    local function Step()
        i = i + 1
        local s = list[i]
        if not s or not MerchantOpen() then
            selling = false
            if sold > 0 then Print(string.format(L("sold %d grey item%s for %s"), sold, sold == 1 and "" or "s", Money(value))) end
            return
        end
        local ok = pcall(C_Container.UseContainerItem, s.bag, s.slot)
        if ok then sold = sold + 1 end
        C_Timer.After(0.12, Step)                  -- one at a time: a flood of sales can get a player disconnected
    end
    Step()
end
addon.SellGrayNow = SellGray

--------------------------------------------------------------------------------
-- Faster auto loot
--------------------------------------------------------------------------------
local lootedAt = 0
local function FastLoot(autoLoot)
    local db = DB()
    if not (db and db.fastLoot == true) then return end
    -- auto loot on (or the key that flips it held down): the game says so in the event, else read the setting
    local auto = autoLoot
    if auto == nil then auto = (GetCVar and GetCVar("autoLootDefault") == "1") end
    if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
    if not auto then return end
    if GetTime() - lootedAt < 0.3 then return end                    -- once per window
    lootedAt = GetTime()
    for slot = (GetNumLootItems and GetNumLootItems() or 0), 1, -1 do
        pcall(LootSlot, slot)
    end
end
addon.FastLootNow = FastLoot

--------------------------------------------------------------------------------
-- Events and commands
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "LOOT_READY" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, autoLoot)
    local db = DB()
    if not db then return end
    if event == "MERCHANT_SHOW" then
        if db.sellGray == true and C_Timer and C_Timer.After then C_Timer.After(0.4, function() pcall(SellGray, false) end) end
    elseif event == "LOOT_READY" then
        pcall(FastLoot, autoLoot)
    end
end)

local function Flag(a) if a == "on" then return true elseif a == "off" then return false end end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    local c = (cmd or ""):lower()
    local a = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    local db = DB()
    if c == "sellgray" or c == "sellgrey" then
        if a == "now" then SellGray(true); return true end
        local f = Flag(a)
        if f ~= nil then db.sellGray = f and true or nil end
        Print(L("sell grey loot at vendors: ") .. (db.sellGray == true and "on" or "OFF") .. L("  (/lazy sellgray on|off, or /lazy sellgray now at an open vendor; items you protect with /lazy keep are never sold)"))
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    elseif c == "fastloot" then
        local f = Flag(a)
        if f ~= nil then db.fastLoot = f and true or nil end
        Print(L("faster auto loot: ") .. (db.fastLoot == true and "on" or "OFF") .. L("  (/lazy fastloot on|off; it works when auto loot is on in the game's options)"))
        if addon.RefreshOptions then addon.RefreshOptions() end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["LootTools.lua"] = true end end
