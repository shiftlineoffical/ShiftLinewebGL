local opening = {}
local displayWidth, displayHeight = love.graphics.getDimensions()

local gamejolt = require("gamejolt")
local gamejoltuser = require("gamejoltuser")
local i18n = require("i18n")
local utf8 = require("utf8")
local ui = require("lib.ui")

local okHttp, http = pcall(require, "socket.http")
if not okHttp then
    http = nil
end


local BACKSPACE_REPEAT_DELAY = 0.4
local BACKSPACE_REPEAT_INTERVAL = 0.05
local LOGIN_FADE_SPEED = 6
local OPENING_FADE_DURATION = 0.6

local MAX_USERID_LENGTH = 64
local MAX_TOKEN_LENGTH = 128

local LOGIN_PANEL_WIDTH_RATIO = 0.4
local LOGIN_PANEL_HEIGHT_RATIO = 0.8
local LOGIN_INPUT_WIDTH_RATIO = 0.7

local TOKEN_TOGGLE_WIDTH = 46

local logoimg = nil
local gamejoltlogoimg = nil
local videostream = nil
local Video = nil

local loginfont = nil
local exitfont = nil
local clickfont = nil

local button = {
    x = 0,
    y = 0,
    w = 0,
    h = 0
}

local exitButton = {
    x = 0,
    y = 0,
    w = 0,
    h = 0
}

local tokenToggleButton = {
    x = 0,
    y = 0,
    w = TOKEN_TOGGLE_WIDTH,
    h = 0
}

local loginOpen = false
local focusedField = nil

local usernametext = ""
local tokentext = ""

local autologinChecked = false
local showToken = false

local statusText = ""
local statusIsError = false

local fadeOut = false
local fadeAlpha = 0
local loginFade = 0

local caretTimer = 0
local caretOn = true

local backspaceWasDown = false
local backspaceHoldTime = 0
local backspaceRepeatTimer = 0

local cachedUiRects = nil
local cachedTokenMaskSource = nil
local cachedTokenMaskValue = ""

local openingLogoScale = 0.7
local gamejoltLogoScale = 1.0

local exitButtonPaddingX = 16
local exitButtonPaddingY = 10

local function updateDisplaySize()
    local w, h = love.graphics.getDimensions()

    if w ~= displayWidth or h ~= displayHeight then
        displayWidth = w
        displayHeight = h
        cachedUiRects = nil
        return true
    end

    return false
end

local function pointInRect(px, py, r)
    if type(r) ~= "table" then
        return false
    end

    local rx = r.x or r.left or 0
    local ry = r.y or r.top or 0
    local rw = r.w or r.width or r.size or 0
    local rh = r.h or r.height or r.size or 0

    return px >= rx
        and px <= rx + rw
        and py >= ry
        and py <= ry + rh
end

local function utf8Length(text)
    if type(text) ~= "string" then
        return 0
    end

    return utf8.len(text) or #text
end

local function updateOpeningLayout()
    local baseFontSize = math.max(
        18,
        math.floor(displayHeight * 0.035)
    )

    local exitFontSize = math.max(
        18,
        math.floor(displayHeight * 0.04)
    )

    local clickFontSize = math.max(
        16,
        math.floor(displayHeight * 0.025)
    )

    loginfont = love.graphics.newFont(
        "lib/data/fonts/NotoSansJP-ExtraLight.ttf",
        baseFontSize
    )

    exitfont = love.graphics.newFont(
        "lib/data/fonts/NotoSansJP-ExtraLight.ttf",
        exitFontSize
    )

    clickfont = love.graphics.newFont(
        "lib/data/fonts/NotoSansJP-ExtraLight.ttf",
        clickFontSize
    )

    exitButtonPaddingX = math.max(
        10,
        math.floor(exitFontSize * 0.45)
    )

    exitButtonPaddingY = math.max(
        6,
        math.floor(exitFontSize * 0.35)
    )

    if logoimg then
        local mainLogoMaxW = displayWidth * 0.45
        local mainLogoMaxH = displayHeight * 0.34

        openingLogoScale = ui.scaleToFit(
            logoimg,
            mainLogoMaxW,
            mainLogoMaxH
        )
    end

    if gamejoltlogoimg then
        local smallMaxW = displayWidth * 0.12
        local smallMaxH = displayHeight * 0.12

        gamejoltLogoScale = ui.scaleToFit(
            gamejoltlogoimg,
            smallMaxW,
            smallMaxH
        )

        button.w =
            gamejoltlogoimg:getWidth()
            * gamejoltLogoScale

        button.h =
            gamejoltlogoimg:getHeight()
            * gamejoltLogoScale
    else
        button.w = 0
        button.h = 0
    end

    button.x =
        displayWidth
        - button.w
        - displayWidth * 0.02

    button.y = displayHeight * 0.02

    cachedUiRects = nil
