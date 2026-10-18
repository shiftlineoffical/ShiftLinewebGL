local parser = {}

local function numberValue(value, default)
    return tonumber(value) or default
end

local function valueFor(text, key, default)
    local value = text:match(key .. "%s*%(%s*([^%)]+)%)")
    if not value then
        return default
    end
    return value:gsub("^%s*(.-)%s*$", "%1")
end

function parser.parse(text, id)
    if type(text) ~= "string" then
        return nil, "chart data must be a string"
    end
    if text:match("^%s*return%s+") then
        local loader = loadstring or load
        local chunk = loader(text, "shiftline-chart")
        if chunk then
            local ok, chart = pcall(chunk)
            if ok and type(chart) == "table" then
                chart.id = chart.id or id
                chart.raw = nil
                chart.meta = chart.meta or {}
                chart.difficulties = chart.difficulties or {}
                chart.notes = chart.notes or {}
                chart.events = chart.events or {}
                return chart
            end
        end
    end
    local result = {
        id = id,
        raw = text,
        meta = {
            title = valueFor(text, "title", ""),
            artist = valueFor(text, "artist", ""),
            audio = valueFor(text, "musicfile", valueFor(text, "audio", "")),
            bpm = numberValue(valueFor(text, "bpm", 0), 0),
            offset = numberValue(valueFor(text, "offset", 0), 0),
            volume = numberValue(valueFor(text, "volume", 1), 1),
            demostart = numberValue(valueFor(text, "demostart", 0), 0),
            demoend = numberValue(valueFor(text, "demoend", 0), 0),
            genre = valueFor(text, "genre", "")
        },
        difficulties = {},
        notes = {},
        events = {}
    }
    for _, difficulty in ipairs({"easy", "normal", "hard", "extra", "custom"}) do
        result.difficulties[difficulty] = {
            level = numberValue(text:match(difficulty .. "[^\n]-level%s*[:=]%s*([%d%.]+)"), 0),
            lanes = 6,
            notes = {}
        }
        result.notes[difficulty] = result.difficulties[difficulty].notes
        result.events[difficulty] = {}
    end
    result.meta.title = result.meta.title ~= "" and result.meta.title or valueFor(text, "musicName", "")
    return result
end

function parser.fromEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local text = entry.data
    if type(text) ~= "string" and type(entry.text) == "string" then
        text = entry.text
    end
    if not text and type(entry.path) == "string" and love.filesystem.getInfo(entry.path) then
        text = love.filesystem.read(entry.path)
    end
    if not text then
        return nil, "chart data unavailable"
    end
    return parser.parse(text, entry.id or entry.archive or entry.name)
end

return parser