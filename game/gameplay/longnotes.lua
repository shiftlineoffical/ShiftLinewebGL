local longnotes = {
    active = {}
}

function longnotes.start(note)
    if note and note.id then
        longnotes.active[note.id] = {note = note, held = true}
    end
end

function longnotes.release(noteId)
    local value = longnotes.active[noteId]
    if value then
        value.held = false
        longnotes.active[noteId] = nil
    end
    return value
end

function longnotes.isHeld(noteId)
    return longnotes.active[noteId] ~= nil
end

return longnotes