end

local function updateExitButtonLayout()
    if not exitfont then
        return
    end

    local exitText = i18n.t("exit")

    local exitW =
        exitfont:getWidth(exitText)
        + exitButtonPaddingX * 2

    local exitH =
        exitfont:getHeight()
        + exitButtonPaddingY * 2

    exitButton.w = exitW
    exitButton.h = exitH

    exitButton.x =
        displayWidth
        - exitW
        - displayWidth * 0.02

    exitButton.y =
        displayHeight
        - exitH
        - displayHeight * 0.02
end

local function getLoginUiRects()
    if cachedUiRects then
        return
            cachedUiRects.panel,
            cachedUiRects.userBox,
            cachedUiRects.tokenBox,
            cachedUiRects.checkbox,
            cachedUiRects.loginBtn,
            cachedUiRects.tokenToggle
    end

    local panelW =
        displayWidth
        * LOGIN_PANEL_WIDTH_RATIO

    local panelH =
        displayHeight
        * LOGIN_PANEL_HEIGHT_RATIO

    local panel = {
        x = (displayWidth - panelW) / 2,
        y = (displayHeight - panelH) / 2,
        w = panelW,
        h = panelH
    }

    local inputW =
        panel.w
        * LOGIN_INPUT_WIDTH_RATIO

    local inputH =
        math.max(
            42,
            math.floor(displayHeight * 0.05)
        )

    local inputX =
        panel.x
        + (panel.w - inputW) / 2

    local userY =
        panel.y
        + panel.h * 0.27

    local tokenY =
        userY
        + inputH
        + panel.h * 0.04

    local userBox = {
        x = inputX,
        y = userY,
        w = inputW,
        h = inputH
    }

    local tokenBox = {
        x = inputX,
        y = tokenY,
        w = inputW,
        h = inputH
    }

    local checkboxSize =
        math.floor(inputH * 0.7 + 0.5)

    local checkboxY =
        tokenY
        + inputH
        + panel.h * 0.055

    local checkbox = {
        x = inputX,
        y = checkboxY,
        size = checkboxSize
    }

    local loginBtnY =
        checkboxY
        + checkboxSize
        + panel.h * 0.08

    local loginBtn = {
        x = inputX,
        y = loginBtnY,
        w = inputW,
        h = inputH
    }

    local tokenToggle = {
        x = tokenBox.x
            + tokenBox.w
            - TOKEN_TOGGLE_WIDTH,
        y = tokenBox.y,
        w = TOKEN_TOGGLE_WIDTH,
        h = tokenBox.h
    }

    cachedUiRects = {
        panel = panel,
        userBox = userBox,
        tokenBox = tokenBox,
        checkbox = checkbox,
        loginBtn = loginBtn,
        tokenToggle = tokenToggle
    }

    return
        panel,
        userBox,
        tokenBox,
        checkbox,
        loginBtn,
        tokenToggle
end

local function setTextInputRectForFocus()
    if not loginOpen or focusedField == nil then
        love.keyboard.setTextInput(false)
        return
    end

    local _, userBox, tokenBox =
        getLoginUiRects()

    if focusedField == "userid" then
        love.keyboard.setTextInput(
            true,
            userBox.x,
            userBox.y,
            userBox.w,
            userBox.h
        )
    elseif focusedField == "token" then
        love.keyboard.setTextInput(
            true,
            tokenBox.x,
            tokenBox.y,
            tokenBox.w,
            tokenBox.h
        )
    else
        love.keyboard.setTextInput(true)
    end
end

local function setFocusedField(field)
    if field ~= nil
        and field ~= "userid"
        and field ~= "token" then
        return
    end

    focusedField = field
    caretTimer = 0
    caretOn = true

    setTextInputRectForFocus()
end

