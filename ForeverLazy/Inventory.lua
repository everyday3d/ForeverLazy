-- Item tooltips that say where you have an item: in your bags, your bank, your mail, worn, and on your other
-- characters too ("Beef: 12 in bags, 38 in bank"). Each character's stock is remembered when you play it.
--   /lazy has <part of an item name>      list what each character has of matching items
-- Bank and mail are remembered from the last time you opened them.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function DB() return addon.GetDB() end

-- the realm name is sometimes empty right after logging in: use the last good one so a character never splits in two
local function RealmNow()
    local r = GetRealmName and GetRealmName() or ""
    local root = addon.GetRoot and addon.GetRoot()
    if r ~= "" then
        if root then root.lastRealm = r end
        return r
    end
    return root and root.lastRealm or ""
end

local function Key()
    return (UnitName("player") or "?") .. "-" .. RealmNow()
end

local function Store()
    local root = addon.GetRoot()
    root.inv = root.inv or {}
    return root.inv
end

local function Me()
    local inv = Store()
    local k = Key()
    inv[k] = inv[k] or {}
    local me = inv[k]
    me.name = UnitName("player")
    -- the full name: this server gives each character a second part ("Tank Hanks") as the realm part of the name
    local okF, n, r = pcall(UnitFullName, "player")
    if okF and n and r and r ~= "" then me.full = n .. " " .. r else me.full = nil end
    me.realm = RealmNow()
    me.class = select(2, UnitClass("player"))
    me.faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    return me
end

--------------------------------------------------------------------------------
-- Reading what I have
--------------------------------------------------------------------------------
local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
end

