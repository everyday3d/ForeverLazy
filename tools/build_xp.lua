local DB = "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/QuestieDB/support/Forever/QuestXP/"
local QuestXP = { db = {} }
QuestieLoader = { ImportModule = function() return QuestXP end }
dofile(DB .. "xpDB-classic.lua")
local nBase = 0; for _ in pairs(QuestXP.db) do nBase = nBase + 1 end
dofile(DB .. "xpDB-traces.lua")
local ids = {}
for id in pairs(QuestXP.db) do ids[#ids + 1] = id end
table.sort(ids)
-- the old file, for comparison
local ns = { dataset = {} }
assert(loadfile("C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/ForeverLazy/data/QuestXP.lua"))("ForeverLazy", ns)
local old = ns.dataset.xp
local same, changed, added, removed = 0, 0, 0, 0
local ex = {}
for id, v in pairs(QuestXP.db) do
  local o = old[id]
  if not o then added = added + 1
  elseif o[1] == v[1] and o[2] == v[2] then same = same + 1
  else changed = changed + 1; if #ex < 6 then ex[#ex+1] = string.format("%d: {%s,%s} -> {%s,%s}", id, o[1], o[2], v[1], v[2]) end end
end
for id in pairs(old) do if not QuestXP.db[id] then removed = removed + 1 end end
print(string.format("base %d, total %d; vs old: same %d changed %d added %d removed %d", nBase, #ids, same, changed, added, removed))
for _, e in ipairs(ex) do print("  " .. e) end
local f = assert(io.open("C:/claude/questie-export/offline/staged-data/QuestXP.lua", "wb"))
f:write("-- Quest XP at the quest's own level: id -> { level, xp }. Generated from the game's quest database (base table plus values seen in play). Do not edit.\n")
f:write("local ADDON, ns = ...\nlocal xp = {}\n")
local line, n = {}, 0
local function flush()
  if #line > 0 then f:write("for k, v in pairs({" .. table.concat(line) .. "}) do xp[k] = v end\n"); line = {} end
end
for _, id in ipairs(ids) do
  local v = QuestXP.db[id]
  line[#line + 1] = string.format("[%d]={%d,%d},", id, v[1], v[2])
  if #table.concat(line) > 170 then flush() end
end
flush()
f:write("ns.dataset.xp = xp\n")
f:close()