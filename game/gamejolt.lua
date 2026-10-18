local gamejolt = {}
local gamejoltuserdata={

    userid="",
    username="",
    user_token=""
}
local gamejoltapi=require "lib.plugins.gamejolt.gamejolt_api"
setmetatable(gamejolt, { __index = gamejoltapi })
local gamejoltuser=require "gamejoltuser"
local log = require "log"
local JSON = require "JSON"

-- 状態を外部から参照できるようにする
gamejolt.status = {
    authenticated = false,
    message = "",
    username = "",
    userId = "",
    avatarUrl = "",
}
gamejolt.username = ""
gamejolt.userToken = ""
gamejolt.isLoggedIn = false

gamejolt.memory = {
    resultScore = nil,
    resultRating = nil,
    resultSummary = nil,
    lastLoadedAt = nil,
}

local userdata={}
local useravaterurl=""
local userid=""


local function updateStatus(authenticated, message)
    gamejolt.status.authenticated = authenticated
    gamejolt.status.message = message
    gamejolt.isLoggedIn = authenticated
    gamejolt.username = gamejolt.status.username or gamejoltuser.userid or ""
    gamejolt.userToken = gamejoltuser.user_token or ""
end

local function normalizeResponse(response)
    if type(response) ~= "table" then
        return {success = "false", message = tostring(response or "unknown")}
    end
    if response.success == nil and response.response and type(response.response) == "table" then
        local inner = response.response
        response.success = inner.success
        response.message = inner.message or response.message
        response.data = inner.data or response.data
    end
    return response
end

local function serializeDataValue(value)
    if value == nil then
        return ""
    end
    if type(value) == "table" then
        local okEncode, raw = pcall(function()
            return JSON:encode(value)
        end)
        if okEncode and type(raw) == "string" then
            return raw
        end
    end
    return tostring(value)
end

local function connection(force)
    if not force and gamejoltuser.autologin ~= true then
        updateStatus(false, "auto-login disabled")
        gamejolt.status.username = ""
        gamejolt.status.userId = ""
        gamejolt.status.avatarUrl = ""
        return false
    end

    if not (gamejoltuser.userid and gamejoltuser.user_token) or gamejoltuser.userid == "" then
        updateStatus(false, "ユーザーネームとトークンを入力してください")
        return false
    end

    gamejoltuserdata.userid = gamejoltuser.userid
    gamejoltuserdata.user_token = gamejoltuser.user_token

    -- 必ず2引数で初期化
    gamejoltapi:init(1053992, "d9b3bdca24c8156fe10c485bdc827a25")

    -- 認証
    local auth_success = gamejoltapi:users_auth(gamejoltuserdata.userid, gamejoltuserdata.user_token)

    if auth_success == "true" then
        log.info("GameJolt authentication successful.: " .. gamejoltuserdata.userid)
        updateStatus(true, "認証成功")

        -- 認証成功後にセッション開始
        local session = gamejoltapi:sessions_open()
        if session and session.success == "true" then
            log.info("GameJolt connection successful")
            updateStatus(true, "認証・接続成功")
        else
            updateStatus(true, "認証成功 (セッション開始失敗)")
        end

        -- ユーザー情報読み取り (userID 取得 -> users_fetch_uid で再取得)
        local okUn, userdata_uname = pcall(function() return gamejoltapi:users_fetch_uname(gamejoltuserdata.userid) end)
        if okUn and userdata_uname and userdata_uname.users and userdata_uname.users[1] then
            local fetched = userdata_uname.users[1]
            local fetchedId = fetched.id
            gamejolt.status.userId = fetchedId or ""

            local okUid, userdata_uid = pcall(function() return gamejoltapi:users_fetch_uid(fetchedId) end)
            if okUid and userdata_uid and userdata_uid.users and userdata_uid.users[1] then
                local user = userdata_uid.users[1]
                gamejolt.status.username = user.username or fetched.username or gamejoltuserdata.userid
                gamejolt.status.avatarUrl = user.avatar_url or fetched.avatar_url or ""
            else
                gamejolt.status.username = fetched.username or gamejoltuserdata.userid
                gamejolt.status.avatarUrl = fetched.avatar_url or ""
            end
        else
            gamejolt.status.username = gamejoltuserdata.userid
            gamejolt.status.userId = ""
            gamejolt.status.avatarUrl = ""
        end

    else
        log.warn("GameJolt authentication failed.")
        updateStatus(false, "認証失敗")
        gamejolt.status.username = ""
        gamejolt.status.userId = ""
        gamejolt.status.avatarUrl = ""
    end

    return gamejolt.status.authenticated
