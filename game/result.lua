local result = {}
local i18n = require "i18n"
local ui = require("lib.ui")
local gamejolt = require("gamejolt")
local settings = require("settings")
local log = require("log")
local JSON = require("JSON")

local fonts = {}
local introTime = 0
local actionButtons = {}

local function loadFont(path, size)
    local ok, font
    if type(path) == "string" then
        ok, font = pcall(ui.newFont, path, size)
    else
        ok, font = pcall(ui.newFont, path)
    end
    if ok and font then
        return font
    end

    local okDefault, defaultFont = pcall(ui.newFont, size)
    if okDefault and defaultFont then
        return defaultFont
    end

    return love.graphics.getFont()
end

local function ensureFonts()
    if next(fonts) then
        return
    end

    fonts.eyebrow = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 16)
    fonts.label = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 24)
    fonts.body = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 26)
    fonts.title = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 42)
    fonts.songHero = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 56)
    fonts.metric = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 34)
    fonts.score = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 72)
    fonts.rank = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 104)
    fonts.judge = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 54)
    fonts.heading = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 82)
    fonts.button = loadFont("lib/data/fonts/NotoSansJP-Light.ttf", 30)
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function easeOutCubic(t)
    local x = clamp(t, 0, 1)
    local inv = 1 - x
    return 1 - inv * inv * inv
end

local function easeInOutCubic(t)
    local x = clamp(t, 0, 1)
    if x < 0.5 then
        return 4 * x * x * x
    end

    local inv = -2 * x + 2
    return 1 - (inv * inv * inv) * 0.5
end

local function reveal(time, startTime, duration, easing)
    local eased = (easing or easeOutCubic)((time - startTime) / duration)
    return clamp(eased, 0, 1)
end

local function isImageObject(value)
    return value
        and type(value) == "userdata"
        and type(value.getWidth) == "function"
        and type(value.getHeight) == "function"
end

local function pointInPolygon(x, y, poly)
    if not poly or #poly < 6 then
        return false
    end

    local inside = false
    local j = #poly - 1

    for i = 1, #poly, 2 do
        local xi = poly[i]
        local yi = poly[i + 1]
        local xj = poly[j]
        local yj = poly[j + 1]

        local intersect =
            ((yi > y) ~= (yj > y)) and
            (x < (xj - xi) * (y - yi) / ((yj - yi) == 0 and 0.0001 or (yj - yi)) + xi)

        if intersect then
            inside = not inside
        end

        j = i
    end

    return inside
end

local function getParallelogram(x, y, w, h, skew)
    return {
        x, y,
        x + skew, y + h,
        x + w + skew, y + h,
        x + w, y
    }
end

local function getPolyBounds(poly)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for i = 1, #poly, 2 do
        local px = poly[i]
        local py = poly[i + 1]
        if px < minX then
            minX = px
        end
        if px > maxX then
            maxX = px
        end
        if py < minY then
            minY = py
        end
        if py > maxY then
            maxY = py
        end
    end

    return minX, minY, maxX, maxY
end

