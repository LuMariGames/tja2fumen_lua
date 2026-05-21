-- converters.lua
-- Lua 5.4 port of tja2fumen.converters

local classes = require("tja2fumen.classes")
local const   = require("tja2fumen.constants")

local TJAMeasureProcessed = classes.TJAMeasureProcessed
local FumenCourse         = classes.FumenCourse
local FumenHeader         = classes.FumenHeader
local FumenMeasure        = classes.FumenMeasure
local FumenNote           = classes.FumenNote

local BRANCH_NAMES        = const.BRANCH_NAMES
local SENOTECHANGE_TYPES  = const.SENOTECHANGE_TYPES

----------------------------------------------------------------------
-- process_commands
----------------------------------------------------------------------

local function process_commands(tja_branches, bpm)
    local processed = {}
    for name in pairs(tja_branches) do
        processed[name] = {}
    end

    for branch_name, measures in pairs(tja_branches) do
        local current_bpm = bpm
        local current_scroll = 1.0
        local current_gogo = false
        local current_barline = true
        local current_senote = ""
        local dividend = 4
        local divisor  = 4

        for _, measure in ipairs(measures) do
            local mp = TJAMeasureProcessed.new{
                bpm          = current_bpm,
                scroll       = current_scroll,
                gogo         = current_gogo,
                barline      = current_barline,
                time_sig     = { dividend, divisor },
                subdivisions = #measure.notes,
            }

            for _, data in ipairs(measure.combined) do
                if data.name == "note" then
                    table.insert(mp.notes, data)

                elseif data.name == "delay" then
                    mp.delay = tonumber(data.value) * 1000

                elseif data.name == "branch_start" then
                    local parts = {}
                    for v in data.value:gmatch("[^,]+") do
                        parts[#parts+1] = v
                    end
                    if #parts ~= 3 then
                        error("#BRANCHSTART must have 3 comma-separated values")
                    end
                    local t, v1, v2 = parts[1], parts[2], parts[3]
                    if t:lower() == "r" then
                        mp.branch_type = "r"
                        mp.branch_cond = { tonumber(v1), tonumber(v2) }
                    elseif t:lower() == "p" then
                        mp.branch_type = "p"
                        mp.branch_cond = { tonumber(v1)/100, tonumber(v2)/100 }
                    else
                        error("Invalid #BRANCHSTART type: " .. t)
                    end

                elseif data.name == "section" then
                    mp.section = true

                elseif data.name == "levelhold" then
                    mp.levelhold = true

                elseif data.name == "barline" then
                    current_barline = (tonumber(data.value) == 1)
                    mp.barline = current_barline

                elseif data.name == "measure" then
                    local a,b = data.value:match("(%d+)%/(%d+)")
                    if a and b then
                        dividend = tonumber(a)
                        divisor  = tonumber(b)
                        mp.time_sig = { dividend, divisor }
                    end

                elseif data.name == "bpm"
                    or data.name == "scroll"
                    or data.name == "gogo"
                    or data.name == "senote"
                then
                    local new_val
                    if data.name == "bpm" then
                        new_val = tonumber(data.value)
                        current_bpm = new_val
                    elseif data.name == "scroll" then
                        new_val = tonumber(data.value)
                        current_scroll = new_val
                    elseif data.name == "gogo" then
                        new_val = (tonumber(data.value) == 1)
                        current_gogo = new_val
                    elseif data.name == "senote" then
                        new_val = SENOTECHANGE_TYPES[tonumber(data.value)]
                        current_senote = new_val
                    end

                    if data.pos == 0 then
                        mp[data.name] = new_val
                    else
                        mp.pos_end = data.pos
                        table.insert(processed[branch_name], mp)

                        mp = TJAMeasureProcessed.new{
                            bpm          = current_bpm,
                            scroll       = current_scroll,
                            gogo         = current_gogo,
                            barline      = current_barline,
                            time_sig     = { dividend, divisor },
                            subdivisions = #measure.notes,
                            pos_start    = data.pos,
                            senote       = current_senote,
                        }
                    end

                    current_senote = ""
                end
            end

            mp.pos_end = #measure.notes
            table.insert(processed[branch_name], mp)
        end
    end

    -- Validate branch lengths
    local lengths = {}
    for name, list in pairs(processed) do
        if #list > 0 then
            lengths[#lengths+1] = #list
        end
    end
    local first = lengths[1] or 0
    for _, v in ipairs(lengths) do
        if v ~= first then
            error("Branches do not have the same number of measures")
        end
    end

    return processed
end

----------------------------------------------------------------------
-- convert_tja_to_fumen
----------------------------------------------------------------------

local function convert_tja_to_fumen(tja)
    local tja_proc = process_commands(tja.branches, tja.bpm)

    local n_measures = #tja_proc.normal
    local fumen = FumenCourse.new{
        measures   = {},
        header     = FumenHeader.new(),
        score_init = tja.score_init,
        score_diff = tja.score_diff,
    }

    for i=1,n_measures do
        fumen.measures[i] = FumenMeasure.new()
    end

    fumen.header.b512_b515_number_of_measures = n_measures
    fumen.header.b432_b435_has_branches =
        ( #tja_proc.normal > 0 and #tja_proc.professional > 0 and #tja_proc.master > 0 ) and 1 or 0

    local balloons = {}
    for i,v in ipairs(tja.balloon) do balloons[i] = v end

    local total_notes = { normal=0, professional=0, master=0 }

    for branch_name, branch in pairs(tja_proc) do
        if #branch == 0 then goto continue end

        local branch_points_total = 0
        local branch_points_measure = 0
        local current_drumroll = FumenNote.new()
        local current_levelhold = false

        local branch_types = {}
        local branch_conditions = {}

        for idx, mp in ipairs(branch) do
            local fm = fumen.measures[idx]

            fm.branches[branch_name].speed = mp.scroll
            fm.gogo = mp.gogo
            fm.bpm  = mp.bpm

            local measure_length = mp.pos_end - mp.pos_start
            fm:set_duration(mp.time_sig, measure_length, mp.subdivisions)

            if idx == 1 then
                fm:set_first_ms_offsets(tja.offset)
            else
                fm:set_ms_offsets(mp.delay, fumen.measures[idx-1])
            end

            local barline_off = (mp.barline == false)
            local is_sub = (measure_length < mp.subdivisions and mp.pos_start ~= 0)
            if barline_off or is_sub then
                fm.barline = false
            end

            if mp.branch_type ~= "" then
                fm:set_branch_info(
                    mp.branch_type,
                    mp.branch_cond,
                    branch_points_total,
                    branch_name,
                    current_levelhold
                )
                branch_points_total = 0
                current_levelhold = false

                table.insert(branch_types, mp.branch_type)
                table.insert(branch_conditions, mp.branch_cond)
            end

            branch_points_total = branch_points_total + branch_points_measure

            if mp.levelhold then
                current_levelhold = true
            end

            branch_points_measure = 0

            for _, note_tja in ipairs(mp.notes) do
                local pos_ratio = (note_tja.pos - mp.pos_start) /
                                  (mp.pos_end - mp.pos_start)
                local note_pos = fm.duration * pos_ratio

                if note_tja.value == "EndDRB" then
                    if current_drumroll.note_type == "" then
                        goto skip_note
                    end

                    if not current_drumroll.multimeasure then
                        current_drumroll.duration =
                            current_drumroll.duration + (note_pos - current_drumroll.pos)
                    else
                        current_drumroll.duration =
                            current_drumroll.duration + (note_pos - 0)
                    end

                    current_drumroll.duration = math.floor(current_drumroll.duration)
                    current_drumroll = FumenNote.new()
                    goto skip_note
                end

                if note_tja.value == "Kusudama" and current_drumroll.note_type ~= "" then
                    goto skip_note
                end

                local note = FumenNote.new()
                note.pos = note_pos

                if mp.senote ~= "" then
                    note.note_type = mp.senote
                    note.manually_set = true
                    mp.senote = ""
                else
                    note.note_type = note_tja.value
                end

                note.score_init = tja.score_init
                note.score_diff = tja.score_diff

                if note.note_type == "Drumroll" or note.note_type == "DRUMROLL" then
                    current_drumroll = note
                elseif note.note_type == "Balloon" or note.note_type == "Kusudama" then
                    note.hits = table.remove(balloons, 1) or 1
                    current_drumroll = note
                elseif note.note_type:lower():match("^don") or note.note_type:lower():match("^ka") then
                    total_notes[branch_name] = total_notes[branch_name] + 1
                end

                local pts = 0
                if note.note_type == "Don" or note.note_type == "Ka" then
                    pts = fumen.header.b468_b471_branch_pts_good
                elseif note.note_type == "DON" or note.note_type == "KA" then
                    pts = fumen.header.b484_b487_branch_pts_good_big
                elseif note.note_type == "Balloon" then
                    pts = fumen.header.b496_b499_branch_pts_balloon
                elseif note.note_type == "Kusudama" then
                    pts = fumen.header.b500_b503_branch_pts_kusudama
                end
                branch_points_measure = branch_points_measure + pts

                table.insert(fm.branches[branch_name].notes, note)
                fm.branches[branch_name].length =
                    fm.branches[branch_name].length + 1

                ::skip_note::
            end

            if current_drumroll.note_type ~= "" then
                if current_drumroll.multimeasure then
                    current_drumroll.duration =
                        current_drumroll.duration + fm.duration
                else
                    current_drumroll.multimeasure = true
                    current_drumroll.duration =
                        current_drumroll.duration + (fm.duration - current_drumroll.pos)
                end
            end
        end

        ::continue::
    end

    fumen.header:set_hp_bytes(total_notes.normal, tja.course, tja.level)
    fumen.header:set_timing_windows(tja.course)

    return fumen
end

----------------------------------------------------------------------
-- fix_dk_note_types_course
----------------------------------------------------------------------

local function fix_dk_note_types_course(fumen)
    local bpms = {}
    for _, m in ipairs(fumen.measures) do
        bpms[#bpms+1] = m.bpm
    end

    local counts = {}
    for _, bpm in ipairs(bpms) do
        counts[bpm] = (counts[bpm] or 0) + 1
    end

    local song_bpm = nil
    local maxc = -1
    for bpm, c in pairs(counts) do
        if c > maxc then
            maxc = c
            song_bpm = bpm
        end
    end

    for _, branch in ipairs(BRANCH_NAMES) do
        local dk = {}
        for _, m in ipairs(fumen.measures) do
            for _, note in ipairs(m.branches[branch].notes) do
                if note.note_type:lower():match("^don") or
                   note.note_type:lower():match("^ka")
                then
                    note.pos_abs = m.offset_start + note.pos +
                                   (4 * 60000 / m.bpm)
                    table.insert(dk, note)
                end
            end
        end

        if #dk > 0 then
            fix_dk_note_types(dk, song_bpm)
        end
    end
end

----------------------------------------------------------------------
-- fix_dk_note_types
----------------------------------------------------------------------

function fix_dk_note_types(dk_notes, song_bpm)
    table.sort(dk_notes, function(a,b) return a.pos_abs < b.pos_abs end)

    for i=1,#dk_notes-1 do
        dk_notes[i].diff = math.floor(dk_notes[i+1].pos_abs - dk_notes[i].pos_abs)
    end

    local diffs = {}
    for _, n in ipairs(dk_notes) do
        diffs[n.diff] = true
    end

    local unique = {}
    for d in pairs(diffs) do unique[#unique+1] = d end
    table.sort(unique)

    local measure_dur = (4 * 60000) / song_bpm
    local quarter = math.floor(measure_dur / 4)
    local eighth  = math.floor(measure_dur / 8)

    local under_quarter = {}
    for _, d in ipairs(unique) do
        if d < quarter then under_quarter[#under_quarter+1] = d end
    end

    local clusters = {}
    local small = {}
    for _, d in ipairs(under_quarter) do
        if d < eighth then
            small[#small+1] = d
        else
            clusters[#clusters+1] = { d }
        end
    end
    if #small > 0 then table.insert(clusters, 1, small) end

    local semi = {}
    for _, n in ipairs(dk_notes) do semi[#semi+1] = n end

    for _, diffset in ipairs(clusters) do
        semi = cluster_notes(semi, diffset)
    end

    local final = {}
    for _, item in ipairs(semi) do
        if type(item) == "table" and item[1] then
            final[#final+1] = item
        else
            final[#final+1] = { item }
        end
    end

    replace_alternate_don_kas(final, eighth)
end

----------------------------------------------------------------------
-- cluster_notes
----------------------------------------------------------------------

function cluster_notes(list, diffset)
    local out = {}
    local cluster = {}

    local function in_set(v)
        for _, d in ipairs(diffset) do
            if v == d then return true end
        end
        return false
    end

    for _, item in ipairs(list) do
        if type(item) == "table" and item[1] and item[1].pos_abs then
            if #cluster > 0 then
                table.insert(out, cluster)
                cluster = {}
            end
            table.insert(out, item)
        else
            -- 常に現在の音符をクラスターに追加
            cluster[#cluster+1] = item
            -- 現在の音符のdiff（次の音符との間隔）が密集地帯の条件を満たさないなら、ここで区切る
            if not in_set(item.diff) then
                table.insert(out, cluster)
                cluster = {}
            end
        end
    end

    if #cluster > 0 then
        table.insert(out, cluster)
    end

    return out
end

----------------------------------------------------------------------
-- replace_alternate_don_kas
----------------------------------------------------------------------

function replace_alternate_don_kas(clusters, eighth)
    local big = { DON=true, DON2=true, KA=true, KA2=true }

    for _, cluster in ipairs(clusters) do
        for _, note in ipairs(cluster) do
            if not big[note.note_type] and not note.manually_set then
                if note.note_type:match("%d$") then
                    note.note_type = note.note_type:gsub("%d$", "2")
                else
                    note.note_type = note.note_type .. "2"
                end
            end
        end

        local all_don = true
        for _, note in ipairs(cluster) do
            if not note.note_type:match("^Don") then
                all_don = false
                break
            end
        end

        for i, note in ipairs(cluster) do
            if all_don and (#cluster % 2 == 1) and (i % 2 == 2)
                and not big[note.note_type]
                and not note.manually_set
            then
                note.note_type = "Don3"
            end
        end

        local fast4 = (#cluster == 4)
        if fast4 then
            for i=1,3 do
                if cluster[i].diff >= eighth then
                    fast4 = false
                    break
                end
            end
        end

        if not fast4 then
            local last = cluster[#cluster]
            if not big[last.note_type] and not last.manually_set then
                last.note_type = last.note_type:gsub("2$", "")
            end
        end
    end
end

----------------------------------------------------------------------
return {
    process_commands = process_commands,
    convert_tja_to_fumen = convert_tja_to_fumen,
    fix_dk_note_types_course = fix_dk_note_types_course,
    fix_dk_note_types = fix_dk_note_types,
}
