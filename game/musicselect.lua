
local musicselect={}
local log = require "log"
local audiocache = require "audiocache"
local createsfb = require "createsfb"
local play = require "gameplay.play"
local i18n = require "i18n"
local gamejolt = require "gamejolt"
local gamejoltuser = require "gamejoltuser"
local collections = nil
local filteredCollections = nil
local musicfiles = nil
local chartfiles = nil
local imagefiles = nil
local imageObjects = nil
local jacketMap = nil
local jacketLoadFailed = nil
local allMusicfilesCache = nil
local allChartfilesCache = nil
local allImagefilesCache = nil
local audioByArchiveCache = nil
local imageByArchiveCache = nil
local allChartDataCache = nil

local cachedChartData = nil
local chartMetaCache = {}
local verboseSfbLogs = false
local startupCollections = nil
local startupPreviewSources = nil
local startupAssetsConsumed = false
local playCollections = nil
local playCollectionsIndex = nil
local captureSelectionState
local refreshAfterSfbGeneration

local music = {
    data = {},
    demostart = {},
    demoend = {},
    volume = {}
}

local openURL = false
local difficultyOrder = {"easy", "normal", "hard", "extra", "custom"}
local difficultyIndexMap = {}
for i = 1, #difficultyOrder do
    difficultyIndexMap[difficultyOrder[i]] = i
end

local buildImageObject, parseChartMeta, preloadChartEntry

local difficultyColor = {
    easy = {0.1, 1, 0.1},
    normal = {0.5, 0.5, 1},
    hard = {1, 1, 0},
    extra = {1, 0.1, 0.1},
    custom = {0.5, 0.1, 0.5}
}
local difficultyLabelRatio = {
    easy = 0.525,
    normal = 0.6,
    hard = 0.7,
    extra = 0.8,
    custom = 0.9
}

-- 難易度表示のフォーマット関数
local function formatDifficultyLevel(levelValue)
    if not levelValue or levelValue == "" or levelValue == "--" then
        return "--"
    end

    local text = tostring(levelValue)
    local integerPart, fractionPart = text:match("^%s*([%+%-]?%d+)%.(%d+)%s*$")
    if integerPart and fractionPart then
        local firstFractionDigit = tonumber(fractionPart:sub(1, 1)) or 0
        if firstFractionDigit >= 5 then
            return integerPart .. "+"
        end
        return integerPart
    end

    local integerOnly = text:match("^%s*([%+%-]?%d+)%s*$")
    if integerOnly then
        return integerOnly
    end

    local num = tonumber(text)
    if not num then
        return text
    end

    local base = math.floor(num)
    if (num - base) >= 0.5 then
        return tostring(base) .. "+"
    end
    return tostring(base)
end

local function levelValueExists(levelInfo, diff)
    if type(levelInfo) ~= "table" then
        return false
    end
    local v = levelInfo[diff]
    return v ~= nil and v ~= ""
end

local genreListCache = {"All"}
local appliedGenre = nil
local difficultyZonesCache = nil
local difficultyZonesCacheWidth = 0
local difficultyZonesCacheHeight = 0

-- UTF-8 文字列をクリーンにする関数
local function cleanUTF8(str)
    if not str then return "" end
    local cleaned = {}
    local cleanedCount = 0
    local i = 1
    local byteLength = #str
    while i <= byteLength do
        local byte = str:byte(i)
        if byte < 128 then
            -- ASCII
            cleanedCount = cleanedCount + 1
            cleaned[cleanedCount] = str:sub(i, i)
            i = i + 1
        elseif byte >= 192 and byte <= 223 then
            -- 2-byte sequence
            if i + 1 <= byteLength then
                cleanedCount = cleanedCount + 1
                cleaned[cleanedCount] = str:sub(i, i + 1)
                i = i + 2
            else
                i = i + 1
            end
        elseif byte >= 224 and byte <= 239 then
            -- 3-byte sequence
            if i + 2 <= byteLength then
                cleanedCount = cleanedCount + 1
                cleaned[cleanedCount] = str:sub(i, i + 2)
                i = i + 3
            else
                i = i + 1
            end
        elseif byte >= 240 and byte <= 247 then
            -- 4-byte sequence
            if i + 3 <= byteLength then
                cleanedCount = cleanedCount + 1
                cleaned[cleanedCount] = str:sub(i, i + 3)
                i = i + 4
            else
                i = i + 1
            end
        else
            -- Invalid byte, skip
            i = i + 1
        end
    end
    return table.concat(cleaned)
end

local function normalizeGenres(rawGenre)
    local genres = {}
    local genreCount = 0
    local seen = {}

    local function addGenre(value)
        if type(value) ~= "string" then
            return
        end
        local cleaned = value:match("^%s*(.-)%s*$") or value
        if cleaned ~= "" and not seen[cleaned] then
            seen[cleaned] = true
            genreCount = genreCount + 1
            genres[genreCount] = cleaned
        end
    end

    if type(rawGenre) == "table" then
        for i = 1, #rawGenre do
            addGenre(rawGenre[i])
        end
    else
        addGenre(rawGenre)
    end

    if genreCount == 0 then
        genres[1] = "Unknown"
    end

    return genres
end

local function normalizeWatchusers(raw)
    local users = {}
    local seen = {}
    local count = 0

    local function addUser(value)
        if type(value) ~= "string" then
            return
        end
        local cleaned = value:match("^%s*(.-)%s*$") or value
        cleaned = cleanUTF8(cleaned)
        if cleaned ~= "" and not seen[cleaned] then
            seen[cleaned] = true
            count = count + 1
            users[count] = cleaned
        end
    end

    if type(raw) == "table" then
        for i = 1, #raw do
            addUser(raw[i])
        end
    else
        addUser(raw)
    end

    return users
end

local function normalizeWatchuserName(name)
    if type(name) ~= "string" then
        return ""
    end
    local normalized = cleanUTF8(name):match("^%s*(.-)%s*$") or ""
    return normalized
end

local function chartHasGenre(rawGenre, targetGenre)
    if targetGenre == "All" then
        return true
    end

    if type(rawGenre) == "table" then
        for i = 1, #rawGenre do
            if rawGenre[i] == targetGenre then
                return true
            end
        end
        return false
    end

    return rawGenre == targetGenre
end

local displayWidth, displayHeight = love.graphics.getDimensions()

local function refreshMusicselectFonts()
    local titleSize = math.max(20, math.floor(displayHeight * 0.04))
    local selectTitleSize = math.max(26, math.floor(displayHeight * 0.06))
    local artistSize = math.max(16, math.floor(displayHeight * 0.035))
    local selectArtistSize = math.max(20, math.floor(displayHeight * 0.045))
    local uiFontSize = math.max(18, math.floor(displayWidth * 0.05))

    titlefont = love.graphics.newFont("lib/data/fonts/NotoSansJP-Regular.ttf", titleSize)
    selecttitlefont = love.graphics.newFont("lib/data/fonts/NotoSansJP-Regular.ttf", selectTitleSize)
    artistfont = love.graphics.newFont("lib/data/fonts/NotoSansJP-ExtraLight.ttf", artistSize)
    selectartistfont = love.graphics.newFont("lib/data/fonts/NotoSansJP-ExtraLight.ttf", selectArtistSize)
    backbutton = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", uiFontSize)
    levelfont = love.graphics.newFont("lib/data/fonts/851H-kktt_004.ttf", uiFontSize)
end

local function updateDisplaySize()
    local w, h = love.graphics.getDimensions()
    if w ~= displayWidth or h ~= displayHeight then
        displayWidth, displayHeight = w, h
        refreshMusicselectFonts()
        return true
    end
    return false
end

musicselect.selectedIndex = 1
musicselect.cardBounds = {}
local selectedGenre = "All"
local cardTopIndex = 1

-- フェード
local fadeAlpha = 0
local fading = false
local fadeSpeed = 1.5

local titleScrollOffset = 0
local titleScrollWait = 0
local titleScrollSpeed = 40
local titleScrollGap = 50
local titleScrollEnabled = false
local titleScrollTextWidth = 0
local titleScrollAreaWidth = 0

local artistScrollOffset = 0
local artistScrollWait = 0
local artistScrollSpeed = 40
local artistScrollGap = 50
local artistScrollEnabled = false
local artistScrollTextWidth = 0
local artistScrollAreaWidth = 0

local listArtistScrollOffset = 0
local listArtistScrollSpeed = 30
local listArtistScrollGap = 40

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

local function getDifficultyIndex(diff)
    return difficultyIndexMap[diff] or 1
end

local function setSelectedDifficulty(diff)
    if difficultyIndexMap[diff] then
        musicselect.selectedDifficulty = diff
    else
        musicselect.selectedDifficulty = difficultyOrder[1]
    end
end

-- 指定インデックスに対して現在の selectedDifficulty が有効か検査し、無効なら
-- 最初に見つかる有効な難易度へ切替して selectedLevelValue を設定する。
local function ensureSelectedDifficultyValidForIndex(idx)
    idx = tonumber(idx) or musicselect.selectedIndex
    if not idx or idx <= 0 then return end
    local chartdata = chartreader()
    local levelInfo = (chartdata.level and chartdata.level[idx]) or {}
    local curVal = (levelInfo and levelInfo[musicselect.selectedDifficulty]) or nil
    if curVal and curVal ~= "" then
        musicselect.selectedLevelValue = curVal
        return
    end
    for _, diff in ipairs(difficultyOrder) do
        local v = levelInfo and levelInfo[diff]
        if v and v ~= "" then
            setSelectedDifficulty(diff)
            musicselect.selectedLevelValue = v
            log.debug("ensureSelectedDifficultyValidForIndex: switched to " .. tostring(diff) .. " for index " .. tostring(idx))
            return
        end
    end
    musicselect.selectedLevelValue = "--"
    log.debug("ensureSelectedDifficultyValidForIndex: no valid difficulty for index " .. tostring(idx))
end

local function getDifficultyZonePolygons()
    if difficultyZonesCache
        and difficultyZonesCacheWidth == displayWidth
        and difficultyZonesCacheHeight == displayHeight then
        return difficultyZonesCache
    end

    local levelTopY = displayHeight / 3 * 2
    local levelBottomY = levelTopY * 1.25
    local leftX = displayWidth / 2
    local rightX = displayWidth
    local zoneCount = #difficultyOrder
    local zoneWidth = (rightX - leftX) / zoneCount
    local skew = -displayWidth * 0.02 -- 左下に傾く

    local zones = {}
    for i, diff in ipairs(difficultyOrder) do
        local fromX = leftX + (i - 1) * zoneWidth
        local toX = leftX + i * zoneWidth

        if i == 1 then
            -- EASYオフセット
            zones[diff] = {
                fromX, levelTopY,
                toX, levelTopY,
                toX + skew, levelBottomY,
                fromX, levelBottomY
            }
        else
            zones[diff] = {
                fromX, levelTopY,
                toX, levelTopY,
                toX + skew, levelBottomY,
                fromX + skew, levelBottomY
            }
        end
    end

    difficultyZonesCache = zones
    difficultyZonesCacheWidth = displayWidth
    difficultyZonesCacheHeight = displayHeight
    return difficultyZonesCache
