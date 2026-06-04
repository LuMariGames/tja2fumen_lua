-- main_reverse.lua
-- 逆変換実行スクリプト

local fumen_parser = require("tja2fumen.fumen_parser")
local fumen2tja    = require("tja2fumen.fumen2tja")

local input_fumen = fs.ask_select_file("Select a .bin File.", "0:/tja/*.bin")
if not input_fumen then return end
local output_tja  = "0:/tja/output.tja"   -- 出力するTJAテキストファイル

print("1. Fumenバイナリを解析中...")
-- 3DS/PC環境用のファイルならリトルエンディアン "<"
-- Wii U環境用のファイルならビッグエンディアン ">" を指定
local song_obj = fumen_parser.parse_fumen(input_fumen, "<")

print("2. TJAファイルへ逆変換・書き出し中...")
fumen2tja.write_tja(output_tja, song_obj)

print("成功: " .. output_tja .. " が生成されました！")