-- Spare file, so later work only needs a /reload. Filled in later.
local ADDON, ns = ...

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["Spare4.lua"] = true end end
