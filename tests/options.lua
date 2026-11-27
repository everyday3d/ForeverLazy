-- The options window (no game needed): lua tests/options.lua [folder with Options.lua]
-- Stand-in frames remember where they are put and whether they show, so the pages and the search can be checked.
local dir = (arg and arg[1]) or "ForeverLazy"

local frames = {}
local function Frame(kind, name)
    local f = { kind = kind, shown = true, enabled = true, scripts = {}, text = nil }
    frames[#frames + 1] = f
    f.SetPoint = function(self, point, a, b) if type(a) == "number" then self.x, self.y = a, b end end
    f.ClearAllPoints = function(self) self.x, self.y = nil, nil end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    f.SetShown = function(self, v) self.shown = v and true or false end
    f.SetText = function(self, t) self.text = t; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
    f.GetText = function(self) return self.text end
    f.SetWidth = function(self, w) self.width = w end
    f.GetWidth = function(self) return self.width end
    f.GetStringHeight = function(self)
        local w = self.width or 100000
        return 14 * math.max(1, math.ceil(#tostring(self.text or "") * 6.5 / w))
    end
    f.SetEnabled = function(self, v) self.enabled = v end
    f.SetScript = function(self, what, fn) self.scripts[what] = fn end
    f.CreateFontString = function() return Frame("string") end
    f.CreateTexture = function() return Frame("texture") end
    setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") and k ~= "TitleText" then return function() end end end })
    if name then
        for _, suffix in ipairs({ "Text", "Low", "High" }) do _G[name .. suffix] = Frame("string") end
    end
    return f
end
CreateFrame = function(kind, name) return Frame(kind, name) end
UIParent, UISpecialFrames, SlashCmdList = Frame("ui"), {}, {}
tinsert, unpack, date = table.insert, table.unpack, os.date
local myClass = "PALADIN"
UnitClass = function() return myClass, myClass end

local db = setmetatable({ pos = {}, modules = {}, scale = 1, alpha = 1, arrival = 10, optAllClasses = true }, { __index = function(_, k)
    if type(k) == "string" and k:match("^color") or type(k) == "string" and k:match("^plateColor") then return { 1, 1, 1 } end
    if k == "panelScale" then return 1 end
    if k == "extraTargets" then return 0 end
end })
local off = {}
local addon = { GetDB = function() return db end, GetRoot = function() return {} end, Print = function() end,
    ModuleOn = function(m) return not off[m] end, MODULES = { { "quests", "Quest helpers (item button, chain, reward pick, farm)" }, { "gear", "Gear advisor (upgrades in tooltips and bags, the gear bar)" } } }
local ns = { L = function(s) return s end, addon = addon }
assert(loadfile("ForeverLazy/OptionTips.lua"))("ForeverLazy", ns)
assert(loadfile("ForeverLazy/CompassExtras.lua"))("ForeverLazy", ns)
assert(loadfile(dir .. "/Options.lua"))("ForeverLazy", ns)
addon:OpenOptions()
local M = addon.OptionsModel

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok    " .. name) else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local searchBox
for _, f in ipairs(frames) do if f.kind == "EditBox" and f.scripts.OnTextChanged then searchBox = f end end
-- what is on screen now: the text of every shown check box
local function ShownTexts()
    local out = {}
    for _, s in ipairs(M.sections) do
        for _, b in ipairs(s.blocks) do
            for _, it in ipairs(b.items) do
                if it.obj.shown then out[#out + 1] = { it = it, text = M.BlockText(b), section = s.title } end
            end
        end
    end
    return out
end
local function Shows(words)
    for _, e in ipairs(ShownTexts()) do if M.Matches(e.text, words) then return e end end
end

test("every subheading is on exactly one page, and every listed one exists", function()
    local listed, made = {}, {}
    for _, p in ipairs(M.pages) do for _, t in ipairs(p[2]) do assert(not listed[t], "listed twice: " .. t); listed[t] = true end end
    for _, s in ipairs(M.sections) do made[s.title] = true; assert(listed[s.title], "on no page: " .. s.title) end
    for t in pairs(listed) do assert(made[t], "listed but never made: " .. t) end
    assert(#M.pages == 12)
end)

test("every control shows on its page, none on top of another", function()
    local seen = {}
    local tabs = {}
    for _, p in ipairs(M.pages) do
        db.optPage = p[1]
        addon.RefreshOptions()
        local at = {}
        for _, e in ipairs(ShownTexts()) do
            local o = e.it.obj
            seen[o] = true
            if o.kind == "CheckButton" or o.kind == "Slider" or o.kind == "Button" then
                local key = o.x .. "," .. o.y
                assert(not at[key], p[1] .. ": two controls at " .. key .. ": " .. e.text .. " / " .. tostring(at[key]))
                at[key] = e.text
            end
        end
    end
    for _, s in ipairs(M.sections) do
        for _, b in ipairs(s.blocks) do
            for _, it in ipairs(b.items) do assert(seen[it.obj], "never shown: " .. s.title .. ": " .. M.BlockText(b)) end
        end
    end
end)

test("blocks go downwards and take room", function()
    for _, s in ipairs(M.sections) do
        for i, b in ipairs(s.blocks) do
            local after = s.blocks[i + 1] and s.blocks[i + 1].top or s.bodyEnd
            assert(b.top - after > 0, s.title .. " block " .. i .. " has height " .. (b.top - after) .. ": " .. M.BlockText(b))
        end
    end
end)

test("a search finds a setting on another page", function()
    db.optPage = "Start here"
    searchBox:SetText("flash cast")
    assert(Shows("flash the mob's cast bar"), "not found")
    assert(not Shows("Timestamps in front"), "an unrelated setting is shown")
end)

test("a search by a subheading's name shows what is under it", function()
    searchBox:SetText("couch")
    assert(Shows("Read the steps aloud"))
end)

test("a search with no match shows nothing, clearing it brings the page back", function()
    searchBox:SetText("zzzzqqq")
    assert(#ShownTexts() == 0, #ShownTexts() .. " still shown")
    searchBox:SetText("")
    assert(#ShownTexts() > 0)
end)

test("a module that is off hides its settings, search included", function()
    off.gear = true
    searchBox:SetText("score gear as")
    assert(not Shows("Score gear as"))
    off.gear = nil
    searchBox:SetText("")
    searchBox:SetText("score gear as")
    assert(Shows("Score gear as"))
    searchBox:SetText("")
end)

test("no setting is offered twice", function()
    local seen = {}
    for _, s in ipairs(M.sections) do
        for _, b in ipairs(s.blocks) do
            for _, it in ipairs(b.items) do
                if (it.obj.kind == "CheckButton" or it.obj.kind == "Slider") and it.text and b.kind ~= "radio" then
                    assert(not seen[it.text], "twice: " .. it.text)
                    seen[it.text] = true
                end
            end
        end
    end
end)

test("long text wraps and nothing under it is covered", function()
    local wrapped = 0
    for _, p in ipairs(M.pages) do
        db.optPage = p[1]
        addon.RefreshOptions()
        local drawn = {}
        for _, e in ipairs(ShownTexts()) do drawn[#drawn + 1] = e end
        for _, e in ipairs(drawn) do
            local it = e.it
            if it.wrap then
                assert(it.wrap.width and it.wrap.width <= 520, "not wrapped to the page: " .. e.text)
                local h = it.wrap:GetStringHeight()
                if h > 14 then wrapped = wrapped + 1 end
                -- the text's top and bottom on the page (beside a tick box it starts 9 under the box's top)
                local top = it.obj.y - (it.indent and 9 or 0)
                local bottom = top - h
                for _, other in ipairs(drawn) do
                    local o = other.it.obj
                    if o ~= it.obj and o.y < it.obj.y then
                        assert(o.y <= bottom + 3, p[1] .. ": text over the next control: " .. e.text:sub(1, 60) .. " / " .. other.text:sub(1, 40))
                    end
                end
            end
        end
    end
    assert(wrapped > 10, "only " .. wrapped .. " texts wrapped")
end)
test("class settings show only on that class, unless every class is asked for", function()
    db.optAllClasses = nil
    searchBox:SetText("")
    db.optPage = "My class"
    addon.RefreshOptions()
    assert(Shows("Paladin blessings: one button") and not Shows("Totem bar") and not Shows("pet needs feeding"))
    myClass = "SHAMAN"
    addon.RefreshOptions()
    assert(Shows("Totem bar") and not Shows("Paladin blessings: one button"))
    searchBox:SetText("pet needs feeding")
    assert(#ShownTexts() == 0, "a search shows another class's setting")
    searchBox:SetText("")
    myClass = "PALADIN"
    db.optAllClasses = true
    addon.RefreshOptions()
    assert(Shows("Totem bar") and Shows("pet needs feeding"))
end)

test("every tick box and slider says what it does when hovered", function()
    local missing, checked = {}, 0
    for _, s in ipairs(M.sections) do
        for _, b in ipairs(s.blocks) do
            for _, it in ipairs(b.items) do
                if (it.obj.kind == "CheckButton" or it.obj.kind == "Slider") and b.kind ~= "radio" then
                    checked = checked + 1
                    if not addon.OptionTip(it.text) then missing[#missing + 1] = tostring(it.text) end
                    assert(it.obj.scripts.OnEnter, "no hover: " .. tostring(it.text))
                end
            end
        end
    end
    assert(#missing == 0, #missing .. " without a description:\n" .. table.concat(missing, "\n"))
    assert(checked > 100, "only " .. checked)
end)
test("every module has a description", function()
    local text = io.open("ForeverLazy/Modules.lua", "rb"):read("a")
    local list = text:match("addon%.MODULES = {(.-)\n}")
    local n = 0
    for name in list:gmatch('{ "%a+",%s+"(.-)" }') do n = n + 1; assert(addon.OptionTip(name), "module without a description: " .. name) end
    assert(n > 15, n)
end)
-- every tick box's text, for writing their descriptions
if os.getenv("LIST_CHECKS") then
    for _, s in ipairs(M.sections) do
        for _, b in ipairs(s.blocks) do
            for _, it in ipairs(b.items) do
                if it.obj.kind == "CheckButton" then print("CHECK\t" .. s.title .. "\t" .. tostring(it.text)) end
            end
        end
    end
end
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
