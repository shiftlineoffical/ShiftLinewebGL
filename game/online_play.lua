local online_play = {}

local play = require("gameplay.play")
local online_connect = require("online_connect")
local gamejolt = require("gamejolt")

local comboByPlayer = {}
local playerInfo = {}
local avatarCache = {}
local rankedPlayers = {}
local rankingsDirty = true

local playerID = nil
local sendTimer = 0
local infoTimer = 0
local lastSentCombo = nil

local comboFont = nil
local labelFont = nil
local playerFont = nil
local rankFont = nil
local getLocalInfo
local loadAvatar

local function resetState()
    comboByPlayer = {}
    playerInfo = {}
    avatarCache = {}
    rankedPlayers = {}
    rankingsDirty = true

    playerID =
        online_connect.getPlayerID() or "local"

    local localName, localAvatarUrl = getLocalInfo()

    comboByPlayer[playerID] = 0

    playerInfo[playerID] = {
        name = localName,
        avatarUrl = localAvatarUrl,
    }

    if localAvatarUrl then
        loadAvatar(localAvatarUrl)
    end

    sendTimer = 0
    infoTimer = 0
    lastSentCombo = nil
end

local function updateFonts()
    local _, height =
        love.graphics.getDimensions()

    comboFont = love.graphics.newFont(
        "lib/data/fonts/NotoSansJP-Regular.ttf",
        math.max(
            24,
            math.floor(height * 0.04)
        )
    )

    labelFont = love.graphics.newFont(
        "lib/data/fonts/NotoSansJP-Light.ttf",
        math.max(
            14,
            math.floor(height * 0.02)
        )
    )

    playerFont = love.graphics.newFont(
        "lib/data/fonts/NotoSansJP-Regular.ttf",
        math.max(
            18,
            math.floor(height * 0.025)
        )
    )

    rankFont = love.graphics.newFont(
        "lib/data/fonts/NotoSansJP-Regular.ttf",
        math.max(
            20,
            math.floor(height * 0.03)
        )
    )
end

getLocalInfo = function()
    local name = "Player"
    local avatarUrl = nil

    if gamejolt
        and gamejolt.status
        and gamejolt.status.authenticated
    then
        if type(gamejolt.status.username) == "string"
            and gamejolt.status.username ~= ""
        then
            name =
                gamejolt.status.username
        end

        if type(gamejolt.status.avatarUrl) == "string"
            and gamejolt.status.avatarUrl ~= ""
        then
            avatarUrl =
                gamejolt.status.avatarUrl
        end
    end

    if name == "Player"
        and type(playerID) == "string"
        and playerID ~= ""
        and playerID ~= "local"
    then
        name = playerID
    end

    return name, avatarUrl
end

local function getAvatarExtension(url)
    if type(url) ~= "string" then
        return "png"
    end

    local clean =
        url:gsub("#.*$", "")
            :gsub("%?.*$", "")

    local ext =
        clean:match("%.([%w]+)$")

    if not ext then
        return "png"
    end

    ext = ext:lower()

    if ext == "jpg"
        or ext == "jpeg"
    then
        return "jpg"
    end

    return "png"
end

loadAvatar = function(url)
    if type(url) ~= "string"
        or url == ""
    then
        return nil
    end

    if avatarCache[url] then
        return avatarCache[url]
    end

    local okHttp, http =
        pcall(require, "socket.http")

    if not okHttp
        or not http
        or not http.request
    then
        return nil
    end

    local body, code =
        http.request(url)

    if code ~= 200
        and code ~= "200"
    then
        return nil
    end

    if type(body) ~= "string"
        or body == ""
    then
        return nil
    end

    local ext =
        getAvatarExtension(url)

    local okFile, fileData =
        pcall(
            love.filesystem.newFileData,
            body,
            "online_avatar." .. ext
        )

    if not okFile
        or not fileData
    then
        return nil
    end

    local okImage, image =
        pcall(
            love.graphics.newImage,
            fileData
        )

    if not okImage
        or not image
    then
        return nil
    end

    avatarCache[url] = image

    return image
