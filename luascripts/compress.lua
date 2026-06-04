-- compress.lua

local lz = require("lzx.lz_compress")

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then error("Cannot open " .. path) end
    local data = f:read("a")
    f:close()
    return data
end

local function write_file(path, data)
    local f = io.open(path, "wb")
    if not f then error("Cannot write " .. path) end
    f:write(data)
    f:close()
end

local function to_byte_array(str)
    local t = {}
    for i = 1, #str do
        t[i-1] = str:byte(i)
    end
    return t
end

print("FUMEN Compressor")

-- 固定ファイル名
local path = fs.ask_select_file("Select a .bin File.\n.binファイルを選択して下さい。", "0:/tja/*.bin")

if not path then return end
print("FUMEN Loading: " .. path)

-- 1. compress
print("Compressing: " .. path)
local fumen_data = to_byte_array(read_file(path))
local outbuf = {}
local out = {
    write = function(_, s)
        outbuf[#outbuf+1] = s
    end
}
lz.compress_nlz10(fumen_data, out)
local compressed = table.concat(outbuf)
print("Writeing: " .. path)
write_file(path, compressed)

print("Complete!")