end

local function pointInConvexPolygon(px, py, points)
    local pointCount = #points / 2
    local sign = 0
    local epsilon = 0.0001

    for i = 1, pointCount do
        local nextI = (i % pointCount) + 1
        local x1 = points[(i - 1) * 2 + 1]
        local y1 = points[(i - 1) * 2 + 2]
        local x2 = points[(nextI - 1) * 2 + 1]
        local y2 = points[(nextI - 1) * 2 + 2]
        local cross = (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1)

        if math.abs(cross) > epsilon then
            local currentSign = (cross > 0) and 1 or -1
            if sign == 0 then
                sign = currentSign
            elseif sign ~= currentSign then
                return false
            end
        end
    end

    return true
end








local function buildAudioSource(entry, requestedVolume)
    requestedVolume = tonumber(requestedVolume) or 1.0

    local function clampSample(v)
        if v > 1.0 then
            return 1.0
        elseif v < -1.0 then
            return -1.0
        end
        return v
    end

    local function applyGain(sounddata, gain)
        if gain <= 1.0 then
            return
        end
        pcall(function()
            sounddata:mapSamples(function(s)
                return clampSample(s * gain)
            end)
        end)
    end

    ---@return love.Source|nil
    local function createSourceFromSoundData(sounddata)
        if not sounddata then
            return nil
        end

        applyGain(sounddata, requestedVolume)

        local ok, source = pcall(love.audio.newSource, sounddata, "static")
        if ok and source then
            if requestedVolume > 1.0 then
                source:setVolume(1.0)
            else
                source:setVolume(math.max(requestedVolume, 0.0))
            end
            return source
        end
        return nil
    end

    local cachedSoundData = audiocache.getPreloadedSoundData(collections, entry)
    if cachedSoundData then
        local sourceSoundData = nil
        if cachedSoundData ~= nil then
            sourceSoundData = cachedSoundData
        end
        if requestedVolume > 1.0 and cachedSoundData and type(cachedSoundData.clone) == "function" then
            local okClone, clonedSoundData = pcall(function()
                return cachedSoundData:clone()
            end)
            if okClone and clonedSoundData then
                sourceSoundData = clonedSoundData
            else
                sourceSoundData = nil
            end
        end

        local cachedSource = createSourceFromSoundData(sourceSoundData)
        if cachedSource then
            return cachedSource
        end
    end

    if type(entry) == "table" and type(entry.data) == "string" then
        local okFile, fileData = pcall(love.filesystem.newFileData, entry.data, entry.name or "audio")
        if okFile and fileData then
            local okSound, soundData = pcall(love.sound.newSoundData, fileData)
            if okSound and soundData then
                return createSourceFromSoundData(soundData)
            end
            log.warn("Warning: failed to create SoundData for " .. tostring(entry.name))
            return nil
        end
        log.warn("Warning: failed to create FileData for " .. tostring(entry.name))
        return nil
    end

    if type(entry) == "table" and type(entry.name) == "string" then
        return buildAudioSource(entry.name, requestedVolume)
    end

    if type(entry) == "string" then
        local ok, sounddata = pcall(love.sound.newSoundData, entry)
        if ok and sounddata then
            return createSourceFromSoundData(sounddata)
        end

        local ok2, source = pcall(love.audio.newSource, entry, "stream")
        if ok2 and source then
            source:setVolume(math.max(math.min(requestedVolume, 1.0), 0.0))
            return source
        end

        log.warn("Warning: failed to create Source for " .. tostring(entry))
        return nil
    end

    return nil
end

local function formatAudioCacheVolume(requestedVolume)
    return string.format("%.6f", tonumber(requestedVolume) or 1.0)
end

local function getAudioSourceCacheKey(entry, requestedVolume)
    local volumeKey = formatAudioCacheVolume(requestedVolume)
    if type(entry) == "table" then
        local archive = entry.archive or ""
        local name = entry.name or ""
        local dataSize = (type(entry.data) == "string") and #entry.data or 0
        if dataSize > 0 then
            return archive .. ":" .. name .. ":" .. tostring(dataSize) .. ":" .. volumeKey
        end
        return "pathtbl:" .. archive .. ":" .. name .. ":" .. volumeKey
    end
    if type(entry) == "string" then
        return "path:" .. entry .. ":" .. volumeKey
    end
    return nil
end

function musicselect.prebuildPreviewSources(preloadedCollections)
    return {}
end

---@param entry table
local function preloadChartEntry(entry)
    if type(entry) ~= "table" or type(entry.data) ~= "string" then
        return
    end
    if entry._parsedChartTable ~= nil then
        return
    end

    local chunk, err = load(entry.data, entry.name or "chart", "t")
    if not chunk then
        return
    end

    local ok, chart = pcall(chunk)
    if not ok or type(chart) ~= "table" then
        return
    end

    entry._parsedChartTable = chart
end

local function preloadStartupCollectionAssets(collections)
    if type(collections) ~= "table" then
        return
    end

    local chartEntries = type(collections.charts) == "table" and collections.charts or {}
    for _, entry in ipairs(chartEntries) do
        if type(entry) == "table" then
            preloadChartEntry(entry)
        end
    end

    local imageEntries = type(collections.images) == "table" and collections.images or {}
    for _, entry in ipairs(imageEntries) do
        if type(entry) == "table" then
            buildImageObject(entry)
        end
    end
end

function musicselect.setStartupAssets(preloadedCollections, preloadedPreviewSources)
    startupCollections = preloadedCollections
    startupPreviewSources = preloadedPreviewSources
    startupAssetsConsumed = false
    preloadStartupCollectionAssets(preloadedCollections)
end

local function normalizeDemoRange(source, startTime, endTime)
    local start = tonumber(startTime) or 0
    local finish = tonumber(endTime) or 0
    if start < 0 then
        start = 0
    end
    if finish <= 0 then
        local duration = source:getDuration("seconds")
        if type(duration) == "number" and duration > 0 then
            finish = duration
        else
            finish = math.huge
        end
    end
    if finish < start then
        local duration = source:getDuration("seconds")
        if type(duration) == "number" and duration > 0 then
            finish = duration
        else
            finish = start
        end
    end
    return start, finish
end

