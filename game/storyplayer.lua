local storyplayer = {}
local displayWidth, displayHeight
if love and love.graphics and type(love.graphics.getDimensions) == "function" then
    displayWidth, displayHeight = love.graphics.getDimensions()
else
    displayWidth, displayHeight = 800, 600
end
local font = nil
local smallFont = nil
local active = false
local storyData = nil
local storyPath = nil
local currentLineIndex = 0
local revealProgress = 0
local revealSpeed = 90
local currentLineText = ""
local isTextComplete = false
local backgroundImage = nil
local currentBackgroundImage = nil
local finishCallback = nil
local effectCallback = nil
local scriptThread = nil
local scriptEnv = nil
local scriptWaiting = false
local scriptWaitTime = 0
local scriptSkippable = false
local scriptLanguageData = {}
local scriptObjects = {}
local scriptSprites = {}
local scriptSource = nil
local completeStory

local log = require "log"
local i18n = require "i18n"

local function initFonts()
    if not font then
        font = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", math.max(26, math.floor(displayHeight * 0.05)))
    end
    if not smallFont then
        smallFont = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", math.max(18, math.floor(displayHeight * 0.035)))
    end
end

local function setFontIfAvailable(fontValue)
    if fontValue then
        love.graphics.setFont(fontValue)
    end
end

local function maybeSetEnv(chunk, env)
    if type(setfenv) == "function" then
        setfenv(chunk, env)
        return chunk
    end
    local loaded, err = load(chunk, nil, "t", env)
    if not loaded then
        return nil, err
    end
    return loaded
end

local function createObj(name)
    local obj = {
        name = name,
        active = false,
        x = 0,
        y = 0,
        TranslateX = function(self, value)
            self.x = (tonumber(value) or 0)
        end,
        TranslateY = function(self, value)
            self.y = (tonumber(value) or 0)
        end,
        Translate = function(self, x, y)
            self.x = tonumber(x) or self.x
            self.y = tonumber(y) or self.y
        end
    }
    return obj
end

local function getScriptObject(name)
    local key = tostring(name or "")
    if key == "" then
        return createObj(key)
    end
    if not scriptObjects[key] then
        scriptObjects[key] = createObj(key)
    end
    return scriptObjects[key]
end

local function loadScriptBackground(path)
    if not path or path == "" then
        return false
    end

    local folder = storyPath and storyPath:match("^(.*)[/\\]") or ""
    local candidates = {
        path,
        folder .. "/" .. path,
        folder .. "\\" .. path
    }

    for _, candidate in ipairs(candidates) do
        if love.filesystem.getInfo(candidate) then
            local ok, image = pcall(love.graphics.newImage, candidate)
            if ok and image then
                currentBackgroundImage = image
                backgroundImage = image
                return true
            end
        end
    end
    return false
end

local function getLanguageEntry(key)
    local lang = i18n.getLanguage()
    if scriptLanguageData[lang] and scriptLanguageData[lang][key] ~= nil then
        return scriptLanguageData[lang][key]
    end
    return key
end

local function queueMessage(text)
    currentLineText = tostring(text or "")
    revealProgress = 0
    isTextComplete = false
    return coroutine.yield("message")
end

local function resumeScript()
    if not scriptThread or coroutine.status(scriptThread) == "dead" then
        return
    end

    local ok, status = coroutine.resume(scriptThread)
    if not ok then
        log.error("Story script error: " .. tostring(status))
        completeStory()
        return
    end

    if coroutine.status(scriptThread) == "dead" then
        completeStory()
        return
    end

    if status == "wait" then
        scriptWaiting = true
        return
    end

    if status == "message" then
        scriptWaiting = false
        return
    end

    -- If resumed without a known yield reason, continue running until next explicit yield or completion.
    resumeScript()
end

