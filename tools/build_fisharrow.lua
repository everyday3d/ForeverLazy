-- Draws the fish that replaces the arrow on fishing route trips (our own drawing): a 64x64 uncompressed 32-bit TGA, nose up
-- so it turns like an arrow:  lua tools/build_fisharrow.lua <out.tga>
local N, SUB = 64, 4
local out = arg[1] or "ForeverLazy/media/arrow_fish.tga"

local function Ellipse(x, y, cx, cy, rx, ry) return ((x - cx) / rx) ^ 2 + ((y - cy) / ry) ^ 2 <= 1 end

-- the body: pointed toward the nose, round in the middle, narrow before the tail
local function Body(x, y, grow)
    local top, bottom, widest = 4 - grow, 48 + grow, 24
    if y < top or y > bottom then return false end
    local half
    if y <= widest then
        half = 15 * math.sin((y - top) / (widest - top) * math.pi / 2) ^ 0.8
    else
        half = 4 + 11 * math.cos((y - widest) / (bottom - widest) * math.pi / 2)
    end
    return math.abs(x - 32) <= half + grow
end

-- the forked tail
local function Tail(x, y, grow)
    if y < 45 or y > 61 + grow then return false end
    local spread = 4 + (y - 45) * 0.95 + grow
    local notch = math.max(0, (y - 52) * 1.3 - grow)
    local d = math.abs(x - 32)
    return d <= spread and d >= notch
end

-- side fins, swept back
local function Fins(x, y, grow)
    if y < 24 - grow or y > 38 + grow then return false end
    local d = math.abs(x - 32)
    return d >= 10 and d <= 13 + (y - 24) * 0.75 + grow and y >= 24 - grow + (d - 12) * 0.9
end

-- the colour at a point (x right, y down), or nil outside
local function At(x, y)
    for _, ex in ipairs({ 25.5, 38.5 }) do
        if Ellipse(x, y, ex, 17, 1.7, 1.9) then return 0.05, 0.05, 0.08 end
        if Ellipse(x, y, ex, 17, 3.4, 3.6) then return 1, 1, 1 end
    end
    if Body(x, y, 0) then
        local d = math.abs(x - 32)
        -- a few rows of scales
        for row, sy in ipairs({ 27, 33, 39 }) do
            local r = (x - 32 - (row % 2) * 3) % 8 - 4
            local curve = sy + 3 - (r * r) * 0.22
            if math.abs(y - curve) < 0.7 and d < 10 then return 0.75, 0.38, 0.05 end
        end
        local s = 1 - d * 0.022                                 -- lighter down the back
        return s, s * 0.66, s * 0.12
    end
    if Tail(x, y, 0) or Fins(x, y, 0) then return 0.92, 0.45, 0.08 end
    if Body(x, y, 2.6) or Tail(x, y, 2.6) or Fins(x, y, 2.4) then return 0.05, 0.05, 0.08 end
end

local bytes = {}
for row = N - 1, 0, -1 do                                  -- a TGA starts with the bottom line
    for col = 0, N - 1 do
        local r, g, b, hits = 0, 0, 0, 0
        for i = 0, SUB - 1 do
            for j = 0, SUB - 1 do
                local cr, cg, cb = At(col + (i + 0.5) / SUB, row + (j + 0.5) / SUB)
                if cr then r, g, b, hits = r + cr, g + cg, b + cb, hits + 1 end
            end
        end
        local function Byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
        if hits == 0 then bytes[#bytes + 1] = "\0\0\0\0"
        else bytes[#bytes + 1] = string.char(Byte(b / hits), Byte(g / hits), Byte(r / hits), Byte(hits / (SUB * SUB))) end
    end
end
local header = string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, N % 256, math.floor(N / 256), N % 256, math.floor(N / 256), 32, 8)
local f = assert(io.open(out, "wb"))
f:write(header, table.concat(bytes))
f:close()
print("wrote " .. out)