local function setLoginUiOpen(open)
    open = open == true

    if loginOpen == open then
        return
    end

    loginOpen = open
    loginFade = 0

    caretTimer = 0
    caretOn = true

    statusText = ""
    statusIsError = false

    if open then
        if focusedField == nil then
            if usernametext == "" then
                focusedField = "userid"
            elseif tokentext == "" then
                focusedField = "token"
            else
                focusedField = "userid"
            end
        end

        setTextInputRectForFocus()
    else
        setFocusedField(nil)
        love.keyboard.setTextInput(false)
    end
end

local function backspaceUtf8(text)
    if text == "" then
        return ""
    end

    local byteoffset = utf8.offset(text, -1)

    if not byteoffset then
        return ""
    end

    return string.sub(text, 1, byteoffset - 1)
end

local function fitTextEnd(text, maxWidth, font)
    if type(text) ~= "string" then
        return ""
    end

    if not font or maxWidth <= 0 then
        return ""
    end

    if font:getWidth(text) <= maxWidth then
        return text
    end

    local len = utf8Length(text)

    if len <= 0 then
        return ""
    end

    local lo = 1
    local hi = len
    local best = ""

    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local byteIndex = utf8.offset(text, mid)

        if not byteIndex then
            break
        end

        local candidate = text:sub(byteIndex)

        if font:getWidth(candidate) <= maxWidth then
            best = candidate
            hi = mid - 1
        else
            lo = mid + 1
        end
    end

    return best
end

local function deleteOneCharFromFocusedField()
    if focusedField == "userid" then
        usernametext =
            backspaceUtf8(usernametext)
    elseif focusedField == "token" then
        tokentext =
            backspaceUtf8(tokentext)
    end

    caretTimer = 0
    caretOn = true
    cachedTokenMaskSource = nil
end

local function tryAppendToFocusedField(text)
    if not loginOpen then
        return
    end

    if type(text) ~= "string"
        or text == "" then
        return
    end

    text = text:gsub("[\r\n]+", "")

    if text == "" then
        return
    end

    local currentText
    local maxLength

    if focusedField == "userid" then
        currentText = usernametext
        maxLength = MAX_USERID_LENGTH
    elseif focusedField == "token" then
        currentText = tokentext
        maxLength = MAX_TOKEN_LENGTH
    else
        return
    end

    local currentLength =
        utf8Length(currentText)

    if currentLength >= maxLength then
        return
    end

    local textLength =
        utf8Length(text)

    if currentLength + textLength > maxLength then
        local allowed =
            maxLength - currentLength

        if allowed <= 0 then
            return
        end

        local endByte =
            utf8.offset(text, allowed + 1)

        if endByte then
            text = text:sub(1, endByte - 1)
        else
            text = text:sub(1, allowed)
        end
    end

    if text == "" then
        return
    end

    if focusedField == "userid" then
        usernametext =
            usernametext .. text
    elseif focusedField == "token" then
        tokentext =
            tokentext .. text
    end

    caretTimer = 0
    caretOn = true
    cachedTokenMaskSource = nil
end

local function getTokenMask()
    if cachedTokenMaskSource ~= tokentext then
        local len = utf8Length(tokentext)

        cachedTokenMaskSource = tokentext
        cachedTokenMaskValue =
            string.rep("*", len)
    end

    return cachedTokenMaskValue
end

local function getUrlExtension(url)
    if type(url) ~= "string" then
        return nil
    end

    local clean =
        url:gsub("#.*$", "")
           :gsub("%?.*$", "")

    local ext =
        clean:match("%.([%w]+)$")

    if not ext then
        return nil
    end

    ext = ext:lower()

    if ext == "png"
        or ext == "jpg"
        or ext == "jpeg" then
        return ext
    end

    return nil
end

local function fetchAvatarImage(url)
    if type(url) ~= "string"
        or url == "" then
        return nil
    end

    if not url:match("^https://") then
        return nil
    end

    if not http
        or not http.request then
        return nil
    end

    local oldTimeout = http.TIMEOUT
    http.TIMEOUT = 5

    local okRequest, body, code =
        pcall(http.request, url)

    http.TIMEOUT = oldTimeout

    if not okRequest then
        return nil
    end

    if code ~= 200
        and code ~= "200" then
        return nil
    end

    if type(body) ~= "string"
        or body == "" then
        return nil
    end

    local ext =
        getUrlExtension(url)
        or "png"

    local okFile, fileData =
        pcall(
            love.filesystem.newFileData,
            body,
            "gamejolt_avatar." .. ext
        )

    if not okFile or not fileData then
        return nil
    end

    local okImg, image =
        pcall(
            love.graphics.newImage,
            fileData
        )

    if not okImg then
        return nil
    end

    return image
