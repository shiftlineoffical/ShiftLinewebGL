local story = {}
local displayWidth, displayHeight = love.graphics.getDimensions()
local displayWidth, displayHeight
if love and love.graphics and type(love.graphics.getDimensions) == "function" then
    displayWidth, displayHeight = love.graphics.getDimensions()
else
    displayWidth, displayHeight = 800, 600
end
local log = require "log"
local json = require "JSON"
local i18n = require "i18n"
local ui = require "lib.ui"
local scratchsfs = require "scratchsfs"
local storyplayer = require "storyplayer"
local bluescreen = require "bluescreen"

-- UI管理
local slope = -(displayWidth / 20) / (displayHeight * 0.9)
local storyFolders = {}
local buttons = {}
local currentFolderIndex = nil
local folderMode = true
local fadeAlpha = 0
local fading = false
local fadeSpeed = 1.5

-- ストーリー再生管理
local storyData = nil
local storyLines = {}
local currentLineIndex = 0
local nextEffects = {}
local isPlayingStory = false
local selectedStory = nil
local parseStoryFile, executeEffect, getStoryTitle, getStoryTitleFromFile

local function onStoryFinish()
    isPlayingStory = false
    fading = true
    log.info("Story completed")
end

local function onStoryEffect(effect)
    executeEffect(effect)
end

