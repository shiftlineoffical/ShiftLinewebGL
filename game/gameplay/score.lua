local score = {
    values = {
        critical = 3,
        perfect = 3,
        good = 2,
        bad = 1,
        miss = 0
    }
}

function score.add(current, value)
    return (tonumber(current) or 0) + (score.values[value] or 0)
end

function score.value(judgment)
    return score.values[judgment] or 0
end

return score