end

function gamejolt.init(self, id, key, args)
    if type(self) ~= "table" or self ~= gamejolt then
        args = key
        key = id
        id = self
        self = gamejolt
    end

    local gameId = id or 1053992
    local privateKey = key or args or "d9b3bdca24c8156fe10c485bdc827a25"
    gamejoltapi:init(gameId, privateKey)
    gamejolt.status.message = "initialized"
    return true
end

function gamejolt.authUser(username, token, callback)
    if type(username) ~= "string" or username == "" then
        if type(callback) == "function" then
            callback(false, "invalid username")
        end
        return false
    end

    gamejoltuser.userid = username or ""
    gamejoltuser.user_token = token or ""
    local ok, response = connection(true)
    if type(callback) == "function" then
        callback(ok, response)
    end
    return ok, response
end

function gamejolt.openSession()
    return connection(true)
end

function gamejolt.update(dt)
    if gamejolt.status and gamejolt.status.authenticated then
        pcall(function()
            gamejoltapi:sessions_ping("active")
        end)
    end
end

function gamejolt.pingSession(active)
    if not gamejolt.status.authenticated then
        return false
    end

    local ok, response = pcall(function()
        return gamejoltapi:sessions_ping(active and "active" or "idle")
    end)
    response = normalizeResponse(response)
    return ok and response and response.success == "true", response
end

function gamejolt.closeSession()
    if not gamejolt.status.authenticated then
        return false
    end

    local ok, response = pcall(function()
        return gamejoltapi:sessions_close()
    end)
    response = normalizeResponse(response)
    return ok and response and response.success == "true", response
end

function gamejolt.fetchData(key, isGlobal)
    local ok, response = pcall(function()
        if isGlobal then
            return gamejoltapi:data_store_global_fetch(key)
        end
        return gamejoltapi:data_store_local_fetch(key)
    end)
    response = normalizeResponse(response)
    return ok and response or nil, response
end

function gamejolt.loadMemoryData()
    if not gamejolt.status.authenticated then
        return false, "not authenticated"
    end

    local okScore, responseScore = pcall(function()
        return gamejolt.fetchData("result_score")
    end)
    if okScore and responseScore and responseScore.data ~= nil then
        gamejolt.memory.resultScore = responseScore.data
        gamejolt.memory.lastLoadedAt = os.time()
    end

    local okRating, responseRating = pcall(function()
        return gamejolt.fetchData("result_rating")
    end)
    if okRating and responseRating and responseRating.data ~= nil then
        gamejolt.memory.resultRating = responseRating.data
        gamejolt.memory.lastLoadedAt = os.time()
    end

    local okSummary, responseSummary = pcall(function()
        return gamejolt.fetchData("result_summary")
    end)
    if okSummary and responseSummary and responseSummary.data ~= nil then
        gamejolt.memory.resultSummary = responseSummary.data
        gamejolt.memory.lastLoadedAt = os.time()
    end

    return true, gamejolt.memory
end

function gamejolt.setData(key, data, isGlobal)
    local payload = serializeDataValue(data)
    local ok, response = pcall(function()
        if isGlobal then
            return gamejoltapi:data_store_global_set(key, payload)
        end
        return gamejoltapi:data_store_local_set(key, payload)
    end)
    response = normalizeResponse(response)
    return ok and response and response.success == "true", response
end

function gamejolt.setBigData(key, data, isGlobal)
    return gamejolt.setData(key, data, isGlobal)
end