end

opening.fetchAvatarImage = fetchAvatarImage

local function pushLoginToMain(authenticatedOverride)
    if type(App) ~= "table"
        or type(App.setLogin) ~= "function" then
        return
    end

    local status = gamejolt.status or {}

    local authenticated =
        authenticatedOverride

    if authenticated == nil then
        authenticated =
            status.authenticated == true
    end

    App.setLogin({
        authenticated = authenticated,
        userid = usernametext or "",
        user_token = tokentext or "",
        username = status.username or "",
        userId = status.userId or "",
        avatarUrl = status.avatarUrl or ""
    })
end
local function attemptLogin()
    statusText = ""
    statusIsError = false

    if usernametext == ""
        or tokentext == "" then

        statusText =
            "UserID と Token を入力してください"

        statusIsError = true

        if usernametext == "" then
            setFocusedField("userid")
        else
            setFocusedField("token")
        end

        return
    end

    local ok, authenticatedOrErr =
        pcall(function()
            return gamejolt.login(
                usernametext,
                tokentext
            )
        end)

    if not ok then
        statusText =
            "ログインに失敗しました: "
            .. tostring(authenticatedOrErr)

        statusIsError = true

        pushLoginToMain(false)
        return
    end

    if authenticatedOrErr then
        statusText = "ログイン成功"
        statusIsError = false

        if autologinChecked then
            if type(gamejoltuser.save)
                == "function" then

                pcall(
                    gamejoltuser.save,
                    usernametext,
                    tokentext,
                    true
                )
            end
        else
            if type(gamejoltuser.clear)
                == "function" then

                pcall(gamejoltuser.clear)
            end
        end

        setFocusedField(nil)
        pushLoginToMain(true)
    else
        statusText =
            "ログイン失敗 (UserID/Token を確認してください)"

        statusIsError = true

        pushLoginToMain(false)
    end
end

local function updateVideo()
    if not Video then
        return
    end

    local okPlaying, playing =
        pcall(function()
            return Video:isPlaying()
        end)

    if not okPlaying then
        return
    end

    if not playing then
        pcall(function()
            Video:rewind()
            Video:play()
        end)
    end
end

local function drawVideo()
    if not Video then
        love.graphics.setColor(
            0,
            0,
            0,
            1
        )

        love.graphics.rectangle(
            "fill",
            0,
            0,
            displayWidth,
            displayHeight
        )

        love.graphics.setColor(
            1,
            1,
            1,
            1
        )

        return
    end

    local videoW = Video:getWidth()
    local videoH = Video:getHeight()

    if videoW <= 0 or videoH <= 0 then
        return
    end

    local scale =
        math.max(
            displayWidth / videoW,
            displayHeight / videoH
        )

    local drawW = videoW * scale
    local drawH = videoH * scale

    local drawX =
        (displayWidth - drawW) / 2

    local drawY =
        (displayHeight - drawH) / 2

    love.graphics.setColor(
        1,
        1,
        1,
        0.5
    )

    love.graphics.draw(
        Video,
        drawX,
        drawY,
        0,
        scale,
        scale
    )

    love.graphics.setColor(
        1,
        1,
        1,
        1
    )
end

