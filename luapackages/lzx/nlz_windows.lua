local SlidingWindow = require("lzx.sliding_window")

local NLZ10Window = setmetatable({}, {__index = SlidingWindow})
NLZ10Window.__index = NLZ10Window
NLZ10Window.size = 4096
NLZ10Window.match_min = 3
NLZ10Window.match_max = 3 + 0xF

function NLZ10Window:new(buf)
    local o = SlidingWindow.new(self, buf)
    return o
end

local NLZ11Window = setmetatable({}, {__index = SlidingWindow})
NLZ11Window.__index = NLZ11Window
NLZ11Window.size = 4096
NLZ11Window.match_min = 3
NLZ11Window.match_max = 0x111 + 0xFFFF

function NLZ11Window:new(buf)
    local o = SlidingWindow.new(self, buf)
    return o
end

local NOverlayWindow = setmetatable({}, {__index = NLZ10Window})
NOverlayWindow.disp_min = 3

return {
    NLZ10Window = NLZ10Window,
    NLZ11Window = NLZ11Window,
    NOverlayWindow = NOverlayWindow,
}