local function createScriptEnvironment()
    local env = {
        love = love,
        math = math,
        string = string,
        table = table,
        ipairs = ipairs,
        pairs = pairs,
        tostring = tostring,
        tonumber = tonumber,
        type = type,
        assert = assert,
        pcall = pcall,
        xpcall = xpcall,
        error = error,
        unpack = table.unpack or unpack,
        print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring(select(i, ...))
            end
            log.info(table.concat(parts, "\t"))
        end,
        language = {
            addMulti = function(data)
                if type(data) ~= "table" then
                    return
                end
                for lang, entries in pairs(data) do
                    if type(lang) == "string" and type(entries) == "table" then
                        scriptLanguageData[lang] = scriptLanguageData[lang] or {}
                        for k, v in pairs(entries) do
                            scriptLanguageData[lang][k] = v
                        end
                    end
                end
            end,
            get = function(key)
                return getLanguageEntry(key)
            end
        },
        music = {
            setVolume = function(volume)
                love.audio.setVolume(math.max(0, math.min(1, tonumber(volume) or 0)))
            end
        },
        shiftline = {
            AddBackground = function(id, text, image)
                return true
            end,
            AddPlace = function(bgId, placeId, displayName, x, y)
                return true
            end,
            AddStory = function(placeId, storyId, chapter, title, path, prereq, condA, condB)
                return true
            end,
            AddSeries = function(seriesId, seriesName, entries)
                return true
            end,
            message = function(text)
                return queueMessage(text)
            end,
            run = function(fn)
                if type(fn) == "function" then
                    local ok, err = pcall(fn)
                    if not ok then
                        log.error("shiftline.run error: " .. tostring(err))
                    end
                end
            end,
            wait = function(seconds)
                scriptWaitTime = tonumber(seconds) or 0
                scriptWaiting = true
                return coroutine.yield("wait")
            end,
            fade = function(duration)
                log.info("shiftline.fade(" .. tostring(duration) .. ")")
            end,
            setSkippable = function(flag)
                scriptSkippable = not not flag
            end,
            setBackground = function(path)
                if not path then
                    return
                end
                if not loadScriptBackground(path) then
                    log.warn("shiftline.setBackground failed to load: " .. tostring(path))
                end
            end,
            setFace = function(face)
                log.info("shiftline.setFace(" .. tostring(face) .. ")")
            end,
            bounce = function(value)
                log.info("shiftline.bounce(" .. tostring(value) .. ")")
            end,
            playKBM = function(...)
                log.info("shiftline.playKBM called")
                if type(changeProgram) == "function" then
                    changeProgram(4)
                end
            end,
            getLastResult = function()
                return rawget(_G, "lastResult")
            end,
            sprite = {
                load = function(path)
                    if not path then
                        return false
                    end
                    local folder = storyPath and storyPath:match("^(.*)[/\\]") or ""
                    local candidates = {
                        path,
                        folder .. "/" .. path,
                        folder .. "\\" .. path
                    }
                    for _, candidate in ipairs(candidates) do
                        if love.filesystem.getInfo(candidate) then
                            local ok, image = pcall(love.graphics.newImage, candidate)
                            if ok and image then
                                scriptSprites[path] = image
                                return true
                            end
                        end
                    end
                    return false
                end,
                create = function(name)
                    return getScriptObject(name)
                end,
                get = function(path)
                    return scriptSprites[path]
                end
            },
            addCharacterSync = function(...) end,
            setCharacterSync = function(...) end,
            showNewSongModal = function(text)
                return queueMessage(tostring(text or "New song unlocked"))
            end,
            endstory = function()
                completeStory()
            end
        },
        obj = createObj
    }

    setmetatable(env, { __index = _G })
    return env
end

local function updateLayout()
    local w, h = love.graphics.getDimensions()
    if w ~= displayWidth or h ~= displayHeight then
        displayWidth, displayHeight = w, h
        font = nil
        smallFont = nil
        initFonts()
    end
end

local function loadBackgroundImage()
    backgroundImage = nil
    if currentBackgroundImage then
        backgroundImage = currentBackgroundImage
        return
    end

    if not storyData or not storyPath then
        return
    end

    local illust = storyData.metadata and storyData.metadata.illust
    if not illust or illust == "" or illust == "none" then
        return
    end

    local folder = storyPath:match("^(.*)[/\\]") or ""
    local candidates = {
        illust,
        folder .. "/" .. illust,
        folder .. "\\" .. illust
    }

    for _, path in ipairs(candidates) do
        if love.filesystem.getInfo(path) then
            local ok, image = pcall(love.graphics.newImage, path)
            if ok and image then
                backgroundImage = image
                return
            end
        end
    end