function opening.load()
    updateDisplaySize()

    cachedUiRects = nil
    opening.endprocess = false

    do
        local ok, image =
            pcall(
                love.graphics.newImage,
                "img/logo.png"
            )

        if ok then
            logoimg = image
        else
            logoimg = nil
        end
    end

    do
        local ok, image =
            pcall(
                love.graphics.newImage,
                "img/gamejoltlogo.png"
            )

        if ok then
            gamejoltlogoimg = image
        else
            gamejoltlogoimg = nil
        end
    end

    updateOpeningLayout()
    updateExitButtonLayout()

    Video = nil
    videostream = nil

    if love.graphics.newVideoStream then
        local okStream, stream =
            pcall(
                love.graphics.newVideoStream,
                "img/OP.ogv"
            )

        if okStream and stream then
            videostream = stream

            local okVideo, video =
                pcall(
                    love.graphics.newVideo,
                    videostream
                )

            if okVideo then
                Video = video
            end
        end
    elseif love.graphics.newVideo then
        local okVideo, video =
            pcall(
                love.graphics.newVideo,
                "img/OP.ogv"
            )

        if okVideo then
            Video = video
        end
    end

    if Video then
        pcall(function()
            Video:play()
        end)
    end

    usernametext =
        gamejoltuser.userid or ""

    tokentext =
        gamejoltuser.user_token or ""

    cachedTokenMaskSource = nil
    cachedTokenMaskValue = ""

    autologinChecked =
        gamejoltuser.autologin == true

    showToken = false

    if gamejolt.status
        and gamejolt.status.authenticated then

        pushLoginToMain(true)
    end

    loginOpen = false
    focusedField = nil

    loginFade = 0

    fadeOut = false
    fadeAlpha = 0

    caretTimer = 0
    caretOn = true

    backspaceWasDown = false
    backspaceHoldTime = 0
    backspaceRepeatTimer = 0

    love.keyboard.setTextInput(false)

end

function opening.update(dt)
    local resized =
        updateDisplaySize()

    if resized then
        updateOpeningLayout()
        updateExitButtonLayout()

        if loginOpen
            and focusedField ~= nil then

            setTextInputRectForFocus()
        end
    end

    local backspaceDown =
        loginOpen
        and focusedField ~= nil
        and love.keyboard.isDown("backspace")

    if backspaceDown then
        if not backspaceWasDown then
            backspaceHoldTime = 0
            backspaceRepeatTimer = 0
        else
            backspaceHoldTime =
                backspaceHoldTime + dt

            if backspaceHoldTime >=
                BACKSPACE_REPEAT_DELAY then

                backspaceRepeatTimer =
                    backspaceRepeatTimer + dt

                local deletes = 0

                while
                    backspaceRepeatTimer >=
                        BACKSPACE_REPEAT_INTERVAL
                    and deletes < 64
                do
                    deleteOneCharFromFocusedField()

                    backspaceRepeatTimer =
                        backspaceRepeatTimer
                        - BACKSPACE_REPEAT_INTERVAL

                    deletes = deletes + 1
                end
            end
        end
    else
        backspaceHoldTime = 0
        backspaceRepeatTimer = 0
    end

    backspaceWasDown =
        backspaceDown

    caretTimer =
        caretTimer + dt

    if caretTimer >= 0.5 then
        caretTimer =
            caretTimer - 0.5

        caretOn = not caretOn
    end

    if fadeOut then
        fadeAlpha =
            math.min(
                fadeAlpha
                    + dt / OPENING_FADE_DURATION,
                1
            )

        if fadeAlpha >= 1 then
            opening.endprocess = true
        end
    end

    if loginOpen then
        loginFade =
            math.min(
                loginFade
                    + dt * LOGIN_FADE_SPEED,
                1
            )
    end

    updateVideo()
    button.x =
        displayWidth
        - button.w
        - displayWidth * 0.02

    button.y =
        displayHeight * 0.02

    updateExitButtonLayout()
end

function opening.textinput(text)
    tryAppendToFocusedField(text)
end

function opening.keypressed(key)
    if not loginOpen then
        return
    end

    if key == "escape" then
        setLoginUiOpen(false)
        return
    end

    if key == "tab" then
        if focusedField == "userid" then
            setFocusedField("token")
        else
            setFocusedField("userid")
        end

        return
    end

    if key == "return"
        or key == "kpenter" then

        attemptLogin()
        return
    end

    local ctrl =
        love.keyboard.isDown("lctrl")
        or love.keyboard.isDown("rctrl")

    if ctrl and key == "v" then
        local clip =
            love.system.getClipboardText()
            or ""

        clip = clip:gsub(
            "[\r\n]+",
            ""
        )

        if clip ~= "" then
            tryAppendToFocusedField(clip)
        end

        return
    end

    if key == "backspace" then
        deleteOneCharFromFocusedField()
        return
    end
end

