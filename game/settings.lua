local _G = _G
local love = love
local string = string
local table = table
local math = math
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local type = type
local string_format = string.format
local table_insert = table.insert
local table_remove = table.remove
local table_concat = table.concat
local math_floor = math.floor
local math_max = math.max
local math_min = math.min





local settings = {}

local utf8 = require("utf8")
local log = require("log")
local gamejolt = require("gamejolt")
local discordSDK = require("lib.SDK")
local JSON = require("JSON")
local ui = require("lib.ui")
local settingsApi = require("settings.settings_api")
local coreWindow = require("core.window")
local reportTransport = require "report_transport"

local displayWidth, displayHeight = love.graphics.getDimensions()

local function isCloudoampUser()
    return gamejolt.status and gamejolt.status.authenticated and gamejolt.status.username == "cloudoamp"
end

local categoryColors = {
    {0.75, 0.75, 0.75},
    {0.75, 0.75, 0.75},
    {0.75, 0.75, 0.75},
    {0.75, 0.75, 0.75},
    {0.75, 0.75, 0.75},
    {0.75, 0.75, 0.75}
}

local linkdata = {
    shiftline = "https://shiftline.gt.tc",
    gamepage = "https://gamejolt.com/games/shiftline/1053992",
    twitter = "https://x.com/shiftline_offi"
}

-- Basic settings UI metadata.
selectedIndex = 1
selectedFieldIndex = 1
keyConfigSelectedIndex = 1
keyConfigWaitingForKey = false
keyConfigTargetField = nil
keyConfigReturnIndex = 4

-- Feedback form state
local feedbackSubject = ""
local feedbackBody = ""
local feedbackStatus = nil -- nil, "sending", "sent", "error"
local feedbackStatusTime = 0
local feedbackFocusedField = 1 -- 1 = subject, 2 = body
local feedbackTextInputEnabled = false
local feedbackActiveInputField = nil
local feedbackCompositionField = nil
local feedbackCompositionText = ""
local BACKSPACE_REPEAT_DELAY = 0.4
local BACKSPACE_REPEAT_INTERVAL = 0.05
local backspaceWasDown = false
local backspaceHoldTime = 0
local backspaceRepeatTimer = 0

local function updateFeedbackTextInput()
    local activeField = selectedIndex == 6
        and (feedbackFocusedField == 1 or feedbackFocusedField == 2)
        and feedbackFocusedField
        or nil
    if activeField ~= feedbackActiveInputField then
        feedbackActiveInputField = activeField
        feedbackCompositionField = nil
        feedbackCompositionText = ""
    end

    local shouldEnable = activeField ~= nil
    if shouldEnable == feedbackTextInputEnabled then
        return
    end

    feedbackTextInputEnabled = shouldEnable
    if love.keyboard and love.keyboard.setTextInput then
        love.keyboard.setTextInput(shouldEnable)
    end
end

local categories = {"display", "audio", "misc", "play", "key", "feedback"}

local settingFields = {
    {"displaySize", "displayMode", "vsync"},
    {"masterVolume", "musicVolume", "sfxVolume"},
    {"language", "timeout", "defaultLevel", "discordAccount"},
    {"moveSpeed", "timing", "playLogSave", "showFPS"},
    {"leftone", "lefttwo", "lefttree", "rightone", "righttwo", "righttree"},
    {"feedbackSubject", "feedbackBody", "feedbackSend"}
}

local displayResolutions = {
    {1280, 720},
    {1600, 900},
    {1920, 1080}
}

local localeTexts = {
    jp = {
        title = "設定",
        categories = {"表示", "音声", "その他", "プレイ", "キー", "要望"},
        displaySize = "解像度",
        displayMode = "表示モード",
        vsync = "垂直同期",
        fullscreen = "フルスクリーン",
        windowed = "ウィンドウ",
        masterVolume = "全体音量",
        musicVolume = "BGM音量",
        sfxVolume = "SFX音量",
        language = "言語",
        timeout = "タイムアウト",
        defaultLevel = "デフォルト難易度",
        discordAccount = "Discord連携",
        discordConnect = "接続する",
        discordConnected = "接続済み（Enterで解除）",
        discordConnecting = "接続中...",
        discordFailed = "接続失敗（Enterで再試行）",
        discordUnavailable = "利用不可",
        discordAccountHelp = "EnterまたはクリックでDiscord連携。接続済みなら解除します。",
        moveSpeed = "移動速度",
        timing = "タイミング",
        playLogSave = "プレイログ保存",
        showFPS = "FPS表示",
        website = "ウェブサイト",
        gamepage = "ゲームページ",
        twitter = "X(Twitter)",
        feedbackSubject = "件名",
        feedbackBody = "本文",
        feedbackSend = "送信",
        feedbackSending = "送信中...",
        feedbackSent = "フィードバックを送信しました",
        feedbackError = "送信に失敗しました",
        moveup = "上移動",
        movedown = "下移動",
        moveleft = "左移動",
        moveright = "右移動",
        leftone = "左1",
        lefttwo = "左2",
        lefttree = "左3",
        rightone = "右1",
        righttwo = "右2",
        righttree = "右3",
        pause = "ポーズ",
        helpText = "上下/左右で選択、ホイールで調整、Enterで保存",
        openLinkHelp = "リンクを開くにはクリック",
        keyConfigHelp = "Enterまたはクリックでキーを割り当て、Escでキャンセル",
        keyConfigTitle = "キーバインド設定",
        keyConfigPrompt = "レーンを選んでキーを押してください",
        keyConfigWaiting = "入力待ち...",
        booleanOn = "ON",
        booleanOff = "OFF",
        languageName = {jp = "日本語", en = "English"},
        levelName = {easy = "easy", normal = "normal", hard = "hard", extra = "extra"}
    },
    en = {
        title = "Settings",
        categories = {"Display", "Audio", "Misc", "Play", "Key", "Feedback"},
        displaySize = "Display Size",
        displayMode = "Display Mode",
        vsync = "VSync",
        fullscreen = "Fullscreen",
        windowed = "Windowed",
        masterVolume = "Master Volume",
        musicVolume = "Music Volume",
        sfxVolume = "SFX Volume",
        language = "Language",
        timeout = "Timeout",
        defaultLevel = "Default Level",
        discordAccount = "Discord Account",
        discordConnect = "Connect Discord",
        discordConnected = "Connected (Enter to disconnect)",
        discordConnecting = "Connecting...",
        discordFailed = "Connection failed (Enter to retry)",
        discordUnavailable = "Unavailable",
        discordAccountHelp = "Press Enter or click to connect. Disconnects when already connected.",
        moveSpeed = "Move Speed",
        timing = "Timing",
        playLogSave = "Play Log Save",
        showFPS = "Show FPS",
        website = "Website",
        gamepage = "Gamepage",
        twitter = "Twitter",
        feedbackSubject = "Subject",
        feedbackBody = "Body",
        feedbackSend = "Send",
        feedbackSending = "Sending...",
        feedbackSent = "Feedback sent",
        feedbackError = "Failed to send",
        moveup = "Move Up",
        movedown = "Move Down",
        moveleft = "Move Left",
        moveright = "Move Right",
        leftone = "Left 1",
        lefttwo = "Left 2",
        lefttree = "Left 3",
        rightone = "Right 1",
        righttwo = "Right 2",
        righttree = "Right 3",
        pause = "Pause",
        helpText = "Click/UpDown/LeftRight to select, wheel to adjust, Enter/click to save",
        openLinkHelp = "Click to open link",
        keyConfigHelp = "Press Enter or click to assign a key, Esc cancels",
        keyConfigTitle = "Key Bind Config",
        keyConfigPrompt = "Select a lane and press a key",
        keyConfigWaiting = "Waiting for input...",
        booleanOn = "On",
        booleanOff = "Off",
        languageName = {jp = "日本語", en = "English"},
        levelName = {easy = "Easy", normal = "Normal", hard = "Hard", extra = "Extra"}
    }
}

