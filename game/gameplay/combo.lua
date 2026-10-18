local combo = {}

function combo.apply(current, maximum, judgment)
    local value = tonumber(current) or 0
    local peak = tonumber(maximum) or 0
    if judgment == "miss" then
        return 0, peak
    end
    value = value + 1
    return value, math.max(peak, value)
end

return combo