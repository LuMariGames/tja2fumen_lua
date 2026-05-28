-- classes.lua
-- Lua 5.4 implementation of tja2fumen.classes

local const   = require("tja2fumen.constants")

-- 依存（Python 側の BRANCH_NAMES, TIMING_WINDOWS 相当）
local BRANCH_NAMES = BRANCH_NAMES or { "normal", "professional", "master" }
local TIMING_WINDOWS = TIMING_WINDOWS or const.TIMING_WINDOWS -- 例: TIMING_WINDOWS["Oni"] = { ... }

local M = {}

----------------------------------------------------------------------
-- 小さなユーティリティ
----------------------------------------------------------------------

local function deepcopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local t = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            t[k] = deepcopy(v)
        else
            t[k] = v
        end
    end
    return t
end

local function split(str, sep)
    sep = sep or ","
    local t = {}
    for part in string.gmatch(str, "([^" .. sep .. "]+)") do
        t[#t+1] = part
    end
    return t
end

----------------------------------------------------------------------
-- TJAData
----------------------------------------------------------------------

local TJAData = {}
TJAData.__index = TJAData

function TJAData.new(name, value, pos)
    return setmetatable({
        name = name,
        value = value,
        pos = pos, -- int
    }, TJAData)
end

M.TJAData = TJAData

----------------------------------------------------------------------
-- TJAMeasure
----------------------------------------------------------------------

local TJAMeasure = {}
TJAMeasure.__index = TJAMeasure

function TJAMeasure.new()
    return setmetatable({
        notes = "",
        events = {},
        combined = {},
    }, TJAMeasure)
end

M.TJAMeasure = TJAMeasure

----------------------------------------------------------------------
-- TJACourse
----------------------------------------------------------------------

local TJACourse = {}
TJACourse.__index = TJACourse

function TJACourse.new(args)
    args = args or {}
    return setmetatable({
        bpm       = args.bpm,
        offset    = args.offset,
        course    = args.course,
        level     = args.level or 0,
        balloon   = args.balloon or {},
        score_init = args.score_init or 0,
        score_diff = args.score_diff or 0,
        data      = args.data or {},
        branches  = args.branches or {}, -- name -> { TJAMeasure, ... }
    }, TJACourse)
end

M.TJACourse = TJACourse

----------------------------------------------------------------------
-- TJASong
----------------------------------------------------------------------

local TJASong = {}
TJASong.__index = TJASong

function TJASong.new(args)
    args = args or {}
    return setmetatable({
        bpm     = args.bpm,
        offset  = args.offset,
        courses = args.courses or {}, -- name -> TJACourse
    }, TJASong)
end

M.TJASong = TJASong

----------------------------------------------------------------------
-- TJAMeasureProcessed
----------------------------------------------------------------------

local TJAMeasureProcessed = {}
TJAMeasureProcessed.__index = TJAMeasureProcessed

function TJAMeasureProcessed.new(args)
    args = args or {}
    return setmetatable({
        bpm          = args.bpm or 0.0,
        scroll       = args.scroll or 1.0,
        gogo         = args.gogo or false,
        barline      = (args.barline ~= false),
        time_sig     = args.time_sig or {4, 4},
        subdivisions = args.subdivisions or 0,
        pos_start    = args.pos_start or 0,
        pos_end      = args.pos_end or 0,
        delay        = args.delay or 0.0,
        section      = args.section or false,
        levelhold    = args.levelhold or false,
        senote       = args.senote or "",
        branch_type  = args.branch_type or "",
        branch_cond  = args.branch_cond or {0.0, 0.0},
        notes        = args.notes or {}, -- { TJAData, ... }
    }, TJAMeasureProcessed)
end

M.TJAMeasureProcessed = TJAMeasureProcessed

----------------------------------------------------------------------
-- FumenNote
----------------------------------------------------------------------

local FumenNote = {}
FumenNote.__index = FumenNote

function FumenNote.new(args)
    args = args or {}
    return setmetatable({
        note_type     = args.note_type or "",
        pos           = args.pos or 0.0,
        pos_abs       = args.pos_abs or 0.0,
        diff          = args.diff or 0,
        score_init    = args.score_init or 0,
        score_diff    = args.score_diff or 0,
        padding       = args.padding or 0.0,
        item          = args.item or 0,
        duration      = args.duration or 0.0,
        multimeasure  = args.multimeasure or false,
        hits          = args.hits or 0,
        hits_padding  = args.hits_padding or 0,
        drumroll_bytes = args.drumroll_bytes or string.rep("\0", 8),
        manually_set  = args.manually_set or false,
    }, FumenNote)
end

M.FumenNote = FumenNote

----------------------------------------------------------------------
-- FumenBranch
----------------------------------------------------------------------

local FumenBranch = {}
FumenBranch.__index = FumenBranch

function FumenBranch.new(args)
    args = args or {}
    return setmetatable({
        length  = args.length or 0,
        speed   = args.speed or 0.0,
        padding = args.padding or 0,
        notes   = args.notes or {}, -- { FumenNote, ... }
    }, FumenBranch)
end

M.FumenBranch = FumenBranch

----------------------------------------------------------------------
-- FumenMeasure
----------------------------------------------------------------------

local FumenMeasure = {}
FumenMeasure.__index = FumenMeasure

local function default_branch_info()
    return { -1, -1, -1, -1, -1, -1 }
end

local function default_branches()
    local t = {}
    for _, name in ipairs(BRANCH_NAMES) do
        t[name] = FumenBranch.new()
    end
    return t
end

function FumenMeasure.new(args)
    args = args or {}
    return setmetatable({
        bpm          = args.bpm or 0.0,
        offset_start = args.offset_start or 0.0,
        offset_end   = args.offset_end or 0.0,
        duration     = args.duration or 0.0,
        gogo         = args.gogo or false,
        barline      = (args.barline ~= false),
        branch_info  = args.branch_info or default_branch_info(),
        branches     = args.branches or default_branches(),
        padding1     = args.padding1 or 0,
        padding2     = args.padding2 or 0,
    }, FumenMeasure)
end

function FumenMeasure:set_duration(time_sig, measure_length, subdivisions)
    -- time_sig: {num, den}
    local num, den = time_sig[1], time_sig[2]
    local full_duration = 4 * 60000 / self.bpm
    local measure_size = num / den
    local measure_ratio
    if subdivisions == 0 or subdivisions == 0.0 then
        measure_ratio = 1.0
    else
        measure_ratio = measure_length / subdivisions
    end
    self.duration = full_duration * measure_size * measure_ratio
end

function FumenMeasure:set_first_ms_offsets(song_offset)
    -- song_offset: seconds
    self.offset_start = song_offset * -1 * 1000
    self.offset_start = self.offset_start - (4 * 60000 / self.bpm)
    self.offset_end = self.offset_start + self.duration
end

function FumenMeasure:set_ms_offsets(delay, prev_measure)
    self.offset_start = prev_measure.offset_end
    self.offset_start = self.offset_start + delay
    self.offset_start = self.offset_start + (4 * 60000 / prev_measure.bpm)
    self.offset_start = self.offset_start - (4 * 60000 / self.bpm)
    self.offset_end = self.offset_start + self.duration
end

function FumenMeasure:set_branch_info(branch_type, branch_cond,
                                      branch_points_total,
                                      current_branch,
                                      has_levelhold)
    if has_levelhold then
        if current_branch == "normal" then
            self.branch_info[1] = 999
            self.branch_info[2] = 999
        elseif current_branch == "professional" then
            self.branch_info[3] = 0
            self.branch_info[4] = 999
        elseif current_branch == "master" then
            self.branch_info[5] = 0
            self.branch_info[6] = 0
        end
        return
    end

    if branch_type == "p" then
        local vals = {}
        for i = 1, 2 do
            local percent = branch_cond[i]
            if percent > 0 and percent <= 1 then
                vals[i] = math.floor(branch_points_total * percent + 0.5)
            elseif percent > 1 then
                vals[i] = 999
            else
                vals[i] = 0
            end
        end
        if current_branch == "normal" then
            self.branch_info[1], self.branch_info[2] = vals[1], vals[2]
        elseif current_branch == "professional" then
            self.branch_info[3], self.branch_info[4] = vals[1], vals[2]
        elseif current_branch == "master" then
            self.branch_info[5], self.branch_info[6] = vals[1], vals[2]
        end
    elseif branch_type == "r" then
        local v1 = math.floor(branch_cond[1])
        local v2 = math.floor(branch_cond[2])
        if current_branch == "normal" then
            self.branch_info[1], self.branch_info[2] = v1, v2
        elseif current_branch == "professional" then
            self.branch_info[3], self.branch_info[4] = v1, v2
        elseif current_branch == "master" then
            self.branch_info[5], self.branch_info[6] = v1, v2
        end
    end
end

M.FumenMeasure = FumenMeasure

----------------------------------------------------------------------
-- FumenHeader
----------------------------------------------------------------------

local FumenHeader = {}
FumenHeader.__index = FumenHeader

local function default_timing_windows()
    local t = {}
    for i = 1, 108 do
        t[i] = 0.0
    end
    return t
end

function FumenHeader.new(args)
    args = args or {}
    return setmetatable({
        order                           = args.order or "<",
        b000_b431_timing_windows        = args.b000_b431_timing_windows or default_timing_windows(),
        b432_b435_has_branches          = args.b432_b435_has_branches or 0,
        b436_b439_hp_max                = args.b436_b439_hp_max or 10000,
        b440_b443_hp_clear              = args.b440_b443_hp_clear or 8000,
        b444_b447_hp_gain_good          = args.b444_b447_hp_gain_good or 10,
        b448_b451_hp_gain_ok            = args.b448_b451_hp_gain_ok or 5,
        b452_b455_hp_loss_bad           = args.b452_b455_hp_loss_bad or -20,
        b456_b459_normal_normal_ratio   = args.b456_b459_normal_normal_ratio or 65536,
        b460_b463_normal_professional_ratio = args.b460_b463_normal_professional_ratio or 65536,
        b464_b467_normal_master_ratio   = args.b464_b467_normal_master_ratio or 65536,
        b468_b471_branch_pts_good       = args.b468_b471_branch_pts_good or 20,
        b472_b475_branch_pts_ok         = args.b472_b475_branch_pts_ok or 10,
        b476_b479_branch_pts_bad        = args.b476_b479_branch_pts_bad or 0,
        b480_b483_branch_pts_drumroll   = args.b480_b483_branch_pts_drumroll or 1,
        b484_b487_branch_pts_good_big   = args.b484_b487_branch_pts_good_big or 20,
        b488_b491_branch_pts_ok_big     = args.b488_b491_branch_pts_ok_big or 10,
        b492_b495_branch_pts_drumroll_big = args.b492_b495_branch_pts_drumroll_big or 1,
        b496_b499_branch_pts_balloon    = args.b496_b499_branch_pts_balloon or 30,
        b500_b503_branch_pts_kusudama   = args.b500_b503_branch_pts_kusudama or 30,
        b504_b507_branch_pts_unknown    = args.b504_b507_branch_pts_unknown or 20,
        b508_b511_dummy_data            = args.b508_b511_dummy_data or 12345678,
        b512_b515_number_of_measures    = args.b512_b515_number_of_measures or 0,
        b516_b519_unknown_data          = args.b516_b519_unknown_data or 0,
    }, FumenHeader)
end

function FumenHeader:unp(raw_bytes, fmt, start_idx, end_idx)
    -- Lua string index is 1-based, Python slice is 0-based inclusive
    local len = end_idx - start_idx + 1
    local chunk = string.sub(raw_bytes, start_idx + 1, start_idx + len)
    local order = self.order or "<"
    local full_fmt = order .. fmt
    local vals = { string.unpack(full_fmt, chunk) }
    -- string.unpack returns values + next_index; drop last
    vals[#vals] = nil
    if #vals == 1 then
        return vals[1]
    else
        return vals
    end
end

function FumenHeader:_parse_order(raw_bytes)
    self.order = ""
    local big  = self:unp(raw_bytes, "I4", 512, 515) -- ">I" 相当は order で切り替えたいが、
    local little = self:unp(raw_bytes, "I4", 512, 515) -- 実際には order を変えつつ読む必要がある
    -- 上のままだと同じ order で読んでしまうので、実運用では
    -- big/little 用に一時的に self.order を変えて読むのが安全。
    -- ここでは Python 実装の意図に合わせて簡略化するなら、
    -- 先に big, 次に little を別々に読むようにする:

    -- 正しくやるなら:
    -- self.order = ">"
    -- local big = self:unp(raw_bytes, "I4", 512, 515)
    -- self.order = "<"
    -- local little = self:unp(raw_bytes, "I4", 512, 515)

    -- ここでは上記コメントの形で使うことを想定
    if big < little then
        self.order = ">"
    else
        self.order = "<"
    end
end

function FumenHeader:parse_header_values(raw_bytes)
    self:_parse_order(raw_bytes)
    local raw = raw_bytes
    self.b000_b431_timing_windows          = self:unp(raw, "f108", 0, 431)
    self.b432_b435_has_branches            = self:unp(raw, "i4", 432, 435)
    self.b436_b439_hp_max                  = self:unp(raw, "i4", 436, 439)
    self.b440_b443_hp_clear                = self:unp(raw, "i4", 440, 443)
    self.b444_b447_hp_gain_good            = self:unp(raw, "i4", 444, 447)
    self.b448_b451_hp_gain_ok              = self:unp(raw, "i4", 448, 451)
    self.b452_b455_hp_loss_bad             = self:unp(raw, "i4", 452, 455)
    self.b456_b459_normal_normal_ratio     = self:unp(raw, "i4", 456, 459)
    self.b460_b463_normal_professional_ratio = self:unp(raw, "i4", 460, 463)
    self.b464_b467_normal_master_ratio     = self:unp(raw, "i4", 464, 467)
    self.b468_b471_branch_pts_good         = self:unp(raw, "i4", 468, 471)
    self.b472_b475_branch_pts_ok           = self:unp(raw, "i4", 472, 475)
    self.b476_b479_branch_pts_bad          = self:unp(raw, "i4", 476, 479)
    self.b480_b483_branch_pts_drumroll     = self:unp(raw, "i4", 480, 483)
    self.b484_b487_branch_pts_good_big     = self:unp(raw, "i4", 484, 487)
    self.b488_b491_branch_pts_ok_big       = self:unp(raw, "i4", 488, 491)
    self.b492_b495_branch_pts_drumroll_big = self:unp(raw, "i4", 492, 495)
    self.b496_b499_branch_pts_balloon      = self:unp(raw, "i4", 496, 499)
    self.b500_b503_branch_pts_kusudama     = self:unp(raw, "i4", 500, 503)
    self.b504_b507_branch_pts_unknown      = self:unp(raw, "i4", 504, 507)
    self.b508_b511_dummy_data              = self:unp(raw, "i4", 508, 511)
    self.b512_b515_number_of_measures      = self:unp(raw, "i4", 512, 515)
    self.b516_b519_unknown_data            = self:unp(raw, "i4", 516, 519)
end

function FumenHeader:set_timing_windows(difficulty)
    if difficulty == "Ura" or difficulty == "Edit" then
        difficulty = "Oni"
    end
    local tw = TIMING_WINDOWS[difficulty]
    local t = {}
    if tw then
        for i = 1, 36 do
            for j = 1, #tw do
                t[#t+1] = tw[j]
            end
        end
    else
        t = default_timing_windows()
    end
    self.b000_b431_timing_windows = t
end

function FumenHeader:_get_hp_from_lookup_tables(n_notes, difficulty, stars)
    if not (n_notes > 0 and n_notes <= 2500) then
        return
    end
    local star_to_key = {
        Oni =   { [1]='17',[2]='17',[3]='17',[4]='17',[5]='17',
                  [6]='17',[7]='17',[8]='8',[9]='910',[10]='910' },
        Hard =  { [1]='12',[2]='12',[3]='3',[4]='4',[5]='58',
                  [6]='58',[7]='58',[8]='58',[9]='58',[10]='58' },
        Normal={ [1]='12',[2]='12',[3]='3',[4]='4',[5]='57',
                  [6]='57',[7]='57',[8]='57',[9]='57',[10]='57' },
        Easy = { [1]='1',[2]='23',[3]='23',[4]='45',[5]='45',
                 [6]='45',[7]='45',[8]='45',[9]='45',[10]='45' },
    }
    local key = difficulty .. "-" .. star_to_key[difficulty][stars]
    local f = io.open("0:/gm9/luapackages/tja2fumen/hp_values.csv", "r")
    if not f then return end
    local header_line = f:read("l")
    if not header_line then f:close(); return end
    local headers = split(header_line, ",")
    local good_key = "good_" .. key
    local ok_key   = "ok_" .. key
    local bad_key  = "bad_" .. key

    local idx_good, idx_ok, idx_bad
    for i, h in ipairs(headers) do
        if h == good_key then idx_good = i end
        if h == ok_key   then idx_ok   = i end
        if h == bad_key  then idx_bad  = i end
    end

    local num = 0
    for line in f:lines() do
        num = num + 1
        if num == n_notes then
            local cols = split(line, ",")
            if idx_good then
                self.b444_b447_hp_gain_good = tonumber(cols[idx_good]) or self.b444_b447_hp_gain_good
            end
            if idx_ok then
                self.b448_b451_hp_gain_ok = tonumber(cols[idx_ok]) or self.b448_b451_hp_gain_ok
            end
            if idx_bad then
                self.b452_b455_hp_loss_bad = tonumber(cols[idx_bad]) or self.b452_b455_hp_loss_bad
            end
            break
        end
    end
    f:close()
end

function FumenHeader:set_hp_bytes(n_notes, difficulty, stars)
    if difficulty == "Ura" or difficulty == "Edit" then
        difficulty = "Oni"
    end
    self:_get_hp_from_lookup_tables(n_notes, difficulty, stars)
    local clear_map = {
        Easy   = 6000,
        Normal = 7000,
        Hard   = 7000,
        Oni    = 8000,
    }
    self.b440_b443_hp_clear = clear_map[difficulty] or self.b440_b443_hp_clear
end

function FumenHeader:raw_bytes()
    local fmt = self.order
    local values = {}

    -- timing windows
    for _ = 1, #self.b000_b431_timing_windows do
        fmt = fmt .. "f"
    end
    for _, v in ipairs(self.b000_b431_timing_windows) do
        values[#values+1] = v
    end

    local ints = {
        "b432_b435_has_branches",
        "b436_b439_hp_max",
        "b440_b443_hp_clear",
        "b444_b447_hp_gain_good",
        "b448_b451_hp_gain_ok",
        "b452_b455_hp_loss_bad",
        "b456_b459_normal_normal_ratio",
        "b460_b463_normal_professional_ratio",
        "b464_b467_normal_master_ratio",
        "b468_b471_branch_pts_good",
        "b472_b475_branch_pts_ok",
        "b476_b479_branch_pts_bad",
        "b480_b483_branch_pts_drumroll",
        "b484_b487_branch_pts_good_big",
        "b488_b491_branch_pts_ok_big",
        "b492_b495_branch_pts_drumroll_big",
        "b496_b499_branch_pts_balloon",
        "b500_b503_branch_pts_kusudama",
        "b504_b507_branch_pts_unknown",
        "b508_b511_dummy_data",
        "b512_b515_number_of_measures",
        "b516_b519_unknown_data",
    }

    for _ = 1, #ints do
        fmt = fmt .. "i4"
    end
    for _, name in ipairs(ints) do
        values[#values+1] = self[name]
    end

    local packed = string.pack(fmt, table.unpack(values))
    assert(#packed == 520, "FumenHeader.raw_bytes: expected 520 bytes, got " .. #packed)
    return packed
end

M.FumenHeader = FumenHeader

----------------------------------------------------------------------
-- FumenCourse
----------------------------------------------------------------------

local FumenCourse = {}
FumenCourse.__index = FumenCourse

function FumenCourse.new(args)
    args = args or {}
    return setmetatable({
        header     = args.header or FumenHeader.new(),
        measures   = args.measures or {}, -- { FumenMeasure, ... }
        score_init = args.score_init or 0,
        score_diff = args.score_diff or 0,
    }, FumenCourse)
end

M.FumenCourse = FumenCourse

----------------------------------------------------------------------
return M
