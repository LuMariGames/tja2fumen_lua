-- lz_compress.lua
local SlidingWindow = require("lzx.sliding_window")
local NLZ = require("lzx.nlz_windows")

local NLZ10Window = NLZ.NLZ10Window
local NLZ11Window = NLZ.NLZ11Window

-- pack helpers
local function u8(n)
    return string.char(n & 0xFF)
end

local function u16be(n)
    return string.char((n >> 8) & 0xFF, n & 0xFF)
end

local function u32le(n)
    return string.char(
        n & 0xFF,
        (n >> 8) & 0xFF,
        (n >> 16) & 0xFF,
        (n >> 24) & 0xFF
    )
end

local function packflags(flags)
    local n = 0
    for i = 1, 8 do
        n = n << 1
        if flags[i] then n = n | 1 end
    end
    return n
end

local function _compress(input, windowclass)
    local window = windowclass:new(input)
    local i = 0

    return function()
        if i >= #input then return nil end

        local match = window:search()
        if match then
            local count, disp = match[1], match[2]
            window:advance(count)
            i = i + count
            return {count, disp}
        else
            local b = input[i]
            window:next()
            i = i + 1
            return b
        end
    end
end

local function chunkit(iter, n)
    return function()
        local buf = {}
        for i = 1, n do
            local v = iter()
            if not v then break end
            buf[#buf+1] = v
        end
        if #buf == 0 then return nil end
        return buf
    end
end

local function compress_nlz10(input, out)
    out:write(u32le((#input << 8) + 0x10))

    local iter = _compress(input, NLZ10Window)
    local chunk = chunkit(iter, 8)

    local length = 0

    while true do
        local tokens = chunk()
        if not tokens then break end

        local flags = {}
        for i, t in ipairs(tokens) do
            flags[i] = type(t) == "table"
        end

        out:write(u8(packflags(flags)))
        length = length + 1

        for _, t in ipairs(tokens) do
            if type(t) == "table" then
                local count, disp = t[1], t[2]
                count = count - 3
                disp = (-disp) - 1

                local sh = (count << 12) | disp
                out:write(u16be(sh))
                length = length + 2
            else
                out:write(u8(t))
                length = length + 1
            end
        end
    end

    local padding = 4 - (length % 4 == 0 and 4 or (length % 4))
    if padding > 0 then
        out:write(string.rep("\xFF", padding))
    end
end

local function compress_nlz11(input, out)
    out:write(u32le((#input << 8) + 0x11))

    local iter = _compress(input, NLZ11Window)
    local chunk = chunkit(iter, 8)

    local length = 0

    while true do
        local tokens = chunk()
        if not tokens then break end

        local flags = {}
        for i, t in ipairs(tokens) do
            flags[i] = type(t) == "table"
        end

        out:write(u8(packflags(flags)))
        length = length + 1

        for _, t in ipairs(tokens) do
            if type(t) == "table" then
                local count, disp = t[1], t[2]
                disp = (-disp) - 1

                if count <= 1 + 0xF then
                    count = count - 1
                    local sh = (count << 12) | disp
                    out:write(u16be(sh))
                    length = length + 2

                elseif count <= 0x11 + 0xFF then
                    count = count - 0x11
                    local b = count >> 4
                    local sh = ((count & 0xF) << 12) | disp
                    out:write(u8(b))
                    out:write(u16be(sh))
                    length = length + 3

                else
                    count = count - 0x111
                    local l = (1 << 28) | (count << 12) | disp
                    out:write(u32le(l))
                    length = length + 4
                end
            else
                out:write(u8(t))
                length = length + 1
            end
        end
    end

    local padding = 4 - (length % 4 == 0 and 4 or (length % 4))
    if padding > 0 then
        out:write(string.rep("\xFF", padding))
    end
end

return {
    compress_nlz10 = compress_nlz10,
    compress_nlz11 = compress_nlz11,
}