function opening.mousepressed(
    x,
    y,
    mouseButton,
    istouch,
    presses
)
    if mouseButton ~= 1 then
        return
    end

    if pointInRect(
        x,
        y,
        exitButton
    ) then
        love.event.quit()
        return
    end

    if pointInRect(
        x,
        y,
        button
    ) then
        setLoginUiOpen(
            not loginOpen
        )

        return
    end

    if not loginOpen then
        if not fadeOut then
            fadeOut = true
            fadeAlpha = 0
        end

        return
    end

    local panel,
        userBox,
        tokenBox,
        checkbox,
        loginBtn,
        tokenToggle =
        getLoginUiRects()

    if not pointInRect(
        x,
        y,
        panel
    ) then
        setLoginUiOpen(false)
        return
    end

    if pointInRect(
        x,
        y,
        userBox
    ) then
        setFocusedField("userid")
        return
    end

    if pointInRect(
        x,
        y,
        tokenToggle
    ) then
        showToken =
            not showToken

        caretTimer = 0
        caretOn = true

        return
    end

    if pointInRect(
        x,
        y,
        tokenBox
    ) then
        setFocusedField("token")
        return
    end

    if x >= checkbox.x
        and x <= checkbox.x + checkbox.size
        and y >= checkbox.y
        and y <= checkbox.y + checkbox.size then

        autologinChecked =
            not autologinChecked

        if not autologinChecked
            and type(gamejoltuser.clear)
                == "function" then

            pcall(
                gamejoltuser.clear
            )
        end

        return
    end
        local discordButtonH =
        math.max(
            42,
            math.floor(displayHeight * 0.05)
        )

    local discordButtonY =
        loginBtn.y
        + loginBtn.h
        + panel.h * 0.12

    local discordButton = {
        x = loginBtn.x,
        y = discordButtonY,
        w = loginBtn.w,
        h = discordButtonH
    }

    if pointInRect(
        x,
        y,
        loginBtn
    ) then
        attemptLogin()
        return
    end
end

