local JSON = require "JSON"
local curlUtils = require "curl_utils"
local ch = love.thread.getChannel("play_song_request_channel")
local resultCh = love.thread.getChannel("play_song_request_result_channel")
local data = ch:demand()
local song = data and data.song or ""
local difficulty = data and data.difficulty or ""
local musicCountUrl = curlUtils.musicCountUrl

local function urlEncode(str)
    if type(str) ~= "string" then
        return ""
    end
    return str:gsub("([^%w%-_.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function sendRequest(song, difficulty)
    if type(song) ~= "string" or song == "" then
        return "Request count unavailable", false
    end

    local safeDifficulty = ""
    if difficulty ~= nil then
        safeDifficulty = tostring(difficulty)
    end
    local requestBody = "song=" .. urlEncode(song) .. "&difficulty=" .. urlEncode(safeDifficulty)

    local curlPath = curlUtils.getPath()
    local workdir = curlUtils.getTempDir()
    local body_file = curlUtils.joinPath(workdir, "musiccount_body_" .. tostring(os.time()) .. ".txt")
    local body_handle = io.open(body_file, "wb")
    if body_handle then
        body_handle:write(requestBody)
        body_handle:close()
    else
        return "Request count unavailable", false
    end

    local curl_cmd = curlUtils.quote(curlPath) .. ' --connect-timeout 10 --max-time 30 -sSL -L -i --get ' .. curlUtils.quote(musicCountUrl) .. ' --data-binary @' .. curlUtils.quote(body_file) .. ' -w "\n--CURL_EXIT--%{exitcode}\n--CURL_STATUS--%{http_code}" 2>&1'

    local handle = io.popen(curl_cmd)
    local curl_output = ""
    if handle then
        curl_output = handle:read("*a") or ""
        handle:close()
    end
    pcall(os.remove, body_file)

    local status = 500
    local responseBody = ""

    if curl_output and curl_output ~= "" then
        local status_marker = curl_output:match("%-%-CURL_STATUS%-%-(%d+)")
        if status_marker then
            status = tonumber(status_marker) or 500
        else
            local last_status = nil
            for code in curl_output:gmatch("HTTP/[%d%.]+%s+(%d+)") do
                last_status = tonumber(code)
            end
            if last_status then
                status = last_status
            end
        end

        local body = curl_output:match(".*\r\n\r\n(.*)%-%-CURL_STATUS%-%-%d+") or curl_output:match(".*\n\n(.*)%-%-CURL_STATUS%-%-%d+") or curl_output:match(".*\r\n\r\n(.*)") or curl_output:match(".*\n\n(.*)")
        if body then
            responseBody = body
        else
            responseBody = curl_output
        end
    end

    if responseBody == "" or status ~= 200 then
        return "Request count unavailable", false
    end

    if responseBody:match("function[^<]*not found") then
        return "Request count unavailable", false
    end

    if responseBody:match("^%s*<html") then
        return "Request sent", true
    end

    local ok, decoded = pcall(JSON.decode, JSON, responseBody)
    if not ok or type(decoded) ~= "table" then
        return "Request count unavailable", true
    end

    local success = decoded.success == true or tostring(decoded.status or ""):lower() == "ok"
    if not success then
        local countText = tostring(decoded.count or decoded.song or "?")
        if decoded.count == nil and decoded.song then
            countText = "logged"
        end
        return "Request count: " .. countText, true
    end

    local countText = tostring(decoded.count or decoded.song or "?")
    if decoded.count == nil and decoded.song then
        countText = "logged"
    end

    return "Request count: " .. countText, true
end

local countText, success = sendRequest(song, difficulty)
resultCh:push({countText = countText, ok = success})