local function clamp(value, minValue, maxValue)
    return math_max(minValue, math_min(maxValue, value))
end

local function drawAlignedText(text, x, y, boxWidth, boxHeight, fontObj, align)
    local f = fontObj or font
    local width = boxWidth or f:getWidth(tostring(text))
    local height = boxHeight or f:getHeight()
    local textY = y + math_max(0, (height - f:getHeight()) * 0.5)
    love.graphics.printf(tostring(text), x, textY, width, align or "left")
end

local layout = {
    leftWidth = 320,
    rightX = 360,
    lineHeight = 60,
    spacing = 18,
    padding = 28
}
local slope = -0.02

local function updateLayout()
    displayWidth, displayHeight = love.graphics.getDimensions()
    layout.padding = math_max(displayWidth * 0.03, 16)
    layout.leftWidth = displayWidth * 0.24
    layout.rightX = layout.leftWidth + layout.padding
    layout.lineHeight = math_max(displayHeight * 0.075, 40)
    layout.spacing = math_max(displayHeight * 0.028, 10)
    layout.panelY = layout.padding + displayHeight * 0.05
    layout.panelH = displayHeight - layout.panelY - layout.padding
    slope = -(displayWidth / 20) / (displayHeight * 0.9)
end

local function refreshFonts()
    local titleSize = math_max(48, math_floor(displayHeight * 0.085))
    local subtitleSize = math_max(34, math_floor(displayHeight * 0.055))
    local bodySize = math_max(24, math_floor(displayHeight * 0.038))
    Titlefont = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", titleSize)
    Subtitlefont = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", subtitleSize)
    font = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", bodySize)
    FeedbackTitlefont = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", math_max(32, math_floor(displayHeight * 0.06)))
    Feedbackfont = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", math_max(20, math_floor(displayHeight * 0.03)))
end

local function getLocaleText(key)
    local lang = settingsdata and settingsdata.miscsettings and settingsdata.miscsettings.language or "jp"
    local locale = localeTexts[lang] or localeTexts.jp
    return locale[key] or key
end

local function getBooleanText(value)
    if value then
        return getLocaleText("booleanOn")
    end
    return getLocaleText("booleanOff")
end

local function removeLastUTF8Char(text)
    if type(text) ~= "string" or text == "" then
        return ""
    end

    local byteStart = utf8.offset(text, -1)
    if byteStart then
        return text:sub(1, byteStart - 1)
    end

    return ""
end

local function wrapFeedbackText(text, maxWidth)
    local lines = {}
    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for _, codepoint in utf8.codes(paragraph) do
            local character = utf8.char(codepoint)
            if line ~= "" and font:getWidth(line .. character) > maxWidth then
                table_insert(lines, line)
                line = character
            else
                line = line .. character
            end
        end
        table_insert(lines, line)
    end
    return table_concat(lines, "\n")
end

local function drawFeedbackText(text, composition, x, y, maxWidth)
    local fullText = text .. composition
    love.graphics.printf(
        wrapFeedbackText(fullText, maxWidth),
        x,
        y,
        maxWidth,
        "left"
    )

    if composition == "" then
        return
    end

    local wrappedText = wrapFeedbackText(text, maxWidth)
    local currentLine = wrappedText:match("[^\n]*$") or ""
    local lineIndex = 0
    for _ in wrappedText:gmatch("\n") do
        lineIndex = lineIndex + 1
    end

    local compositionStartWidth = nil
    local compositionEndWidth = nil
    local lineHeight = love.graphics.getFont():getHeight()
    local function drawUnderline()
        if compositionStartWidth and compositionEndWidth > compositionStartWidth then
            local underlineY = y + lineIndex * lineHeight + lineHeight - 2
            love.graphics.line(
                x + compositionStartWidth,
                underlineY,
                x + compositionEndWidth,
                underlineY
            )
        end
        compositionStartWidth = nil
        compositionEndWidth = nil
    end

    for _, codepoint in utf8.codes(composition) do
        local character = utf8.char(codepoint)
        if character == "\n" then
            drawUnderline()
            lineIndex = lineIndex + 1
            currentLine = ""
        else
            if currentLine ~= ""
                and font:getWidth(currentLine .. character) > maxWidth then
                drawUnderline()
                lineIndex = lineIndex + 1
                currentLine = ""
            end

            if not compositionStartWidth then
                compositionStartWidth = font:getWidth(currentLine)
            end
            currentLine = currentLine .. character
            compositionEndWidth = font:getWidth(currentLine)
        end
    end
    drawUnderline()
end

local function getDefaultLevelText(value)
    local lang = settingsdata and settingsdata.miscsettings and settingsdata.miscsettings.language or "jp"
    local locale = localeTexts[lang] or localeTexts.jp
    return locale.levelName[value] or value
end

local function findResolutionIndex(size)
    for i, res in ipairs(displayResolutions) do
        if size[1] == res[1] and size[2] == res[2] then
            return i
        end
    end
    return 1
end

local function getCurrentFieldCount()
    return #settingFields[selectedIndex]
end

local function isAdjustableField(fieldName)
    return fieldName ~= "discordAccount"
end

local function activateDiscordAccount()
    local state = discordSDK.getAuthState()
    if state == "ready" then
        discordSDK.logout()
    elseif state ~= "authorizing" and state ~= "authenticating" and state ~= "connecting" then
        discordSDK.authorize()
    end
end

local function drawMenuItem(y, label, isSelected)
    love.graphics.setColor(isSelected and {1, 0.9, 0.4} or {1, 1, 1})
    love.graphics.print(label, 40, y)
end

