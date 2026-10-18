local online_musicselect = {}

local musicselect = require("musicselect")
local online_connect = require("online_connect")
local play = require("gameplay.play")

local votes = {}
local voted = false
local deciding = false
local resultIndex = nil
local statusText = "曲を選んで決定してください"
local statusColor = {0.7, 0.85, 0.9}
local resultTimer = 0
local lotteryActive = false
local lotteryTimer = 0
local lotteryCandidates = {}
local lotteryDisplayIndex = 1
local uiFont = nil

local function setStatus(text, isError)
    statusText = text or ""
    if isError then
        statusColor = {1, 0.4, 0.4}
    else
        statusColor = {0.7, 0.85, 0.9}
    end
end

local function getVoteCount()
    local count = 0
    for _ in pairs(votes) do
        count = count + 1
    end
    return count
end

local function preparePlay(index)
    local collections = musicselect.getCollections and musicselect.getCollections()
    local chartData = type(chartreader) == "function" and chartreader() or {}
    local count = musicselect.getSelectableCount and musicselect.getSelectableCount() or 0
    if not collections or index < 1 or index > count then
        setStatus("決定された曲が見つかりません", true)
        return false
    end

    musicselect.selectedIndex = index
    musicselect.selectedDifficulty = musicselect.selectedDifficulty or "easy"
    selectindex = index
    musicname = chartData.name and chartData.name[index] or ""
    musicartist = chartData.artist and chartData.artist[index] or ""
    musicdifficulty = musicselect.selectedDifficulty
    musiclevel = musicdifficulty

    if play.setCollections and musicselect.getPlayCollections then
        play.setCollections(musicselect.getPlayCollections())
    end

    resultIndex = index
    resultTimer = 0
    deciding = true
    setStatus("決定しました: " .. tostring(musicname))
    return true
end

local function chooseResult()
    if deciding or lotteryActive then
        return
    end

    local expected = math.max(1, online_connect.getPartyCount())
    if getVoteCount() < expected then
        return
    end

    local candidates = {}
    for playerID, index in pairs(votes) do
        candidates[#candidates + 1] = {
            playerID = playerID,
            index = index
        }
    end
    if #candidates == 0 then
        return
    end

    lotteryCandidates = candidates
    lotteryActive = true
    lotteryTimer = 0
    lotteryDisplayIndex = 1
    setStatus("全員の候補から抽選中")
end

local function submitVote()
    if voted or deciding then
        return
    end

    local index = tonumber(musicselect.getSelectedIndex and musicselect.getSelectedIndex())
    local count = musicselect.getSelectableCount and musicselect.getSelectableCount() or 0
    if not index or index < 1 or index > count then
        setStatus("選択できる曲がありません", true)
        return
    end

    local playerID = online_connect.getPlayerID() or "local"
    votes[playerID] = index
    voted = true
    musicselect.selectmode = 0
    musicselect.endprocess = false
    setStatus("投票しました。全員の決定を待っています")
    online_connect.send("ONLINE_VOTE", index, playerID)
    chooseResult()
end

local function receivePacket(typeName, parts)
    if typeName == "ONLINE_VOTE" then
        local index = tonumber(parts and parts[2])
        local playerID = parts and parts[3]
        local count = musicselect.getSelectableCount and musicselect.getSelectableCount() or 0
        if index and index >= 1 and index <= count and type(playerID) == "string" and playerID ~= "" then
            votes[playerID] = index
            setStatus(string.format("投票受付: %d / %d", getVoteCount(), math.max(1, online_connect.getPartyCount())))
            chooseResult()
        end
    elseif typeName == "ONLINE_RESULT" then
        local index = tonumber(parts and parts[2])
        if index then
            lotteryActive = false
            preparePlay(index)
        end
    end
end

