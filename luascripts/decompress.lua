-- decompress.lua  (NLZ10/NLZ11 decompression runner)

local nlz10 = require("lzx.lz_decompress")

print("nlz Decompressor")

-- ★絶対パスで指定すること
local INPUT_PATH  = fs.ask_select_file("Select a .bin File.", "0:/tja/*.bin")
if not INPUT_PATH then return end

local function write_bytes(path, tbl)
    local f = io.open(path, "wb")
    for i = 1, #tbl do
        f:write(string.char(tbl[i]))
    end
    f:close()
end

local function main()
    print("Decompressing: " .. INPUT_PATH)
    local out = nlz10.decompress_file(INPUT_PATH)
    write_bytes(INPUT_PATH, out)
end

main()
