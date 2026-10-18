--[[

sfb形式　中身
SFB1
ファイル数
ファイル名,オフセット,サイズ
ファイル名,オフセット,サイズ
ファイル名,オフセット,サイズ
ファイルデータ

データの渡し方
sfbloader.load()でsfbファイルを読み込む
sfbloader.load()はテーブルを返す



metaデータ変数名
musicName
musicartist
musicbpm
musicvolume
demostart
demoend
musicurl




]]





local sfbloader = {}

local log = require "log"

local function readLineFromString(data, pos)
    if not data or pos > #data then return nil, pos end
    local s, e = data:find("\n", pos, true)
    if s then
        local line = data:sub(pos, s - 1)
        if line:sub(-1) == "\r" then
            line = line:sub(1, -2)
        end
        return line, e + 1
    else
        local line = data:sub(pos)
        if line:sub(-1) == "\r" then
            line = line:sub(1, -2)
        end
        return line, #data + 1
    end
end

function sfbloader.load()
    log.info("sfbloader.load() started")
    local result = {
        audio = {},
        images = {},
        charts = {}
    }

    local files = love.filesystem.getDirectoryItems("")
    log.info("Found " .. #files .. " item(s) in root directory")
    
    local sfbCount = 0
    for _, filename in ipairs(files) do
        if filename:match("%.sfb$") then
            sfbCount = sfbCount + 1
            log.info("Found SFB file: " .. filename)
            local rawData = love.filesystem.read(filename)
            local data = nil
            if type(rawData) == "string" then
                data = rawData
            elseif rawData and rawData.getString then
                data = rawData:getString()
            end
            if type(data) == "string" then
                local pos = 1
                local magic
                magic, pos = readLineFromString(data, pos)
                local _versionLine
                _versionLine, pos = readLineFromString(data, pos)
                local countLine
                countLine, pos = readLineFromString(data, pos)

                local fileCount = tonumber(countLine)

                if magic == "SFB1" and fileCount then
                    local index = {}
                    local indexCount = 0
                    for i = 1, fileCount do
                        local line
                        line, pos = readLineFromString(data, pos)
                        if line then
                            local name, offset, size = line:match("([^,]+),([^,]+),([^,]+)")
                            if name and offset and size then
                                indexCount = indexCount + 1
                                index[indexCount] = {
                                    name = name,
                                    offset = tonumber(offset),
                                    size = tonumber(size)
                                }
                            end
                        end
                    end

                    local indexEnd = pos - 1
                    local minOffset = nil
                    for _, info in ipairs(index) do
                        if info.offset then
                            if not minOffset or info.offset < minOffset then
                                minOffset = info.offset
                            end
                        end
                    end
                    if minOffset and minOffset > indexEnd then
                        local delta = minOffset - indexEnd
                        for _, info in ipairs(index) do
                            info.offset = info.offset - delta
                        end
                    end

                    for _, info in ipairs(index) do
                        local startPos = info.offset + 1
                        local endPos = info.offset + info.size
                        if startPos >= 1 and endPos <= #data then
                            local rawData = data:sub(startPos, endPos)

                            local fileEntry = {
                                name = info.name,
                                data = rawData,
                                archive = filename
                            }

                            local infoName = info.name or ""
                            local lowerName = string.lower(infoName)
                            local ext = infoName:match("%.([^%.]+)$")
                            if not ext then
                                local jacketExt = lowerName:match("^jacket(%w+)$")
                                if jacketExt then
                                    ext = jacketExt
                                end
                            end
                            if ext then
                                ext = string.lower(ext)
                            end

                            if ext == "ogg" or ext == "wav" or ext == "mp3" then
                                result.audio[#result.audio + 1] = fileEntry
                            elseif ext == "png" or ext == "jpg" or ext == "jpeg" or lowerName:find("jacket", 1, true) then
                                result.images[#result.images + 1] = fileEntry
                            elseif ext == "bin" or ext == "lua" then
                                result.charts[#result.charts + 1] = fileEntry
                            end
                        end
                    end
                end
            end
        end
    end

    log.info("SFB files found: " .. sfbCount)
    log.info("Loaded audio files: " .. #result.audio)
    log.info("Loaded image files: " .. #result.images)
    log.info("Loaded chart files: " .. #result.charts)
    
    return result
end

return sfbloader
