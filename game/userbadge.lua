local userbadge = {}

local gamejolt = require "gamejolt"
local gamejoltuser = require "gamejoltuser"
local settings = require "settings"
local ui = require("lib.ui")
local okHttp, http = pcall(require, "socket.http")
if not okHttp then http = nil end

local avatarImg = nil
local avatarScale = 1
local avatarUrlLoaded = nil
local avatarUrlAttempted = nil
local badgeFont = nil

local function ensureFont()
    if not badgeFont then
        badgeFont = ui.newFont("lib/data/fonts/NotoSansJP-Light.ttf", 20)
        if not badgeFont and love and love.graphics and love.graphics.newFont then
            badgeFont = love.graphics.newFont(20)
        end
    end
end

local function getUrlExtension(url)
    if type(url) ~= "string" then return nil end
    local clean = url:gsub("#.*$", ""):gsub("%?.*$", "")
    local ext = clean:match("%.([%w]+)$")
    if not ext then return nil end
    ext = ext:lower()
    if ext == "png" or ext == "jpg" or ext == "jpeg" then
        return ext
    end
    return nil
end

local function fetchAvatarImage(url)
    if type(url) ~= "string" or url == "" then return nil end
    if not http or not http.request then return nil end

    local body, code = http.request(url)
    if code ~= 200 and code ~= "200" then return nil end
    if type(body) ~= "string" or body == "" then return nil end

    local ext = getUrlExtension(url) or "png"
    local okFile, fileData = pcall(love.filesystem.newFileData, body, "gamejolt_avatar." .. ext)
    if not okFile or not fileData then return nil end

    local okImg, imgOrErr = pcall(love.graphics.newImage, fileData)
    if not okImg then return nil end

    return imgOrErr
end

function userbadge.update(dt)
    if gamejolt.status and gamejolt.status.authenticated then
        local url = gamejolt.status.avatarUrl
        if type(url) == "string" and url ~= "" and url ~= avatarUrlLoaded and url ~= avatarUrlAttempted then
            avatarUrlAttempted = url
            avatarImg = fetchAvatarImage(url)
            if avatarImg then
                avatarScale = 40 / math.max(1, math.max(avatarImg:getWidth(), avatarImg:getHeight()))
                avatarUrlLoaded = url
            end
        end
    else
        avatarImg = nil
        avatarScale = 1
        avatarUrlLoaded = nil
        avatarUrlAttempted = nil
    end
end

function userbadge.draw()
    if not (gamejolt.status and gamejolt.status.authenticated) then return end

    local username = gamejolt.status.username
    if type(username) ~= "string" or username == "" then
        username = gamejoltuser.userid or ""
    end
    if type(username) ~= "string" or username == "" then return end

    local ratingText = ""
    local settingsData = nil
    if settings and type(settings.settingsdata) == "table" then
        settingsData = settings.settingsdata
    elseif _G and _G.settingsdata then
        settingsData = _G.settingsdata
    end

    if type(settingsData) == "table" then
        local stats = settingsData.stats
        if type(stats) == "table" then
            local rating = tonumber(stats.ratingAverage) or tonumber(stats.lastRating)
            if type(rating) == "number" and rating > 0 then
                ratingText = "  " .. string.format("%.2f", rating)
            end
        end
    end

    if ratingText == ""
        and gamejolt.memory
    then
        local remoteRating =
            tonumber(gamejolt.memory.resultRating)

        if remoteRating and remoteRating > 0 then
            ratingText =
                "  "
                .. string.format(
                    "%.2f",
                    remoteRating
                )
        end
    end

    ensureFont()
    if not badgeFont or type(badgeFont.getWidth) ~= "function" then
        return
    end

    local prevFont = love.graphics.getFont()
    local r, g, b, a = love.graphics.getColor()
    love.graphics.setFont(badgeFont)

    local iconSize = 40
    local pad = 10
    local x = 10
    local y = 10

    local displayName = username .. ratingText
    local textW = badgeFont:getWidth(displayName)
    local textH = badgeFont:getHeight()
    local bgW = iconSize + pad + textW + pad
    local bgH = iconSize

    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", x - 4, y - 4, bgW + 8, bgH + 8, 6, 6)

    if avatarImg then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(avatarImg, x, y, 0, avatarScale, avatarScale)
    else
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.rectangle("fill", x, y, iconSize, iconSize)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.rectangle("line", x, y, iconSize, iconSize)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(displayName, x + iconSize + pad, y + math.floor((iconSize - textH) / 2 + 0.5))

    love.graphics.setFont(prevFont)
    love.graphics.setColor(r, g, b, a)
end

return userbadge
