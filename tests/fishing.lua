-- Fishing helpers (no game needed): lua tests/fishing.lua
-- First the rules, then the buttons, sound, loot and double click run on stand-ins. It cannot say whether the game answers
-- this way, or how the bar looks.
local now = 1000
GetTime = function() return now end
unpack = table.unpack
local combat = false
InCombatLockdown = function() return combat end
local function Frame(name)
    local f = { shown = true, attrs = {}, scripts = {}, name = name }
    f.SetAttribute = function(self, k, v) assert(not combat, "a secure button was changed during a fight"); self.attrs[k] = v end
    f.SetText = function(self, t) self.text = t end
    f.Show = function(self) assert(not combat, "shown during a fight"); self.shown = true end
    f.Hide = function(self) assert(not combat, "hidden during a fight"); self.shown = false end
    f.SetShown = function(self, v) self.shown = v and true or false end
    f.SetScript = function(self, w, fn) self.scripts[w] = fn end
    f.CreateFontString = function() return Frame() end
    f.CreateTexture = function() return Frame() end
    setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    if name then _G[name] = f end
    return f
end
CreateFrame = function(_, name) return Frame(name) end
UIParent, GameTooltip = Frame(), Frame()
local worldClick
WorldFrame = { HookScript = function(_, _, fn) worldClick = fn end }
local timers = {}
C_Timer = { After = function(secs, fn) timers[#timers + 1] = { secs = secs, fn = fn } end }
local function RunTimers() local l = timers; timers = {}; for _, t in ipairs(l) do t.fn() end end

local POLE, SWORD, SHIELD = 6256, 1000, 2000
local worn = { [16] = SWORD, [17] = SHIELD }
local bags = { [1] = POLE }
local counts = { [6529] = 3, [6532] = 1 }
GetInventoryItemID = function(_, slot) return worn[slot] end
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 4 or 0 end, GetContainerItemID = function(_, s) return bags[s] end }
GetItemInfoInstant = function(id) if id == POLE then return id, "", "", "", 0, 2, 20 end return id, "", "", "", 0, 2, 7 end
GetItemInfo = function(x) return "Item " .. tostring(x), nil, nil, nil, nil, nil, nil, nil, nil, nil, 25 end
GetItemCount = function(id) return counts[id] or 0 end
UnitName = function() return "Jim Buck" end
GetRealmName = function() return "Test" end
GetRealZoneText = function() return "Westfall" end
GetSpellInfo = function() return "Fishing" end
local rank = 40
GetNumSkillLines = function() return 2 end
GetSkillLineInfo = function(i) if i == 1 then return "Professions", true end return "Fishing", false, false, rank, 0, 0, 75 end
local enchant = { false }
GetWeaponEnchantInfo = function() return table.unpack(enchant) end
local channel
UnitChannelInfo = function() return channel end
local cvars = { Sound_EnableSFX = "1", Sound_SFXVolume = "0.3", Sound_MusicVolume = "0.8", Sound_AmbienceVolume = "0.6" }
GetCVar = function(n) return cvars[n] end
SetCVar = function(n, v) cvars[n] = v end
local override
SetOverrideBindingClick = function(_, _, key, button) override = key .. ">" .. button end
ClearOverrideBindings = function() override = nil end
local mouseover = false
UnitExists = function() return mouseover end
local fishingLoot, looted = true, {}
IsFishingLoot = function() return fishingLoot end
GetNumLootItems = function() return 2 end
GetLootSlotInfo = function(s) return "icon", s == 1 and "Raw Brilliant Smallfish" or "Driftwood", s == 1 and 2 or 1 end
GetLootSlotLink = function(s) return "link" .. s end
LootSlot = function(s) looted[#looted + 1] = s end

local said = {}
local db = { pos = {} }
local addon = { GetDB = function() return db end, Print = function(s) said[#said + 1] = s end }
local ns = { L = function(s) return s end, addon = addon, api = {} }
assert(loadfile("ForeverLazy/Fishing.lua"))("ForeverLazy", ns)
local F = addon.Fish

local passed, failed = 0, 0
local function test(label, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. label) else failed = failed + 1; print("FAIL  " .. label .. "\n      " .. tostring(err)) end
end
local function eq(a, b) if a ~= b then error("got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end
local function Heard(words) for _, s in ipairs(said) do if s:find(words, 1, true) then return true end end return false end
local function Event(...) F.OnEvent(nil, ...) end

test("the best lure my skill allows", function()
    local have = function(id) return counts[id] or 0 end
    eq(F.BestLure(have, 150).id, 6532)
    eq(F.BestLure(have, 40).id, 6529)
    eq(F.BestLure(function() return 0 end, 150), nil)
end)
test("what the cast and swap buttons do", function()
    eq(F.CastMacro("Fishing", true, nil), "/cast Fishing")
    eq(F.CastMacro("Fishing", false, 6256), "/equipslot [nocombat] 16 item:6256")
    eq(F.CastMacro("Fishing", false, nil), "/cast Fishing")
    eq(F.SwapMacro(true, nil, { main = 1, off = 2 }), "/equipslot 16 item:1\n/equipslot 17 item:2")
    eq(F.SwapMacro(true, nil, nil), nil)
    eq(F.SwapMacro(false, nil, { main = 1 }), nil)
    eq(F.LureMacro({ id = 6529 }), "/use item:6529\n/use 16")
end)
test("pools are told from other wreckage", function()
    assert(F.IsPoolName("Oily Blackmouth School") and F.IsPoolName("Floating Wreckage") and F.IsPoolName("Oil Spill") and F.IsPoolName("Stonescale Eel Swarm"))
    assert(not F.IsPoolName("Zeppelin Debris") and not F.IsPoolName("Shipwreck Debris") and not F.IsPoolName("Strange Debris"))
end)
test("everything is off to begin with: no bar, no sound change, no looting, nothing written down", function()
    Event("PLAYER_LOGIN"); RunTimers()
    assert(_G.ForeverLazy_Fish, "no button for the key")
    eq(_G.ForeverLazy_FishBar, nil)
    worn = { [16] = POLE }; bags = { [1] = SWORD }
    channel = "Fishing"; Event("UNIT_SPELLCAST_CHANNEL_START", "player")
    eq(cvars.Sound_MusicVolume, "0.8")
    Event("LOOT_READY"); Event("LOOT_CLOSED")
    eq(#looted, 0); eq(db.fishCatch, nil)
    F.RightDown(); now = now + 0.2; F.RightDown(); eq(override, nil)
    channel = nil; Event("UNIT_SPELLCAST_CHANNEL_STOP", "player"); RunTimers()
    worn = { [16] = SWORD, [17] = SHIELD }; bags = { [1] = POLE }
end)
test("the pole button remembers the weapons and gives them back", function()
    db.fishSwap = true
    Event("PLAYER_EQUIPMENT_CHANGED"); RunTimers()
    eq(ForeverLazy_PoleSwap.attrs.macrotext1, "/equipslot [nocombat] 16 item:6256")
    assert(ForeverLazy_FishBar.shown)
    eq(ForeverLazy_FishBarSwap.text, "Pole")
    worn = { [16] = POLE }; bags = { [1] = SWORD, [2] = SHIELD }
    Event("PLAYER_EQUIPMENT_CHANGED"); RunTimers()
    eq(ForeverLazy_PoleSwap.attrs.macrotext1, "/equipslot 16 item:1000\n/equipslot 17 item:2000")
    eq(ForeverLazy_FishBarSwap.text, "Weapons")
    eq(ForeverLazy_Fish.attrs.macrotext1, "/cast Fishing")
end)
test("nothing secure is touched during a fight, and it catches up afterwards", function()
    combat = true
    worn = { [16] = SWORD, [17] = SHIELD }; bags = { [1] = POLE }
    Event("PLAYER_EQUIPMENT_CHANGED"); RunTimers()
    Event("BAG_UPDATE_DELAYED")
    eq(ForeverLazy_FishBarSwap.text, "Weapons")
    combat = false
    Event("PLAYER_REGEN_ENABLED")
    eq(ForeverLazy_FishBarSwap.text, "Pole")
end)
test("the lure button, and one warning each time it is needed", function()
    db.fishSwap, db.fishLure = nil, true
    F.Update(); assert(not ForeverLazy_FishBar.shown, "with only the lure ticked the bar waits for the pole")
    worn = { [16] = POLE }; bags = {}
    F.Update(); assert(ForeverLazy_FishBar.shown)
    eq(ForeverLazy_FishBarLure.attrs.macrotext1, "/use item:6529\n/use 16")
    said = {}
    F.LureWarning(); F.LureWarning(); eq(#said, 1); assert(Heard("No lure"))
    enchant = { true, 300000 }; said = {}; F.LureWarning(); eq(#said, 0)
    enchant = { true, 45000 }; F.LureWarning(); F.LureWarning(); eq(#said, 1); assert(Heard("about to wear off"))
end)
test("the splash is louder while the line is out, and the settings come back", function()
    db.fishSound = true
    channel = "Fishing"; Event("UNIT_SPELLCAST_CHANNEL_START", "player")
    eq(cvars.Sound_SFXVolume, "1"); eq(cvars.Sound_MusicVolume, "0")
    Event("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    eq(cvars.Sound_MusicVolume, "0", "kept for the loot")
    Event("UNIT_SPELLCAST_CHANNEL_START", "player"); RunTimers()
    eq(cvars.Sound_MusicVolume, "0")
    Event("UNIT_SPELLCAST_CHANNEL_STOP", "player"); RunTimers()
    eq(cvars.Sound_SFXVolume, "0.3"); eq(cvars.Sound_MusicVolume, "0.8"); eq(cvars.Sound_AmbienceVolume, "0.6"); eq(db.fishSoundSaved, nil)
end)
test("a fight or a logout puts the sound back at once, and so does the next login", function()
    F.SoundUp(); Event("PLAYER_REGEN_DISABLED"); eq(cvars.Sound_MusicVolume, "0.8")
    F.SoundUp(); F.SoundUp(); Event("PLAYER_LOGOUT"); eq(cvars.Sound_MusicVolume, "0.8")
    F.SoundUp(); Event("PLAYER_LOGIN"); eq(cvars.Sound_MusicVolume, "0.8"); RunTimers()
end)
test("another channel changes nothing", function()
    channel = "Drain Life"; Event("UNIT_SPELLCAST_CHANNEL_START", "player"); eq(cvars.Sound_MusicVolume, "0.8")
end)
test("the catch is written down once and picked up", function()
    db.fishLog, db.fishAutoLoot, looted = true, true, {}
    Event("LOOT_READY"); Event("LOOT_OPENED"); Event("LOOT_CLOSED")
    eq(#looted, 2); eq(db.fishCatch.Westfall["Raw Brilliant Smallfish"].n, 2)
    local list, total, value = F.Summary(db.fishCatch.Westfall)
    eq(list[1].name, "Raw Brilliant Smallfish"); eq(total, 3); eq(value, 75)
    said = {}; addon:HandleExtraCommand("fish", "log"); assert(Heard("caught in Westfall: 3"))
end)
test("other loot is left alone", function()
    fishingLoot, looted = false, {}
    Event("LOOT_READY"); Event("LOOT_CLOSED")
    eq(#looted, 0); eq(db.fishCatch.Westfall["Driftwood"].n, 1)
    fishingLoot = true
end)
test("double right-click lends the button once and gives it back", function()
    db.fishDoubleClick = true
    now = now + 5; worldClick(nil, "RightButton"); eq(override, nil)
    now = now + 0.2; worldClick(nil, "RightButton"); eq(override, "BUTTON2>ForeverLazy_Fish")
    ForeverLazy_Fish.scripts.PostClick(nil, "LeftButton", true); assert(override, "gone before the release")
    ForeverLazy_Fish.scripts.PostClick(nil, "LeftButton", false); eq(override, nil)
    now = now + 5; F.RightDown(); now = now + 0.2; F.RightDown(); RunTimers(); eq(override, nil)
end)
test("not on a creature, not without the pole, not slowly", function()
    mouseover = true; now = now + 5; F.RightDown(); now = now + 0.2; F.RightDown(); eq(override, nil)
    mouseover = false; now = now + 5; F.RightDown(); now = now + 1; F.RightDown(); eq(override, nil)
    worn = { [16] = SWORD }; now = now + 5; F.RightDown(); now = now + 0.2; F.RightDown(); eq(override, nil)
end)
test("skill and points gained", function()
    worn = { [16] = POLE }; db.fishSkill = true
    rank = 43
    F.Update()
    said = {}; addon:HandleExtraCommand("fish", "status"); assert(Heard("fishing skill 43 of 75, 3 gained"), table.concat(said, " / "))
end)
test("/lazy fish 2 is still the pool finder's", function()
    local got
    ns.addon.HandleExtraCommand(addon, "fish", "log all")
    eq(addon:HandleExtraCommand("fish", "2"), nil)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
