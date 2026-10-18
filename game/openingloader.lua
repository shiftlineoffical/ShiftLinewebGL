---@type any
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

local play = require "gameplay.play"
local musicselect = require "musicselect"
local log = require "log"
local i18n = require "i18n"
local audiocache = require "audiocache"
local ui = require("lib.ui")
local createsfb = pcall(require, "createsfb") and require("createsfb") or nil
local gamejolt = nil
local settings = require "settings"

do
    local ok, result = pcall(require, "gamejolt")

    if ok then
        gamejolt = result
        log.info("GameJolt module loaded")
    else
        log.warn("GameJolt module failed to load: " .. tostring(result))
    end
end
local http = pcall(require, "socket.http") and require("socket.http") or nil

local openingloader = {}

local displayx, displayy = love.graphics.getDimensions()
local logotransparency = 0
local lodingfont, verfont
local logo, logox, logoy
local endsaccess = 0
local appversion = "0.4.0"
local nowappversion, nowappdownloadurl
local timer = 0
local fadingIn = true
local fadingOut = false
local heavyStarted = false

local function getPathSeparator()
    return package.config:sub(1,1)
end

local function joinPath(a,b)
    local sep = getPathSeparator()
    if not a or a == "" then return b end
    if a:sub(-1) == sep then return a..b end
    return a..sep..b
end

