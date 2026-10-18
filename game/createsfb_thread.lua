-- createsfb_thread.lua
-- スレッド内で楽曲リストを読み込む（ブロッキングなし）

local love = love
local pcall = pcall
local require = require
local type = type
local tostring = tostring

-- デバッグログ出力（オプション）
local function logThreadMsg(msg)
    if love and love.thread and love.thread.getChannel then
        local ch = love.thread.getChannel("openingloader_log_channel")
        if ch then
            pcall(function() ch:push({level = "info", msg = msg}) end)
        end
    end
end

-- スレッド内で実行される処理
local function runCreatesfbLoad()
    -- 依存モジュールの読み込み
    local createsfb_ok, createsfb = pcall(require, "createsfb")
    if not createsfb_ok or not createsfb then
        return {ok = false, err = "createsfb module not found"}
    end

    local log_ok, log = pcall(require, "log")
    if not log_ok or not log then
        log = {info = function() end, warn = function() end, error = function() end}
    end

    -- スレッド開始ログ
    if log and type(log.info) == "function" then pcall(log.info) end

    -- createsfb から楽曲リストを読み込む
    local collections = nil
    if type(createsfb.load) == "function" then
        local ok, res = pcall(createsfb.load, createsfb, {forceRebuildAll = false})
        if ok and type(res) == "table" then
            collections = res
        end
    end

    -- 完了ログ
    if log and type(log.info) == "function" then pcall(log.info) end

    return {ok = true, result = collections}
end

-- メイン実行
local result = runCreatesfbLoad()

-- 結果をチャネルを通じてメインスレッドに返す
if love and love.thread then
    local ch = love.thread.getChannel("openingloader_createsfb_channel")
    if ch then
        pcall(function() ch:push(result) end)
    end
end
