-- compare two dumps (old in-game export vs new offline one): how many records differ, and a few examples
local OLD, NEW = arg[1], arg[2]
ForeverLazyDB = nil; dofile(OLD); local old = ForeverLazyDB.exportDump
ForeverLazyDB = nil; dofile(NEW); local new = ForeverLazyDB.exportDump
for _, kind in ipairs({ "quests", "npcs", "objects", "items" }) do
    local same, diff, onlyOld, onlyNew = 0, 0, 0, 0
    local examples = {}
    local fields = old.fields[kind]
    for id, rec in pairs(old[kind]) do
        local n = new[kind][id]
        if n == nil then onlyOld = onlyOld + 1
        elseif n == rec then same = same + 1
        else
            diff = diff + 1
            if #examples < 4 then examples[#examples + 1] = id end
        end
    end
    for id in pairs(new[kind]) do if old[kind][id] == nil then onlyNew = onlyNew + 1 end end
    print(string.format("%-8s same %6d  changed %5d  only in old %4d  only in new %4d", kind, same, diff, onlyOld, onlyNew))
    for _, id in ipairs(examples) do
        print("   id " .. id)
        print("     old: " .. old[kind][id]:sub(1, 200))
        print("     new: " .. new[kind][id]:sub(1, 200))
    end
end