end

local function sendPlayerInfo()
    if not online_connect.isConnected() then
        return
    end

    local name, avatarUrl =
        getLocalInfo()
    local id = playerID or "local"

    playerInfo[id] = {
        name = name,
        avatarUrl = avatarUrl,
    }

    if avatarUrl then
        loadAvatar(avatarUrl)
    end

    online_connect.send(
        "ONLINE_PLAYER",
        id,
        name,
        avatarUrl or ""
    )
end

local function receivePacket(typeName, parts)
    if typeName == "ONLINE_PLAYER" then
        local id = parts and parts[2]
        local name = parts and parts[3]
        local avatarUrl = parts and parts[4]

        if type(id) ~= "string"
            or id == ""
        then
            return
        end

        if type(name) ~= "string"
            or name == ""
        then
            name = "Player"
        end

        if type(avatarUrl) ~= "string"
            or avatarUrl == ""
        then
            avatarUrl = nil
        end

        playerInfo[id] = {
            name = name,
            avatarUrl = avatarUrl,
        }

        rankingsDirty = true
        if avatarUrl then
            loadAvatar(avatarUrl)
        end

        return
    end

    if typeName == "ONLINE_COMBO" then
        local id = parts and parts[2]
        local combo =
            tonumber(parts and parts[3])

        if type(id) == "string"
            and id ~= ""
            and combo
        then
            comboByPlayer[id] =
                math.max(
                    0,
                    math.floor(combo)
                )
            rankingsDirty = true
        end

        return
    end
end

local function playerLeft(id)
    if not id then
        return
    end

    comboByPlayer[id] = nil
    playerInfo[id] = nil
    rankingsDirty = true
end

local function getRankedPlayers()
    if not rankingsDirty then
        return rankedPlayers
    end

    local result = {}

    for id, combo in pairs(comboByPlayer) do
        local info =
            playerInfo[id] or {}

        result[#result + 1] = {
            id = id,
            combo =
                math.max(
                    0,
                    math.floor(
                        tonumber(combo) or 0
                    )
                ),
            name =
                info.name or "Player",
            avatarUrl =
                info.avatarUrl,
        }
    end

    table.sort(
        result,
        function(a, b)
            if a.combo ~= b.combo then
                return a.combo > b.combo
            end

            return tostring(a.id)
                < tostring(b.id)
        end
    )

    rankedPlayers = result
    rankingsDirty = false
    return rankedPlayers
end

local function getRankColor(rank)
    if rank == 1 then
        return 1.0, 0.82, 0.2
    end

    if rank == 2 then
        return 0.75, 0.8, 0.85
    end

    if rank == 3 then
        return 0.8, 0.5, 0.25
    end

    return 0.45, 0.95, 0.9
end

function online_play.load()
    if type(
        play.setResultTransitionHandler
    ) == "function"
    then
        play.setResultTransitionHandler(
            function()
                changeProgram(12)
            end
        )
    end

    play.load()

    updateFonts()
    resetState()
    if online_connect.isConnected() then
        sendPlayerInfo()
    end
end

function online_play.update(dt)
    play.update(dt)

    if not online_connect.isConnected() then
        return
    end

    local delta =
        dt or 0

    sendTimer =
        sendTimer + delta

    infoTimer =
        infoTimer + delta

    if infoTimer >= 0.5 then
        infoTimer = 0
        sendPlayerInfo()
    end

    local currentCombo = 0

    if play
        and type(play.getCombo) == "function"
    then
        local ok, value =
            pcall(play.getCombo)

        if ok then
            currentCombo =
                tonumber(value) or 0
        end
    end

    currentCombo =
        math.max(
            0,
            math.floor(currentCombo)
        )

    local id = playerID or "local"
    comboByPlayer[id] =
        currentCombo

    if currentCombo ~= lastSentCombo
        and sendTimer >= 0.1
    then
        sendTimer = 0

        lastSentCombo =
            currentCombo

        online_connect.send(
            "ONLINE_COMBO",
            id,
            currentCombo
        )
    end
