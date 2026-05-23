-- tja2fumen.lua
-- chart.tja を固定で変換するバージョン

local const      = require("tja2fumen.constants")
local parsers    = require("tja2fumen.parsers")
local converters = require("tja2fumen.converters")
local writers    = require("tja2fumen.writers")

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

print("TJA2FUMEN v1.1")
local target = fs.ask_select_file("Select a .tja File.\n.tjaファイルを選択して下さい。", "0:/tja/*.tja")

print("TJA Loading: " .. target)

-- 1. TJA をパース
local tja = parsers.parse_tja(target)

local answer = ui.ask("It can be compressed for use with\nTaiko no Tatsujin (3DS).\nDo you want to compress it?\n\n3DS版太鼓の達人用に圧縮する事が出来ます。\n圧縮しますか？")

-- 2. 各コースを変換
for course_name, course in pairs(tja.courses) do
    print("Course Convert: " .. course_name)

    local fumen = converters.convert_tja_to_fumen(course)

    -- Don/Ka の種類補正
    converters.fix_dk_note_types_course(fumen)

    -- 出力ファイル名
    local base = target:gsub("%.tja$", "")
    local name = base:gsub("0:/tja/", "")
    local cid = const.COURSE_IDS[course_name] or "m"
    local outpath

    if course_name == "Ura" then
        outpath = "0:/tja/ex_" .. name .. "_m.bin"
    else
        outpath = base .. "_" .. cid .. ".bin"
    end

    print("Writeing: " .. outpath)
    writers.write_fumen(outpath, fumen)

    -- 3. 各コースを圧縮
    if answer then
        print("FUMEN Compressing: " .. outpath)
        local fumen_data = to_byte_array(read_file(outpath))
        local outbuf = {}
        local out = {
            write = function(_, s)
                outbuf[#outbuf+1] = s
            end
        }
        lz.compress_nlz10(fumen_data, out)
        local compressed = table.concat(outbuf)
        print("Writeing: " .. outpath)
        write_file(outpath, compressed)
    end
end

print("Complete!")
