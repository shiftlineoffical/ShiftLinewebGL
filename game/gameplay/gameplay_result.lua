local result = {}

function result.new(noteId, lane, judgment, timingDifference, combo, score, critical, miss, timestamp)
    return {
        noteId = noteId,
        lane = lane,
        judgment = judgment,
        timingDifference = timingDifference or 0,
        combo = combo or 0,
        score = score or 0,
        critical = critical == true,
        miss = miss == true,
        timestamp = timestamp or 0
    }
end

return result