end

function online_play.draw()
    play.draw()

    local width, height =
        love.graphics.getDimensions()

    local players =
        getRankedPlayers()

    local panelX = 18
    local panelY = 18

    local panelWidth =
        math.min(
            390,
            width * 0.42
        )

    local rowHeight = 72
    local avatarSize = 48

    for rank, player in ipairs(players) do
        local y =
            panelY +
            (rank - 1) *
            rowHeight

        love.graphics.setColor(
            0,
            0,
            0,
            0.5
        )

        love.graphics.rectangle(
            "fill",
            panelX,
            y,
            panelWidth,
            rowHeight - 6,
            8,
            8
        )

        local rr, gg, bb =
            getRankColor(rank)

        love.graphics.setColor(
            rr,
            gg,
            bb,
            1
        )

        love.graphics.setFont(
            rankFont or love.graphics.getFont()
        )

        local rankText =
            tostring(rank)

        love.graphics.print(
            rankText,
            panelX + 10,
            y + 18
        )

        local avatarX =
            panelX + 52

        local avatarY =
            y + 7

        local avatar = nil

        if player.avatarUrl then
            avatar = avatarCache[player.avatarUrl]
        end

        if avatar then
            local scale =
                avatarSize /
                math.max(
                    avatar:getWidth(),
                    avatar:getHeight()
                )

            love.graphics.setColor(
                1,
                1,
                1,
                1
            )

            love.graphics.draw(
                avatar,
                avatarX,
                avatarY,
                0,
                scale,
                scale
            )
        else
            love.graphics.setColor(
                0.1,
                0.1,
                0.1,
                0.8
            )

            love.graphics.rectangle(
                "fill",
                avatarX,
                avatarY,
                avatarSize,
                avatarSize,
                6,
                6
            )

            love.graphics.setColor(
                1,
                1,
                1,
                0.35
            )

            love.graphics.rectangle(
                "line",
                avatarX,
                avatarY,
                avatarSize,
                avatarSize,
                6,
                6
            )
        end

        love.graphics.setFont(
            playerFont or love.graphics.getFont()
        )

        love.graphics.setColor(
            1,
            1,
            1,
            1
        )

        love.graphics.print(
            player.name,
            avatarX + avatarSize + 10,
            y + 8
        )

        love.graphics.setFont(
            labelFont or love.graphics.getFont()
        )

        love.graphics.setColor(
            0.55,
            0.9,
            0.86,
            0.95
        )

        love.graphics.print(
            tostring(player.combo)
                .. " COMBO",
            avatarX + avatarSize + 10,
            y + 36
        )
    end

    love.graphics.setColor(
        1,
        1,
        1,
        1
    )
end

function online_play.drawOverlay()
    if play.drawOverlay then
        play.drawOverlay()
    end
end

function online_play.mousepressed(...)
    if play.mousepressed then
        play.mousepressed(...)
    end
end

function online_play.mousereleased(...)
    if play.mousereleased then
        play.mousereleased(...)
    end
end

function online_play.wheelmoved(...)
    if play.wheelmoved then
        play.wheelmoved(...)
    end
end

function online_play.keypressed(key, ...)
    if key == "escape" then
        return
    end

    if play.keypressed then
        play.keypressed(key, ...)
    end
end

function online_play.keyreleased(...)
    if play.keyreleased then
        play.keyreleased(...)
    end
end

function online_play.quit()
    if type(
        play.setResultTransitionHandler
    ) == "function"
    then
        play.setResultTransitionHandler(nil)
    end

    if play.quit then
        play.quit()
    end

    comboByPlayer = {}
    playerInfo = {}
    avatarCache = {}
end

online_connect.on(
    "packet",
    receivePacket
)

online_connect.on(
    "player_leave",
    playerLeft
)

return online_play
