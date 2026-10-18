local notes = {
    lanes = {},
    cursors = {}
}

function notes.reset(laneCount)
    notes.lanes = {}
    notes.cursors = {}
    for lane = 1, laneCount or 6 do
        notes.lanes[lane] = {}
        notes.cursors[lane] = 1
    end
end

function notes.setLane(lane, values)
    notes.lanes[lane] = values or {}
    notes.cursors[lane] = 1
end

function notes.current(lane)
    local values = notes.lanes[lane] or {}
    return values[notes.cursors[lane] or 1]
end

function notes.advance(lane)
    notes.cursors[lane] = (notes.cursors[lane] or 1) + 1
    return notes.current(lane)
end

return notes