-- constants.lua
-- Lua 5.4 port of tja2fumen.constants

local M = {}

-- Names for branches in diverge songs
M.BRANCH_NAMES = { "normal", "professional", "master" }

-- Types of notes that can be found in TJA files
M.TJA_NOTE_TYPES = {
    ['0'] = 'Blank',
    ['1'] = 'Don',
    ['2'] = 'Ka',
    ['3'] = 'DON',
    ['4'] = 'KA',
    ['5'] = 'Drumroll',
    ['6'] = 'DRUMROLL',
    ['7'] = 'Balloon',
    ['8'] = 'EndDRB',
    ['9'] = 'Kusudama',
    ['A'] = 'DON2',      -- hands
    ['B'] = 'KA2',       -- hands
    ['C'] = 'Blank',     -- bombs
    ['D'] = 'Drumroll',  -- fuse roll
    ['E'] = 'DON2',      -- red + green single hit
    ['F'] = 'Ka',        -- ADLib (hidden note)
    ['G'] = 'KA2',       -- red + green double hit
    ['H'] = 'DRUMROLL',  -- double roll
    ['I'] = 'Drumroll',  -- green roll
}

-- Conversion for TJAPlayer3's #SENOTECHANGE command
M.SENOTECHANGE_TYPES = {
    [1] = "Don",   -- ドン
    [2] = "Don2",  -- ド
    [3] = "Don3",  -- コ
    [4] = "Ka",    -- カッ
    [5] = "Ka2",   -- カ
}

-- Types of notes that can be found in fumen files
M.FUMEN_NOTE_TYPES = {
    [0x1]  = "Don",      -- ドン
    [0x2]  = "Don2",     -- ド
    [0x3]  = "Don3",     -- コ
    [0x4]  = "Ka",       -- カッ
    [0x5]  = "Ka2",      -- カ
    [0x6]  = "Drumroll",
    [0x7]  = "DON",
    [0x8]  = "KA",
    [0x9]  = "DRUMROLL",
    [0xA]  = "Balloon",
    [0xB]  = "DON2",        -- hands
    [0xC]  = "Kusudama",
    [0xD]  = "KA2",         -- hands
    [0xE]  = "Unknown1",    -- ? (Present in some Wii1 songs)
    [0xF]  = "Unknown2",    -- ? (Present in some PS4 songs)
    [0x10] = "Unknown3",    -- ? (Present in some Wii1 songs)
    [0x11] = "Unknown4",    -- ? (Present in some Wii1 songs)
    [0x12] = "Unknown5",    -- ? (Present in some Wii4 songs)
    [0x13] = "Unknown6",    -- ? (Present in some Wii1 songs)
    [0x14] = "Unknown7",    -- ? (Present in some PS4 songs)
    [0x15] = "Unknown8",    -- ? (Present in some Wii1 songs)
    [0x16] = "Unknown9",    -- ? (Present in some Wii1 songs)
    [0x17] = "Unknown10",   -- ? (Present in some Wii4 songs)
    [0x18] = "Unknown11",   -- ? (Present in some PS4 songs)
    [0x19] = "Unknown12",   -- ? (Present in some PS4 songs)
    [0x22] = "Unknown13",   -- ? (Present in some Wii1 songs)
    [0x62] = "Drumroll2",   -- ?
}

-- Invert the dict to go from note type to fumen byte values
M.FUMEN_TYPE_NOTES = {}
for k, v in pairs(M.FUMEN_NOTE_TYPES) do
    M.FUMEN_TYPE_NOTES[v] = k
end

-- Normalize the various fumen course names into 1 name per difficulty
M.NORMALIZE_COURSE = {
    ['0']     = 'Easy',
    Easy      = 'Easy',
    ['1']     = 'Normal',
    Normal    = 'Normal',
    ['2']     = 'Hard',
    Hard      = 'Hard',
    ['3']     = 'Oni',
    Oni       = 'Oni',
    ['4']     = 'Ura',
    Ura       = 'Ura',
    Edit      = 'Ura',
}

-- Fetch the 5 valid course names from NORMALIZE_COURSE's values
M.COURSE_NAMES = {}
do
    local seen = {}
    for _, v in pairs(M.NORMALIZE_COURSE) do
        if not seen[v] then
            seen[v] = true
            table.insert(M.COURSE_NAMES, v)
        end
    end
end

-- All combinations of difficulty and single/multiplayer type
M.TJA_COURSE_NAMES = {}
do
    local players = { "", "P1", "P2" }
    for _, difficulty in ipairs(M.COURSE_NAMES) do
        for _, p in ipairs(players) do
            table.insert(M.TJA_COURSE_NAMES, difficulty .. p)
        end
    end
end

-- Map course difficulty to filename IDs (e.g. Oni -> `song_m.bin`)
M.COURSE_IDS = {
    Easy   = 'e',
    Normal = 'n',
    Hard   = 'h',
    Oni    = 'm',
    Ura    = 'ex',
}

M.TIMING_WINDOWS = {
    --          "GOOD"              "OK"               "BAD"
    Easy   = { 41.7083358764648, 108.441665649414, 125.125000000000 },
    Normal = { 41.7083358764648, 108.441665649414, 125.125000000000 },
    Hard   = { 25.0250015258789,  75.075004577637, 108.441665649414 },
    Oni    = { 25.0250015258789,  75.075004577637, 108.441665649414 },
}

return M