local function ItemAt(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount or 1 end
        return nil
    end
    if GetContainerItemLink then
        local link = GetContainerItemLink(bag, slot)
        if link then
            local _, count = GetContainerItemInfo(bag, slot)
            return tonumber(link:match("item:(%d+)")), count or 1
        end
    end
end

local function ScanContainers(list)
    local items = {}
    for _, bag in ipairs(list) do
        for slot = 1, NumSlots(bag) do
            local id, count = ItemAt(bag, slot)
            if id then items[id] = (items[id] or 0) + count end
        end
    end
    return items
end

-- the containers I carry: the backpack, my bags and the reagent bag
local function BagIds()
    local list = {}
    for b = 0, (_G.NUM_BAG_SLOTS or 4) + (_G.NUM_REAGENTBAG_SLOTS or 0) do list[#list + 1] = b end
    return list
end

-- the bank's containers. A container I carry is never part of the bank, whatever number this client gives the bank: counting one
-- would show my bag contents as "in bank" too.
local function BankIds()
    local mine, seen, list = {}, {}, {}
    for _, b in ipairs(BagIds()) do mine[b] = true end
    local function Add(b) if type(b) == "number" and not mine[b] and not seen[b] then seen[b] = true; list[#list + 1] = b end end
    Add(_G.BANK_CONTAINER or -1)
    local bi = Enum and Enum.BagIndex
    if type(bi) == "table" then
        for name, v in pairs(bi) do
            if type(name) == "string" and (name == "Bank" or name:find("^BankBag") or name:find("^CharacterBankTab")) then Add(v) end
        end
    end
    local first = (_G.NUM_BAG_SLOTS or 4) + (_G.NUM_REAGENTBAG_SLOTS or 0) + 1
    for b = first, first + (_G.NUM_BANKBAGSLOTS or 7) - 1 do Add(b) end
    table.sort(list)
    return list
end

local function ScanBags()
    Me().bags = ScanContainers(BagIds())
end

local function ScanBank()
    local list = BankIds()
    local me = Me()
    me.bank = ScanContainers(list)
    me.bankTime = time()
end

local function ScanWorn()
    local items = {}
    for slot = 1, 19 do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id then items[id] = (items[id] or 0) + 1 end
    end
    Me().worn = items
end

local function ScanMail()
    if not (GetInboxNumItems and GetInboxItem) then return end
    local items = {}
    for i = 1, (GetInboxNumItems() or 0) do
        for j = 1, 12 do
            local ok, name, id, _, count = pcall(GetInboxItem, i, j)
            if not ok or not name then break end
            id = tonumber(id)
            if not id and GetInboxItemLink then
                local link = GetInboxItemLink(i, j)
                id = link and tonumber(link:match("item:(%d+)"))
            end
            if id then items[id] = (items[id] or 0) + (tonumber(count) or 1) end
        end
    end
    local me = Me()
    me.mail = items
    me.mailTime = time()
end

-- The guild bank: each tab is read when the bank sends it. Opening the bank asks for every tab you can see, one by one.
local function GuildStore()
    local root = addon.GetRoot()
    root.guildBank = root.guildBank or {}
    return root.guildBank
end

local function MyGuild()
    local name = GetGuildInfo and GetGuildInfo("player")
    return name
end

local queryingTab
local function ScanGuildTab(tab)
    local guild = MyGuild()
    if not guild or not tab or not GetGuildBankItemLink then return end
    local items = {}
    for slot = 1, 98 do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            local count = 1
            if GetGuildBankItemInfo then
                local _, c = GetGuildBankItemInfo(tab, slot)
                count = tonumber(c) or 1
            end
            if id then items[id] = (items[id] or 0) + count end
        end
    end
    local store = GuildStore()
    store[guild] = store[guild] or { tabs = {} }
    store[guild].tabs[tab] = items
    store[guild].t = time()
end

local function GuildCount(guild, id)
    local g = GuildStore()[guild]
    if not g then return 0 end
    local n = 0
    for _, items in pairs(g.tabs or {}) do n = n + (items[id] or 0) end
    return n
end

local function QueryAllGuildTabs()
    local n = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    for i = 1, n do
        local _, _, viewable = GetGuildBankTabInfo(i)
        if viewable and QueryGuildBankTab then
            C_Timer.After(i * 1.2, function()
                if _G.GuildBankFrame and not GuildBankFrame:IsShown() then return end
                queryingTab = i
                pcall(QueryGuildBankTab, i)
            end)
        end
    end
    C_Timer.After((n + 1) * 1.2, function() queryingTab = nil end)
end
local bankOpen = false
local pending
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_OPENED",
                     "BANKFRAME_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKBAGSLOTS_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if not C_Timer or not C_Timer.After then return end
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        C_Timer.After(0.6, function() if bankOpen then pcall(ScanBank) end end)
    elseif event == "BANKFRAME_CLOSED" then
        pcall(ScanBank); bankOpen = false
    elseif event == "GUILDBANKFRAME_OPENED" then
        C_Timer.After(1, function() pcall(QueryAllGuildTabs) end)
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        local tab = queryingTab or (GetCurrentGuildBankTab and GetCurrentGuildBankTab())
        C_Timer.After(0.3, function() pcall(ScanGuildTab, tab) end)
    elseif event == "MAIL_INBOX_UPDATE" or event == "MAIL_CLOSED" then
        C_Timer.After(0.5, function() pcall(ScanMail) end)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(0.5, function() pcall(ScanWorn) end)
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(4, function() pcall(ScanBags); pcall(ScanWorn) end)
    else
        -- bags changed: one scan a moment later, however many events came
        if pending then return end
        pending = true
        C_Timer.After(1, function()
            pending = false
            pcall(ScanBags)
            if bankOpen then pcall(ScanBank) end
        end)
    end
end)

--------------------------------------------------------------------------------
-- The tooltip
--------------------------------------------------------------------------------
local PLACES = { { "bags", "in bags" }, { "bank", "in bank" }, { "mail", "in mail" }, { "worn", "worn" } }

local function CountsFor(c, id, isMe)
    local out, total = {}, 0
    for _, p in ipairs(PLACES) do
        local n
        if isMe and p[1] == "bags" then
            n = (GetItemCount and GetItemCount(id, false)) or (c.bags and c.bags[id]) or 0
        else
            n = c[p[1]] and c[p[1]][id] or 0
        end
        if n and n > 0 then
            out[#out + 1] = string.format("%d %s", n, p[2])
            total = total + n
        end
    end
    return out, total
end

local function ClassColour(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function AddCounts(tt, id)
    local db = DB()
    if not db or db.itemTooltip == false or not id or not tt or not tt.AddDoubleLine then return end
    if tt.flInv == id then return end
    local inv = Store()
    local myKey = Key()
    Me()
    local rows, grand, places = {}, 0, 0
    local keys = {}
    for k in pairs(inv) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if a == myKey then return true elseif b == myKey then return false end
        return (inv[a].name or a) < (inv[b].name or b)
    end)
    -- One character can have been saved more than once under different realm spellings (a half-saved copy, the server name, the
    -- name part). Those copies are the same character: list one of them. Mine wins, then the copy that has the full name.
    local keep, groupOf = {}, {}
    for _, k in ipairs(keys) do
        local c = inv[k]
        local first = ((c.full or c.name or k):match("^(%S+)") or k):match("^([^%-]+)") or k
        local group = first .. "|" .. tostring(c.class)
        local cur = groupOf[group]
        if not cur or k == myKey or (cur ~= myKey and c.full and not inv[cur].full) then groupOf[group] = k end
    end
    for _, k in pairs(groupOf) do keep[k] = true end
    for _, k in ipairs(keys) do
        local c = inv[k]
        local ghost = not keep[k]
        if not ghost and (k == myKey or db.itemTooltipAlts ~= false) then
            local parts, total = CountsFor(c, id, k == myKey)
            if total > 0 then
                local name = (k == myKey) and "You" or (c.full or c.name or k)
                if k ~= myKey and not c.full and (c.realm or "") ~= "" and c.realm ~= RealmNow() then name = name .. "-" .. c.realm end
                rows[#rows + 1] = { name, table.concat(parts, ", "), c.class, k == myKey }
                grand = grand + total
                places = places + #parts
            end
        end
    end
    -- guild banks I have looked inside
    if db.itemTooltipAlts ~= false then
        local mine = MyGuild()
        local names = {}
        for g in pairs(GuildStore()) do names[#names + 1] = g end
        table.sort(names, function(a, b)
            if a == mine then return true elseif b == mine then return false end
            return a < b
        end)
        for _, g in ipairs(names) do
            local n = GuildCount(g, id)
            if n > 0 then
                rows[#rows + 1] = { "<" .. g .. ">", string.format("%d in guild bank", n), nil, false, true }
                grand = grand + n
                places = places + 1
            end
        end
    end
    if #rows == 0 then return end
    tt.flInv = id
    tt:AddLine(" ")
    for _, r in ipairs(rows) do
        local cr, cg, cb = ClassColour(r[3])
        if r[5] then cr, cg, cb = 0.25, 0.85, 0.75 end
        tt:AddDoubleLine(r[1], r[2], cr, cg, cb, 1, 1, 1)
    end
    if #rows > 1 or places > 1 then
        tt:AddDoubleLine("Total", tostring(grand), 1, 0.82, 0, 1, 0.82, 0)
    end
    if tt.Show then tt:Show() end
end

local function Hook()
    local hooked = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
            local id = data and data.id
            if id then AddCounts(tt, id) end
        end)
        hooked = ok
    end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
        local tt = _G[name]
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) self.flInv = nil end)
            if not hooked then
                pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    local id = link and tonumber(link:match("item:(%d+)"))
                    if id then AddCounts(self, id) end
                end)
            end
        end
    end
end

local hookEv = CreateFrame("Frame")
pcall(hookEv.RegisterEvent, hookEv, "PLAYER_LOGIN")
hookEv:SetScript("OnEvent", function() pcall(Hook) end)

--------------------------------------------------------------------------------
-- /lazy has <name>
--------------------------------------------------------------------------------
local function ItemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if n then return n end
    n = GetItemInfo and GetItemInfo(id)
    return n
end

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "inventory" then
        -- /lazy inventory: which containers are counted as my bags and as my bank (to check a wrong count)
        local function Show(name, ids)
            local parts = {}
            for _, b in ipairs(ids) do parts[#parts + 1] = string.format("%d (%d slots)", b, NumSlots(b)) end
            Print(name .. ": " .. table.concat(parts, ", "))
        end
        Show(L("bags are"), BagIds())
        Show(L("bank is"), BankIds())
        return true
    end
    if (cmd or ""):lower() == "has" then
        local want = ((rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
        if want == "" then Print(L("/lazy has <part of an item name>, for example /lazy has cured light hide")); return true end
        local inv = Store()
        Me()
        local found = 0
        local seen = {}
        for k, c in pairs(inv) do
            for _, p in ipairs(PLACES) do
                for id in pairs(c[p[1]] or {}) do
                    if not seen[id] then
                        seen[id] = true
                        local name = ItemName(id)
                        if name and name:lower():find(want, 1, true) then
                            found = found + 1
                            local bits = {}
                            for k2, c2 in pairs(inv) do
                                local parts, total = CountsFor(c2, id, k2 == Key())
                                if total > 0 then bits[#bits + 1] = string.format("%s: %s", k2 == Key() and "you" or (c2.full or c2.name or k2), table.concat(parts, ", ")) end
                            end
                            Print(string.format("%s - %s", name, table.concat(bits, "; ")))
                        end
                    end
                end
            end
        end
        if found == 0 then Print(L("none of your characters has anything like that (open your bank and mailbox once on each character so I can see them)")) end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Inventory.lua"] = true end end
