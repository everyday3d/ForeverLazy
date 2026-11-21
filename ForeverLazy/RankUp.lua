-- When you learn a new rank of a spell, put it on your action bars in place of the old rank.
-- Switch it off in Forever Lazy's options ("Newest spell rank on my action bars").
-- Bars cannot be changed in combat, so a spell learned mid-fight is swapped when the fight ends.
local ADDON, ns = ...
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function Enabled() local db = DB(); return not (db and db.rankUp == false) end

local function RankNum(sub)
    return tonumber(tostring(sub or ""):match("(%d+)")) or 0
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id); if ok and n then return n end end
    if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok then return type(n) == "table" and n.name or n end end
end

local function SpellRank(id)
    local sub
    if C_Spell and C_Spell.GetSpellSubtext then local ok, s = pcall(C_Spell.GetSpellSubtext, id); if ok then sub = s end end
    if not sub and GetSpellSubtext then local ok, s = pcall(GetSpellSubtext, id); if ok then sub = s end end
    return RankNum(sub)
end

-- every spell I know: best[name] = { id =, rank = } for the highest rank
local function KnownBest()
    local best = {}
    local function Add(id, name, sub)
        if not (id and name) then return end
        local r = RankNum(sub)
        if r == 0 then r = SpellRank(id) end
        local b = best[name]
        if not b or r > b.rank then best[name] = { id = id, rank = r } end
    end
    if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
                local kind, id
                if GetSpellBookItemInfo then
                    local ok, k, v = pcall(GetSpellBookItemInfo, i, "spell")
                    if ok then kind, id = k, v end
                end
                if kind == nil or kind == "SPELL" then
                    local ok, name, sub, sid = pcall(GetSpellBookItemName, i, "spell")
                    if ok and name then Add(id or sid, name, sub) end
                end
            end
        end
    elseif C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if li then
                for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                    local si = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if si and si.spellID and not si.isPassive then Add(si.spellID, si.name, si.subName) end
                end
            end
        end
    end
    return best
end

local pending, running = false, false

local function Run()
    pending = false
    if running or not Enabled() then return end
    if InCombatLockdown() then pending = true; return end
    if GetCursorInfo and GetCursorInfo() then pending = true; return end     -- carrying something: try again later
    if not (GetActionInfo and PickupSpell and PlaceAction) then return end
    running = true
    local best = KnownBest()
    local swapped = 0
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and id then
            local name = SpellName(id)
            local b = name and best[name]
            if b and b.id ~= id and b.rank > SpellRank(id) then
                local ok = pcall(PickupSpell, b.id)
                if ok and GetCursorInfo and GetCursorInfo() == "spell" then
                    PlaceAction(slot)
                    if ClearCursor then ClearCursor() end
                    swapped = swapped + 1
                elseif ClearCursor then
                    ClearCursor()
                end
            end
        end
    end
    running = false
    if swapped > 0 then Print("action bars: put the newest rank of " .. swapped .. " spell" .. (swapped == 1 and "" or "s") .. " in place of the old one" .. (swapped == 1 and "" or "s") .. ".") end
end
addon.RankUpRun = Run

local function Soon()
    if not Enabled() then return end
    if C_Timer and C_Timer.After then C_Timer.After(0.7, Run) else Run() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("LEARNED_SPELL_IN_TAB")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    Soon()
end)
