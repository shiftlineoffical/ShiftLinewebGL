local json = require("lib.plugins.gamejolt.json")

local SAVE_FILE_NAME = "gamejolt_login.json"

local gamejoltuser = {
    userid = "",
    user_token = "",
    autologin = false,
}

local function hasFilesystem()
    return love and love.filesystem and love.filesystem.getInfo and love.filesystem.read and love.filesystem.write
end

local function getPathSeparator()
    return package.config and package.config:sub(1, 1) or "/"
end

local function joinPath(a, b)
    local sep = getPathSeparator()
    if not a or a == "" then return b end
    if a:sub(-1) == sep then return a .. b end
    return a .. sep .. b
end

local function fileExists(path)
    if love and love.filesystem and love.filesystem.getInfo then
        local ok, info = pcall(love.filesystem.getInfo, path)
        if ok and info then return true end
    end
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function getSfbDirectory()
    if not (love and love.filesystem) then return nil end

    local saveDir = love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory() or nil
    local sourceDir = love.filesystem.getSourceBaseDirectory and love.filesystem.getSourceBaseDirectory() or nil

    if love.filesystem.getDirectoryItems then
        local items = love.filesystem.getDirectoryItems("") or {}
        for _, name in ipairs(items) do
            if type(name) == "string" and name:match("%.sfb$") then
                if saveDir and fileExists(joinPath(saveDir, name)) then
                    return saveDir
                end
                if sourceDir and fileExists(joinPath(sourceDir, name)) then
                    return sourceDir
                end
            end
        end
    end

    if saveDir and saveDir ~= "" then return saveDir end
    if sourceDir and sourceDir ~= "" then return sourceDir end
    return nil
end

local function getLoginPath()
    if love and love.filesystem and love.filesystem.getSaveDirectory then
        local saveDir = love.filesystem.getSaveDirectory()
        if saveDir and saveDir ~= "" then
            return SAVE_FILE_NAME, saveDir
        end
    end
    return SAVE_FILE_NAME, nil
end

local function readFile(path)
    if love and love.filesystem and love.filesystem.read then
        local ok, data = pcall(love.filesystem.read, path)
        if ok and type(data) == "string" and data ~= "" then
            return data
        end
    end
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function writeFile(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function removeFile(path)
    if os.remove then
        local ok = os.remove(path)
        return ok == true
    end
    return false
end

function gamejoltuser.load()
    if not hasFilesystem() then return false end

    local path, dir = getLoginPath()
    local raw = nil

    if dir and love.filesystem and love.filesystem.getSaveDirectory and dir == love.filesystem.getSaveDirectory() then
        if not love.filesystem.getInfo(SAVE_FILE_NAME) then return false end
        local okRead, data = pcall(love.filesystem.read, SAVE_FILE_NAME)
        if okRead and type(data) == "string" and data ~= "" then
            raw = data
        end
    else
        if not fileExists(path) then return false end
        raw = readFile(path)
    end

    if type(raw) ~= "string" or raw == "" then return false end

    local okDecode, data = pcall(function() return json:decode(raw) end)
    if not okDecode or type(data) ~= "table" then return false end

    if type(data.userid) == "string" then gamejoltuser.userid = data.userid end
    if type(data.user_token) == "string" then gamejoltuser.user_token = data.user_token end
    gamejoltuser.autologin = (data.autologin == true)

    return true
end

function gamejoltuser.save(userid, token, autologin)
    gamejoltuser.userid = userid or ""
    gamejoltuser.user_token = token or ""
    gamejoltuser.autologin = (autologin == true)

    if not hasFilesystem() then return false end

    local payload = {
        userid = gamejoltuser.userid,
        user_token = gamejoltuser.user_token,
        autologin = gamejoltuser.autologin,
    }
    local raw = json:encode(payload)

    local path, dir = getLoginPath()

    if dir and love.filesystem and love.filesystem.getSaveDirectory and dir == love.filesystem.getSaveDirectory() then
        local okWrite, wrote = pcall(love.filesystem.write, SAVE_FILE_NAME, raw)
        return okWrite == true and wrote ~= nil
    end

    return writeFile(path, raw)
end

function gamejoltuser.clear()
    gamejoltuser.autologin = false
    if not (love and love.filesystem and love.filesystem.remove) then return false end

    local path, dir = getLoginPath()
    if dir and love.filesystem and love.filesystem.getSaveDirectory and dir == love.filesystem.getSaveDirectory() then
        if love.filesystem.getInfo(SAVE_FILE_NAME) then
            local okRemove, removed = pcall(love.filesystem.remove, SAVE_FILE_NAME)
            if okRemove ~= true or removed == nil then return false end
        end
        return true
    end

    if fileExists(path) then
        local ok = removeFile(path)
        if ok then return true end
    end

    if love.filesystem.getInfo(SAVE_FILE_NAME) then
        local okRemove, removed = pcall(love.filesystem.remove, SAVE_FILE_NAME)
        if okRemove ~= true or removed ~= true then return false end
    end
    return true
end

-- Load saved credentials if present.
pcall(gamejoltuser.load)

return gamejoltuser
