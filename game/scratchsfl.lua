local scratchsfl = {}

scratchsfl.foldname = {}
scratchsfl.list = {}
scratchsfl.path = {}
scratchsfl.basePath = {}

local log = require("log")

local function listDir(path)
    local ok, items = pcall(love.filesystem.getDirectoryItems, path)

    if not ok or type(items) ~= "table" then
        return {}
    end

    table.sort(items)

    return items
end

local function isDirectory(path)
    local ok, info = pcall(love.filesystem.getInfo, path)

    return ok
        and info ~= nil
        and info.type == "directory"
end

function scratchsfl.load()
    local basePaths = {
        "lib/data/Songs",
        "Songs"
    }

    local sflfoldname = {}
    local sflpath = {}
    local basePath = {}

    log.info(
        "scratchsfl: scanning basePaths: " ..
        table.concat(basePaths, ", ")
    )

    for _, base in ipairs(basePaths) do
        local entries = listDir(base)

        for _, foldName in ipairs(entries) do
            local songPath = base .. "/" .. foldName

            if isDirectory(songPath) then
                local items = listDir(songPath)
                local chartPath = nil

                for _, fileName in ipairs(items) do
                    if fileName:lower():match("%.sfl$") then
                        chartPath = songPath .. "/" .. fileName
                        break
                    end
                end

                if chartPath then
                    sflfoldname[#sflfoldname + 1] = foldName
                    sflpath[#sflpath + 1] = chartPath
                    basePath[#basePath + 1] = base

                    log.info(
                        "scratchsfl: found song: " ..
                        foldName ..
                        " -> " ..
                        chartPath
                    )
                end
            end
        end
    end

    -- 曲名順にソート
    local songs = {}

    for i = 1, #sflfoldname do
        songs[#songs + 1] = {
            name = sflfoldname[i],
            path = sflpath[i],
            base = basePath[i]
        }
    end

    table.sort(songs, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    sflfoldname = {}
    sflpath = {}
    basePath = {}

    for i, song in ipairs(songs) do
        sflfoldname[i] = song.name
        sflpath[i] = song.path
        basePath[i] = song.base
    end

    -- SFB一覧
    local filelist = {}

    for i = 1, #sflfoldname do
        local folderPath =
            basePath[i] .. "/" .. sflfoldname[i]

        local items = listDir(folderPath)

        for _, fileName in ipairs(items) do
            if fileName:lower():match("%.sfb$") then
                filelist[#filelist + 1] = fileName
            end
        end
    end

    table.sort(filelist, function(a, b)
        return a:lower() < b:lower()
    end)

    scratchsfl.foldname = sflfoldname
    scratchsfl.list = filelist
    scratchsfl.path = sflpath
    scratchsfl.basePath = basePath

    log.info(
        "scratchsfl: songs found: " ..
        tostring(#sflfoldname)
    )
end

return scratchsfl,
       scratchsfl.foldname,
       scratchsfl.list,
       scratchsfl.path