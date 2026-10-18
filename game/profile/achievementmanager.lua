local achievement = {
    unlocked = {},
    pending = {}
}

function achievement.unlock(id)
    if not id or achievement.unlocked[id] then
        return false
    end
    achievement.unlocked[id] = os.time()
    achievement.pending[#achievement.pending + 1] = id
    return true
end

function achievement.evaluate(entries, context)
    local unlocked = {}
    for _, entry in ipairs(entries or {}) do
        if entry.id and type(entry.condition) == "function" and entry.condition(context or {}) and achievement.unlock(entry.id) then
            unlocked[#unlocked + 1] = entry.id
        end
    end
    return unlocked
end

function achievement.takePending()
    local pending = achievement.pending
    achievement.pending = {}
    return pending
end

return achievement