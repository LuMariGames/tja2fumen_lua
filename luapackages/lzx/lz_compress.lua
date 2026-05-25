-- lz_compress.lua

local SlidingWindow = require("lzx.sliding_window")
local NLZ = require("lzx.nlz_windows")

local NLZ10Window = NLZ.NLZ10Window
local NLZ11Window = NLZ.NLZ11Window

local function compress_nlz10(input, out)
    local out_buffer = {}
    local buf_idx = 1

    local header_val = (#input << 8) + 0x10
    out_buffer[buf_idx] = string.char(
        header_val & 0xFF,
        (header_val >> 8) & 0xFF,
        (header_val >> 16) & 0xFF,
        (header_val >> 24) & 0xFF
    )
    buf_idx = buf_idx + 1

    local window = NLZ10Window:new(input)
    local i = 0
    local n_input = #input
    local length = 0
    local tokens_area = {}

    while i < n_input do
        local flag_byte = 0
        local token_count = 0

        for k = 1, 8 do
            flag_byte = flag_byte << 1
            if i < n_input then
                local match = window:search()
                token_count = token_count + 1
                
                if match then
                    flag_byte = flag_byte | 1
                    local count, disp = match[1], match[2]
                    window:advance(count)
                    i = i + count

                    local c = count - 3
                    local d = (-disp) - 1
                    local sh = (c << 12) | d
                    
                    tokens_area[token_count] = string.char((sh >> 8) & 0xFF, sh & 0xFF)
                else
                    local b = input[i]
                    window:next()
                    i = i + 1
                    tokens_area[token_count] = string.char(b & 0xFF)
                end
            end
        end

        out_buffer[buf_idx] = string.char(flag_byte & 0xFF)
        buf_idx = buf_idx + 1
        length = length + 1

        for j = 1, token_count do
            local t_str = tokens_area[j]
            out_buffer[buf_idx] = t_str
            buf_idx = buf_idx + 1
            length = length + #t_str
        end
    end

    local padding = 4 - (length % 4 == 0 and 4 or (length % 4))
    if padding > 0 then
        out_buffer[buf_idx] = string.rep("\xFF", padding)
    end

    out:write(table.concat(out_buffer))
end

local function compress_nlz11(input, out)
    local out_buffer = {}
    local buf_idx = 1

    -- ヘッダー書き込み
    local header_val = (#input << 8) + 0x11
    out_buffer[buf_idx] = string.char(
        header_val & 0xFF,
        (header_val >> 8) & 0xFF,
        (header_val >> 16) & 0xFF,
        (header_val >> 24) & 0xFF
    )
    buf_idx = buf_idx + 1

    local window = NLZ11Window:new(input)
    local i = 0
    local n_input = #input
    local length = 0
    
    -- トークンのキャッシュエリア（最大8個）
    -- matches[k] にテーブルが入っていればマッチ、数値ならリテラル
    local tokens_match = {} 
    local tokens_str = {}

    while i < n_input do
        local flag_byte = 0
        local token_count = 0

        -- 8個のトークンを先読み・探索
        for k = 1, 8 do
            flag_byte = flag_byte << 1
            if i < n_input then
                token_count = token_count + 1
                local match = window:search()
                if match then
                    flag_byte = flag_byte | 1
                    tokens_match[token_count] = match
                    window:advance(match[1])
                    i = i + match[1]
                else
                    tokens_match[token_count] = input[i]
                    window:next()
                    i = i + 1
                end
            end
        end

        -- フラグバイトを確定
        out_buffer[buf_idx] = string.char(flag_byte & 0xFF)
        buf_idx = buf_idx + 1
        length = length + 1

        -- トークンを文字列化してバッファへ
        for j = 1, token_count do
            local t = tokens_match[j]
            if type(t) == "table" then
                local count, disp = t[1], t[2]
                disp = (-disp) - 1

                if count <= 16 then -- 1 + 0xF
                    count = count - 1
                    local sh = (count << 12) | disp
                    out_buffer[buf_idx] = string.char((sh >> 8) & 0xFF, sh & 0xFF)
                    buf_idx = buf_idx + 1
                    length = length + 2
                elseif count <= 272 then -- 0x11 + 0xFF
                    count = count - 0x11
                    local b = count >> 4
                    local sh = ((count & 0xF) << 12) | disp
                    out_buffer[buf_idx] = string.char(b & 0xFF, (sh >> 8) & 0xFF, sh & 0xFF)
                    buf_idx = buf_idx + 1
                    length = length + 3
                else
                    count = count - 0x111
                    local l = (1 << 28) | (count << 12) | disp
                    out_buffer[buf_idx] = string.char(
                        l & 0xFF,
                        (l >> 8) & 0xFF,
                        (l >> 16) & 0xFF,
                        (l >> 24) & 0xFF
                    )
                    buf_idx = buf_idx + 1
                    length = length + 4
                end
            else
                -- リテラル（1バイト）
                out_buffer[buf_idx] = string.char(t & 0xFF)
                buf_idx = buf_idx + 1
                length = length + 1
            end
        end
    end

    local padding = 4 - (length % 4 == 0 and 4 or (length % 4))
    if padding > 0 then
        out_buffer[buf_idx] = string.rep("\xFF", padding)
    end

    out:write(table.concat(out_buffer))
end

return {
    compress_nlz10 = compress_nlz10,
    compress_nlz11 = compress_nlz11,
}