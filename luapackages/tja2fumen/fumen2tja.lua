-- fumen2tja.lua
-- FumenCourse オブジェクトを .tja テキストファイルに変換して書き出すスクリプト

local const = require("tja2fumen.constants")
local FUMEN_NOTE_TYPES = const.FUMEN_NOTE_TYPES -- 音符名 -> バイト値
local BRANCH_NAMES     = const.BRANCH_NAMES

-- TJAの音符文字マッピング (音符名 -> TJAの文字)
local NOTE_TYPE_TO_TJA = {
    Don = "1", Don2 = "1", Don3 = "1", Ka = "2", Ka2 = "2", DON = "3", KA = "4",
    Drumroll = "5", DRUMROLL = "6", Balloon = "7", Kusudama = "9",
    Unknown = "0"
}

----------------------------------------------------------------------
-- クオンタイズ（ミリ秒位置からTJAの文字インデックスへの変換）
----------------------------------------------------------------------
local function quantize_measure(notes, measure_start, measure_duration)
    if #notes == 0 then return "0" end -- 音符がなければ「0」1文字

    -- 各音符の小節内での相対比率（0.0 〜 1.0）を計算
    local ratios = {}
    for _, note in ipairs(notes) do
        local rel_pos = note.pos
        local ratio = rel_pos / measure_duration
        if ratio < 0 then ratio = 0 end
        if ratio > 0.999 then ratio = 0.999 end
        table.insert(ratios, { ratio = ratio, note = note })
    end

    -- 適切な小節の分割数（文字数）を探索 (4, 8, 12, 16, 32, 48, 64, 96...)
    -- すべての音符が綺麗にグリッドに乗る最小の分母を見つける
    local candidate_divs = {4, 8, 12, 16, 32, 48, 64, 96, 128, 192, 256}
    local best_div = 16

    for _, div in ipairs(candidate_divs) do
        local all_match = true
        for _, item in ipairs(ratios) do
            local grid_pos = item.ratio * div
            local _, frac = math.modf(grid_pos + 0.001) -- 丸め誤差考慮
            if frac > 0.01 and frac < 0.99 then
                all_match = false
                break
            end
        end
        if all_match then
            best_div = div
            break
        end
    end

    -- 文字列配列の初期化
    local tja_chars = {}
    for i = 1, best_div do tja_chars[i] = "0" end

    -- ノーツを配置
    for _, item in ipairs(ratios) do
        local idx = math.floor(item.ratio * best_div) + 1
        local tja_char = NOTE_TYPE_TO_TJA[item.note.note_type] or "0"
        tja_chars[idx] = tja_char
    end

    return table.concat(tja_chars)
end

----------------------------------------------------------------------
-- メインの書き出し関数
----------------------------------------------------------------------
local function write_tja(path_out, fumen_course)
    local file = io.open(path_out, "w")
    if not file then 
        fs.make_dummy_file(path_out, 0)
        file = io.open(path_out, "w")
    end

    -- 1. 簡易的な共通ヘッダーの出力
    -- (Fumenの最初の小節からBPMとOFFSETを復元)
    local first_measure = fumen_course.measures[1]
    local initial_bpm = first_measure and first_measure.bpm or 120
    
    -- Fumenのoffset_start(ミリ秒)をTJAのOFFSET(秒、符号反転)に変換
    local initial_offset = 0
    if first_measure then
        initial_offset = -(first_measure.offset_start / 1000)
    end

    file:write("TITLE: Reverse Engineered Song\n")
    file:write(string.format("BPM:%.2f\n", initial_bpm))
    file:write(string.format("OFFSET:%.4f\n", initial_offset))
    file:write("COURSE:Oni\n")
    file:write("LEVEL:10\n\n")
    file:write("#START\n")

    -- 状態管理変数
    local current_gogo = false
    local current_barline = true

    -- 2. 小節ループ
    for m_idx, measure in ipairs(fumen_course.measures) do
        -- 次の小節の開始位置から、この小節の持続時間を計算
        local next_measure = fumen_course.measures[m_idx + 1]
        local measure_duration = 2000 -- デフォルト値（4/4拍子、BPM120相当）
        if next_measure then
            measure_duration = next_measure.offset_start - measure.offset_start
        else
            -- 最終小節はBPMから4/4拍子として計算
            measure_duration = (60000 / measure.bpm) * 4
        end

        -- ギミックイベントの検知と出力
        if measure.gogo ~= current_gogo then
            current_gogo = measure.gogo
            file:write(current_gogo and "#GOGOSTART\n" or "#GOGOEND\n")
        end
        if measure.barline ~= current_barline then
            current_barline = measure.barline
            file:write(current_barline and "#BARLINEON\n" or "#BARLINEOFF\n")
        end
        
        -- ※本来はここで小節内のBPM変化やスクロール変化も検知して挿入します

        -- 3. 分岐/ノーツの出力 (ここでは分岐のない 'normal' を基準に書き出します)
        local branch = measure.branches["normal"]
        if branch then
            -- スクロールスピード（HS）の変化があれば出力
            if m_idx == 1 or fumen_course.measures[m_idx-1].branches["normal"].speed ~= branch.speed then
                file:write(string.format("#SCROLL %.2f\n", branch.speed))
            end

            -- ノーツをTJA文字列に変換
            local measure_line = quantize_measure(branch.notes, measure.offset_start, measure_duration)
            file:write(measure_line .. ",\n")
        else
            file:write("0,\n")
        end
    end

    file:write("#END\n")
    file:close()
end

return {
    write_tja = write_tja
}