function gamejolt.saveBestSongScore(songKey, score, metadata)
    if not gamejolt.status.authenticated then
        return false, "not authenticated"
    end

    local normalizedKey = tostring(songKey or "")
    local normalizedScore = tonumber(score) or 0

    if normalizedKey == "" then
        return false, "song key is empty"
    end

    local response, fetchResponse = gamejolt.fetchData("best_song_scores")
    local scores = {}

    if type(response) == "table"
        and response.success == "true"
        and response.data ~= nil
    then
        local stored = response.data

        if type(stored) == "string" then
            local decodeOK, decoded = pcall(function()
                return JSON:decode(stored)
            end)

            if decodeOK then
                stored = decoded
            end
        end

        if type(stored) == "table" then
            scores = stored
        end
    elseif fetchResponse
        and fetchResponse.message
    then
        log.warn(
            "GameJolt best song scores load failed: "
            .. tostring(fetchResponse.message)
        )
    end

    local previous = scores[normalizedKey]
    local previousScore = 0

    if type(previous) == "table" then
        previousScore = tonumber(previous.score) or 0
    else
        previousScore = tonumber(previous) or 0
    end

    if normalizedScore <= previousScore then
        log.info(
            "GameJolt best song score unchanged: "
            .. normalizedKey
            .. " best="
            .. tostring(previousScore)
        )
        return true, {
            success = "true",
            unchanged = true,
            score = previousScore
        }
    end

    local entry = {
        score = normalizedScore
    }

    if type(metadata) == "table" then
        entry.song = metadata.song
        entry.artist = metadata.artist
        entry.level = metadata.level
        entry.accuracy = metadata.accuracy
    end

    scores[normalizedKey] = entry

    local saved, saveResponse = gamejolt.setData(
        "best_song_scores",
        scores
    )

    if not saved then
        log.warn(
            "GameJolt best song score save failed: "
            .. tostring(saveResponse and saveResponse.message or saveResponse or "unknown")
        )
        return false, saveResponse
    end

    log.info(
        "GameJolt best song score saved: "
        .. normalizedKey
        .. " score="
        .. tostring(normalizedScore)
    )

    return true, saveResponse
end

function gamejolt.updateData(key, value, operation, isGlobal)
    local ok, response = pcall(function()
        if isGlobal then
            return gamejoltapi:data_store_global_update(key, operation, value)
        end
        return gamejoltapi:data_store_local_update(key, operation, value)
    end)
    response = normalizeResponse(response)
    return ok and response and response.success == "true", response
end

function gamejolt.removeData(key, isGlobal)
    local ok, response = pcall(function()
        if isGlobal then
            return gamejoltapi:data_store_global_remove(key)
        end
        return gamejoltapi:data_store_local_remove(key)
    end)
    response = normalizeResponse(response)
    return ok and response and response.success == "true", response
end

function gamejolt.fetchStorageKeys(isGlobal)
    local ok, response = pcall(function()
        if isGlobal then
            return gamejoltapi:data_store_global_getKeys()
        end
        return gamejoltapi:data_store_local_getKeys()
    end)
    response = normalizeResponse(response)
    return ok and response or nil, response
end

function gamejolt.giveTrophy(id, callback)
    local ok, response = pcall(function()
        return gamejoltapi:trophies_addAcheived(id)
    end)
    response = normalizeResponse(response)
    local success = ok and response and response.success == "true"
    if type(callback) == "function" then
        callback(success, response)
    end
    return success, response
end

function gamejolt.addTrophy(id, callback)
    return gamejolt.giveTrophy(id, callback)
end

function gamejolt.fetchTrophy(id)
    local ok, response = pcall(function()
        return gamejoltapi:trophies_fetch(nil, id)
    end)
    response = normalizeResponse(response)
    return ok and response or nil, response
end

function gamejolt.fetchTrophiesByStatus(achieved)
    local ok, response = pcall(function()
        return gamejoltapi:trophies_fetch(achieved)
    end)
    response = normalizeResponse(response)
    return ok and response or nil, response
end

function gamejolt.fetchAllTrophies()
    local ok, response = pcall(function()
        return gamejoltapi:trophies_fetch()
    end)
    response = normalizeResponse(response)
    return ok and response or nil, response
end

function gamejolt.addScore(scoreValue, desc, tableId, guestName, extraData, callback)
    local sortValue = desc or tostring(scoreValue or 0)
    local ok, response = gamejolt.submitScore(scoreValue, sortValue, extraData or guestName, tableId)
    if type(callback) == "function" then
        callback(ok, response)
    end
    return ok, response
end

function gamejolt.fetchScores(limit, tableId)
    local ok, response = pcall(function()
        return gamejoltapi:scores_local_fetch(limit, tableId)
    end)
    response = normalizeResponse(response)
    return ok and response or nil, response
end

function gamejolt.fetchTables()
    local ok, response = pcall(function()
        return gamejoltapi:scores_tables()
    end)
    response = normalizeResponse(response)
    return ok and response or nil, response
end

function gamejolt.getCredentials(dir)
    return {
        username = gamejoltuser.userid or "",
        userToken = gamejoltuser.user_token or "",
        gameId = gamejoltapi.GAME_ID,
        gameKey = gamejoltapi.PRIVATE_KEY,
        dir = tostring(dir or "")
    }
