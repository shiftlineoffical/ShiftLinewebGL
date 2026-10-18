local socket = require("socket")
local log = require("log")
local okGamejolt, gamejolt = pcall(require, "gamejolt")

local function networkLog(level, ...)
    local logger = log[level] or log.debug
    logger("[network]", ...)
end

local function registerBundledSSLModules()
    local moduleSymbols = {
        ["ssl.context"] = "luaopen_ssl_context",
        ["ssl.x509"] = "luaopen_ssl_x509",
        ["ssl.config"] = "luaopen_ssl_config"
    }

    local libraryPaths = {
        "ssl/core.dll",
        "./ssl/core.dll",
        ".\\ssl\\core.dll",
        "ssl/core.so",
        "./ssl/core.so",
        "ssl/core.dylib",
        "./ssl/core.dylib"
    }

    if love
        and love.filesystem
        and type(love.filesystem.getSource) == "function" then

        local source = love.filesystem.getSource()
        if type(source) == "string" and source ~= "" then
            table.insert(libraryPaths, 1, source .. "/ssl/core.dll")
            table.insert(libraryPaths, 2, source .. "/ssl/core.so")
            table.insert(libraryPaths, 3, source .. "/ssl/core.dylib")
        end
    end

    if type(package.loadlib) ~= "function" then
        networkLog("error", "package.loadlib is unavailable")
        return
    end

    for moduleName, symbolName in pairs(moduleSymbols) do
        if not package.preload[moduleName] then
            for _, libraryPath in ipairs(libraryPaths) do
                local ok, loader, loadError = pcall(
                    package.loadlib,
                    libraryPath,
                    symbolName
                )

                if ok and loader then
                    package.preload[moduleName] = loader
                    networkLog("debug", "Registered bundled SSL module", moduleName, libraryPath)
                    break
                end

                if not ok then
                    loadError = loader
                end

                loadError = tostring(loadError or "")
                if loadError ~= "" then
                    networkLog("debug", "Bundled SSL module path unavailable", libraryPath, loadError)
                end
            end
        end
    end
end

