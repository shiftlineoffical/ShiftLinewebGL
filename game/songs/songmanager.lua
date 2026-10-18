local songmanager = {
    songs = {},
    byId = {}
}

function songmanager.clear()
    songmanager.songs = {}
    songmanager.byId = {}
end

function songmanager.register(song)
    if type(song) ~= "table" then
        return nil
    end
    local id = tostring(song.id or song.songId or song.title or #songmanager.songs + 1)
    local existing = songmanager.byId[id]
    if existing then
        for key, value in pairs(song) do
            existing[key] = value
        end
        return existing
    end
    song.id = id
    song.source = song.source or "local"
    songmanager.byId[id] = song
    songmanager.songs[#songmanager.songs + 1] = song
    return song
end

function songmanager.registerCollections(collections, source)
    if type(collections) ~= "table" then
        return 0
    end
    local count = 0
    for _, entry in ipairs(collections.charts or {}) do
        local song = {}
        for key, value in pairs(entry) do
            song[key] = value
        end
        song.source = source or song.source or "local"
        if song.id == nil then
            song.id = song.archive or song.name or song.title
        end
        if songmanager.register(song) then
            count = count + 1
        end
    end
    return count
end

function songmanager.getAll()
    return songmanager.songs
end

function songmanager.get(id)
    return songmanager.byId[tostring(id)]
end

return songmanager