-- Offline test for the item tooltip's character list (no game needed): one character saved under several realm
-- spellings is listed once.   lua tests/inventory.lua
local root = (arg and arg[0] or "tests/inventory.lua"):gsub("[/\\]tests[/\\]inventory%.lua$", ""):gsub("^tests[/\\]inventory%.lua$", ".")

local rootDB = { inv = {} }
local db = { itemTooltip = true }
local addon = { Print = function() end, GetDB = function() return db end, GetRoot = function() return rootDB end }
local ns = { addon = addon, L = function(x) return x end }

local hookFn, hookEv
local onEvents = {}
function CreateFrame()
    local f = setmetatable({}, { __index = function() return function() end end })
    f.RegisterEvent = function() end
    f.SetScript = function(self, n, fn) if n == "OnEvent" then hookEv = fn; onEvents[#onEvents + 1] = fn end end
    return f
end
C_Timer = { After = function(_, fn) fn() end }
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) hookFn = fn end }
Enum = { TooltipDataType = { Item = 1 } }
GetItemCount = function() return 2 end
local playerName, realm = "Bad", "CAMWOW US1 Realm 7 PvE"
function UnitName() return playerName end
function GetRealmName() return realm end
function UnitFullName() return playerName, "Altitude" end
function UnitClass() return "Mage", "MAGE" end
function UnitFactionGroup() return "Alliance" end
function GetGuildInfo() return nil end
RAID_CLASS_COLORS = {}

assert(loadfile(root .. "/ForeverLazy/Inventory.lua"))("ForeverLazy", ns)
if hookEv then pcall(hookEv, nil, "PLAYER_LOGIN") end
assert(hookFn, "the tooltip hook is set")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

-- the same character saved three ways, and another character saved twice (shapes from a real saved-variables file)
local function Load()
    rootDB.inv = {
        ["Bad-CAMWOW US1 Realm 7 PvE"] = { name = "Bad", class = "MAGE", realm = realm, bags = { [1] = 2 }, bank = {}, mail = {}, worn = {} },
        ["Bad-"] = { name = "Bad", full = "Bad Altitude", class = "MAGE", realm = "", bags = { [1] = 2 }, bank = {}, mail = {}, worn = {} },
        ["Bad-Altitude"] = { name = "Bad", full = "Bad Altitude", class = "MAGE", realm = "Altitude", bags = { [1] = 2 }, bank = {}, mail = {}, worn = {} },
        ["Tank-CAMWOW US1 Realm 7 PvE"] = { name = "Tank", class = "PALADIN", realm = realm, bags = { [1] = 5 }, bank = {}, mail = {}, worn = {} },
        ["Tank-"] = { name = "Tank", full = "Tank Hanks", class = "PALADIN", realm = "", bags = { [1] = 5 }, bank = {}, mail = {}, worn = {} },
    }
end
local function Rows()
    local seen = {}
    local tt = { AddDoubleLine = function(_, l, r) seen[#seen + 1] = l .. " | " .. r end, AddLine = function() end, Show = function() end }
    hookFn(tt, { id = 1 })
    return seen
end
local function Count(rows, text) local n = 0; for _, r in ipairs(rows) do if r:find(text, 1, true) then n = n + 1 end end; return n end

test("the character I play is listed once, as You", function()
    Load()
    local rows = Rows()
    assert(Count(rows, "You") == 1, table.concat(rows, "; "))
    assert(Count(rows, "Bad") == 0, "no other copy of me: " .. table.concat(rows, "; "))
end)

test("another character saved twice is listed once", function()
    Load()
    local rows = Rows()
    assert(Count(rows, "Tank") == 1, table.concat(rows, "; "))
    assert(Count(rows, "Tank Hanks") == 1, "the copy with the full name is the one shown: " .. table.concat(rows, "; "))
end)

test("it still works when the realm name is empty at the moment", function()
    Load(); realm = ""
    local rows = Rows()
    assert(Count(rows, "Bad") == 0 and Count(rows, "You") == 1, table.concat(rows, "; "))
    realm = "CAMWOW US1 Realm 7 PvE"
end)

-- the bank scan must never count the containers I carry
test("the bank scan does not count my bags, even when the client numbers the bank like a bag", function()
    local contents = { [0] = { [1] = { itemID = 1, stackCount = 12 } }, [5] = { [1] = { itemID = 4, stackCount = 3 } }, [6] = { [1] = { itemID = 9, stackCount = 7 } } }
    NUM_BAG_SLOTS = 4; NUM_REAGENTBAG_SLOTS = 1; NUM_BANKBAGSLOTS = 7
    BANK_CONTAINER = 0                                   -- a client that calls the backpack the bank
    C_Container = {
        GetContainerNumSlots = function(b) return contents[b] and 4 or 0 end,
        GetContainerItemInfo = function(b, s) return contents[b] and contents[b][s] or nil end,
    }
    Load()
    for _, fn in ipairs(onEvents) do pcall(fn, nil, "PLAYER_LOGIN"); pcall(fn, nil, "BANKFRAME_CLOSED") end
    local me = rootDB.inv["Bad-" .. realm] or rootDB.inv["Bad-"]
    assert(me, "my record exists")
    assert((me.bank or {})[1] == nil, "the 12 dust in my backpack is not in the bank")
    assert((me.bank or {})[9] == 7, "a real bank item is counted")
    assert((me.bank or {})[4] == nil, "the reagent bag I carry is not the bank")
    BANK_CONTAINER = nil
end)
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
