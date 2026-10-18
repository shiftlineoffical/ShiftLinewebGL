local online_result = {}

local result = require("result")
local online_connect = require("online_connect")

local results = {}
local playerID = nil
local sent = false
local resultFont = nil
local labelFont = nil

local function hasAllResults()
    local players = online_connect.getPartyPlayers()
    if #players == 0 then
        return results[playerID] ~= nil
    end

    for _, id in ipairs(players) do
        if not results[id] then
            return false
        end
    end

    return true
end

local function number(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function localResult()
    local scoreData = _G.score or {}
    return {
        score = number(scoreData.score),
        maxcombo = number(scoreData.maxcombo),
        perfect = number(scoreData.perfect),
        good = number(scoreData.good),
        bad = number(scoreData.bad),
        miss = number(scoreData.miss)
    }
end

local function sendLocalResult()
    if sent or not online_connect.isConnected() then
        return
    end

    local data = localResult()
    playerID = online_connect.getPlayerID() or "local"
    results[playerID] = data
    online_connect.send(
        "ONLINE_RESULT_DATA",
        playerID,
        data.score,
        data.maxcombo,
        data.perfect,
        data.good,
        data.bad,
        data.miss
    )
    sent = true
end

local function receivePacket(typeName, parts)
    if typeName ~= "ONLINE_RESULT_DATA" then
        return
    end

    local remoteID = parts and parts[2]
    if type(remoteID) ~= "string" or remoteID == "" then
        return
    end

    results[remoteID] = {
        score = number(parts[3]),
        maxcombo = number(parts[4]),
        perfect = number(parts[5]),
        good = number(parts[6]),
        bad = number(parts[7]),
        miss = number(parts[8])
    }
end

local function updateFonts()
    local _, height = love.graphics.getDimensions()
    resultFont = love.graphics.newFont(
        "lib/data/fonts/NotoSansJP-Regular.ttf",
        math.max(18, math.floor(height * 0.026))
    )
    labelFont = love.graphics.newFont(
        "lib/data/fonts/NotoSansJP-Light.ttf",
        math.max(14, math.floor(height * 0.019))
    )
end

local function sortedResults()
    local list = {}
    for id, data in pairs(results) do
        list[#list + 1] = {id = id, data = data}
    end
    table.sort(list, function(left, right)
        return left.data.score > right.data.score
    end)
    return list
end

function online_result.load()
    result.load()
    updateFonts()
    results = {}
    playerID = online_connect.getPlayerID() or "local"
    sent = false
    sendLocalResult()
end

function online_result.update(dt)
    result.update(dt)
    sendLocalResult()
end

function online_result.draw()
    result.draw()

    local width, height = love.graphics.getDimensions()
    local list = sortedResults()
    local x = width * 0.04
    local y = height * 0.73
    local rowHeight = math.max(28, height * 0.038)
    local panelWidth = width * 0.42
    local maxRows = math.floor((height * 0.23) / rowHeight)

    love.graphics.setColor(0.02, 0.04, 0.06, 0.94)
    love.graphics.rectangle("fill", x, y, panelWidth, rowHeight * (math.min(#list, maxRows) + 1) + 18)
    love.graphics.setColor(0.55, 0.86, 0.86, 1)
    love.graphics.setFont(labelFont or love.graphics.getFont())
    love.graphics.print("全員の結果", x + 16, y + 8)

    for index = 1, math.min(#list, maxRows) do
        local entry = list[index]
        local rowY = y + 36 + (index - 1) * rowHeight
        local data = entry.data
        local label = entry.id == playerID and "あなた" or ("Player " .. tostring(index))
        local text = string.format(
            "%s    %07d    MAX %d    P %d / G %d / B %d / M %d",
            label,
            data.score,
            data.maxcombo,
            data.perfect,
            data.good,
            data.bad,
            data.miss
        )
        love.graphics.setColor(1, 1, 1, entry.id == playerID and 1 or 0.78)
        love.graphics.setFont(resultFont or love.graphics.getFont())
        love.graphics.print(text, x + 16, rowY)
    end

    if not hasAllResults() then
        love.graphics.setColor(1, 0.85, 0.45, 1)
        love.graphics.setFont(labelFont or love.graphics.getFont())
        love.graphics.print("全員の結果を待っています", x + 16, y - 30)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function online_result.drawOverlay()
    if result.drawOverlay then
        result.drawOverlay()
    end
end

function online_result.mousepressed(...)
    if hasAllResults() and type(changeProgram) == "function" then
        changeProgram(9)
    end
end

function online_result.keypressed(...)
    local key = ...
    if (key == "return" or key == "space" or key == "escape")
        and hasAllResults()
        and type(changeProgram) == "function"
    then
        changeProgram(9)
    end
end

function online_result.quit()
    if result.quit then
        result.quit()
    end
end

online_connect.on("packet", receivePacket)

return online_result