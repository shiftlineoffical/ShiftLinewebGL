local judgment = require "gameplay.judgment"
local result = require "gameplay.gameplay_result"

local inputjudge = {}

function inputjudge.judge(note, now, combo, score, timestamp)
    if type(note) ~= "table" then
        return nil
    end
    local difference = ((tonumber(now) or 0) - (tonumber(note.time) or 0)) * 1000
    local value = judgment.evaluate(difference, note.critical)
    return result.new(note.id, note.lane, value, difference, combo, score, value == "critical", value == "miss", timestamp)
end

return inputjudge