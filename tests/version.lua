-- /lazy version (no game needed): lua tests/version.lua
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local meta = "0.27.0"
C_AddOns = { GetAddOnMetadata = function() return meta end }
UnitName = function() return "Me" end
local said, passedOn = {}, {}
local addon = { Print = function(s) said[#said + 1] = s end, RegisterComm = function() end,
    HandleExtraCommand = function(_, cmd) passedOn[#passedOn + 1] = cmd; return true end }
assert(loadfile("ForeverLazy/Version.lua"))("ForeverLazy", { L = function(s) return s end, addon = addon })
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
test("/lazy version and /lazy ver say the version I run", function()
    for _, c in ipairs({ "version", "VER" }) do
        said = {}
        assert(addon:HandleExtraCommand(c, "") == true)
        assert(said[1] == "version 0.27.0" and said[2]:find("nobody"), table.concat(said, " | "))
    end
end)
test("it says when someone has a newer one", function()
    said = {}
    addon:OnVersion("FLVER", "0.28.0", "PARTY", "Friend-Realm")
    said = {}
    addon:HandleExtraCommand("version", "")
    assert(said[2]:find("0.28.0 is out %(Friend has it%)"), tostring(said[2]))
end)
test("other commands are passed on", function()
    addon:HandleExtraCommand("plan", "")
    assert(passedOn[#passedOn] == "plan")
end)
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
