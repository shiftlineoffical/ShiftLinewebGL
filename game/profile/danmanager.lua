local dan = {}

function dan.isEnabled(status)
    return type(status) == "table"
        and status.authenticated == true
        and tostring(status.username or "") == "cloudoamp"
        and tostring(status.userId or "") ~= ""
end

function dan.evaluate(course, results, status)
    if not dan.isEnabled(status) then
        return false
    end
    local totalMiss = 0
    local minimumAccuracy = 1
    local totalScore = 0
    for _, result in ipairs(results or {}) do
        totalMiss = totalMiss + (tonumber(result.miss) or 0)
        minimumAccuracy = math.min(minimumAccuracy, tonumber(result.accuracy) or 0)
        totalScore = totalScore + (tonumber(result.score) or 0)
    end
    local requirements = course and course.requirements or {}
    return totalScore >= (requirements.totalScore or 0)
        and totalMiss <= (requirements.maximumMiss or math.huge)
        and minimumAccuracy >= (requirements.minimumAccuracy or 0)
end

return dan