end

completeStory = function()
    active = false
    if finishCallback then
        finishCallback()
    end
end

local function setCurrentLine(index)
    currentLineIndex = index
    revealProgress = 0
    isTextComplete = false
    local lineData = storyData and storyData.lines and storyData.lines[index]
    currentLineText = lineData and lineData.text or ""

    if effectCallback and lineData and lineData.effects then
        for _, effect in ipairs(lineData.effects) do
            effectCallback(effect)
        end
    end
end

function storyplayer.load()
    initFonts()
end

function storyplayer.start(path, data, onFinish, onEffect)
    storyPath = path
    storyData = data
    finishCallback = onFinish
    effectCallback = onEffect
    active = true
    scriptThread = nil
    scriptEnv = nil
    scriptWaiting = false
    scriptWaitTime = 0
    scriptSkippable = false
    scriptLanguageData = {}
    scriptObjects = {}
    scriptSprites = {}
    scriptSource = nil
    currentBackgroundImage = nil

    updateLayout()
    initFonts()
    loadBackgroundImage()

    if storyData and storyData.scriptSource then
        scriptSource = storyData.scriptSource
        scriptEnv = createScriptEnvironment()
        local chunk, err
        if type(load) == "function" then
            chunk, err = load(scriptSource, "@" .. storyPath, "t", scriptEnv)
        end
        if not chunk and type(loadstring) == "function" then
            local loaded, loadErr = loadstring(scriptSource, "@" .. storyPath)
            if loaded then
                chunk, err = maybeSetEnv(loaded, scriptEnv)
            else
                err = loadErr
            end
        end
        if not chunk then
            log.error("Invalid story script: " .. tostring(err))
            completeStory()
            return
        end

        local function scriptMain()
            local ok, err2 = pcall(chunk)
            if not ok then
                log.error("Story script runtime error: " .. tostring(err2))
            end
        end

        scriptThread = coroutine.create(scriptMain)
        resumeScript()
    elseif storyData and storyData.lines and #storyData.lines > 0 then
        setCurrentLine(1)
    else
        completeStory()
    end
end

function storyplayer.isActive()
    return active
end

function storyplayer.update(dt)
    if not active then
        return
    end

    if scriptThread then
        if scriptWaiting then
            if scriptWaitTime > 0 then
                scriptWaitTime = scriptWaitTime - dt
                if scriptWaitTime <= 0 then
                    scriptWaiting = false
                    resumeScript()
                end
            end
            return
        end

        if coroutine.status(scriptThread) == "dead" then
            completeStory()
            return
        end
    end

    if not isTextComplete then
        revealProgress = revealProgress + revealSpeed * dt
        if revealProgress >= #currentLineText then
            revealProgress = #currentLineText
            isTextComplete = true
        end
    end
end

local function visibleText()
    local count = math.floor(revealProgress)
    if count < 1 then
        return ""
    end
    local text = currentLineText:sub(1, count)
    -- UTF-8デコーディングエラーを防ぐため、不完全なUTF-8シーケンスを削除
    while #text > 0 do
        local ok = pcall(function()
            -- UTF-8検証：printf前に正しいかチェック
            local _ = text:byte(#text)
        end)
        if ok then
            break
        end
        text = text:sub(1, -2)  -- 最後の1文字を削除
    end
    return text
end

local function drawBackground()
    if backgroundImage then
        local iw, ih = backgroundImage:getDimensions()
        local scale = math.max(displayWidth / iw, displayHeight / ih)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(backgroundImage, 0, 0, 0, scale, scale)
    else
        love.graphics.setColor(0.08, 0.08, 0.12)
        love.graphics.rectangle("fill", 0, 0, displayWidth, displayHeight)
        for y = 0, displayHeight, 60 do
            love.graphics.setColor(1, 1, 1, 0.02)
            love.graphics.rectangle("fill", 0, y, displayWidth, 40)
        end
    end

    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, 0, displayWidth, displayHeight)
end

local function drawTextFrame(x, y, w, h)
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", x, y, w, h, 14, 14)
    love.graphics.setColor(1, 1, 1, 0.16)
    love.graphics.rectangle("line", x, y, w, h, 14, 14)
