-- When you learn a new rank of a spell, put it on your action bars in place of the old rank.
-- Switch it off in Forever Lazy's options ("Newest spell rank on my action bars").
-- Bars cannot be changed in combat, so a spell learned mid-fight is swapped when the fight ends.
local ADDON, ns = ...
local L = ns.L
local addon = ns.addon
local Print = addon.Print

local function DB() return addon.GetDB() end
local function Enabled() local db = DB(); return not (db and db.rankUp == false) end

-- spells whose rank I want to keep as it is (a low rank on purpose): db.rankKeep[lower case name] = true
local function Kept(name)
    local db = DB()
    local k = db and db.rankKeep
    return k and name and k[name:lower()] and true or false
end

-- "/lazy rankup keep <spell>": a name, or a spell link shift-clicked into the line
local function SpellFromText(text)
    text = tostring(text or "")
    local linked = text:match("%[(.-)%]")
    return ((linked or text):gsub("^%s+", ""):gsub("%s+$", ""))
end

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

-- picking a spell up moved to C_Spell on newer clients
local function Pickup(id)
    if PickupSpell then return PickupSpell(id) end
    if C_Spell and C_Spell.PickupSpell then return C_Spell.PickupSpell(id) end
end
local function CanPickup() return (PickupSpell or (C_Spell and C_Spell.PickupSpell)) and true or false end

local pending, running = false, false

