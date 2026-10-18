-- JSON.lua
local json_ok, json = pcall(require, "JSON")
local reportTransport = require "report_transport"
local log = require "log"
local M = {}

local ERROR_FILE = "last_error.json"


local function saveLocal(data)
    if not (love and love.filesystem and love.filesystem.write) then
        return false
    end

    local ok, result, err = pcall(
        love.filesystem.write,
        ERROR_FILE,
        data
    )
    if not ok or not result then
        return false, tostring(err or result or "write failed")
    end
    return true
end

local function removeLocal()
    if not (love and love.filesystem and love.filesystem.remove) then
        return false
    end

    local ok, result, err = pcall(
        love.filesystem.remove,
        ERROR_FILE
    )
    if not ok or not result then
        return false, tostring(err or result or "remove failed")
    end
    return true
end


local function generateCrashID()
    local base = os.time()
    local randomPart = math.random(100000, 999999)

    return string.format(
        "CRASH-%d-%06d",
        base,
        randomPart
    )
end


function M.report(msg, trace)
    local crashID = generateCrashID()

    local payload = {
        crash_id = crashID,
        message = tostring(msg or ""),
        traceback = tostring(trace or ""),
        os = (love and love.system and love.system.getOS and love.system.getOS()) or "unknown",
        version = (love and love.getVersion and select(2, love.getVersion())) or "unknown",
        time = os.date("%Y-%m-%d %H:%M:%S")
    }

    if not json_ok or not json then
        log.error("[error_reporter] JSON module unavailable; crash report could not be encoded")
        return crashID
    end

    local encodedOK, localJSON = pcall(json.encode_pretty, json, payload)
    if not encodedOK or type(localJSON) ~= "string" then
        log.error("[error_reporter] Failed to encode crash report: " .. tostring(localJSON))
        return crashID
    end

    local saved, saveError = saveLocal(localJSON)
    if not saved then
        log.error("[error_reporter] Failed to persist crash report: " .. tostring(saveError))
    end

    local sent, sendError = reportTransport.send("error_report", payload)
    if sent then
        local removed, removeError = removeLocal()
        if not removed then
            log.warn("[error_reporter] Delivered crash report could not be removed from the retry queue: " .. tostring(removeError))
        end
    else
        log.warn("[error_reporter] Crash report remains queued locally: " .. tostring(sendError))
    end

    return crashID
end



function M.resendIfExists()
    if not (
        love and
        love.filesystem and
        love.filesystem.getInfo and
        love.filesystem.read
    ) then
        return false
    end

    local info = love.filesystem.getInfo(ERROR_FILE)

    if not info then
        return false
    end

    local ok, raw = pcall(
        love.filesystem.read,
        ERROR_FILE
    )

    if ok and type(raw) == "string" and raw ~= "" and type(json.decode) == "function" then
        local decodeOK, decoded = pcall(json.decode, json, raw)

        if decodeOK and type(decoded) == "table" then
            local sent, sendError = reportTransport.send("error_report", decoded)
            if sent then
                local removed, removeError = removeLocal()
                if not removed then
                    log.warn("[error_reporter] Delivered crash report remains in the retry queue: " .. tostring(removeError))
                end
                return removed
            end
            log.warn("[error_reporter] Queued crash report could not be resent: " .. tostring(sendError))
        elseif not decodeOK then
            log.error("[error_reporter] Failed to decode queued crash report: " .. tostring(decoded))
        end
    end

    return false
end






return M