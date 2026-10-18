---@diagnostic disable: undefined-global, undefined-field

local log = require "log"
local i18n = require "i18n"
local json_ok, JSON = pcall(require, "JSON")
local ok_gamejolt, gamejolt = pcall(require, "gamejolt")
local ok_gamejoltuser, gamejoltuser = pcall(require, "gamejoltuser")
local ok_openingloader, openingloader = pcall(require, "openingloader")
local ok_musicselect, musicselect = pcall(require, "musicselect")
local ok_network, network = pcall(require, "network")

console = {
    active = false,
    input = "",
    lines = {},
    maxLines = 28,
    scrollOffset = 0,
    flags = {
        debug_titles = true,
        debug_omitnotes = true,
        debug_slowlad_typing = true,
        debug_exam = true,
        debug_offline = true,
        debug_cansendmayself = true,
        debug_nottification = true,
        debug_story_reload = true,
        debug_removeresult = true,
        debug_boxtage = true,
        debug_story = true,
        debug_reward = true,
        debug_printerror = true,
        debug_createexam = true,
        debug_hidefuture = true,
        debug_legacysongs = true,
        debug_immediate_destroye = true,
        debug_consolescreen = true,
        editor_reloadonreset = true,
        editor_resetscene = true,
        editor_enable = true,
        lang_dubpagish = true,
        lang_export = true,
        lang_test = true,
        sfl_list_set = true,
        skin_show = true
    },
    playerData = {},
    playerDataBackup = {},
    suggestionIndex = 1,
    errors = {},
    maxErrors = 100,
    startedAt = os.clock()
}

local consoleFontCache = {}

local function getConsoleFont()
    local lang = "jp"

    if i18n and i18n.getLanguage then
        pcall(function()
            lang = i18n.getLanguage()
        end)
    end

    local key = tostring(lang) .. ":20"

    if consoleFontCache[key] then
        return consoleFontCache[key]
    end

    local font

    if love and love.graphics and love.graphics.newFont then
        if lang == "jp" then
            local fontPath = "lib/data/fonts/NotoSansJP-Regular.ttf"
            local ok, result = pcall(
                love.graphics.newFont,
                fontPath,
                20
            )

            if ok and result then
                font = result
            end
        end

        if not font then
            font = love.graphics.newFont(20)
        end
    end

    consoleFontCache[key] = font

    return font
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$") or ""
end

local function formatValue(value)
    if value == nil then
        return "nil"
    end

    if type(value) == "boolean" then
        return tostring(value)
    end

    if type(value) == "number" then
        return tostring(value)
    end

    if type(value) == "string" then
        if value == "" then
            return "\"\""
        end

        return value
    end

    if type(value) == "table" then
        local result = "{"
        local count = 0

        for k, v in pairs(value) do
            count = count + 1

            if count > 5 then
                result = result .. ", ..."
                break
            end

            result = result .. tostring(k) .. ":" .. tostring(v) .. ", "
        end

        if result:sub(-2) == ", " then
            result = result:sub(1, -3)
        end

        return result .. "}"
    end

    return tostring(value)
end

local function formatString(value)
    if value == nil then
        return "nil"
    end

    if type(value) ~= "string" then
        return tostring(value)
    end

    if value == "" then
        return "\"\""
    end

    return value
end

local function ensureFlag(name)
    if console.flags[name] == nil then
        console.flags[name] = false
    end

    return console.flags[name]
end

local function toggleFlag(name)
    console.flags[name] = not ensureFlag(name)

    console.addLine(
        name .. " = " .. tostring(console.flags[name])
    )

    if console.flags[name] and console.debugCommands[name] then
        console.debugCommands[name]()
    end
end

local function setFlag(name, value)
    console.flags[name] = value

    console.addLine(
        name .. " = " .. tostring(console.flags[name])
    )

    if value and console.debugCommands[name] then
        console.debugCommands[name]()
    end
end

local function gotoScene(id)
    if type(id) ~= "number" then
        return false
    end

    if type(changeProgram) == "function" then
        changeProgram(id)
        console.addLine("gotoScene(" .. id .. ")")
        return true
    end

    console.addLine(
        "gotoScene: changeProgramが利用できません"
    )

    return false
end

local function triggerDebugEvent(name)
    if type(console.debugCommands[name]) == "function" then
        console.debugCommands[name]()
    end
end

local function startStoryDebug()
    console.addLine("startStoryDebug()")
    gotoScene(6)
end

local function startExamDebug()
    console.addLine("startExamDebug()")

    if type(createExam) == "function" then
        createExam()
    else
        console.addLine(
            "startExamDebug: createExamが利用できません"
        )
    end
end

local function showRewardDebug()
    console.addLine("showRewardDebug()")

    if type(_G) == "table" then
        _G.rewardOpen = true
    end
end

local function reloadStoryDebug()
    console.addLine("reloadStoryDebug()")

    if type(reloadCurrentChart) == "function" then
        reloadCurrentChart()
    else
        console.addLine(
            "reloadStoryDebug: reloadCurrentChartが利用できません"
        )
    end
end

local function createExamDebug()
    console.addLine("createExamDebug()")
    startExamDebug()
end

local function showGameJoltUserData()
    if not ok_gamejoltuser or not gamejoltuser then
        console.addLine(
            "gamejoltuserモジュールが利用できません"
        )
        return
    end

    console.addLine(
        "gamejoltuser.userid=" ..
        tostring(gamejoltuser.userid)
    )

    console.addLine(
        "gamejoltuser.user_token=" ..
        (gamejoltuser.user_token ~= "" and "[redacted]" or "(empty)")
    )

    console.addLine(
        "gamejoltuser.autologin=" ..
        tostring(gamejoltuser.autologin)
    )
end

local function urlDecode(str)
    if type(str) ~= "string" then
        return str
    end

    str = str:gsub("+", " ")

    str = str:gsub(
        "%%(%x%x)",
        function(hex)
            return string.char(
                tonumber(hex, 16)
            )
        end
    )

    return str
end

local function parseGameJoltValue(value)
    if type(value) ~= "string" then
        return value
    end

    local decoded = urlDecode(value)

    if JSON then
        local ok, parsed = pcall(function()
            return JSON:decode(decoded)
        end)

        if ok and parsed ~= nil then
            return parsed
        end
    end

    return decoded
end