function online_musicselect.load()
    votes = {}
    voted = false
    deciding = false
    resultIndex = nil
    resultTimer = 0
    lotteryActive = false
    lotteryTimer = 0
    lotteryCandidates = {}
    lotteryDisplayIndex = 1
    musicselect.load()
    musicselect.onlineMode = true
    uiFont = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", math.max(16, math.floor(love.graphics.getHeight() * 0.022)))

    local playerID = online_connect.getPlayerID() or "local"
    if online_connect.getMode() == "hosting" then
        votes[playerID] = nil
        setStatus("曲を選んで決定してください。全員の投票後に抽選します")
    else
        setStatus("曲を選んで決定してください。ホストが抽選します")
    end
end

function online_musicselect.update(dt)
    musicselect.update(dt)
    if lotteryActive then
        lotteryTimer = lotteryTimer + (dt or 0)
        if #lotteryCandidates > 0 then
            lotteryDisplayIndex = (math.floor(lotteryTimer / 0.12) % #lotteryCandidates) + 1
        end

        if lotteryTimer >= 1.6 and online_connect.getMode() == "hosting" then
            local candidate = lotteryCandidates[math.random(1, #lotteryCandidates)]
            lotteryActive = false
            if preparePlay(candidate.index) then
                online_connect.send("ONLINE_RESULT", candidate.index)
            end
        end
    elseif deciding then
        resultTimer = resultTimer + (dt or 0)
        if resultTimer >= 0.6 and type(changeProgram) == "function" then
            gamestatus = string.format("%s [%s]", musicname, string.upper(musicdifficulty))
            changeProgram(11)
        end
    elseif musicselect.selectmode == 2 then
        submitVote()
    end
end

function online_musicselect.draw()
    musicselect.draw()

    local width, height = love.graphics.getDimensions()
    love.graphics.setColor(0.03, 0.05, 0.07, 0.92)
    love.graphics.rectangle("fill", width * 0.25, height * 0.91, width * 0.5, height * 0.07)
    love.graphics.setColor(statusColor[1], statusColor[2], statusColor[3], 1)
    love.graphics.setFont(uiFont or love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", 18))
    love.graphics.printf(statusText, width * 0.27, height * 0.925, width * 0.46, "center")

    if lotteryActive then
        local panelX, panelY = width * 0.2, height * 0.13
        local panelW, panelH = width * 0.6, height * 0.68
        love.graphics.setColor(0.03, 0.05, 0.07, 0.96)
        love.graphics.rectangle("fill", panelX, panelY, panelW, panelH)
        love.graphics.setColor(0.55, 0.8, 0.82, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", panelX, panelY, panelW, panelH)
        love.graphics.setFont(uiFont or love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", 18))
        love.graphics.setColor(0.82, 0.95, 0.94, 1)
        love.graphics.printf("全員の投票から抽選", panelX, panelY + 24, panelW, "center")

        local chartData = type(chartreader) == "function" and chartreader() or {}
        local rowY = panelY + 92
        for i, candidate in ipairs(lotteryCandidates) do
            local title = chartData.name and chartData.name[candidate.index] or "不明な曲"
            local active = i == lotteryDisplayIndex
            love.graphics.setColor(active and 0.55 or 0.32, active and 0.8 or 0.45, active and 0.82 or 0.58, 1)
            love.graphics.rectangle("line", panelX + 30, rowY, panelW - 60, 46)
            love.graphics.printf(string.format("%s   %s", tostring(candidate.playerID), tostring(title)), panelX + 44, rowY + 13, panelW - 88, "left")
            rowY = rowY + 58
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function online_musicselect.drawOverlay()
    if musicselect.drawOverlay then
        musicselect.drawOverlay()
    end
end

function online_musicselect.mousepressed(...)
    musicselect.mousepressed(...)
end

function online_musicselect.wheelmoved(...)
    musicselect.wheelmoved(...)
end

function online_musicselect.keypressed(...)
    local key = select(1, ...)
    if key ~= "escape" then
        musicselect.keypressed(...)
    end
end

function online_musicselect.quit()
    musicselect.quit()
end

online_connect.on("packet", receivePacket)

return online_musicselect