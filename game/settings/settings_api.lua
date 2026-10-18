local api = {}

function api.get(settings, path, default)
    local value = settings
    for key in tostring(path or ""):gmatch("[^%.]+") do
        if type(value) ~= "table" then
            return default
        end
        value = value[key]
    end
    if value == nil then
        return default
    end
    return value
end

function api.set(settings, path, value)
    local keys = {}
    for key in tostring(path or ""):gmatch("[^%.]+") do
        keys[#keys + 1] = key
    end
    if #keys == 0 then
        return false
    end
    local target = settings
    for i = 1, #keys - 1 do
        target[keys[i]] = target[keys[i]] or {}
        target = target[keys[i]]
    end
    target[keys[#keys]] = value
    return true
end

function api.load(settingsModule)
    if settingsModule and settingsModule.load then
        return settingsModule.load()
    end
end

function api.save(settingsModule)
    if settingsModule and settingsModule.save then
        return settingsModule.save()
    end
end

return api