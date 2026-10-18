local gameplay = {
    song = nil,
    chart = nil,
    difficulty = "easy",
    currentTime = 0,
    currentNote = 1,
    currentMeasure = 1,
    gravity = 1,
    hs = 1,
    gogo = false,
    auto = false,
    paused = false,
    state = "idle"
}

function gameplay.reset(song, chart, difficulty)
    gameplay.song = song
    gameplay.chart = chart
    gameplay.difficulty = difficulty or "easy"
    gameplay.currentTime = 0
    gameplay.currentNote = 1
    gameplay.currentMeasure = 1
    gameplay.state = "ready"
end

function gameplay.update(time)
    if not gameplay.paused then
        gameplay.currentTime = tonumber(time) or gameplay.currentTime
    end
end

return gameplay