-- Draws the compass's tombstone (our own drawing) as a 64x64 uncompressed 32-bit TGA:  lua tools/build_tombstone.lua <out.tga>
local N, SUB = 64, 4
local out = arg[1] or "ForeverLazy/media/tombstone.tga"

-- the stone: straight sides with a round top; grow widens it (for the dark edge)
local function Stone(x, y, grow)
    local half, top, bottom, mid = 18 + grow, 24, 55 + grow, 32
    if y > bottom then return false end
    if y >= top then return math.abs(x - mid) <= half end
    return (x - mid) ^ 2 + (y - top) ^ 2 <= half ^ 2
end
local function Mound(x, y, grow) return x >= 7 - grow and x <= 57 + grow and y >= 53 - grow and y <= 61 + grow end
local function Cross(x, y)
    return (math.abs(x - 32) <= 3 and y >= 17 and y <= 44) or (math.abs(x - 32) <= 10 and y >= 23 and y <= 29)
end

-- the colour at a point (x right, y down), or nil outside
local function At(x, y)
    if Mound(x, y, 0) then local s = 0.50 - (y - 53) * 0.02; return s, s * 0.92, s * 0.80 end
    if Stone(x, y, 0) then
        if Cross(x, y) then return 0.22, 0.23, 0.26 end
        local s = 0.95 - (x - 14) * 0.007                 -- lit from the left
        return s, s, math.min(1, s * 1.04)
    end
    if Stone(x, y, 3) or Mound(x, y, 3) then return 0.06, 0.06, 0.08 end
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
