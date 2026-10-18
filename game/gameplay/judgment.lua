local judgment = {
    windows = {
        perfect = 80,
        good = 160,
        bad = 180
    }
}

function judgment.evaluate(timingDifference, critical)
    local absolute = math.abs(tonumber(timingDifference) or math.huge)
    if absolute <= judgment.windows.perfect then
        return critical and "critical" or "perfect"
    elseif absolute <= judgment.windows.good then
        return "good"
    elseif absolute <= judgment.windows.bad then
        return "bad"
    end
    return "miss"
end

function judgment.isHit(value)
    return value == "critical" or value == "perfect" or value == "good" or value == "bad"
end

return judgment