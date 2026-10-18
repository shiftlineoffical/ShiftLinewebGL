local rate = {
    current = 0,
    peak = 0,
    history = {}
}

function rate.calculate(data)
    data = data or {}
    local score = math.max(0, math.min(1, (tonumber(data.score) or 0) / math.max(1, tonumber(data.maxScore) or 1000000)))
    local accuracy = math.max(0, math.min(1, tonumber(data.accuracy) or score))
    local combo = math.max(0, math.min(1, (tonumber(data.combo) or 0) / math.max(1, tonumber(data.noteCount) or 1)))
    local miss = math.max(0, tonumber(data.miss) or 0)
    local level = tonumber(data.chartLevel) or tonumber(data.difficulty) or 0
    return math.max(0, level * (score * 0.55 + accuracy * 0.35 + combo * 0.1) - miss * 0.02)
end

function rate.add(data)
    local value = rate.calculate(data)
    rate.current = rate.current * 0.9 + value * 0.1
    rate.peak = math.max(rate.peak, rate.current)
    rate.history[#rate.history + 1] = rate.current
    return rate.current, rate.current - (rate.history[#rate.history - 1] or rate.current)
end

return rate