-- ストーリーデータの読み込み
local function loadStories()
    storyFolders = {}

    -- scratchsfsを使用してストーリー情報を取得
    scratchsfs.load()

    local grouped = {}
    local folderOrder = {}

    if scratchsfs.path and #scratchsfs.path > 0 then
        for i = 1, #scratchsfs.path do
            local storyFile = scratchsfs.path[i]
            local storyTitle = getStoryTitleFromFile(storyFile)
            local folderName = scratchsfs.foldname and scratchsfs.foldname[i] or getStoryTitle(storyFile)

            if not grouped[folderName] then
                grouped[folderName] = {}
                folderOrder[#folderOrder + 1] = folderName
            end

            table.insert(grouped[folderName], {
                title = storyTitle,
                file = storyFile,
                folder = folderName
            })
            log.info("Loaded story: " .. storyTitle .. " from " .. storyFile)
        end

        for _, folderName in ipairs(folderOrder) do
            local entries = grouped[folderName]
            table.sort(entries, function(a, b) return a.title < b.title end)
            table.insert(storyFolders, {
                folder = folderName,
                entries = entries
            })
        end
    end

    log.info("Total story folders loaded: " .. #storyFolders)
end

local function parseStoryMetadata(content)
    local metadata = {
        title = "Untitled",
        illust = "none",
        bgm = "none"
    }

    for line in content:gmatch("[^\n]+") do
        local trimmed = line:gsub("//.*", ""):match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            if trimmed:match("^#%s+TITLE%s+") then
                metadata.title = trimmed:match("^#%s+TITLE%s+(.+)") or metadata.title
            elseif trimmed:match("^#%s+ILLUST%s+") then
                metadata.illust = trimmed:match("^#%s+ILLUST%s+(.+)") or metadata.illust
            elseif trimmed:match("^#%s+BGM%s+") then
                metadata.bgm = trimmed:match("^#%s+BGM%s+(.+)") or metadata.bgm
            end
        end
    end
    return metadata
end

local function isStoryScript(content)
    return content:find("shiftline%.") or content:find("language%.addMulti") or content:find("music%.setVolume") or content:find("%f[%w]obj%(")
end

local function parseStoryFileLines(content, metadata)
    metadata = metadata or parseStoryMetadata(content)
    local lines = {}
    local currentEffects = {}

    for line in content:gmatch("[^\n]+") do
        line = line:gsub("//.*", ""):match("^%s*(.-)%s*$")
        if line and line ~= "" then
            if line:match("^#%s+TITLE%s+") then
                metadata.title = line:match("^#%s+TITLE%s+(.+)") or metadata.title
            elseif line:match("^#%s+ILLUST%s+") then
                metadata.illust = line:match("^#%s+ILLUST%s+(.+)") or metadata.illust
            elseif line:match("^#%s+BGM%s+") then
                metadata.bgm = line:match("^#%s+BGM%s+(.+)") or metadata.bgm
            elseif line:match("^#") or line:match("^@") or line:match("^!") then
                if line:match("^@") or line:match("^!") then
                    table.insert(currentEffects, line)
                end
            else
                table.insert(lines, {
                    text = line,
                    effects = currentEffects
                })
                currentEffects = {}
            end
        end
    end

    return metadata, lines
end

-- ストーリーファイルのパーサー
parseStoryFile = function(filepath)
    local content, err = love.filesystem.read(filepath)
    if not content then
        log.error("Failed to read story file: " .. filepath .. " (" .. (err or "unknown error") .. ")")
        return nil
    end

    local metadata = parseStoryMetadata(content)
    if isStoryScript(content) then
        return {
            metadata = metadata,
            scriptSource = content,
            scriptPath = filepath
        }
    end

    local _, lines = parseStoryFileLines(content, metadata)
    return {
        metadata = metadata,
        lines = lines
    }
end

getStoryTitleFromFile = function(filepath)
    local storyInfo = parseStoryFile(filepath)
    if storyInfo and storyInfo.metadata and storyInfo.metadata.title and storyInfo.metadata.title ~= "Untitled" then
        return storyInfo.metadata.title
    end
    return getStoryTitle(filepath)
end

-- 演出コマンドの実行
executeEffect = function(effectLine)
    if effectLine:match("^@%s*illust") then
        local illust, fadeTime = effectLine:match("^@%s*illust%s+(%S+)%s*(%S*)")
        fadeTime = tonumber(fadeTime) or 1.0
        log.info("Effect: illust=" .. tostring(illust) .. ", fadeTime=" .. fadeTime)
    elseif effectLine:match("^@%s*bgm") then
        local bgm, fadeTime = effectLine:match("^@%s*bgm%s+(%S+)%s*(%S*)")
        fadeTime = tonumber(fadeTime) or 1.5
        log.info("Effect: bgm=" .. tostring(bgm) .. ", fadeTime=" .. fadeTime)
    elseif effectLine:match("^@%s*fade_in") then
        local fadeTimeStr = effectLine:match("^@%s*fade_in%s+(%S+)") or "2.0"
        local fadeTime = tonumber(fadeTimeStr) or 2.0
        log.info("Effect: fade_in, fadeTime=" .. fadeTime)
    elseif effectLine:match("^!%s*flash") then
        local durationStr = effectLine:match("^!%s*flash%s+(%S+)") or "0.1"
        local duration = tonumber(durationStr) or 0.1
        log.info("Effect: flash, duration=" .. duration)
    elseif effectLine:match("^!%s*shake") then
        local durationStr, strengthStr = effectLine:match("^!%s*shake%s+(%S+)%s+(%S+)")
        local duration = tonumber(durationStr) or 2.0
        local strength = tonumber(strengthStr) or 0.5
        log.info("Effect: shake, duration=" .. duration .. ", strength=" .. strength)
    elseif effectLine:match("^!%s*bluescreen") then
        bluescreen.start()
    end
end

getStoryTitle = function(path)
    local name = path:match("[^/\\]+$") or path
    return name:gsub("%.sfs$", "")
end

local function getCurrentFolderEntries()
    return storyFolders[currentFolderIndex] and storyFolders[currentFolderIndex].entries or {}
end

local function getCurrentFolderName()
    return storyFolders[currentFolderIndex] and storyFolders[currentFolderIndex].folder or ""
end

-- UIボタンの構築
local function getParallelogram(x1, x2, y1, y2)
    local dx = slope * (y2 - y1)
    return {
        x1, y1,
        x1 + dx, y2,
        x2 + dx, y2,
        x2, y1
    }
end

local function buildButton(x1, x2, y1, y2, text)
    return {
        poly = getParallelogram(x1, x2, y1, y2),
        x = (x1 + x2) / 2,
        y = (y1 + y2) / 2,
        text = text
    }
end

local function rebuildButtons()
    buttons = {}
    local entries = folderMode and storyFolders or getCurrentFolderEntries()
    local totalCount = #entries + 1

    -- グリッド配置: 2列×複数行
    local cols = 2
    local rows = math.max(1, math.ceil(totalCount / cols))

    local buttonWidth = displayWidth / (cols * 2.2)
    local buttonHeight = displayHeight / (rows * 2.2)
    local startX = displayWidth / 20
    local startY = displayHeight / 20

    for i = 1, totalCount do
        local col = ((i - 1) % cols)
        local row = math.floor((i - 1) / cols)
        local x1 = startX + col * (buttonWidth + displayWidth / 20)
        local x2 = x1 + buttonWidth
        local y1 = startY + row * (buttonHeight + displayHeight / 20)
        local y2 = y1 + buttonHeight

        if i == 1 then
            buttons[i] = buildButton(x1, x2, y1, y2, "Back")
            buttons[i].action = "back"
        else
            if folderMode then
                local folderData = storyFolders[i - 1]
                buttons[i] = buildButton(x1, x2, y1, y2, folderData.folder)
                buttons[i].action = "folder"
                buttons[i].folderIndex = i - 1
            else
                local entry = entries[i - 1]
                buttons[i] = buildButton(x1, x2, y1, y2, entry.title)
                buttons[i].action = "story"
                buttons[i].folderIndex = currentFolderIndex
                buttons[i].storyIndex = i - 1
                buttons[i].file = entry.file
            end
        end
    end
end

local function updateLayout(force)
    local w, h = love.graphics.getDimensions()
    if force or w ~= displayWidth or h ~= displayHeight then
        displayWidth, displayHeight = w, h
        slope = -(displayWidth / 20) / (displayHeight * 0.9)
        rebuildButtons()
    end
end

local function pointInPolygon(x, y, poly)
    if not poly or #poly < 6 then return false end
    local inside = false
    local j = #poly - 1
    
    for i = 1, #poly, 2 do
        local xi = poly[i]
        local yi = poly[i + 1]
        local xj = poly[j]
        local yj = poly[j + 1]
        
        local intersect = ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
        
        if intersect then
            inside = not inside
        end
        
        j = i
    end
    
    return inside
end

local function drawButton(button, mx, my)
    if not button or not button.poly then return end
    
    local opts = {
        hoverColor = {0.25, 0.25, 0.25},
        color = {0.1, 0.1, 0.1},
        lineColor = {1, 1, 1, 0.5},
        textColor = {1, 1, 1},
        textPadding = 36
    }
    
    if i18n.getLanguage() == "jp" then
        opts.textPadding = opts.textPadding + 20
    end
    
    ui.drawParallelogram(button.poly, button.text, love.graphics.getFont(), opts)
end

function story.load()
    log.info("Story Selector loaded")
    storyplayer.load()

    if not isPlayingStory then
        -- 選択画面の初期化
        folderMode = true
        currentFolderIndex = nil
        updateLayout(true)
        loadStories()
        rebuildButtons()
        
        fadeAlpha = 0
        fading = false
        selectedStory = nil
        story.endprocess = false
    else
        -- ストーリー再生画面の初期化
        fadeAlpha = 0
        fading = false
        currentLineIndex = 0
        story.endprocess = false
    end
    
    -- フォント設定
    local baseSize = math.max(28, math.floor(displayHeight * 0.08))
    if i18n.getLanguage() == "jp" then
        baseSize = math.max(24, math.floor(displayHeight * 0.072))
    end
    local font = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", baseSize)
    love.graphics.setFont(font)
end

function story.update(dt, extraData)
    if bluescreen.isActive() then
        bluescreen.update(dt)
        return
    end

    if storyplayer.isActive() then
        storyplayer.update(dt)
    end

    if fading then
        fadeAlpha = fadeAlpha + fadeSpeed * dt
        
        if fadeAlpha >= 1 then
            fadeAlpha = 1
            story.endprocess = true
        end
    end
end

function story.draw()
    updateLayout(false)
    
    if bluescreen.isActive() then
        bluescreen.draw()
        return
    end

    if storyplayer.isActive() then
        storyplayer.draw()
    else
        -- ストーリー選択画面
        love.graphics.setColor(0.05, 0.05, 0.05)
        love.graphics.rectangle("fill", 0, 0, displayWidth, displayHeight)
        
        love.graphics.setColor(1, 1, 1)
        if not folderMode then
            love.graphics.printf(getCurrentFolderName(), 40, 20, displayWidth - 80, "left")
        end

        local mx, my = love.mouse.getPosition()
        
        for _, button in ipairs(buttons) do
            drawButton(button, mx, my)
        end
        
        love.graphics.setColor(1, 1, 1)
    end
end

function story.drawOverlay()
    if fadeAlpha > 0 then
        love.graphics.setColor(0, 0, 0, fadeAlpha)
        love.graphics.rectangle("fill", 0, 0, displayWidth, displayHeight)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function story.keypressed(key)
    if key == "escape" then
        if storyplayer.isActive() then
            storyplayer.keypressed(key)
            return
        end

        if not folderMode then
            folderMode = true
            currentFolderIndex = nil
            rebuildButtons()
            return
        end

        if not fading then
            fading = true
            selectedStory = nil
            log.info("Return to game mode select")
        end
    elseif storyplayer.isActive() then
        storyplayer.keypressed(key)
    end
end

function story.mousepressed(x, y, button)
    updateLayout(false)
    
    if button ~= 1 then return end
    if fading then return end
    if bluescreen.isActive() then return end
    
    if storyplayer.isActive() then
        storyplayer.mousepressed(x, y, button)
        return
    end

    -- 選択画面時のボタン処理
    for _, btn in ipairs(buttons) do
        if pointInPolygon(x, y, btn.poly) then
            if btn.action == "back" then
                if not folderMode then
                    folderMode = true
                    currentFolderIndex = nil
                    rebuildButtons()
                    return
                end
                if not fading then
                    fading = true
                    selectedStory = nil
                    log.info("Return to game mode select")
                end
                return
            end

            if btn.action == "folder" then
                currentFolderIndex = btn.folderIndex
                folderMode = false
                rebuildButtons()
                return
            end

            if btn.action == "story" then
                -- ストーリーをパース
                local storyPath = btn.file
                storyData = parseStoryFile(storyPath)

                if storyData then
                    storyLines = storyData.lines
                    currentLineIndex = 0
                    isPlayingStory = true
                    storyplayer.start(storyPath, storyData, onStoryFinish, onStoryEffect)
                    log.info("Starting story: " .. storyData.metadata.title)
                else
                    log.error("Failed to parse story: " .. storyPath)
                end
                return
            end
        end
    end
end

return story
