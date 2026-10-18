local window = {
    lastWindowedWidth = nil,
    lastWindowedHeight = nil
}

function window.getSize()
    return love.graphics.getDimensions()
end

function window.setSize(width, height)
    width = math.max(320, math.floor(tonumber(width) or 1280))
    height = math.max(240, math.floor(tonumber(height) or 720))
    window.lastWindowedWidth = width
    window.lastWindowedHeight = height
    return love.window.setMode(width, height, {
        fullscreen = false,
        fullscreentype = "desktop"
    })
end

function window.applyMode(width, height, options)
    options = options or {}
    width = math.max(320, math.floor(tonumber(width) or 1280))
    height = math.max(240, math.floor(tonumber(height) or 720))

    window.lastWindowedWidth = width
    window.lastWindowedHeight = height

    return love.window.setMode(width, height, {
        fullscreen = options.fullscreen == true,
        fullscreentype = "desktop",
        vsync = options.vsync
    })
end

function window.isFullscreen()
    return love.window.getFullscreen()
end

function window.setFullscreen(enabled)
    if enabled then
        if not window.isFullscreen() then
            window.lastWindowedWidth, window.lastWindowedHeight = love.graphics.getDimensions()
        end
        return love.window.setFullscreen(true, "desktop")
    end

    local changed = love.window.setFullscreen(false)
    if not window.lastWindowedWidth or not window.lastWindowedHeight then
        local settings = package.loaded.settings
        local displaySettings = settings
            and settings.settingsdata
            and settings.settingsdata.displaysettings
        local displaySize = displaySettings and displaySettings.displaysize
        if type(displaySize) == "table" then
            window.lastWindowedWidth = tonumber(displaySize[1])
            window.lastWindowedHeight = tonumber(displaySize[2])
        end
    end

    if window.lastWindowedWidth and window.lastWindowedHeight then
        love.window.setMode(window.lastWindowedWidth, window.lastWindowedHeight, {
            fullscreen = false,
            fullscreentype = "desktop"
        })
    end
    return changed
end

function window.toggleFullscreen()
    return window.setFullscreen(not window.isFullscreen())
end

function window.resize(width, height)
    if width and height and not window.isFullscreen() then
        window.lastWindowedWidth = width
        window.lastWindowedHeight = height
    end
end

return window