end

function gamejolt.submitScore(scoreValue, sortValue, extraData, tableId)
    if not gamejolt.status.authenticated then
        return false, "not authenticated"
    end

    local score = tostring(scoreValue or 0)
    local sort = tostring(sortValue or scoreValue or 0)
    local ok, response = pcall(function()
        return gamejolt:scores_add(score, sort, nil, extraData, tableId)
    end)
    response = normalizeResponse(response)

    if not ok or not response or response.success ~= "true" then
        log.warn("GameJolt score submit failed: " .. tostring(response and response.message or response or "unknown"))
        return false, response
    end

    log.info("GameJolt score submitted: " .. score)
    return true, response
end

local function saveLocalJson(filename, data)
    if not love or not love.filesystem or not love.filesystem.write then
        return false, "love.filesystem unavailable"
    end

    local okEncode, raw = pcall(function()
        return JSON:encode(data or {})
    end)
    if not okEncode or type(raw) ~= "string" then
        return false, "json encode failed"
    end

    local okWrite, wrote = pcall(love.filesystem.write, filename, raw)
    if okWrite == true and wrote ~= nil then
        return true, "local saved"
    end

    return false, "local write failed"
end

function gamejolt.saveSettings(settingsTable, key)
    if not gamejolt.status.authenticated then
        return false, "not authenticated"
    end

    local dataKey = tostring(key or "settings")
    local dataValue = JSON:encode(settingsTable or {})

    local ok, response = pcall(function()
        return gamejolt:data_store_local_set(dataKey, dataValue)
    end)
    response = normalizeResponse(response)

    if not ok or not response or response.success ~= "true" then
        log.warn("GameJolt settings save failed: " .. tostring(response and response.message or response or "unknown"))
        return false, response
    end

    log.info("GameJolt settings saved: " .. dataKey)
    return true, response
end

function gamejolt.loadSettings(key)
    if not gamejolt.status.authenticated then
        return false, "not authenticated"
    end

    local dataKey = tostring(key or "settings")
    local response, fetchResponse = gamejolt.fetchData(dataKey)

    if type(response) ~= "table" then
        return false,
            fetchResponse or "settings response is invalid"
    end

    if response.success ~= "true" then
        log.warn(
            "GameJolt settings load failed: "
            .. tostring(response.message or "unknown")
        )
        return false, response
    end

    local value = response.data

    if type(value) == "string" then
        local okDecode, decoded = pcall(function()
            return JSON:decode(value)
        end)

        if not okDecode then
            return false, "settings JSON decode failed"
        end

        value = decoded
    end

    if type(value) ~= "table" then
        return false, "settings data is not an object"
    end

    log.info("GameJolt settings loaded: " .. dataKey)
    return true, value
end

function gamejolt.savePlayerStats(statsTable, key, localFilename)
    local payload = statsTable or {}
    local filename = tostring(localFilename or "player_stats.json")

    if gamejolt.status.authenticated then
        local dataKey = tostring(key or "player_stats")
        local dataValue = JSON:encode(payload)

        local ok, response = pcall(function()
            return gamejolt:data_store_local_set(dataKey, dataValue)
        end)
        response = normalizeResponse(response)

        if not ok or not response or response.success ~= "true" then
            log.warn("GameJolt player stats save failed: " .. tostring(response and response.message or response or "unknown"))
            return false, response
        end

        log.info("GameJolt player stats saved: " .. dataKey)
        return true, response
    end

    local ok, err = saveLocalJson(filename, payload)
    if ok then
        log.info("Local player stats saved: " .. filename)
        return true, { success = "local", message = filename }
    end

    log.warn("Local player stats save failed: " .. tostring(err))
    return false, err
end

function gamejolt.login(username, token)
    gamejoltuser.userid = username or ""
    gamejoltuser.user_token = token or ""

    return connection(true)
end


function gamejolt.load(useravaterurl,userid)
    local ok, res = connection(false)
    if ok then
        pcall(function()
            gamejolt.loadMemoryData()
        end)
    end
    return ok, res
end


function session()
    -- 既にセッション確立済みなら何もしない
    if gamejolt.status.authenticated then
        return
    end
end


function gamejolt.quit()
    -- セッションが開いていたら閉じる
    if gamejolt and gamejolt.sessions_close then
        pcall(function() gamejolt:sessions_close() end)
    end
end


return gamejolt
