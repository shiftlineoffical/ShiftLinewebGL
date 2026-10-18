local M = {}

M.musicCountUrl = "https://script.google.com/macros/s/AKfycbxY2r67YHH3sHB90RMLli2bTb_8uZDCYX0k97YaSwwo5yHdEkByn02Ys-dzXu9YP5eymQ/exec"

local function getOS()
    return love and love.system and love.system.getOS and love.system.getOS() or "Windows"
end

function M.isWindows()
    return getOS() == "Windows"
end

local function isMacOS(osName)
    return osName == "OS X" or osName == "macOS"
end

function M.getPath()
    local configuredPath = os.getenv("CURL")
    if configuredPath and configuredPath ~= "" then
        return configuredPath
    end

    local osName = getOS()
    if isMacOS(osName) then
        local systemCurl = "/usr/bin/curl"
        local handle = io.open(systemCurl, "rb")
        if handle then
            handle:close()
            return systemCurl
        end
        return "curl"
    end

    if osName == "Windows" then
        local windir = os.getenv("WINDIR") or "C:\\Windows"
        local systemCurl = windir .. "\\System32\\curl.exe"
        local handle = io.open(systemCurl, "rb")
        if handle then
            handle:close()
            return systemCurl
        end
        return "curl.exe"
    end

    return "curl"
end

function M.getTempDir()
    local osName = getOS()
    if osName == "Windows" then
        local candidates = {
            (os.getenv("WINDIR") or "C:\\Windows") .. "\\Temp"
        }
        local tempDirectory = os.getenv("TEMP")
        local tmpDirectory = os.getenv("TMP")
        if tempDirectory then
            candidates[#candidates + 1] = tempDirectory
        end
        if tmpDirectory then
            candidates[#candidates + 1] = tmpDirectory
        end

        for _, directory in ipairs(candidates) do
            if type(directory) == "string"
                and directory ~= ""
                and not directory:find("[^\032-\126]") then
                local probeName = string.format(
                    "shiftline_temp_probe_%d_%06d",
                    os.time(),
                    math.random(100000, 999999)
                )
                local probePath = directory:gsub("[\\\\/]$", "")
                    .. "\\"
                    .. probeName
                local probe = io.open(probePath, "wb")
                if probe then
                    probe:close()
                    os.remove(probePath)
                    return directory
                end
            end
        end

        return os.getenv("TEMP")
            or os.getenv("TMP")
            or "C:\\Windows\\Temp"
    end

    local candidates = {}
    local tempDirectory = os.getenv("TMPDIR")
    if tempDirectory and tempDirectory ~= "" then
        candidates[#candidates + 1] = tempDirectory
    end
    candidates[#candidates + 1] = "/tmp"

    for _, directory in ipairs(candidates) do
        local probeName = string.format(
            "shiftline_temp_probe_%d_%06d",
            os.time(),
            math.random(100000, 999999)
        )
        local probePath = directory:gsub("[\\\\/]$", "")
            .. "/"
            .. probeName
        local probe = io.open(probePath, "wb")
        if probe then
            probe:close()
            os.remove(probePath)
            return directory
        end
    end

    return tempDirectory or "/tmp"
end

function M.joinPath(directory, filename)
    local separator = M.isWindows() and "\\" or "/"
    return directory:gsub("[\\\\/]$", "") .. separator .. filename
end

function M.quote(value)
    value = tostring(value)
    if M.isWindows() then
        return '"' .. value:gsub('"', '\\"') .. '"'
    end

    return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.nullDevice()
    return M.isWindows() and "NUL" or "/dev/null"
end

return M