local function drawLoginUi()
    if not loginOpen then
        return
    end

    local panel,
        userBox,
        tokenBox,
        checkbox,
        loginBtn,
        tokenToggle =
        getLoginUiRects()

    local a = loginFade
    local font =
        loginfont
        or love.graphics.getFont()

    local padding = 10

    love.graphics.setColor(
        0,
        0,
        0,
        0.75 * a
    )

    love.graphics.rectangle(
        "fill",
        panel.x,
        panel.y,
        panel.w,
        panel.h
    )

    if gamejoltlogoimg then
        love.graphics.setColor(
            1,
            1,
            1,
            a
        )

        local maxLogoW =
            panel.w * 0.6

        local maxLogoH =
            panel.h * 0.18

        local logoScale =
            ui.scaleToFit(
                gamejoltlogoimg,
                maxLogoW,
                maxLogoH
            )

        local logoW =
            gamejoltlogoimg:getWidth()
            * logoScale

        local logoH =
            gamejoltlogoimg:getHeight()
            * logoScale

        local logoX =
            panel.x
            + (panel.w - logoW) / 2

        local logoY =
            panel.y
            + panel.h * 0.045

        love.graphics.draw(
            gamejoltlogoimg,
            logoX,
            logoY,
            0,
            logoScale,
            logoScale
        )
    end

    love.graphics.setColor(
        0,
        0,
        0,
        a
    )

    love.graphics.rectangle(
        "fill",
        userBox.x,
        userBox.y,
        userBox.w,
        userBox.h
    )

    love.graphics.rectangle(
        "fill",
        tokenBox.x,
        tokenBox.y,
        tokenBox.w,
        tokenBox.h
    )

    love.graphics.setColor(
        1,
        1,
        1,
        a
    )

    love.graphics.rectangle(
        "line",
        userBox.x,
        userBox.y,
        userBox.w,
        userBox.h
    )

    love.graphics.rectangle(
        "line",
        tokenBox.x,
        tokenBox.y,
        tokenBox.w,
        tokenBox.h
    )

    if focusedField == "userid" then
        love.graphics.setColor(
            0.3,
            0.9,
            0.4,
            a
        )

        love.graphics.rectangle(
            "line",
            userBox.x - 2,
            userBox.y - 2,
            userBox.w + 4,
            userBox.h + 4
        )
    elseif focusedField == "token" then
        love.graphics.setColor(
            0.3,
            0.9,
            0.4,
            a
        )

        love.graphics.rectangle(
            "line",
            tokenBox.x - 2,
            tokenBox.y - 2,
            tokenBox.w + 4,
            tokenBox.h + 4
        )
    end

    local textYAdjust =
        math.floor(
            (userBox.h - font:getHeight()) / 2
            + 0.5
        )

    local userTextWidth =
        userBox.w - padding * 2

    local tokenTextWidth =
        tokenBox.w
        - padding * 2
        - TOKEN_TOGGLE_WIDTH

    local useridDisplay

    if usernametext ~= "" then
        useridDisplay =
            fitTextEnd(
                usernametext,
                userTextWidth,
                font
            )
    else
        useridDisplay = "UserID"
    end

    local tokenDisplay

    if tokentext ~= "" then
        if showToken then
            tokenDisplay =
                fitTextEnd(
                    tokentext,
                    tokenTextWidth,
                    font
                )
        else
            tokenDisplay =
                fitTextEnd(
                    getTokenMask(),
                    tokenTextWidth,
                    font
                )
        end
    else
        tokenDisplay = "Token"
    end

    love.graphics.setFont(font)

    if usernametext == "" then
        love.graphics.setColor(
            0.6,
            0.6,
            0.6,
            a
        )
    else
        love.graphics.setColor(
            0.9,
            0.9,
            0.9,
            a
        )
    end

    love.graphics.print(
        useridDisplay,
        userBox.x + padding,
        userBox.y + textYAdjust
    )

    if tokentext == "" then
        love.graphics.setColor(
            0.6,
            0.6,
            0.6,
            a
        )
    else
        love.graphics.setColor(
            0.9,
            0.9,
            0.9,
            a
        )
    end

    love.graphics.print(
        tokenDisplay,
        tokenBox.x + padding,
        tokenBox.y + textYAdjust
    )

    love.graphics.setColor(
        0.1,
        0.1,
        0.1,
        0.95 * a
    )

    love.graphics.rectangle(
        "fill",
        tokenToggle.x,
        tokenToggle.y,
        tokenToggle.w,
        tokenToggle.h
    )

    love.graphics.setColor(
        0.7,
        0.7,
        0.7,
        a
    )

    love.graphics.rectangle(
        "line",
        tokenToggle.x,
        tokenToggle.y,
        tokenToggle.w,
        tokenToggle.h
    )

    local toggleText =
        showToken and "Hide" or "Show"

    local toggleFontSize =
        math.max(
            10,
            math.floor(
                font:getHeight() * 0.38
            )
        )

    local toggleFont =
        love.graphics.newFont(
            "lib/data/fonts/NotoSansJP-ExtraLight.ttf",
            toggleFontSize
        )

    love.graphics.setFont(toggleFont)

    local toggleTextX =
        tokenToggle.x
        + (tokenToggle.w
            - toggleFont:getWidth(toggleText))
        / 2

    local toggleTextY =
        tokenToggle.y
        + (tokenToggle.h
            - toggleFont:getHeight())
        / 2

    love.graphics.print(
        toggleText,
        toggleTextX,
        toggleTextY
    )

    love.graphics.setFont(font)

    if caretOn and focusedField ~= nil then
        local caretX
        local caretY

        if focusedField == "userid" then
            caretX =
                userBox.x + padding

            if usernametext ~= "" then
                caretX =
                    caretX
                    + font:getWidth(
                        useridDisplay
                    )
            end

            caretY =
                userBox.y
                + textYAdjust
        else
            caretX =
                tokenBox.x + padding

            if tokentext ~= "" then
                caretX =
                    caretX
                    + font:getWidth(
                        tokenDisplay
                    )
            end

            caretY =
                tokenBox.y
                + textYAdjust
        end

        love.graphics.setColor(
            0.9,
            0.9,
            0.9,
            a
        )

        love.graphics.print(
            "|",
            caretX,
            caretY - 4
        )
    end

    local checkboxX = checkbox.x
    local checkboxY = checkbox.y
    local checkboxSize = checkbox.size

    love.graphics.setColor(
        1,
        1,
        1,
        a
    )

    love.graphics.rectangle(
        "line",
        checkboxX,
        checkboxY,
        checkboxSize,
        checkboxSize
    )

    if autologinChecked then
        love.graphics.setLineWidth(2)

        love.graphics.line(
            checkboxX + 3,
            checkboxY
                + checkboxSize * 0.55,
            checkboxX
                + checkboxSize * 0.4,
            checkboxY
                + checkboxSize
                - 4
        )

        love.graphics.line(
            checkboxX
                + checkboxSize * 0.4,
            checkboxY
                + checkboxSize
                - 4,
            checkboxX
                + checkboxSize
                - 3,
            checkboxY + 4
        )

        love.graphics.setLineWidth(1)
    end

    love.graphics.setFont(
        loginfont or font
    )

    love.graphics.print(
        i18n.t("autoLogin"),
        checkboxX
            + checkboxSize
            + padding,
        checkboxY
    )

    love.graphics.setColor(
        0.15,
        0.15,
        0.15,
        a
    )

    love.graphics.rectangle(
        "fill",
        loginBtn.x,
        loginBtn.y,
        loginBtn.w,
        loginBtn.h
    )

    love.graphics.setColor(
        1,
        1,
        1,
        a
    )

    love.graphics.rectangle(
        "line",
        loginBtn.x,
        loginBtn.y,
        loginBtn.w,
        loginBtn.h
    )

    local loginLabel =
        i18n.t("login")

    local loginLabelX =
        loginBtn.x
        + (loginBtn.w
            - font:getWidth(loginLabel))
        / 2

    local loginLabelY =
        loginBtn.y
        + math.floor(
            (loginBtn.h
                - font:getHeight())
            / 2
            + 0.5
        )

    love.graphics.print(
        loginLabel,
        loginLabelX,
        loginLabelY
    )
    if statusText ~= "" then
        if statusIsError then
            love.graphics.setColor(
                1,
                0.4,
                0.4,
                a
            )
        else
            love.graphics.setColor(
                0.4,
                1,
                0.6,
                a
            )
        end

        love.graphics.printf(
            statusText,
            panel.x + padding,
            loginBtn.y
                + loginBtn.h
                + padding,
            panel.w - padding * 2,
            "left"
        )
    end

    love.graphics.setColor(
        1,
        1,
        1,
        1
    )
