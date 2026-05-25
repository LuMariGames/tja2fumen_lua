-- sliding_window.lua

local SlidingWindow = {}
SlidingWindow.__index = SlidingWindow

SlidingWindow.size = 4096
SlidingWindow.disp_min = 2
SlidingWindow.disp_start = 1
SlidingWindow.match_min = 1
SlidingWindow.match_max = nil

function SlidingWindow:new(buf)
    local o = {
        data = buf,
        hash = {}, -- 各キーに対して { head = 1, tail = 0, [1] = pos, [2] = pos, ... }
        full = false,
        start = 0,
        stop = 0,
        index = 0,
    }
    setmetatable(o, self)
    assert(o.match_max ~= nil)
    return o
end

function SlidingWindow:next()
    if self.index < self.disp_start - 1 then
        self.index = self.index + 1
        return
    end

    if self.full then
        local olditem = self.data[self.start]
        local list = self.hash[olditem]
        if list then
            list.head = list.head + 1 -- table.remove(list, 1) を O(1) に最適化
        end
    end

    local item = self.data[self.stop]
    local list = self.hash[item]
    if not list then
        list = { head = 1, tail = 0 }
        self.hash[item] = list
    end
    local tail = list.tail + 1
    list[tail] = self.stop
    list.tail = tail

    self.stop = self.stop + 1
    self.index = self.index + 1

    if self.full then
        self.start = self.start + 1
    else
        if self.stop >= self.size then
            self.full = true
        end
    end
end

function SlidingWindow:advance(n)
    for _ = 1, n do
        self:next()
    end
end

function SlidingWindow:match(start, bufstart)
    local size = self.index - start
    if size == 0 then return 0 end

    local matchlen = 0
    local data = self.data
    local maxlen = #data - bufstart
    if maxlen > self.match_max then maxlen = self.match_max end

    -- ループ内のテーブルアクセスをローカル変数に固定して高速化
    for i = 0, maxlen - 1 do
        if data[start + (i % size)] == data[bufstart + i] then
            matchlen = matchlen + 1
        else
            break
        end
    end
    return matchlen
end

function SlidingWindow:search()
    local indices = self.hash[self.data[self.index]]
    if not indices or indices.head > indices.tail then return nil end

    local match_max = self.match_max
    local match_min = self.match_min
    local disp_min = self.disp_min
    local index = self.index

    local best_len = -1
    local best_disp = 0

    -- ソートや一時テーブルの作成をやめ、走査しながら最大値を記録する
    for idx = indices.head, indices.tail do
        local i = indices[idx]
        local matchlen = self:match(i, index)
        if matchlen >= match_min then
            local disp = index - i
            if disp >= disp_min then
                if matchlen > best_len then
                    best_len = matchlen
                    best_disp = -disp
                    if matchlen >= match_max then
                        break
                    end
                end
            end
        end
    end

    if best_len >= match_min then
        return {best_len, best_disp} -- 必要な時だけテーブルを返す
    end

    return nil
end

return SlidingWindow