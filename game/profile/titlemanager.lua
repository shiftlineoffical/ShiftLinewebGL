local title = {
    data = {},
    unlocked = {}
}

function title.register(entry)
    if type(entry) == "table" and entry.id then
        title.data[entry.id] = entry
    end
end

function title.evaluate(context)
    local unlocked = {}
    for id, entry in pairs(title.data) do
        if type(entry.condition) == "function" and entry.condition(context or {}) then
            title.unlocked[id] = true
            unlocked[#unlocked + 1] = id
        end
    end
    return unlocked
end

function title.isUnlocked(id)
    return title.unlocked[id] == true
end

return title