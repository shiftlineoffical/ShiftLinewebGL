local replay = {
    active = nil,
    version = 1
}

function replay.start(songId, chartId, difficulty)
    replay.active = {
        songId = songId,
        chartId = chartId,
        difficulty = difficulty,
        inputs = {},
        startedAt = os.time(),
        version = replay.version
    }
    return replay.active
end

function replay.record(input)
    if replay.active and type(input) == "table" then
        replay.active.inputs[#replay.active.inputs + 1] = input
    end
end

function replay.finish(summary)
    if not replay.active then
        return nil
    end
    for key, value in pairs(summary or {}) do
        replay.active[key] = value
    end
    local result = replay.active
    replay.active = nil
    return result
end

function replay.load(data)
    if type(data) ~= "table" then
        return nil
    end
    data.version = data.version or 1
    data.inputs = data.inputs or {}
    return data
end

return replay