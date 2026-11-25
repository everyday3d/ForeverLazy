-- Offline tests for selling grey loot and faster auto loot (no game needed).   lua tests/loot.lua
local root = (arg and arg[0] or "tests/loot.lua"):gsub("[/\\]tests[/\\]loot%.lua$", ""):gsub("^tests[/\\]loot%.lua$", ".")

local db = {}
local said = {}
local addon = { Print = function(m) said[#said + 1] = m end, GetDB = function() return db end, RefreshOptions = function() end,
                IsKeptItem = function(name) return name == "Cozy Sleeping Bag" end }
local ns = { addon = addon, L = function(x) return x end }

local onEvent
function CreateFrame()
    local f = setmetatable({}, { __index = function() return function() end end })
    f.SetScript = function(_, n, fn) if n == "OnEvent" then onEvent = fn end end
    return f
end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers() while #timers > 0 do local t = table.remove(timers, 1); t() end end
local now = 100
function GetTime() return now end

assert(loadfile(root .. "/ForeverLazy/LootTools.lua"))("ForeverLazy", ns)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "differs") .. ": got " .. tostring(a) .. ", wanted " .. tostring(b), 2) end end

--------------------------------------------------------------------------------
test("only grey items with a price are chosen, and the total is right", function()
    local slots = {
        { bag = 0, slot = 1, quality = 0, price = 5, count = 3, name = "Broken Fang" },
        { bag = 0, slot = 2, quality = 1, price = 50, count = 1, name = "Linen Cloth" },
        { bag = 0, slot = 3, quality = 0, price = 0, count = 1, name = "Quest Junk" },
        { bag = 1, slot = 1, quality = 0, price = 10, count = 1, name = "Torn Rag" },
    }
    local out, value = addon.GraySelection(slots)
    eq(#out, 2); eq(value, 25, "5 x 3 + 10")
end)

test("a protected item and a locked one are never sold", function()
    local slots = {
        { bag = 0, slot = 1, quality = 0, price = 8, count = 1, name = "Cozy Sleeping Bag" },
        { bag = 0, slot = 2, quality = 0, price = 8, count = 1, locked = true, name = "Rusty Nail" },
        { bag = 0, slot = 3, quality = 0, price = 8, count = 1, name = "Tattered Cloth" },
    }
    local out = addon.GraySelection(slots, addon.IsKeptItem)
    eq(#out, 1); eq(out[1].name, "Tattered Cloth")
end)

test("a limit stops a runaway sale", function()
    local slots = {}
    for i = 1, 200 do slots[i] = { bag = 0, slot = i, quality = 0, price = 1, count = 1, name = "x" .. i } end
    eq(#addon.GraySelection(slots, nil, 50), 50)
end)

test("money reads like the game's", function()
    eq(addon.LootMoney(12345), "1g 23s 45c"); eq(addon.LootMoney(250), "2s 50c"); eq(addon.LootMoney(7), "7c")
end)

--------------------------------------------------------------------------------
-- a vendor and bags
local bags, sold, merchantOpen = {}, {}, true
NUM_BAG_SLOTS = 4
C_Container = {
    GetContainerNumSlots = function(b) return bags[b] and 8 or 0 end,
    GetContainerItemInfo = function(b, s) return bags[b] and bags[b][s] or nil end,
    UseContainerItem = function(b, s) sold[#sold + 1] = b .. ":" .. s end,
}
MerchantFrame = { IsShown = function() return merchantOpen end }
local prices = { ["|Hitem:1|h[Broken Fang]|h"] = 5, ["|Hitem:2|h[Torn Rag]|h"] = 10, ["|Hitem:3|h[Cozy Sleeping Bag]|h"] = 20 }
function GetItemInfo(link)
    local name = link:match("%[(.-)%]")
    return name, link, 0, 1, 1, "", "", 1, "", 0, prices[link]
end

test("opening a vendor with the option off sells nothing", function()
    bags = { [0] = { [1] = { quality = 0, hyperlink = "|Hitem:1|h[Broken Fang]|h", stackCount = 2 } } }
    sold = {}; db.sellGray = nil
    onEvent(nil, "MERCHANT_SHOW"); RunTimers()
    eq(#sold, 0)
end)

test("opening a vendor with the option on sells the grey items and says the total", function()
    bags = { [0] = { [1] = { quality = 0, hyperlink = "|Hitem:1|h[Broken Fang]|h", stackCount = 2 },
                     [2] = { quality = 1, hyperlink = "|Hitem:9|h[Linen Cloth]|h", stackCount = 1 },
                     [3] = { quality = 0, hyperlink = "|Hitem:3|h[Cozy Sleeping Bag]|h", stackCount = 1 } },
             [1] = { [1] = { quality = 0, hyperlink = "|Hitem:2|h[Torn Rag]|h", stackCount = 1 } } }
    sold = {}; said = {}; db.sellGray = true
    onEvent(nil, "MERCHANT_SHOW"); RunTimers()
    table.sort(sold)
    eq(table.concat(sold, ","), "0:1,1:1", "the sleeping bag is protected, the cloth is white")
    assert(said[#said]:find("sold 2 grey items for 20c"), said[#said])
    db.sellGray = nil
end)

test("a vendor that closes stops the selling", function()
    bags = { [0] = { [1] = { quality = 0, hyperlink = "|Hitem:1|h[Broken Fang]|h", stackCount = 1 }, [2] = { quality = 0, hyperlink = "|Hitem:2|h[Torn Rag]|h", stackCount = 1 } } }
    sold = {}; db.sellGray = true
    onEvent(nil, "MERCHANT_SHOW")
    table.remove(timers, 1)()                       -- the first sale goes through after the short wait
    merchantOpen = false
    RunTimers()
    merchantOpen = true; db.sellGray = nil
    assert(#sold <= 1, "nothing more once the vendor closed: " .. #sold)
end)

test("/lazy sellgray now sells even with the automatic part off", function()
    bags = { [0] = { [1] = { quality = 0, hyperlink = "|Hitem:1|h[Broken Fang]|h", stackCount = 1 } } }
    sold = {}; db.sellGray = nil
    addon:HandleExtraCommand("sellgray", "now"); RunTimers()
    eq(#sold, 1)
end)

--------------------------------------------------------------------------------
test("faster auto loot empties the window when it is on and auto loot is on", function()
    local taken = {}
    function GetNumLootItems() return 3 end
    function LootSlot(i) taken[#taken + 1] = i end
    function GetCVar() return "1" end
    function IsModifiedClick() return false end
    db.fastLoot = true; now = now + 10
    onEvent(nil, "LOOT_READY", true)
    eq(table.concat(taken, ","), "3,2,1")
end)

test("faster auto loot does nothing when it is off, or when auto loot is off", function()
    local taken = {}
    function LootSlot(i) taken[#taken + 1] = i end
    db.fastLoot = nil; now = now + 10
    onEvent(nil, "LOOT_READY", true); eq(#taken, 0, "off")
    db.fastLoot = true; now = now + 10
    onEvent(nil, "LOOT_READY", false); eq(#taken, 0, "the game's auto loot is off")
end)

test("it loots once for one window, not twice", function()
    local taken = {}
    function LootSlot(i) taken[#taken + 1] = i end
    db.fastLoot = true; now = now + 10
    onEvent(nil, "LOOT_READY", true); onEvent(nil, "LOOT_READY", true)
    eq(#taken, 3, "one pass over three slots")
end)

test("the commands", function()
    addon:HandleExtraCommand("sellgray", "on"); eq(db.sellGray, true)
    addon:HandleExtraCommand("sellgray", "off"); eq(db.sellGray, nil)
    addon:HandleExtraCommand("fastloot", "off"); eq(db.fastLoot, nil)
    addon:HandleExtraCommand("fastloot", "on"); eq(db.fastLoot, true)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
