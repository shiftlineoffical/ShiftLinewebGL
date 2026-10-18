local bluescreen = {}

local displayWidth, displayHeight = love.graphics.getDimensions()
local state = "idle"
local countdown = 10
local countdownTimer = 0
local flashTimer = 0
local font = nil
local monospaceFont = nil

local function initFonts()
    if not font then
        font = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", 20)
        monospaceFont = love.graphics.newFont("lib/data/fonts/NotoSansJP-Light.ttf", 18)
    end
end

local function drawGlitchOverlay()
    love.graphics.setColor(1, 1, 1, 0.08)
    for y = 0, displayHeight, 4 do
        love.graphics.rectangle("fill", 0, y, displayWidth, 1)
    end
end

function bluescreen.start()
    state = "bsod"
    countdown = 10
    countdownTimer = 0
    flashTimer = 0
    initFonts()
end

function bluescreen.isActive()
    return state ~= "idle"
end

function bluescreen.update(dt)
    if state == "idle" then
        return
    end

    if state == "bsod" then
        countdownTimer = countdownTimer + dt
        if countdownTimer >= 1 then
            countdownTimer = countdownTimer - 1
            countdown = countdown - 1
            if countdown <= 0 then
                state = "flash"
                flashTimer = 0
            end
        end
    elseif state == "flash" then
        flashTimer = flashTimer + dt
        if flashTimer >= 2.8 then
            state = "idle"
        end
    end
end

local function drawBSODScreen()
    love.graphics.clear(0, 0, 0.67)
    love.graphics.setFont(monospaceFont)
    love.graphics.setColor(1, 1, 1)

    local x, y = 40, 40
    local lineHeight = monospaceFont:getHeight() * 1.3
    local lines = {
        "OS:[ShiftLine] SYSTEM_FAILURE",
        "",
        "A problem has been detected and OS:[ShiftLine] has been shut down to prevent damage to your memory_address.",
        "",
        "* Check to be sure you have adequate disk space.",
        "* If a driver is identified in the stop message, disable the driver or check with the manufacturer for updates.",
        "",
        "Technical information:",
        "*** STOP: 0x0000008E (0xC0000005, 0x8054DF87, 0xB8F97810, 0x00000000)",
        "*** [nil]_POINTER_DEREFERENCE",
        "",
        "Beginning dump of physical memory...",
        "Physical memory dump complete.",
        string.format("System reboot in %d seconds...", countdown)
    }

    for _, line in ipairs(lines) do
        love.graphics.print(line, x, y)
        y = y + lineHeight
    end

    drawGlitchOverlay()
end

function bluescreen.draw()
    if state == "idle" then
        return
    end

    drawBSODScreen()
    if state == "flash" then
        love.graphics.setColor(1, 1, 1, math.min(flashTimer / 2.5, 1))
        love.graphics.rectangle("fill", 0, 0, displayWidth, displayHeight)
    end
end

return bluescreen