-- lz_decompress.lua
-- NLZ10 / NLZ11 decompressor for GodMode9 Lua

local M = {}

-- -------------------------
-- 共通ユーティリティ
-- -------------------------
local function bits(byte)
    return {
        (byte >> 7) & 1,
        (byte >> 6) & 1,
        (byte >> 5) & 1,
        (byte >> 4) & 1,
        (byte >> 3) & 1,
        (byte >> 2) & 1,
        (byte >> 1) & 1,
        byte & 1
    }
end

local function read_u16_be(b1, b2)
    return (b1 << 8) | b2
end

-- -------------------------
-- NLZ10 raw (LZSS10)
-- Python: decompress_raw_lzss10
-- -------------------------
function M.decompress_raw_lzss10(indata, decompressed_size, overlay)
    local data = {}
    local out_len = 0

    local it = 1
    local disp_extra = overlay and 3 or 1

    local function readbyte()
        local v = indata[it]
        it = it + 1
        return v
    end

    local function readshort()
        local a = readbyte()
        local b = readbyte()
        return read_u16_be(a, b)
    end

    local function writebyte(b)
        out_len = out_len + 1
        data[out_len] = b
    end

    while out_len < decompressed_size do
        local flagbyte = readbyte()
        local flagbits = bits(flagbyte)

        for i = 1, 8 do
            local flag = flagbits[i]

            if flag == 0 then
                writebyte(readbyte())
            elseif flag == 1 then
                local sh = readshort()
                local count = (sh >> 12) + 3
                local disp  = (sh & 0x0FFF) + disp_extra

                for _ = 1, count do
                    local src = out_len - disp + 1
                    writebyte(data[src])
                end
            else
                error("invalid flag (LZ10)")
            end

            if out_len >= decompressed_size then
                break
            end
        end
    end

    if out_len ~= decompressed_size then
        error("DecompressionError: LZ10 size mismatch")
    end

    return data
end

-- -------------------------
-- NLZ11 raw (LZSS11)
-- Python: decompress_raw_lzss11
-- -------------------------
function M.decompress_raw_lzss11(indata, decompressed_size)
    local data = {}
    local out_len = 0

    local it = 1

    local function readbyte()
        local v = indata[it]
        it = it + 1
        return v
    end

    local function writebyte(b)
        out_len = out_len + 1
        data[out_len] = b
    end

    while out_len < decompressed_size do
        local flagbyte = readbyte()
        local flagbits = bits(flagbyte)

        for i = 1, 8 do
            local flag = flagbits[i]

            if flag == 0 then
                writebyte(readbyte())

            elseif flag == 1 then
                local b = readbyte()
                local indicator = b >> 4
                local count

                if indicator == 0 then
                    -- 8 bit count, 12 bit disp
                    count = (b << 4)
                    b = readbyte()
                    count = count + (b >> 4)
                    count = count + 0x11
                elseif indicator == 1 then
                    -- 16 bit count, 12 bit disp
                    count = ((b & 0x0F) << 12) + (readbyte() << 4)
                    b = readbyte()
                    count = count + (b >> 4)
                    count = count + 0x111
                else
                    -- indicator is count (4 bits), 12 bit disp
                    count = indicator + 1
                end

                local disp = ((b & 0x0F) << 8) + readbyte()
                disp = disp + 1

                for _ = 1, count do
                    local src = out_len - disp + 1
                    if src < 1 then
                        error("LZ11 backref OOB: count=" .. count ..
                              " disp=" .. disp ..
                              " out_len=" .. out_len)
                    end
                    writebyte(data[src])
                end
            else
                error("invalid flag (LZ11)")
            end

            if out_len >= decompressed_size then
                break
            end
        end
    end

    if out_len ~= decompressed_size then
        error("DecompressionError: LZ11 size mismatch")
    end

    return data
end

-- -------------------------
-- bytes API (Python: decompress_bytes)
-- data: Lua string
-- 戻り値: byte配列テーブル
-- -------------------------
function M.decompress_bytes(str)
    local b = {str:byte(1, -1)}
    if #b < 4 then
        error("too short")
    end

    local magic = b[1]
    local size = b[2] | (b[3] << 8) | (b[4] << 16)

    local raw = {}
    for i = 5, #b do
        raw[#raw + 1] = b[i]
    end

    if magic == 0x10 then
        return M.decompress_raw_lzss10(raw, size, false)
    elseif magic == 0x11 then
        return M.decompress_raw_lzss11(raw, size)
    else
        error("not an LZSS10/11 file")
    end
end

-- -------------------------
-- file API (Python: decompress_file)
-- path: 絶対パス
-- 戻り値: byte配列テーブル
-- -------------------------
function M.decompress_file(path)
    local f = io.open(path, "rb")
    if not f then
        error("cannot open file: " .. path)
    end

    local h = f:read(4)
    if not h or #h < 4 then
        f:close()
        error("header too short")
    end

    local h1, h2, h3, h4 = h:byte(1, 4)
    local magic = h1
    local size = h2 | (h3 << 8) | (h4 << 16)

    local rest = f:read("a")
    f:close()

    local raw = {rest:byte(1, -1)}

    if magic == 0x10 then
        return M.decompress_raw_lzss10(raw, size, false)
    elseif magic == 0x11 then
        return M.decompress_raw_lzss11(raw, size)
    else
        error("not an LZSS10/11 file")
    end
end

return M