local function withPolygonStencil(poly, drawFn)
    love.graphics.stencil(function()
        love.graphics.polygon("fill", poly)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    drawFn()
    love.graphics.setStencilTest()
end

local function getAccent(rank)
    local tones = {
        SS = 1.00,
        S = 0.97,
        A = 0.94,
        B = 0.90,
        C = 0.86,
        D = 0.82
    }
    local tone = tones[rank] or 0.92

    return {tone, tone, tone}
end

local function getLayoutSkew(w, h, panelH)
    local slope = -(w / 20) / (h * 0.9)
    return slope * panelH
end

local function drawPolyPanel(x, y, w, h, skew, alpha, fillTone, lineAlpha)
    local tone = fillTone or 0.10
    local poly = getParallelogram(x, y, w, h, skew)
    love.graphics.setColor(tone, tone, tone, 0.96 * alpha)
    love.graphics.polygon("fill", poly)
    love.graphics.setColor(1, 1, 1, (lineAlpha or 0.5) * alpha)
    love.graphics.polygon("line", poly)
    return poly
end

local function drawCroppedImage(image, x, y, w, h, alpha)
    if isImageObject(image) then
        local imageW = math.max(1, image:getWidth())
        local imageH = math.max(1, image:getHeight())
        local scale = math.max(w / imageW, h / imageH)
        local drawW = imageW * scale
        local drawH = imageH * scale
        local drawX = x + (w - drawW) * 0.5
        local drawY = y + (h - drawH) * 0.5
        love.graphics.setScissor(x, y, w, h)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(image, drawX, drawY, 0, scale, scale)
        love.graphics.setScissor()
        return
    end

    love.graphics.setColor(0.10, 0.10, 0.10, 0.96 * alpha)
    love.graphics.rectangle("fill", x, y, w, h)
end

local function getResultScore()
    local scoreData = _G.score or {}
    local perfect = math.max(0, math.floor(tonumber(scoreData.perfect) or 0))
    local good = math.max(0, math.floor(tonumber(scoreData.good) or 0))
    local bad = math.max(0, math.floor(tonumber(scoreData.bad) or 0))
    local miss = math.max(0, math.floor(tonumber(scoreData.miss) or 0))

    return {
        score = math.max(0, math.floor(tonumber(scoreData.score) or 0)),
        maxcombo = math.max(0, math.floor(tonumber(scoreData.maxcombo) or 0)),
        perfect = perfect,
        good = good,
        bad = bad,
        miss = miss,
        total = perfect + good + bad + miss
    }
end

local function getAccuracy(scoreData)
    if scoreData.total <= 0 then
        return 0
    end

    local weighted = scoreData.perfect + scoreData.good * 0.7 + scoreData.bad * 0.2
    return clamp(weighted / scoreData.total, 0, 1)
end

local function parseDifficultyValue(level)
    if type(level) == "number" then
        return math.max(1, level)
    end

    if type(level) ~= "string" then
        return 1
    end

    local numeric = tonumber(level)
    if numeric and numeric > 0 then
        if numeric > 20 then
            return numeric / 10
        end
        return numeric
    end

    local lower = level:lower()
    if lower == "easy" then
        return 4
    elseif lower == "normal" then
        return 7
    elseif lower == "hard" then
        return 10
    elseif lower == "extra" then
        return 12
    elseif lower == "custom" then
        return 9
    end

    local extracted = level:match("([0-9]+%.?[0-9]*)")
    local parsed = tonumber(extracted)
    if parsed and parsed > 0 then
        if parsed > 20 then
            return parsed / 10
        end
        return parsed
    end

    return 1
end

local getRank

local function getSongRating(scoreData, level)
    local difficulty = parseDifficultyValue(level)
    local accuracy = getAccuracy(scoreData)
    local rating = math.max(0, difficulty) * accuracy

    return clamp(math.floor(rating * 100 + 0.5) / 100, 0, 15)
end

local function getRatingAverage()
    local stats = settings and settings.settingsdata and settings.settingsdata.stats

    if type(stats) == "table" then
        local history = stats.ratingHistory
        if type(history) == "table" and #history > 0 then
            local sum = 0
            local count = 0
            for _, value in ipairs(history) do
                local numericValue = tonumber(value)
                if numericValue then
                    sum = sum + numericValue
                    count = count + 1
                end
            end
            if count > 0 then
                return math.floor((sum / count) * 100 + 0.5) / 100
            end
        end
    end

    return 0
end

local function updateRatingStats(rating)
    if not settings or type(settings.settingsdata) ~= "table" then
        return
    end

    local stats = settings.settingsdata.stats
    if type(stats) ~= "table" then
        stats = {}
        settings.settingsdata.stats = stats
    end

    if type(stats.ratingHistory) ~= "table" then
        stats.ratingHistory = {}
    end

    table.insert(stats.ratingHistory, rating)
    while #stats.ratingHistory > 30 do
        table.remove(stats.ratingHistory, 1)
    end

    local sum = 0
    for _, value in ipairs(stats.ratingHistory) do
        local numericValue = tonumber(value)
        if numericValue then
            sum = sum + numericValue
        end
    end

    stats.ratingAverage = (#stats.ratingHistory > 0)
        and math.floor((sum / #stats.ratingHistory) * 100 + 0.5) / 100
        or 0
    stats.lastRating = rating

    if type(stats.bestRating) ~= "number" or rating > stats.bestRating then
        stats.bestRating = rating
    end

    if type(settings.save) == "function" then
        pcall(settings.save)
    end

    return stats.ratingAverage
end

local function decodeGameJoltValue(value)
    if type(value) ~= "string" then
        return value
    end

    local ok, decoded = pcall(function()
        return JSON:decode(value)
    end)
    if ok then
        return decoded
    end

    return value
end

local function sendResultToGameJolt()
    if not gamejolt then
        log.warn("GameJolt module unavailable")
        return
    end

    local scoreData = getResultScore()
    local title, artist, level = tostring(_G.name or ""), tostring(_G.artist or ""), tostring(_G.level or "")
    local songRating = getSongRating(scoreData, level)
    local stats = settings and settings.settingsdata and settings.settingsdata.stats or {}
    local overallRating = updateRatingStats(songRating)

    if not overallRating then
        overallRating = getRatingAverage()
    end

    local ratingAvg = overallRating

    local payload = {
        song = title,
        artist = artist,
        difficulty = level,
        level = level,
        rating = overallRating,
        ratingAverage = overallRating,
        songRating = songRating,
        lastRating = stats.lastRating or songRating,
        score = scoreData.score,
        maxcombo = scoreData.maxcombo,
        perfect = scoreData.perfect,
        good = scoreData.good,
        bad = scoreData.bad,
        miss = scoreData.miss,
        accuracy = string.format("%.4f", getAccuracy(scoreData)),
        settings = (settings and settings.settingsdata) or {}
    }

    if gamejolt.status and gamejolt.status.authenticated then
        local callScoreOK, scoreSynced, responseScore = pcall(function()
            return gamejolt.submitScore(scoreData.score, scoreData.score, JSON:encode(payload), 1090059)
        end)
        if callScoreOK and scoreSynced then
            log.info("GameJolt result score synced")
        else
            log.warn("GameJolt result score sync failed: " .. tostring((type(responseScore) == "table" and responseScore.message) or responseScore or "unknown"))
            local fallbackOK, fallbackResponse = gamejolt.setData("result_score", scoreData.score)
            if fallbackOK then
                log.info("GameJolt result score saved to Data Store")
            else
                log.warn("GameJolt result score Data Store fallback failed: " .. tostring(fallbackResponse and fallbackResponse.message or fallbackResponse or "unknown"))
            end
        end

        local songKey = title
            .. "|"
            .. artist
            .. "|"
            .. level

        local callBestOK, bestSynced, bestResponse = pcall(function()
            return gamejolt.saveBestSongScore(
                songKey,
                scoreData.score,
                {
                    song = title,
                    artist = artist,
                    level = level,
                    accuracy = getAccuracy(scoreData)
                }
            )
        end)

        if callBestOK and bestSynced then
            log.info("GameJolt best song score synced")
        else
            local bestError = type(bestResponse) == "table"
                and bestResponse.message
                or bestResponse

            log.warn(
                "GameJolt best song score sync failed: "
                .. tostring(bestError or "unknown")
            )
        end

        local callRatingOK, ratingSynced, responseRating = pcall(function()
            return gamejolt.setData("result_rating", overallRating)
        end)
        if callRatingOK and ratingSynced then
            log.info("GameJolt result rating synced to Data Store")
        else
            log.warn("GameJolt result rating sync failed: " .. tostring((type(responseRating) == "table" and responseRating.message) or responseRating or "unknown"))
        end

        local callSummaryOK, summarySynced, responseSummary = pcall(function()
            return gamejolt.setData("result_summary", payload)
        end)
        if callSummaryOK and summarySynced then
            log.info("GameJolt result summary synced to Data Store")
        else
            log.warn("GameJolt result summary sync failed: " .. tostring((type(responseSummary) == "table" and responseSummary.message) or responseSummary or "unknown"))
        end

        local okLoadScore, responseLoadScore = pcall(function()
            return gamejolt.fetchData("result_score")
        end)
        if okLoadScore and responseLoadScore and responseLoadScore.data ~= nil then
            log.info("GameJolt result score loaded: " .. tostring(decodeGameJoltValue(responseLoadScore.data)))
        else
            log.warn("GameJolt result score load failed: " .. tostring((type(responseLoadScore) == "table" and responseLoadScore.message) or responseLoadScore or "unknown"))
        end

        local okLoadSummary, responseLoadSummary = pcall(function()
            return gamejolt.fetchData("result_summary")
        end)
        if okLoadSummary and responseLoadSummary and responseLoadSummary.data ~= nil then
            local loadedSummary = decodeGameJoltValue(responseLoadSummary.data)
            log.info("GameJolt result summary loaded: " .. tostring(type(loadedSummary) == "table" and loadedSummary.song or loadedSummary))
        else
            log.warn("GameJolt result summary load failed: " .. tostring((type(responseLoadSummary) == "table" and responseLoadSummary.message) or responseLoadSummary or "unknown"))

        end
    end

    if type(gamejolt.savePlayerStats) == "function" then
        local callStatsOK, statsSynced, responseStats = pcall(function()
            return gamejolt.savePlayerStats(payload, "player_stats", "local_player_stats.json")
        end)
        if callStatsOK then
            if statsSynced then
                log.info("GameJolt player stats synced")
            else
                log.warn("Player stats save failed: " .. tostring((type(responseStats) == "table" and responseStats.message) or responseStats or "unknown"))
            end
        else
            log.warn("Player stats save failed: " .. tostring(statsSynced or "unknown"))
        end
    end

end

getRank = function(scoreData)
    local accuracy = getAccuracy(scoreData)
    if scoreData.perfect > 0 and scoreData.good == 0 and scoreData.bad == 0 and scoreData.miss == 0 then
        return "SS"
    end
    if accuracy >= 0.95 then
        return "S"
    end
    if accuracy >= 0.88 then
        return "A"
    end
    if accuracy >= 0.78 then
        return "B"
    end
    if accuracy >= 0.65 then
        return "C"
    end
    return "D"
end

local function getSongMeta()
    return tostring(_G.name or "Unknown Title"),
        tostring(_G.artist or "Unknown Artist"),
        tostring(_G.level or "--"),
        _G.jacket
end

local function beginFrame()
    actionButtons = {}
end

local function registerButton(id, poly)
    actionButtons[#actionButtons + 1] = {
        id = id,
        poly = poly
    }
end

local function triggerAction(actionId)
    if actionId == "retry" then
        changeProgram(4)
    elseif actionId == "select" then
        changeProgram(3)
    end
end

local function drawBackdrop(w, h, jacket, alpha)
    local splitX = math.floor(w * 0.5)

    love.graphics.clear(0.06, 0.06, 0.06, 1)
    drawCroppedImage(jacket, 0, 0, w, h, 0.16)

    love.graphics.setColor(0.03, 0.03, 0.03, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)

    drawCroppedImage(jacket, 0, 0, splitX, h, math.max(0.14, alpha))
    love.graphics.setColor(0.02, 0.02, 0.02, 0.18 + 0.14 * alpha)
    love.graphics.rectangle("fill", 0, 0, splitX, h)

    love.graphics.setColor(0.05, 0.05, 0.05, 0.98)
    love.graphics.rectangle("fill", splitX, 0, w - splitX, h)

    love.graphics.setColor(1, 1, 1, 0.12 * alpha)
    love.graphics.rectangle("fill", splitX - 1, 0, 2, h)

    love.graphics.setColor(1, 1, 1, 0.04 * alpha)
    love.graphics.rectangle("fill", splitX + clamp(w * 0.03, 18, 32), h * 0.12, w * 0.18, 2)
    love.graphics.rectangle("fill", splitX + clamp(w * 0.03, 18, 32), h * 0.88, w * 0.24, 2)
end

local function drawHeroPanel(x, y, w, h, accent, alpha, title, artist, level, jacket, rank)
    if alpha <= 0 then
        return
    end

    local screenW, screenH = love.graphics.getDimensions()
    local sideBySide = h < w * 0.78
    local titleW = w
    local jacketSize
    local jacketX
    local jacketY

    if sideBySide then
        jacketSize = clamp(math.min(w * 0.40, h - 12), 150, 250)
        jacketX = x + w - jacketSize
        jacketY = y + h - jacketSize
        titleW = w - jacketSize - 26
    else
        local headerH = clamp(h * 0.28, 120, 190)
        jacketSize = clamp(math.min(w * 0.78, h - headerH - 20), 190, 340)
        jacketX = x + w - jacketSize - 6
        jacketY = y + headerH + 22
    end

    local jacketSkew = getLayoutSkew(screenW, screenH, jacketSize + 18)
    drawPolyPanel(jacketX - 18, jacketY - 10, jacketSize + 30, jacketSize + 20, jacketSkew, 0.84 * alpha, 0.08, 0.40)

    love.graphics.setFont(fonts.rank)
    love.graphics.setColor(1, 1, 1, 0.95 * alpha)
    love.graphics.printf(rank, x, y - 10, titleW, "right")

    local rankBottom = y - 10 + fonts.rank:getHeight()
    love.graphics.setFont(fonts.songHero)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(title, x, rankBottom - 14, titleW, "right")

    local _, titleLines = fonts.songHero:getWrap(title, titleW)
    local titleHeight = math.max(1, #titleLines) * fonts.songHero:getHeight()
    local artistY = rankBottom - 6 + titleHeight

    love.graphics.setFont(fonts.body)
    love.graphics.setColor(1, 1, 1, 0.72 * alpha)
    love.graphics.printf(artist, x, artistY, titleW, "right")

    local levelText = i18n.t("levelPrefix") .. level
    local levelW = fonts.label:getWidth(levelText) + 34
    local levelH = 42
    local levelY = artistY + fonts.body:getHeight() + 14
    local levelX = x + titleW - levelW
    local levelSkew = getLayoutSkew(screenW, screenH, levelH)
    drawPolyPanel(levelX, levelY, levelW, levelH, levelSkew, alpha, 0.10, 0.50)
    love.graphics.setFont(fonts.label)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(levelText, levelX + 12, levelY + (levelH - fonts.label:getHeight()) * 0.5 - 1, levelW - 24, "center")

    drawCroppedImage(jacket, jacketX, jacketY, jacketSize, jacketSize, 0.98 * alpha)
    love.graphics.setColor(0.02, 0.02, 0.02, 0.18 * alpha)
    love.graphics.rectangle("fill", jacketX, jacketY, jacketSize, jacketSize)
    love.graphics.setColor(1, 1, 1, 0.60 * alpha)
    love.graphics.rectangle("line", jacketX, jacketY, jacketSize, jacketSize)
end

local function drawResultHeader(x, y, w, h, alpha, title, artist, level, rank)
    if alpha <= 0 then
        return
    end

    drawPolyPanel(x, y, w, h, 0, alpha, 0.06, 0.24)

    local pad = clamp(w * 0.05, 20, 34)
    local rankFont = w < 760 and fonts.score or fonts.rank
    local titleFont = w < 760 and fonts.body or fonts.title

    love.graphics.setFont(fonts.label)
    love.graphics.setColor(1, 1, 1, 0.80 * alpha)
    love.graphics.print(i18n.t("result"), x + pad, y + 16)

    love.graphics.setFont(rankFont)
    love.graphics.setColor(1, 1, 1, 0.92 * alpha)
    love.graphics.printf(rank, x + pad, y + 12, w - pad * 2, "right")

    local rankW = rankFont:getWidth(rank)
    local contentW = math.max(140, w - pad * 2 - rankW - 24)
    local titleY = y + clamp(h * 0.36, 52, 88)

    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(title, x + pad, titleY, contentW, "left")

    local _, titleLines = titleFont:getWrap(title, contentW)
    local titleHeight = math.max(1, #titleLines) * titleFont:getHeight()
    local artistY = titleY + titleHeight + 8

    love.graphics.setFont(fonts.body)
    love.graphics.setColor(1, 1, 1, 0.70 * alpha)
    love.graphics.printf(artist, x + pad, artistY, contentW, "left")

    love.graphics.setFont(fonts.label)
    love.graphics.setColor(1, 1, 1, 0.72 * alpha)
    love.graphics.print(i18n.t("levelPrefix") .. tostring(level), x + pad, y + h - fonts.label:getHeight() - 16)
end

local function drawScoreBlock(x, y, w, h, alpha, score, total, ratingAvg, songRating, bestRating)
    if alpha <= 0 then
        return
    end

    drawPolyPanel(x, y, w, h, 0, alpha, 0.08, 0.24)

    local pad = clamp(w * 0.05, 20, 34)
    love.graphics.setFont(fonts.label)
    love.graphics.setColor(1, 1, 1, 0.82 * alpha)
    love.graphics.print(i18n.t("score"), x + pad, y + 16)

    love.graphics.setFont(fonts.score)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(string.format("%07d", score), x + pad, y + h * 0.33, w - pad * 2, "right")

    local ratingY = y + h - fonts.eyebrow:getHeight() * 4 - 18
    love.graphics.setFont(fonts.eyebrow)
    love.graphics.setColor(1, 1, 1, 0.58 * alpha)
    love.graphics.print(i18n.t("ratingAverage") .. " " .. string.format("%.2f", ratingAvg or 0), x + pad, ratingY)
    love.graphics.print(i18n.t("songRate") .. " " .. string.format("%.2f", songRating or 0), x + pad, ratingY + fonts.eyebrow:getHeight() + 6)

    if type(bestRating) == "number" and bestRating > 0 then
        love.graphics.print(i18n.t("bestRating") .. " " .. string.format("%.2f", bestRating), x + pad, ratingY + (fonts.eyebrow:getHeight() + 6) * 2)
    end

    love.graphics.print(i18n.t("totalNotes") .. tostring(total), x + pad, y + h - fonts.eyebrow:getHeight() - 14)
end

local function drawStatStrip(x, y, w, h, skew, label, value, accent, alpha, big)
    if alpha <= 0 then
        return
    end

    drawPolyPanel(x, y, w, h, skew, alpha, 0.10, 0.50)

    local labelFont = big and fonts.title or fonts.eyebrow
    local valueFont = big and fonts.score or fonts.metric
    love.graphics.setFont(labelFont)
    love.graphics.setColor(1, 1, 1, 0.82 * alpha)
    love.graphics.print(label, x + 16, y + 8)

    local valueY = y + h - valueFont:getHeight() - (big and 10 or 8)
    love.graphics.setFont(valueFont)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(value, x + 18, valueY, w - 36, "right")
end

local function drawActionButton(x, y, w, h, skew, id, text, accent, alpha, mouseX, mouseY, primary)
    if alpha <= 0 then
        return
    end

    local poly = getParallelogram(x, y, w, h, skew)
    if alpha > 0.85 then
        registerButton(id, poly)
    end

    local hover = alpha > 0.85 and pointInPolygon(mouseX, mouseY, poly)
    local fill = primary and (hover and 0.25 or 0.16) or (hover and 0.20 or 0.10)
    local textColor = {1, 1, 1}

    love.graphics.setColor(fill, fill, fill, 0.96 * alpha)
    love.graphics.polygon("fill", poly)
    love.graphics.setColor(1, 1, 1, 0.50 * alpha)
    love.graphics.polygon("line", poly)

    local buttonFont = w < 240 and fonts.label or fonts.button
    love.graphics.setFont(buttonFont)
    love.graphics.setColor(textColor[1], textColor[2], textColor[3], alpha)
    love.graphics.printf(text, x + 16, y + (h - buttonFont:getHeight()) * 0.5, w - 32, "center")
end

local function drawJudgementRow(x, y, w, h, label, value, alpha)
    if alpha <= 0 then
        return
    end

    drawPolyPanel(x, y, w, h, 0, alpha, 0.08, 0.22)

    local valueW = clamp(w * 0.28, 120, 188)
    local labelFont = h >= 58 and fonts.judge or fonts.title
    love.graphics.setFont(labelFont)
    love.graphics.setColor(1, 1, 1, 0.92 * alpha)
    love.graphics.print(label, x + 6, y + (h - labelFont:getHeight()) * 0.5 - 3)

    local boxX = x + w - valueW
    drawPolyPanel(boxX, y, valueW, h, 0, alpha, 0.12, 0.40)
    love.graphics.setFont(fonts.metric)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(tostring(value), boxX + 14, y + (h - fonts.metric:getHeight()) * 0.5, valueW - 28, "left")
end

function result.load()
    ensureFonts()
    introTime = 0
    actionButtons = {}
    gamestatus = "Result"
    sendResultToGameJolt()
end

function result.update(dt)
    introTime = introTime + math.max(0, tonumber(dt) or 0)
end

function result.keypressed(key)
    if key == "r" then
        triggerAction("retry")
        return
    end

    if key == "return" or key == "space" or key == "escape" then
        triggerAction("select")
    end
end

function result.mousepressed(x, y, button)
    if button ~= 1 then
        return
    end

    for i = 1, #actionButtons do
        local action = actionButtons[i]
        if pointInPolygon(x, y, action.poly) then
            triggerAction(action.id)
            return
        end
    end
end

function result.draw()
    ensureFonts()
    beginFrame()

    local w, h = love.graphics.getDimensions()
    local scoreData = getResultScore()
    local accuracy = getAccuracy(scoreData)
    local accuracyText = string.format("%.2f%%", accuracy * 100)
    local rank = getRank(scoreData)
    local songRating = getSongRating(scoreData, tostring(_G.level or ""))
    local stats = settings and settings.settingsdata and settings.settingsdata.stats or {}
    local ratingAvg = getRatingAverage()
    local bestRating = stats.bestRating or 0
    local accent = getAccent(rank)
    local title, artist, level, jacket = getSongMeta()
    local mouseX, mouseY = love.mouse.getPosition()

    local baseAlpha = reveal(introTime, 0.00, 0.24)
    local contentT = reveal(introTime, 0.82, 0.36)
    local panelT = reveal(introTime, 1.06, 0.34)
    local buttonT = reveal(introTime, 1.40, 0.30)

    drawBackdrop(w, h, jacket, baseAlpha)

    local splitX = math.floor(w * 0.5)
    local rightX = splitX
    local rightW = w - splitX
    local headerH = math.floor(h * 0.28)
    local scoreH = math.floor(h * 0.17)
    local metricH = math.floor(h * 0.11)
    local footerH = math.floor(h * 0.11)
    local judgementAreaH = h - headerH - scoreH - metricH - footerH
    local judgementH = math.floor(judgementAreaH / 4)
    local judgementRemainder = judgementAreaH - judgementH * 4

    drawResultHeader(rightX, 0, rightW, headerH, contentT, title, artist, level, rank)
    drawScoreBlock(rightX, headerH, rightW, scoreH, panelT, scoreData.score, scoreData.total, ratingAvg, songRating, bestRating)

    local metricY = headerH + scoreH
    local maxComboW = math.floor(rightW * 0.34)
    local accuracyW = math.floor(rightW * 0.33)
    local rankW = rightW - maxComboW - accuracyW
    drawStatStrip(rightX, metricY, maxComboW, metricH, 0, i18n.t("maxCombo"), tostring(scoreData.maxcombo), accent, panelT, false)
    drawStatStrip(rightX + maxComboW, metricY, accuracyW, metricH, 0, i18n.t("accuracy"), accuracyText, accent, panelT, false)
    drawStatStrip(rightX + maxComboW + accuracyW, metricY, rankW, metricH, 0, i18n.t("rank"), rank, accent, panelT, false)

    local judgementRows = {
        {label = i18n.t("perfect"), value = scoreData.perfect, start = 1.18},
        {label = i18n.t("good"), value = scoreData.good, start = 1.24},
        {label = i18n.t("bad"), value = scoreData.bad, start = 1.30},
        {label = i18n.t("miss"), value = scoreData.miss, start = 1.36}
    }

    local rowY = metricY + metricH
    for i = 1, #judgementRows do
        local row = judgementRows[i]
        local extra = i == #judgementRows and judgementRemainder or 0
        local rowH = judgementH + extra
        local rowT = reveal(introTime, row.start, 0.24)
        drawJudgementRow(rightX, rowY, rightW, rowH, row.label, row.value, rowT * panelT)
        rowY = rowY + rowH
    end

    local footerY = h - footerH
    local hintH = math.min(22, math.floor(footerH * 0.28))
    local buttonY = footerY + hintH
    local buttonH = h - buttonY
    local retryW = math.floor(rightW * 0.42)
    local selectW = rightW - retryW

    if buttonT > 0 then
        love.graphics.setFont(fonts.eyebrow)
        love.graphics.setColor(1, 1, 1, 0.54 * buttonT)
        love.graphics.print(i18n.t("retryHint"), rightX + 18, footerY + 4)
        love.graphics.printf(i18n.t("musicSelectHint"), rightX + 18, footerY + 4, rightW - 36, "right")
    end

    drawActionButton(
        rightX,
        buttonY,
        retryW,
        buttonH,
        0,
        "retry",
        i18n.t("retry"),
        accent,
        buttonT,
        mouseX,
        mouseY,
        true
    )

    drawActionButton(
        rightX + retryW,
        buttonY,
        selectW,
        buttonH,
        0,
        "select",
        i18n.t("musicSelect"),
        accent,
        buttonT,
        mouseX,
        mouseY,
        false
    )
end

function result.quit()
    actionButtons = {}
    introTime = 0
end

return result
