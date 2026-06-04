-- fumen_parser.lua
-- Lua 5.4 port/extension of tja2fumen.parsers (Fumen Binary Parser)

local classes = require("tja2fumen.classes")
local const   = require("tja2fumen.constants")

local FumenCourse  = classes.FumenCourse
local FumenMeasure = classes.FumenMeasure
local FumenBranch  = classes.FumenBranch
local FumenNote    = classes.FumenNote
local FumenHeader  = classes.FumenHeader

local BRANCH_NAMES     = const.BRANCH_NAMES
local FUMEN_TYPE_NOTES = const.FUMEN_TYPE_NOTES

-- FUMEN_TYPE_NOTES の逆写像を作成 (バイト値 -> 音符名文字列)
local NOTE_BYTE_TO_TYPE = {}
if FUMEN_TYPE_NOTES then
    for type_str, byte_val in pairs(FUMEN_TYPE_NOTES) do
        NOTE_BYTE_TO_TYPE[byte_val] = type_str
    end
end

----------------------------------------------------------------------
-- read_struct
----------------------------------------------------------------------
local function read_struct(file, order, fmt)
    local full_fmt = order .. fmt
    local size = string.packsize(full_fmt)
    local bytes = file:read(size)

    if not bytes or #bytes < size then
        return nil -- ファイル終端、またはデータ不足
    end

    local vals = { string.unpack(full_fmt, bytes) }
    vals[#vals] = nil -- string.unpack が末尾に返す「次に読み込む位置」を削除
    return vals
end

----------------------------------------------------------------------
-- parse_fumen
----------------------------------------------------------------------
local function parse_fumen(path_in, order)
    -- エンディアンの指定がない場合はリトルエンディアン ("<") をデフォルトに
    -- (3DS, PC, Switch等の環境向け。Wii U等なら ">" を明示指定)
    order = order or "<"

    local file = io.open(path_in, "rb")
    if not file then 
        error("Cannot open Fumen file: " .. tostring(path_in)) 
    end

    -- 1. ヘッダー (520バイト) の読み込み
    local header_bytes = file:read(520)
    if not header_bytes or #header_bytes < 520 then
        file:close()
        error("Invalid Fumen file: Header too short.")
    end

    -- ヘッダーオブジェクトの復元
    local header = FumenHeader.new()
    header.bytes = header_bytes
    header.order = order

    -- メインのコースオブジェクトを生成
    local song = FumenCourse.new()
    song.header = header
    song.measures = {}

    -- 2. 小節ループ (ファイルの終端に達するまで回す)
    while true do
        --------------------------------------------------------------
        -- 小節ヘッダーのパース ("ffBBHiiiiiii" = 40バイト)
        --------------------------------------------------------------
        local m_vals = read_struct(file, order, "ffBBHiiiiiii")
        if not m_vals then
            break -- 綺麗にファイルの終端に達したためループを抜ける
        end

        local measure = FumenMeasure.new()
        measure.bpm          = m_vals[1]
        measure.offset_start = m_vals[2]
        measure.gogo         = (m_vals[3] == 1)
        measure.barline      = (m_vals[4] == 1)
        measure.padding1     = m_vals[5]
        measure.branch_info  = { m_vals[6], m_vals[7], m_vals[8], m_vals[9], m_vals[10], m_vals[11] }
        measure.padding2     = m_vals[12]
        measure.branches     = {}

        --------------------------------------------------------------
        -- 分岐ヘッダーのパース ("HHf" = 8バイト × 3分岐分)
        --------------------------------------------------------------
        local branch_note_counts = {}

        for _, branch_name in ipairs(BRANCH_NAMES) do
            local b_vals = read_struct(file, order, "HHf")
            if not b_vals then
                file:close()
                error("Malformed Fumen: Missing branch header data in measure " .. (#song.measures + 1))
            end

            local branch = FumenBranch.new()
            branch.length  = b_vals[1] -- この分岐に含まれる音符数
            branch.padding = b_vals[2]
            branch.speed   = b_vals[3]
            branch.notes   = {}

            measure.branches[branch_name] = branch
            branch_note_counts[branch_name] = branch.length

        --------------------------------------------------------------
        -- 音符（ノーツ）データのパース ("ififHHf" = 24バイト × 各分岐の音符数)
        --------------------------------------------------------------
            local branch = measure.branches[branch_name]
            local num_notes = branch_note_counts[branch_name]

            for i = 1, num_notes do
                local n_vals = read_struct(file, order, "ififHHf")
                if not n_vals then
                    file:close()
                    error("Malformed Fumen: Expected " .. num_notes .. " notes, but reached EOF early.")
                end

                local note = FumenNote.new()
                local byte_type = n_vals[1]
                
                note.note_type = NOTE_BYTE_TO_TYPE[byte_type] or "Unknown"
                note.pos       = n_vals[2]
                note.item      = n_vals[3]
                note.padding   = n_vals[4]

                -- 音符タイプに応じた分岐（風船/くすだま or 通常ノーツ）
                local type_lower = note.note_type:lower()
                if type_lower == "balloon" or type_lower == "kusudama" then
                    note.hits         = n_vals[5]
                    note.hits_padding = n_vals[6]
                    note.score_init   = 0
                    note.score_diff   = 0
                else
                    note.score_init   = n_vals[5]
                    -- writers.lua で 4 倍されて書き込まれた値を元の精度に戻す
                    note.score_diff   = n_vals[6] / 4
                    note.hits         = 0
                end

                note.duration = n_vals[7]

                if type_lower == "drumroll" then
                    local extra_bytes = file:read(8)
                    if not extra_bytes or #extra_bytes < 8 then
                        file:close()
                        error("Malformed Fumen: Missing drumroll extra bytes.")
                    end
                    note.drumroll_bytes = extra_bytes

                    local Rollend = FumenNote.new()
                    Rollend.note_type = "EndDRB"
                    Rollend.pos       = note.pos + note.duration
                    Rollend.item      = n_vals[3]
                    Rollend.padding   = n_vals[4]
                    Rollend.score_init = n_vals[5]
                    -- writers.lua で 4 倍されて書き込まれた値を元の精度に戻す
                    Rollend.score_diff = n_vals[6] / 4
                    Rollend.hits      = 0
                end

                table.insert(branch.notes, note)
                table.insert(branch.notes, Rollend)
            end
        end

        table.insert(song.measures, measure)
    end

    file:close()
    return song
end

----------------------------------------------------------------------
return {
    parse_fumen = parse_fumen,
}