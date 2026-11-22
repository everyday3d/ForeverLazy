local OLD = "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/ForeverLazy/data/"
local NEW = "C:/claude/questie-export/offline/staged-extras/"
local function load2(dir, f) local ns = { dataset = {} }; assert(loadfile(dir .. f))("ForeverLazy", ns); return ns.dataset end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function ser(v)
  if type(v) ~= "table" then return tostring(v) end
  local ks = {}; for k in pairs(v) do ks[#ks+1] = k end
  table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
  local p = {}; for _, k in ipairs(ks) do p[#p+1] = tostring(k) .. "=" .. ser(v[k]) end
  return "{" .. table.concat(p, ",") .. "}"
end
-- zones
local o, n = load2(OLD, "Zones.lua").zones, load2(NEW, "Zones.lua").zones
local same, diff, onlyO, onlyN = 0, 0, 0, 0
for k, v in pairs(o.areaToMap) do if n.areaToMap[k] == nil then onlyO = onlyO + 1 elseif n.areaToMap[k] == v then same = same + 1 else diff = diff + 1 end end
for k in pairs(n.areaToMap) do if o.areaToMap[k] == nil then onlyN = onlyN + 1 end end
print("zones areaToMap: old", count(o.areaToMap), "new", count(n.areaToMap), "same", same, "changed", diff, "only old", onlyO, "only new", onlyN)
print("zones dungeons: old", count(o.dungeons), "new", count(n.dungeons), "identical", ser(o.dungeons) == ser(n.dungeons))
-- extra1
local o1, n1 = load2(OLD, "Extra1.lua"), load2(NEW, "Extra1.lua")
print("hidden: old", #o1.hidden, "new", #n1.hidden)
local ds, dd = 0, 0
for item, t in pairs(o1.drops) do if ser(t) == ser(n1.drops[item] or {}) then ds = ds + 1 else dd = dd + 1 end end
print("drops: old items", count(o1.drops), "new items", count(n1.drops), "same", ds, "changed or gone", dd)
-- extra2
local o2, n2 = load2(OLD, "Extra2.lua"), load2(NEW, "Extra2.lua")
for name, v in pairs(o2.hiddenGroups) do print("group", name, "old", #v, "new", n2.hiddenGroups[name] and #n2.hiddenGroups[name] or "missing") end
for name, v in pairs(n2.hiddenGroups) do if not o2.hiddenGroups[name] then print("group", name, "NEW only", #v) end end
local ts, td, to, tn = 0, 0, 0, 0
for id, t in pairs(o2.tags) do if n2.tags[id] == nil then to = to + 1 elseif n2.tags[id] == t then ts = ts + 1 else td = td + 1 end end
for id in pairs(n2.tags) do if o2.tags[id] == nil then tn = tn + 1 end end
print("tags: old", count(o2.tags), "new", count(n2.tags), "same", ts, "changed", td, "only old", to, "only new", tn)
-- townsfolk
local ot, nt = load2(OLD, "Townsfolk.lua").townsfolk, load2(NEW, "Townsfolk.lua").townsfolk
for _, part in ipairs({ "townsfolk", "professionTrainers", "classSpecificTownsfolk", "factionSpecificTownsfolk", "petFoodVendorTypes", "professionKeys" }) do
  print("townsfolk." .. part, "identical:", ser(ot[part]) == ser(nt[part]))
end
for cat, list in pairs(ot.townsfolk) do
  local so, sn = {}, {}
  for _, id in ipairs(list) do so[id] = true end
  for _, id in ipairs(nt.townsfolk[cat] or {}) do sn[id] = true end
  local a, b = 0, 0
  for id in pairs(so) do if not sn[id] then a = a + 1 end end
  for id in pairs(sn) do if not so[id] then b = b + 1 end end
  print(string.format("  %-16s old %4d new %4d  removed %3d added %3d", cat, #list, #(nt.townsfolk[cat] or {}), a, b))
end