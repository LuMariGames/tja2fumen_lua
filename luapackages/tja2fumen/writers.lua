-- writers.lua
-- Lua 5.4 port of tja2fumen.writers

local classes = require("tja2fumen.classes")
local const   = require("tja2fumen.constants")

local BRANCH_NAMES     = const.BRANCH_NAMES
local FUMEN_TYPE_NOTES = const.FUMEN_TYPE_NOTES

----------------------------------------------------------------------
-- write_struct
----------------------------------------------------------------------

local function write_struct(file, order, fmt, values)
    local full_fmt = order .. fmt
    local ok, packed = pcall(string.pack, full_fmt, table.unpack(values))
    if not ok then
        error("Can't pack values for format '" .. fmt .. "'")
    end
    file:write(packed)
end

----------------------------------------------------------------------
-- write_fumen
----------------------------------------------------------------------

local function write_fumen(path_out, song)
    local file = assert(io.open(path_out, "wb"))

    -- Write header (520 bytes)
    file:write(song.header:raw_bytes())

    for _, measure in ipairs(song.measures) do
        ------------------------------------------------------------------
        -- Write measure struct
        -- Python format: "ffBBHiiiiiii"
        --   f: bpm
        --   f: offset_start
        --   B: gogo
        --   B: barline
        --   H: padding1
        --   i x 6: branch_info
        --   i: padding2
        ------------------------------------------------------------------

        local measure_struct = {
            measure.bpm,
            measure.offset_start,
            measure.gogo and 1 or 0,
            measure.barline and 1 or 0,
            measure.padding1,
            measure.branch_info[1],
            measure.branch_info[2],
            measure.branch_info[3],
            measure.branch_info[4],
            measure.branch_info[5],
            measure.branch_info[6],
            measure.padding2,
        }

        write_struct(file, song.header.order, "ffBBHiiiiiii", measure_struct)

        ------------------------------------------------------------------
        -- Write branches
        ------------------------------------------------------------------
        for _, branch_name in ipairs(BRANCH_NAMES) do
            local branch = measure.branches[branch_name]

            -- Python format: "HHf"
            local branch_struct = {
                branch.length,
                branch.padding,
                branch.speed,
            }

            write_struct(file, song.header.order, "HHf", branch_struct)

            ------------------------------------------------------------------
            -- Write notes
            -- Python format: "ififHHf"
            ------------------------------------------------------------------
            for _, note in ipairs(branch.notes) do
                local note_type_byte = FUMEN_TYPE_NOTES[note.note_type]
                if not note_type_byte then
                    error("Unknown note type: " .. tostring(note.note_type))
                end

                local note_struct = {
                    note_type_byte,
                    note.pos,
                    note.item,
                    note.padding,
                }

                if note.hits and note.hits > 0 then
                    -- Balloon / Kusudama
                    table.insert(note_struct, note.hits)
                    table.insert(note_struct, note.hits_padding or 0)
                else
                    -- Normal notes
                    local si = math.min(65535, note.score_init)
                    local sd = math.min(65535, note.score_diff * 4)
                    table.insert(note_struct, si)
                    table.insert(note_struct, sd)
                end

                table.insert(note_struct, note.duration)

                write_struct(file, song.header.order, "ififHHf", note_struct)

                -- Drumroll extra bytes
                if note.note_type:lower() == "drumroll" then
                    file:write(note.drumroll_bytes)
                end
            end
        end
    end

    file:seek("set", 0)
    for i = 1, 36 do
        file:write("\x34\x33\xC8\x41\x67\x26\x96\x42\x22\xE2\xD8\x42")
    end

end

----------------------------------------------------------------------
return {
    write_fumen = write_fumen,
}