local function printGameJoltValue(
    value,
    name,
    prefix,
    isLast,
    isRoot
)
    prefix = prefix or ""

    if type(value) == "table" then
        local keys = {}

        for k in pairs(value) do
            table.insert(keys, k)
        end

        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)

        if #keys == 0 then
            if isRoot then
                console.addLine(
                    tostring(name) .. " = {}"
                )
            else
                local connector

                if isLast then
                    connector = "└─ "
                else
                    connector = "├─ "
                end

                console.addLine(
                    prefix ..
                    connector ..
                    tostring(name) ..
                    " = {}"
                )
            end

            return
        end

        if isRoot then
            for i, key in ipairs(keys) do
                local last = i == #keys

                printGameJoltValue(
                    value[key],
                    tostring(key),
                    "",
                    last,
                    false
                )
            end

            return
        end

        local connector

        if isLast then
            connector = "└─ "
        else
            connector = "├─ "
        end

        console.addLine(
            prefix ..
            connector ..
            tostring(name)
        )

        local childPrefix

        if isLast then
            childPrefix = prefix .. "   "
        else
            childPrefix = prefix .. "│  "
        end

        for i, key in ipairs(keys) do
            local last = i == #keys

            printGameJoltValue(
                value[key],
                tostring(key),
                childPrefix,
                last,
                false
            )
        end

        return
    end

    local connector

    if isLast then
        connector = "└─ "
    else
        connector = "├─ "
    end

    console.addLine(
        prefix ..
        connector ..
        tostring(name) ..
        " = " ..
        tostring(value)
    )
end