local function fileExists(path)
    if love and love.filesystem and love.filesystem.getInfo then
        local ok, info = pcall(love.filesystem.getInfo, path)
        if ok and info then return true end
    end
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function filterCollectionsByCharts(collections)
    if type(collections) ~= "table" then
        return {audio = {}, charts = {}, images = {}}
    end

    local chartEntries = type(collections.charts) == "table" and collections.charts or {}
    local allowedArchives = {}
    local filteredCharts = {}

    for _, entry in ipairs(chartEntries) do
        if type(entry) == "table" and type(entry.archive) == "string" and entry.archive ~= "" then
            allowedArchives[entry.archive] = true
        end
        if type(entry) == "table" then
            filteredCharts[#filteredCharts + 1] = entry
        end
    end

    local function isAllowedEntry(entry)
        if type(entry) ~= "table" then
            return false
        end
        local archive = entry.archive
        return type(archive) == "string" and archive ~= "" and allowedArchives[archive] == true
    end

    local filteredCollections = {
        audio = {},
        charts = filteredCharts,
        images = {}
    }

    for _, entry in ipairs(collections.audio or {}) do
        if isAllowedEntry(entry) then
            filteredCollections.audio[#filteredCollections.audio + 1] = entry
        end
    end

    for _, entry in ipairs(collections.images or {}) do
        if isAllowedEntry(entry) then
            filteredCollections.images[#filteredCollections.images + 1] = entry
        end
    end

    return filteredCollections
end

local function sfbcheck()
    log.info("== Direct Song Load Started ==")
    local collections = nil
    if createsfb and type(createsfb.load) == "function" then
        local ok, res = pcall(createsfb.load, createsfb, {forceRebuildAll = false})
        if ok and type(res) == "table" then
            collections = filterCollectionsByCharts(res)
        end
    end
    log.info("== Direct Song Load Completed ==")
    endsaccess = math_min(100, endsaccess + 30)
    return collections
end

local function updatechack()
    if not http or not http.request then
        log.warn("socket.http not available; skipping update check")
        return
    end
    local ok, remote = pcall(http.request, http, "https://raw.githubusercontent.com/cloudoamp/ShiftLine/refs/heads/main/update.txt")
    if not ok or type(remote) ~= "string" then
        log.warn("Update server connection failed or invalid response")
        return
    end
    -- parse simple manifest lines
    local function trim(s) return (s or ""):gsub("\r",""):match("^%s*(.-)%s*$") or "" end
    for line in remote:gmatch("[^\\r\\n]+") do
        local k,v = line:match("^%s*([%w_]+)%s*[:=]%s*(.-)%s*$")
        if k and v then
            k = k:lower()
            v = trim(v)
            if k == "version" then nowappversion = v end
            if k:find("winfileurl") then nowappdownloadurl = v end
            if k:find("macfileurl") and (love.system.getOS and love.system.getOS() == "OS X") then nowappdownloadurl = v end
            if k:find("linuxfileurl") and (love.system.getOS and love.system.getOS() == "Linux") then nowappdownloadurl = v end
        end
    end
    endsaccess = math_min(100, endsaccess + 10)
end

local function cacheStartupCollections(collections)
    openingloader._collections = collections

    if _G.main and type(_G.main) == "table" then
        _G.main.startup = _G.main.startup or {}
        _G.main.startup.collections = collections
        _G.main.startup.previewSources = _G.main.startup.previewSources or {}
    end

    return collections
end

local function performHeavyLoad()
    -- Start update check in a separate thread to avoid blocking.
    pcall(function()
        if love and love.thread then
            local ok, thread = pcall(function() return love.thread.newThread("openingloader_update_thread.lua") end)
            if ok and thread then
                pcall(function() thread:start() end)
            end
        else
            pcall(updatechack)
        end
    end)

    -- Start createsfb load in a separate thread to avoid blocking main thread.
    local threadStarted = false
    pcall(function()
        if love and love.thread then
            local ok, thread = pcall(function() return love.thread.newThread("createsfb_thread.lua") end)
            if ok and thread then
                local startOk = pcall(function() thread:start() end)
                if startOk then
                    threadStarted = true
                    openingloader._createsfbThreadStarted = true
                    openingloader._threadStartTime = love.timer.getTime and love.timer.getTime() or 0
                end
            end
        end
    end)

    -- If thread didn't start, use fallback immediately
    if not threadStarted then
        log.info("Createsfb thread not available, using fallback sync load")
        local ok, cols = pcall(sfbcheck)
        if ok and type(cols) == "table" then
            openingloader._collections = filterCollectionsByCharts(cols)
            cacheStartupCollections(openingloader._collections)
        else
            openingloader._collections = {audio = {}, charts = {}, images = {}}
        end
    end

    -- Defer actual audio preload to update() so we can process per-frame.
    if not openingloader._collections then
        openingloader._audioPreloadState = nil
    else
        local entries = openingloader._collections.audio or {}
        if #entries > 0 then
            openingloader._audioPreloadState = {entries = entries, idx = 1, loaded = 0, total = #entries}
        end
    end

    pcall(function() if play and type(play.preloadCommonAudio) == "function" then play.preloadCommonAudio() end end)

    pcall(function()
        if gamejolt and type(gamejolt.load) == "function" then
            local authenticated = gamejolt.load()

            if authenticated
                and settings
                and type(settings.loadFromGameJolt) == "function"
            then
                settings.loadFromGameJolt()
            end
        end
    end)

    log.info("Started asynchronous createsfb and update tasks")
end

function openingloader.getCollections()
    return openingloader._collections
end

function openingloader.load()
    love.window.setTitle("ShiftLine - ver"..appversion)
    logo = love.graphics.newImage("img/logo.png")
    logox = logo and logo:getWidth() or 0
    logoy = logo and logo:getHeight() or 0

    lodingfont = ui.newFont("lib/data/fonts/NotoSansJP-ExtraLight.ttf", 40)
    verfont = ui.newFont("lib/data/fonts/NotoSansJP-ExtraLight.ttf", 20)

    heavyStarted = false
    openingloader._deferred = true
end

function openingloader.update(dt)
    if fadingIn then
        logotransparency = math_min(1, logotransparency + dt)
        endsaccess = math_min(100, endsaccess + dt * 30)
        if endsaccess >= 100 then fadingIn = false; timer = 0 end
        return
    end

    if openingloader._deferred and not heavyStarted then
        heavyStarted = true
        -- run heavy load (which starts an async update-check thread) but protect errors
        pcall(performHeavyLoad)
        openingloader._deferred = false
    end

    -- Check for update thread result and parse manifest when available
    if love and love.thread and http then
        local ch = love.thread.getChannel("openingloader_update_channel")
        local msg = ch:pop()
        if msg and type(msg) == "table" then
            if msg.ok and type(msg.body) == "string" then
                -- simple parse: extract version and urls
                for line in msg.body:gmatch("[^\r\n]+") do
                    local k,v = line:match("^%s*([%w_]+)%s*[:=]%s*(.-)%s*$")
                    if k and v then
                        k = k:lower(); v = v:gsub("\r",""):match("^%s*(.-)%s*$")
                        if k == "version" then nowappversion = v end
                        if k:find("winfileurl") then nowappdownloadurl = v end
                    end
                end
                endsaccess = math_min(100, endsaccess + 5)
            else
                log.warn("Update thread failed: " .. tostring(msg.err))
            end
        end
    end

    if not fadingOut then
        timer = timer + dt
        if timer >= 1 then
            fadingOut = true
            timer = 0
        end
        return
    end

    -- If createsfb thread has produced collections, handle them and start incremental audio preload.
    if not openingloader._audioPreloadState then
        if love and love.thread then
            local ch = love.thread.getChannel("openingloader_createsfb_channel")
            local msg = ch:pop()
            if msg and type(msg) == "table" then
                if msg.ok and type(msg.result) == "table" then
                    local collections = filterCollectionsByCharts(msg.result)
                    cacheStartupCollections(collections)
                    local entries = openingloader._collections.audio or {}
                    if #entries > 0 then
                        openingloader._audioPreloadState = {entries = entries, idx = 1, loaded = 0, total = #entries}
                    end
                    pcall(function()
                        if musicselect and type(musicselect.setStartupAssets) == "function" then
                            musicselect.setStartupAssets(openingloader._collections, {})
                        end
                    end)
                    pcall(function()
                        if play and type(play.setCollections) == "function" then
                            play.setCollections(openingloader._collections)
                        end
                    end)
                else
                    log.warn("createsfb thread failed: " .. tostring(msg.err))
                end
            -- Thread timeout: if thread is still pending after 8 seconds, use fallback
            elseif openingloader._createsfbThreadStarted and openingloader._threadStartTime then
                local currentTime = love.timer.getTime and love.timer.getTime() or 0
                if currentTime - openingloader._threadStartTime > 8 then
                    log.warn("createsfb thread timeout, using fallback")
                    local ok, cols = pcall(sfbcheck)
                    if ok and type(cols) == "table" then
                        cacheStartupCollections(filterCollectionsByCharts(cols))
                    else
                        cacheStartupCollections({audio = {}, charts = {}, images = {}})
                    end
                    openingloader._createsfbThreadStarted = false
                    local entries = openingloader._collections.audio or {}
                    if #entries > 0 then
                        openingloader._audioPreloadState = {entries = entries, idx = 1, loaded = 0, total = #entries}
                    end
                end
            end
        end
    end

    if openingloader._audioPreloadState then
        local st = openingloader._audioPreloadState
        local batch = 6  -- Increased from 3 to 6 for faster preload
        for i = 1, batch do
            if st.idx > st.total then break end
            local entry = st.entries[st.idx]
            if entry then
                local ok, rec = pcall(audiocache.preloadEntry, openingloader._collections, entry)
                if ok and rec and rec.soundData then
                    st.loaded = st.loaded + 1
                end
            end
            st.idx = st.idx + 1
        end
        if st.total > 0 then
            endsaccess = math_min(100, endsaccess + (st.loaded / math_max(1, st.total)) * 10)  -- Increased multiplier from 5 to 10
        end
        if st.idx > st.total then
            log.info(string_format("Preloaded audio at startup: %d/%d", st.loaded, st.total))
            openingloader._audioPreloadState = nil
            endsaccess = math_min(100, endsaccess + 15)  -- Increased from 10 to 15
        end
    end

    logotransparency = math_max(0, logotransparency - dt)
    if logotransparency <= 0 then openingloader.endprocess = true end
end

function openingloader.draw()
    displayx, displayy = love.graphics.getDimensions()
    love.graphics.setFont(lodingfont)
    local percentText = tostring(math_floor(endsaccess)) .. "%"
    local percentHalfWidth = lodingfont:getWidth(percentText) / 2
    love.graphics.setColor(1,1,1,logotransparency)
    love.graphics.print(percentText, displayx/10*8.5+100, displayy/10*9-40, 0, 1, 1, percentHalfWidth, lodingfont:getHeight()/2)
    love.graphics.rectangle("line", displayx/10*8.5, displayy/10*9, 200, 20)
    love.graphics.setFont(verfont)
    love.graphics.rectangle("fill", displayx/10*8.5, displayy/10*9, endsaccess*2, 20)
    pcall(function() love.graphics.print(i18n.t("Version")..appversion,10,displayy/10*9) end)

    -- Show small status line under progress bar
    local statusText = ""
    if openingloader._deferred and not heavyStarted then
        statusText = "Preparing..."
    elseif heavyStarted and (not openingloader.endprocess) then
        statusText = "Loading assets..."
    elseif openingloader.endprocess then
        statusText = "Finishing..."
    end
    love.graphics.setFont(ui.newFont("lib/data/fonts/NotoSansJP-ExtraLight.ttf", 16))
    love.graphics.setColor(1,1,1,logotransparency * 0.9)
    love.graphics.print(statusText, displayx/10*8.5, displayy/10*9 + 24)
end

return openingloader
