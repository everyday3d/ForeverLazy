-- build the data files of our own from the in-game export
local SRC = "C:/claude/questie-export/offline/new-export.lua"
local OUT = "C:/claude/questie-export/offline/staged-data/"
ForeverLazyDB = nil
dofile(SRC)
local dump = ForeverLazyDB.exportDump

local FIELDS = {
  quests = { "name","startedBy","finishedBy","requiredLevel","questLevel","requiredRaces","requiredClasses","objectivesText","triggerEnd","objectives",
    "sourceItemId","preQuestGroup","preQuestSingle","exclusiveTo","zoneOrSort","requiredSkill","requiredMinRep","nextQuestInChain","questFlags","specialFlags","parentQuest","requiredMaxLevel","childQuests","requiredMaxRep","requiredRanks","requiredSpell","requiredSpecialization","breadcrumbs","breadcrumbForQuestId","disabledByQuest","availableUntilCompleted","availableStartingWith" },
  npcs = { "name","minLevel","maxLevel","rank","spawns","questStarts","questEnds","friendlyToFaction","subName","npcFlags" },
  objects = { "name","questStarts","questEnds","spawns" },
  items = { "name","npcDrops","objectDrops","vendors" },
}
local FILE = { quests = "Quests", npcs = "Npcs", objects = "Objects", items = "Items" }

local function ser(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" then if v == math.floor(v) then return string.format("%.0f", v) end return string.format("%.4g", v) end
  if t == "boolean" then return tostring(v) end
  if t == "table" then
    local parts, n = {}, 0
    for _ in pairs(v) do n = n + 1 end
    local arr = true
    for i = 1, n do if v[i] == nil then arr = false break end end
    if arr then for i = 1, n do parts[i] = ser(v[i]) end
    else
      local keys = {}
      for k in pairs(v) do keys[#keys+1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, k in ipairs(keys) do parts[#parts+1] = "[" .. (type(k) == "number" and string.format("%.0f", k) or string.format("%q", k)) .. "]=" .. ser(v[k]) end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end

os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>nul')
for _, kind in ipairs({ "quests", "npcs", "objects", "items" }) do
  local srcIdx = {}
  for i, n in ipairs(dump.fields[kind]) do srcIdx[n] = i end
  local ids = {}
  for id in pairs(dump[kind]) do ids[#ids+1] = id end
  table.sort(ids)
  local f = assert(io.open(OUT .. FILE[kind] .. ".lua", "wb"))
  f:write("-- Generated from the game's quest database export. Do not edit. See docs/QUESTIE-INDEPENDENCE.md.\n")
  f:write("-- Each record is a Lua list in the field order below, kept as text and parsed when asked for.\n")
  f:write("local ADDON, ns = ...\nlocal D = ns.dataset\nD.fields." .. kind .. " = {")
  local q = {}
  for i, n in ipairs(FIELDS[kind]) do q[i] = string.format("%q", n) end
  f:write(table.concat(q, ",") .. "}\nlocal R = D." .. kind .. "\n")
  local count, bytes = 0, 0
  for _, id in ipairs(ids) do
    local rec = load("return " .. dump[kind][id])()
    local vals, last = {}, 0
    for i, name in ipairs(FIELDS[kind]) do
      local v = rec[srcIdx[name]]
      if v ~= nil then vals[i] = ser(v); last = i end
    end
    for i = 1, last do vals[i] = vals[i] or "nil" end
    local s = "{" .. table.concat(vals, ",", 1, last) .. "}"
    assert(not s:find("]=]", 1, true))
    f:write(string.format("R[%d]=[=[%s]=]\n", id, s))
    count = count + 1; bytes = bytes + #s
  end
  f:write(string.format("D.count.%s = %d\n", kind, count))
  f:close()
  print(string.format("%-8s %6d records, %.2f MB", kind, count, bytes / 1048576))
end
