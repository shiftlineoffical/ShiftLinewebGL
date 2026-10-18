local loader = {}
local parser = require "songs.songparser"
local cache = require "songs.songcache"
local songmanager = require "songs.songmanager"

function loader.loadCollections(collections, source)
    if type(collections) ~= "table" then
        return 0
    end
    local audioByArchive = {}
    local jacketByArchive = {}
    for _, entry in ipairs(collections.audio or {}) do
        audioByArchive[entry.archive or entry.name] = entry
    end
    for _, entry in ipairs(collections.images or {}) do
        jacketByArchive[entry.archive or entry.name] = entry
    end
    local count = 0
    for _, entry in ipairs(collections.charts or {}) do
        local id = entry.id or entry.archive or entry.name
        local chart = cache.fetch("charts", id, entry.version)
        if not chart then
            chart = parser.fromEntry(entry)
            if chart then
                cache.put("charts", id, chart, entry.version)
            end
        end
        local song = {
            id = id,
            chart = chart,
            chartEntry = entry,
            audio = audioByArchive[entry.archive or entry.name],
            jacket = jacketByArchive[entry.archive or entry.name],
            source = source or "local"
        }
        if chart and chart.meta then
            song.title = chart.meta.title
            song.artist = chart.meta.artist
            song.metadata = chart.meta
        end
        songmanager.register(song)
        count = count + 1
    end
    return count
end

return loader