end

function opening.draw()
    drawVideo()

    if logoimg then
        local logoW =
            logoimg:getWidth()
            * openingLogoScale

        local logoH =
            logoimg:getHeight()
            * openingLogoScale

        local logoX =
            displayWidth / 2
            - logoW / 2

        local logoY =
            displayHeight * 0.18
            - logoH / 2

        love.graphics.setColor(
            1,
            1,
            1,
            1
        )

        love.graphics.draw(
            logoimg,
            logoX,
            logoY,
            0,
            openingLogoScale,
            openingLogoScale
        )
    end

    local currentClickFont =
        clickfont
        or love.graphics.getFont()

    love.graphics.setFont(
        currentClickFont
    )

    local clickText =
        i18n.t("clickToStart")

    local clickY =
        displayHeight
        - currentClickFont:getHeight()
        - math.max(
            20,
            math.floor(
                displayHeight * 0.025
            )
        )

    love.graphics.setColor(
        1,
        1,
        1,
        1
    )

    love.graphics.print(
        clickText,
        displayWidth / 2
            - currentClickFont:getWidth(clickText) / 2,
        clickY
    )

    if exitfont then
        local exitText =
            i18n.t("exit")

        love.graphics.setFont(
            exitfont
        )

        love.graphics.setColor(
            1,
            1,
            1,
            1
        )

        love.graphics.rectangle(
            "line",
            exitButton.x,
            exitButton.y,
            exitButton.w,
            exitButton.h
        )

        love.graphics.print(
            exitText,
            exitButton.x
                + exitButtonPaddingX,
            exitButton.y
                + exitButtonPaddingY
        )
    end

    if gamejoltlogoimg then
        love.graphics.setColor(
            1,
            1,
            1,
            1
        )

        love.graphics.draw(
            gamejoltlogoimg,
            button.x,
            button.y,
            0,
            gamejoltLogoScale,
            gamejoltLogoScale
        )
    end

    drawLoginUi()

    love.graphics.setColor(
        1,
        1,
        1,
        1
    )
end

function opening.drawOverlay()
    if not fadeOut then
        return
    end

    love.graphics.setColor(
        0,
        0,
        0,
        fadeAlpha
    )

    love.graphics.rectangle(
        "fill",
        0,
        0,
        displayWidth,
        displayHeight
    )

    love.graphics.setColor(
        1,
        1,
        1,
        1
    )
end


return opening