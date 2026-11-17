-- Shared discoveries: boat docks that players teach the addon are passed to your guild and your group as hidden addon
-- messages. There is no chat channel and nothing is ever shown in chat: other players see no text from this at all.
-- Only a map and two coordinates travel, and a dock is only used by someone else once two different players agree
-- on where it is. It is OFF until you switch it on.
--   /lazy net on | off | status
local ADDON, ns = ...
local addon = ns.addon
local api = ns.api
local Print = addon.Print

local function DB() return addon.GetDB() end

local PREFIX = "FLNET"
local rate = {}           -- player -> { n, t0 }

local function Channels()
    local out = {}
    if IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
    if IsInRaid and IsInRaid() then out[#out + 1] = "RAID" elseif IsInGroup and IsInGroup() then out[#out + 1] = "PARTY" end
    return out
end

local function Reports()
    local root = addon.GetRoot()
    root.dockReports = root.dockReports or {}
    return root.dockReports
end

-- a dock reported by others is used once two different players agree
function addon.CommunityDock(node, to)
    local rep = Reports()[node .. ">" .. (to or "")] or Reports()[node]
    if not rep then return nil end
    local list = {}
    for _, r in pairs(rep) do list[#list + 1] = r end
    for i = 1, #list do
        local agree = 0
        for j = 1, #list do
            if list[i].map == list[j].map and math.abs(list[i].zx - list[j].zx) < 0.03 and math.abs(list[i].zy - list[j].zy) < 0.03 then
                agree = agree + 1
            end
        end
        if agree >= 2 then return { map = list[i].map, zx = list[i].zx, zy = list[i].zy } end
    end
end

-- called when I teach a dock with /lazy boat mark
function addon.NetShareDock(key, map, zx, zy)
    local db = DB()
    if not (db and db.community) then return end
    local data = addon:Serialize({ key = key, map = map, zx = zx, zy = zy })
    for _, ch in ipairs(Channels()) do addon:SendCommMessage(PREFIX, data, ch) end
end

local function Allowed(sender)
    local r = rate[sender]
    local now = GetTime()
    if not r or now - r.t0 > 60 then rate[sender] = { t0 = now, n = 1 }; return true end
    r.n = r.n + 1
    return r.n <= 12                      -- a dozen messages a minute from one player is plenty
end

function addon:OnNet(prefix, message, distribution, sender)
    if prefix ~= PREFIX then return end
    local db = DB()
    if not (db and db.community) then return end
    local who = (sender or "?"):match("^([^%-]+)") or sender
    if who == UnitName("player") or not Allowed(who) then return end
    local ok, t = self:Deserialize(message)
    if not ok or type(t) ~= "table" then return end
    if type(t.key) == "string" and #t.key < 40 and type(t.map) == "number" and type(t.zx) == "number"
        and type(t.zy) == "number" and t.zx >= 0 and t.zx <= 1 and t.zy >= 0 and t.zy <= 1 then
        local rep = Reports()
        rep[t.key] = rep[t.key] or {}
        rep[t.key][who] = { map = t.map, zx = t.zx, zy = t.zy }
    end
end
addon:RegisterComm(PREFIX, "OnNet")

local prev = addon.HandleExtraCommand
function addon:HandleExtraCommand(cmd, rest)
    if (cmd or ""):lower() == "net" then
        local db = DB()
        local a = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if a == "on" then
            db.community = true
            Print("sharing on: boat docks you teach go to your guild and group as hidden addon messages. Nothing shows in chat.")
        elseif a == "off" then
            db.community = false
            Print("sharing off")
        else
            local n = 0
            for _ in pairs(Reports()) do n = n + 1 end
            Print(string.format("sharing is %s. %d dock%s reported by others so far. /lazy net on | off",
                db.community and "on" or "off", n, n == 1 and "" or "s"))
        end
        return true
    end
    if prev then return prev(self, cmd, rest) end
end