local function getSettingValue(key)
    if key == "displaySize" then
        local size = settingsdata.displaysettings.displaysize
        return tostring(size[1]) .. "x" .. tostring(size[2])
    elseif key == "displayMode" then
        return getLocaleText(settingsdata.displaysettings.displaymode)
    elseif key == "vsync" then
        return getBooleanText(settingsdata.displaysettings.vsync)
    elseif key == "masterVolume" then
        return string_format("%.1f", settingsdata.audiosettings.mastervolume)
    elseif key == "musicVolume" then
        return string_format("%.1f", settingsdata.audiosettings.musicvolume)
    elseif key == "sfxVolume" then
        return string_format("%.1f", settingsdata.audiosettings.sfxvolume)
    elseif key == "language" then
        local lang = settingsdata.miscsettings.language or "jp"
        return getLocaleText("languageName")[lang]
    elseif key == "timeout" then
        return tostring(settingsdata.miscsettings.timeout)
    elseif key == "defaultLevel" then
        return getDefaultLevelText(settingsdata.miscsettings.defoltlevel)
    elseif key == "discordAccount" then
        local state = discordSDK.getAuthState()
        if state == "ready" then
            return getLocaleText("discordConnected")
        elseif state == "authorizing" or state == "authenticating" or state == "connecting" then
            return getLocaleText("discordConnecting")
        elseif state == "failed" then
            return getLocaleText("discordFailed")
        elseif state == "unavailable" then
            return getLocaleText("discordUnavailable")
        end
        return getLocaleText("discordConnect")
    elseif key == "moveSpeed" then
        return string_format("%.1f", settingsdata.playsettings.movespead)
    elseif key == "timing" then
        return tostring(settingsdata.playsettings.timing)
    elseif key == "playLogSave" then
        return getBooleanText(settingsdata.playsettings.playlogsave)
    elseif key == "showFPS" then
        return getBooleanText(settingsdata.playsettings.showfps)
    elseif key == "website" then
        return linkdata.shiftline
    elseif key == "gamepage" then
        return linkdata.gamepage
    elseif key == "twitter" then
        return linkdata.twitter
    elseif key == "moveup" or key == "movedown" or key == "moveleft" or key == "moveright" or key == "leftone" or key == "lefttwo" or key == "lefttree" or key == "rightone" or key == "righttwo" or key == "righttree" or key == "pause" then
        return settingsdata.keysettings[key]
    end
    return ""
end

local keyConfigItemOrder = {"moveup", "movedown", "moveleft", "moveright", "leftone", "lefttwo", "lefttree", "rightone", "righttwo", "righttree"}

local function getKeyConfigFieldName(index)
    return keyConfigItemOrder[index]
end

local function normalizeKeyBindingName(key, scancode)
    if type(key) == "string" and key ~= "" then
        local normalized = key:lower()
        if normalized == " " then
            return "space"
        end
        return normalized
    end
    if type(scancode) == "string" and scancode ~= "" then
        return scancode:lower()
    end
    return nil
end

local function beginKeyBinding(itemIndex)
    keyConfigSelectedIndex = itemIndex
    keyConfigWaitingForKey = true
    keyConfigTargetField = getKeyConfigFieldName(itemIndex)
end

local function getKeyConfigItemRect(index)
    local laneGap = math_max(16, displayWidth * 0.018)
    local isDirectionItem = index <= 4
    local itemCount = isDirectionItem and 4 or 6
    local itemWidth = (displayWidth - layout.padding * 2 - laneGap * (itemCount - 1)) / itemCount
    local itemHeight = math_max(92, displayHeight * 0.16)
    local rowY = displayHeight * 0.18
    if not isDirectionItem then
        rowY = displayHeight * 0.36
    end
    local x = layout.padding + (index - 1) * (itemWidth + laneGap)
    if not isDirectionItem then
        x = layout.padding + (index - 5) * (itemWidth + laneGap)
    end
    return x, rowY, itemWidth, itemHeight
end

local function drawKeyConfigScreen()
    love.graphics.setFont(Subtitlefont)
    love.graphics.setColor(1, 1, 1, 0.95)
    local titleText = tostring(getLocaleText("keyConfigTitle"))
    love.graphics.print(titleText, displayWidth / 2 - Subtitlefont:getWidth(titleText) / 2, layout.padding)

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, 0.8)
    local promptText = tostring(getLocaleText("keyConfigPrompt"))
    love.graphics.printf(promptText, layout.padding, layout.padding + 46, displayWidth - layout.padding * 2, "center")

    love.graphics.setColor(1, 1, 1, 0.65)
    love.graphics.printf("Esc: back", layout.padding, layout.padding + 82, displayWidth - layout.padding * 2, "center")

    for itemIndex = 1, #keyConfigItemOrder do
        local x, y, w, h = getKeyConfigItemRect(itemIndex)
        local fieldName = getKeyConfigFieldName(itemIndex)
        local isSelected = keyConfigSelectedIndex == itemIndex
        local isWaiting = keyConfigWaitingForKey and keyConfigTargetField == fieldName
        local poly = ui.parallelogramPoly(x, x + w, y, y + h, slope)
        local color = isSelected and {0.20, 0.20, 0.20, 0.96} or {0.10, 0.10, 0.10, 0.92}
        local lineColor = isSelected and {1, 1, 1, 0.18} or {1, 1, 1, 0.08}
        if isWaiting then
            color = {0.18, 0.18, 0.18, 0.98}
            lineColor = {1, 1, 1, 0.28}
        end
        ui.drawParallelogram(poly, "", font, {
            color = color,
            lineColor = lineColor,
            textPadding = 12,
            textColor = {1, 1, 1, 1}
        })

        love.graphics.setColor(1, 1, 1, 0.95)
        drawAlignedText(getLocaleText(fieldName), x + 12, y, w - 24, h, font, "left")

        local keyValue = tostring(getSettingValue(fieldName))
        love.graphics.setColor(1, 1, 1, 0.82)
        drawAlignedText(keyValue ~= "" and keyValue or "?", x + 12, y, w - 24, h, font, "center")

        if isWaiting then
            love.graphics.setColor(1, 0.92, 0.5, 0.9)
            drawAlignedText(getLocaleText("keyConfigWaiting"), x + 12, y, w - 24, h, font, "center")
        end
    end

    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf(getLocaleText("keyConfigHelp"), layout.padding, displayHeight - font:getHeight() * 2, displayWidth - layout.padding * 2, "center")
end

local function drawSettingLine(y, label, value, isSelected)
    love.graphics.setColor(isSelected and {1, 0.9, 0.4} or {1, 1, 1})
    love.graphics.print(label .. ": " .. tostring(value), displayWidth/2, y)
end