---@param entry table|string|nil
---@return love.Image|nil
buildImageObject = function(entry)
    if not entry then
        return nil
    end

    if type(entry) == "table" and entry._cachedJacketImage ~= nil then
        return entry._cachedJacketImage or nil
    end

    local img = nil

    if type(entry) == "table" and type(entry.data) == "string" then
        local ok, filedata = pcall(love.filesystem.newFileData, entry.data, entry.name or "image")
        if ok and filedata then
            local ok2, imgdata = pcall(love.image.newImageData, filedata)
            if ok2 and imgdata then
                local ok3, imgObj = pcall(love.graphics.newImage, imgdata)
                if ok3 and imgObj then
                    img = imgObj
                    log.debug("buildImageObject: loaded image from data name=" .. tostring(entry.name))
                else
                    log.warn("Warning: failed to create Image object for " .. tostring(entry.name))
                end
            else
                log.warn("Warning: failed to create ImageData for " .. tostring(entry.name))
            end
        else
            log.warn("Warning: failed to create FileData for " .. tostring(entry and entry.name))
        end
    elseif type(entry) == "table" and type(entry.name) == "string" then
        local imagePath = entry.name
        local fileContent = nil

        local function path_to_save_relative(p)
            if not (love and love.filesystem and love.filesystem.getSaveDirectory) then
                return nil
            end
            local ok, saveDir = pcall(love.filesystem.getSaveDirectory)
            if not ok or type(saveDir) ~= "string" then return nil end
            local normSave = saveDir:gsub("\\","/")
            local normPath = p:gsub("\\","/")
            if normPath:sub(1, #normSave) == normSave then
                local rel = normPath:sub(#normSave + 1)
                rel = rel:gsub("^[/\\]+", "")
                if rel == "" then rel = "." end
                return rel
            end
            return nil
        end

        local rel = path_to_save_relative(imagePath)
        if rel and love and love.filesystem and love.filesystem.read then
            local okRead, contents = pcall(love.filesystem.read, rel)
            if okRead and contents then fileContent = contents end
        end

        if not fileContent then
            -- 絶対パス（AppData など）の場合、io.open を使用してファイルを読み込む
            if imagePath:match("^[A-Za-z]:") or imagePath:match("^/") then
                local f = io.open(imagePath, "rb")
                if f then
                    fileContent = f:read("*a")
                    f:close()
                end
            end
        end

        if fileContent then
            local fileName = imagePath:match("([^/\\]+)$") or "image"
            local ok, filedata = pcall(love.filesystem.newFileData, fileContent, fileName)
            if ok and filedata then
                local ok2, imgdata = pcall(love.image.newImageData, filedata)
                if ok2 and imgdata then
                    local ok3, imgObj = pcall(love.graphics.newImage, imgdata)
                    if ok3 and imgObj then
                        img = imgObj
                        log.debug("buildImageObject: loaded image from path " .. tostring(imagePath))
                    else
                        log.warn("Warning: failed to create Image object from path " .. tostring(imagePath))
                    end
                else
                    log.warn("Warning: failed to create ImageData from path " .. tostring(imagePath))
                end
            else
                log.warn("Warning: failed to create FileData from path " .. tostring(imagePath))
            end
        else
            local ok, imgObj = pcall(love.graphics.newImage, imagePath)
            if ok and imgObj then
                img = imgObj
            else
                log.warn("Warning: failed to load Image by name " .. tostring(imagePath))
            end
        end
    elseif type(entry) == "string" then
        -- 絶対パス（AppData など）の場合、io.open を使用してファイルを読み込む
        local fileContent = nil

        local function path_to_save_relative(p)
            if not (love and love.filesystem and love.filesystem.getSaveDirectory) then
                return nil
            end
            local ok, saveDir = pcall(love.filesystem.getSaveDirectory)
            if not ok or type(saveDir) ~= "string" then return nil end
            local normSave = saveDir:gsub("\\","/")
            local normPath = p:gsub("\\","/")
            if normPath:sub(1, #normSave) == normSave then
                local rel = normPath:sub(#normSave + 1)
                rel = rel:gsub("^[/\\]+", "")
                if rel == "" then rel = "." end
                return rel
            end
            return nil
        end

        local rel = path_to_save_relative(entry)
        if rel and love and love.filesystem and love.filesystem.read then
            local okRead, contents = pcall(love.filesystem.read, rel)
            if okRead and contents then fileContent = contents end
        end

        if not fileContent then
            if entry:match("^[A-Za-z]:") or entry:match("^/") then
                local f = io.open(entry, "rb")
                if f then
                    fileContent = f:read("*a")
                    f:close()
                end
            end
        end

        if fileContent then
            local fileName = entry:match("([^/\\]+)$") or "image"
            local ok, filedata = pcall(love.filesystem.newFileData, fileContent, fileName)
            if ok and filedata then
                local ok2, imgdata = pcall(love.image.newImageData, filedata)
                if ok2 and imgdata then
                    local ok3, imgObj = pcall(love.graphics.newImage, imgdata)
                    if ok3 and imgObj then
                        img = imgObj
                        log.debug("buildImageObject: loaded image from entry string " .. tostring(entry))
                    else
                        log.warn("Warning: failed to create Image object from path " .. tostring(entry))
                    end
                else
                    log.warn("Warning: failed to create ImageData from path " .. tostring(entry))
                end
            else
                log.warn("Warning: failed to create FileData from path " .. tostring(entry))
            end
        else
            local ok, imgObj = pcall(love.graphics.newImage, entry)
            if ok and imgObj then
                img = imgObj
            else
                log.warn("Warning: failed to load Image by path " .. tostring(entry))
            end
        end
    end

    if type(entry) == "table" then
        entry._cachedJacketImage = img or false
    end

    return img
end

local function stopPreviewAudio()
    if not music or not music.data then
        return
    end
    for _, source in pairs(music.data) do
        if source and source.stop then
            source:stop()
        end
    end
end

local function drawCardSingleLineText(font, text, x, y, areaW)
    if not font or areaW <= 0 then
        return
    end

    text = text or ""
    love.graphics.setFont(font)

    local textWidth = font:getWidth(text)
    if textWidth > areaW then
        local sx, sy, sw, sh = love.graphics.getScissor()
        love.graphics.setScissor(x, y, areaW, font:getHeight())
        local drawX = x - (listArtistScrollOffset % (textWidth + listArtistScrollGap))
        love.graphics.print(text, drawX, y)
        love.graphics.print(text, drawX + textWidth + listArtistScrollGap, y)
        if sx ~= nil then
            love.graphics.setScissor(sx, sy, sw, sh)
        else
            love.graphics.setScissor()
        end
    else
        love.graphics.print(text, x, y)
    end
end

local function rebuildPreviewAudio()
    stopPreviewAudio()

    music = {
        data = {},
        entries = {},
        demostart = {},
        demoend = {},
        volume = {}
    }
    musicselect._currentIndex = nil

    local chartdata = chartreader()
    local count = chartfiles and #chartfiles or 0
    for i = 1, count do
        local audioEntry = musicfiles and musicfiles[i]
        local vol = tonumber(chartdata.volume and chartdata.volume[i]) or 1.0
        vol = math.max(vol, 0.0)

        music.entries[i] = audioEntry
        music.demostart[i] = tonumber(chartdata.demostart and chartdata.demostart[i]) or 0
        music.demoend[i] = tonumber(chartdata.demoend and chartdata.demoend[i]) or 0
        music.volume[i] = vol

        if audioEntry then
            local sourceKey = getAudioSourceCacheKey(audioEntry, vol)
            local source = sourceKey and startupPreviewSources and startupPreviewSources[sourceKey] or nil
            if not source then
                source = buildAudioSource(audioEntry, vol)
                if source and sourceKey then
                    startupPreviewSources = startupPreviewSources or {}
                    startupPreviewSources[sourceKey] = source
                end
            end
            if source then
                source:stop()
                local startTime, endTime = normalizeDemoRange(
                    source,
                    music.demostart[i],
                    music.demoend[i]
                )
                music.demostart[i] = startTime
                music.demoend[i] = endTime
                music.data[i] = source
            end
    end
end
end

local function getPreviewSource(index)
    if not music or not music.data or not index or index <= 0 then
        return nil
    end

    local existing = music.data[index]
    if existing then
        return existing
    end

    local entry = music.entries and music.entries[index]
    if not entry then
        return nil
    end

    local vol = music.volume and music.volume[index] or 1.0
    local sourceKey = getAudioSourceCacheKey(entry, vol)
    local source = nil
    if sourceKey and startupPreviewSources then
        source = startupPreviewSources[sourceKey]
    end
    if not source then
        source = buildAudioSource(entry, vol)
        if source and sourceKey then
            startupPreviewSources = startupPreviewSources or {}
            startupPreviewSources[sourceKey] = source
        end
    end
    if not source then
        return nil
    end

    source:stop()
    local startTime, endTime = normalizeDemoRange(
        source,
        music.demostart and music.demostart[index],
        music.demoend and music.demoend[index]
    )
    music.demostart[index] = startTime
    music.demoend[index] = endTime
    music.data[index] = source
    return source
end

local function getJacketImage(index)
    if not index or index <= 0 then
        return nil
    end
    if not jacketMap then
        return nil
    end
    local cached = jacketMap[index]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    if jacketLoadFailed and jacketLoadFailed[index] then
        return nil
    end

    local entry = imagefiles and imagefiles[index]
    local img = buildImageObject(entry)
    if img then
        jacketMap[index] = img
        if imageObjects then
            imageObjects[index] = img
        end
        return img
    end

    jacketMap[index] = false
    if jacketLoadFailed then
        jacketLoadFailed[index] = true
    end
    return nil
end

local function getSelectableCount()
    local chartdata = chartreader()
    local chartCount = 0
    if chartdata and chartdata.name then
        chartCount = #chartdata.name
    end

    if chartCount > 0 then
        return chartCount
    end

    local imageCount = (imagefiles and #imagefiles) or 0
    return imageCount
end

local function rebuildGenreList(chartdata)
    local list = {"All"}
    local discovered = {}
    local discoveredCount = 0
    local genreSet = { All = true }
    local genres = chartdata and chartdata.genre
    if genres then
        for i = 1, #genres do
            local entryGenres = normalizeGenres(genres[i])
            for j = 1, #entryGenres do
                local g = entryGenres[j]
                if g ~= "" and g ~= "All" and not genreSet[g] then
                    genreSet[g] = true
                    discoveredCount = discoveredCount + 1
                    discovered[discoveredCount] = g
                end
            end
        end
    end

    table.sort(discovered)
    for i = 1, discoveredCount do
        list[#list + 1] = discovered[i]
    end

    genreListCache = list
    if not genreSet[selectedGenre] then
        selectedGenre = "All"
    end
end

local function uniqueEntries(list)
    local seen = {}
    local out = {}
    local outCount = 0
    for _, entry in ipairs(list or {}) do
        local key
        if type(entry) == "table" then
            local name = entry.name or ""
            local archive = entry.archive or ""
            key = archive .. ":" .. name
        else
            key = tostring(entry)
        end
        if not seen[key] then
            seen[key] = true
            outCount = outCount + 1
            out[outCount] = entry
        end
    end
    return out
end

local function applySelectedGenreFilter()
    if not allChartfilesCache then
        musicfiles = nil
        chartfiles = nil
        imagefiles = nil
        imageObjects = nil
        jacketMap = nil
        jacketLoadFailed = nil
        filteredCollections = nil
        playCollections = nil
        rebuildPreviewAudio()
        musicselect.cardBounds = {}
        musicselect.selectedIndex = 0
        cardTopIndex = 1
        return
    end

    local filteredChartfiles = {}
    local filteredCount = 0
    for i, chartEntry in ipairs(allChartfilesCache) do
        local genres = allChartDataCache and allChartDataCache.genre and allChartDataCache.genre[i]
        local watchuser = normalizeWatchusers(allChartDataCache and allChartDataCache.watchuser and allChartDataCache.watchuser[i] or {})
        local restrictedByWatchuser = false

        -- watchuser制限がある楽曲は常に表示から除外
        if #watchuser > 0 then
            restrictedByWatchuser = true
        end

        -- 解析された難易度ブロックがあれば表示対象にする
        local hasAnyDifficulty = true

        if chartHasGenre(genres, selectedGenre) and not restrictedByWatchuser and hasAnyDifficulty then
            filteredCount = filteredCount + 1
            filteredChartfiles[filteredCount] = chartEntry
        end
    end

    chartfiles = filteredChartfiles
    cachedChartData = nil

    musicfiles = {}
    imagefiles = {}
    imageObjects = {}
    jacketMap = {}
    jacketLoadFailed = {}

    for i, chartEntry in ipairs(chartfiles) do
        local archive = (type(chartEntry) == "table") and chartEntry.archive or nil
        local audioEntry = archive and audioByArchiveCache and audioByArchiveCache[archive] or false
        local imageEntry = archive and imageByArchiveCache and imageByArchiveCache[archive] or false

        musicfiles[i] = audioEntry
        imagefiles[i] = imageEntry
    end

    filteredCollections = {
        audio = musicfiles,
        charts = chartfiles,
        images = imagefiles,
        _runtimeAudioCache = collections and collections._runtimeAudioCache or nil
    }
    playCollections = nil

    log.debug("setCollections: After filtering - chartfiles count = " .. (#chartfiles or 0) .. " (selectedGenre=" .. tostring(selectedGenre) .. ")")

    rebuildPreviewAudio()

    musicselect.cardBounds = {}
    if getSelectableCount() > 0 then
        musicselect.selectedIndex = 1
    else
        musicselect.selectedIndex = 0
    end
    cardTopIndex = 1
    appliedGenre = selectedGenre
end

local function getCardLayout()
    local cardX = displayWidth / 10
    local cardStartY = displayHeight / 10 * 1.5
    local cardW = displayWidth / 5 * 2
    local cardH = displayHeight / 10
    local cardStepY = displayHeight / 10 * 1.5
    local cardBottomY = displayHeight / 10 * 9
    local visibleCount = 1
    local availableHeight = cardBottomY - cardStartY

    if cardStepY > 0 and availableHeight > 0 then
        visibleCount = math.floor((availableHeight - cardH) / cardStepY) + 1
    end
    if visibleCount < 1 then
        visibleCount = 1
    end

    return {
        x = cardX,
        y = cardStartY,
        w = cardW,
        h = cardH,
        stepY = cardStepY,
        visibleCount = visibleCount
    }
end

local function syncCardTopIndex(itemCount)
    updateDisplaySize()

    local count = itemCount or getSelectableCount()
    if count <= 0 then
        cardTopIndex = 1
        return
    end

    local layout = getCardLayout()
    local maxTop = math.max(1, count - layout.visibleCount + 1)
    cardTopIndex = clamp(cardTopIndex, 1, maxTop)

    local selected = clamp(musicselect.selectedIndex or 1, 1, count)
    if selected < cardTopIndex then
        cardTopIndex = selected
    elseif selected > cardTopIndex + layout.visibleCount - 1 then
        cardTopIndex = selected - layout.visibleCount + 1
    end

    cardTopIndex = clamp(cardTopIndex, 1, maxTop)
end

function musicselect.getSelectedIndex()
    return musicselect.selectedIndex
end

function musicselect.getSelectableCount()
    return getSelectableCount()
end



function musicselect.load()

    musicselect.onlineMode = false

    if not urlimg then
        urlimg=love.graphics.newImage("img/Link.png")
    end

    log.info("Musicselect - musicselect.load() started")
    selectedGenre = "All"
    cachedChartData = nil
    chartMetaCache = {}
    sfbloadercatcher()
    if appliedGenre ~= selectedGenre then
        applySelectedGenreFilter()
    end
    
    log.info("Reading music chart data...")
    local loadedChartData = chartreader()
    if collections then
        applySelectedGenreFilter()
    end
    log.info("Total music files loaded: " .. (#(loadedChartData.name or {}) or 0))

    totitle = false
    selectmode = nil

    if getSelectableCount() > 0 then
        musicselect.selectedIndex = 1
    else
        musicselect.selectedIndex = 0
    end
    cardTopIndex = 1

    updateDisplaySize()
    refreshMusicselectFonts()

    musicselect.endprocess = false
    musicselect.selectmode = 0
    musicselect.selectedDifficulty = "easy"
    musicselect.selectedLevelValue = ""

    fadeAlpha = 0
    fading = false

end













function musicselect.getCollections()
    return filteredCollections or collections
end

local function buildSelectedCollectionsForPlay(selectedIndex)
    selectedIndex = tonumber(selectedIndex or musicselect.selectedIndex) or 0
    if selectedIndex <= 0 then
        playCollections = nil
        return nil
    end

    local activeCollections = filteredCollections or collections or {}
    local selectedAudio = musicfiles and musicfiles[selectedIndex] or nil
    local selectedChart = chartfiles and chartfiles[selectedIndex] or nil
    local selectedImage = imagefiles and imagefiles[selectedIndex] or nil

    if selectedAudio then
        local cacheOwner = collections or activeCollections
        local record = audiocache.preloadEntry(cacheOwner, selectedAudio)
        if record and record.soundData and type(selectedAudio) == "table" then
            selectedAudio._cachedBgmSoundData = record.soundData
        end
    end

    if selectedChart then
        preloadChartEntry(selectedChart)
    end

    local cachedJacket = getJacketImage(selectedIndex)
    if type(selectedImage) == "table" then
        selectedImage._cachedJacketImage = cachedJacket or false
    end

    playCollections = {
        audio = selectedAudio and {selectedAudio} or {},
        charts = selectedChart and {selectedChart} or {},
        images = selectedImage and {selectedImage} or {},
        _runtimeAudioCache = activeCollections._runtimeAudioCache or (collections and collections._runtimeAudioCache) or nil
    }

    return playCollections
end

function musicselect.getPlayCollections()
    local currentIndex = tonumber(musicselect.selectedIndex) or 0
    if playCollections and playCollectionsIndex == currentIndex then
        return playCollections
    end

    local selectedPlayCollections = buildSelectedCollectionsForPlay(currentIndex)
    playCollections = selectedPlayCollections
    playCollectionsIndex = currentIndex
    return playCollections
end

function musicselect.reloadCollectionsForPlay()
    local currentIndex = tonumber(musicselect.selectedIndex) or 0
    local selectedPlayCollections = buildSelectedCollectionsForPlay(currentIndex)
    playCollections = selectedPlayCollections
    playCollectionsIndex = currentIndex
    if not playCollections then
        log.warn("[Preparing to play] Could not secure the selected song data.")
        return nil
    end

    local selectedAudioCount = type(selectedPlayCollections) == "table" and type(selectedPlayCollections.audio) == "table" and #(selectedPlayCollections.audio) or 0
    local selectedChartCount = type(selectedPlayCollections) == "table" and type(selectedPlayCollections.charts) == "table" and #(selectedPlayCollections.charts) or 0
    local selectedImageCount = type(selectedPlayCollections) == "table" and type(selectedPlayCollections.images) == "table" and #(selectedPlayCollections.images) or 0
    local playAudioCount = type(playCollections) == "table" and type(playCollections.audio) == "table" and #(playCollections.audio) or 0
    local playChartCount = type(playCollections) == "table" and type(playCollections.charts) == "table" and #(playCollections.charts) or 0
    local playImageCount = type(playCollections) == table and type(playCollections.images) == "table" and #(playCollections.images) or 0

    log.info(string.format(
        "[play準備] 選択曲のみをメモリから引き渡します: audio=%d charts=%d images=%d",
        selectedAudioCount,
        selectedChartCount,
        selectedImageCount,
        playAudioCount,
        playChartCount,
        playImageCount
    ))

    return playCollections
end

function musicselect.setCollections(c)
    local previousCollections = collections
    if c and previousCollections == c
        and allChartfilesCache
        and allChartDataCache
        and filteredCollections
    then
        return
    end
    collections = c
    filteredCollections = nil
    cachedChartData = nil
    playCollections = nil
    playCollectionsIndex = nil
    if previousCollections ~= collections then
        chartMetaCache = {}
    end

    log.debug("setCollections: Input collections = " .. tostring(c))
    if c then
        log.debug("  audio count = " .. (#(c.audio or {}) or 0))
        log.debug("  charts count = " .. (#(c.charts or {}) or 0))
        log.debug("  images count = " .. (#(c.images or {}) or 0))
    end

    if collections then
        allMusicfilesCache = uniqueEntries(collections.audio)
        allChartfilesCache = uniqueEntries(collections.charts)
        allImagefilesCache = uniqueEntries(collections.images)
        
    log.debug("setCollections: After uniqueEntries:")
        log.debug("  allMusicfiles count = " .. (#allMusicfilesCache or 0))
        log.debug("  allChartfiles count = " .. (#allChartfilesCache or 0))
        log.debug("  allImagefiles count = " .. (#allImagefilesCache or 0))

        audioByArchiveCache = {}
        for _, entry in ipairs(allMusicfilesCache) do
            if type(entry) == "table" and entry.archive and not audioByArchiveCache[entry.archive] then
                audioByArchiveCache[entry.archive] = entry
            end
        end

        imageByArchiveCache = {}
        for _, entry in ipairs(allImagefilesCache) do
            if type(entry) == "table" and entry.archive and not imageByArchiveCache[entry.archive] then
                imageByArchiveCache[entry.archive] = entry
            end
        end

        chartfiles = allChartfilesCache
        cachedChartData = nil
        log.debug("setCollections: Before chartreader() - chartfiles count = " .. (#chartfiles or 0))
        allChartDataCache = chartreader()
        log.debug("setCollections: After chartreader() - allChartData has " .. (#(allChartDataCache.name or {}) or 0) .. " entries")
        rebuildGenreList(allChartDataCache)
        applySelectedGenreFilter()
    else
        allMusicfilesCache = nil
        allChartfilesCache = nil
        allImagefilesCache = nil
        audioByArchiveCache = nil
        imageByArchiveCache = nil
        allChartDataCache = nil
        musicfiles = nil
        chartfiles = nil
        imagefiles = nil
        imageObjects = nil
        jacketMap = nil
        jacketLoadFailed = nil
        filteredCollections = nil
        playCollections = nil
        genreListCache = {"All"}
        rebuildPreviewAudio()

        musicselect.cardBounds = {}
        musicselect.selectedIndex = 0
        cardTopIndex = 1
    end
end

captureSelectionState = function()
    local state = {
        index = musicselect.selectedIndex or 1,
        difficulty = musicselect.selectedDifficulty
    }

    local selectedIndex = state.index
    local selectedChart = chartfiles and chartfiles[selectedIndex]
    if type(selectedChart) == "table" then
        state.archive = selectedChart.archive
        state.chartName = selectedChart.name
    elseif type(selectedChart) == "string" then
        state.chartName = selectedChart
    end

    local data = chartreader()
    if data and data.name then
        state.title = data.name[selectedIndex]
    end

    return state
end

local function restoreSelectionState(state)
    local count = getSelectableCount()
    if count <= 0 then
        musicselect.selectedIndex = 0
        cardTopIndex = 1
        return
    end

    local restoredIndex = nil
    if state and state.archive and chartfiles then
        for i, entry in ipairs(chartfiles) do
            if type(entry) == "table" and entry.archive == state.archive then
                restoredIndex = i
                break
            end
        end
    end

    if not restoredIndex and state and state.chartName and chartfiles then
        for i, entry in ipairs(chartfiles) do
            if (type(entry) == "table" and entry.name == state.chartName) or entry == state.chartName then
                restoredIndex = i
                break
            end
        end
    end

    if not restoredIndex and state and state.title then
        local data = chartreader()
        if data and data.name then
            for i = 1, #data.name do
                if data.name[i] == state.title then
                    restoredIndex = i
                    break
                end
            end
        end
    end

    if not restoredIndex then
        local fallback = (state and state.index) or 1
        restoredIndex = clamp(fallback, 1, count)
    end

    musicselect.selectedIndex = clamp(restoredIndex, 1, count)
    syncCardTopIndex(count)

    if state and state.difficulty then
        setSelectedDifficulty(state.difficulty)
    end
end

local function readLineFromString(data, pos)
    if not data or pos > #data then
        return nil, pos
    end

    local startPos, endPos = data:find("\n", pos, true)
    if startPos then
        local line = data:sub(pos, startPos - 1)
        if line:sub(-1) == "\r" then
            line = line:sub(1, -2)
        end
        return line, endPos + 1
    end

    local line = data:sub(pos)
    if line:sub(-1) == "\r" then
        line = line:sub(1, -2)
    end
    return line, #data + 1
end

local function loadSingleArchive(archiveName)
    local rawData = love.filesystem.read(archiveName)
    local data = nil
    if type(rawData) == "string" then
        data = rawData
    elseif rawData and rawData.getString then
        data = rawData:getString()
    end

    if type(data) ~= "string" then
        return nil, "read_failed"
    end

    local pos = 1
    local magic
    magic, pos = readLineFromString(data, pos)
    local _versistory
    _versistory, pos = readLineFromString(data, pos)
    local countLine
    countLine, pos = readLineFromString(data, pos)
    local fileCount = tonumber(countLine)

    if magic ~= "SFB1" or not fileCount then
        return nil, "invalid_sfb_header"
    end

    local index = {}
    local indexCount = 0
    for _ = 1, fileCount do
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

    local parsed = {
        audio = {},
        images = {},
        charts = {}
    }

    for _, info in ipairs(index) do
        local startPos = (info.offset or -1) + 1
        local endPos = (info.offset or 0) + (info.size or 0)
        if startPos >= 1 and endPos <= #data then
            local entry = {
                name = info.name,
                data = data:sub(startPos, endPos),
                archive = archiveName
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
                parsed.audio[#parsed.audio + 1] = entry
            elseif ext == "png" or ext == "jpg" or ext == "jpeg" or lowerName:find("jacket", 1, true) then
                parsed.images[#parsed.images + 1] = entry
            elseif ext == "bin" or ext == "lua" then
                parsed.charts[#parsed.charts + 1] = entry
            end
        end
    end

    return parsed
end

local function replaceArchiveEntries(baseList, archiveName, replacementEntries)
    local merged = {}
    local mergedCount = 0
    for _, entry in ipairs(baseList or {}) do
        if type(entry) ~= "table" or entry.archive ~= archiveName then
            mergedCount = mergedCount + 1
            merged[mergedCount] = entry
        end
    end

    for _, entry in ipairs(replacementEntries or {}) do
        mergedCount = mergedCount + 1
        merged[mergedCount] = entry
    end

    return merged
end

local function clearPreviewSourceCacheForArchive(archiveName)
    if not startupPreviewSources or type(archiveName) ~= "string" or archiveName == "" then
        return
    end

    local prefix = archiveName .. ":"
    for key in pairs(startupPreviewSources) do
        if type(key) == "string" and key:sub(1, #prefix) == prefix then
            startupPreviewSources[key] = nil
        end
    end
end

local function reloadGeneratedArchive(archiveName)
    if type(archiveName) ~= "string" or archiveName == "" then
        return false
    end

    local loaded, err = loadSingleArchive(archiveName)
    if not loaded then
        log.warn("[Reload Music] Failed to reload generated log: " .. tostring(archiveName) .. " (" .. tostring(err) .. ")")
        return false
    end

    collections = collections or {audio = {}, charts = {}, images = {}}
    collections.audio = replaceArchiveEntries(collections.audio, archiveName, loaded.audio)
    collections.charts = replaceArchiveEntries(collections.charts, archiveName, loaded.charts)
    collections.images = replaceArchiveEntries(collections.images, archiveName, loaded.images)
    clearPreviewSourceCacheForArchive(archiveName)

    return true
end

local function reloadCollectionsFromSfb()
    local loadedCollections = nil
    local ok, err = pcall(function()
        local sfbloader = require("sfbloader")
        loadedCollections = sfbloader.load()
    end)
    if not ok then
        log.warn("[Reload Music] Failed to reload music.: " .. tostring(err))
        return nil
    end
    return loadedCollections
end

refreshAfterSfbGeneration = function(selectionState, opts)
    opts = opts or {}
    local didReload = false

    if opts.collections then
        collections = opts.collections
        if opts.clearPreviewCache then
            startupPreviewSources = {}
        end
        didReload = true
    elseif opts.generatedArchives then
        for _, archiveName in ipairs(opts.generatedArchives) do
            if reloadGeneratedArchive(archiveName) then
                didReload = true
            end
        end
    end

    if didReload then
        musicselect.setCollections(collections)
        restoreSelectionState(selectionState)
        if play and play.setCollections and musicselect.getCollections then
            play.setCollections(musicselect.getCollections())
        end
        log.info("[Reload Song] The song selection position has been restored after reloading.")
    else
        log.warn("[Reload Song] Screen refresh skipped because no songs to reload were found.")
    end
end

function sfbloadercatcher()
    if not collections then
        if startupCollections and not startupAssetsConsumed then
            collections = startupCollections
            startupAssetsConsumed = true
        elseif createsfb and type(createsfb.load) == "function" then
            local ok, loadedCollections = pcall(createsfb.load, createsfb, {forceRebuildAll = false})
            if ok and type(loadedCollections) == "table" then
                collections = loadedCollections
            else
                log.warn("sfbloadercatcher: direct song load failed, using empty collections.")
                collections = {audio = {}, charts = {}, images = {}}
            end
        else
            log.warn("sfbloadercatcher: startup collections are not ready. Using empty collections.")
            collections = {audio = {}, charts = {}, images = {}}
        end
    end

    musicselect.setCollections(collections)

    if verboseSfbLogs then
        log.debug(string.format("[SFB] filtered audio=%d, charts=%d, images=%d",
            (musicfiles and #musicfiles) or 0,
            (chartfiles and #chartfiles) or 0,
            (imagefiles and #imagefiles) or 0))
    end
end






function musicselect.update(dt)
    updateDisplaySize()

    if totitle then
        musicselect.endsaccess = true
    end

    if fading then
        fadeAlpha = fadeAlpha + fadeSpeed * dt
        if fadeAlpha >= 1 then
            fadeAlpha = 1
            musicselect.endprocess = true
        end
    end
    local index = musicselect.selectedIndex
    if not index or index <= 0 then
        return
    end
    if not music or not music.data then
        return
    end

    local source = getPreviewSource(index)
    if not source then
        return
    end

    if musicselect._currentIndex ~= index then
        if musicselect._currentIndex and music.data[musicselect._currentIndex] then
            music.data[musicselect._currentIndex]:stop()
        end
        musicselect._currentIndex = index
        local startTime = music.demostart[index] or 0
        source:stop()
        source:seek(startTime)
        local volume = clamp01(music.volume[index] or 1.0)
        source:setVolume(volume)
        source:play()
    elseif not source:isPlaying() then
        local startTime = music.demostart[index] or 0
        source:seek(startTime)
        local volume = clamp01(music.volume[index] or 1.0)
        source:setVolume(volume)
        source:play()
    end

    local endTime = music.demoend[index]
    if endTime and endTime > 0 then
        local currentTime = source:tell()
        if currentTime >= endTime then
            local over = currentTime - endTime
            local baseVolume = music.volume[index] or 1.0
            local effectiveVolume = clamp01(baseVolume)

            if over <= 0.5 then
                local fade = 1.0 - (over / 0.5)
                source:setVolume(effectiveVolume * fade)
            else
                local startTime = music.demostart[index] or 0
                source:seek(startTime)
                source:setVolume(effectiveVolume)
                source:play()
            end
        end
    end

    -- レベル選択用データ更新: 実際のレベル値を反映する（存在しない場合は "--" を表示）
    local chartdata = chartreader()
    do
        local idx = index
        local levelInfo = (chartdata.level and chartdata.level[idx]) or {}
        local v = levelInfo and levelInfo[musicselect.selectedDifficulty]
        if v and v ~= "" then
            musicselect.selectedLevelValue = v
        else
            musicselect.selectedLevelValue = "--"
        end
    end

    -- タイトル名スクロール制御
    local title = (chartdata.name and chartdata.name[index]) or ""
    titleScrollTextWidth = selecttitlefont and selecttitlefont:getWidth(title) or 0
    local titleX = displayWidth/40*21
    titleScrollAreaWidth = displayWidth/2 - titleX - 10

    if titleScrollTextWidth > titleScrollAreaWidth and titleScrollAreaWidth > 0 then
        titleScrollEnabled = true
        if titleScrollWait > 0 then
            titleScrollWait = titleScrollWait - dt
        else
            titleScrollOffset = titleScrollOffset + titleScrollSpeed * dt
            if titleScrollOffset > titleScrollTextWidth + titleScrollGap then
                titleScrollOffset = 0
                titleScrollWait = 1.0
            end
        end
    else
        titleScrollEnabled = false
        titleScrollOffset = 0
        titleScrollWait = 0
    end

    -- アーティスト名スクロール制御
    local artist = (chartdata.artist and chartdata.artist[index]) or ""
    artistScrollTextWidth = selectartistfont and selectartistfont:getWidth(artist) or 0
    local artistX = displayWidth/40*21
    artistScrollAreaWidth = displayWidth - artistX - 20

    if artistScrollTextWidth > artistScrollAreaWidth then
        artistScrollEnabled = true
        if artistScrollWait > 0 then
            artistScrollWait = artistScrollWait - dt
        else
            artistScrollOffset = artistScrollOffset + artistScrollSpeed * dt
            if artistScrollOffset > artistScrollTextWidth + artistScrollGap then
                artistScrollOffset = 0
                artistScrollWait = 1.0
            end
        end
    else
        artistScrollEnabled = false
        artistScrollOffset = 0
        artistScrollWait = 0
    end

    -- リスト内のアーティスト名スクロールオフセット
    listArtistScrollOffset = listArtistScrollOffset + listArtistScrollSpeed * dt
    if listArtistScrollOffset > 2000 then
        listArtistScrollOffset = 0
    end



    -- URLを開く
    if openURL == true then
        local url = (chartdata.url and chartdata.url[index]) or ""
        if url ~= "" then
            love.system.openURL(url)
            log.info("opened the URL" .. url)
            openURL = false
        else
            log.warn("URL is invalid: " .. tostring(chartdata.url[musicselect.selectedIndex]))
            openURL = false
        end
    end


end











function musicselect.mousepressed(x, y, button)
    if button ~= 1 then return end
    if fading then return end
    if not musicselect.cardBounds then return end

    updateDisplaySize()

    if urlimg then
        local iconScale = 0.1
        local btnW = urlimg:getWidth() * iconScale
        local btnH = urlimg:getHeight() * iconScale
        local btnX = displayWidth - btnW - 10
        local btnY = displayHeight / 20

        local hitMargin = 8
        if x >= btnX - hitMargin and x <= btnX + btnW + hitMargin
            and y >= btnY - hitMargin and y <= btnY + btnH + hitMargin then
            openURL = true
            return
        end
    end

    if not musicselect.onlineMode then
        local backX = displayWidth / 20
        local backY = displayHeight / 10 * 9
        if x >= 0 and x <= backX and y >= backY and y <= displayHeight then
            musicselect.selectmode = 1
            fadeAlpha = 0
            fading = true
            return
        end
    end

    for _, rect in ipairs(musicselect.cardBounds) do
        if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
            log.debug("mousepressed: clicked rect index=" .. tostring(rect.index) .. ", selLevelValue=" .. tostring(musicselect.selectedLevelValue) .. ", selDifficulty=" .. tostring(musicselect.selectedDifficulty))
            musicselect.selectedIndex = rect.index
            syncCardTopIndex(getSelectableCount())

            -- クリックした楽曲に対して、現在の選択難易度が存在しない場合は
            -- 強制的に最初に見つかる有効な難易度へ切替える（確実に即時反映させる）
            do
                local chartdata = chartreader()
                local levelInfo = (chartdata.level and chartdata.level[musicselect.selectedIndex]) or {}
                -- 詳細ログ: index と levelInfo の内容を出力
                local infoParts = {}
                for _, d in ipairs(difficultyOrder) do
                    local vv = levelInfo and levelInfo[d] or nil
                    infoParts[#infoParts+1] = d .. '=' .. tostring(vv)
                end
                log.debug("mousepressed: levelInfo for index=" .. tostring(musicselect.selectedIndex) .. " -> " .. table.concat(infoParts, ", "))

                -- 優先方針: まず現在の selectedDifficulty が当該曲で有効か確認。無効なら最初に見つかる有効な難易度へ切替。
                local curVal = (levelInfo and levelInfo[musicselect.selectedDifficulty]) or nil
                if not (curVal and curVal ~= "") then
                    for _, diff in ipairs(difficultyOrder) do
                        local v = levelInfo and levelInfo[diff]
                        if v and v ~= "" then
                            local before = musicselect.selectedDifficulty
                            setSelectedDifficulty(diff)
                            musicselect.selectedLevelValue = v
                            log.debug("mousepressed: forced auto-switch difficulty from " .. tostring(before) .. " to " .. tostring(diff) .. " for index " .. tostring(musicselect.selectedIndex))
                            break
                        end
                    end
                else
                    -- 現在の選択難易度が有効なら表示を実際の値で更新
                    musicselect.selectedLevelValue = curVal
                    log.debug("mousepressed: kept selected difficulty " .. tostring(musicselect.selectedDifficulty) .. " with value " .. tostring(curVal) .. " for index " .. tostring(musicselect.selectedIndex))
                end

                -- 有効な難易度が見つからなかった場合は -- を表示する
                if not musicselect.selectedLevelValue or musicselect.selectedLevelValue == "" then
                    musicselect.selectedLevelValue = "--"
                    log.debug("mousepressed: no valid difficulty found for index=" .. tostring(musicselect.selectedIndex))
                end
            end

            return
        end
    end

    -- ジャンルクリック判定
    for i, g in ipairs(genreListCache) do
        local bx = 10
        local by = 100 + (i-1)*50
        if x >= bx and x <= bx + 120 and y >= by and y <= by + 40 then
            if selectedGenre ~= g then
                selectedGenre = g
                applySelectedGenreFilter()
            end
            return
        end
    end

    -- 難易度背景の平行四辺形クリック判定
    local difficultyZones = getDifficultyZonePolygons()
    for _, diff in ipairs(difficultyOrder) do
        local points = difficultyZones[diff]
        if points and pointInConvexPolygon(x, y, points) then
            -- クリックされた難易度が現在の選択曲に存在するか確認する
            local chartdata = chartreader()
            local levelInfo = (chartdata.level and chartdata.level[musicselect.selectedIndex]) or {}
            if levelValueExists(levelInfo, diff) then
                setSelectedDifficulty(diff)
                musicselect.selectedLevelValue = (levelInfo and levelInfo[diff]) or diff
                return
            else
                -- 存在しない難易度は無視せず、代わりに最初に見つかる有効な難易度へ切替する
                for _, nd in ipairs(difficultyOrder) do
                    if levelValueExists(levelInfo, nd) then
                        setSelectedDifficulty(nd)
                        musicselect.selectedLevelValue = (levelInfo and levelInfo[nd]) or nd
                        log.debug("mousepressed: requested difficulty " .. tostring(diff) .. " not present; switched to " .. tostring(nd) .. " for index " .. tostring(musicselect.selectedIndex))
                        break
                    end
                end
                return
            end
        end
    end

    if x >= displayWidth/3*1.75 and x <= displayWidth/3*1.75+displayWidth/5*1.5 and y >= displayHeight/8*7 and y <= displayHeight/8*7+displayHeight/10 then
        musicselect.selectmode = 2
        musicselect.endprocess = false
        fadeAlpha = 0
        fading = true
        local chartData = chartreader()
        musicselect.musicname = cleanUTF8(chartData.name[musicselect.selectedIndex] or "")
        musicselect.musicartist = cleanUTF8(chartData.artist[musicselect.selectedIndex] or "")
        musicselect.level = chartData.level and chartData.level[musicselect.selectedIndex] or {}
        
        -- E キーが押されていたら editor に遷移
        if love.keyboard.isDown("e") then
            musicselect.selectmode = 8
        end
        return
    end
end






function musicselect.wheelmoved(x, y)
    if y == 0 then return end
    if fading then return end
    local count = getSelectableCount()
    if count <= 0 then return end

    local steps = math.max(1, math.floor(math.abs(y)))
    local delta = (y > 0) and -steps or steps
    local nextIndex = musicselect.selectedIndex or 1
    nextIndex = clamp(nextIndex + delta, 1, count)
    musicselect.selectedIndex = nextIndex
    syncCardTopIndex(count)
    ensureSelectedDifficultyValidForIndex(musicselect.selectedIndex)
end






function musiccard()
    local chartdata = chartreader()

    musicselect.cardBounds = {}

    local itemCount = getSelectableCount()
    local selectedIndex = musicselect.selectedIndex or 1
    if itemCount > 0 then
        selectedIndex = clamp(selectedIndex, 1, itemCount)
    else
        selectedIndex = 0
    end
    musicselect.selectedIndex = selectedIndex
    syncCardTopIndex(itemCount)

    -- ジャンルボタン描画（テキストを矩形内で垂直中央に揃える）
    for i, g in ipairs(genreListCache) do
        local x = 10
        local y = 100 + (i-1)*50
        local btnW, btnH = 120, 40
        if selectedGenre == g then
            love.graphics.setColor(0.2, 0.6, 1, 0.5)
            love.graphics.rectangle("fill", x, y, btnW, btnH)
        end

        if selectedGenre == g then
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5)
        end

        love.graphics.setFont(artistfont)
        local fh = (artistfont and artistfont:getHeight()) or 16
        local textX = x + 10
        local textY = y + math.floor((btnH - fh) / 2)
        love.graphics.print(g, textX, textY)
    end


    local layout = getCardLayout()
    local startIndex = cardTopIndex
    local endIndex = math.min(itemCount, startIndex + layout.visibleCount - 1)
    local cardX = layout.x
    local cardW = layout.w
    local cardH = layout.h
    local row = 0
    local boundsCount = 0

    for i = startIndex, endIndex do
        local jacket = getJacketImage(i)
        local cardY = layout.y + layout.stepY * row
        boundsCount = boundsCount + 1
        musicselect.cardBounds[boundsCount] = {x = cardX, y = cardY, w = cardW, h = cardH, index = i}

        if i == selectedIndex then
            love.graphics.setColor(0.2, 0.6, 1, 0.25)
            love.graphics.rectangle("fill", cardX, cardY, cardW, cardH)
        end

        if jacket and type(jacket.getHeight) == "function" then
            local h = jacket:getHeight()
            if h > 0 then
                local scale = (displayHeight / 10) / h
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(jacket, cardX, cardY, 0, scale, scale)
                local titleText = chartdata.name[i] or ""
                local artistText = chartdata.artist[i] or ""
                local titleFH = titlefont and titlefont:getHeight() or 20
                local artistFH = artistfont and artistfont:getHeight() or 16
                local innerPad = 6
                local totalTextH = titleFH + artistFH + innerPad
                local contentStartY = cardY + math.floor((cardH - totalTextH) / 2)

                local titleX = displayWidth/10*1.5 + jacket:getWidth() * scale
                local titleY = contentStartY
                local titleAreaW = (cardX + cardW) - titleX - 10
                drawCardSingleLineText(titlefont, titleText, titleX, titleY, titleAreaW)

                local artistX = displayWidth/10*2 + jacket:getWidth() * scale
                local artistY = contentStartY + titleFH + innerPad
                local artistAreaW = (displayWidth/2 - artistX - 10)
                drawCardSingleLineText(artistfont, artistText, artistX, artistY, artistAreaW)
            end
        else
            -- プレースホルダー表示
            love.graphics.setColor(0.25, 0.25, 0.25)
            love.graphics.rectangle("fill", cardX, cardY, cardW, cardH)
            love.graphics.setColor(1, 1, 1)
            local titleText = chartdata.name[i] or "Unknown"
            local artistText = chartdata.artist[i] or "Unknown"
            local titleFH = titlefont and titlefont:getHeight() or 20
            local artistFH = artistfont and artistfont:getHeight() or 16
            local innerPad = 6
            local totalTextH = titleFH + artistFH + innerPad
            local contentStartY = cardY + math.floor((cardH - totalTextH) / 2)
            drawCardSingleLineText(titlefont, titleText, cardX + 10, contentStartY, cardW - 20)
            drawCardSingleLineText(artistfont, artistText, cardX + 10, contentStartY + titleFH + innerPad, cardW - 20)
            love.graphics.setColor(1, 1, 0.7)
            love.graphics.setFont(artistfont)
            love.graphics.printf("No Jacket", cardX, cardY + cardH / 2 - artistfont:getHeight() / 2, cardW, "center")
        end

        if i == selectedIndex then
            love.graphics.setColor(0.2, 0.6, 1, 0.9)
        else
            love.graphics.setColor(1, 1, 1)
        end
        love.graphics.rectangle("line", cardX, cardY, cardW, cardH)
        row = row + 1
    end
    --楽曲詳細
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(selecttitlefont)
    -- 選択楽曲のジャケットを表示する領域を枠で描画
    love.graphics.rectangle("line",displayWidth/2,0,displayWidth,displayHeight/3*2)


    --難易度ブロック全体背景描画
    local difficultyZones = getDifficultyZonePolygons()

    for _, diff in ipairs(difficultyOrder) do
        local points = difficultyZones[diff]
        local col = difficultyColor[diff]
        local alpha = (musicselect.selectedDifficulty == diff) and 0.35 or 0.18
        love.graphics.setColor(col[1], col[2], col[3], alpha)
        love.graphics.polygon("fill",
            points[1], points[2],
            points[3], points[4],
            points[5], points[6],
            points[7], points[8]
        )
    end

    -- 難易度テキスト
    love.graphics.setFont(titlefont)
    for _, diff in ipairs(difficultyOrder) do
        local x = displayWidth * difficultyLabelRatio[diff]
        local text = string.upper(diff)

        if musicselect.selectedDifficulty == diff then
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(0, 0, 0)
        end
        love.graphics.print(text, x, displayHeight/3*2)
    end

    -- レベル値表示
    love.graphics.setFont(levelfont)
    for _, diff in ipairs(difficultyOrder) do
        local x = displayWidth * difficultyLabelRatio[diff]
        local color = difficultyColor[diff]
        if musicselect.selectedDifficulty == diff then
            love.graphics.setColor(1,0.85,0.45)
        else
            love.graphics.setColor(color[1], color[2], color[3])
        end
        local levelValue = chartdata.level and chartdata.level[selectedIndex] and chartdata.level[selectedIndex][diff]
        local displayValue = formatDifficultyLevel(levelValue)
        love.graphics.print(displayValue, x, displayHeight/3*2.125)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(titlefont)






    local selectedJacket = getJacketImage(selectedIndex)
    if selectedJacket and type(selectedJacket.getWidth) == "function" and type(selectedJacket.getHeight) == "function" then
        love.graphics.draw(selectedJacket, displayWidth/2+1, displayHeight/20, 0, displayWidth/2/selectedJacket:getWidth(), displayHeight/2/selectedJacket:getHeight())
        jacketimg = selectedJacket
    else
        jacketimg = nil
        -- プレースホルダー
        love.graphics.setColor(0.25, 0.25, 0.25)
        love.graphics.rectangle("fill", displayWidth/2+1, displayHeight/20, displayWidth/2, displayHeight/2)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("No Jacket", displayWidth/2+1, displayHeight/20 + 20, displayWidth/2, "center")
    end

    love.graphics.setColor(1, 1, 1)
    local titleText = chartdata.name[selectedIndex] or ""
    local titleX = displayWidth/40*21
    local titleY = displayHeight/20*11
    local titleClipW = displayWidth/2 - titleX - 10
    local titleClipH = selecttitlefont:getHeight()

    if titleScrollEnabled and titleClipW > 0 and titleClipH > 0 then
        local sx, sy, sw, sh = love.graphics.getScissor()
        love.graphics.setScissor(titleX, titleY, titleClipW, titleClipH)

        local x = titleX - titleScrollOffset
        love.graphics.print(titleText, x, titleY)
        love.graphics.print(titleText, x + titleScrollTextWidth + titleScrollGap, titleY)

        if sx ~= nil then
            love.graphics.setScissor(sx, sy, sw, sh)
        else
            love.graphics.setScissor()
        end
    else
        love.graphics.print(titleText, titleX, titleY)
    end

    love.graphics.setFont(selectartistfont)

    local artistText = chartdata.artist[selectedIndex] or ""
    local artistX = displayWidth/40*21
    local artistY = displayHeight/20*11+60
    local clipX, clipY = artistX, artistY
    local clipW, clipH = displayWidth/2 - artistX - 10, selectartistfont:getHeight()

    if artistScrollEnabled and clipW > 0 and clipH > 0 then
        local sx, sy, sw, sh = love.graphics.getScissor()
        love.graphics.setScissor(clipX, clipY, clipW, clipH)

        local x = artistX - artistScrollOffset
        love.graphics.print(artistText, x, artistY)
        love.graphics.print(artistText, x + artistScrollTextWidth + artistScrollGap, artistY)

        if sx ~= nil then
            love.graphics.setScissor(sx, sy, sw, sh)
        else
            love.graphics.setScissor()
        end
    else
        love.graphics.print(artistText, artistX, artistY)
    end

    if chartdata and chartdata.name and chartdata.name[1] then
        love.graphics.setColor(1, 1, 1)
    end

    -- 楽曲動画視聴ボタン（URL存在時のみ表示）
    local url = (chartdata.url and chartdata.url[selectedIndex]) or ""
    if url and url ~= "" and urlimg then
        local iconScale = 0.1
        local btnW = urlimg:getWidth() * iconScale
        local btnH = urlimg:getHeight() * iconScale
        local btnX = displayWidth - btnW - 10
        local btnY = displayHeight / 20
        love.graphics.setColor(0.8, 0.8, 0.8)
        love.graphics.draw(urlimg, btnX, btnY, 0, iconScale, iconScale)
    end

    --背景透過防止
    love.graphics.setColor(0,0,0,0.3)
    love.graphics.rectangle("fill",displayWidth/2,0,displayWidth/2,displayHeight/3*2)

end







local function createEmptyLevel()
    return {
        easy = "",
        normal = "",
        hard = "",
        extra = "",
        custom = ""
    }
end

local function createEmptyChartMeta(chartEntry)
    local fileName = ""
    if type(chartEntry) == "table" then
        fileName = chartEntry.name or ""
    elseif type(chartEntry) == "string" then
        fileName = chartEntry
    end

    return {
        title = "",
        artist = "",
        bpm = 0,
        volume = 1.0,
        demostart = 0,
        demoend = 0,
        url = "",
        level = createEmptyLevel(),
        genre = {"Unknown"},
        watchuser = {},
        file = fileName
    }
end

local function getChartMetaCacheKey(chartEntry)
    if type(chartEntry) == "table" then
        local archive = chartEntry.archive or ""
        local name = chartEntry.name or ""
        local data = chartEntry.data
        local dataSize = (type(data) == "string") and #data or 0
        local dataHash = 0
        if type(data) == "string" then
            for i = 1, #data do
                dataHash = (dataHash * 131 + data:byte(i)) % 2147483647
            end
        end
        return archive .. ":" .. name .. ":" .. tostring(dataSize) .. ":" .. tostring(dataHash)
    end
    if type(chartEntry) == "string" then
        local info = love.filesystem.getInfo(chartEntry, "file")
        if info then
            return "path:" .. chartEntry .. ":" .. tostring(info.size or 0) .. ":" .. tostring(info.modtime or 0)
        end
        return "path:" .. chartEntry
    end
    return nil
end

local function parseMetaOnly(chartText, chunkName)
    if type(chartText) ~= "string" then
        return nil
    end

    local metaBlock = chartText:match("meta%s*=%s*(%b{})")
    if not metaBlock then
        metaBlock = chartText:match("%[\"meta\"%]%s*=%s*(%b{})")
    end
    if not metaBlock then
        local function captureAll(fn)
            local list = {}
            for s in chartText:gmatch(fn.."%s*%((.-)%)") do
                list[#list + 1] = s
            end
            return list
        end

        local metaCalls = captureAll("meta")
        local artistCalls = captureAll("artist")
        local demostartCalls = captureAll("demostart")
        local demoendCalls = captureAll("demoend")
        local watchuserCalls = captureAll("watchuser")
        local genreCalls = captureAll("genre")
        local urlCalls = captureAll("url")

        local any = (#metaCalls > 0) or (#artistCalls > 0) or (#demostartCalls > 0) or (#demoendCalls > 0)
                    or (#watchuserCalls > 0) or (#genreCalls > 0) or (#urlCalls > 0)
        if any then
            local function splitArgs(s)
                local args = {}
                local i = 1
                local len = #s
                local cur = ""
                local inq = false
                local qchar = nil
                while i <= len do
                    local c = s:sub(i,i)
                    if inq then
                        cur = cur .. c
                        if c == qchar then
                            inq = false
                            qchar = nil
                        end
                    else
                        if c == '"' or c == "'" then
                            inq = true
                            qchar = c
                            cur = cur .. c
                        elseif c == "," then
                            args[#args+1] = cur:match("^%s*(.-)%s*$") or cur
                            cur = ""
                        else
                            cur = cur .. c
                        end
                    end
                    i = i + 1
                end
                if cur ~= "" then
                    args[#args+1] = cur:match("^%s*(.-)%s*$") or cur
                end
                return args
            end

            local parts = {}
            if #metaCalls > 0 then
                local args = splitArgs(metaCalls[1])
                if args[1] then
                    local t = args[1]
                    if not t:match('^["\']') then t = '"'..t..'"' end
                    parts[#parts+1] = "title=" .. t
                end
                if args[2] then
                    local f = args[2]
                    if not f:match('^["\']') then f = '"'..f..'"' end
                    parts[#parts+1] = "file=" .. f
                end
                if args[3] then
                    parts[#parts+1] = "bpm=" .. (tonumber(args[3]) or 0)
                end
            end
            if #artistCalls > 0 then
                local a = splitArgs(artistCalls[1])[1] or "" 
                if a ~= "" and not a:match('^["\']') then a = '"'..a..'"' end
                parts[#parts+1] = "artist=" .. a
            end
            if #demostartCalls > 0 then
                parts[#parts+1] = "demostart=" .. (tonumber(splitArgs(demostartCalls[1])[1]) or 0)
            end
            if #demoendCalls > 0 then
                parts[#parts+1] = "demoend=" .. (tonumber(splitArgs(demoendCalls[1])[1]) or 0)
            end
            if #genreCalls > 0 then
                local g = splitArgs(genreCalls[1])[1] or ""
                if g ~= "" and not g:match('^["\']') then g = '"'..g..'"' end
                parts[#parts+1] = "genre=" .. g
            end
            if #urlCalls > 0 then
                local u = splitArgs(urlCalls[1])[1] or ""
                if u ~= "" and not u:match('^["\']') then u = '"'..u..'"' end
                parts[#parts+1] = "url=" .. u
            end
            if #watchuserCalls > 0 then
                -- watchuser may contain multiple args
                local wargs = splitArgs(watchuserCalls[1])
                local wparts = {}
                for _, v in ipairs(wargs) do
                    local x = v
                    if not x:match('^["\']') then x = '"'..x..'"' end
                    wparts[#wparts+1] = x
                end
                parts[#parts+1] = "watchuser={" .. table.concat(wparts, ",") .. "}"
            end

            metaBlock = "{" .. table.concat(parts, ",") .. "}"
        end
    end
    if not metaBlock then
        log.trace("chartreader: parseMetaOnly - no meta block found in " .. (chunkName or "(unknown)"))
        return nil
    end

    local chunk, err = load("return " .. metaBlock, (chunkName or "chart") .. ":meta", "t")
    if not chunk then
        if verboseSfbLogs then
            log.warn("chartreader: meta load failed for", chunkName or "(unknown)", err)
        end
        return nil
    end

    local ok, meta = pcall(chunk)
    if ok and type(meta) == "table" then
        return meta
    end
    return nil
end

local function applyMetaToParsed(parsed, meta)
    parsed.title = cleanUTF8(meta.title or "")
    parsed.artist = cleanUTF8(meta.artist or "")
    parsed.bpm = meta.bpm or 0

    local rawVolume = tonumber(meta.volume) or 1.0
    if rawVolume <= 1.0 then
        parsed.volume = math.max(rawVolume, 0.0)
    else
        parsed.volume = 1.0 + (rawVolume - 1.0) / 9.0
    end

    parsed.demostart = tonumber(meta.demostart) or 0
    parsed.demoend = tonumber(meta.demoend) or 0
    parsed.url = meta.url or ""

    local levels = meta.levels or {}
    log.debug("  applyMetaToParsed: title=" .. tostring(parsed.title) .. ", meta.levels=" .. tostring(levels))
    if type(levels) == "table" then
        log.debug("    easy=" .. tostring(levels.easy) .. ", normal=" .. tostring(levels.normal) .. ", hard=" .. tostring(levels.hard))
    end
    
    parsed.level = {
        easy = levels.easy or "",
        normal = levels.normal or "",
        hard = levels.hard or "",
        extra = levels.extra or "",
        custom = levels.custom or ""
    }

    parsed.genre = normalizeGenres(meta.genre)
    parsed.watchuser = normalizeWatchusers(meta.watchuser)
end

local function parseChartMeta(chartEntry)
    local cacheKey = getChartMetaCacheKey(chartEntry)
    if cacheKey and chartMetaCache[cacheKey] then
        log.trace("parseChartMeta: Using cached data for " .. (chartEntry.name or "unknown"))
        return chartMetaCache[cacheKey]
    end

    local parsed = createEmptyChartMeta(chartEntry)
    log.trace("parseChartMeta: Parsing chart entry - name=" .. (chartEntry.name or "?"))

    if type(chartEntry) == "table" and type(chartEntry.data) == "string" then
        local meta = parseMetaOnly(chartEntry.data, chartEntry.name or "chart")
        if not meta then
            local chunk, err = load(chartEntry.data, chartEntry.name or "chart", "t")
            if chunk then
                local ok, chart = pcall(chunk)
                if ok and type(chart) == "table" and type(chart.meta) == "table" then
                    meta = chart.meta
                    log.debug("  parseChartMeta: Loaded via pcall(chunk), chart.name=" .. tostring(chartEntry.name))
                    log.debug("    meta.title=" .. tostring(meta.title))
                    log.debug("    meta.levels=" .. tostring(meta.levels))
                    if meta.levels then
                        log.debug("      easy=" .. tostring(meta.levels.easy))
                        log.debug("      normal=" .. tostring(meta.levels.normal))
                    end
                elseif verboseSfbLogs then
                    log.warn("chartreader: invalid chart table", chartEntry.name or "(unknown)")
                end
            elseif verboseSfbLogs then
                log.warn("chartreader: load failed for", chartEntry.name or "(unknown)", err)
            end
        end

        if type(meta) == "table" then
            applyMetaToParsed(parsed, meta)
        end
    end

    if cacheKey then
        chartMetaCache[cacheKey] = parsed
    end
    log.trace("parseChartMeta: Completed for " .. (chartEntry.name or "unknown") .. 
              " - title=" .. (parsed.title or "?") .. ", bpm=" .. (parsed.bpm or "?"))
    return parsed
end

function chartreader()
    if cachedChartData then
        return cachedChartData
    end

    if not chartfiles then
        cachedChartData = {
            name = {},
            artist = {},
            bpm = {},
            volume = {},
            demostart = {},
            demoend = {},
            file = {},
            url = {},
            level = {},
            genre = {},
            watchuser = {}
        }
        return cachedChartData
    end

    log.info("chartreader: Starting to load " .. #chartfiles .. " chart(s)")

    local musicName = {}
    local musicfilesList = {}
    local musicartist = {}
    local musicbpm = {}
    local musiclevel = {}
    local musicvolume = {}
    local demostart = {}
    local demoend = {}
    local musicurl = {}
    local musicgenre = {}
    for i = 1, #chartfiles do
        local chartEntry = chartfiles[i]
        local parsed = parseChartMeta(chartEntry)
        musicName[i] = parsed.title
        musicartist[i] = parsed.artist
        musicbpm[i] = parsed.bpm
        musicvolume[i] = parsed.volume
        demostart[i] = parsed.demostart
        demoend[i] = parsed.demoend
        musicurl[i] = parsed.url
        musiclevel[i] = parsed.level
        musicgenre[i] = parsed.genre
        musicfilesList[i] = parsed.file
        
        log.debug("  [" .. i .. "] title=\"" .. (musicName[i] or "?") .. "\", artist=\"" .. (musicartist[i] or "?") .. 
                 "\", bpm=" .. (musicbpm[i] or "0") .. 
                 ", levels=[" .. (musiclevel[i].easy or "-") .. "," .. (musiclevel[i].normal or "-") .. "," .. 
                 (musiclevel[i].hard or "-") .. "," .. (musiclevel[i].extra or "-") .. "," .. 
                 (musiclevel[i].custom or "-") .. "]")
    end

    local musicwatchuser = {}
    for i = 1, #chartfiles do
        local chartEntry = chartfiles[i]
        local parsed = chartMetaCache[getChartMetaCacheKey(chartEntry)]
        if parsed and parsed.watchuser then
            musicwatchuser[i] = parsed.watchuser
        else
            musicwatchuser[i] = {}
        end
    end

    cachedChartData = {
        name = musicName,
        artist = musicartist,
        url = musicurl,
        bpm = musicbpm,
        volume = musicvolume,
        demostart = demostart,
        demoend = demoend,
        file = musicfilesList,
        level = musiclevel,
        genre = musicgenre,
        watchuser = musicwatchuser
    }
    
    log.info("chartreader: Successfully loaded " .. #musicName .. " chart(s)")
    return cachedChartData
end










function musicselect.draw()
    updateDisplaySize()
    love.graphics.setColor(0,0,0,0.7)
    love.graphics.rectangle("fill",0,0,displayWidth/10,displayHeight/10*9)
    love.graphics.setColor(1, 1, 1, 0.2)
    local bgJacket = getJacketImage(musicselect.selectedIndex) or jacketimg
    if bgJacket and type(bgJacket.getWidth) == "function" and type(bgJacket.getHeight) == "function" then
        love.graphics.draw(bgJacket, 0, 0, 0, displayWidth / bgJacket:getWidth(), displayHeight / bgJacket:getHeight())
    else
        love.graphics.setColor(0.1, 0.1, 0.1, 0.2)
        love.graphics.rectangle("fill", 0, 0, displayWidth, displayHeight)
    end
    love.graphics.setColor(1, 1, 1, 1)
    musiccard()

    -- ジャンルバーおよび戻るボタン
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(backbutton)
    love.graphics.line(displayWidth/10,0,displayWidth/10,displayHeight)
    love.graphics.line(0,displayHeight/10*9,displayWidth/10,displayHeight/10*9)
    if not musicselect.onlineMode then
        love.graphics.print("⇐",0, displayHeight/10*9)
    end
    love.graphics.setFont(titlefont)
    love.graphics.rectangle("line",displayWidth/3*1.75,displayHeight/8*7,displayWidth/5*1.5,displayHeight/10)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill",displayWidth/3*1.75,displayHeight/8*7,displayWidth/5*1.5,displayHeight/10)
    love.graphics.setColor(1, 1, 1)
    local playText = i18n.t("play")
    love.graphics.print(playText, displayWidth/3*2 + titlefont:getWidth(playText), displayHeight/8*7 + 10)
end









function musicselect.drawOverlay()
    if fadeAlpha > 0 then
        love.graphics.setColor(0, 0, 0, fadeAlpha)
        love.graphics.rectangle("fill", 0, 0, displayWidth, displayHeight)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function musicselect.quit()
    if music and music.data then
        for _, source in pairs(music.data) do
            if source and source.stop then
                source:stop()
            end
        end
    end
    fadeAlpha = 0
    fading = false
    musicselect._currentIndex = nil
end





function musicselect.keypressed(key)
    if key == "q" then
        -- 全楽曲ソースファイルを再走査し再読み込み
        local selectionState = captureSelectionState()
        log.info("[Direct Reload] Re-scanning all songs...")
        
        if createsfb and createsfb.load then
            local loadedCollections = createsfb.load({forceRebuildAll = true})
            log.info("[Direct Reload] All songs have been rescanned.")
            if loadedCollections then
                refreshAfterSfbGeneration(selectionState, {collections = loadedCollections, clearPreviewCache = true})
            else
                log.warn("[Direct Reload] The changes could not be applied because the reload failed.")
            end
        else
            log.warn("[direct reload] createsfb.load() not found")
        end

        return
    end

    if key == "a" then
        -- 互換キー: 直接読み込み方式では単一再生成は不要なため全体再読込で同期
        local selectionState = captureSelectionState()
        local selectedIndex = musicselect.selectedIndex or 1
        log.info("[Direct Reload] Performing a full reload including song selection" .. selectedIndex)
        
        if createsfb and createsfb.load then
            local loadedCollections = createsfb.load({forceRebuildAll = false})
            if loadedCollections then
                refreshAfterSfbGeneration(selectionState, {collections = loadedCollections, clearPreviewCache = true})
            else
                log.warn("[Direct Reload] Reload failed.")
            end
        else
            log.warn("[direct reload] createsfb.load() not found")
        end

        return
    end

    if key == "up" then
        local count = getSelectableCount()
        if count > 0 then
            musicselect.selectedIndex = clamp((musicselect.selectedIndex or 1) - 1, 1, count)
            syncCardTopIndex(count)
            ensureSelectedDifficultyValidForIndex(musicselect.selectedIndex)
        end
    end

    if key == "down" then
        local count = getSelectableCount()
        if count > 0 then
            musicselect.selectedIndex = clamp((musicselect.selectedIndex or 1) + 1, 1, count)
            syncCardTopIndex(count)
            ensureSelectedDifficultyValidForIndex(musicselect.selectedIndex)
        end
    end

    if key == "left" or key == "right" then
        local chartdata = chartreader()
        local levelInfo = (chartdata.level and chartdata.level[musicselect.selectedIndex]) or {}
        local current = getDifficultyIndex(musicselect.selectedDifficulty)
        local step = (key == "left") and -1 or 1

        local tried = 0
        local foundDiff = nil
        while tried < #difficultyOrder do
            current = current + step
            if current < 1 then current = #difficultyOrder end
            if current > #difficultyOrder then current = 1 end
            local diff = difficultyOrder[current]
            local value = levelInfo[diff]
            if value and value ~= "" then
                foundDiff = diff
                break
            end
            tried = tried + 1
        end

        if foundDiff then
            setSelectedDifficulty(foundDiff)
            local value = (levelInfo and levelInfo[foundDiff]) or "--"
            musicselect.selectedLevelValue = (value ~= "" and value) or "--"
        else
            -- どの難易度も譜面なしなら現在のままを維持（とりあえず fallback）
            local curVal = (levelInfo and levelInfo[musicselect.selectedDifficulty]) or "--"
            musicselect.selectedLevelValue = (curVal ~= "" and curVal) or "--"
        end
    end

    if key == "return" or key == "space" then
        musicselect.selectmode = 2
        musicselect.endprocess = false
        fadeAlpha = 0
        fading = true
        local chartData = chartreader()
        musicselect.musicname = cleanUTF8(chartData.name[musicselect.selectedIndex] or "")
        musicselect.musicartist = cleanUTF8(chartData.artist[musicselect.selectedIndex] or "")
        musicselect.level = chartData.level and chartData.level[musicselect.selectedIndex] or {}

        -- E キーが押されていたら editor に遷移
        if love.keyboard.isDown("e") then
            musicselect.selectmode = 8
        end
        return
    end
end

function musicselect.getAllWatchusers()
    chartreader()

    if not allChartfilesCache or not allChartDataCache then
        return {}
    end

    local result = {}
    local count = 0
    for i = 1, #allChartfilesCache do
        local watchusers = normalizeWatchusers(allChartDataCache.watchuser and allChartDataCache.watchuser[i] or {})
        if #watchusers > 0 then
            count = count + 1
            result[count] = {
                index = i,
                title = allChartDataCache.name and allChartDataCache.name[i] or "Unknown",
                artist = allChartDataCache.artist and allChartDataCache.artist[i] or "Unknown",
                watchusers = watchusers,
                chartEntry = allChartfilesCache[i]
            }
        end
    end

    return result
end

function musicselect.getWatchuserSongs(searchName)
    if type(searchName) ~= "string" then
        searchName = ""
    end
    
    searchName = searchName:lower()
    
    -- getAllWatchusers() ですべての watchuser 制限楽曲を取得
    local allWatched = musicselect.getAllWatchusers()
    
    if searchName == "" then
        -- 引数なし：すべての watchuser 楽曲を返す
        return allWatched
    end
    
    -- 特定ユーザーで検索
    local results = {}
    for _, song in ipairs(allWatched) do
        local hasMatch = false
        for _, user in ipairs(song.watchusers) do
            if user:lower():find(searchName, 1, true) then
                hasMatch = true
                break
            end
        end
        
        if hasMatch then
            table.insert(results, song)
        end
    end
    
    return results
end

return musicselect
