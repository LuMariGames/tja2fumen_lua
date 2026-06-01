-- parsers.lua
-- Lua 5.4 port of tja2fumen.parsers

local classes = require("tja2fumen.classes")
local const   = require("tja2fumen.constants")

local TJASong        = classes.TJASong
local TJACourse      = classes.TJACourse
local TJAMeasure     = classes.TJAMeasure
local TJAData        = classes.TJAData
local FumenCourse    = classes.FumenCourse
local FumenMeasure   = classes.FumenMeasure
local FumenBranch    = classes.FumenBranch
local FumenNote      = classes.FumenNote
local FumenHeader    = classes.FumenHeader

local NORMALIZE_COURSE = const.NORMALIZE_COURSE
local COURSE_NAMES     = const.COURSE_NAMES
local BRANCH_NAMES     = const.BRANCH_NAMES
local TJA_COURSE_NAMES = const.TJA_COURSE_NAMES
local TJA_NOTE_TYPES   = const.TJA_NOTE_TYPES
local FUMEN_NOTE_TYPES = const.FUMEN_NOTE_TYPES

----------------------------------------------------------------------
-- Utility
----------------------------------------------------------------------

local function split(str, sep)
    sep = sep or ","
    local t = {}
    for part in string.gmatch(str, "([^" .. sep .. "]+)") do
        t[#t+1] = part
    end
    return t
end

----------------------------------------------------------------------
-- read_struct (Lua version)
----------------------------------------------------------------------

local function read_struct(file, order, fmt)
    local full_fmt = order .. fmt
    local size = string.packsize(full_fmt)
    local bytes = file:read(size)

    if not bytes or #bytes < size then
        bytes = (bytes or "") .. string.rep("\0", size - (bytes and #bytes or 0))
    end

    local vals = { string.unpack(full_fmt, bytes) }
    vals[#vals] = nil
    return vals
end

----------------------------------------------------------------------
-- parse_tja
----------------------------------------------------------------------

local function parse_tja(fname)
    local f = io.open(fname, "r")
    if not f then error("Cannot open TJA: " .. fname) end
    local text = f:read("a")
    f:close()

    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        if line:match("%S") then
            lines[#lines+1] = line
        end
    end

    local tja = split_tja_lines_into_courses(lines)

    for _, course in pairs(tja.courses) do
        local branches, balloon_data = parse_tja_course_data(course.data)
        course.branches = branches
        course.balloon  = fix_balloon_field(course.balloon, balloon_data)
    end

    return tja
end

----------------------------------------------------------------------
-- split_tja_lines_into_courses
----------------------------------------------------------------------

function split_tja_lines_into_courses(lines)
    local cleaned = {}
    for _, line in ipairs(lines) do
        local no_comment = line:match("^(.-)//") or line
        no_comment = no_comment:match("^%s*(.-)%s*$")
        if no_comment ~= "" then
            cleaned[#cleaned+1] = no_comment
        end
    end

    local meta = {}
    for _, key in ipairs({"BPM","OFFSET"}) do
        for _, line in ipairs(cleaned) do
            if line:match("^"..key) then
                meta[key] = tonumber(line:match(":(.*)"))
                break
            end
        end
        if not meta[key] then
            error("Missing required metadata: " .. key)
        end
    end

    local courses = {}
    for _, name in ipairs(TJA_COURSE_NAMES) do
        courses[name] = TJACourse.new{
            bpm    = meta.BPM,
            offset = meta.OFFSET,
            course = name
        }
    end

    local song = TJASong.new{
        bpm     = meta.BPM,
        offset  = meta.OFFSET,
        courses = courses
    }

    local current = ""
    local base = ""

    for _, line in ipairs(cleaned) do
        local key, val = line:match("^([%w]+):(.*)")
        local start = line:match("^#START%s*(.*)")

        if key then
            key = key:upper()
            val = val:match("^%s*(.-)%s*$")

            if key == "COURSE" then
                val = val:lower():gsub("^%l", string.upper)
                if not NORMALIZE_COURSE[val] then
                    error("Invalid COURSE: " .. val)
                end
                current = NORMALIZE_COURSE[val]
                base = current

            elseif key == "LEVEL" then
                local n = tonumber(val)
                if not n then error("Invalid LEVEL: "..val) end
                n = math.max(1, math.min(10, n))
                song.courses[current].level = n

            elseif key == "SCOREINIT" then
                song.courses[current].score_init = tonumber(val:match("([^,]+)$")) or 0

            elseif key == "SCOREDIFF" then
                song.courses[current].score_diff = tonumber(val:match("([^,]+)$")) or 0

            elseif key == "BALLOON" then
                local t = {}
                for v in val:gmatch("[^,]+") do t[#t+1] = tonumber(v) end
                song.courses[current].balloon = t

            elseif key == "STYLE" then
                if val == "Single" then
                    current = base
                end
            end

        elseif start then
            if start == "1P" or start == "2P" then
                start = start:sub(2,2) .. start:sub(1,1)
            end
            if start == "P1" or start == "P2" then
                current = base .. start
                song.courses[current] = TJACourse.new(song.courses[base])
                song.courses[current].data = {}
            elseif start ~= "" then
                error("Invalid #START: "..start)
            end
            song.courses[current].data[#song.courses[current].data+1] = "#START"

        else
            if current ~= "" then
                song.courses[current].data[#song.courses[current].data+1] = line
            end
        end
    end

    for _, cname in ipairs(COURSE_NAMES) do
        local single = song.courses[cname]
        local p1 = song.courses[cname.."P1"]
        if p1 and #p1.data > 0 and #single.data == 0 then
            song.courses[cname] = p1
        end
    end

    for k,v in pairs(song.courses) do
        if #v.data == 0 then
            song.courses[k] = nil
        end
    end

    return song
end

----------------------------------------------------------------------
-- parse_tja_course_data
----------------------------------------------------------------------

function parse_tja_course_data(data)
    local branches = {}
    local balloons = {}
    for _, b in ipairs(BRANCH_NAMES) do
        branches[b] = { TJAMeasure.new() }
        balloons[b] = {}
    end

    local has_branches = false
    for _, d in ipairs(data) do
        if d:match("^#BRANCH") then has_branches = true break end
    end

    local current = has_branches and "all" or "normal"
    local branch_condition = ""
    local idx_m = 0
    local idx_branchstart = 0

    for idx_l, line in ipairs(data) do
        local cmd, val = line:match("^#([%w]+)%s*(.*)")
        local note_data = nil
        if not cmd then note_data = line end

        if note_data then
            local notes = note_data
            local ends = notes:sub(-1) == ","
            if ends then notes = notes:sub(1, -2) end

            local targets = (current == "all") and BRANCH_NAMES or {current}
            for _, b in ipairs(targets) do
                check_branch_length(branches, b, idx_m+1)
                branches[b][idx_m].notes = branches[b][idx_m].notes .. notes
                if ends then
                    branches[b][idx_m+1] = TJAMeasure.new()
                end
            end
            if ends then idx_m = idx_m + 1 end

            local balloon_notes = {}
            for c in notes:gmatch(".") do
                if c == "7" or c == "9" then
                    balloon_notes[#balloon_notes+1] = c
                end
            end
            if current == "all" then
                for i=1,#balloon_notes do balloon_notes[i] = "DUPE" end
            end
            for _, b in ipairs((current=="all") and BRANCH_NAMES or {current}) do
                for _, bn in ipairs(balloon_notes) do
                    balloons[b][#balloons[b]+1] = bn
                end
            end

        elseif cmd then
            cmd = cmd:upper()
            local targets = (current=="all") and BRANCH_NAMES or {current}

            local pos = 0
            for _, b in ipairs(targets) do
                check_branch_length(branches, b, idx_m+1)
                if idx_m == 0 then idx_m = 1 end
                pos = #branches[b][idx_m].notes
            end

            local name = nil

            if cmd == "GOGOSTART" then name, val = "gogo","1"
            elseif cmd == "GOGOEND" then name, val = "gogo","0"
            elseif cmd == "BARLINEON" then name, val = "barline","1"
            elseif cmd == "BARLINEOFF" then name, val = "barline","0"
            elseif cmd == "DELAY" then name = "delay"
            elseif cmd == "SCROLL" then name = "scroll"
            elseif cmd == "BPMCHANGE" then name = "bpm"
            elseif cmd == "MEASURE" then name = "measure"
            elseif cmd == "LEVELHOLD" then name = "levelhold"
            elseif cmd == "SENOTECHANGE" then name = "senote"
            elseif cmd == "SECTION" then
                if data[idx_l+1] and data[idx_l+1]:match("^#BRANCHSTART") then
                    name = "section"
                    current = "all"
                elseif branch_condition == "" then
                    name = "section"
                    current = "all"
                else
                    name, val = "branch_start", branch_condition
                end
            elseif cmd == "BRANCHSTART" then
                current = "all"
                name = "branch_start"
                branch_condition = val
                for _, b in ipairs(BRANCH_NAMES) do
                    check_branch_length(branches, b)
                end
                idx_branchstart = idx_m
            elseif cmd == "START" or cmd == "END" then
                current = has_branches and "all" or "normal"
            elseif cmd == "N" then
                current = "normal"
                idx_m = idx_branchstart
            elseif cmd == "E" then
                current = "professional"
                idx_m = idx_branchstart
            elseif cmd == "M" then
                current = "master"
                idx_m = idx_branchstart
            elseif cmd == "BRANCHEND" then
                current = "all"
            end

            if name then
                for _, b in ipairs(targets) do
                    check_branch_length(branches, b, idx_m+1)
                    table.insert(branches[b][idx_m].events,
                        TJAData.new(name, val, pos))
                end
            end
        end
    end

    for _, branch in pairs(branches) do
        local last = branch[#branch]
        if #last.notes == 0 and #last.events == 0 then
            branch[#branch] = nil
        end
    end

    for bname, branch in pairs(branches) do
        if #branch > 0 then
            check_branch_length(branches, bname)
        end
    end

    for _, branch in pairs(branches) do
        for _, measure in ipairs(branch) do
            local valid = {}
            for c in measure.notes:gmatch(".") do
                if TJA_NOTE_TYPES[c] then
                    valid[#valid+1] = c
                end
            end
            local notes = {}
            for i, c in ipairs(valid) do
                local v = TJA_NOTE_TYPES[c]
                if v ~= "Blank" then
                    notes[#notes+1] = TJAData.new("note", v, i-1)
                end
            end
            local events = measure.events
            while #notes > 0 or #events > 0 do
                if #events > 0 and #notes > 0 then
                    if notes[1].pos >= events[1].pos then
                        measure.combined[#measure.combined+1] = table.remove(events,1)
                    else
                        measure.combined[#measure.combined+1] = table.remove(notes,1)
                    end
                elseif #events > 0 then
                    measure.combined[#measure.combined+1] = table.remove(events,1)
                elseif #notes > 0 then
                    measure.combined[#measure.combined+1] = table.remove(notes,1)
                end
            end
        end
    end

    return branches, balloons
end

----------------------------------------------------------------------
-- check_branch_length
----------------------------------------------------------------------

function check_branch_length(branches, name, expected)
    local branch = branches[name]
    local len = #branch

    if not expected or expected == 0 then
        local max_len = len
        local max_name = name
        for n, b in pairs(branches) do
            if #b > max_len then
                max_len = #b
                max_name = n
            end
        end
        for i=len+1, max_len do
            branch[i] = branches[max_name][i]
        end
    else
        for i=len+1, expected do
            branch[i] = TJAMeasure.new()
        end
    end
end

----------------------------------------------------------------------
-- fix_balloon_field
----------------------------------------------------------------------

function fix_balloon_field(field, data)
    local all_have = true
    for _, v in pairs(data) do
        if #v == 0 then all_have = false break end
    end
    if not all_have then return field end

    local same = true
    for _, v in pairs(data) do
        if #v ~= #field then same = false break end
    end
    if same then
        local t = {}
        for i=1,3 do
            for _, v in ipairs(field) do t[#t+1] = v end
        end
        return t
    end

    local any_dupe = false
    for _, v in pairs(data) do
        for _, x in ipairs(v) do
            if x == "DUPE" then any_dupe = true break end
        end
    end
    if not any_dupe then return field end

    local total = 0
    for _, v in pairs(data) do total = total + #v end
    if #field >= total then return field end

    local dupes = {}
    local fixed = {}

    for _, bn in ipairs(data.normal) do
        local hits = table.remove(field,1)
        if bn == "DUPE" then dupes[#dupes+1] = hits end
        fixed[#fixed+1] = hits
    end

    for _, branch in ipairs({"professional","master"}) do
        local copy = { table.unpack(dupes) }
        for _, bn in ipairs(data[branch]) do
            if bn == "DUPE" then
                fixed[#fixed+1] = table.remove(copy,1)
            else
                fixed[#fixed+1] = table.remove(field,1)
            end
        end
    end

    return fixed
end

return {
    parse_tja = parse_tja,
    parse_tja_course_data = parse_tja_course_data,
    check_branch_length = check_branch_length,
    fix_balloon_field = fix_balloon_field,
}