local function adjustCurrentSetting(amount)
    if selectedIndex == 1 then
        if selectedFieldIndex == 1 then
            local current = findResolutionIndex(settingsdata.displaysettings.displaysize)
            current = clamp(current + amount, 1, #displayResolutions)
            settingsdata.displaysettings.displaysize = {displayResolutions[current][1], displayResolutions[current][2]}
        elseif selectedFieldIndex == 2 then
            local modes = {"fullscreen", "windowed"}
            local current = 1
            for i, v in ipairs(modes) do
                if v == settingsdata.displaysettings.displaymode then
                    current = i
                    break
                end
            end
            current = clamp(current + amount, 1, #modes)
            settingsdata.displaysettings.displaymode = modes[current]
        elseif selectedFieldIndex == 3 then
            settingsdata.displaysettings.vsync = not settingsdata.displaysettings.vsync
        end
        settings.applyDisplaySettings()
    elseif selectedIndex == 2 then
        if selectedFieldIndex == 1 then
            settingsdata.audiosettings.mastervolume = clamp(settingsdata.audiosettings.mastervolume + amount * 0.1, 0.0, 1.0)
        elseif selectedFieldIndex == 2 then
            settingsdata.audiosettings.musicvolume = clamp(settingsdata.audiosettings.musicvolume + amount * 0.1, 0.0, 1.0)
        elseif selectedFieldIndex == 3 then
            settingsdata.audiosettings.sfxvolume = clamp(settingsdata.audiosettings.sfxvolume + amount * 0.1, 0.0, 1.0)
        end
        settings.applyAudioSettings()
    elseif selectedIndex == 3 then
        if selectedFieldIndex == 1 then
            local languages = {"jp", "en"}
            local current = 1
            for i, v in ipairs(languages) do
                if v == settingsdata.miscsettings.language then
                    current = i
                    break
                end
            end
            current = clamp(current + amount, 1, #languages)
            settingsdata.miscsettings.language = languages[current]
        elseif selectedFieldIndex == 2 then
            settingsdata.miscsettings.timeout = clamp(settingsdata.miscsettings.timeout + amount * 5, 5, 120)
        elseif selectedFieldIndex == 3 then
            local levels = {"easy", "normal", "hard", "extra"}
            local current = 1
            for i, v in ipairs(levels) do
                if v == settingsdata.miscsettings.defoltlevel then
                    current = i
                    break
                end
            end
            current = clamp(current + amount, 1, #levels)
            settingsdata.miscsettings.defoltlevel = levels[current]
        end
    elseif selectedIndex == 4 then
        if selectedFieldIndex == 1 then
            settingsdata.playsettings.movespead = clamp(settingsdata.playsettings.movespead + amount * 0.1, 0.5, 3.0)
        elseif selectedFieldIndex == 2 then
            settingsdata.playsettings.timing = clamp(settingsdata.playsettings.timing + amount, -100, 100)
        elseif selectedFieldIndex == 3 then
            settingsdata.playsettings.playlogsave = not settingsdata.playsettings.playlogsave
        elseif selectedFieldIndex == 4 then
            settingsdata.playsettings.showfps = not settingsdata.playsettings.showfps
        end
    elseif selectedIndex == 5 then
        return
    end

    settings.save()
end

settingsdata={
    displaysettings={
    displaysize = {displayWidth, displayHeight},
    displaymode = "fullscreen",
    vsync = true,
    },


    audiosettings={
        mastervolume = 1.0,
        musicvolume = 1.0,
        sfxvolume = 1.0,
        EQsettings = {
            bass = 1,
            mid = 1,
            treble = 1
        },
    },

    keysettings={
        moveup = "w",
        movedown = "s",
        moveleft = "a",
        moveright = "d",
        leftone = "z",
        lefttwo = "x",
        lefttree = "c",
        rightone = "num3",
        righttwo = "num2",
        righttree = "num1",
        pause = "escape"

    },

    miscsettings={
        language = "jp",
        timeout = 30,
        defoltlevel = "extra"
    },
    playsettings={
        movespead = 1.0,
        timing=0,
        playlogsave = true,
        showfps = false,
    },
    stats={
        bestRating = 0,
        lastRating = 0,
        ratingAverage = 0,
        ratingHistory = {}
    }
}

settings.settingsdata = settingsdata

function settings.get(path, default)
    return settingsApi.get(settingsdata, path, default)
end

function settings.set(path, value)
    return settingsApi.set(settingsdata, path, value)
end

function settings.applyDisplaySettings()
    if love.window then
        local width = tonumber(settingsdata.displaysettings.displaysize[1])
        local height = tonumber(settingsdata.displaysettings.displaysize[2])
        local fullscreen = settingsdata.displaysettings.displaymode == "fullscreen"
        if not width or width <= 0 or not height or height <= 0 then
            width, height = love.graphics.getDimensions()
        end
        coreWindow.applyMode(width, height, {
            fullscreen = fullscreen,
            vsync = settingsdata.displaysettings.vsync == true
        })
        displayWidth, displayHeight = love.graphics.getDimensions()
    end
    -- Apply display settings and refresh dependent UI state.
    updateLayout()
    refreshFonts()

    -- Refresh the music select UI if it is available.
    pcall(function()
        local ok, ms = pcall(require, "musicselect")
        if ok and ms and type(ms.refreshMusicselectFonts) == "function" then
            ms.refreshMusicselectFonts()
        end
    end)
end

function settings.applyAudioSettings()
    if love.audio then
        love.audio.setVolume(settingsdata.audiosettings.mastervolume)
    end
end

function settings.applySettings()
    settings.applyDisplaySettings()
    settings.applyAudioSettings()
end

function settings.openLink()
    local field = settingFields[selectedIndex][selectedFieldIndex]
    local url = getSettingValue(field)
    if type(url) == "string" and url ~= "" and love.system and love.system.openURL then
        love.system.openURL(url)
    end
end

function settings.load()

    if love.filesystem.getInfo("settings.json") then

        local contents = love.filesystem.read("settings.json")

        local decoded = JSON:decode(contents)

        if decoded then
            settingsdata = decoded
            settings.settingsdata = settingsdata
        end

    else

        settings.save() -- Create a default settings file when none exists.

    end

    settings.applySettings()

    updateLayout()
    refreshFonts()

end

function settings.loadFromGameJolt()
    if not gamejolt
        or not gamejolt.status
        or not gamejolt.status.authenticated
        or type(gamejolt.loadSettings) ~= "function"
    then
        return false, "GameJolt is not authenticated"
    end

    local ok, remoteSettings =
        gamejolt.loadSettings("settings")

    if not ok or type(remoteSettings) ~= "table" then
        log.warn(
            "GameJolt settings were not applied: "
            .. tostring(remoteSettings or "unknown")
        )
        return false, remoteSettings
    end

    settingsdata = remoteSettings
    settings.settingsdata = settingsdata

    local encoded = JSON:encode(settingsdata)
    love.filesystem.write("settings.json", encoded)
    settings.applySettings()
    updateLayout()
    refreshFonts()

    log.info("GameJolt settings applied locally")
    return true
end

local function getFieldRowRect(index)
    local x = layout.rightX
    local statusH = layout.lineHeight * 2 + layout.spacing
    local y = layout.panelY + statusH + layout.spacing + (index - 1) * (layout.lineHeight + layout.spacing)
    local w = displayWidth - x - layout.padding
    local h = layout.lineHeight
    return x, y, w, h
end

local function isPointInRect(x, y, rx, ry, rw, rh)
    return x >= rx and y >= ry and x <= rx + rw and y <= ry + rh
end

local function getFieldIndexAtPosition(x, y)
    for i = 1, getCurrentFieldCount() do
        local rx, ry, rw, rh = getFieldRowRect(i)
        if isPointInRect(x, y, rx, ry, rw, rh) then
            return i
        end
    end
    return nil
end

local function adjustFieldAtPosition(x, y)
    local index = getFieldIndexAtPosition(x, y)
    if not index then
        return false
    end

    local fieldName = settingFields[selectedIndex][index]
    if not isAdjustableField(fieldName) then
        return false
    end

    local rx, ry, rw, rh = getFieldRowRect(index)
    local arrowWidth = math_min(48, rw * 0.1)
    local leftArrowX = rx + rw - arrowWidth * 2 - 22
    local rightArrowX = rx + rw - arrowWidth - 14

    selectedFieldIndex = index

    if isPointInRect(x, y, leftArrowX, ry + 8, arrowWidth, rh - 16) then
        adjustCurrentSetting(-1)
        return true
    elseif isPointInRect(x, y, rightArrowX, ry + 8, arrowWidth, rh - 16) then
        adjustCurrentSetting(1)
        return true
    end

    return false
end

function settings.update(dt)
    updateFeedbackTextInput()

    local backspaceDown = selectedIndex == 6
        and (feedbackFocusedField == 1 or feedbackFocusedField == 2)
        and love.keyboard.isDown("backspace")
    if backspaceDown then
        if not backspaceWasDown then
            backspaceHoldTime = 0
            backspaceRepeatTimer = 0
        else
            backspaceHoldTime = backspaceHoldTime + dt
            if backspaceHoldTime >= BACKSPACE_REPEAT_DELAY then
                backspaceRepeatTimer = backspaceRepeatTimer + dt
                local deletes = 0
                while backspaceRepeatTimer >= BACKSPACE_REPEAT_INTERVAL and deletes < 64 do
                    if feedbackFocusedField == 1 then
                        feedbackSubject = removeLastUTF8Char(feedbackSubject)
                    else
                        feedbackBody = removeLastUTF8Char(feedbackBody)
                    end
                    backspaceRepeatTimer = backspaceRepeatTimer - BACKSPACE_REPEAT_INTERVAL
                    deletes = deletes + 1
                end
            end
        end
    else
        backspaceHoldTime = 0
        backspaceRepeatTimer = 0
    end
    backspaceWasDown = backspaceDown

    for index = 1, #categories do
        local color = categoryColors[index]
        if color then
            if index == selectedIndex then
                color[1], color[2], color[3] = 1.0, 1.0, 1.0
            else
                color[1], color[2], color[3] = 0.5, 0.5, 0.5
            end
        end
    end
end


function settings.draw()
    updateLayout()

    if selectedIndex == 5 then
        drawKeyConfigScreen()
        return
    end
    
    if selectedIndex == 6 then
        settings.feedbackdraw()
        return
    end

    love.graphics.setFont(Titlefont)
    love.graphics.setColor(1, 1, 1)
    local titleText = tostring(getLocaleText("title"))
    love.graphics.print(titleText, displayWidth/2 - Titlefont:getWidth(titleText)/2, layout.padding / 2)

    love.graphics.setFont(Subtitlefont)
    local panelY = layout.panelY
    local panelH = layout.panelH
    local panelW = layout.leftWidth - layout.padding / 2

    local panelPoly = ui.parallelogramPoly(layout.padding, layout.padding + panelW, panelY, panelY + panelH, slope)
    love.graphics.setColor(0.05, 0.05, 0.05, 0.98)
    love.graphics.polygon("fill", panelPoly)
    love.graphics.setColor(1,1,1,0.12)
    love.graphics.polygon("line", panelPoly)

    for i = 1, #categories do
        local bx = layout.padding + 16
        local by = panelY + (i - 1) * (layout.lineHeight + layout.spacing)
        local bw = panelW - 32
        local bh = layout.lineHeight
        local isSelected = i == selectedIndex
        local text = getLocaleText("categories")[i]

        if isSelected then
            love.graphics.setColor(0.22, 0.22, 0.22, 0.96)
            love.graphics.rectangle("fill", bx, by, bw, bh)
            love.graphics.setColor(1, 1, 1, 0.18)
            love.graphics.rectangle("line", bx, by, bw, bh)
        else
            love.graphics.setColor(0.10, 0.10, 0.10, 0.92)
            love.graphics.rectangle("fill", bx, by, bw, bh)
            love.graphics.setColor(1, 1, 1, 0.06)
            love.graphics.rectangle("line", bx, by, bw, bh)
        end

        love.graphics.setColor(1, 1, 1, 0.96)
        love.graphics.setFont(Subtitlefont)
        drawAlignedText(text, bx + 18, by, bw - 18, bh, Subtitlefont, "left")
    end

    local statusX = layout.rightX
    local statusY = panelY
    local statusW = displayWidth - statusX - layout.padding
    local statusH = layout.lineHeight * 2 + layout.spacing
    local statusPoly = ui.parallelogramPoly(statusX, statusX + statusW, statusY, statusY + statusH, slope)
    love.graphics.setColor(0, 0, 0, 0.95)
    love.graphics.polygon("fill", statusPoly)
    love.graphics.setColor(1,1,1,0.16)
    love.graphics.polygon("line", statusPoly)
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, 0.94)
    love.graphics.print(getLocaleText("categories")[selectedIndex] .. " - " .. getCurrentFieldCount() .. " items", statusX + 20, statusY + 18)
    love.graphics.setColor(1, 1, 1, 0.8)
    local statusHelp = getLocaleText("helpText")
    love.graphics.print(statusHelp, statusX + 20, statusY + 20 + Subtitlefont:getHeight())

    love.graphics.setFont(font)
    local maxFieldY = layout.panelY + layout.panelH - layout.padding
    local visibleItemCount = 0
    
    for i, _ in ipairs(settingFields[selectedIndex]) do
        local rx, ry, rw, rh = getFieldRowRect(i)
        if ry + rh <= maxFieldY then
            visibleItemCount = i
        else
            break
        end
    end
    
    if selectedFieldIndex > visibleItemCount then
        selectedFieldIndex = math_max(1, visibleItemCount)
    end
    
    for i, field in ipairs(settingFields[selectedIndex]) do
        local rx, ry, rw, rh = getFieldRowRect(i)
        
        if ry + rh > maxFieldY then
            break
        end
        
        local fieldName = settingFields[selectedIndex][i]
        local isSelected = selectedFieldIndex == i
        local fieldPoly = ui.parallelogramPoly(rx, rx + rw, ry, ry + rh, slope)
        love.graphics.setColor(isSelected and {0.20, 0.20, 0.20, 0.96} or {0.10, 0.10, 0.10, 0.92})
        love.graphics.polygon("fill", fieldPoly)
        love.graphics.setColor(1,1,1,0.08)
        love.graphics.polygon("line", fieldPoly)

        love.graphics.setColor(1, 1, 1, 0.94)
        drawAlignedText(getLocaleText(field), rx + 18, ry, rw - 170, rh, font, "left")

        local valueText = tostring(getSettingValue(field))
        local maxValueW = rw * 0.34
        local valueX = rx + rw - maxValueW - 18
        love.graphics.setColor(1, 1, 1, 0.82)
        drawAlignedText(valueText, valueX, ry, maxValueW, rh, font, "right")

        local fieldName = settingFields[selectedIndex][i]
        local canAdjust = isAdjustableField(fieldName)
        if canAdjust then
            local arrowW = math_min(48, rw * 0.1)
            local arrowH = rh - 24
            local leftArrowX = rx + rw - arrowW * 2 - 22
            local rightArrowX = rx + rw - arrowW - 14
            local leftPoly = ui.parallelogramPoly(leftArrowX, leftArrowX + arrowW, ry + 12, ry + 12 + arrowH, slope)
            local rightPoly = ui.parallelogramPoly(rightArrowX, rightArrowX + arrowW, ry + 12, ry + 12 + arrowH, slope)
            love.graphics.setColor(1, 1, 1, 0.08)
            love.graphics.polygon("fill", leftPoly)
            love.graphics.polygon("fill", rightPoly)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf("<", leftArrowX, ry + 18, arrowW, "center")
            love.graphics.printf(">", rightArrowX, ry + 18, arrowW, "center")
        end
    end

    love.graphics.setColor(1, 1, 1, 0.78)
    local helpText = getLocaleText("helpText")
    if selectedIndex == 3 and settingFields[selectedIndex][selectedFieldIndex] == "discordAccount" then
        helpText = getLocaleText("discordAccountHelp")
    end
    love.graphics.print(helpText, layout.rightX, displayHeight - font:getHeight() * 2)
end


local function getCategoryRect(index)
    local x = layout.padding + 16
    local y = layout.panelY + (index - 1) * (layout.lineHeight + layout.spacing)
    local w = layout.leftWidth - layout.padding - 32
    local h = layout.lineHeight
    return x, y, w, h
end

local function getFeedbackFormLayout()
    local panelY = layout.padding * 3
    local panelH = displayHeight - layout.padding * 5
    local panelW = displayWidth - layout.padding * 2
    local formX = layout.padding + 40
    local formW = panelW - 80
    local labelHeight = font:getHeight()
    local fieldHeight = math_min(56, math_max(40, labelHeight * 2))
    local fieldSpacing = math_min(14, math_max(8, panelH * 0.02))
    local formY = panelY + math_min(24, panelH * 0.06)
    local subjectInputY = formY + labelHeight + 6
    local bodyLabelY = subjectInputY + fieldHeight + fieldSpacing
    local bodyInputY = bodyLabelY + labelHeight + 6
    local availableBodyHeight = panelY + panelH - bodyInputY - fieldHeight - 32
    local bodyFieldHeight = math_max(64, math_min(144, availableBodyHeight))
    local buttonY = bodyInputY + bodyFieldHeight + 16
    return formX, formW, formY, subjectInputY, bodyLabelY, bodyInputY, buttonY, fieldHeight, bodyFieldHeight
end

local function sendFeedback()
    if feedbackStatus == "sending" then
        return
    end
    
    if feedbackSubject == "" or feedbackBody == "" then
        feedbackStatus = "error"
        feedbackStatusTime = os.time()
        return
    end
    
    feedbackStatus = "sending"
    feedbackStatusTime = os.time()
    local osName = love.system and love.system.getOS and love.system.getOS() or "unknown"
    local version = "unknown"
    if love.getVersion then
        local ok, major, minor, revision = pcall(love.getVersion)
        if ok and major then
            version = string.format(
                "%s.%s.%s",
                tostring(major),
                tostring(minor),
                tostring(revision or 0)
            )
        end
    end

    local feedbackID = string.format(
        "FEEDBACK-%d-%06d",
        os.time(),
        math.random(100000, 999999)
    )
    local payload = {
        feedback_id = feedbackID,
        subject = feedbackSubject,
        body = feedbackBody,
        os = osName,
        version = version,
        time = os.date("%Y-%m-%d %H:%M:%S")
    }
    local sent, sendError = reportTransport.send("feedback", payload)
    if sent then
        feedbackStatus = "sent"
        feedbackSubject = ""
        feedbackBody = ""
    else
        feedbackStatus = "error"
        log.error("[settings] Feedback delivery failed: " .. tostring(sendError))
    end

    feedbackStatusTime = os.time()
end

function settings.mousepressed(x, y, button)
    if button ~= 1 then
        return
    end

    updateLayout()

    print("[DEBUG] mousepressed called, selectedIndex=" .. selectedIndex .. ", x=" .. x .. ", y=" .. y)
    
    if selectedIndex == 6 then -- Feedback category
        print("[DEBUG] In feedback category, feedbackFocusedField=" .. feedbackFocusedField)
        local lang = settingsdata.miscsettings.language or "jp"
        
        local formX, formW, formY, subjectInputY, bodyLabelY, bodyInputY, buttonY, fieldHeight, bodyFieldHeight = getFeedbackFormLayout()

        -- Subject field
        if isPointInRect(x, y, formX, subjectInputY, formW, fieldHeight) then
            feedbackFocusedField = 1
            print("[DEBUG] Clicked subject field")
            return
        end
        
        -- Body field
        if isPointInRect(x, y, formX, bodyInputY, formW, bodyFieldHeight) then
            feedbackFocusedField = 2
            print("[DEBUG] Clicked body field")
            return
        end
        
        -- Send button
        if isPointInRect(x, y, formX, buttonY, formW, fieldHeight) then
            feedbackFocusedField = 3
            print("[DEBUG] Clicked send button")
            sendFeedback()
            return
        end
        return
    end

    if selectedIndex == 5 then
        for itemIndex = 1, #keyConfigItemOrder do
            local rx, ry, rw, rh = getKeyConfigItemRect(itemIndex)
            if isPointInRect(x, y, rx, ry, rw, rh) then
                keyConfigSelectedIndex = itemIndex
                beginKeyBinding(itemIndex)
                return
            end
        end
        return
    end

    for i = 1, #categories do
        local rx, ry, rw, rh = getCategoryRect(i)
        if isPointInRect(x, y, rx, ry, rw, rh) then
            selectedIndex = i
            selectedFieldIndex = 1
            if i == 6 then
                feedbackFocusedField = 1
            end
            print("[DEBUG] Clicked category " .. i .. ", selectedIndex=" .. selectedIndex)
            return
        end
    end

    if adjustFieldAtPosition(x, y) then
        return
    end

    local index = getFieldIndexAtPosition(x, y)
    if index then
        selectedFieldIndex = index
        if selectedIndex == 3 and settingFields[selectedIndex][index] == "discordAccount" then
            activateDiscordAccount()
        end
    end
    return
end


function settings.save()

    local jsonText = JSON:encode_pretty(settingsdata)

    local success, message = love.filesystem.write("settings.json", jsonText)

    if success then
        print("settings.json saved!")
        if gamejolt and type(gamejolt.saveSettings) == "function" and gamejolt.status and gamejolt.status.authenticated then
            local ok, response = pcall(gamejolt.saveSettings, settingsdata)
            local responseTable = type(response) == "table" and response or {}
            if ok and responseTable.success == "true" then
                log.info("GameJolt settings synced")
            else
                log.warn(
                    "GameJolt settings sync failed: "
                    .. tostring(responseTable.message or response or "unknown")
                )
            end
        end
    else
        print("save error: " .. tostring(message))
    end
end

function settings.displaydraw()
    love.graphics.setFont(font)
    local y = displayHeight/5 - font:getHeight() * 1.5
    drawSettingLine(y, "Display Size", settingsdata.displaysettings.displaysize[1] .. "x" .. settingsdata.displaysettings.displaysize[2], selectedFieldIndex == 1)
    drawSettingLine(y + 50, "Display Mode", settingsdata.displaysettings.displaymode, selectedFieldIndex == 2)
    drawSettingLine(y + 100, "VSync", tostring(settingsdata.displaysettings.vsync), selectedFieldIndex == 3)
end

function settings.audiodraw()
    love.graphics.setFont(font)
    local y = displayHeight/5 - font:getHeight() * 1.5
    drawSettingLine(y, "Master Volume", string_format("%.1f", settingsdata.audiosettings.mastervolume), selectedFieldIndex == 1)
    drawSettingLine(y + 50, "Music Volume", string_format("%.1f", settingsdata.audiosettings.musicvolume), selectedFieldIndex == 2)
    drawSettingLine(y + 100, "SFX Volume", string_format("%.1f", settingsdata.audiosettings.sfxvolume), selectedFieldIndex == 3)
end

function settings.miscdraw()
    love.graphics.setFont(font)
    local y = displayHeight/5 - font:getHeight() * 1.5
    drawSettingLine(y, "Language", settingsdata.miscsettings.language, selectedFieldIndex == 1)
    drawSettingLine(y + 50, "Timeout", tostring(settingsdata.miscsettings.timeout), selectedFieldIndex == 2)
    drawSettingLine(y + 100, "Default Level", settingsdata.miscsettings.defoltlevel, selectedFieldIndex == 3)
end

function settings.playdraw()
    love.graphics.setFont(font)
    local y = displayHeight/5 - font:getHeight() * 1.5
    drawSettingLine(y, "Move Speed", string_format("%.1f", settingsdata.playsettings.movespead), selectedFieldIndex == 1)
    drawSettingLine(y + 50, "Timing", tostring(settingsdata.playsettings.timing), selectedFieldIndex == 2)
    drawSettingLine(y + 100, "Play Log Save", tostring(settingsdata.playsettings.playlogsave), selectedFieldIndex == 3)
end

function settings.feedbackdraw()
    updateLayout()
    
    local lang = settingsdata.miscsettings.language or "jp"
    local locale = localeTexts[lang]
    
    -- Draw title
    love.graphics.setFont(FeedbackTitlefont or Titlefont)
    love.graphics.setColor(1, 1, 1)
    local titleText = locale.feedbackSubject:sub(1, 1) == "件" and "フィードバック" or "Feedback"
    love.graphics.print(titleText, displayWidth/2 - (FeedbackTitlefont or Titlefont):getWidth(titleText)/2, layout.padding / 2)
    
    -- Draw background panel
    love.graphics.setFont(Feedbackfont or Subtitlefont)
    local panelX = layout.padding
    local panelY = layout.padding * 3
    local panelW = displayWidth - layout.padding * 2
    local panelH = displayHeight - layout.padding * 5
    
    local panelPoly = ui.parallelogramPoly(panelX, panelX + panelW, panelY, panelY + panelH, slope)
    love.graphics.setColor(0.05, 0.05, 0.05, 0.98)
    love.graphics.polygon("fill", panelPoly)
    love.graphics.setColor(1, 1, 1, 0.12)
    love.graphics.polygon("line", panelPoly)
    
    -- Input form
    love.graphics.setFont(Feedbackfont or font)
    local formX, formW, formY, subjectInputY, bodyLabelY, bodyInputY, buttonY, fieldHeight, bodyFieldHeight = getFeedbackFormLayout()
    
    -- Subject field
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print(locale.feedbackSubject .. ":", formX, formY)
    
    if feedbackFocusedField == 1 then
        love.graphics.setColor(1, 1, 1, 0.3)
    else
        love.graphics.setColor(1, 1, 1, 0.1)
    end
    love.graphics.rectangle("fill", formX, subjectInputY, formW, fieldHeight)
    
    if feedbackFocusedField == 1 then
        love.graphics.setColor(1, 1, 1, 0.8)
    else
        love.graphics.setColor(1, 1, 1, 0.3)
    end
    love.graphics.rectangle("line", formX, subjectInputY, formW, fieldHeight)
    
    -- Draw subject text with clipping
    love.graphics.setScissor(formX, subjectInputY, formW, fieldHeight)
    love.graphics.setColor(0.9, 0.9, 0.9, 1)
    drawFeedbackText(
        feedbackSubject,
        feedbackCompositionField == 1 and feedbackCompositionText or "",
        formX + 12,
        subjectInputY + 9,
        formW - 24
    )
    love.graphics.setScissor()
    
    -- Body field
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print(locale.feedbackBody .. ":", formX, bodyLabelY)
    
    if feedbackFocusedField == 2 then
        love.graphics.setColor(1, 1, 1, 0.3)
    else
        love.graphics.setColor(1, 1, 1, 0.1)
    end
    love.graphics.rectangle("fill", formX, bodyInputY, formW, bodyFieldHeight)
    
    if feedbackFocusedField == 2 then
        love.graphics.setColor(1, 1, 1, 0.8)
    else
        love.graphics.setColor(1, 1, 1, 0.3)
    end
    love.graphics.rectangle("line", formX, bodyInputY, formW, bodyFieldHeight)
    
    -- Draw body text with clipping
    love.graphics.setScissor(formX, bodyInputY, formW, bodyFieldHeight)
    love.graphics.setColor(0.9, 0.9, 0.9, 1)
    drawFeedbackText(
        feedbackBody,
        feedbackCompositionField == 2 and feedbackCompositionText or "",
        formX + 12,
        bodyInputY + 9,
        formW - 24
    )
    love.graphics.setScissor()
    
    -- Send button
    if feedbackFocusedField == 3 then
        love.graphics.setColor(0.2, 0.2, 0.2, 0.96)
    else
        love.graphics.setColor(0.1, 0.1, 0.1, 0.92)
    end
    love.graphics.rectangle("fill", formX, buttonY, formW, fieldHeight)
    
    if feedbackFocusedField == 3 then
        love.graphics.setColor(1, 1, 1, 0.18)
    else
        love.graphics.setColor(1, 1, 1, 0.06)
    end
    love.graphics.rectangle("line", formX, buttonY, formW, fieldHeight)
    
    love.graphics.setColor(1, 1, 1, 0.96)
    love.graphics.setFont(Feedbackfont or Subtitlefont)
    if feedbackStatus == "sending" then
        love.graphics.print(locale.feedbackSending, formX + 12, buttonY + 6)
    elseif feedbackStatus == "sent" then
        love.graphics.print(locale.feedbackSent, formX + 12, buttonY + 6)
    elseif feedbackStatus == "error" then
        love.graphics.print(locale.feedbackError, formX + 12, buttonY + 6)
    else
        love.graphics.print(locale.feedbackSend, formX + 12, buttonY + 6)
    end
    
    -- Help text
    love.graphics.setFont(Feedbackfont or font)
    love.graphics.setColor(1, 1, 1, 0.6)
    local helpText = lang == "jp" and "↑↓でフィールド切り替え、BackspaceとEnterで操作、ESCで戻る" or "Up/Down to switch fields, Enter/Backspace to edit, ESC to go back"
    love.graphics.print(helpText, formX, displayHeight - layout.padding - 30)
    
    -- Status message fade out
    if feedbackStatus and os.time() - feedbackStatusTime > 3 then
        feedbackStatus = nil
    end
end

function settings.openMenu()
    settings.previousProgram = programnumber
    selectedIndex = 1
    selectedFieldIndex = 1
    feedbackFocusedField = 1
    feedbackSubject = ""
    feedbackBody = ""
    feedbackStatus = nil
    feedbackCompositionField = nil
    feedbackCompositionText = ""
    updateFeedbackTextInput()
    changeProgram(5)
end

function settings.keypressed(key, scancode, isrepeat)
    if selectedIndex == 6 then -- Feedback category
        if key == "escape" then
            selectedIndex = 1
            selectedFieldIndex = 1
            feedbackFocusedField = 1
            return
        end
        
        if feedbackFocusedField == 1 then
            -- Subject input
            if key == "backspace" and not isrepeat then
                feedbackSubject = removeLastUTF8Char(feedbackSubject)
            elseif key == "tab" or key == "down" then
                if isrepeat and key == "return" then return end
                feedbackFocusedField = 2
            end
            return
        elseif feedbackFocusedField == 2 then
            -- Body input
            if key == "backspace" and not isrepeat then
                feedbackBody = removeLastUTF8Char(feedbackBody)
            elseif key == "tab" then
                if isrepeat then return end
                feedbackFocusedField = 3
            elseif key == "up" then
                if isrepeat then return end
                feedbackFocusedField = 1
            end
            return
        elseif feedbackFocusedField == 3 then
            -- Send button
            if key == "return" or key == "space" then
                sendFeedback()
                feedbackFocusedField = 1
            elseif key == "up" or key == "w" or key == "kpup" then
                feedbackFocusedField = 2
            elseif key == "tab" or key == "down" or key == "s" or key == "kpdown" then
                feedbackFocusedField = 1
            end
            return
        end
    elseif selectedIndex == 5 then
        if keyConfigWaitingForKey then
            if key == "escape" then
                keyConfigWaitingForKey = false
                keyConfigTargetField = nil
                return
            end

            local normalizedKey = normalizeKeyBindingName(key, scancode)
            if normalizedKey then
                settingsdata.keysettings[keyConfigTargetField] = normalizedKey
                settings.save()
                keyConfigWaitingForKey = false
                keyConfigTargetField = nil
            end
            return
        end

        if key == "left" or key == "a" or key == "kpleft" then
            keyConfigSelectedIndex = math_max(1, keyConfigSelectedIndex - 1)
            return
        end

        if key == "right" or key == "d" or key == "kpright" then
            keyConfigSelectedIndex = math_min(#keyConfigItemOrder, keyConfigSelectedIndex + 1)
            return
        end

        if key == "up" or key == "w" or key == "kpup" then
            keyConfigSelectedIndex = math_max(1, keyConfigSelectedIndex - 4)
            return
        end

        if key == "down" or key == "s" or key == "kpdown" then
            keyConfigSelectedIndex = math_min(#keyConfigItemOrder, keyConfigSelectedIndex + 4)
            return
        end

        if key == "return" or key == "space" or key == "kpenter" then
            beginKeyBinding(keyConfigSelectedIndex)
            return
        end

        if key == "escape" then
            selectedIndex = keyConfigReturnIndex or 4
            selectedFieldIndex = 1
            return
        end
    end

    if key == "escape" then
        if settings.previousProgram and settings.previousProgram ~= 5 then
            changeProgram(settings.previousProgram)
        else
            changeProgram(2)
        end
        return
    end

    if key == "up" or key == "w" or key == "kpup" then
        selectedIndex = math_max(1, selectedIndex - 1)
        selectedFieldIndex = 1
        return
    end

    if key == "down" or key == "s" or key == "kpdown" then
        selectedIndex = math_min(#categories, selectedIndex + 1)
        selectedFieldIndex = 1
        return
    end

    if key == "tab" then
        selectedFieldIndex = selectedFieldIndex % getCurrentFieldCount() + 1
        return
    end

    if key == "return" or key == "space" or key == "kpenter" then
        if selectedIndex == 3 and settingFields[selectedIndex][selectedFieldIndex] == "discordAccount" then
            activateDiscordAccount()
        end
        return
    end

    if key == "left" or key == "kpleft" then
        local fieldName = settingFields[selectedIndex][selectedFieldIndex]
        if isAdjustableField(fieldName) then
            adjustCurrentSetting(-1)
        end
        return
    end

    if key == "right" or key == "kpright" then
        local fieldName = settingFields[selectedIndex][selectedFieldIndex]
        if isAdjustableField(fieldName) then
            adjustCurrentSetting(1)
        end
        return
    end

    local numericIndex = tonumber(key)
    if numericIndex and numericIndex >= 1 and numericIndex <= #categories then
        selectedIndex = numericIndex
        selectedFieldIndex = 1
        return
    end

end

function settings.textinput(t)
    if selectedIndex == 6 and type(t) == "string" then
        if feedbackFocusedField == 1 then
            feedbackSubject = feedbackSubject .. t
        elseif feedbackFocusedField == 2 then
            feedbackBody = feedbackBody .. t
        end
        feedbackCompositionField = nil
        feedbackCompositionText = ""
    end
end

function settings.textedited(text)
    if selectedIndex ~= 6
        or (feedbackFocusedField ~= 1 and feedbackFocusedField ~= 2)
        or type(text) ~= "string" then
        feedbackCompositionField = nil
        feedbackCompositionText = ""
        return
    end

    feedbackCompositionField = feedbackFocusedField
    feedbackCompositionText = text
end

return settings