local function Run(verbose)
    verbose = verbose == true                      -- only the button and the command say anything when nothing changes
    pending = false
    if running or not Enabled() then
        if verbose then Print(L("action bars: ") .. (running and "already busy" or "switched off in the options")) end
        return
    end
    if InCombatLockdown() then pending = true; if verbose then Print(L("action bars: in combat, I will do it when the fight ends")) end; return end
    if GetCursorInfo and GetCursorInfo() then pending = true; if verbose then Print(L("action bars: you are carrying something, put it down first")) end; return end
    if not (GetActionInfo and CanPickup() and PlaceAction) then
        if verbose then
            local gone = {}
            if not GetActionInfo then gone[#gone + 1] = "GetActionInfo" end
            if not CanPickup() then gone[#gone + 1] = "PickupSpell (or C_Spell.PickupSpell)" end
            if not PlaceAction then gone[#gone + 1] = "PlaceAction" end
            Print(L("action bars: this client is missing ") .. table.concat(gone, ", "))
        end
        return
    end
    running = true
    local best = KnownBest()
    local swapped = 0
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and id then
            local name = SpellName(id)
            local b = name and not Kept(name) and best[name]
            if b and b.id ~= id and b.rank > SpellRank(id) then
                local ok = pcall(Pickup, b.id)
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
    if swapped > 0 then Print(L("action bars: put the newest rank of ") .. swapped .. L(" spell") .. (swapped == 1 and "" or "s") .. L(" in place of the old one") .. (swapped == 1 and "" or "s") .. ".")
    elseif verbose then Print(L("action bars: nothing to change (every spell on them is already its newest rank). /lazy rankup debug shows what I see.")) end
end
addon.RankUpRun = function() Run(true) end

-- /lazy rankup debug: what the bars and the spellbook look like to this addon (a popup you can copy)
local function Debug()
    local dbg = {}
    dbg[#dbg + 1] = string.format("api: GetNumSpellTabs=%s GetSpellBookItemName=%s GetSpellBookItemInfo=%s C_SpellBook=%s", tostring(GetNumSpellTabs ~= nil),
        tostring(GetSpellBookItemName ~= nil), tostring(GetSpellBookItemInfo ~= nil), tostring(C_SpellBook ~= nil))
    dbg[#dbg + 1] = string.format("api: GetActionInfo=%s PickupSpell/C_Spell.PickupSpell=%s PlaceAction=%s C_Spell.GetSpellSubtext=%s GetSpellSubtext=%s", tostring(GetActionInfo ~= nil),
        tostring(CanPickup()), tostring(PlaceAction ~= nil), tostring(C_Spell and C_Spell.GetSpellSubtext ~= nil), tostring(GetSpellSubtext ~= nil))
    dbg[#dbg + 1] = "enabled: " .. tostring(Enabled()) .. "  combat: " .. tostring(InCombatLockdown()) .. "  cursor: " .. tostring(GetCursorInfo and GetCursorInfo() or nil)
    local best = KnownBest()
    local n = 0
    for _ in pairs(best) do n = n + 1 end
    dbg[#dbg + 1] = "spellbook: " .. n .. " different spells read"
    local shown = 0
    local kinds = {}
    for slot = 1, 180 do
        local kind, id
        if GetActionInfo then kind, id = GetActionInfo(slot) end
        if kind and kind ~= "spell" then kinds[kind] = (kinds[kind] or 0) + 1 end
        if kind == "spell" and id then
            local name = SpellName(id)
            local b = name and best[name]
            shown = shown + 1
            local kept = name and Kept(name)
            if kept then b = nil end
            if shown <= 40 then
                dbg[#dbg + 1] = string.format("slot %d: %s id %s rank %s | book: %s", slot, tostring(name), tostring(id), tostring(SpellRank(id)),
                    b and ("id " .. tostring(b.id) .. " rank " .. tostring(b.rank) .. (b.id ~= id and b.rank > SpellRank(id) and "  -> WOULD SWAP" or "")) or (kept and "kept as it is (you chose to keep this rank)" or "not found in the spellbook"))
            end
        end
    end
    dbg[#dbg + 1] = "spells on the bars: " .. shown
    local other = {}
    for k, n in pairs(kinds) do other[#other + 1] = k .. " x" .. n end
    table.sort(other)
    dbg[#dbg + 1] = "other things on the bars: " .. (#other > 0 and table.concat(other, ", ") or "none")
    if addon.ShowTextPopup then addon.ShowTextPopup(L("Spell rank debug"), table.concat(dbg, "\n")) else Print(table.concat(dbg, "\n")) end
end

local prevCmd = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "rankup" then
        local raw = ((rest or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        local a = raw:lower()
        local db = DB()
        local verb, arg = a:match("^(%a+)%s*(.*)$")
        if a == "debug" then Debug()
        elseif verb == "keep" and arg ~= "" then
            local name = SpellFromText(raw:match("^%a+%s+(.*)$"))
            db.rankKeep = db.rankKeep or {}
            db.rankKeep[name:lower()] = true
            Print(L("action bars: ") .. name .. L(" keeps whatever rank you put on the bar. /lazy rankup unkeep ") .. name .. L(" undoes it."))
        elseif verb == "unkeep" and arg ~= "" then
            local name = SpellFromText(raw:match("^%a+%s+(.*)$"))
            if db.rankKeep then db.rankKeep[name:lower()] = nil end
            Print(L("action bars: ") .. name .. L(" gets its newest rank again."))
        elseif a == "keep" or a == "list" then
            local names = {}
            for n in pairs(db.rankKeep or {}) do names[#names + 1] = n end
            table.sort(names)
            Print(L("action bars: ranks kept as they are: ") .. (#names > 0 and table.concat(names, ", ") or "none") .. L(". /lazy rankup keep <spell> adds one."))
        else Run(true) end
        return true
    end
    if prevCmd then return prevCmd(self, cmd, rest) end
end

local function Soon()
    if not Enabled() then return end
    if C_Timer and C_Timer.After then C_Timer.After(0.7, Run) else Run() end
end

local ev = CreateFrame("Frame")
-- an event this game does not know makes RegisterEvent fail, so each one is tried on its own (LEARNED_SPELL_IN_TAB is an old one)
for _, e in ipairs({ "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    Soon()
end)

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["RankUp.lua"] = true end end
