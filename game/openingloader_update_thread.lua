-- openingloader_update_thread.lua
-- スレッド内でバージョン更新情報を確認する

local love = love
local pcall = pcall
local require = require
local type = type
local tostring = tostring

-- スレッド内で実行される処理
local function runUpdateCheck()
    -- socket.http が必要
    local http_ok, http = pcall(require, "socket.http")
    if not http_ok or not http then
        return {ok = false, err = "socket.http not available"}
    end

    local log_ok, log = pcall(require, "log")
    if not log_ok or not log then
        log = {info = function() end, warn = function() end, error = function() end}
    end

    if log and type(log.info) == "function" then pcall(log.info) end

    -- バージョン確認URL から情報を取得
    local remote = nil
    local ok, result = pcall(function()
        return http.request("https://raw.githubusercontent.com/cloudoamp/ShiftLine/refs/heads/main/update.txt")
    end)

    if ok and type(result) == "string" then
        remote = result
        if log and type(log.info) == "function" then pcall(log.info) end
        return {ok = true, body = remote}
    else
        if log and type(log.warn) == "function" then pcall(log.warn) end
        return {ok = false, err = tostring(result or "unknown error")}
    end
end

-- メイン実行
local result = runUpdateCheck()

-- 結果をチャネルを通じてメインスレッドに返す
if love and love.thread then
    local ch = love.thread.getChannel("openingloader_update_channel")
    if ch then
        pcall(function() ch:push(result) end)
    end
end