end

local function drawStoryLine()
    local visible = visibleText()

    -- 対応フォーマット:
    -- 1) 名前>>セリフ  (例: ルナ>>おはよう)
    -- 2) >>セリフ      (名前なしの会話)
    -- 3) 名前「セリフ」(旧形式)
    local arrowName, arrowText = currentLineText:match("^(.-)>>%s*(.*)$")
    local charName, dialogue
    if arrowText and arrowText ~= "" then
        local nameTrim = arrowName and arrowName:match("^%s*(.-)%s*$") or ""
        if nameTrim == "" then
            charName = nil
        else
            charName = nameTrim
        end
        dialogue = arrowText
    else
        charName, dialogue = currentLineText:match("^(.-)「(.*)」$")
    end

    -- "ナレーション" ラベルの場合は会話扱いにしない
    if charName then
        local nameTrim = charName:match("^%s*(.-)%s*$") or ""
        local isNarrationLabel = (nameTrim == "ナレーション" or nameTrim == "Narration" or nameTrim == "narration")
        if isNarrationLabel then
            charName = nil
            dialogue = nil
        end
    end

    if dialogue and dialogue ~= "" then
        local visibleDialogue = dialogue:sub(1, math.min(math.floor(revealProgress), #dialogue))
        local boxHeight = displayHeight * 0.32
        local x = 40
        local y = displayHeight - boxHeight - 40
        local w = displayWidth - 80
        drawTextFrame(x, y, w, boxHeight)

        if charName then
            setFontIfAvailable(font)
            love.graphics.setColor(0.8, 0.95, 1)
            love.graphics.printf(charName, x + 28, y + 22, w - 56, "left")
        end

        setFontIfAvailable(smallFont)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(visibleDialogue, x + 28, y + 58, w - 56, "left")

        love.graphics.setColor(0.75, 0.75, 0.8)
        love.graphics.printf("Press Space/Enter to continue", x + 28, y + boxHeight - 34, w - 56, "right")
    else
        local boxHeight = displayHeight * 0.38
        local x = 60
        local y = displayHeight * 0.45 - 20
        local w = displayWidth - 120
        drawTextFrame(x, y, w, boxHeight)

        setFontIfAvailable(font)
        love.graphics.setColor(1, 1, 0.95)
        love.graphics.printf(visible, x + 30, y + 24, w - 60, "left")

        setFontIfAvailable(smallFont)
        love.graphics.setColor(0.75, 0.75, 0.85)
        love.graphics.printf("Press Space/Enter to continue", x + 30, y + boxHeight - 34, w - 60, "right")
    end
end

function storyplayer.draw()
    if not active then
        return
    end

    updateLayout()
    initFonts()
    if not storyData then
        completeStory()
        return
    end
    drawBackground()

    setFontIfAvailable(smallFont)
    love.graphics.setColor(0.85, 0.85, 0.85)
    local metadata = storyData.metadata or {}
    love.graphics.printf(metadata.title or "Story", 40, 30, displayWidth - 80, "left")

    local totalLines = storyData.lines and #storyData.lines or 0
    local lineLabel = storyData.scriptSource and "Script" or string.format("%d / %d", currentLineIndex, totalLines)
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf(lineLabel, 40, 64, displayWidth - 80, "left")

    drawStoryLine()
end

function storyplayer.advance()
    if not active then
        return
    end

    if scriptThread then
        if isTextComplete then
            resumeScript()
        else
            revealProgress = #currentLineText
            isTextComplete = true
        end
        return
    end

    if not isTextComplete then
        revealProgress = #currentLineText
        isTextComplete = true
        return
    end

    if storyData and currentLineIndex < #storyData.lines then
        setCurrentLine(currentLineIndex + 1)
    else
        completeStory()
    end
end

function storyplayer.keypressed(key)
    if not active then
        return
    end

    if key == "escape" then
        completeStory()
        return
    end

    if key == "space" or key == "return" then
        storyplayer.advance()
    end
end

function storyplayer.mousepressed(x, y, button)
    if not active or button ~= 1 then
        return
    end

    storyplayer.advance()
end

return storyplayer
