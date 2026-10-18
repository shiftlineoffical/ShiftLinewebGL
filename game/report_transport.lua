local JSON = require "JSON"
local curlUtils = require "curl_utils"
local log = require "log"

local transport = {}

local REPORT_WORKER_URL = "https://shiftline-server.cloudoam.workers.dev/report"

local function escapeCurlConfig(value)
    return tostring(value)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\r", "")
        :gsub("\n", "")
end

local function removeFile(path)
    if path then
        local existingFile = io.open(path, "rb")
        if not existingFile then
            return
        end
        existingFile:close()

        local ok, err = os.remove(path)
        if not ok then
            log.warn("[report_transport] Could not remove temporary request file: " .. tostring(err))
        end
    end
end

local function readResponseBody(path)
    local file, openError = io.open(path, "rb")
    if not file then
        return nil, "Could not open curl response: " .. tostring(openError)
    end
    local body, readError = file:read("*a")
    file:close()
    if type(body) ~= "string" then
        return nil, "Could not read curl response: " .. tostring(readError)
    end
    return body
end

local function sendWithCurl(url, body)
    local tempDir = curlUtils.getTempDir()
    local nonce = string.format(
        "%d_%06d",
        os.time(),
        math.random(100000, 999999)
    )
    local bodyPath = curlUtils.joinPath(tempDir, "shiftline_report_" .. nonce .. ".json")
    local configPath = curlUtils.joinPath(tempDir, "shiftline_report_" .. nonce .. ".curl")
    local responsePath = curlUtils.joinPath(tempDir, "shiftline_report_" .. nonce .. ".response")

    local bodyFile, bodyOpenError = io.open(bodyPath, "wb")
    if not bodyFile then
        return false, "Cannot create temporary request body: " .. tostring(bodyOpenError)
    end
    local bodyOK, bodyError = bodyFile:write(body)
    bodyFile:close()
    if not bodyOK then
        removeFile(bodyPath)
        return false, "Cannot write temporary request body: " .. tostring(bodyError)
    end

    local configFile, configOpenError = io.open(configPath, "wb")
    if not configFile then
        removeFile(bodyPath)
        return false, "Cannot create temporary curl config: " .. tostring(configOpenError)
    end
    local config = table.concat({
        'url = "' .. escapeCurlConfig(url) .. '"\n',
        'request = "POST"\n',
        'header = "Content-Type: application/json"\n',
        'data-binary = "@' .. escapeCurlConfig(bodyPath) .. '"\n',
        'write-out = "%{http_code}"\n',
        'max-time = 10\n',
        'proto = "=https"\n'
    })
    local configOK, configError = configFile:write(config)
    configFile:close()
    if not configOK then
        removeFile(bodyPath)
        removeFile(configPath)
        return false, "Cannot write temporary curl config: " .. tostring(configError)
    end

    local curlPath = curlUtils.getPath()
    local quotedCurlPath = curlUtils.quote(curlPath)
    if curlUtils.isWindows() and not curlPath:find("%s") then
        quotedCurlPath = curlPath
    end
    local command = table.concat({
        quotedCurlPath,
        " --silent --show-error --output ",
        curlUtils.quote(responsePath),
        " --config ",
        curlUtils.quote(configPath),
        " 2>&1"
    })
    local popenOK, handle = pcall(io.popen, command, "r")
    if not popenOK or not handle then
        removeFile(bodyPath)
        removeFile(configPath)
        removeFile(responsePath)
        return false, "Could not start curl: " .. tostring(handle)
    end

    local readOK, response = pcall(handle.read, handle, "*a")
    local closeOK, exitOK, exitReason, exitCode = pcall(handle.close, handle)
    removeFile(bodyPath)
    removeFile(configPath)

    if not readOK then
        removeFile(responsePath)
        return false, "Could not read curl response: " .. tostring(response)
    end
    if not closeOK then
        removeFile(responsePath)
        return false, "Could not close curl process: " .. tostring(exitOK)
    end

    local statusCode = tonumber((response or ""):match("(%d%d%d)%s*$"))
    local processStatus = tostring(exitOK)
    if exitReason then
        processStatus = processStatus .. " " .. tostring(exitReason)
    end
    if exitCode ~= nil then
        processStatus = processStatus .. " " .. tostring(exitCode)
    end
    local processSucceeded = exitOK == true
        or (exitReason == "exit" and tonumber(exitCode) == 0)
        or (type(exitOK) == "number" and exitOK == 0)
    if not processSucceeded or not statusCode or statusCode < 200 or statusCode >= 300 then
        removeFile(responsePath)
        local processOutput = tostring(response or "")
            :gsub("[%c]+", " ")
            :match("^%s*(.-)%s*$")
        if #processOutput > 512 then
            processOutput = processOutput:sub(1, 512)
        end
        return false, string.format(
            "HTTPS report request failed (HTTP %s, process %s%s)",
            tostring(statusCode or "unknown"),
            processStatus,
            processOutput ~= "" and (", curl: " .. processOutput) or ""
        )
    end

    local responseBody, responseReadError = readResponseBody(responsePath)
    removeFile(responsePath)
    if not responseBody then
        return false, responseReadError
    end

    local decodeOK, decodedResponse = pcall(JSON.decode, JSON, responseBody)
    if not decodeOK
        or type(decodedResponse) ~= "table"
        or decodedResponse.ok ~= true then
        local responseMessage = type(decodedResponse) == "table"
            and type(decodedResponse.error) == "string"
            and decodedResponse.error
            or responseBody
        responseMessage = tostring(responseMessage)
            :gsub("[%c]+", " ")
            :match("^%s*(.-)%s*$")
        if #responseMessage > 256 then
            responseMessage = responseMessage:sub(1, 256)
        end
        return false, "Report server returned an unexpected response: "
            .. (responseMessage ~= "" and responseMessage or "empty response")
    end
    return true
end

function transport.send(kind, payload)
    if type(kind) ~= "string"
        or type(payload) ~= "table"
        or (kind ~= "error_report" and kind ~= "feedback") then
        return false, "Invalid report message"
    end

    if type(REPORT_WORKER_URL) ~= "string"
        or not REPORT_WORKER_URL:match("^https://[%w%.%-]+/[%w%-%_/%?=&%.]*$") then
        local err = "Set REPORT_WORKER_URL to the deployed Cloudflare Worker HTTPS URL"
        log.error("[report_transport] " .. err)
        return false, err
    end

    local request = {kind = kind, payload = payload}

    local encodeOK, body = pcall(function()
        return JSON:encode(request)
    end)
    if not encodeOK or type(body) ~= "string" then
        local err = tostring(body or "JSON encoding failed")
        log.error("[report_transport] Failed to encode report payload: " .. err)
        return false, err
    end

    local sendOK, sent, sendError = pcall(
        sendWithCurl,
        REPORT_WORKER_URL,
        body
    )
    if not sendOK then
        local err = tostring(sent or "HTTPS report sender raised an error")
        log.error("[report_transport] " .. err)
        return false, err
    end
    if sent ~= true then
        local err = tostring(sendError or "HTTPS report request failed")
        log.error("[report_transport] " .. err)
        return false, err
    end

    return true
end

return transport
