-- ADTS AAC（32000Hz / 2ch 前提）の総サンプル数を取得する
local function get_aac_total_samples(path)
    local f = assert(io.open(path, "rb"))

    local total_frames = 0
    local total_samples = 0

    while true do
        local header = f:read(7)
        if not header or #header < 7 then break end

        local b1, b2, b3, b4, b5, b6, b7 = header:byte(1, 7)

        -- syncword 0xFFF
        if b1 == 0xFF and (b2 & 0xF0) == 0xF0 then
            -- protection_absent (1bit, b2 の LSB)
            local protection_absent = b2 & 0x01

            -- フレーム長（13bit）: b4, b5, b6 を使用
            local frame_length =
                ((b4 & 0x03) << 11) |
                (b5 << 3) |
                ((b6 & 0xE0) >> 5)

            -- ヘッダーサイズ
            local header_size = protection_absent ~= 0 and 7 or 9

            -- 残りペイロード長
            local payload = frame_length - header_size
            if payload < 0 then
                -- 壊れたフレームとみなして終了
                break
            end

            -- フレームカウント
            total_frames = total_frames + 1
            total_samples = total_samples + 1024

            -- CRC 付きの場合は、すでに 7 バイトしか読んでないので
            -- 残り (header_size - 7) バイト分をスキップ
            if header_size > 7 then
                f:seek("cur", header_size - 7)
            end

            -- ペイロードをスキップ
            f:seek("cur", payload)
        else
            -- syncword でない → 1バイト戻して再検索
            f:seek("cur", -6)  -- 7バイト読んだので 6 バイト戻る
        end
    end

    f:close()
    return total_frames, total_samples
end

-- リトルエンディアンで 32bit 整数を書き込む
local function write_u32_le(f, value)
    local b1 = value & 0xFF
    local b2 = (value >> 8) & 0xFF
    local b3 = (value >> 16) & 0xFF
    local b4 = (value >> 24) & 0xFF
    f:write(string.char(b1, b2, b3, b4))
end


-- AAC → NAAC 変換
local function convert_to_naac(aac_path)

    print("AAC Loading: " .. aac_path)
    print("Please wait a moment...")
    -- 1. AAC の総サンプル数を取得
    local _, total_samples = get_aac_total_samples(aac_path)

    -- 2. AAC のバイト数を取得
    local f_in = assert(io.open(aac_path, "rb"))
    local aac_size = f_in:seek("end")
    f_in:seek("set", 0)

    -- 3. 出力ファイル作成
    print("AAC to NAAC Converting...")
    local base = aac_path:gsub("%.aac$", "")
    local naac_path
    if total_samples < 960000 then
        naac_path = base .. "_3ds_s.naac"
    else
        naac_path = base .. "_3ds.naac"
    end


    local f_out = io.open(naac_path, "wb")
    if not f_out then
        fs.make_dummy_file(naac_path, 0)
        f_out = io.open(naac_path, "wb")
    end

    -- 4. 4096 バイトのヘッダー領域を作成（全部 0x00）
    local header = string.rep("\0", 4096)
    f_out:write(header)

    -- 5. ヘッダー内容を書き込む
    -- 1-4: "AAC "
    f_out:seek("set", 0)
    f_out:write("AAC ")

    -- 5: バージョン 0x01
    f_out:write(string.char(0x01))

    -- 6-8: 予約領域（0x00）
    f_out:write("\0\0\0")

    -- 9: チャンネル数 0x02
    f_out:write(string.char(0x02))

    -- 10-12: 予約領域
    f_out:write("\0\0\0")

    -- 13-14: サンプリングレート 32000 (0x007D) リトルエンディアン
    f_out:write(string.char(0x00, 0x7D))

    -- 15-16: 予約領域
    f_out:write("\0\0")

    -- 17-20: 総サンプル数（LE）
    write_u32_le(f_out, total_samples)

    -- 21-36: 予約領域
    f_out:write(string.rep("\0", 16))

    -- 37-40: AAC 本体のバイト数（LE）
    write_u32_le(f_out, aac_size)

    -- 41-4096: 残りは 0x00 のまま
    f_out:seek("set", 4096)

    -- 6. AAC 本体を追記
    local data = f_in:read("a")
    f_out:write(data)

    f_in:close()
    f_out:close()

    print("NAAC Convert complete!")
    print("Total samples:", total_samples)
    print("AAC Size:", aac_size)
end


-- 使用例
print("AAC2NAAC")
local target = fs.ask_select_file("Select a .aac File.\n.aacファイルを選択して下さい。", "0:/tja/*.aac")
if not target then return end
convert_to_naac(target)