local function showGameJoltDataBank(args)
    if not ok_gamejolt or not gamejolt then
        console.addLine(
            "gamejoltモジュールが利用できません"
        )
        return
    end

    if not gamejolt.fetchStorageKeys then
        console.addLine(
            "fetchStorageKeysが利用できません"
        )
        return
    end

    local mode = trim(args or ""):lower()

    local isGlobal =
        mode == "global" or
        mode == "g"

    local storageName

    if isGlobal then
        storageName = "Global Data Store"
    else
        storageName = "Local Data Store"
    end

    console.addLine(
        "[" .. storageName .. "]"
    )

    console.addLine(
        "キー一覧を取得しています..."
    )

    local ok, response = pcall(function()
        return gamejolt.fetchStorageKeys(
            isGlobal
        )
    end)

    if not ok then
        console.addLine(
            "Data Storeキー取得エラー: " ..
            tostring(response)
        )
        return
    end

    if type(response) ~= "table" then
        console.addLine(
            "Data Storeのレスポンスが不正です"
        )
        return
    end

    if response.success ~= "true" then
        console.addLine(
            "Data Store取得失敗: " ..
            tostring(
                response.message or
                "unknown error"
            )
        )
        return
    end

    local keys

    if type(response.data) == "table" then
        if type(response.data.keys) == "table" then
            keys = response.data.keys
        else
            keys = response.data
        end
    end

    if not keys and type(response.keys) == "table" then
        keys = response.keys
    end

    if type(keys) ~= "table" then
        console.addLine(
            "Data Storeにキーがありません"
        )
        return
    end

    if #keys == 0 then
        console.addLine(
            "Data Storeは空です"
        )
        return
    end

    console.addLine(
        "合計 " .. tostring(#keys) .. " 件"
    )

    console.addLine(
        "--------------------------------"
    )

    for i, keyData in ipairs(keys) do
        local key

        if type(keyData) == "table" then
            key =
                keyData.key or
                keyData.name or
                keyData.id
        else
            key = keyData
        end

        if key ~= nil then
            key = tostring(key)

            console.addLine(
                string.format(
                    "[%d/%d] %s",
                    i,
                    #keys,
                    key
                )
            )

            local fetchOK, fetchResponse =
                pcall(function()
                    return gamejolt.fetchData(
                        key,
                        isGlobal
                    )
                end)

            if fetchOK and
                type(fetchResponse) == "table" then

                if fetchResponse.success == "true" then
                    local value =
                        parseGameJoltValue(
                            fetchResponse.data
                        )

                    if type(value) == "table" then
                        printGameJoltValue(
                            value,
                            "",
                            "",
                            true,
                            true
                        )
                    else
                        console.addLine(
                            "  value = " ..
                            tostring(value)
                        )
                    end
                else
                    console.addLine(
                        "  ERROR: " ..
                        tostring(
                            fetchResponse.message or
                            "取得失敗"
                        )
                    )
                end
            else
                console.addLine(
                    "  ERROR: Data取得失敗"
                )
            end

            console.addLine("")
        else
            console.addLine(
                "[" ..
                tostring(i) ..
                "] 不明なキー形式"
            )
        end
    end

    console.addLine(
        "--------------------------------"
    )

    console.addLine(
        "Data Store取得完了: " ..
        tostring(#keys) ..
        " 件"
    )
end

local function executeAudioCommand(cmd)
    if cmd == "audio_musiclist" then
        if type(getMusicList) == "function" then
            local ok, result =
                pcall(getMusicList)

            if ok then
                console.addLine(
                    "音声リストを読み込みました"
                )

                if type(result) == "table" then
                    for i = 1, math.min(10, #result) do
                        console.addLine(
                            "- " ..
                            tostring(result[i])
                        )
                    end
                end
            else
                console.addLine(
                    "audio_musiclistコマンドが失敗しました"
                )
            end
        else
            console.addLine(
                "audio_musiclist: 利用できません"
            )
        end

        return
    end

    if cmd == "audio_sfxlist" then
        console.addLine(
            "audio_sfxlist: 利用できません"
        )
    end
end

local function executePlayerCommand(cmd, args)
    local parts = {}

    for part in (args or ""):gmatch("%S+") do
        table.insert(parts, part)
    end

    if cmd == "player_data_set" then
        if #parts < 2 then
            console.addLine(
                "使用法: player_data_set キー 値"
            )
            return
        end

        console.playerData[parts[1]] = parts[2]

        console.addLine(
            "プレイヤーデータ設定: " ..
            parts[1] ..
            "=" ..
            tostring(parts[2])
        )

        return
    end

    if cmd == "player_data_get" then
        if #parts < 1 then
            console.addLine(
                "使用法: player_data_get キー"
            )
            return
        end

        console.addLine(
            parts[1] ..
            " = " ..
            formatValue(
                console.playerData[parts[1]]
            )
        )

        return
    end

    if cmd == "player_data_show" then
        console.addLine(
            "playerData = " ..
            formatValue(console.playerData)
        )
        return
    end

    if cmd == "player_data_backup" or
        cmd == "player_data_bukup" then

        console.playerDataBackup = {}

        for k, v in pairs(console.playerData) do
            console.playerDataBackup[k] = v
        end

        console.addLine(
            "プレイヤーデータのバックアップを作成しました"
        )

        return
    end

    if cmd == "player_delete" then
        if #parts < 1 then
            console.addLine(
                "使用法: player_delete キー"
            )
            return
        end

        console.playerData[parts[1]] = nil

        console.addLine(
            "プレイヤーデータを削除しました: " ..
            parts[1]
        )

        return
    end

    if cmd == "player_verify" or
        cmd == "player_verfy" then

        local count = 0

        for _ in pairs(console.playerData) do
            count = count + 1
        end

        console.addLine(
            "プレイヤーデータエントリ=" ..
            count ..
            ", バックアップ=" ..
            tostring(
                next(console.playerDataBackup) ~= nil
            )
        )

        return
    end
end

local function copyConsoleOutput()
    local text = table.concat(
        console.lines,
        "\n"
    )

    if love.system and
        love.system.setClipboardText then

        love.system.setClipboardText(text)

        console.addLine(
            "console output copied to clipboard"
        )
    else
        console.addLine(
            "クリップボードが利用できません"
        )
    end
end

local function getLoadedMusicEntries()
    local collections = nil
    local ms = musicselect or _G.musicselect

    if ms and ms.getCollections then
        local ok, result =
            pcall(ms.getCollections)

        if ok and result then
            collections = result
        end
    end

    if not collections and
        _G.main and
        _G.main.startup and
        _G.main.startup.collections then

        collections =
            _G.main.startup.collections
    end

    local sourceList = {}

    if type(collections) == "table" then
        if type(collections.audio) == "table" then
            sourceList = collections.audio
        elseif type(collections.songs) == "table" then
            sourceList = collections.songs
        elseif type(collections.music) == "table" then
            sourceList = collections.music
        end
    end

    local entries = {}

    for i, entry in ipairs(sourceList) do
        local info = {
            index = i,
            title = "Unknown",
            artist = "",
            level = "",
            source = ""
        }

        if type(entry) == "table" then
            info.title =
                entry.title or
                entry.name or
                entry.path or
                entry.archive or
                ("Entry " .. i)

            info.artist =
                entry.artist or
                entry.author or
                entry.creator or
                entry.artistName or
                ""

            info.level =
                entry.level or
                entry.difficulty or
                entry.diff or
                entry.musicLevel or
                ""

            info.source =
                entry.source or
                entry.file or
                entry.path or
                entry.archive or
                ""
        elseif type(entry) == "string" then
            info.title = entry
        end

        entries[#entries + 1] = info
    end

    return entries
end

local function showLoadedMusicList()
    local items = getLoadedMusicEntries()

    if #items == 0 then
        console.addLine(
            "読み込まれた楽曲一覧はありません"
        )
        return
    end

    console.addLine(
        "[Loaded music list] total=" ..
        #items
    )

    for _, item in ipairs(items) do
        local meta = {}

        if item.artist and item.artist ~= "" then
            table.insert(
                meta,
                tostring(item.artist)
            )
        end

        if item.level and item.level ~= "" then
            table.insert(
                meta,
                "Lv:" .. tostring(item.level)
            )
        end

        local suffix = ""

        if #meta > 0 then
            suffix =
                " / " ..
                table.concat(meta, " / ")
        end

        console.addLine(
            string.format(
                "[%02d] %s%s",
                item.index,
                tostring(item.title),
                suffix
            )
        )
    end
end

local function writeLoadedMusicListToFile()
    local items = getLoadedMusicEntries()

    if #items == 0 then
        console.addLine(
            "読み込まれた楽曲一覧はありません"
        )
        return
    end

    local payload = {
        total = #items,
        items = items
    }

    local data

    if JSON and JSON.encode_pretty then
        local ok, result =
            pcall(
                JSON.encode_pretty,
                JSON,
                payload
            )

        if ok and result then
            data = result
        end
    end

    if not data then
        data =
            "{\n" ..
            "  \"total\": " ..
            #items ..
            ",\n" ..
            "  \"items\": [\n"

        for i, item in ipairs(items) do
            local title =
                tostring(item.title)
                :gsub("\\", "\\\\")
                :gsub("\n", "\\n")
                :gsub("\"", "\\\"")

            local artist =
                tostring(item.artist)
                :gsub("\\", "\\\\")
                :gsub("\n", "\\n")
                :gsub("\"", "\\\"")

            local level =
                tostring(item.level)
                :gsub("\\", "\\\\")
                :gsub("\n", "\\n")
                :gsub("\"", "\\\"")

            local line =
                "    {\n" ..
                "      \"index\": " ..
                item.index ..
                ",\n" ..
                "      \"title\": \"" ..
                title ..
                "\",\n" ..
                "      \"artist\": \"" ..
                artist ..
                "\",\n" ..
                "      \"level\": \"" ..
                level ..
                "\"\n" ..
                "    }"

            if i < #items then
                line = line .. ","
            end

            data =
                data ..
                line ..
                "\n"
        end

        data =
            data ..
            "  ]\n}"
    end

    if love and
        love.filesystem and
        love.filesystem.write then

        local ok, err =
            pcall(
                love.filesystem.write,
                "loaded_music_list.json",
                data
            )

        if ok then
            console.addLine(
                "loaded_music_list.json に楽曲一覧をJSON出力しました"
            )
            return
        end

        console.addLine(
            "ファイル出力に失敗しました: " ..
            tostring(err)
        )

        return
    end

    console.addLine(
        "love.filesystem.write が利用できません"
    )
end

local function showWatchwuserInfo(args)
    local musicselect_ok, musicselect_module =
        pcall(require, "musicselect")

    if not musicselect_ok or
        not musicselect_module then

        console.addLine(
            "watchuser: musicselectモジュールが利用できません"
        )

        return
    end

    if not musicselect_module.getWatchuserSongs then
        console.addLine(
            "watchuser: getWatchuserSongsメソッドが利用できません"
        )
        return
    end

    local searchName =
        trim(args or ""):lower()

    local ok, found_songs =
        pcall(
            musicselect_module.getWatchuserSongs,
            searchName
        )

    if not ok or
        type(found_songs) ~= "table" then

        console.addLine(
            "watchuser: データ取得に失敗しました"
        )

        return
    end

    if #found_songs == 0 then
        if searchName == "" then
            console.addLine(
                "watchuser: watchuser制限がある楽曲が見つかりません"
            )

            console.addLine(
                "  ヒント: 初回検索の場合は、まず音楽選択画面に移動してください"
            )
        else
            console.addLine(
                "watchuser: '" ..
                searchName ..
                "'でマッチする楽曲が見つかりません"
            )
        end

        return
    end

    if searchName == "" then
        console.addLine(
            "watchuser: 制限がある楽曲 " ..
            #found_songs ..
            "曲"
        )
    else
        console.addLine(
            "watchuser '" ..
            searchName ..
            "': " ..
            #found_songs ..
            "曲"
        )
    end

    for _, song in ipairs(found_songs) do
        local title =
            song.title or "Unknown"

        local users = ""

        if type(song.watchusers) == "table" then
            users =
                table.concat(
                    song.watchusers,
                    ", "
                )
        else
            users =
                tostring(
                    song.watchusers or ""
                )
        end

        console.addLine(
            "  [" ..
            tostring(song.index or "?") ..
            "] " ..
            title ..
            " (ウォッチャー: " ..
            users ..
            ")"
        )
    end
end

local function checkStartupCache()
    console.addLine(
        "[Startup Cache Check]"
    )

    local ok = true

    if _G.main and
        _G.main.startup and
        _G.main.startup.collections then

        console.addLine(
            "main.startup.collections: OK"
        )
    else
        console.addLine(
            "main.startup.collections: NOT FOUND"
        )
        ok = false
    end

    local ms =
        musicselect or
        _G.musicselect

    if ms and ms.getCollections then
        local success =
            pcall(ms.getCollections)

        if success then
            console.addLine(
                "musicselect.getCollections: OK"
            )
        else
            console.addLine(
                "musicselect.getCollections: ERROR"
            )
            ok = false
        end
    else
        console.addLine(
            "musicselect.getCollections: NOT AVAILABLE"
        )
    end

    if ok then
        console.addLine(
            "Startup cache: ALL SYSTEMS OK"
        )
    else
        console.addLine(
            "Startup cache: ISSUE DETECTED"
        )
    end
end

local function checkOpeningloaderStatus()
    console.addLine(
        "[Openingloader Cache Status]"
    )

    local ol =
        openingloader or
        _G.openingloader

    if not ol then
        console.addLine(
            "openingloader: NOT LOADED"
        )
        return
    end

    console.addLine(
        "openingloader: LOADED"
    )

    if ol._collections then
        console.addLine(
            "openingloader._collections: EXISTS"
        )

        local cols =
            ol._collections

        if type(cols) == "table" then
            local audioCount =
                type(cols.audio) == "table" and
                #cols.audio or
                0

            local chartCount =
                type(cols.charts) == "table" and
                #cols.charts or
                0

            console.addLine(
                string.format(
                    "  - audio: %d items",
                    audioCount
                )
            )

            console.addLine(
                string.format(
                    "  - charts: %d items",
                    chartCount
                )
            )

            if audioCount == 0 then
                console.addLine(
                    "  WARNING: No audio entries found"
                )
            end
        end
    else
        console.addLine(
            "openingloader._collections: NOT SET"
        )
    end

    if type(ol.getCollections) == "function" then
        console.addLine(
            "openingloader.getCollections: AVAILABLE"
        )

        local result =
            pcall(ol.getCollections)

        if result then
            console.addLine(
                "  - Function call: OK"
            )
        else
            console.addLine(
                "  - Function call: FAILED"
            )
        end
    else
        console.addLine(
            "openingloader.getCollections: NOT AVAILABLE"
        )
    end
end

local function checkWebhookStatus()
    console.addLine(
        "[Webhook Status Check]"
    )

    if love and love.filesystem then
        local exists =
            love.filesystem.getInfo(
                "last_error.json"
            )

        if exists then
            console.addLine(
                "last_error.json: EXISTS (pending send)"
            )
        else
            console.addLine(
                "last_error.json: NOT FOUND (clean)"
            )
        end
    else
        console.addLine(
            "love.filesystem: NOT AVAILABLE"
        )
    end
end

local function showFPS()
    local fps = 0
    local delta = 0

    if love.timer then
        if love.timer.getFPS then
            fps = love.timer.getFPS()
        end

        if love.timer.getDelta then
            delta = love.timer.getDelta()
        end
    end

    console.addLine(
        string.format(
            "FPS = %d",
            fps
        )
    )

    console.addLine(
        string.format(
            "Frame time = %.3f ms",
            delta * 1000
        )
    )

    if fps < 30 then
        console.addLine(
            "WARNING: FPS is below 30"
        )
    elseif fps < 60 then
        console.addLine(
            "WARNING: FPS is below 60"
        )
    else
        console.addLine(
            "FPS status: GOOD"
        )
    end
end

local function showMemory()
    local luaMemory =
        collectgarbage("count")

    console.addLine(
        string.format(
            "Lua memory = %.2f MB",
            luaMemory / 1024
        )
    )

    if love.graphics and
        love.graphics.getStats then

        local stats =
            love.graphics.getStats()

        if stats.texturememory then
            console.addLine(
                string.format(
                    "Texture memory = %.2f MB",
                    stats.texturememory / 1024 / 1024
                )
            )
        end

        if stats.images then
            console.addLine(
                "Images = " ..
                tostring(stats.images)
            )
        end

        if stats.canvases then
            console.addLine(
                "Canvases = " ..
                tostring(stats.canvases)
            )
        end
    end
end

local function showGraphicsStats()
    if not love.graphics or
        not love.graphics.getStats then

        console.addLine(
            "love.graphics.getStats が利用できません"
        )

        return
    end

    local stats =
        love.graphics.getStats()

    local fields = {
        "drawcalls",
        "drawcallsbatched",
        "textures",
        "images",
        "canvases",
        "fonts",
        "shaders"
    }

    console.addLine(
        "[Graphics Statistics]"
    )

    for _, name in ipairs(fields) do
        if stats[name] ~= nil then
            console.addLine(
                name ..
                " = " ..
                tostring(stats[name])
            )
        end
    end

    if stats.texturememory then
        console.addLine(
            string.format(
                "texturememory = %.2f MB",
                stats.texturememory / 1024 / 1024
            )
        )
    end
end

local function showResolution()
    local width =
        _G.displayx or
        love.graphics.getWidth()

    local height =
        _G.displayy or
        love.graphics.getHeight()

    console.addLine(
        "displayx = " ..
        tostring(width)
    )

    console.addLine(
        "displayy = " ..
        tostring(height)
    )

    console.addLine(
        "resolution = " ..
        tostring(width) ..
        "x" ..
        tostring(height)
    )
end

local function showSystemInfo()
    console.addLine(
        "[System Information]"
    )

    if love.system then
        if love.system.getOS then
            console.addLine(
                "OS = " ..
                tostring(love.system.getOS())
            )
        end

        if love.system.getProcessorCount then
            console.addLine(
                "CPU threads = " ..
                tostring(
                    love.system.getProcessorCount()
                )
            )
        end
    end

    if love.getVersion then
        local major, minor, revision, codename =
            love.getVersion()

        console.addLine(
            string.format(
                "LÖVE = %d.%d.%d",
                major,
                minor,
                revision
            )
        )

        if codename then
            console.addLine(
                "codename = " ..
                tostring(codename)
            )
        end
    end

    console.addLine(
        "Lua = " ..
        tostring(_VERSION)
    )
end

local function showTimerInfo()
    console.addLine(
        "[Timer]"
    )

    if love.timer then
        if love.timer.getTime then
            console.addLine(
                string.format(
                    "love.timer.getTime = %.3f",
                    love.timer.getTime()
                )
            )
        end

        if love.timer.getAverageDelta then
            console.addLine(
                string.format(
                    "average delta = %.3f ms",
                    love.timer.getAverageDelta() * 1000
                )
            )
        end

        if love.timer.getFPS then
            console.addLine(
                "FPS = " ..
                tostring(love.timer.getFPS())
            )
        end
    end

    console.addLine(
        string.format(
            "console uptime = %.2f sec",
            os.clock() - console.startedAt
        )
    )
end

local function showFlags()
    local names = {}

    for name in pairs(console.flags) do
        table.insert(names, name)
    end

    table.sort(names)

    console.addLine(
        "[Debug Flags] total=" ..
        tostring(#names)
    )

    for _, name in ipairs(names) do
        console.addLine(
            string.format(
                "%-32s = %s",
                name,
                tostring(console.flags[name])
            )
        )
    end
end

local function executeFlagCommand(args)
    local parts = {}

    for part in (args or ""):gmatch("%S+") do
        table.insert(parts, part)
    end

    if #parts == 0 then
        console.addLine(
            "使用法: flag 名前 [on|off|toggle]"
        )
        return
    end

    local name = parts[1]
    local action =
        (parts[2] or "toggle"):lower()

    if console.flags[name] == nil then
        console.addLine(
            "存在しないフラグ: " ..
            name
        )
        return
    end

    if action == "on" or
        action == "true" then

        setFlag(name, true)
        return
    end

    if action == "off" or
        action == "false" then

        setFlag(name, false)
        return
    end

    if action == "toggle" then
        toggleFlag(name)
        return
    end

    console.addLine(
        "指定できる値: on / off / toggle"
    )
end

local function runGC()
    local before =
        collectgarbage("count")

    local ok, err =
        pcall(function()
            collectgarbage("collect")
        end)

    local after =
        collectgarbage("count")

    if ok then
        console.addLine(
            string.format(
                "GC completed: %.2f MB -> %.2f MB",
                before / 1024,
                after / 1024
            )
        )

        console.addLine(
            string.format(
                "Freed: %.2f MB",
                (before - after) / 1024
            )
        )
    else
        console.addLine(
            "GC failed: " ..
            tostring(err)
        )
    end
end

local function showVersion()
    if love.getVersion then
        local major, minor, revision =
            love.getVersion()

        console.addLine(
            string.format(
                "LÖVE %d.%d.%d",
                major,
                minor,
                revision
            )
        )
    else
        console.addLine(
            "LÖVE version unavailable"
        )
    end

    console.addLine(
        tostring(_VERSION)
    )
end

local function showModules()
    console.addLine(
        "[Module Status]"
    )

    console.addLine(
        "JSON = " ..
        tostring(json_ok and JSON ~= nil)
    )

    console.addLine(
        "gamejolt = " ..
        tostring(ok_gamejolt and gamejolt ~= nil)
    )

    console.addLine(
        "gamejoltuser = " ..
        tostring(
            ok_gamejoltuser and
            gamejoltuser ~= nil
        )
    )

    console.addLine(
        "openingloader = " ..
        tostring(
            ok_openingloader and
            openingloader ~= nil
        )
    )

    console.addLine(
        "musicselect = " ..
        tostring(
            ok_musicselect and
            musicselect ~= nil
        )
    )
end

local function showErrors()
    local count = 0

    for _ in pairs(console.errors) do
        count = count + 1
    end

    console.addLine(
        "[Errors] total=" ..
        tostring(count)
    )

    if count == 0 then
        console.addLine(
            "エラー履歴はありません"
        )
        return
    end

    local keys = {}

    for key in pairs(console.errors) do
        table.insert(keys, key)
    end

    table.sort(keys, function(a, b)
        return tonumber(a) < tonumber(b)
    end)

    for _, key in ipairs(keys) do
        console.addLine(
            "[" ..
            tostring(key) ..
            "] " ..
            tostring(console.errors[key])
        )
    end
end

local function showCurrentScene()
    console.addLine(
        console.getCurrentProgramSummary()
    )

    console.addLine(
        "programnumber = " ..
        tostring(_G.programnumber)
    )

    if _G.program then
        console.addLine(
            "program = " ..
            tostring(_G.program)
        )
    end
end

local function showNetworkInfo()
    if not ok_network or not network then
        console.addLine("[ERROR] Network module not available")
        return
    end

    console.addLine("=== Network Information ===")

    local localIP = network.getLocalIP()
    if localIP then
        console.addLine("Local IP: " .. localIP)
    else
        console.addLine("Local IP: (failed to get)")
    end

    console.addLine("")
    console.addLine("HTTP Library Status: " .. (network.httpAvailable and "✓ Available" or "✗ Not Available"))
    
    if not network.httpAvailable then
        console.addLine("")
        console.addLine("Note: External IP cannot be fetched without socket.http library")
        console.addLine("See 'network_externalip' command for installation instructions")
        return
    end

    console.addLine("[Fetching External IP (trying multiple endpoints)...]")
    network.getExternalIP(function(ip, err)
        if ip then
            console.addLine("External IP: " .. ip)
        else
            console.addLine("External IP: (failed)")
            if err then
                console.addLine("  Error: " .. err)
            end
            console.addLine("Tips: ネットワーク接続またはファイアウォール設定を確認してください")
        end
    end)
end

local function showLocalIP()
    if not ok_network or not network then
        console.addLine("[ERROR] Network module not available")
        return
    end

    console.addLine("Local Network Status:")
    console.addLine("")
    
    local localIP = network.getLocalIP()
    if localIP then
        console.addLine("✓ Local IP: " .. localIP)
    else
        console.addLine("✗ Local IP: (failed to get)")
    end
    
    console.addLine("HTTP Library: " .. (network.httpAvailable and "✓ Available" or "✗ Not Available"))
end

local function showExternalIP()
    if not ok_network or not network then
        console.addLine("[ERROR] Network module not available")
        return
    end

    if not network.httpAvailable then
        console.addLine("[ERROR] HTTP Library Not Available")
        console.addLine("")
        console.addLine("socket.http (LuaSocket) がインストールされていません")
        console.addLine("")
        console.addLine("解決方法:")
        console.addLine("  1. LuaRocks をインストール: https://luarocks.org/")
        console.addLine("  2. LuaSocket をインストール:")
        console.addLine("     > luarocks install luasocket")
        console.addLine("")
        console.addLine("または")
        console.addLine("")
        console.addLine("  Windows: choco install luarocks")
        console.addLine("  Lua: https://github.com/diegonehab/luasocket")
        return
    end

    console.addLine("[Fetching External IP (trying multiple endpoints)...]")
    console.addLine("Endpoints:")
    console.addLine("  1. api.ipify.org")
    console.addLine("  2. icanhazip.com")
    console.addLine("  3. ifconfig.me")
    console.addLine("  4. ident.me")
    console.addLine("")
    
    network.getExternalIP(function(ip, err)
        if ip then
            console.addLine("✓ Result: " .. ip)
        else
            console.addLine("✗ Result: (failed)")
            if err then
                console.addLine("  Error: " .. err)
            end
            console.addLine("")
            console.addLine("Tips:")
            console.addLine("  - インターネット接続を確認")
            console.addLine("  - ファイアウォールがHTTP通信をブロックしていないか確認")
            console.addLine("  - VPN・プロキシの設定を確認")
        end
    end)
end

console.debugCommands = {}

local commandSpecs = {
    help = {
        desc = "ヘルプを表示",
        handler = function()
            console.showHelp()
        end
    },

    clean = {
        desc = "コンソールログを消去",
        handler = function()
            console.clear()
        end
    },

    debug_printerror = {
        desc = "エラー表示を切り替え",
        handler = function()
            toggleFlag("debug_printerror")
        end
    },

    gamejoltuser_data = {
        desc = "GameJoltユーザーデータを表示",
        handler = function()
            showGameJoltUserData()
        end
    },

    gamejolt_databank = {
        desc = "GameJolt Data Storeの全データを表示",
        handler = function(args)
            showGameJoltDataBank(args)
        end
    },

    watchuser = {
        desc = "ユーザー制限がある楽曲を表示",
        handler = function(args)
            showWatchwuserInfo(args)
        end
    },

    music_list = {
        desc = "読み込まれた楽曲一覧を表示",
        handler = function()
            showLoadedMusicList()
        end
    },

    music_dump = {
        desc = "読み込まれた楽曲一覧をファイル出力",
        handler = function()
            writeLoadedMusicListToFile()
        end
    },

    startup_cache_check = {
        desc = "Startup キャッシュ状態をチェック",
        handler = function()
            checkStartupCache()
        end
    },

    openingloader_status = {
        desc = "Openingloader キャッシュ詳細を表示",
        handler = function()
            checkOpeningloaderStatus()
        end
    },

    webhook_check = {
        desc = "Webhook ステータスをチェック",
        handler = function()
            checkWebhookStatus()
        end
    },

    globals = {
        desc = "グローバル変数を表示",
        handler = function()
            console.showGlobals()
        end
    },

    status = {
        desc = "現在のゲーム状態を表示",
        handler = function()
            console.showStatus()
        end
    },

    program = {
        desc = "現在のプログラムを表示",
        handler = function()
            console.showProgram()
        end
    },

    editor = {
        desc = "エディタ状態を表示",
        handler = function()
            console.showEditor()
        end
    },

    play = {
        desc = "プレイ状態を表示",
        handler = function()
            console.showPlay()
        end
    },

    song = {
        desc = "現在の曲情報を表示",
        handler = function()
            console.showSong()
        end
    },

    fps = {
        desc = "FPSとフレーム時間を表示",
        handler = function()
            showFPS()
        end
    },

    memory = {
        desc = "Lua・グラフィックスのメモリ状況を表示",
        handler = function()
            showMemory()
        end
    },

    graphics_stats = {
        desc = "LÖVEのグラフィックス統計を表示",
        handler = function()
            showGraphicsStats()
        end
    },

    resolution = {
        desc = "現在の画面解像度を表示",
        handler = function()
            showResolution()
        end
    },

    system = {
        desc = "OS・CPU・LÖVE・Lua情報を表示",
        handler = function()
            showSystemInfo()
        end
    },

    timer = {
        desc = "タイマー・平均フレーム時間を表示",
        handler = function()
            showTimerInfo()
        end
    },

    flags = {
        desc = "デバッグフラグ一覧を表示",
        handler = function()
            showFlags()
        end
    },

    flag = {
        desc = "デバッグフラグを変更",
        handler = function(args)
            executeFlagCommand(args)
        end
    },

    gc = {
        desc = "Luaのガベージコレクションを実行",
        handler = function()
            runGC()
        end
    },

    version = {
        desc = "LÖVEとLuaのバージョンを表示",
        handler = function()
            showVersion()
        end
    },

    modules = {
        desc = "主要モジュールの読み込み状態を表示",
        handler = function()
            showModules()
        end
    },

    errors = {
        desc = "保存されているエラー履歴を表示",
        handler = function()
            showErrors()
        end
    },

    scene = {
        desc = "現在のシーン情報を表示",
        handler = function()
            showCurrentScene()
        end
    },

    network_info = {
        desc = "ネットワーク情報を表示（ローカルIP・外部IP）",
        handler = function()
            showNetworkInfo()
        end
    },

    network_localip = {
        desc = "ローカルIPアドレスを表示",
        handler = function()
            showLocalIP()
        end
    },

    network_externalip = {
        desc = "外部IPアドレスを取得・表示",
        handler = function()
            showExternalIP()
        end
    }
}

local availableCommands = {}

for name, spec in pairs(commandSpecs) do
    if spec and type(spec) == "table" then
        table.insert(
            availableCommands,
            {
                name = name,
                desc = spec.desc or ""
            }
        )
    end
end

table.sort(
    availableCommands,
    function(a, b)
        return a.name < b.name
    end
)

local function getMatchingCommands(prefix)
    local trimmed = trim(prefix)

    if trimmed == "" then
        return {}
    end

    local lower = trimmed:lower()
    local results = {}

    for _, cmd in ipairs(availableCommands) do
        if cmd.name:find(
            lower,
            1,
            true
        ) then
            table.insert(
                results,
                cmd
            )
        end
    end

    return results
end

function console.clear()
    console.lines = {}
    console.scrollOffset = 0
end

function console.getProgramName(num)
    local programNames = {
        [0] = "openingloader",
        [1] = "opening",
        [2] = "gamemodeselect",
        [3] = "musicselect",
        [4] = "play",
        [5] = "settings",
        [6] = "story",
        [7] = "result",
        [8] = "editor"
    }

    return programNames[num] or tostring(num)
end

function console.getCurrentProgramSummary()
    local currentNum =
        _G.programnumber or -1

    local currentName =
        console.getProgramName(currentNum)

    return string.format(
        "program=%s(%d)",
        currentName,
        currentNum
    )
end

function console.showHelp()
    console.addLine(
        "利用可能なコマンド:"
    )

    for _, cmd in ipairs(availableCommands) do
        console.addLine(
            "\t" ..
            tostring(cmd.name) ..
            "\t" ..
            tostring(cmd.desc or "")
        )
    end
end

function console.showStatus()
    console.addLine(
        console.getCurrentProgramSummary()
    )

    console.addLine(
        "editorStarted=" ..
        formatValue(_G.editorStarted) ..
        ", editorAutoplay=" ..
        formatValue(_G.editorAutoplay)
    )

    console.addLine(
        "musicload=" ..
        formatValue(_G.musicload) ..
        ", bgmSource=" ..
        tostring(_G.bgmSource ~= nil)
    )

    console.addLine(
        "musictime=" ..
        formatValue(_G.musictime) ..
        ", musictimer=" ..
        formatValue(_G.musictimer)
    )

    console.addLine(
        "finished=" ..
        formatValue(_G.finished) ..
        ", paused=" ..
        formatValue(_G.paused)
    )

    console.addLine(
        "chartLoaded=" ..
        tostring(
            _G.chartRuntime and
            _G.chartRuntime.chart ~= nil
        )
    )
end

function console.showProgram()
    console.addLine(
        console.getCurrentProgramSummary()
    )

    if _G.program then
        console.addLine(
            "program table=" ..
            tostring(_G.program)
        )
    else
        console.addLine(
            "program table=nil"
        )
    end
end

function console.showEditor()
    console.addLine(
        "editorStarted=" ..
        formatValue(_G.editorStarted) ..
        ", editorAutoplay=" ..
        formatValue(_G.editorAutoplay)
    )

    console.addLine(
        "lanegravity=" ..
        formatValue(_G.lanegravity) ..
        ", notegravity=" ..
        formatValue(_G.notegravity)
    )

    console.addLine(
        "musicload=" ..
        formatValue(_G.musicload) ..
        ", musicstarted=" ..
        formatValue(_G.songStarted)
    )

    console.addLine(
        "musictime=" ..
        formatValue(_G.musictime) ..
        ", musictimer=" ..
        formatValue(_G.musictimer)
    )
end

function console.showPlay()
    console.addLine(
        "score=" ..
        formatValue(
            _G.score and
            _G.score.score
        ) ..
        ", maxcombo=" ..
        formatValue(
            _G.score and
            _G.score.maxcombo
        )
    )

    console.addLine(
        "songStarted=" ..
        formatValue(_G.songStarted) ..
        ", waitingResume=" ..
        formatValue(_G.waitingResume)
    )

    console.addLine(
        "metaDisplayShown=" ..
        formatValue(_G.metaDisplayShown) ..
        ", metaDisplayFinished=" ..
        formatValue(_G.metaDisplayFinished)
    )
end

function console.showSong()
    local songData

    if type(getSelectedSongDisplayData) == "function" then
        local ok, result =
            pcall(
                getSelectedSongDisplayData
            )

        if ok and
            type(result) == "table" then

            songData = result
        end
    end

    if songData then
        console.addLine(
            "title=" ..
            formatValue(songData.title) ..
            ", artist=" ..
            formatValue(songData.artist)
        )

        console.addLine(
            "level=" ..
            formatValue(songData.level) ..
            ", levelColor=" ..
            formatValue(songData.levelColor)
        )
    else
        console.addLine(
            "曲データが利用できません"
        )
    end
end

local function getGlobalSongValue(
    globalName,
    fallbackNames
)
    local value =
        _G[globalName]

    if value ~= nil and
        value ~= "" then

        return value
    end

    if type(fallbackNames) == "table" then
        for _, name in ipairs(fallbackNames) do
            local fallback =
                _G[name]

            if fallback ~= nil and
                fallback ~= "" then

                return fallback
            end
        end
    end

    return value
end

function console.showGlobals()
    local displayX =
        _G.displayx

    local displayY =
        _G.displayy

    local songName =
        getGlobalSongValue(
            "name",
            {
                "title",
                "musicname",
                "songname"
            }
        )

    local songArtist =
        getGlobalSongValue(
            "artist",
            {
                "songartist",
                "artistName",
                "creator"
            }
        )

    local songLevel =
        getGlobalSongValue(
            "level",
            {
                "difficulty",
                "diff",
                "musicLevel"
            }
        )

    local jacketExists =
        _G.jacketimg ~= nil

    local bgmExists =
        _G.bgmSource ~= nil

    console.addLine(
        "displayx=" ..
        formatValue(displayX) ..
        ", displayy=" ..
        formatValue(displayY)
    )

    console.addLine(
        "name=" ..
        formatString(songName) ..
        ", artist=" ..
        formatString(songArtist) ..
        ", level=" ..
        formatString(songLevel)
    )

    console.addLine(
        "jacketimg=" ..
        tostring(jacketExists) ..
        ", bgmSource=" ..
        tostring(bgmExists)
    )

    if _G.programnumber ~= nil then
        console.addLine(
            "programnumber=" ..
            tostring(_G.programnumber) ..
            " (" ..
            console.getProgramName(
                _G.programnumber
            ) ..
            ")"
        )
    end
end

function console.addLine(text)
    local line =
        tostring(text or "")

    table.insert(
        console.lines,
        line
    )

    local maxStoredLines = 1000

    while #console.lines >
        maxStoredLines do

        table.remove(
            console.lines,
            1
        )
    end
end

function console.logError(
    msg,
    traceback_str,
    count
)
    local text =
        tostring(msg or "")

    if traceback_str and
        traceback_str ~= "" then

        text =
            text ..
            "\n" ..
            tostring(traceback_str)
    end

    console.addLine(
        "[ERROR] " .. text
    )

    if type(count) == "number" then
        console.errors[count] = text
    end
end

function console.submitCommand()
    local command =
        trim(console.input)

    console.addLine(
        "> " .. command
    )

    console.input = ""

    if command == "" then
        return
    end

    local cmd, args =
        command:match(
            "^(%S+)%s*(.*)$"
        )

    cmd =
        cmd and
        cmd:lower() or
        ""

    args =
        args or ""

    local spec =
        commandSpecs[cmd]

    if spec and
        spec.handler then

        local ok, err =
            pcall(
                spec.handler,
                args
            )

        if not ok then
            console.addLine(
                "[COMMAND ERROR] " ..
                tostring(err)
            )
        end

        return
    end

    console.addLine(
        "不明なコマンド: " ..
        cmd ..
        "。'help'と入力してください"
    )
end

function console.toggle()
    console.active =
        not console.active

    if love.keyboard and
        love.keyboard.setTextInput then

        love.keyboard.setTextInput(
            console.active
        )
    end

    if console.active then
        console.scrollOffset = 0

        console.addLine(
            "コンソール version 1.2.0  [help]コマンドでヘルプを表示"
        )
    else
        console.clear()
    end
end

function console.wheelmoved(x, y)
    if not console.active then
        return
    end

    local font =
        getConsoleFont()

    local lineHeight =
        (font and font:getHeight() or 20) + 4

    local height =
        _G.displayy or
        love.graphics.getHeight()

    local maxLines =
        math.max(
            1,
            math.floor(
                (height - 120) /
                lineHeight
            )
        )

    local maxOffset =
        math.max(
            0,
            #console.lines -
            maxLines
        )

    if y > 0 then
        console.scrollOffset =
            math.min(
                maxOffset,
                (console.scrollOffset or 0) + 3
            )
    elseif y < 0 then
        console.scrollOffset =
            math.max(
                0,
                (console.scrollOffset or 0) - 3
            )
    end
end

function console.keypressed(
    key,
    scancode,
    isrepeat
)
    if key == "escape" then
        console.toggle()
        return
    end

    if key == "backspace" then
        if #console.input > 0 then
            console.input =
                console.input:sub(
                    1,
                    -2
                )
        end

        return
    end

    if key == "tab" then
        local matches =
            getMatchingCommands(
                console.input
            )

        if #matches > 0 then
            console.input =
                matches[1].name ..
                " "
        end

        return
    end

    if key == "up" or
        key == "pageup" then

        local maxOffset =
            math.max(
                0,
                #console.lines -
                (console.maxLines or 28)
            )

        console.scrollOffset =
            math.max(
                0,
                (console.scrollOffset or 0) - 1
            )

        console.scrollOffset =
            math.min(
                console.scrollOffset,
                maxOffset
            )

        return
    end

    if key == "down" or
        key == "pagedown" then

        local maxOffset =
            math.max(
                0,
                #console.lines -
                (console.maxLines or 28)
            )

        console.scrollOffset =
            math.min(
                maxOffset,
                (console.scrollOffset or 0) + 1
            )

        return
    end

    if key == "c" and
        love.keyboard and
        love.keyboard.isDown and
        (
            love.keyboard.isDown("lctrl") or
            love.keyboard.isDown("rctrl")
        ) then

        copyConsoleOutput()
        return
    end

    if key == "return" or
        key == "kpenter" then

        console.submitCommand()
        return
    end
end

function console.textinput(t)
    console.input =
        console.input .. t
end

function console.draw()
    local width =
        _G.displayx or
        love.graphics.getWidth()

    local height =
        _G.displayy or
        love.graphics.getHeight()

    local font =
        getConsoleFont()

    local oldFont =
        love.graphics.getFont()

    if font then
        love.graphics.setFont(font)
    end

    local lineHeight =
        (font and font:getHeight() or 20) + 4

    local leftWidth =
        math.max(
            280,
            math.floor(width * 0.28)
        )

    love.graphics.push()

    love.graphics.setColor(
        0,
        0,
        0,
        0.88
    )

    love.graphics.rectangle(
        "fill",
        0,
        0,
        width,
        height
    )

    love.graphics.setColor(
        0.1,
        0.1,
        0.1,
        0.95
    )

    love.graphics.rectangle(
        "fill",
        10,
        10,
        leftWidth - 20,
        height - 80
    )

    love.graphics.setColor(
        1,
        1,
        1,
        0.95
    )

    love.graphics.print(
        "Command suggestions",
        16,
        14
    )

    love.graphics.setColor(
        0.5,
        0.5,
        0.5,
        0.9
    )

    love.graphics.line(
        16,
        34,
        leftWidth - 16,
        34
    )

    local matches =
        getMatchingCommands(
            console.input
        )

    local suggestY = 40

    if trim(console.input) == "" then
        love.graphics.setColor(
            0.7,
            0.7,
            0.7,
            0.9
        )

        love.graphics.print(
            "Type to search commands...",
            16,
            suggestY
        )

        suggestY =
            suggestY +
            lineHeight
    else
        for i = 1,
            math.min(
                #matches,
                math.floor(
                    (height - 120) /
                    (lineHeight * 2)
                )
            ) do

            love.graphics.setColor(
                1,
                1,
                1,
                1
            )

            love.graphics.print(
                matches[i].name,
                16,
                suggestY
            )

            love.graphics.setColor(
                0.8,
                0.8,
                0.8,
                0.8
            )

            love.graphics.print(
                matches[i].desc,
                18,
                suggestY +
                (font and font:getHeight() or 16)
            )

            suggestY =
                suggestY +
                lineHeight * 2
        end

        if #matches == 0 then
            love.graphics.setColor(
                1,
                1,
                1,
                1
            )

            love.graphics.print(
                "No matching command",
                16,
                suggestY
            )

            suggestY =
                suggestY +
                lineHeight
        end
    end

    love.graphics.setColor(
        1,
        1,
        1,
        0.95
    )

    love.graphics.print(
        "Console output",
        leftWidth + 16,
        14
    )

    love.graphics.setColor(
        0.5,
        0.5,
        0.5,
        0.9
    )

    love.graphics.line(
        leftWidth + 16,
        34,
        width - 16,
        34
    )

    local y = 40

    local maxLines =
        math.floor(
            (height - 120) /
            lineHeight
        )

    local maxOffset =
        math.max(
            0,
            #console.lines -
            maxLines
        )

    console.scrollOffset =
        math.min(
            console.scrollOffset or 0,
            maxOffset
        )

    local endIndex =
        #console.lines -
        (console.scrollOffset or 0)

    local start =
        math.max(
            1,
            endIndex - maxLines + 1
        )

    for i = start, endIndex do
        local line =
            console.lines[i]

        if line:sub(1, 1) == "\t" then
            local helpText =
                line:sub(2)

            local commandName,
                description =
                helpText:match(
                    "^(.-)\t(.*)$"
                )

            if commandName and
                description then

                local commandX =
                    leftWidth + 16

                local descriptionX =
                    leftWidth + 280

                love.graphics.setColor(
                    1,
                    1,
                    1,
                    1
                )

                love.graphics.print(
                    commandName,
                    commandX,
                    y
                )

                love.graphics.setColor(
                    0.8,
                    0.8,
                    0.8,
                    1
                )

                love.graphics.print(
                    description,
                    descriptionX,
                    y
                )
            else
                love.graphics.setColor(
                    1,
                    1,
                    1,
                    1
                )

                love.graphics.print(
                    helpText,
                    leftWidth + 16,
                    y
                )
            end
        else
            love.graphics.setColor(
                1,
                1,
                1,
                1
            )

            love.graphics.print(
                line,
                leftWidth + 16,
                y
            )
        end

        y =
            y +
            lineHeight
    end

    love.graphics.setColor(
        0.5,
        0.5,
        0.5,
        0.7
    )

    local scrollInfo =
        string.format(
            "[%d/%d]",
            #console.lines,
            maxLines
        )

    if maxOffset > 0 then
        local scrollPercent =
            math.floor(
                (
                    console.scrollOffset /
                    maxOffset
                ) * 100
            )

        scrollInfo =
            string.format(
                "[%d/%d] (%.0f%%)",
                #console.lines,
                maxLines,
                scrollPercent
            )
    end

    love.graphics.print(
        scrollInfo,
        width - 200,
        height - 62
    )

    love.graphics.setColor(
        0.15,
        0.15,
        0.15,
        0.98
    )

    love.graphics.rectangle(
        "fill",
        10,
        height - 50,
        width - 20,
        40
    )

    love.graphics.setColor(
        1,
        1,
        1,
        1
    )

    love.graphics.print(
        "> " .. console.input,
        16,
        height - 42
    )

    love.graphics.pop()

    if oldFont then
        love.graphics.setFont(oldFont)
    end
end

return console