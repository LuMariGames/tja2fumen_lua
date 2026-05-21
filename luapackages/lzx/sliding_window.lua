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
        hash = {},
        full = false,
        start = 0,
        stop = 0,
        index = 0,
    }
    setmetatable(o, self)
    assert(o.match_max ~= nil)
    return o
end

local function hash_get(tbl, key)
    local t = tbl[key]
    if not t then
        t = {}
        tbl[key] = t
    end
    return t
end

function SlidingWindow:next()
    if self.index < self.disp_start - 1 then
        self.index = self.index + 1
        return
    end

    if self.full then
        local olditem = self.data[self.start]
        table.remove(self.hash[olditem], 1)
    end

    local item = self.data[self.stop]
    local list = hash_get(self.hash, item)
    list[#list + 1] = self.stop

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
    local maxlen = math.min(#self.data - bufstart, self.match_max)

    for i = 0, maxlen - 1 do
        if self.data[start + (i % size)] == self.data[bufstart + i] then
            matchlen = matchlen + 1
        else
            break
        end
    end
    return matchlen
end

function SlidingWindow:search()
    local match_max = self.match_max
    local match_min = self.match_min

    local counts = {}
    local indices = self.hash[self.data[self.index]] or {}

    for _, i in ipairs(indices) do
        local matchlen = self:match(i, self.index)
        if matchlen >= match_min then
            local disp = self.index - i
            if disp >= self.disp_min then
                counts[#counts + 1] = {matchlen, -disp}
                if matchlen >= match_max then
                    return counts[#counts]
                end
            end
        end
    end

    if #counts > 0 then
        table.sort(counts, function(a, b) return a[1] > b[1] end)
        return counts[1]
    end

    return nil
end

return SlidingWindow
