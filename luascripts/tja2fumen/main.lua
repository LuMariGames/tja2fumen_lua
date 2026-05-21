-- main.lua
-- chart.tja を固定で変換するバージョン

local parsers    = require("tja2fumen.parsers")
local converters = require("tja2fumen.converters")
local writers    = require("tja2fumen.writers")

-- 固定ファイル名
local target = "0:/tja/chart.tja"

print("TJA Loading: " .. target)

-- 1. TJA をパース
local tja = parsers.parse_tja(target)

-- 2. 各コースを変換
for course_name, course in pairs(tja.courses) do
    print("Course Convert: " .. course_name)

    local fumen = converters.convert_tja_to_fumen(course)

    -- Don/Ka の種類補正
    converters.fix_dk_note_types_course(fumen)

    -- 出力ファイル名
    local base = target:gsub("%.tja$", "")
    local outpath = base .. "_" .. course_name .. ".bin"

    print("Writeing: " .. outpath)
    writers.write_fumen(outpath, fumen)
end

print("Complete!")