local function loadSSL()
    local candidates = {"ssl", "luasec", "ssl.core"}
    local errors = {}

    local cpath = package.cpath or ""
    local extraPaths = {
        ";?.dll",
        ";?.so",
        ";?.dylib",
        ";?/core.dll",
        ";?/core.so",
        ";?/core.dylib"
    }
    for _, path in ipairs(extraPaths) do
        if not cpath:find(path, 1, true) then
            cpath = cpath .. path
        end
    end
    package.cpath = cpath
    registerBundledSSLModules()

    for _, moduleName in ipairs(candidates) do
        networkLog("debug", "Loading SSL module", moduleName)

        local ok, module = pcall(require, moduleName)
        if ok and module and type(module.wrap) == "function" then
            networkLog("info", "SSL module loaded", moduleName)
            return module
        end
        if ok then
            errors[#errors + 1] = moduleName .. " does not provide ssl.wrap"
            networkLog("debug", "SSL module has no wrap", moduleName)
        else
            errors[#errors + 1] = tostring(module)
            networkLog("debug", "SSL module load failed", moduleName, tostring(module))
        end
    end

    networkLog("error", "No compatible SSL module found", table.concat(errors, " | "))
    return nil, table.concat(errors, "\n")
end
local ssl, sslLoadError = loadSSL()
local bit = require("bit")

local network = {}

network.config = {
    serverURL = os.getenv("SOCKET_URL")
        or os.getenv("WS_URL")
        or os.getenv("SHIFTLINE_SOCKET_URL")
        or "wss://shiftline-server.cloudoam.workers.dev/ws",
    roomIDLength = 10,
    roomIDPattern = "^[A-Za-z0-9]+$",
    roomIDGenerator = nil,
    roomIDValidator = nil,
}

network.SERVER_URL = network.config.serverURL

network.VERSION = 1

network.mode = "offline"

network.peer = nil
network.connected = false

network.playerID = nil
network.remotePlayerID = nil
network.roomID = nil
network.partyPlayers = {}

network.messages = {}
network.handlers = {}

network.ping = 0
network.lastPingTime = 0
network.pingInterval = 2
network.pingTimeout = 5

network.lastError = nil

network.connectTimeout = 5
network.handshakeTimeout = 10

network.httpAvailable = true

local pendingPing = nil
local pingTimes = {}

local connectionStartTime = 0
local handshakeStartTime = 0

local closing = false
local receiveBuffer = ""

local wsHost = nil
local wsPort = nil
local wsPath = nil
local wsSecure = false

local fragmentedOpcode = nil
local fragmentedPayload = {}

function network.configure(options)
    if type(options) ~= "table" then
        return false, "Invalid socket config"
    end

    if options.serverURL ~= nil then
        network.SERVER_URL = tostring(options.serverURL)
        network.config.serverURL = network.SERVER_URL
    end

    if options.roomIDLength ~= nil then
        local length = tonumber(options.roomIDLength)
        if length and length > 0 then
            network.config.roomIDLength = length
        end
    end

    if options.roomIDPattern ~= nil then
        network.config.roomIDPattern = tostring(options.roomIDPattern)
    end

    if options.roomIDGenerator ~= nil then
        network.config.roomIDGenerator = options.roomIDGenerator
    end

    if options.roomIDValidator ~= nil then
        network.config.roomIDValidator = options.roomIDValidator
    end

    return true
end

function network.setServerURL(url)
    if type(url) ~= "string" then
        return false, "Invalid server URL"
    end

    return network.configure({serverURL = url})
end

function network.getServerURL()
    return network.SERVER_URL
end

local CHARS =
    "ABCDEFGHJKLMNPQRSTUVWXYabcderghijklmnopqrstuvwxyzZ23456789"

local BASE64 =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ..
    "abcdefghijklmnopqrstuvwxyz" ..
    "0123456789+/"

-- 乱数文字列を作る
local function randomString(length)
    local result = {}

    for i = 1, length do
        local index =
            math.random(1, #CHARS)

        result[i] =
            CHARS:sub(index, index)
    end

    return table.concat(result)
end

-- イベントを発火する
local function emit(event, ...)
    local list =
        network.handlers[event]

    if not list then
        return
    end

    for _, callback in ipairs(list) do
        local ok, err =
            pcall(callback, ...)

        if not ok then
            network.lastError =
                tostring(err)
        end
    end
end

-- エラーを設定する
local function setError(message)
    network.lastError =
        tostring(message or "不明なエラー")

    networkLog("error", network.lastError)

    emit(
        "error",
        network.lastError
    )
end

local function isWouldBlockError(message)
    return message == "timeout"
        or message == "wantread"
        or message == "wantwrite"
end

local function resetPartyPlayers()
    network.partyPlayers = {}
end

local function addPartyPlayer(playerID)
    if type(playerID) == "string" and playerID ~= "" then
        network.partyPlayers[playerID] = true
    end
end

local function removePartyPlayer(playerID)
    if type(playerID) == "string" then
        network.partyPlayers[playerID] = nil
    end
end

-- イベントハンドラを登録する
function network.on(event, callback)
    if type(event) ~= "string" then
        return false
    end

    if type(callback) ~= "function" then
        return false
    end

    network.handlers[event] =
        network.handlers[event] or {}

    table.insert(
        network.handlers[event],
        callback
    )

    return true
end

-- プレイヤーIDを生成する
local function generatePlayerID()
    if okGamejolt
        and gamejolt
        and gamejolt.status
        and gamejolt.status.authenticated
        and tostring(gamejolt.status.username or "") ~= "" then
        return tostring(gamejolt.status.username)
    end

    return randomString(8)
end

-- 区切り文字で分割する
local function split(str, separator)
    local result = {}

    if type(str) ~= "string" then
        return result
    end

    if separator == "" then
        result[1] = str
        return result
    end

    local start = 1

    while true do
        local position =
            str:find(
                separator,
                start,
                true
            )

        if not position then
            result[#result + 1] =
                str:sub(start)

            break
        end

        result[#result + 1] =
            str:sub(
                start,
                position - 1
            )

        start =
            position + #separator
    end

    return result
end

-- URLを解析する
local function parseURL(url)
    if type(url) ~= "string" then
        return nil
    end

    local host, port, path

    host, port, path =
        url:match(
            "^wss://([^:/]+):(%d+)(/.*)$"
        )

    if host then
        return true,
            host,
            tonumber(port),
            path
    end

    host, path =
        url:match(
            "^wss://([^:/]+)(/.*)$"
        )

    if host then
        return true,
            host,
            443,
            path
    end

    host, port, path =
        url:match(
            "^ws://([^:/]+):(%d+)(/.*)$"
        )

    if host then
        return false,
            host,
            tonumber(port),
            path
    end

    host, path =
        url:match(
            "^ws://([^:/]+)(/.*)$"
        )

    if host then
        return false,
            host,
            80,
            path
    end

    return nil
end

-- URL用に文字列をエンコードする
local function urlEncode(value)
    value =
        tostring(value or "")

    return value:gsub(
        "([^%w%-_%.~])",
        function(c)
            return string.format(
                "%%%02X",
                string.byte(c)
            )
        end
    )
end

-- Base64をエンコードする
local function base64Encode(data)
    local result = {}
    local len = #data

    for i = 1, len, 3 do
        local a =
            string.byte(data, i) or 0

        local b =
            string.byte(data, i + 1) or 0

        local c =
            string.byte(data, i + 2) or 0

        local triple =
            a * 65536 +
            b * 256 +
            c

        local n1 =
            math.floor(triple / 262144) % 64

        local n2 =
            math.floor(triple / 4096) % 64

        local n3 =
            math.floor(triple / 64) % 64

        local n4 =
            triple % 64

        result[#result + 1] =
            BASE64:sub(
                n1 + 1,
                n1 + 1
            )

        result[#result + 1] =
            BASE64:sub(
                n2 + 1,
                n2 + 1
            )

        if i + 1 <= len then
            result[#result + 1] =
                BASE64:sub(
                    n3 + 1,
                    n3 + 1
                )
        else
            result[#result + 1] = "="
        end

        if i + 2 <= len then
            result[#result + 1] =
                BASE64:sub(
                    n4 + 1,
                    n4 + 1
                )
        else
            result[#result + 1] = "="
        end
    end

    return table.concat(result)
end

-- WebSocketキーを生成する
local function websocketKey()
    local bytes = {}

    for i = 1, 16 do
        bytes[i] =
            string.char(
                math.random(0, 255)
            )
    end

    return base64Encode(
        table.concat(bytes)
    )
end

-- SHA-1の左ローテートを行う
local function leftRotate(value, bits)
    return bit.bor(
        bit.lshift(
            value,
            bits
        ),
        bit.rshift(
            value,
            32 - bits
        )
    )
end

-- SHA-1を計算する
local function sha1(message)
    local bytes = {
        string.byte(
            message,
            1,
            #message
        )
    }

    local bitLength =
        #message * 8

    bytes[#bytes + 1] = 0x80

    while
        (#bytes % 64) ~= 56
    do
        bytes[#bytes + 1] = 0
    end

    local high =
        math.floor(
            bitLength / 4294967296
        )

    local low =
        bitLength % 4294967296

    bytes[#bytes + 1] =
        bit.band(
            bit.rshift(high, 24),
            0xFF
        )

    bytes[#bytes + 1] =
        bit.band(
            bit.rshift(high, 16),
            0xFF
        )

    bytes[#bytes + 1] =
        bit.band(
            bit.rshift(high, 8),
            0xFF
        )

    bytes[#bytes + 1] =
        bit.band(
            high,
            0xFF
        )

    bytes[#bytes + 1] =
        bit.band(
            bit.rshift(low, 24),
            0xFF
        )

    bytes[#bytes + 1] =
        bit.band(
            bit.rshift(low, 16),
            0xFF
        )

    bytes[#bytes + 1] =
        bit.band(
            bit.rshift(low, 8),
            0xFF
        )

    bytes[#bytes + 1] =
        bit.band(
            low,
            0xFF
        )

    local h0 = 0x67452301
    local h1 = 0xEFCDAB89
    local h2 = 0x98BADCFE
    local h3 = 0x10325476
    local h4 = 0xC3D2E1F0

    for chunkStart = 1, #bytes, 64 do
        local w = {}

        for i = 0, 15 do
            local p =
                chunkStart +
                i * 4

            w[i] =
                bit.bor(
                    bit.lshift(
                        bytes[p],
                        24
                    ),
                    bit.lshift(
                        bytes[p + 1],
                        16
                    ),
                    bit.lshift(
                        bytes[p + 2],
                        8
                    ),
                    bytes[p + 3]
                )
        end

        for i = 16, 79 do
            w[i] =
                leftRotate(
                    bit.bxor(
                        w[i - 3],
                        w[i - 8],
                        w[i - 14],
                        w[i - 16]
                    ),
                    1
                )
        end

        local a = h0
        local b = h1
        local c = h2
        local d = h3
        local e = h4

        for i = 0, 79 do
            local f
            local k

            if i < 20 then
                f =
                    bit.bor(
                        bit.band(b, c),
                        bit.band(
                            bit.bnot(b),
                            d
                        )
                    )

                k = 0x5A827999

            elseif i < 40 then
                f =
                    bit.bxor(
                        b,
                        c,
                        d
                    )

                k = 0x6ED9EBA1

            elseif i < 60 then
                f =
                    bit.bor(
                        bit.band(b, c),
                        bit.band(b, d),
                        bit.band(c, d)
                    )

                k = 0x8F1BBCDC

            else
                f =
                    bit.bxor(
                        b,
                        c,
                        d
                    )

                k = 0xCA62C1D6
            end

            local temp =
                bit.band(
                    leftRotate(a, 5) +
                    f +
                    e +
                    k +
                    w[i],
                    0xFFFFFFFF
                )

            e = d
            d = c
            c = leftRotate(b, 30)
            b = a
            a = temp
        end

        h0 =
            bit.band(
                h0 + a,
                0xFFFFFFFF
            )

        h1 =
            bit.band(
                h1 + b,
                0xFFFFFFFF
            )

        h2 =
            bit.band(
                h2 + c,
                0xFFFFFFFF
            )

        h3 =
            bit.band(
                h3 + d,
                0xFFFFFFFF
            )

        h4 =
            bit.band(
                h4 + e,
                0xFFFFFFFF
            )
    end

    local function wordToBytes(word)
        return string.char(
            bit.band(
                bit.rshift(word, 24),
                0xFF
            ),
            bit.band(
                bit.rshift(word, 16),
                0xFF
            ),
            bit.band(
                bit.rshift(word, 8),
                0xFF
            ),
            bit.band(
                word,
                0xFF
            )
        )
    end

    return
        wordToBytes(h0) ..
        wordToBytes(h1) ..
        wordToBytes(h2) ..
        wordToBytes(h3) ..
        wordToBytes(h4)
end

-- WebSocketマスクを作る
local function makeMask()
    local mask = {}

    for i = 1, 4 do
        mask[i] =
            math.random(0, 255)
    end

    return mask
end

-- WebSocketマスクを適用する
local function applyMask(payload, mask)
    local result = {}

    for i = 1, #payload do
        local byte =
            string.byte(payload, i)

        local maskByte =
            mask[
                ((i - 1) % 4) + 1
            ]

        result[i] =
            string.char(
                bit.bxor(
                    byte,
                    maskByte
                )
            )
    end

    return table.concat(result)
end

-- WebSocketフレームを作る
local function encodeFrame(payload, opcode)
    opcode = opcode or 1
    payload = payload or ""

    local mask =
        makeMask()

    local maskedPayload =
        applyMask(
            payload,
            mask
        )

    local length =
        #maskedPayload

    local first =
        string.char(
            0x80 + opcode
        )

    local header

    if length < 126 then

        header =
            first ..
            string.char(
                0x80 + length
            )

    elseif length < 65536 then

        local high =
            math.floor(
                length / 256
            )

        local low =
            length % 256

        header =
            first ..
            string.char(
                0x80 + 126
            ) ..
            string.char(
                high,
                low
            )

    else

        local bytes = {}

        for i = 7, 0, -1 do
            bytes[#bytes + 1] =
                string.char(
                    math.floor(
                        length /
                        (256 ^ i)
                    ) % 256
                )
        end

        header =
            first ..
            string.char(
                0x80 + 127
            ) ..
            table.concat(bytes)
    end

    local maskString =
        string.char(
            mask[1],
            mask[2],
            mask[3],
            mask[4]
        )

    return header ..
        maskString ..
        maskedPayload
end

-- WebSocketフレームを解析する
local function decodeFrame(buffer)
    if #buffer < 2 then
        return nil, buffer
    end

    local b1 =
        string.byte(buffer, 1)

    local b2 =
        string.byte(buffer, 2)

    local fin =
        bit.band(
            b1,
            0x80
        ) ~= 0

    local rsv1 =
        bit.band(
            b1,
            0x40
        ) ~= 0

    local rsv2 =
        bit.band(
            b1,
            0x20
        ) ~= 0

    local rsv3 =
        bit.band(
            b1,
            0x10
        ) ~= 0

    local opcode =
        bit.band(
            b1,
            0x0F
        )

    local masked =
        bit.band(
            b2,
            0x80
        ) ~= 0

    local length =
        bit.band(
            b2,
            0x7F
        )

    local position = 3

    if rsv1 or rsv2 or rsv3 then
        return nil,
            nil,
            "未対応のRSVビット"
    end

    if opcode ~= 0
        and opcode ~= 1
        and opcode ~= 2
        and opcode ~= 8
        and opcode ~= 9
        and opcode ~= 10 then

        return nil,
            nil,
            "未知のWebSocket Opcode"
    end

    if opcode >= 8 then

        if not fin then
            return nil,
                nil,
                "Control Frameの分割は不正です"
        end

        if length > 125 then
            return nil,
                nil,
                "Control Frameが大きすぎます"
        end
    end

    if length == 126 then

        if #buffer < 4 then
            return nil, buffer
        end

        length =
            string.byte(buffer, 3) * 256 +
            string.byte(buffer, 4)

        position = 5

    elseif length == 127 then

        if #buffer < 10 then
            return nil, buffer
        end

        length = 0

        for i = 3, 10 do
            length =
                length * 256 +
                string.byte(buffer, i)
        end

        position = 11
    end

    if length > 16 * 1024 * 1024 then
        return nil,
            nil,
            "WebSocketフレームが大きすぎます"
    end

    local mask

    if masked then

        if #buffer <
            position + 3 then

            return nil, buffer
        end

        mask = {
            string.byte(
                buffer,
                position
            ),

            string.byte(
                buffer,
                position + 1
            ),

            string.byte(
                buffer,
                position + 2
            ),

            string.byte(
                buffer,
                position + 3
            )
        }

        position =
            position + 4
    end

    local frameEnd =
        position + length - 1

    if #buffer < frameEnd then
        return nil, buffer
    end

    local payload = ""

    if length > 0 then
        payload =
            buffer:sub(
                position,
                frameEnd
            )
    end

    if masked then
        payload =
            applyMask(
                payload,
                mask
            )
    end

    local remaining = ""

    if frameEnd < #buffer then
        remaining =
            buffer:sub(
                frameEnd + 1
            )
    end

    return {
        fin = fin,
        opcode = opcode,
        masked = masked,
        payload = payload
    }, remaining
end

-- フレームを送信する
local function sendRawFrame(payload, opcode)
    if not network.peer then
        networkLog("warn", "Send failed: no active peer", "opcode=" .. tostring(opcode))
        return false, "未接続"
    end

    networkLog(
        "debug",
        "Sending WebSocket frame",
        "opcode=" .. tostring(opcode),
        "bytes=" .. tostring(#(payload or ""))
    )

    local frame =
        encodeFrame(
            payload,
            opcode
        )

    local position = 1

    while position <= #frame do
        local sent, err =
            network.peer:send(
                frame,
                position
            )

        if not sent then
            network.lastError =
                tostring(err)

            networkLog("error", "Frame send failed", tostring(err))

            return false, err
        end

        position =
            position + sent
    end

    return true
end

-- WebSocketハンドシェイクを行う
local function websocketHandshake()
    local key =
        websocketKey()

    networkLog(
        "info",
        "Starting WebSocket handshake",
        wsHost .. ":" .. tostring(wsPort),
        wsPath
    )

    local request =
        "GET " ..
        wsPath ..
        " HTTP/1.1\r\n" ..

        "Host: " ..
        wsHost .. "\r\n" ..

        "Upgrade: websocket\r\n" ..

        "Connection: Upgrade\r\n" ..

        "Sec-WebSocket-Key: " ..
        key .. "\r\n" ..

        "Sec-WebSocket-Version: 13\r\n" ..

        "\r\n"

    local sent, err =
        network.peer:send(request)

    if not sent then
        networkLog("error", "WebSocket handshake request failed", tostring(err))
        return false, err
    end

    networkLog("debug", "WebSocket handshake request sent", "bytes=" .. tostring(#request))

    local buffer = ""

    local start =
        socket.gettime()

    while
        socket.gettime() - start <
        network.handshakeTimeout
    do

        local data,
            receiveError,
            partial =
            network.peer:receive(4096)

        if data then

            buffer =
                buffer .. data

            networkLog("debug", "Handshake response data received", "bytes=" .. tostring(#data))

        elseif partial
            and #partial > 0 then

            buffer =
                buffer .. partial

            networkLog("debug", "Handshake response partial data received", "bytes=" .. tostring(#partial), "error=" .. tostring(receiveError))

        elseif isWouldBlockError(receiveError) then

            socket.sleep(0.01)

        else

            networkLog("error", "Handshake response receive failed", tostring(receiveError))

            return false,
                receiveError
        end

        local headerEnd =
            buffer:find(
                "\r\n\r\n",
                1,
                true
            )

        if headerEnd then
            break
        end
    end

    local headerEnd =
        buffer:find(
            "\r\n\r\n",
            1,
            true
        )

    if not headerEnd then
        networkLog("error", "WebSocket handshake timed out", "bytes=" .. tostring(#buffer))
        return false,
            "WebSocketハンドシェイクタイムアウト"
    end

    local header =
        buffer:sub(
            1,
            headerEnd + 3
        )

    local remaining =
        buffer:sub(
            headerEnd + 4
        )

    receiveBuffer =
        remaining

    local status =
        header:match(
            "^HTTP/%d%.%d%s+(%d+)"
        )

    if tonumber(status) ~= 101 then
        networkLog("error", "WebSocket handshake rejected", "status=" .. tostring(status))
        return false,
            "WebSocket接続拒否: " ..
            tostring(status)
    end

    local upgrade =
        header:match(
            "[Uu]pgrade:%s*([^\r\n]+)"
        )

    if not upgrade
        or upgrade:lower() ~= "websocket" then

        networkLog("error", "Invalid Upgrade header", tostring(upgrade))

        return false,
            "Upgradeヘッダー不正"
    end

    local connection =
        header:match(
            "[Cc]onnection:%s*([^\r\n]+)"
        )

    if not connection
        or not connection:lower():find(
            "upgrade",
            1,
            true
        ) then

        networkLog("error", "Invalid Connection header", tostring(connection))

        return false,
            "Connectionヘッダー不正"
    end

    local accept =
        header:match(
            "[Ss]ec%-[Ww]eb[Ss]ocket%-[Aa]ccept:%s*([^\r\n]+)"
        )

    if not accept then
        networkLog("error", "Missing Sec-WebSocket-Accept header")
        return false,
            "Sec-WebSocket-Acceptがありません"
    end

    local expected =
        base64Encode(
            sha1(
                key ..
                "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
            )
        )

    if accept:gsub(
        "%s+$",
        ""
    ) ~= expected then

        networkLog("error", "Invalid Sec-WebSocket-Accept header")

        return false,
            "Sec-WebSocket-Accept不正"
    end

    networkLog("info", "WebSocket handshake completed", "bufferedBytes=" .. tostring(#receiveBuffer))

    return true
end

-- TCPとTLSを接続する
local function connectWebSocket(url, roomID)
    local secure,
        host,
        port,
        path =
        parseURL(url)

    if secure == nil then
        networkLog("error", "Invalid WebSocket URL", tostring(url))
        return nil,
            "WebSocket URL不正"
    end

    networkLog(
        "info",
        "Connecting",
        (secure and "TLS" or "TCP"),
        host .. ":" .. tostring(port),
        "room=" .. tostring(roomID),
        "player=" .. tostring(network.playerID)
    )

    local start =
        socket.gettime()

    path =
        path ..
        "?room=" ..
        urlEncode(roomID) ..
        "&player=" ..
        urlEncode(network.playerID)

    local tcp =
        socket.tcp()

    if not tcp then
        networkLog("error", "TCP socket creation failed")
        return nil,
            "TCPソケット作成失敗"
    end

    tcp:settimeout(
        network.connectTimeout
    )

    local ok, err =
        tcp:connect(
            host,
            port
        )

    if not ok then
        networkLog("error", "TCP connection failed", tostring(err))
        tcp:close()
        return nil, err
    end

    networkLog("info", "TCP connection established", "elapsed=" .. tostring(socket.gettime() - start))

    if socket.gettime() - start >=
        network.connectTimeout then

        tcp:close()

        return nil,
            "TCP接続タイムアウト"
    end

    if secure then

        if not ssl then
            networkLog("error", "LuaSec unavailable", tostring(sslLoadError))
            return nil,
                "LuaSecが見つかりません。使用OS用のssl.luaとネイティブライブラリ(.dll/.so/.dylib)をLÖVEのゲームフォルダに配置してください: " .. tostring(sslLoadError)
        end

        local params = {
            mode = "client",

            protocol = "any",

            verify = "none",

            options = "all",

            server = host
        }

        local wrapped,
            wrapError =
            ssl.wrap(
                tcp,
                params
            )

        if not wrapped then
            networkLog("error", "TLS socket wrapping failed", tostring(wrapError))
            tcp:close()

            return nil,
                wrapError
        end

        tcp = wrapped

        local sniOK,
            sniError =
            pcall(function()
                tcp:sni(host)
            end)

        if not sniOK then
            networkLog("error", "TLS SNI setup failed", tostring(sniError))
            tcp:close()

            return nil,
                tostring(sniError or "SNI設定失敗")
        end

        networkLog("debug", "TLS SNI configured", host)

        tcp:settimeout(
            network.connectTimeout
        )

        local handshakeOK,
            handshakeError =
            tcp:dohandshake()

        if not handshakeOK then
            networkLog("error", "TLS handshake failed", tostring(handshakeError))
            tcp:close()

            return nil,
                handshakeError
        end

        networkLog("info", "TLS handshake completed", host)
    end

    tcp:settimeout(0)

    network.peer = tcp

    wsHost = host
    wsPort = port
    wsPath = path
    wsSecure = secure

    receiveBuffer = ""

    fragmentedOpcode = nil
    fragmentedPayload = {}

    local handshakeOK,
        handshakeError =
        websocketHandshake()

    if not handshakeOK then

        networkLog("error", "WebSocket handshake failed", tostring(handshakeError))

        pcall(function()
            tcp:close()
        end)

        network.peer = nil

        return nil,
            handshakeError
    end

    networkLog("info", "WebSocket connection ready", host .. ":" .. tostring(port))

    return true
end

-- パケットを送信する
local function sendPacket(packet)
    return sendRawFrame(
        packet,
        1
    )
end

local function findTrustedCAFile()
    local configured = os.getenv("SHIFTLINE_CA_FILE")
        or os.getenv("SSL_CERT_FILE")
    if configured and configured ~= "" then
        local file = io.open(configured, "rb")
        if file then
            file:close()
            return configured
        end
        return nil, "Configured CA bundle is not readable: " .. configured
    end

    local candidates = {}
    local source = love
        and love.filesystem
        and type(love.filesystem.getSource) == "function"
        and love.filesystem.getSource()
    if type(source) == "string" and source ~= "" then
        candidates[#candidates + 1] = source .. "/ssl/cacert.pem"
        candidates[#candidates + 1] = source .. "/cacert.pem"
    end

    local isWindows = package.config
        and package.config:sub(1, 1) == "\\"
    if isWindows then
        local programFiles = os.getenv("ProgramFiles") or "C:\\Program Files"
        local programFilesX86 = os.getenv("ProgramFiles(x86)") or "C:\\Program Files (x86)"
        candidates[#candidates + 1] = programFiles .. "\\Git\\mingw64\\ssl\\certs\\ca-bundle.crt"
        candidates[#candidates + 1] = programFilesX86 .. "\\Git\\mingw64\\ssl\\certs\\ca-bundle.crt"
        candidates[#candidates + 1] = programFiles .. "\\Common Files\\SSL\\cert.pem"
    else
        candidates[#candidates + 1] = "/etc/ssl/certs/ca-certificates.crt"
        candidates[#candidates + 1] = "/etc/pki/tls/certs/ca-bundle.crt"
        candidates[#candidates + 1] = "/etc/ssl/cert.pem"
    end

    for _, candidate in ipairs(candidates) do
        local file = io.open(candidate, "rb")
        if file then
            file:close()
            return candidate
        end
    end
    return nil
end

function network.sendWSS(url, message, timeoutSeconds)
    if type(url) ~= "string" or type(message) ~= "string" then
        return false, "WSS URL and message must be strings"
    end

    local secure, host, port, path = parseURL(url)
    if secure ~= true then
        return false, "Report transport requires a wss:// URL"
    end

    if #message > 1024 * 1024 then
        return false, "WebSocket message exceeds 1 MiB"
    end

    if not ssl then
        return false, "LuaSec is unavailable: " .. tostring(sslLoadError)
    end

    local timeout = math.max(1, tonumber(timeoutSeconds) or 5)
    local tcpOK, tcp, err = pcall(socket.tcp)
    if not tcpOK or not tcp then
        return false, "TCP socket creation failed: " .. tostring(err or tcp)
    end

    local function closeSocket()
        if tcp then
            pcall(function()
                tcp:close()
            end)
        end
    end

    tcp:settimeout(timeout)
    local connectOK, connected, connectError = pcall(tcp.connect, tcp, host, port)
    if not connectOK or not connected then
        closeSocket()
        return false, "TCP connection failed: " .. tostring(connectError or connected)
    end

    local caFile, caError = findTrustedCAFile()
    local caPath = os.getenv("SSL_CERT_DIR")
    if not caFile and (not caPath or caPath == "") then
        closeSocket()
        return false, caError
            or "Trusted CA certificates were not found; configure SHIFTLINE_CA_FILE"
    end

    local tlsOptions = {
        mode = "client",
        protocol = "any",
        verify = "peer",
        options = "all",
        server = host,
        cafile = caFile,
        capath = caPath
    }

    local wrapOK, tlsSocket, wrapError = pcall(ssl.wrap, tcp, tlsOptions)
    if not wrapOK or not tlsSocket then
        closeSocket()
        return false, "TLS wrapping failed: " .. tostring(wrapError or tlsSocket)
    end
    tcp = tlsSocket

    local sniOK, sniError = pcall(function()
        tcp:sni(host)
    end)
    if not sniOK then
        closeSocket()
        return false, "TLS SNI setup failed: " .. tostring(sniError)
    end

    local timeoutOK, timeoutError = pcall(tcp.settimeout, tcp, timeout)
    if not timeoutOK then
        closeSocket()
        return false, "TLS socket timeout setup failed: " .. tostring(timeoutError)
    end
    local handshakeCallOK, handshakeOK, handshakeError = pcall(tcp.dohandshake, tcp)
    if not handshakeCallOK or not handshakeOK then
        closeSocket()
        return false, "TLS certificate/handshake verification failed: " .. tostring(handshakeError or handshakeOK)
    end

    local key = websocketKey()
    local hostHeader = host
    if port ~= 443 then
        hostHeader = host .. ":" .. tostring(port)
    end
    local request = table.concat({
        "GET " .. path .. " HTTP/1.1\r\n",
        "Host: " .. hostHeader .. "\r\n",
        "Upgrade: websocket\r\n",
        "Connection: Upgrade\r\n",
        "Sec-WebSocket-Key: " .. key .. "\r\n",
        "Sec-WebSocket-Version: 13\r\n",
        "\r\n"
    })

    local function sendAll(data)
        local position = 1
        while position <= #data do
            local callOK, sent, sendError, lastByte = pcall(tcp.send, tcp, data, position)
            if not callOK then
                return false, sent
            end
            if sent then
                position = sent + 1
            elseif lastByte and lastByte >= position then
                position = lastByte + 1
            else
                return false, sendError
            end
        end
        return true
    end

    local requestSent, requestError = sendAll(request)
    if not requestSent then
        closeSocket()
        return false, "WebSocket handshake request failed: " .. tostring(requestError)
    end

    local response = ""
    local deadline = socket.gettime() + timeout
    while not response:find("\r\n\r\n", 1, true)
        and socket.gettime() < deadline
        and #response < 16384 do
        local receiveOK, data, receiveError, partial =
            pcall(tcp.receive, tcp, 4096)
        if not receiveOK then
            closeSocket()
            return false, "WebSocket handshake read failed: " .. tostring(data)
        end
        response = response .. (data or partial or "")
        if not data and receiveError ~= "timeout"
            and receiveError ~= "wantread"
            and receiveError ~= "wantwrite" then
            closeSocket()
            return false, "WebSocket handshake response failed: " .. tostring(receiveError)
        end
    end

    local headerEnd = response:find("\r\n\r\n", 1, true)
    if not headerEnd then
        closeSocket()
        return false, "WebSocket handshake timed out or response headers were too large"
    end

    local header = response:sub(1, headerEnd + 3)
    local status = tonumber(header:match("^HTTP/%d%.%d%s+(%d+)"))
    local upgrade = header:match("[Uu]pgrade:%s*([^\r\n]+)")
    local connection = header:match("[Cc]onnection:%s*([^\r\n]+)")
    local accept = header:match("[Ss]ec%-[Ww]eb[Ss]ocket%-[Aa]ccept:%s*([^\r\n]+)")
    local expectedAccept = base64Encode(sha1(
        key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    ))
    if status ~= 101
        or not upgrade
        or upgrade:lower() ~= "websocket"
        or not connection
        or not connection:lower():find("upgrade", 1, true)
        or not accept
        or accept:gsub("%s+$", "") ~= expectedAccept then
        closeSocket()
        return false, "WebSocket server rejected or failed to validate the TLS upgrade"
    end

    local frameOK, frame = pcall(encodeFrame, message, 1)
    if not frameOK then
        closeSocket()
        return false, "WebSocket frame encoding failed: " .. tostring(frame)
    end
    local frameSent, frameError = sendAll(frame)
    if not frameSent then
        closeSocket()
        return false, "WebSocket payload send failed: " .. tostring(frameError)
    end

    closeSocket()
    return true
end

-- ゲームパケットを送信する
function network.send(typeName, ...)
    if type(typeName) ~= "string"
        or typeName == "" then

        return false,
            "パケット不正"
    end

    if not network.peer then
        return false,
            "未接続"
    end

    local packet =
        typeName

    local values = {
        ...
    }

    for _, value in ipairs(values) do

        value =
            tostring(value)

        value =
            value:gsub(
                "|",
                ""
            )

        value =
            value:gsub(
                "[\r\n]",
                ""
            )

        packet =
            packet ..
            "|" ..
            value
    end

    return sendPacket(packet)
end

-- 接続完了状態にする
local function setConnected(remotePlayerID)
    network.remotePlayerID =
        remotePlayerID

    resetPartyPlayers()
    addPartyPlayer(network.playerID)
    addPartyPlayer(remotePlayerID)

    network.connected = true

    connectionStartTime = 0
    handshakeStartTime = 0

    network.lastPingTime =
        socket.gettime()

    pendingPing = nil
    pingTimes = {}

    emit(
        "connected",
        network.remotePlayerID
    )
end

-- 完成したアプリケーションメッセージを処理する
local function processPacket(packet)
    if type(packet) ~= "string"
        or packet == "" then

        return
    end

    local parts =
        split(
            packet,
            "|"
        )

    local typeName =
        parts[1]

    if not typeName then
        return
    end

    if typeName == "WELCOME" then

        local remoteID =
            parts[2]

        if not remoteID then
            setError(
                "WELCOME不正"
            )

            network.close(false)

            return
        end

        setConnected(
            remoteID
        )

        return
    end

    if typeName == "PLAYER_JOIN" then

        local remoteID =
            parts[2]

        if remoteID then

            network.remotePlayerID =
                remoteID

            addPartyPlayer(remoteID)

            emit(
                "player_join",
                remoteID
            )
        end

        return
    end

    if typeName == "PLAYER_LEAVE" then

        local remoteID =
            parts[2]

        removePartyPlayer(remoteID)

        emit(
            "player_leave",
            remoteID
        )

        if network.remotePlayerID ==
            remoteID then

            network.remotePlayerID =
                nil
        end

        return
    end

    if typeName == "PING" then

        local id =
            parts[2]

        if id then
            network.send(
                "PONG",
                id
            )
        end

        return
    end

    if typeName == "PONG" then

        local id =
            parts[2]

        local start =
            pingTimes[id]

        if start then

            network.ping =
                (
                    socket.gettime() -
                    start
                ) * 1000

            pingTimes[id] =
                nil

            if pendingPing == id then
                pendingPing = nil
            end

            emit(
                "ping",
                network.ping
            )
        end

        return
    end

    if typeName == "ERROR" then

        local errorCode =
            parts[2] or "UNKNOWN"

        setError(
            "サーバーエラー: " ..
            errorCode
        )

        return
    end

    if typeName == "DISCONNECT" then

        local reason =
            parts[2] or "切断"

        emit(
            "disconnect",
            reason
        )

        network.close(false)

        return
    end

    emit(
        "packet",
        typeName,
        parts
    )
end

-- WebSocketメッセージを処理する
local function processMessage(opcode, payload)
    if opcode == 1 then
        processPacket(payload)
        return
    end

    if opcode == 2 then
        emit(
            "binary",
            payload
        )
        return
    end
end

-- WebSocketフレームを処理する
local function processFrame(frame)
    if not frame then
        return
    end

    local opcode =
        frame.opcode

    local payload =
        frame.payload or ""

    networkLog(
        "debug",
        "Received WebSocket frame",
        "opcode=" .. tostring(opcode),
        "fin=" .. tostring(frame.fin),
        "bytes=" .. tostring(#payload)
    )

    if frame.masked then
        setError(
            "サーバーからのFrameがMaskされています"
        )

        network.close(false)

        return
    end

    if opcode == 0 then

        if not fragmentedOpcode then
            setError(
                "不正なContinuation Frame"
            )

            network.close(false)

            return
        end

        fragmentedPayload[#fragmentedPayload + 1] =
            payload

        if frame.fin then

            local completePayload =
                table.concat(
                    fragmentedPayload
                )

            local completeOpcode =
                fragmentedOpcode

            fragmentedOpcode = nil
            fragmentedPayload = {}

            processMessage(
                completeOpcode,
                completePayload
            )
        end

        return
    end

    if opcode == 1
        or opcode == 2 then

        if fragmentedOpcode then
            setError(
                "未完了Message中に新しいMessageがあります"
            )

            network.close(false)

            return
        end

        if frame.fin then
            processMessage(
                opcode,
                payload
            )
        else
            fragmentedOpcode =
                opcode

            fragmentedPayload = {
                payload
            }
        end

        return
    end

    if opcode == 8 then

        if network.peer then
            pcall(function()
                sendRawFrame(
                    payload,
                    8
                )
            end)
        end

        emit(
            "disconnect",
            "WebSocket切断"
        )

        network.close(false)

        return
    end

    if opcode == 9 then

        sendRawFrame(
            payload,
            10
        )

        return
    end

    if opcode == 10 then
        local start =
            pingTimes[payload]

        if start then
            network.ping =
                (socket.gettime() - start) * 1000

            pingTimes[payload] = nil

            if pendingPing == payload then
                pendingPing = nil
            end

            emit(
                "ping",
                network.ping
            )
        end

        return
    end
end

-- 受信データを処理する
local function receivePackets()
    if not network.peer then
        return
    end

    local function processBufferedFrames()
        while #receiveBuffer > 0 do

            local frame,
                remaining,
                frameError =
                decodeFrame(
                    receiveBuffer
                )

            if frameError then

                setError(
                    frameError
                )

                network.close(false)

                return false
            end

            if not frame then
                return true
            end

            receiveBuffer =
                remaining or ""

            processFrame(frame)

            if not network.peer then
                return false
            end
        end

        return true
    end

    while network.peer do

        if not processBufferedFrames() then
            return
        end

        local data,
            err,
            partial =
            network.peer:receive(4096)

        if data then

            receiveBuffer =
                receiveBuffer .. data

            networkLog("debug", "Received socket data", "bytes=" .. tostring(#data), "buffer=" .. tostring(#receiveBuffer))

        elseif partial
            and #partial > 0 then

            receiveBuffer =
                receiveBuffer .. partial

            networkLog("debug", "Received partial socket data", "bytes=" .. tostring(#partial), "error=" .. tostring(err))

            if not isWouldBlockError(err) then

                emit(
                    "disconnect",
                    tostring(err)
                )

                network.close(false)

                return
            end

        elseif isWouldBlockError(err) then

            break

        elseif err == "closed" then

            networkLog("warn", "Socket closed by peer")

            emit(
                "disconnect",
                "接続終了"
            )

            network.close(false)

            return

        else
            networkLog("error", "Socket receive failed", tostring(err))
            break
        end

        if not processBufferedFrames() then
            return
        end
    end
end

-- RoomIDを作成する
function network.createRoomID(int)
    local length = int or network.config.roomIDLength or 10
    if type(network.config.roomIDGenerator) == "function" then
        return network.config.roomIDGenerator(length)
    end

    return randomString(length)
end

-- 外部RoomIDを作成する
function network.createExternalRoomID()
    return network.createRoomID()
end

-- RoomIDを検証する
function network.parseRoomID(roomID)
    if type(roomID) ~= "string" then
        return nil,
            nil,
            "RoomID不正"
    end

    roomID =
        roomID:match(
            "^%s*(.-)%s*$"
        )

    if roomID == "" then
        return nil,
            nil,
            "RoomID不正"
    end

    if #roomID > 64 then
        return nil,
            nil,
            "RoomIDが長すぎます"
    end

    if type(network.config.roomIDValidator) == "function" then
        local ok, normalized, err = network.config.roomIDValidator(roomID)
        if ok == false then
            return nil, nil, err or "RoomID不正"
        end
        if ok == true then
            return normalized or roomID
        end
    end

    local pattern = network.config.roomIDPattern or "^[A-Za-z0-9]+$"
    if not roomID:match(pattern) then
        return nil,
            nil,
            "RoomID不正"
    end

    return roomID
end

-- ホストとして接続する
function network.host(urlOrConfig)
    networkLog("info", "Host connection requested")

    if type(urlOrConfig) == "string" then
        network.setServerURL(urlOrConfig)
    elseif type(urlOrConfig) == "table" then
        network.configure(urlOrConfig)
    end

    network.close(false)

    network.lastError = nil

    if network.SERVER_URL == "" then
        setError("オンラインサーバー未設定です。SOCKET_URL、WS_URL、またはSHIFTLINE_SOCKET_URLを設定してください")
        return false
    end

    network.mode = "host"

    network.playerID =
        generatePlayerID()

    local roomID =
        network.createRoomID()

    connectionStartTime =
        socket.gettime()

    local ok, err =
        connectWebSocket(
            network.SERVER_URL,
            roomID
        )

    if not ok then

        networkLog("error", "Host connection failed", tostring(err))

        setError(err)

        network.mode =
            "offline"

        network.playerID =
            nil

        return false
    end

    handshakeStartTime =
        socket.gettime()

    network.roomID =
        roomID

    emit(
        "hosting",
        roomID
    )

    networkLog("info", "Host connection initialized", "room=" .. tostring(roomID))

    return true
end

-- Roomに参加する
function network.join(roomID, urlOrConfig)
    networkLog("info", "Join connection requested", "room=" .. tostring(roomID))

    if type(urlOrConfig) == "string" then
        network.setServerURL(urlOrConfig)
    elseif type(urlOrConfig) == "table" then
        network.configure(urlOrConfig)
    end

    network.close(false)

    network.lastError = nil

    if network.SERVER_URL == "" then
        setError("オンラインサーバー未設定です。SOCKET_URL、WS_URL、またはSHIFTLINE_SOCKET_URLを設定してください")
        return false
    end

    local parsedRoomID,
        _,
        err =
        network.parseRoomID(
            roomID
        )

    if not parsedRoomID then
        setError(err)

        return false
    end

    network.lastError = nil

    network.mode = "client"

    network.playerID =
        generatePlayerID()

    connectionStartTime =
        socket.gettime()

    local ok,
        connectError =
        connectWebSocket(
            network.SERVER_URL,
            parsedRoomID
        )

    if not ok then

        networkLog("error", "Join connection failed", tostring(connectError))

        setError(
            connectError
        )

        network.mode =
            "offline"

        network.playerID =
            nil

        return false
    end

    handshakeStartTime =
        socket.gettime()

    network.roomID =
        parsedRoomID

    networkLog("info", "Join connection initialized", "room=" .. tostring(parsedRoomID))

    return true
end

-- ネットワークを更新する
function network.update()
    if network.peer then
        receivePackets()
    end

    if network.peer
        and not network.connected then

        local now =
            socket.gettime()

        if connectionStartTime > 0
            and now -
                connectionStartTime >=
                network.connectTimeout +
                network.handshakeTimeout then

            setError(
                "接続タイムアウト"
            )

            emit(
                "disconnect",
                "接続タイムアウト"
            )

            network.close(false)

            return
        end
    end

    if not network.connected then
        return
    end

    local now =
        socket.gettime()

    if pendingPing then

        local start =
            pingTimes[pendingPing]

        if start
            and now - start >=
            network.pingTimeout then

            pingTimes[pendingPing] =
                nil

            pendingPing = nil

            setError(
                "Pingタイムアウト"
            )

            emit(
                "disconnect",
                "Pingタイムアウト"
            )

            network.close(false)

            return
        end

    elseif now -
        network.lastPingTime >=
        network.pingInterval then

        local id =
            randomString(8)

        pendingPing = id

        pingTimes[id] =
            now

        network.lastPingTime =
            now

        local ok, err =
            sendRawFrame(
                id,
                9
            )

        if not ok then

            pingTimes[id] =
                nil

            pendingPing = nil

            setError(err)

            emit(
                "disconnect",
                "Ping送信失敗"
            )

            network.close(false)

            return
        end
    end
end

-- 接続を閉じる
function network.close(sendDisconnect)
    if sendDisconnect == nil then
        sendDisconnect = true
    end

    if closing then
        return
    end

    closing = true

    if sendDisconnect
        and network.peer then

        pcall(function()

            sendRawFrame(
                "DISCONNECT",
                1
            )

            sendRawFrame(
                "",
                8
            )

        end)
    end

    if network.peer then

        pcall(function()
            network.peer:close()
        end)

    end

    network.peer = nil

    network.connected = false

    network.remotePlayerID = nil
    network.roomID = nil
    resetPartyPlayers()

    pendingPing = nil
    pingTimes = {}

    receiveBuffer = ""

    fragmentedOpcode = nil
    fragmentedPayload = {}

    network.ping = 0
    network.lastPingTime = 0

    connectionStartTime = 0
    handshakeStartTime = 0

    network.mode = "offline"

    wsHost = nil
    wsPort = nil
    wsPath = nil
    wsSecure = false

    closing = false
end

-- 接続状態を取得する
function network.isConnected()
    return network.connected
end

-- Pingを取得する
function network.getPing()
    return math.floor(
        network.ping + 0.5
    )
end

-- エラーを取得する
function network.getError()
    return network.lastError
end

-- 自分のPlayerIDを取得する
function network.getPlayerID()
    return network.playerID
end

-- 相手のPlayerIDを取得する
function network.getRemotePlayerID()
    return network.remotePlayerID
end

-- 現在のパーティー人数を取得する
function network.getPartyCount()
    local count = 0

    for _ in pairs(network.partyPlayers) do
        count = count + 1
    end

    return count
end

-- 参加者ID一覧を取得する
function network.getPartyPlayers()
    local players = {}

    for playerID in pairs(network.partyPlayers) do
        players[#players + 1] = playerID
    end

    table.sort(players)
    return players
end

-- 現在のパーティー人数を取得する（別名）
function network.getPlayerCount()
    return network.getPartyCount()
end

-- 現在のモードを取得する
function network.getMode()
    return network.mode
end

-- RoomIDを取得する
function network.getRoomID()
    return network.roomID
end

return network
