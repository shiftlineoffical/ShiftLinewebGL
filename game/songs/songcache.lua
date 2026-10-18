local cache = {
    charts = {},
    audio = {},
    jackets = {},
    manifests = {}
}

function cache.get(kind, key)
    local bucket = cache[kind]
    return bucket and bucket[key]
end

function cache.put(kind, key, value, version)
    if not cache[kind] or key == nil then
        return value
    end
    cache[kind][key] = {
        version = version,
        value = value
    }
    return value
end

function cache.fetch(kind, key, version)
    local record = cache.get(kind, key)
    if type(record) == "table" and (version == nil or record.version == version) then
        return record.value
    end
    return nil
end

function cache.clear()
    cache.charts = {}
    cache.audio = {}
    cache.jackets = {}
    cache.manifests = {}
end

return cache