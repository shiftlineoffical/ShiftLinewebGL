--[[
linedirections = 判定ラインの向き
1=下(初期値)
2=左
3=上
4=右

notegravity = ノーツの流れてくる向き
1=上から下(初期値)
2=右から左
3=下から上
4=左から右
5=中央から下
6=中央から左
7=中央から上
8=中央から右


]]

local play = {}
local log = require "log"
local i18n = require "i18n"
local audiocache = require "audiocache"
local notemove = require "notemove"
local JSON = require "JSON"
local ui = require("lib.ui")
local story = require "storyselecter"

local sflPlayerOperations = {
    "openSfl",
    "openAudio",
    "openFolder",
    "setDifficulty",
    "play",
    "pause",
    "reset",
    "reload",
    "toggleAuto",
    "setOffset",
    "updateMeasureInfo"
}

play.sflPlayerOperations = sflPlayerOperations
play.sflPlayer = {
    state = {
        loadedSflText = "",
        loadedSflFile = nil,
        loadedAudioFile = nil,
        loadedFolderFiles = {},
        selectedDifficulty = "easy",
        autoPlay = false,
        offsetMs = 0,
        measureInfo = "小節: 1",
        status = "SFL未読込"
    }
}

local function normalizeSflPlayerDifficulty(diff)
    if type(diff) ~= "string" then
        return "easy"
    end
    local key = string.lower(diff)
    if key == "easy" or key == "normal" or key == "hard" or key == "extra" or key == "custom" then
        return key
    end
    return "easy"
end

local function clampSflPlayerOffset(value)
    local num = tonumber(value) or 0
    return num
end

function play.sflPlayer.setStatus(text)
    if type(text) == "string" then
        play.sflPlayer.state.status = text
    end
    return play.sflPlayer.state.status
end

function play.sflPlayer.setDifficulty(diff)
    play.sflPlayer.state.selectedDifficulty = normalizeSflPlayerDifficulty(diff)
    return play.sflPlayer.state.selectedDifficulty
end

function play.sflPlayer.setOffset(value)
    play.sflPlayer.state.offsetMs = clampSflPlayerOffset(value)
    return play.sflPlayer.state.offsetMs
end

function play.sflPlayer.setMeasureInfo(value)
    play.sflPlayer.state.measureInfo = tostring(value or "小節: 1")
    return play.sflPlayer.state.measureInfo
end

function play.sflPlayer.toggleAuto()
    play.sflPlayer.state.autoPlay = not play.sflPlayer.state.autoPlay
    return play.sflPlayer.state.autoPlay
end

function play.sflPlayer.openSfl(file)
    if file == nil then
        return false
    end
    play.sflPlayer.state.loadedSflFile = file
    if type(file) == "string" then
        play.sflPlayer.state.loadedSflText = file
    elseif type(file) == "table" and type(file.text) == "function" then
        local ok, text = pcall(file.text, file)
        if ok and type(text) == "string" then
            play.sflPlayer.state.loadedSflText = text
        end
    end
    play.sflPlayer.state.status = "SFL読込完了"
    return true
end

function play.sflPlayer.openAudio(file)
    if file == nil then
        return false
    end
    play.sflPlayer.state.loadedAudioFile = file
    play.sflPlayer.state.status = "音源: " .. tostring(file.name or file)
    return true
end

function play.sflPlayer.openFolder(files)
    if type(files) ~= "table" then
        return false
    end
    play.sflPlayer.state.loadedFolderFiles = files
    return true
end

function play.sflPlayer.play()
    play.sflPlayer.state.status = "再生中"
    return true
end

function play.sflPlayer.pause()
    play.sflPlayer.state.status = "一時停止"
    return true
end

function play.sflPlayer.reset()
    play.sflPlayer.state.status = "リセット"
    return true
end

function play.sflPlayer.reload()
    play.sflPlayer.state.status = "再読み込み"
    return true
end

function play.sflPlayer.handleOperation(action, payload)
    local op = tostring(action or "")
    if op == "openSfl" then
        return play.sflPlayer.openSfl(payload)
    elseif op == "openAudio" then
        return play.sflPlayer.openAudio(payload)
    elseif op == "openFolder" then
        return play.sflPlayer.openFolder(payload)
    elseif op == "setDifficulty" then
        return play.sflPlayer.setDifficulty(payload)
    elseif op == "play" then
        return play.sflPlayer.play()
    elseif op == "pause" then
        return play.sflPlayer.pause()
    elseif op == "reset" then
        return play.sflPlayer.reset()
    elseif op == "reload" then
        return play.sflPlayer.reload()
    elseif op == "toggleAuto" then
        return play.sflPlayer.toggleAuto()
    elseif op == "setOffset" then
        return play.sflPlayer.setOffset(payload)
    elseif op == "updateMeasureInfo" then
        return play.sflPlayer.setMeasureInfo(payload)
    end
    return false
end

function play.handleSflPlayerQuery(rawQuery, handlers)
    local query = tostring(rawQuery or "")
    local params = {}
    if query ~= "" then
        local normalized = query:gsub("^%?", "")
        for pair in normalized:gmatch("[^&]+") do
            local key, value = pair:match("([^=]+)=?(.*)")
            if key then
                params[key] = value
            end
        end
    end

    local setCookie = handlers and handlers.setCookie or function() end
    local redirect = handlers and handlers.redirect or function() end

    if tostring(params.i) == "1" then
        setCookie("__test=e38f27bdef7926559f4b9a141071e413; max-age=21600; expires=Thu, 31-Dec-37 23:55:55 GMT; path=/")
        redirect("https://shiftline.gt.tc/sflplayer.html?i=2")
        return true
    end

    return false
end

local function getSafeFont(font)
    if font and type(font.getWidth) == "function" and type(font.getHeight) == "function" then
        return font
    end
    return love.graphics.getFont()
end


-- 難易度表示のフォーマット関数
local function formatDifficultyLevel(levelValue)
    if not levelValue or levelValue == "" or levelValue == "--" then
        return "--"
    end

    local text = tostring(levelValue)
    local integerPart, fractionPart = text:match("^%s*([%+%-]?%d+)%.(%d+)%s*$")
    if integerPart and fractionPart then
        local firstFractionDigit = tonumber(fractionPart:sub(1, 1)) or 0
        if firstFractionDigit >= 5 then
            return integerPart .. "+"
        end
        return integerPart
    end

    local integerOnly = text:match("^%s*([%+%-]?%d+)%s*$")
    if integerOnly then
        return integerOnly
    end

    local num = tonumber(text)
    if not num then
        return text
    end

    local base = math.floor(num)
    if (num - base) >= 0.5 then
        return tostring(base) .. "+"
    end
    return tostring(base)
end

notegravity=1
lanegravity=1
notexy={}



local collections = nil
local musicfiles = nil
local chartfiles = nil
local imagefiles = nil

local linedirections = 1
local bgmSource = nil
local musicload = 0
local songStarted = false
local playTimer = 0
local startDelay = 0
local jacketimg = nil

local esc=false

local musictime=0

local musictimer=0

local finished = false
local resultTransitioned = false
local resultTransitionHandler = nil

local paused = false
local resumeTimer = 0
local resumeDelay = 3
local waitingResume = false
local pauseMenuButtons = {}
local pauseMenuButtonFont = nil
local pauseMenuButtonImages = {}
local titlefont = nil
local artistfont = nil
local lefttitlefont = nil
local scoreFont = nil
local comboFont = nil
local labelFont = nil
local laneTransitionDuration = 0.14
local laneIntroDrawDuration = 0.85
local laneIntroBlinkDuration = 1.6

local laneAnim = {
    initialized = false,
    fromLines = nil,
    toLines = nil,
    currentLines = nil,
    toGravity = 1,
    elapsed = 0,
    duration = laneTransitionDuration
}

local judgeAnim = {
    initialized = false,
    fromLine = nil,
    toLine = nil,
    currentLine = nil,
    toGravity = 1,
    elapsed = 0,
    duration = laneTransitionDuration
}

local chartRuntime = {
    chart = nil,
    difficulty = "easy",
    notes = {},
    gravityEvents = {},
    nextGravityEventIndex = 1
}

local activeLaneCount = 6
local baseNoteSpeed = 1.0

noteApproachSeconds = 1.2
local noteFadeSeconds = 0.16
local longNoteFadeDuration = 0.3
local noteRadius = 12
local noteVisualScale = 0.82
local noteDrawQueue = {}
local noteRenderStateCache = {}
local longNotePairs = {}
local directionGlowDuration = 0.22
local directionGlowTimer = 0
laneInputMap = {
    z = 1,
    x = 2,
    c = 3,
    kp1 = 4,
    kp2 = 5,
    kp3 = 6,
    num1 = 4,
    num2 = 5,
    num3 = 6
}
gravity2LeftLaneInputMap = {
    z = 1,
    x = 2,
    c = 3,
    kp1 = 4,
    kp2 = 5,
    kp3 = 6,
    num1 = 4,
    num2 = 5,
    num3 = 6,
    ["1"] = 1,
    ["2"] = 2,
    ["3"] = 3,
    ["4"] = 4,
    ["5"] = 5,
    ["6"] = 6
}
gravity4TopLaneInputMap = {
    z = 1,
    x = 2,
    c = 3,
    kp1 = 4,
    kp2 = 5,
    kp3 = 6,
    num1 = 1,
    num2 = 2,
    num3 = 3,
    ["1"] = 4,
    ["2"] = 5,
    ["3"] = 6,
    ["4"] = 3,
    ["5"] = 2,
    ["6"] = 1
}

local function getEffectiveLaneRange(laneCount)
    local count = math.floor((tonumber(laneCount) or 6) + 0.5)
    if count < 1 then count = 1 end
    if count > 6 then count = 6 end
    local start = math.floor((6 - count) / 2) + 1
    return start, count
end

local function buildInputMapForLaneCount(baseMap, laneCount)
    local start, count = getEffectiveLaneRange(laneCount)
    local map = {}
    for token, lane in pairs(baseMap or {}) do
        local laneNum = tonumber(lane) or 1
        if laneNum >= start and laneNum < start + count then
            map[token] = laneNum - start + 1
        end
    end
    return map
end

laneInputTokens = {}
do
    local seen = {}
    for inputToken in pairs(laneInputMap) do
        if not seen[inputToken] then
            seen[inputToken] = true
            laneInputTokens[#laneInputTokens + 1] = inputToken
        end
    end
    for inputToken in pairs(gravity2LeftLaneInputMap) do
        if not seen[inputToken] then
            seen[inputToken] = true
            laneInputTokens[#laneInputTokens + 1] = inputToken
        end
    end
    for inputToken in pairs(gravity4TopLaneInputMap) do
        if not seen[inputToken] then
            seen[inputToken] = true
            laneInputTokens[#laneInputTokens + 1] = inputToken
        end
    end
end
local judgeWindowMs = {
    perfect = 80,
    good = 160,
    bad = 180
}
local timingAssistEnabled = false
local lastTimingDeltaMs = nil
local timingAssistRemaining = 0
local judgeCounts = {
    perfect = 0,
    good = 0,
    bad = 0,
    miss = 0
}
local longNoteEndGraceMs = 80

local combo = 0
local maxCombo = 0
local score = 0
local lanePressGlowDuration = 0.16
local lanePressGlowTimers = {0, 0, 0, 0, 0, 0}
local laneHoldStates = {false, false, false, false, false, false}
local hitEffects = {}
local hitEffectDuration = 0.2
local metaDisplayHoldSeconds = 2
local metaDisplayFadeSeconds = 1
local musicStartAfterMetaSeconds = 3
local metaDisplayTimer = 0
local metaDisplayShown = false
local metaDisplayFinished = false


local noteSE = {}
local seIndex = 1
local SE_COUNT = 6
local collectionsSummaryLogged = false
local bgmSoundDataPathCache = {}
local jacketImagePathCache = {}






local pushJudgeHitEffect

levelColors = {
    easy = {0.1, 1, 0.1},
    normal = {0.5, 0.5, 1},
    hard = {1, 1, 0},
    extra = {1, 0.1, 0.1},
    default = {0.5, 0.1, 0.5}
}

local function getMetaDisplayTotalSeconds()
    return math.max(0, metaDisplayHoldSeconds) + math.max(0.001, metaDisplayFadeSeconds)
end

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function easeOutCubic(t)
    local x = clamp01(t)
    local inv = 1 - x
    return 1 - inv * inv * inv
end

local function normalizeLaneGravity(v)
    local g = tonumber(v) or 1
    g = math.floor(g + 0.5)
    if g < 1 or g > 4 then
        g = 1
    end
    return g
end

local function normalizeNoteGravity(v)
    local g = tonumber(v) or 1
    g = math.floor(g + 0.5)
    if g < 1 or g > 8 then
        g = 1
    end
    return g
end

local function normalizeLaneIndex(v, fallback)
    local lane = tonumber(v)
    if lane == nil then
        if fallback ~= nil then
            return normalizeLaneIndex(fallback)
        end
        return 1
    end
    lane = math.floor(lane + 0.5)
    if lane < 1 then lane = 1 end
    if lane > activeLaneCount then lane = activeLaneCount end
    return lane
end

local function getGravityVisualLaneIndex(lane, gravity)
    local idx = normalizeLaneIndex(lane)
    local g = normalizeLaneGravity(gravity)
    if g == 4 then
        return activeLaneCount - idx + 1
    end
    return idx
end

local function isVerticalNoteDirection(noteDir)
    local g = normalizeNoteGravity(noteDir)
    return g == 1 or g == 3 or g == 5 or g == 7
end

local function noteGravityToLaneDirection(noteDir)
    local g = normalizeNoteGravity(noteDir)
    if g == 1 or g == 5 then
        return 1
    elseif g == 2 or g == 6 then
        return 2
    elseif g == 3 or g == 7 then
        return 3
    end
    return 4
end

local function isNoteGravityAlignedWithLane(noteDir, laneDir)
    return noteGravityToLaneDirection(noteDir) == normalizeLaneGravity(laneDir)
end

local function getNoteResolvedGravity(note, fallbackDir)
    if type(note) ~= "table" then
        return normalizeNoteGravity(fallbackDir or notegravity)
    end
    return normalizeNoteGravity(note.resolvedGravity or note.gravity or fallbackDir or notegravity)
end

local function isNoteJudgeDirectionAligned(note, laneDir)
    return isNoteGravityAlignedWithLane(getNoteResolvedGravity(note), laneDir)
end

local function normalizeConfiguredInputToken(token)
    if token == nil then
        return nil
    end

    if type(token) ~= "string" then
        token = tostring(token)
    end

    token = token:lower()
    if token == "" then
        return nil
    end
    if token == " " then
        return "space"
    end
    return token
end

local function getConfiguredLaneBinding(laneName)
    if settingsdata and settingsdata.keysettings and type(settingsdata.keysettings[laneName]) == "string" then
        local token = settingsdata.keysettings[laneName]
        if token ~= "" then
            return normalizeConfiguredInputToken(token)
        end
    end
    return nil
end

local function getConfiguredInputToken(actionName)
    if settingsdata and settingsdata.keysettings and type(settingsdata.keysettings[actionName]) == "string" then
        local token = settingsdata.keysettings[actionName]
        if token ~= "" then
            return normalizeConfiguredInputToken(token)
        end
    end
    return nil
end

local function resolveLaneInput(key, scancode)
    local laneBindings = {
        {name = "leftone", lane = 1},
        {name = "lefttwo", lane = 2},
        {name = "lefttree", lane = 3},
        {name = "rightone", lane = 4},
        {name = "righttwo", lane = 5},
        {name = "righttree", lane = 6}
    }

    local normalizedKey = normalizeConfiguredInputToken(key)
    local normalizedScancode = normalizeConfiguredInputToken(scancode)
    local laneDir = normalizeLaneGravity(lanegravity)
    local activeLaneInputMap = buildInputMapForLaneCount(laneInputMap, activeLaneCount)
    local activeGravity2LaneInputMap = buildInputMapForLaneCount(gravity2LeftLaneInputMap, activeLaneCount)
    local activeGravityLaneInputMap = buildInputMapForLaneCount(gravity4TopLaneInputMap, activeLaneCount)

    local function getMappedLane(map, token)
        if not map or not token then
            return nil
        end
        local lane = map[token]
        if lane == nil then
            return nil
        end
        return normalizeLaneIndex(lane)
    end

    for _, binding in ipairs(laneBindings) do
        local token = getConfiguredLaneBinding(binding.name)
        if token and (token == normalizedKey or (normalizedScancode and token == normalizedScancode)) then
            local startLane, laneCount = getEffectiveLaneRange(activeLaneCount)
            if binding.lane >= startLane and binding.lane < startLane + laneCount then
                local mappedLane = binding.lane - startLane + 1
                return normalizeLaneIndex(mappedLane)
            end
        end
    end

    local directionalMap = nil
    if laneDir == 2 then
        directionalMap = activeGravity2LaneInputMap
    elseif laneDir == 4 then
        directionalMap = activeGravityLaneInputMap
    end

    if directionalMap then
        local lane = getMappedLane(directionalMap, normalizedKey)
        if not lane and normalizedScancode then
            lane = getMappedLane(directionalMap, normalizedScancode)
        end
        if lane then
            return lane
        end
    end

    local lane = getMappedLane(activeLaneInputMap, normalizedKey)
    if not lane and normalizedScancode then
        lane = getMappedLane(activeLaneInputMap, normalizedScancode)
    end
    return lane
end

local function resetJudgeCounts()
    judgeCounts.perfect = 0
    judgeCounts.good = 0
    judgeCounts.bad = 0
    judgeCounts.miss = 0
    combo = 0
    maxCombo = 0
    score = 0
end

local function clearLaneInputStates()
    for lane = 1, activeLaneCount do
        laneHoldStates[lane] = false
        lanePressGlowTimers[lane] = 0
    end
end

local function setLaneHoldState(lane, held)
    local idx = normalizeLaneIndex(lane)
    laneHoldStates[idx] = held and true or false
end

local function isInputTokenDown(inputToken)
    if not inputToken or not love or not love.keyboard then
        return false
    end

    local keyboard = love.keyboard
    local okKey, keyDown = pcall(keyboard.isDown, inputToken)
    if okKey and keyDown then
        return true
    end

    if keyboard.isScancodeDown then
        local okScancode, scancodeDown = pcall(keyboard.isScancodeDown, inputToken)
        if okScancode and scancodeDown then
            return true
        end
    end

    return false
end

local function updateLaneHoldStatesFromKeyboard()
    for lane = 1, activeLaneCount do
        laneHoldStates[lane] = false
    end

    local tokens = {}
    local seen = {}
    local function addToken(token)
        if not token or token == "" then
            return
        end
        if not seen[token] then
            seen[token] = true
            tokens[#tokens + 1] = token
        end
    end

    local laneBindings = {"leftone", "lefttwo", "lefttree", "rightone", "righttwo", "righttree"}
    for _, laneName in ipairs(laneBindings) do
        addToken(getConfiguredLaneBinding(laneName))
    end

    for _, inputToken in ipairs(laneInputTokens) do
        addToken(inputToken)
    end

    for _, inputToken in ipairs(tokens) do
        if isInputTokenDown(inputToken) then
            local lane = resolveLaneInput(inputToken, inputToken)
            if lane then
                laneHoldStates[normalizeLaneIndex(lane)] = true
            end
        end
    end
end

local function triggerLanePressGlow(lane)
    local idx = normalizeLaneIndex(lane)
    lanePressGlowTimers[idx] = lanePressGlowDuration
end

local function getLanePressGlow(lane)
    local idx = normalizeLaneIndex(lane)
    if lanePressGlowDuration <= 0 then
        return 0
    end
    local pressGlow = clamp01((lanePressGlowTimers[idx] or 0) / lanePressGlowDuration)
    return pressGlow
end

local function updateLanePressGlowTimers(dt)
    local step = math.max(0, tonumber(dt) or 0)
    for lane = 1, activeLaneCount do
        lanePressGlowTimers[lane] = math.max(0, (lanePressGlowTimers[lane] or 0) - step)
    end
end

local function getJudgeEffectColor(result)
    if result == "perfect" then
        return 0.7, 0.98, 1.0
    elseif result == "good" then
        return 0.62, 1.0, 0.66
    elseif result == "bad" then
        return 1.0, 0.78, 0.46
    end
    return 1.0, 0.48, 0.48
end

local function updateHitEffects(dt)
    if not hitEffects or #hitEffects == 0 then
        return
    end

    local step = math.max(0, tonumber(dt) or 0)
    for i = #hitEffects, 1, -1 do
        local fx = hitEffects[i]
        fx.t = (fx.t or 0) + step
        if fx.t >= (fx.duration or hitEffectDuration) then
            table.remove(hitEffects, i)
        end
    end
end

local function markNoteJudged(note, result, deltaMs, songTime)
    if not note or note.judged then
        return
    end
    note.judged = true
    note.judge = result
    note.judgeDeltaMs = deltaMs
    note.judgedTime = songTime or 0
    note.hit = (result ~= "miss")
    judgeCounts[result] = (judgeCounts[result] or 0) + 1

    if timingAssistEnabled and tonumber(deltaMs) then
        lastTimingDeltaMs = tonumber(deltaMs)
        timingAssistRemaining = 1.25
    end
    
    -- スコアとコンボを更新
    if result == "perfect" then
        score = score + 100
        combo = combo + 1
        if combo > maxCombo then
            maxCombo = combo
        end
    elseif result == "good" then
        score = score + 50
        combo = combo + 1
        if combo > maxCombo then
            maxCombo = combo
        end
    elseif result == "bad" then
        score = score + 10
        combo = 0
    else  -- miss
        combo = 0
    end
end

local function getLongNoteEndGraceSeconds()
    return math.max(0, tonumber(longNoteEndGraceMs) or 0) / 1000
end

local function shouldProcessLongHoldLogic()
    if paused or waitingResume or finished then
        return false
    end

    if not bgmSource or musicload ~= 1 then
        return false
    end

    return songStarted == true
end

local function breakLongHold(pair)
    if not pair or pair.holdBroken then
        return
    end
    pair.holdBroken = true
    combo = 0
end

local function completeLongHoldWithinGrace(pair, songTime)
    if not pair then
        return false
    end

    local endNote = pair.endNote
    if not endNote or endNote.judged then
        return false
    end

    local endTime = tonumber(endNote.timeSec) or 0
    local now = tonumber(songTime) or endTime
    local graceSec = getLongNoteEndGraceSeconds()
    if now < (endTime - graceSec) or now > (endTime + graceSec) then
        return false
    end

    markNoteJudged(endNote, "perfect", (now - endTime) * 1000, now)
    return true
end

local function findJudgeTargetNote(lane, songTime)
    local notes = chartRuntime.notes
    if not notes or #notes == 0 then
        return nil, nil
    end

    local badMs = judgeWindowMs.bad
    local badSec = badMs / 1000
    local laneDir = normalizeLaneGravity(lanegravity)
    local bestNote = nil
    local bestDeltaMs = nil
    local bestAbsMs = nil

    for _, note in ipairs(notes) do
        if not note.judged
            and not note.isLongEnd
            and not note.isLongStart
            and normalizeLaneIndex(note.lane) == lane
            and isNoteJudgeDirectionAligned(note, laneDir) then
            local nt = tonumber(note.timeSec) or 0
            local deltaMs = (songTime - nt) * 1000
            local absMs = math.abs(deltaMs)
            if absMs <= badMs then
                if not bestAbsMs or absMs < bestAbsMs then
                    bestNote = note
                    bestDeltaMs = deltaMs
                    bestAbsMs = absMs
                end
            end

            if (nt - songTime) > badSec then
                break
            end
        end
    end

    return bestNote, bestDeltaMs
end

local function hasBlockingPriorNormalNoteForLong(laneIndex, startTime, songTime, badSec)
    local notes = chartRuntime.notes
    if not notes or #notes == 0 then
        return false
    end

    local laneDir = normalizeLaneGravity(lanegravity)
    for _, note in ipairs(notes) do
        local nt = tonumber(note.timeSec) or 0
        if nt > startTime then
            break
        end

        if not note.judged
            and not note.isLongStart
            and not note.isLongEnd
            and normalizeLaneIndex(note.lane) == laneIndex
            and isNoteJudgeDirectionAligned(note, laneDir) then
            -- 先行ノーマルがまだ判定可能範囲にある間はロング開始を優先させない
            if songTime <= (nt + badSec) then
                return true
            end
        end
    end

    return false
end

local function findJudgeTargetLongBand(lane, songTime)
    if not longNotePairs or #longNotePairs == 0 then
        return nil, nil
    end

    local laneIndex = normalizeLaneIndex(lane)
    local badMs = judgeWindowMs.bad
    local badSec = badMs / 1000
    local bestPair = nil
    local bestDeltaMs = nil
    local bestScore = nil

    for _, pair in ipairs(longNotePairs) do
        local startNote = pair.startNote
        local endNote = pair.endNote
        if startNote and endNote and not startNote.judged and not endNote.judged then
            if normalizeLaneIndex(startNote.lane) == laneIndex
                and isNoteJudgeDirectionAligned(startNote, lanegravity) then
                local startTime = tonumber(startNote.timeSec) or 0
                local endTime = tonumber(endNote.timeSec) or startTime
                if endTime < startTime then
                    endTime = startTime
                end

                local blockedByPriorNormal = hasBlockingPriorNormalNoteForLong(
                    laneIndex,
                    startTime,
                    songTime,
                    badSec
                )

                if not blockedByPriorNormal and songTime >= (startTime - badSec) and songTime <= endTime then
                    local deltaMs = (songTime - startTime) * 1000
                    local score = math.abs(deltaMs)
                    if deltaMs > badMs then
                        score = badMs + deltaMs
                    end

                    if not bestScore or score < bestScore then
                        bestPair = pair
                        bestDeltaMs = deltaMs
                        bestScore = score
                    end
                end
            end
        end
    end

    return bestPair, bestDeltaMs
end

local function handleLaneInputJudge(lane, songTime)
    local longPair, longDeltaMs = findJudgeTargetLongBand(lane, songTime)
    local note, deltaMs = findJudgeTargetNote(lane, songTime)

    local useLongBand = false
    if longPair then
        if not note then
            useLongBand = true
        else
            local longScore = math.abs(longDeltaMs or 0)
            if longScore > judgeWindowMs.bad then
                longScore = longScore + judgeWindowMs.bad
            end
            local noteScore = math.abs(deltaMs or 0)
            useLongBand = longScore <= noteScore
        end
    end

    if useLongBand then
        local startNote = longPair.startNote
        if startNote then
            local result = "bad"
            local absMs = math.abs(longDeltaMs or 0)
            if absMs <= judgeWindowMs.perfect then
                result = "perfect"
            elseif absMs <= judgeWindowMs.good then
                result = "good"
            elseif absMs <= judgeWindowMs.bad then
                result = "bad"
            else
                result = "bad"
            end

            markNoteJudged(startNote, result, longDeltaMs, songTime)
            longPair.holdBroken = false
            if pushJudgeHitEffect then
                pushJudgeHitEffect(startNote.lane, result, startNote)
            end
            return true
        end
    end

    if not note then
        return false
    end

    local result = "bad"
    local absMs = math.abs(deltaMs or 0)
    if absMs <= judgeWindowMs.perfect then
        result = "perfect"
        markNoteJudged(note, result, deltaMs, songTime)
    elseif absMs <= judgeWindowMs.good then
        result = "good"
        markNoteJudged(note, result, deltaMs, songTime)
    else
        markNoteJudged(note, result, deltaMs, songTime)
    end

    if pushJudgeHitEffect then
        pushJudgeHitEffect(note.lane, result, note)
    end
    return true
end

local function updateMissJudgements(songTime)
    local notes = chartRuntime.notes
    if not notes or #notes == 0 then
        return
    end

    local missSec = judgeWindowMs.bad / 1000
    for _, note in ipairs(notes) do
        if not note.judged then
            if note.isLongStart or note.isLongEnd then
                goto continue
            end
            local nt = tonumber(note.timeSec) or 0
            local lateSec = songTime - nt
            if lateSec > missSec then
                markNoteJudged(note, "miss", lateSec * 1000, songTime)
            else
                break
            end
        end
        ::continue::
    end

    if not longNotePairs or #longNotePairs == 0 then
        return
    end

    for _, pair in ipairs(longNotePairs) do
        local startNote = pair.startNote
        local endNote = pair.endNote
        if startNote and endNote and not endNote.judged then
            local endTime = tonumber(endNote.timeSec) or 0
            local lateEndSec = songTime - endTime
            if lateEndSec > missSec then
                if not startNote.judged then
                    local startTime = tonumber(startNote.timeSec) or 0
                    markNoteJudged(startNote, "miss", (songTime - startTime) * 1000, songTime)
                end
                markNoteJudged(endNote, "miss", lateEndSec * 1000, songTime)
            end
        end
    end
end

local function updateLongHoldJudgements(songTime)
    if not shouldProcessLongHoldLogic() then
        return
    end

    if not longNotePairs or #longNotePairs == 0 then
        return
    end

    local graceSec = getLongNoteEndGraceSeconds()

    for _, pair in ipairs(longNotePairs) do
        local startNote = pair.startNote
        local endNote = pair.endNote
        if startNote and endNote and startNote.judged and startNote.hit and not endNote.judged then
            local lane = normalizeLaneIndex(startNote.lane)
            local endTime = tonumber(endNote.timeSec) or 0
            local graceStartTime = endTime - graceSec
            local held = laneHoldStates[lane] == true
            -- ロングノーツの終了ノートの gravity で判定する（複数の gravity イベント区間に対応）
            local directionAligned = isNoteJudgeDirectionAligned(endNote, lanegravity)

            if pair.holdBroken then
                if songTime > (endTime + graceSec) then
                    markNoteJudged(endNote, "miss", (songTime - endTime) * 1000, songTime)
                end
            elseif songTime < graceStartTime then
                if not held or not directionAligned then
                    breakLongHold(pair)
                end
            elseif songTime < endTime then
                if not held or not directionAligned then
                    completeLongHoldWithinGrace(pair, songTime)
                end
            elseif held and directionAligned then
                markNoteJudged(endNote, "perfect", (songTime - endTime) * 1000, songTime)
            elseif songTime <= (endTime + graceSec) then
                completeLongHoldWithinGrace(pair, songTime)
            else
                breakLongHold(pair)
                markNoteJudged(endNote, "miss", (songTime - endTime) * 1000, songTime)
            end
        end
    end
end

local function registerLongHoldRelease(lane, songTime)
    if not shouldProcessLongHoldLogic() then
        return
    end

    if not longNotePairs or #longNotePairs == 0 then
        return
    end

    local laneIndex = normalizeLaneIndex(lane)
    local now = tonumber(songTime)
    local graceSec = getLongNoteEndGraceSeconds()
    for _, pair in ipairs(longNotePairs) do
        local startNote = pair.startNote
        local endNote = pair.endNote
        if startNote and endNote and startNote.judged and startNote.hit and not endNote.judged then
            if normalizeLaneIndex(startNote.lane) == laneIndex then
                if now then
                    local endTime = tonumber(endNote.timeSec) or 0
                    if now >= (endTime - graceSec) and completeLongHoldWithinGrace(pair, now) then
                    elseif now < endTime then
                        breakLongHold(pair)
                    elseif now > (endTime + graceSec) then
                        breakLongHold(pair)
                        markNoteJudged(endNote, "miss", (now - endTime) * 1000, now)
                    end
                end
            end
        end
    end
end

local function isLongStartType(noteType)
    return (tonumber(noteType) or 0) == 2
end

local function isLongEndType(noteType, preferType4Only)
    local t = tonumber(noteType) or 0
    if preferType4Only then
        return t == 4
    end
    -- 旧譜面互換: ロング終点が3で保存されている場合にも対応
    return t == 4 or t == 3
end

local function buildLongNotePairs(notes)
    local pairs = {}
    if type(notes) ~= "table" or #notes == 0 then
        return pairs
    end

    for _, note in ipairs(notes) do
        note.isLongStart = false
        note.isLongEnd = false
    end

    local hasType4End = false
    for _, note in ipairs(notes) do
        if (tonumber(note.type) or 0) == 4 then
            hasType4End = true
            break
        end
    end

    local pendingByLane = {}
    for lane = 1, 6 do
        pendingByLane[lane] = {head = 1, items = {}}
    end

    for _, note in ipairs(notes) do
        local lane = normalizeLaneIndex(note.lane)
        local q = pendingByLane[lane]
        if isLongStartType(note.type) then
            local items = q.items
            items[#items + 1] = note
        elseif isLongEndType(note.type, hasType4End) then
            local head = q.head
            local items = q.items
            if head <= #items then
                local startPairNote = items[head]
                q.head = head + 1
                startPairNote.isLongStart = true
                note.isLongEnd = true
                pairs[#pairs + 1] = {
                    startNote = startPairNote,
                    endNote = note,
                    holdBroken = false
                }
            end
        end
    end

    return pairs
end

local function getDisplaySize()
    local w = tonumber(displayx) or love.graphics.getWidth()
    local h = tonumber(displayy) or love.graphics.getHeight()
    return w, h
end

local function buildJudgeLine(gravity)
    local g = normalizeLaneGravity(gravity)
    local w, h = getDisplaySize()
    local margin = math.min(w, h) * 0.15

    if g == 1 then
        local y = h - margin
        return {x1 = 0, y1 = y, x2 = w, y2 = y}
    elseif g == 3 then
        local y = margin
        return {x1 = 0, y1 = y, x2 = w, y2 = y}
    elseif g == 2 then
        local x = margin
        return {x1 = x, y1 = 0, x2 = x, y2 = h}
    else
        local x = w - margin
        return {x1 = x, y1 = 0, x2 = x, y2 = h}
    end
end

local function triggerDirectionGlow()
    directionGlowTimer = directionGlowDuration
end

local function getUpcomingGravityWarning(songTime)
    local events = chartRuntime.gravityEvents
    if not events or #events == 0 then
        return nil
    end

    local currentSongTime = tonumber(songTime) or tonumber(musictime) or 0
    local bpm = tonumber(chartRuntime.chart and chartRuntime.chart.meta and chartRuntime.chart.meta.bpm) or 120
    if bpm <= 0 then
        bpm = 120
    end
    local leadSec = 240 / bpm
    local idx = chartRuntime.nextGravityEventIndex or 1

    while idx <= #events do
        local event = events[idx]
        local eventTime = tonumber(event and event.timeSec) or 0
        if eventTime <= currentSongTime then
            idx = idx + 1
        else
            local remaining = eventTime - currentSongTime
            if remaining > leadSec then
                return nil
            end
            return {
                laneGravity = noteGravityToLaneDirection(event.gravity),
                timeLeft = remaining,
                leadSec = leadSec
            }
        end
    end

    return nil
end

local function drawUpcomingGravityWarning(songTime)
    local warning = getUpcomingGravityWarning(songTime)
    if not warning then
        return
    end

    local line = buildJudgeLine(warning.laneGravity)
    if not line then
        return
    end

    local remaining = math.max(0, warning.timeLeft)
    local progress = 1 - (remaining / math.max(0.001, warning.leadSec))
    local pulse = 0.5 + 0.5 * math.sin((songTime or 0) * 18 + warning.laneGravity * 2.0)
    local alpha = clamp01(0.12 + 0.68 * pulse * (0.25 + 0.75 * (1 - progress)))

    love.graphics.setLineWidth(3)
    love.graphics.setColor(1.0, 0.7, 0.2, alpha)
    love.graphics.line(line.x1, line.y1, line.x2, line.y2)
    love.graphics.setLineWidth(1)
end

local function getDirectionGlow()
    if directionGlowDuration <= 0 then
        return 0
    end
    return clamp01(directionGlowTimer / directionGlowDuration)
end

local function pointInRect(px, py, rect)
    if not rect then
        return false
    end
    return px >= rect.x and px <= (rect.x + rect.w)
        and py >= rect.y and py <= (rect.y + rect.h)
end

local function getPauseMenuPanelRect()
    local w, h = getDisplaySize()
    local panelW = math.min(w * 0.54, 560)
    local panelH = math.max(h * 0.56, 360)
    return {
        x = (w - panelW) * 0.5,
        y = (h - panelH) * 0.5,
        w = panelW,
        h = panelH,
        cut = math.min(panelW, panelH) * 0.08
    }
end

local function buildPauseMenuButtons()
    local w, h = getDisplaySize()
    local lineY = h * 0.58
    local iconH = math.max(32, math.min(w, h) * 0.075)
    local gap = math.max(12, math.min(w * 0.025, 42))

    local buttons = {
        {label = i18n.t("resume"), action = "resume", shape = "circle", image = pauseMenuButtonImages.resume},
        {label = i18n.t("restart"), action = "restart", shape = "diamond", image = pauseMenuButtonImages.restart},
        {label = i18n.t("exit"), action = "exit", shape = "square", image = pauseMenuButtonImages.exit}
    }

    local totalW = 0
    for _, b in ipairs(buttons) do
        local bw = math.max(64, math.min(w * 0.18, iconH * 1.45))
        local bh = iconH
        if b.image then
            local iw = math.max(1, b.image:getWidth())
            local ih = math.max(1, b.image:getHeight())
            local minH = math.max(24, iconH * 0.62)
            local maxH = iconH
            local maxW = math.min(w * 0.2, 220)
            local scale = math.min(maxW / iw, maxH / ih)

            -- 最低高さは確保しつつ、縦横比は崩さない
            if ih * scale < minH then
                scale = minH / ih
                if iw * scale > maxW then
                    scale = maxW / iw
                end
            end

            bw = iw * scale
            bh = ih * scale
        end

        b.w = bw
        b.h = bh
        b.size = math.max(bw, bh) * 0.5
        b.useImage = b.image ~= nil
        totalW = totalW + bw
    end

    totalW = totalW + gap * math.max(0, #buttons - 1)
    local cursorX = (w - totalW) * 0.5
    for _, b in ipairs(buttons) do
        b.x = cursorX
        b.y = lineY - b.h * 0.5
        b.cx = b.x + b.w * 0.5
        b.cy = lineY
        cursorX = cursorX + b.w + gap
    end

    return buttons
end

local function pointInPauseShape(px, py, buttonData)
    if not buttonData then
        return false
    end
    if buttonData.useImage then
        return pointInRect(px, py, buttonData)
    end

    local cx = tonumber(buttonData.cx) or ((buttonData.x or 0) + (buttonData.w or 0) * 0.5)
    local cy = tonumber(buttonData.cy) or ((buttonData.y or 0) + (buttonData.h or 0) * 0.5)
    local size = math.max(1, tonumber(buttonData.size) or math.min((buttonData.w or 0), (buttonData.h or 0)) * 0.5)
    local dx = px - cx
    local dy = py - cy

    if buttonData.shape == "circle" then
        return (dx * dx + dy * dy) <= (size * size)
    elseif buttonData.shape == "diamond" then
        return (math.abs(dx) + math.abs(dy)) <= size
    elseif buttonData.shape == "square" then
        return math.abs(dx) <= size and math.abs(dy) <= size
    end

    return pointInRect(px, py, buttonData)
end

local function drawPauseShape(mode, shape, cx, cy, size)
    local s = math.max(1, tonumber(size) or 24)
    if shape == "circle" then
        love.graphics.circle(mode, cx, cy, s)
        return
    end
    if shape == "diamond" then
        love.graphics.polygon(mode, cx, cy - s, cx + s, cy, cx, cy + s, cx - s, cy)
        return
    end
    love.graphics.rectangle(mode, cx - s, cy - s, s * 2, s * 2)
end

local function loadPauseMenuButtonImages()
    if next(pauseMenuButtonImages) ~= nil then
        return
    end

    local paths = {
        resume = "img/Resure.png",
        restart = "img/Restart.png",
        exit = "img/Exit.png"
    }

    pauseMenuButtonImages = {}
    for action, path in pairs(paths) do
        local okImage, imageObj = pcall(love.graphics.newImage, path)
        if okImage and imageObj then
            pauseMenuButtonImages[action] = imageObj
        else
            pauseMenuButtonImages[action] = nil
            log.warn("Pause button image load failed: " .. tostring(path))
        end
    end
end

local function ensurePlayFontsLoaded()
    if not titlefont then
        titlefont = ui.newFont("lib/data/fonts/NotoSansJP-Regular.ttf", 60)
    end
    if not artistfont then
        artistfont = ui.newFont("lib/data/fonts/NotoSansJP-ExtraLight.ttf", 40)
    end
    if not lefttitlefont then
        lefttitlefont = ui.newFont("lib/data/fonts/NotoSansJP-Regular.ttf", 30)
    end
    if not pauseMenuButtonFont then
        pauseMenuButtonFont = ui.newFont("lib/data/fonts/NotoSansJP-Regular.ttf", 32)
    end
    if not scoreFont then
        scoreFont = ui.newFont("lib/data/fonts/NotoSansJP-Regular.ttf", 40)
    end
    if not comboFont then
        comboFont = ui.newFont("lib/data/fonts/NotoSansJP-Regular.ttf", 60)
    end
    if not labelFont then
        labelFont = ui.newFont("lib/data/fonts/NotoSansJP-Regular.ttf", 30)
    end
end

local function ensureNoteSePoolLoaded()
    for i = 1, SE_COUNT do
        if not noteSE[i] then
            local ok, source = pcall(love.audio.newSource, "lib/data/BGM/note.ogg", "static")
            if ok and source then
                noteSE[i] = source
            else
                noteSE[i] = nil
                log.warn("Warning: Failed to load note SE source.")
            end
        end
        local s = noteSE[i]
        if s and s.stop then
            pcall(s.stop, s)
        end
    end
    seIndex = 1
end

local function resumeFromPauseMenu()
    if not paused then
        return
    end

    if not waitingResume then
        waitingResume = true
        resumeTimer = 0
    else
        waitingResume = false
        resumeTimer = 0
    end
end

local function restartFromPauseMenu()
    waitingResume = false
    resumeTimer = 0
    paused = false
    if bgmSource and bgmSource.stop then
        bgmSource:stop()
    end
    play.load()
end

function play.restart()
    if not bgmSource then
        return false
    end

    restartFromPauseMenu()
    return true
end

local function exitFromPauseMenu()
    waitingResume = false
    resumeTimer = 0
    paused = false
    if bgmSource and bgmSource.stop then
        bgmSource:stop()
    end

    if type(changeProgram) == "function" then
        changeProgram(3)
    else
    end
end

local function buildLaneLines(gravity)
    local g = normalizeLaneGravity(gravity)
    local w, h = getDisplaySize()
    local lines = {}
    if g == 1 or g == 3 then
        for i = 1, activeLaneCount - 1 do
            local x = w / activeLaneCount * i
            lines[i] = {x1 = x, y1 = 0, x2 = x, y2 = h}
        end
    else
        for i = 1, activeLaneCount - 1 do
            local y = h / activeLaneCount * i
            lines[i] = {x1 = 0, y1 = y, x2 = w, y2 = y}
        end
    end
    return lines
end

local function cloneLine(line)
    if not line then
        return nil
    end
    return {x1 = line.x1, y1 = line.y1, x2 = line.x2, y2 = line.y2}
end

local function interpolateLine(fromLine, toLine, t)
    local a = fromLine or toLine
    local b = toLine or fromLine
    if not a or not b then
        return nil
    end
    return {
        x1 = a.x1 + (b.x1 - a.x1) * t,
        y1 = a.y1 + (b.y1 - a.y1) * t,
        x2 = a.x2 + (b.x2 - a.x2) * t,
        y2 = a.y2 + (b.y2 - a.y2) * t
    }
end

local function cloneLaneLines(lines)
    local copied = {}
    if not lines then
        return copied
    end
    for i = 1, #lines do
        local l = lines[i]
        copied[i] = {x1 = l.x1, y1 = l.y1, x2 = l.x2, y2 = l.y2}
    end
    return copied
end

local function interpolateLaneLines(fromLines, toLines, t)
    local result = {}
    local maxCount = math.max(#(fromLines or {}), #(toLines or {}))
    for i = 1, maxCount do
        local a = (fromLines and fromLines[i]) or (toLines and toLines[i])
        local b = (toLines and toLines[i]) or (fromLines and fromLines[i])
        if a and b then
            result[i] = {
                x1 = a.x1 + (b.x1 - a.x1) * t,
                y1 = a.y1 + (b.y1 - a.y1) * t,
                x2 = a.x2 + (b.x2 - a.x2) * t,
                y2 = a.y2 + (b.y2 - a.y2) * t
            }
        end
    end
    return result
end

local function updateLaneGravityAnimation(dt)
    local targetGravity = normalizeLaneGravity(lanegravity)

    if not laneAnim.initialized then
        laneAnim.toGravity = targetGravity
        laneAnim.toLines = buildLaneLines(targetGravity)
        laneAnim.fromLines = laneAnim.toLines
        laneAnim.currentLines = laneAnim.toLines
        laneAnim.elapsed = laneAnim.duration
        laneAnim.initialized = true
    end

    if not judgeAnim.initialized then
        judgeAnim.toGravity = targetGravity
        judgeAnim.toLine = buildJudgeLine(targetGravity)
        judgeAnim.fromLine = judgeAnim.toLine
        judgeAnim.currentLine = judgeAnim.toLine
        judgeAnim.elapsed = judgeAnim.duration
        judgeAnim.initialized = true
    end

    if targetGravity ~= laneAnim.toGravity then
        laneAnim.fromLines = cloneLaneLines(laneAnim.currentLines)
        laneAnim.toGravity = targetGravity
        laneAnim.toLines = buildLaneLines(targetGravity)
        laneAnim.elapsed = 0

        judgeAnim.fromLine = cloneLine(judgeAnim.currentLine)
        judgeAnim.toGravity = targetGravity
        judgeAnim.toLine = buildJudgeLine(targetGravity)
        judgeAnim.elapsed = 0
        triggerDirectionGlow()
    end

    if laneAnim.elapsed < laneAnim.duration then
        laneAnim.elapsed = math.min(laneAnim.elapsed + dt, laneAnim.duration)
        local t = easeOutCubic(laneAnim.elapsed / laneAnim.duration)
        laneAnim.currentLines = interpolateLaneLines(laneAnim.fromLines, laneAnim.toLines, t)
    else
        laneAnim.currentLines = laneAnim.toLines
    end

    if judgeAnim.elapsed < judgeAnim.duration then
        judgeAnim.elapsed = math.min(judgeAnim.elapsed + dt, judgeAnim.duration)
        local t = easeOutCubic(judgeAnim.elapsed / judgeAnim.duration)
        judgeAnim.currentLine = interpolateLine(judgeAnim.fromLine, judgeAnim.toLine, t)
    else
        judgeAnim.currentLine = judgeAnim.toLine
    end
end

local function drawLaneLineProgress(line, drawProgress, reverseDirection)
    local p = clamp01(drawProgress)
    if p <= 0 then
        return
    end

    local x1, y1, x2, y2 = line.x1, line.y1, line.x2, line.y2
    if reverseDirection then
        local sx = x2 + (x1 - x2) * p
        local sy = y2 + (y1 - y2) * p
        love.graphics.line(sx, sy, x2, y2)
    else
        local ex = x1 + (x2 - x1) * p
        local ey = y1 + (y2 - y1) * p
        love.graphics.line(x1, y1, ex, ey)
    end
end

local function normalizeDifficultyKey(diff)
    if type(diff) ~= "string" then
        return "easy"
    end
    local key = string.lower(diff)
    if key == "easy" or key == "normal" or key == "hard" or key == "extra" or key == "custom" then
        return key
    end
    return "easy"
end

local function loadChartTable(entry, forceReload)
    if type(entry) == "table" and forceReload then
        entry._parsedChartTable = nil
    end

    if type(entry) == "table" and entry._parsedChartTable ~= nil and not forceReload then
        return entry._parsedChartTable or nil
    end

    if type(entry) ~= "table" or type(entry.data) ~= "string" then
        return nil
    end
    local chunk, err = load(entry.data, entry.name or "chart", "t")
    if not chunk then
        log.warn("Chart load failed: " .. tostring(err))
        return nil
    end
    local ok, chart = pcall(chunk)
    if not ok or type(chart) ~= "table" then
        log.warn("Chart parse failed: " .. tostring(chart))
        return nil
    end
    entry._parsedChartTable = chart
    return chart
end

local function pickNotesByDifficulty(chart, diffKey)
    local selected = normalizeDifficultyKey(diffKey)
    local notesByDiff = chart and chart.notes
    if type(notesByDiff) ~= "table" then
        return {}, selected
    end

    local selectedNotes = notesByDiff[selected]
    if type(selectedNotes) == "table" and #selectedNotes > 0 then
        return selectedNotes, selected
    end

    local fallbackDiffs = {"easy", "normal", "hard", "extra", "custom"}
    for _, diff in ipairs(fallbackDiffs) do
        local list = notesByDiff[diff]
        if type(list) == "table" and #list > 0 then
            return list, diff
        end
    end

    return {}, selected
end

local function buildRuntimeNotesFromUnifiedList(sourceNotes)
    local runtimeNotes = {}
    if type(sourceNotes) ~= "table" then
        return runtimeNotes
    end

    for _, n in ipairs(sourceNotes) do
        local sec = tonumber(n.time)
        if not sec then
            local ms = tonumber(n.timeMs)
            sec = ms and (ms / 1000) or 0
        end

        local laneFallback = ((#runtimeNotes % math.max(1, activeLaneCount)) + 1)
        runtimeNotes[#runtimeNotes + 1] = {
            lane = normalizeLaneIndex(n.lane, laneFallback),
            type = tonumber(n.type) or 0,
            timeSec = sec,
            gravity = tonumber(n.gravity)
        }
    end

    return runtimeNotes
end

local function buildRuntimeNotesFromLaneTable(lanesByLane)
    local runtimeNotes = {}
    if type(lanesByLane) ~= "table" then
        return runtimeNotes
    end

    for laneKey, laneNotes in pairs(lanesByLane) do
        local lane = normalizeLaneIndex(laneKey)
        if type(laneNotes) == "table" then
            for _, n in ipairs(laneNotes) do
                local sec = tonumber(n.time)
                if not sec then
                    local ms = tonumber(n.timeMs)
                    sec = ms and (ms / 1000) or 0
                end

                runtimeNotes[#runtimeNotes + 1] = {
                    lane = lane,
                    type = tonumber(n.type) or 0,
                    timeSec = sec,
                    gravity = tonumber(n.gravity)
                }
            end
        end
    end

    return runtimeNotes
end

local function buildRuntimeNotesFromLaneNumbers(laneNumbersByLane)
    local runtimeNotes = {}
    if type(laneNumbersByLane) ~= "table" then
        return runtimeNotes
    end

    for laneKey, laneInfo in pairs(laneNumbersByLane) do
        local lane = normalizeLaneIndex(laneKey)
        if type(laneInfo) == "table" and type(laneInfo.pairs) == "table" then
            for _, pair in ipairs(laneInfo.pairs) do
                if type(pair) == "table" then
                    local noteMs = tonumber(pair[1])
                    if noteMs then
                        runtimeNotes[#runtimeNotes + 1] = {
                            lane = lane,
                            type = tonumber(pair[2]) or 0,
                            timeSec = noteMs / 1000
                        }
                    end
                end
            end
        end
    end

    return runtimeNotes
end

local function buildRuntimeNotesFromLaneTimes(laneTimesByLane)
    local runtimeNotes = {}
    if type(laneTimesByLane) ~= "table" then
        return runtimeNotes
    end

    for laneKey, csv in pairs(laneTimesByLane) do
        local lane = normalizeLaneIndex(laneKey)
        if type(csv) == "string" then
            for token in csv:gmatch("([^,]+)") do
                local noteMs = tonumber(token)
                if noteMs then
                    runtimeNotes[#runtimeNotes + 1] = {
                        lane = lane,
                        type = 1,
                        timeSec = noteMs / 1000
                    }
                end
            end
        end
    end

    return runtimeNotes
end

local function getNoteApproach(note)
    local speed = tonumber(note and note.scrollSpeed) or baseNoteSpeed
    speed = math.max(0.1, speed)
    return math.max(0.05, noteApproachSeconds / speed)
end

local function applyChartSpeedEvents(notes, actions)
    local speed = math.max(0.1, baseNoteSpeed)
    local events = {}

    for _, event in ipairs(actions or {}) do
        local eventType = type(event.type) == "string"
            and string.lower(event.type)
            or ""
        local value = event.args and tonumber(event.args[1])

        if (eventType == "hs" or eventType == "scrollmove")
            and value
            and value > 0
        then
            events[#events + 1] = {
                timeSec = tonumber(event.time) or 0,
                speed = value
            }
        end
    end

    table.sort(events, function(a, b)
        return a.timeSec < b.timeSec
    end)

    local eventIndex = 1
    for _, note in ipairs(notes or {}) do
        while eventIndex <= #events
            and events[eventIndex].timeSec <= note.timeSec
        do
            speed = events[eventIndex].speed
            eventIndex = eventIndex + 1
        end
        note.scrollSpeed = speed
    end

    return events
end

local function applyResolvedGravityToNotes(notes, gravityEvents, initialGravity)
    local currentGravity = normalizeNoteGravity(initialGravity or 1)
    local idx = 1
    local events = gravityEvents or {}

    for _, note in ipairs(notes or {}) do
        while idx <= #events and (events[idx].timeSec or 0) <= (note.timeSec or 0) do
            currentGravity = normalizeNoteGravity(events[idx].gravity)
            idx = idx + 1
        end

        note.resolvedGravity = normalizeNoteGravity(note.gravity or currentGravity)
    end
end

local function buildChartRuntime(chart, diffKey)
    chartRuntime.chart = chart
    chartRuntime.notes = {}
    chartRuntime.gravityEvents = {}
    chartRuntime.nextGravityEventIndex = 1
    longNotePairs = {}

    if type(chart) ~= "table" then
        chartRuntime.difficulty = normalizeDifficultyKey(diffKey)
        return 1, 0
    end

    local selectedNotes, selectedDiff = pickNotesByDifficulty(chart, diffKey)
    chartRuntime.difficulty = selectedDiff

    -- レーン単位データ（`,` 区切り基準）を優先してノーツ時間を構築する。
    local runtimeNotes = {}
    if type(chart.lanes) == "table" then
        log.trace("loadChartTable: chart.lanes is set, selectedDiff=" .. tostring(selectedDiff))
        if chart.lanes[selectedDiff] then
            log.trace("  chart.lanes[" .. tostring(selectedDiff) .. "] exists")
            for laneKey, laneNotes in pairs(chart.lanes[selectedDiff]) do
                log.trace("    lane " .. tostring(laneKey) .. ": " .. #(laneNotes or {}) .. " notes")
            end
        else
            log.trace("  chart.lanes[" .. tostring(selectedDiff) .. "] is nil")
        end
        runtimeNotes = buildRuntimeNotesFromLaneTable(chart.lanes[selectedDiff])
        log.trace("  buildRuntimeNotesFromLaneTable returned " .. #runtimeNotes .. " runtime notes")
    else
        log.trace("loadChartTable: chart.lanes is not set")
    end
    if #runtimeNotes == 0 and type(chart.laneNumbers) == "table" then
        runtimeNotes = buildRuntimeNotesFromLaneNumbers(chart.laneNumbers[selectedDiff])
    end
    if #runtimeNotes == 0 and type(chart.laneTimes) == "table" then
        runtimeNotes = buildRuntimeNotesFromLaneTimes(chart.laneTimes[selectedDiff])
    end
    if #runtimeNotes == 0 then
        runtimeNotes = buildRuntimeNotesFromUnifiedList(selectedNotes)
    end

    table.sort(runtimeNotes, function(a, b) return a.timeSec < b.timeSec end)
    for i, n in ipairs(runtimeNotes) do
        n.id = i
    end
    chartRuntime.notes = runtimeNotes
    longNotePairs = buildLongNotePairs(runtimeNotes)

    local actionsByDiff = chart.actions
    local actions = (type(actionsByDiff) == "table") and actionsByDiff[selectedDiff] or nil
    if type(actions) == "table" then
        for _, ev in ipairs(actions) do
            local eventType = type(ev.type) == "string" and string.lower(ev.type) or ""
            if eventType == "gravity" then
                local g = ev.args and tonumber(ev.args[1])
                if g then
                    chartRuntime.gravityEvents[#chartRuntime.gravityEvents + 1] = {
                        timeSec = tonumber(ev.time) or 0,
                        gravity = normalizeNoteGravity(g)
                    }
                end
            end
        end
        table.sort(chartRuntime.gravityEvents, function(a, b) return a.timeSec < b.timeSec end)
    end

    activeLaneCount = 6
    local laneEvents = type(actions) == "table" and actions or {}
    log.trace("loadChartTable: selectedDiff=" .. selectedDiff .. " actions count=" .. #laneEvents)
    for i, event in ipairs(laneEvents) do
        log.trace("  action[" .. i .. "]: type=" .. tostring(event.type) .. " args=" .. (event.args and tostring(event.args[1]) or "nil"))
    end
    for _, event in ipairs(laneEvents) do
        local eventType = type(event.type) == "string" and string.lower(event.type) or ""
        local laneValue = event.args and tonumber(event.args[1])
        if eventType == "lane" and laneValue then
            laneValue = math.floor(laneValue + 0.5)
            if laneValue == 2 or laneValue == 4 or laneValue == 6 then
                activeLaneCount = laneValue
            end
            log.debug("loadChartTable: Found #Lane event with value=" .. laneValue .. " -> activeLaneCount=" .. activeLaneCount)
        end
    end

    applyChartSpeedEvents(runtimeNotes, actions)

    local initialGravity = 1
    if #chartRuntime.notes > 0 and chartRuntime.notes[1].gravity then
        initialGravity = normalizeNoteGravity(chartRuntime.notes[1].gravity)
    end
    local idx = 1
    while idx <= #chartRuntime.gravityEvents and chartRuntime.gravityEvents[idx].timeSec <= 0 do
        initialGravity = normalizeNoteGravity(chartRuntime.gravityEvents[idx].gravity)
        idx = idx + 1
    end
    chartRuntime.nextGravityEventIndex = idx
    applyResolvedGravityToNotes(chartRuntime.notes, chartRuntime.gravityEvents, initialGravity)

    local metaOffset = 0
    if type(chart.meta) == "table" then
        metaOffset = tonumber(chart.meta.offset) or 0
    end
    return initialGravity, metaOffset
end

local function getLaneBoundsForGravity(lane, gravity)
    local w, h = getDisplaySize()
    local laneIndex = tonumber(lane) or 1
    if laneIndex < 1 then laneIndex = 1 end
    if laneIndex > 6 then laneIndex = 6 end

    local visualLaneIndex = getGravityVisualLaneIndex(laneIndex, gravity)

    if gravity == 1 or gravity == 3 then
        local left = (w / activeLaneCount) * (laneIndex - 1)
        local right = (w / activeLaneCount) * laneIndex
        return {
            left = left,
            right = right,
            top = 0,
            bottom = h,
            thickness = right - left
        }
    end

    local top = (h / activeLaneCount) * (visualLaneIndex - 1)
    local bottom = (h / activeLaneCount) * visualLaneIndex
    return {
        left = 0,
        right = w,
        top = top,
        bottom = bottom,
        thickness = bottom - top
    }
end

local function getLaneCenterForGravity(lane, gravity)
    local b = getLaneBoundsForGravity(lane, gravity)
    return (b.left + b.right) * 0.5, (b.top + b.bottom) * 0.5
end

local function getJudgementPointForLane(lane, laneDir)
    local line = judgeAnim.currentLine or buildJudgeLine(laneDir)
    local cx, cy = getLaneCenterForGravity(lane, laneDir)
    if laneDir == 1 or laneDir == 3 then
        return cx, line.y1
    end
    return line.x1, cy
end

pushJudgeHitEffect = function(lane, result, note)
    if not lane then
        return
    end

    local laneDir = normalizeLaneGravity(lanegravity)
    local x, y = getJudgementPointForLane(lane, laneDir)
    local halfW = math.max(6, noteRadius * noteVisualScale * 0.9)
    local halfH = halfW
    local cache = nil
    if note and note.id then
        cache = noteRenderStateCache[note.id]
    end
    if cache then
        x = cache.x or x
        y = cache.y or y
        halfW = math.max(4, tonumber(cache.halfW) or halfW)
        halfH = math.max(4, tonumber(cache.halfH) or halfH)
    else
        local noteDir = normalizeNoteGravity(note and (note.resolvedGravity or note.gravity) or notegravity)
        if isVerticalNoteDirection(noteDir) then
            halfW = halfW * 0.72
            halfH = halfH * 1.45
        else
            halfW = halfW * 1.45
            halfH = halfH * 0.72
        end
    end
    local r, g, b = getJudgeEffectColor(result)
    hitEffects[#hitEffects + 1] = {
        x = x,
        y = y,
        r = r,
        g = g,
        b = b,
        halfW = halfW,
        halfH = halfH,
        t = 0,
        duration = hitEffectDuration
    }
end

local function getSpawnPointForLane(lane, noteDir, laneDir)
    local w, h = getDisplaySize()
    local bounds = getLaneBoundsForGravity(lane, laneDir)
    local cx = (bounds.left + bounds.right) * 0.5
    local cy = (bounds.top + bounds.bottom) * 0.5
    local buffer = math.max(bounds.thickness, noteRadius * 2)
    local g = normalizeNoteGravity(noteDir)

    if g == 1 then
        return cx, -buffer
    elseif g == 2 then
        return w + buffer, cy
    elseif g == 3 then
        return cx, h + buffer
    elseif g == 4 then
        return -buffer, cy
    elseif g == 5 then
        return cx, h * 0.5
    elseif g == 6 then
        return w * 0.5, cy
    elseif g == 7 then
        return cx, h * 0.5
    elseif g == 8 then
        return w * 0.5, cy
    end
    return cx, -buffer
end

local function getLaneBandForNoteDirection(lane, noteDir)
    local w, h = getDisplaySize()
    local laneIndex = normalizeLaneIndex(lane)
    local g = normalizeNoteGravity(noteDir)

    if isVerticalNoteDirection(g) then
        local laneWidth = w / activeLaneCount
        local left = laneWidth * (laneIndex - 1)
        local right = laneWidth * laneIndex
        return {
            left = left,
            right = right,
            top = 0,
            bottom = h,
            centerX = (left + right) * 0.5,
            centerY = h * 0.5,
            size = laneWidth
        }
    end

    local laneHeight = h / activeLaneCount
    local top = laneHeight * (laneIndex - 1)
    local bottom = laneHeight * laneIndex
    return {
        left = 0,
        right = w,
        top = top,
        bottom = bottom,
        centerX = w * 0.5,
        centerY = (top + bottom) * 0.5,
        size = laneHeight
    }
end

local function buildFreeNotePath(lane, noteDir, approach)
    local w, h = getDisplaySize()
    local band = getLaneBandForNoteDirection(lane, noteDir)
    local margin = math.min(w, h) * 0.15
    local edgeBuffer = math.max(band.size * 0.6, math.min(w, h) * 0.05)
    local g = normalizeNoteGravity(noteDir)

    local sx, sy = band.centerX, band.centerY
    local hx, hy = band.centerX, band.centerY

    if g == 1 then
        sy = -edgeBuffer
        hy = h - margin
    elseif g == 2 then
        sx = w + edgeBuffer
        hx = margin
    elseif g == 3 then
        sy = h + edgeBuffer
        hy = margin
    elseif g == 4 then
        sx = -edgeBuffer
        hx = w - margin
    elseif g == 5 then
        sy = -edgeBuffer
        hy = h - margin
    elseif g == 6 then
        sx = w + edgeBuffer
        hx = margin
    elseif g == 7 then
        sy = h + edgeBuffer
        hy = margin
    elseif g == 8 then
        sx = -edgeBuffer
        hx = w - margin
    end

    approach = math.max(0.001, tonumber(approach) or tonumber(noteApproachSeconds) or 0)
    return {
        spawnX = sx,
        spawnY = sy,
        velX = (hx - sx) / approach,
        velY = (hy - sy) / approach,
        laneSize = band.size,
        edgeBuffer = edgeBuffer
    }
end

local function getStickSizeFromLaneSize(laneSize)
    local size = tonumber(laneSize) or 40
    local length = math.max(20, size * 0.72)
    local thickness = math.max(4, size * 0.118)
    if thickness > length * 0.38 then
        thickness = length * 0.38
    end
    return length, thickness
end

local function isRectOutsideScreen(x, y, halfW, halfH, padding)
    local w, h = getDisplaySize()
    local p = tonumber(padding) or 0
    if x + halfW < -p then return true end
    if x - halfW > w + p then return true end
    if y + halfH < -p then return true end
    if y - halfH > h + p then return true end
    return false
end

local function buildNoteRenderState(note, songTime, fallbackDir, approach)
    local approachSec = math.max(0.001, tonumber(approach) or tonumber(noteApproachSeconds) or 0)
    local noteTime = tonumber(note.timeSec) or 0
    local noteApproachSec = getNoteApproach(note)
    approachSec = noteApproachSec
    local spawnTime = noteTime - noteApproachSec
    local noteDir = normalizeNoteGravity(note.resolvedGravity or note.gravity or fallbackDir)
    local path = buildFreeNotePath(note.lane, noteDir, approachSec)
    local travelTime = songTime - spawnTime
    local x = path.spawnX + path.velX * travelTime
    local y = path.spawnY + path.velY * travelTime
    local stickLength, stickThickness = getStickSizeFromLaneSize(path.laneSize)
    local vertical = isVerticalNoteDirection(noteDir)
    local halfW = vertical and (stickLength * 0.5) or (stickThickness * 0.5)
    local halfH = vertical and (stickThickness * 0.5) or (stickLength * 0.5)

    local alphaMul = 1
    local appearWindow = math.max(0.06, approachSec * 0.15)
    if songTime < noteTime then
        local appearProgress = clamp01((songTime - spawnTime) / appearWindow)
        alphaMul = 0.35 + 0.65 * appearProgress
    end

    return {
        spawnTime = spawnTime,
        x = x,
        y = y,
        dir = noteDir,
        stickLength = stickLength,
        stickThickness = stickThickness,
        edgeBuffer = path.edgeBuffer,
        halfW = halfW,
        halfH = halfH,
        alpha = alphaMul,
        visible = not isRectOutsideScreen(x, y, halfW, halfH, path.edgeBuffer)
    }
end

local function updateChartGravityEvents(songTime)
    local events = chartRuntime.gravityEvents
    if not events or #events == 0 then
        return
    end

    local idx = chartRuntime.nextGravityEventIndex or 1
    while idx <= #events and songTime >= events[idx].timeSec do
        local nextGravity = normalizeNoteGravity(events[idx].gravity)
        if notegravity ~= nextGravity then
            notegravity = nextGravity
            triggerDirectionGlow()
        else
            notegravity = nextGravity
        end
        idx = idx + 1
    end
    chartRuntime.nextGravityEventIndex = idx
end

local function getCurrentSongTime()
    if not songStarted or not bgmSource then
        return nil
    end

    local okSeconds, seconds = pcall(bgmSource.tell, bgmSource, "seconds")
    if okSeconds and type(seconds) == "number" then
        return seconds
    end

    local okDefault, defaultSeconds = pcall(bgmSource.tell, bgmSource)
    if okDefault and type(defaultSeconds) == "number" then
        return defaultSeconds
    end

    return nil
end

function updateNoteDrawQueue(songTime)
    for k in pairs(noteDrawQueue) do
        noteDrawQueue[k] = nil
    end
    for k in pairs(notexy) do
        notexy[k] = nil
    end
    for k in pairs(noteRenderStateCache) do
        noteRenderStateCache[k] = nil
    end

    local notes = chartRuntime.notes
    if not notes or #notes == 0 then
        return
    end

    local currentNoteDir = normalizeNoteGravity(notegravity)
    local queueCount = 0
    local approach = noteApproachSeconds

    chartRuntime.currentIndex = chartRuntime.currentIndex or 1
    local startIndex = chartRuntime.currentIndex

    for i = startIndex, #notes do
        local note = notes[i]

        if note.judged then
            chartRuntime.currentIndex = i + 1
            goto continue
        end

        local spawnTime = note.timeSec - getNoteApproach(note)

        if spawnTime > songTime then
            break
        end

        if note.timeSec > songTime + 2 then
            break
        end

        local state = buildNoteRenderState(note, songTime, currentNoteDir, approach)

        local pos = notexy[note.id]
        if not pos then
            pos = {}
            notexy[note.id] = pos
        end
        pos[1] = state.x
        pos[2] = state.y

        local cache = noteRenderStateCache[note.id]
        if not cache then
            cache = {}
            noteRenderStateCache[note.id] = cache
        end
        cache.x = state.x
        cache.y = state.y
        cache.halfW = state.halfW
        cache.halfH = state.halfH
        cache.dir = state.dir

        if state.visible and not note.isLongStart and not note.isLongEnd then
            queueCount = queueCount + 1

            local q = noteDrawQueue[queueCount]
            if not q then
                q = {}
                noteDrawQueue[queueCount] = q
            end

            q.id = note.id
            q.lane = note.lane
            q.x = state.x
            q.y = state.y
            q.dir = state.dir
            q.stickLength = state.stickLength
            q.stickThickness = state.stickThickness
            q.type = note.type
            q.alpha = state.alpha
        end

        ::continue::
    end
end

local function getNoteColor(noteType, tintEnabled)
    local t = tonumber(noteType) or 0
    if t == 1 then
        -- 1: ノーマルノーツをグレーに統一
        return 0.7, 0.7, 0.7
    end

    if not tintEnabled then
        if t == 3 then
            return 0.85, 0.85, 0.85
        end
        return 0.62, 0.66, 0.72
    end

    if t == 2 then
        -- 2: ロング始点
        return 0.24, 0.86, 1.0
    elseif t == 3 then
        -- 3: クリティカルノーツ
        return 1.0, 0.82, 0.28
    elseif t == 4 then
        -- 4: ロング終点
        return 0.62, 0.74, 1.0
    end
    return 1.0, 1.0, 1.0
end

local function getLaneColor(lane, tintEnabled)
    if not tintEnabled or activeLaneCount ~= 6 then
        return nil
    end

    local laneIndex = normalizeLaneIndex(lane)
    local color = nil

    if laneIndex == 2 then
        color = {0.24, 0.86, 1.0}
    elseif laneIndex == 5 then
        color = {1.0, 0.62, 0.28}
    end

    if not color then
        return nil
    end
    return color[1], color[2], color[3]
end

local function applyBrightness(r, g, b, strength)
    local s = clamp01(strength or 0)
    return r + (1 - r) * s, g + (1 - g) * s, b + (1 - b) * s
end

local function getNoteVisualSize(noteDir, stickLength, stickThickness)
    local length = tonumber(stickLength) or 24
    local thickness = tonumber(stickThickness) or 8
    local verticalFlow = isVerticalNoteDirection(noteDir)
    local w = (verticalFlow and length or thickness) * noteVisualScale
    local h = (verticalFlow and thickness or length) * noteVisualScale
    return w, h, verticalFlow
end

local function drawChamferedRect(mode, x, y, w, h, cut)
    local c = tonumber(cut) or 0
    local maxCut = math.min(w, h) * 0.5 - 0.01
    if c <= 0 or maxCut <= 0 then
        love.graphics.rectangle(mode, x, y, w, h)
        return
    end

    c = math.max(0.01, math.min(c, maxCut))
    love.graphics.polygon(
        mode,
        x + c, y,
        x + w - c, y,
        x + w, y + c,
        x + w, y + h - c,
        x + w - c, y + h,
        x + c, y + h,
        x, y + h - c,
        x, y + c
    )
end

local function drawDirectionGlyph(x, y, w, h, alpha, glow, horizontal)
    local a = clamp01(alpha * (0.26 + glow * 0.18))
    local lineW = math.max(1, math.min(w, h) * 0.12)
    love.graphics.setLineWidth(lineW)
    love.graphics.setColor(0.9, 0.98, 1, a)

    if horizontal then
        local startX = x + w * 0.2
        local step = w * 0.12
        local dx = w * 0.08
        local yBottom = y + h * 0.75
        local yTop = y + h * 0.25
        for i = 0, 2 do
            local sx = startX + step * i
            love.graphics.line(sx, yBottom, sx + dx, yTop)
        end
    else
        local startY = y + h * 0.2
        local step = h * 0.12
        local dy = h * 0.08
        local xLeft = x + w * 0.24
        local xRight = x + w * 0.76
        for i = 0, 2 do
            local sy = startY + step * i
            love.graphics.line(xLeft, sy, xRight, sy + dy)
        end
    end

    love.graphics.setLineWidth(1)
end

local function drawStylishNote(x, y, w, h, noteType, alpha, glow, tintEnabled, lane)
    local baseR, baseG, baseB = getLaneColor(lane, tintEnabled)
    if not baseR then
        baseR, baseG, baseB = getNoteColor(noteType, tintEnabled)
    end

    local baseAlpha = clamp01(alpha or 1)
    if baseAlpha <= 0 then
        return
    end

    local br, bg, bb = applyBrightness(baseR, baseG, baseB, glow * 0.18)
    local pad = math.max(1, math.min(w, h) * 0.06)
    local visualAlpha = clamp01(baseAlpha * 1.18)

    love.graphics.setColor(br * 0.14, bg * 0.14, bb * 0.14, clamp01(visualAlpha * 0.22))
    love.graphics.rectangle("fill", x - pad, y - pad, w + pad * 2, h + pad * 2)

    love.graphics.setColor(br, bg, bb, clamp01(visualAlpha * 1.02))
    love.graphics.rectangle("fill", x, y, w, h)

    love.graphics.setColor(0.08, 0.10, 0.15, clamp01(visualAlpha * 1.0))
    love.graphics.rectangle("fill", x + 1, y + 1, math.max(1, w - 2), math.max(1, h - 2))

    love.graphics.setColor(1, 1, 1, clamp01(visualAlpha * 0.16))
    love.graphics.rectangle("fill", x + 2, y + 2, math.max(1, w - 4), math.max(1, h * 0.18))
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function drawLinearGradientRect(x, y, w, h, fromColor, toColor, alpha, vertical)
    local a = clamp01(alpha or 1)
    if a <= 0 then
        return
    end

    local steps = 22
    if vertical then
        local slice = h / steps
        for i = 0, steps - 1 do
            local t = i / math.max(1, steps - 1)
            local sy = y + slice * i
            local sh = (i == steps - 1) and (y + h - sy) or (slice + 0.6)
            love.graphics.setColor(
                lerp(fromColor[1], toColor[1], t),
                lerp(fromColor[2], toColor[2], t),
                lerp(fromColor[3], toColor[3], t),
                a
            )
            love.graphics.rectangle("fill", x, sy, w, sh)
        end
    else
        local slice = w / steps
        for i = 0, steps - 1 do
            local t = i / math.max(1, steps - 1)
            local sx = x + slice * i
            local sw = (i == steps - 1) and (x + w - sx) or (slice + 0.6)
            love.graphics.setColor(
                lerp(fromColor[1], toColor[1], t),
                lerp(fromColor[2], toColor[2], t),
                lerp(fromColor[3], toColor[3], t),
                a
            )
            love.graphics.rectangle("fill", sx, y, sw, h)
        end
    end
end

local function drawLongNoteConnector(startState, endState, alpha, tintEnabled, holdBroken)
    local baseAlpha = clamp01(alpha or 1)
    if baseAlpha <= 0 then
        return
    end

    -- 開始と終了ノートのどちらがverticalかを判定（複数gravity対応）
    local startVertical = isVerticalNoteDirection(startState.dir)
    local endVertical = isVerticalNoteDirection(endState.dir)
    local verticalFlow = startVertical and endVertical  -- 両方垂直の場合のみ垂直と判定
    local startW, startH = getNoteVisualSize(startState.dir, startState.stickLength, startState.stickThickness)
    local endW, endH = getNoteVisualSize(endState.dir, endState.stickLength, endState.stickThickness)
    local minor = verticalFlow and math.max(startW, endW) or math.max(startH, endH)
    minor = math.max(2, minor)

    local x, y, w, h
    if verticalFlow then
        local cx = (startState.x + endState.x) * 0.5
        local top = math.min(startState.y, endState.y)
        local bottom = math.max(startState.y, endState.y)
        x = cx - minor * 0.5
        y = top
        w = minor
        h = math.max(1, bottom - top)
    else
        local cy = (startState.y + endState.y) * 0.5
        local left = math.min(startState.x, endState.x)
        local right = math.max(startState.x, endState.x)
        x = left
        y = cy - minor * 0.5
        w = math.max(1, right - left)
        h = minor
    end

    if w < 1 or h < 1 then
        return
    end

    local baseFillR, baseFillG, baseFillB = 0.06, 0.08, 0.11
    local gradFrom = {0.56, 0.56, 0.58}
    local gradTo = {0.56, 0.56, 0.58}
    local railR, railG, railB = 0.88, 0.96, 1.0
    local borderR, borderG, borderB = 0.97, 0.99, 1.0
    if holdBroken then
        baseFillR, baseFillG, baseFillB = 0.17, 0.03, 0.05
        gradFrom = {0.98, 0.34, 0.36}
        gradTo = {0.72, 0.10, 0.14}
        railR, railG, railB = 1.0, 0.63, 0.63
        borderR, borderG, borderB = 1.0, 0.84, 0.84
    elseif not tintEnabled then
        gradFrom = {0.5, 0.52, 0.56}
        gradTo = {0.5, 0.52, 0.56}
        railR, railG, railB = 0.9, 0.92, 0.96
        borderR, borderG, borderB = 0.88, 0.9, 0.94
    end

    love.graphics.setColor(baseFillR, baseFillG, baseFillB, clamp01(baseAlpha * 0.92))
    love.graphics.rectangle("fill", x, y, w, h)

    local inset = math.max(1, math.min(w, h) * 0.08)
    local panelX = x + inset
    local panelY = y + inset
    local panelW = w - inset * 2
    local panelH = h - inset * 2
    if panelW > 1 and panelH > 1 then
        drawLinearGradientRect(
            panelX,
            panelY,
            panelW,
            panelH,
            gradFrom,
            gradTo,
            clamp01(baseAlpha * 0.94),
            verticalFlow
        )

        if verticalFlow then
            local railW = math.max(1, panelW * 0.1)
            love.graphics.setColor(railR, railG, railB, clamp01(baseAlpha * 0.36))
            love.graphics.rectangle("fill", panelX + railW, panelY, railW, panelH)
            love.graphics.rectangle("fill", panelX + panelW - railW * 2, panelY, railW, panelH)
        else
            local railH = math.max(1, panelH * 0.1)
            love.graphics.setColor(railR, railG, railB, clamp01(baseAlpha * 0.36))
            love.graphics.rectangle("fill", panelX, panelY + railH, panelW, railH)
            love.graphics.rectangle("fill", panelX, panelY + panelH - railH * 2, panelW, railH)
        end
    end

    love.graphics.setColor(borderR, borderG, borderB, clamp01(baseAlpha * 0.5))
    love.graphics.rectangle("line", x, y, w, h)
end

local function drawLongNoteBodies(songTime)
    if not longNotePairs or #longNotePairs == 0 then
        return
    end

    local notes = chartRuntime.notes
    if not notes or #notes == 0 then
        return
    end

    local approach = math.max(0.001, tonumber(noteApproachSeconds) or 0)
    local currentNoteDir = normalizeNoteGravity(notegravity)
    local currentLaneDir = normalizeLaneGravity(lanegravity)
    local w, h = getDisplaySize()
    
    for _, pair in ipairs(longNotePairs) do
        local startNote = pair.startNote
        local endNote = pair.endNote
        if startNote and endNote then
            local shouldDraw = true
            local shrinkProgress = 0
            
            -- 判定ラインの位置を取得
            if not judgeAnim.currentLine then
                judgeAnim.currentLine = buildJudgeLine(lanegravity)
            end
            local judgeLinePosition = judgeAnim.currentLine
            
            if startNote.judged and startNote.hit then
                -- 始点が判定済みで hit（ボタン押下）の場合
                -- 判定ラインの位置を毎フレーム更新（アニメーション対応）
                if judgeLinePosition then
                    local x1 = judgeLinePosition.x1 or 0
                    local y1 = judgeLinePosition.y1 or 0
                    local x2 = judgeLinePosition.x2 or 0
                    local y2 = judgeLinePosition.y2 or 0
                    startNote.fixedJudgeLinePos = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
                end
                
                if endNote.judged then
                    -- 終点も判定済みの場合、カットアニメーション実行
                    local elapsedSinceEndNoteJudge = songTime - (endNote.judgedTime or 0)
                    if elapsedSinceEndNoteJudge < longNoteFadeDuration then
                        shrinkProgress = elapsedSinceEndNoteJudge / longNoteFadeDuration
                    else
                        shouldDraw = false
                    end
                end
            end
            
            if shouldDraw and (not startNote.judged or (startNote.judged and startNote.hit)) then
                local startSpawn = (startNote.timeSec or 0) - approach
                if songTime >= startSpawn then
                    local startState = buildNoteRenderState(startNote, songTime, currentNoteDir, approach)
                    local endState = buildNoteRenderState(endNote, songTime, currentNoteDir, approach)
                    
                    -- 始点を判定ラインの場所に張り付かせる
                    if startNote.judged and startNote.hit and startNote.fixedJudgeLinePos then
                        local fixedLine = startNote.fixedJudgeLinePos
                        local g = normalizeLaneGravity(lanegravity)
                        
                        if g == 1 then
                            -- 下向き：始点y座標を判定ラインのy座標に固定
                            startState.y = fixedLine.y1
                        elseif g == 3 then
                            -- 上向き：始点y座標を判定ラインのy座標に固定
                            startState.y = fixedLine.y1
                        elseif g == 2 then
                            -- 左向き：始点x座標を判定ラインのx座標に固定
                            startState.x = fixedLine.x1
                        else
                            -- g == 4 右向き：始点x座標を判定ラインのx座標に固定
                            startState.x = fixedLine.x1
                        end
                    end
                    
                    -- 終点を始点に向かって移動（短くなるアニメーション）
                    if shrinkProgress > 0 then
                        endState.x = endState.x + (startState.x - endState.x) * shrinkProgress
                        endState.y = endState.y + (startState.y - endState.y) * shrinkProgress
                    end
                    
                    local connectorAlpha = clamp01(math.min(startState.alpha, endState.alpha) * 0.9)
                    local tintEnabled = isNoteGravityAlignedWithLane(startState.dir, currentLaneDir)

                    if connectorAlpha > 0 then
                        -- クリッピング処理：判定ラインより手前側のみ表示
                        local needsClip = startNote.judged and startNote.hit
                        
                        if needsClip and judgeLinePosition then
                            local scissorX, scissorY, scissorW, scissorH
                            local g = normalizeLaneGravity(lanegravity)
                            
                            if g == 1 then
                                -- 下向き：判定ラインより上を表示
                                scissorX = 0
                                scissorY = 0
                                scissorW = w
                                scissorH = judgeLinePosition.y1
                            elseif g == 3 then
                                -- 上向き：判定ラインより下を表示
                                scissorX = 0
                                scissorY = judgeLinePosition.y1
                                scissorW = w
                                scissorH = math.max(0, h - judgeLinePosition.y1)
                            elseif g == 2 then
                                -- 左向き：判定ラインを越えた右側を表示
                                scissorX = judgeLinePosition.x1
                                scissorY = 0
                                scissorW = math.max(0, w - judgeLinePosition.x1)
                                scissorH = h
                            else
                                -- g == 4 右向き：判定ラインを越えた左側を表示
                                scissorX = 0
                                scissorY = 0
                                scissorW = judgeLinePosition.x1
                                scissorH = h
                            end
                            
                            love.graphics.setScissor(scissorX, scissorY, scissorW, scissorH)
                        end
                        
                        local cx = (startState.x + endState.x) * 0.5
                        local cy = (startState.y + endState.y) * 0.5
                        local extra = math.max(startState.stickLength or 0, endState.stickLength or 0)
                        local halfW = math.abs(startState.x - endState.x) * 0.5 + extra
                        local halfH = math.abs(startState.y - endState.y) * 0.5 + extra
                        local pad = math.max(startState.edgeBuffer or 0, endState.edgeBuffer or 0)
                        if not isRectOutsideScreen(cx, cy, halfW, halfH, pad) then
                            drawLongNoteConnector(startState, endState, connectorAlpha, tintEnabled, pair.holdBroken == true)
                        end
                        
                        if needsClip then
                            love.graphics.setScissor()
                        end
                    end
                end
            end
        end
    end
end

local function getLineIntroVisual()
    local drawProgress = 1
    local lineAlpha = 0.55
    local delay = tonumber(startDelay) or 0
    if playTimer < delay then
        local introT = clamp01(playTimer / laneIntroDrawDuration)
        drawProgress = easeOutCubic(introT)
        if playTimer <= laneIntroBlinkDuration then
            local pulse = 0.5 + 0.5 * math.sin(playTimer * 16)
            lineAlpha = 0.25 + 0.5 * pulse
        end
    end
    return drawProgress, lineAlpha
end

function play.setCollections(c)
    if collections ~= c then
        collectionsSummaryLogged = false
    end
    collections = c
    if collections then
        musicfiles = collections.audio or {}
        chartfiles = collections.charts or {}
        imagefiles = collections.images or {}

        local collectionCount = 0
        if type(musicfiles) == "table" then
            collectionCount = #musicfiles
        end
        if collectionCount <= 1 and type(chartfiles) == "table" and #chartfiles <= 1 then
            selectindex = 1
        end
    else
        musicfiles = nil
        chartfiles = nil
        imagefiles = nil
    end
end

function play.setTimingAssist(enabled)
    timingAssistEnabled = enabled == true
    if not timingAssistEnabled then
        lastTimingDeltaMs = nil
        timingAssistRemaining = 0
    end
end





function play.getCollections()
    return collections
end

function play.getCombo()
    return math.max(0, math.floor(tonumber(combo) or 0))
end

function play.getMaxCombo()
    return math.max(0, math.floor(tonumber(maxCombo) or 0))
end








local function sfbloadercatcher()
    if not collections then
        log.warn("sfbloadercatcher: collections are not initialized by openingloader. Using empty collections.")
        collections = {audio = {}, charts = {}, images = {}}
    end
    play.setCollections(collections)

    if not musicfiles or #musicfiles == 0 then
        log.warn("Error: No music files found.")
    end

    if not chartfiles or #chartfiles == 0 then
        log.warn("Error: No chart files found.")
    end

    if not imagefiles or #imagefiles == 0 then
        log.warn("Error: No image files found.")
    end

    if not collectionsSummaryLogged then
        log.info(string.format(
            "play collections: music=%d charts=%d images=%d",
            #(musicfiles or {}),
            #(chartfiles or {}),
            #(imagefiles or {})
        ))
        collectionsSummaryLogged = true
    end
end








local function buildBgmSource(entry)
    if type(entry) == "table" and entry._cachedBgmSoundData ~= nil then
        local cached = entry._cachedBgmSoundData or nil
        if cached then
            local okStatic, staticSource = pcall(love.audio.newSource, cached, "static")
            if okStatic and staticSource then
                return staticSource
            end
        end
    elseif type(entry) == "string" and bgmSoundDataPathCache[entry] ~= nil then
        local cached = bgmSoundDataPathCache[entry] or nil
        if cached then
            local okStatic, staticSource = pcall(love.audio.newSource, cached, "static")
            if okStatic and staticSource then
                return staticSource
            end
        end
    end

    local preloadedSoundData = nil
    if collections then
        preloadedSoundData = audiocache.getPreloadedSoundData(collections, entry)
    end
    if preloadedSoundData then
        if type(entry) == "table" then
            entry._cachedBgmSoundData = preloadedSoundData
        elseif type(entry) == "string" then
            bgmSoundDataPathCache[entry] = preloadedSoundData
        end

        local okStatic, staticSource = pcall(love.audio.newSource, preloadedSoundData, "static")
        if okStatic and staticSource then
            return staticSource
        end
    end

    if type(entry) == "table" and type(entry.data) == "string" then
        local fileName = entry.name or "audio"

        local okFileData, fileData = pcall(love.filesystem.newFileData, entry.data, fileName)
        if not okFileData or not fileData then
            return nil
        end

        local okSoundData, soundData = pcall(love.sound.newSoundData, fileData)
        if okSoundData and soundData then
            entry._cachedBgmSoundData = soundData
            local okStatic, staticSource = pcall(love.audio.newSource, soundData, "static")
            if okStatic and staticSource then
                return staticSource
            end
        else
            entry._cachedBgmSoundData = false
        end

        -- 要望対応: 再生開始前に全体を先読みできるよう static を優先する
        local okStatic, staticSource = pcall(love.audio.newSource, fileData, "static")
        if okStatic and staticSource then
            return staticSource
        end

        local okStream, streamSource = pcall(love.audio.newSource, fileData, "stream")
        if okStream and streamSource then
            return streamSource
        end
    end

    if type(entry) == "table" and type(entry.name) == "string" then
        return buildBgmSource(entry.name)
    end

    if type(entry) == "string" then
        local okSoundData, soundData = pcall(love.sound.newSoundData, entry)
        if okSoundData and soundData then
            bgmSoundDataPathCache[entry] = soundData
            local okStatic, staticSource = pcall(love.audio.newSource, soundData, "static")
            if okStatic and staticSource then
                return staticSource
            end
        else
            bgmSoundDataPathCache[entry] = false
        end

        local okStatic, staticSource = pcall(love.audio.newSource, entry, "static")
        if okStatic and staticSource then
            return staticSource
        end

        local okStream, streamSource = pcall(love.audio.newSource, entry, "stream")
        if okStream and streamSource then
            return streamSource
        end
    end

    return nil
end

local function buildJacketImage(entry)
    if type(entry) == "table" and entry._cachedJacketImage ~= nil then
        return entry._cachedJacketImage or nil
    elseif type(entry) == "string" and jacketImagePathCache[entry] ~= nil then
        return jacketImagePathCache[entry] or nil
    end

    local builtImage = nil
    if type(entry) == "table" and type(entry.data) == "string" then
        local fileName = entry.name or "jacket"
        local okFileData, fileData = pcall(love.filesystem.newFileData, entry.data, fileName)
        if okFileData and fileData then
            local okImageData, imageData = pcall(love.image.newImageData, fileData)
            if okImageData and imageData then
                local okImage, imageObj = pcall(love.graphics.newImage, imageData)
                if okImage and imageObj then
                    builtImage = imageObj
                end
            end
        end
    elseif type(entry) == "table" and type(entry.name) == "string" then
        local okImage, imageObj = pcall(love.graphics.newImage, entry.name)
        if okImage and imageObj then
            builtImage = imageObj
        end
    elseif type(entry) == "string" then
        local okImage, imageObj = pcall(love.graphics.newImage, entry)
        if okImage and imageObj then
            builtImage = imageObj
        end
    end

    if type(entry) == "table" then
        entry._cachedJacketImage = builtImage or false
    elseif type(entry) == "string" then
        jacketImagePathCache[entry] = builtImage or false
    end

    return builtImage
end

local function resolveJacketEntry(selectedIndex)
    if not imagefiles or #imagefiles == 0 then
        return nil
    end

    local normalizedIndex = tonumber(selectedIndex) or 1
    if not chartfiles or not chartfiles[normalizedIndex] then
        normalizedIndex = 1
    end

    local chartEntry = chartfiles and chartfiles[normalizedIndex]
    local chartArchive = type(chartEntry) == "table" and chartEntry.archive
    if chartArchive then
        for _, imageEntry in ipairs(imagefiles) do
            if type(imageEntry) == "table" and imageEntry.archive == chartArchive then
                return imageEntry
            end
        end
    end

    return imagefiles[normalizedIndex]
end






local function getSelectedSongDisplayData()
    local selectedIndex = tonumber(selectindex) or 1
    if type(chartfiles) == "table" and #chartfiles > 0 and not chartfiles[selectedIndex] then
        selectedIndex = 1
    end

    local displayTitle = "Unknown Title"
    if type(musicname) == "string" and musicname ~= "" then
        displayTitle = musicname
    elseif chartfiles and chartfiles[selectedIndex] then
        displayTitle = chartfiles[selectedIndex].title or chartfiles[selectedIndex].name or "Unknown Title"
    end

    local displayArtist = "Unknown Artist"
    if type(musicartist) == "string" and musicartist ~= "" then
        displayArtist = musicartist
    elseif chartfiles and chartfiles[selectedIndex] then
        displayArtist = chartfiles[selectedIndex].artist or "Unknown Artist"
    end

    local displayLevel = "Unknown Level"
    local rawLevel = "Unknown Level"
    local difficultyKey = nil

    if type(musicdifficulty) == "string" and musicdifficulty ~= "" then
        local numericDifficulty = tostring(musicdifficulty):match("^%s*[%+%-]?%d+%.?%d*%s*$")
        if not numericDifficulty then
            difficultyKey = musicdifficulty
        end
    end
    if not difficultyKey and type(musicselect) == "table" and type(musicselect.selectedDifficulty) == "string" and musicselect.selectedDifficulty ~= "" then
        difficultyKey = musicselect.selectedDifficulty
    end

    if difficultyKey then
        rawLevel = difficultyKey
        displayLevel = string.upper(difficultyKey)
    elseif type(musiclevel) == "string" and musiclevel ~= "" then
        rawLevel = musiclevel
        displayLevel = formatDifficultyLevel(musiclevel)
    elseif chartfiles and chartfiles[selectedIndex] and chartfiles[selectedIndex].level then
        rawLevel = chartfiles[selectedIndex].level
        displayLevel = formatDifficultyLevel(chartfiles[selectedIndex].level)
    end

    return {
        title = displayTitle,
        artist = displayArtist,
        rawLevel = rawLevel,
        level = displayLevel,
        levelColor = levelColors[rawLevel] or levelColors.default
    }
end

local function getFinalJudgeResolveTime()
    local lastNoteTime = 0
    for _, note in ipairs(chartRuntime.notes or {}) do
        local noteTime = tonumber(note.timeSec) or 0
        if noteTime > lastNoteTime then
            lastNoteTime = noteTime
        end
    end

    local resolveMarginSec = (math.max(judgeWindowMs.bad or 0, longNoteEndGraceMs or 0) / 1000) + 0.001
    return math.max(tonumber(musictime) or 0, lastNoteTime + resolveMarginSec)
end

local function publishResultData()
    local songData = getSelectedSongDisplayData()
    _G.name = songData.title
    _G.artist = songData.artist
    _G.level = songData.level
    _G.jacket = jacketimg

    _G.score = _G.score or {}
    _G.score.score = math.max(0, math.floor(tonumber(score) or 0))
    _G.score.maxcombo = math.max(0, math.floor(tonumber(maxCombo) or 0))
    _G.score.perfect = judgeCounts.perfect or 0
    _G.score.great = 0
    _G.score.good = judgeCounts.good or 0
    _G.score.bad = judgeCounts.bad or 0
    _G.score.miss = judgeCounts.miss or 0
end

local function transitionToResult()
    if resultTransitioned then
        return
    end

    resultTransitioned = true
    local finalJudgeTime = getFinalJudgeResolveTime()
    updateLongHoldJudgements(finalJudgeTime)
    updateMissJudgements(finalJudgeTime)
    publishResultData()
    if type(resultTransitionHandler) == "function" then
        resultTransitionHandler()
    else
        changeProgram(7)
    end
end

function play.setResultTransitionHandler(handler)
    resultTransitionHandler = type(handler) == "function" and handler or nil
end

function musicdatadraw()
    local songData = getSelectedSongDisplayData()
    local displayTitle = songData.title
    local displayArtist = songData.artist
    local displayLevel = songData.level
    local levelcolor = songData.levelColor or {1, 1, 1}
    local drawAlpha = alpha or 0
    local drawJacketAlpha = jacketalpha or 0
    local displayx, displayy = getDisplaySize()
    if drawAlpha > 0.001 or drawJacketAlpha > 0.001 then
        metaDisplayShown = true
    end

    love.graphics.setColor(1, 1, 1, drawJacketAlpha)
    if jacketimg then
        jacket = jacketimg
        love.graphics.draw(jacketimg, 0, 0, 0, displayx / jacketimg:getWidth(), displayy / jacketimg:getHeight())
    end
    name = displayTitle
    artist = displayArtist
    level = displayLevel
    local safeLeftTitleFont = getSafeFont(lefttitlefont)
    local safeTitleFont = getSafeFont(titlefont)
    local safeArtistFont = getSafeFont(artistfont)

    love.graphics.setFont(safeLeftTitleFont)
    love.graphics.print(displayTitle, 0, displayy - safeLeftTitleFont:getHeight())
    love.graphics.setColor(1, 1, 1, drawAlpha)
    love.graphics.setFont(safeTitleFont)
    love.graphics.print(displayTitle, displayx / 2 - safeTitleFont:getWidth(displayTitle) / 2, displayy / 2 + displayy / 10)
    love.graphics.setFont(safeArtistFont)
    love.graphics.print(displayArtist, displayx / 2 - safeArtistFont:getWidth(displayArtist) / 2, displayy / 2 + displayy / 5)
    if requestCountText then
        love.graphics.setColor(1, 1, 1, drawAlpha)
        local countText = requestCountText
        love.graphics.print(countText, displayx / 2 - safeArtistFont:getWidth(countText) / 2, displayy / 2 + displayy / 4)
    end
    love.graphics.setFont(safeTitleFont)
    love.graphics.setFont(safeTitleFont)
love.graphics.setColor(levelcolor[1], levelcolor[2], levelcolor[3], drawAlpha)

local levelWidth = safeTitleFont:getWidth(displayLevel)
local levelHeight = safeTitleFont:getHeight()

local levelX = displayx / 2 - levelWidth / 2
local levelY = displayy * 0.78 - levelHeight / 2

love.graphics.print(displayLevel, levelX, levelY)
end





function play.load()
    alpha = 1
    jacketalpha = 0
    playTimer = 0
    metaDisplayTimer = 0
    metaDisplayShown = false
    metaDisplayFinished = false
    musicload = 0
    songStarted = false
    jacketimg = nil
    musictime = 0
    musictimer = 0
    finished = false
    resultTransitioned = false
    lastTimingDeltaMs = nil
    timingAssistRemaining = 0
    paused = false
    waitingResume = false
    resumeTimer = 0
    pauseMenuButtons = {}
    lanegravity = 1
    notegravity = 1
    laneAnim.initialized = false
    laneAnim.elapsed = 0
    judgeAnim.initialized = false
    judgeAnim.elapsed = 0
    chartRuntime.chart = nil
    chartRuntime.notes = {}
    chartRuntime.gravityEvents = {}
    chartRuntime.nextGravityEventIndex = 1
    chartRuntime.difficulty = "easy"
    activeLaneCount = 6
    baseNoteSpeed = 1.0
    noteDrawQueue = {}
    noteRenderStateCache = {}
    longNotePairs = {}
    notexy = {}
    resetJudgeCounts()
    clearLaneInputStates()
    hitEffects = {}
    chartRuntime.currentIndex = 1

    if bgmSource and bgmSource.stop then
        bgmSource:stop()
    end
    bgmSource = nil

    sfbloadercatcher()
    requestCountText = nil
    local songTitle = tostring(musicname or "")
    if songTitle == "" then
        songTitle = getSelectedSongDisplayData().title or ""
    end
    local requestDifficulty = musicdifficulty or musiclevel or chartRuntime.difficulty or ""
    log.info(tostring(musicname), tostring(requestDifficulty) .. "をプレイ")

    local selectedIndex = tonumber(selectindex) or 1
    if type(musicfiles) == "table" and #musicfiles > 0 and not musicfiles[selectedIndex] then
        selectedIndex = 1
    end

    if not musicfiles or not musicfiles[selectedIndex] then
        log.error("Error: Selected music file not found.")
        return
    end

    bgmSource = buildBgmSource(musicfiles[selectedIndex])
    if not bgmSource then
        log.error("Error: Failed to create audio source for selected music.")
        return
    end
    bgmSource:stop()
    local okSeek = pcall(bgmSource.seek, bgmSource, 0, "seconds")
    if not okSeek then
        pcall(bgmSource.seek, bgmSource, 0)
    end
    bgmSource:setLooping(false)

    local selectedChart = chartfiles and chartfiles[selectedIndex] or (chartfiles and chartfiles[1])
    local chartTable = loadChartTable(selectedChart, false)
    local selectedDifficultyKey = musicdifficulty or musiclevel
    if chartTable then
        local initialGravity = buildChartRuntime(chartTable, selectedDifficultyKey)
        notegravity = normalizeNoteGravity(initialGravity)
        lanegravity = noteGravityToLaneDirection(notegravity)
    else
        buildChartRuntime(nil, selectedDifficultyKey)
        notegravity = 1
        lanegravity = 1
        log.warn("Warning: chart data could not be loaded. notes will be empty.")
    end
    local metaDisplayTotal = getMetaDisplayTotalSeconds()
    startDelay = metaDisplayTotal + musicStartAfterMetaSeconds
    local jacketEntry = resolveJacketEntry(selectedIndex)
    jacketimg = buildJacketImage(jacketEntry)
    if not jacketimg and jacketEntry then
        log.warn("Warning: Failed to create jacket image for selected music.")
    end

    ensurePlayFontsLoaded()
    loadPauseMenuButtonImages()
    ensureNoteSePoolLoaded()

end


function playNoteSE()
    if not noteSE then return end

    local s = noteSE[seIndex]
    if not s then return end

    s:stop()
    s:play()

    seIndex = seIndex + 1
    if seIndex > SE_COUNT then
        seIndex = 1
    end
end

-- エディタモードなどから呼ばれる、現在の楽曲チャートを再読み込みする関数
function reloadCurrentChart()
    local selectedIndex = tonumber(selectindex)
    if not selectedIndex then
        log.warn("Error: Invalid selected index.")
        return false
    end
    
    if not chartfiles or not chartfiles[selectedIndex] then
        log.warn("Error: Selected chart file not found.")
        return false
    end
    
    local selectedChart = chartfiles[selectedIndex]
    local chartTable = loadChartTable(selectedChart, true)
    
    noteDrawQueue = {}
    notexy = {}
    noteRenderStateCache = {}
    longNotePairs = {}
    chartRuntime.currentIndex = 1

    local selectedDifficultyKey = musicdifficulty or musiclevel
    if chartTable then
        local initialGravity = buildChartRuntime(chartTable, selectedDifficultyKey)
        notegravity = normalizeNoteGravity(initialGravity)
        lanegravity = noteGravityToLaneDirection(notegravity)
        log.info("チャートを再読み込みしました")
        return true
    else
        log.warn("チャートの再読み込みに失敗しました")
        return false
    end
end

function play.update(dt)
    updateLaneHoldStatesFromKeyboard()
    if not bgmSource then
        return
    end

    if waitingResume and not finished then
        resumeTimer = resumeTimer + dt
        if resumeTimer >= resumeDelay then
            waitingResume = false
            resumeTimer = 0
            paused = false
            if bgmSource then
                bgmSource:play()
            end
        end
        return
    end

    if paused then
        return
    end

    timingAssistRemaining = math.max(
        0,
        timingAssistRemaining - math.max(0, tonumber(dt) or 0)
    )

    playTimer = playTimer + dt
    directionGlowTimer = math.max(0, directionGlowTimer - dt)
    updateLanePressGlowTimers(dt)
    updateHitEffects(dt)
    if not metaDisplayFinished then
        local safeDt = math.max(0, tonumber(dt) or 0)
        metaDisplayTimer = metaDisplayTimer + safeDt
        if metaDisplayShown and metaDisplayTimer >= getMetaDisplayTotalSeconds() then
            metaDisplayFinished = true
            startDelay = playTimer + musicStartAfterMetaSeconds
        end
    end

    if metaDisplayFinished and playTimer >= startDelay and musicload == 0 then
        bgmSource:play()
        musicload = 1
    end

    if musicload == 1 and not songStarted and bgmSource:isPlaying() then
        songStarted = true
    end

    local songTime = getCurrentSongTime()
    if songTime and songTime >= 0 then
        updateLongHoldJudgements(songTime)
        updateMissJudgements(songTime)
        updateChartGravityEvents(songTime)
        updateNoteDrawQueue(songTime)
        musictime = songTime
    else
        if musicload == 0 then
            local preSongTime = math.min(0, playTimer - (tonumber(startDelay) or 0))
            updateNoteDrawQueue(preSongTime)
            musictime = preSongTime
        else
            for k in pairs(noteDrawQueue) do
                noteDrawQueue[k] = nil
            end
            for k in pairs(notexy) do
                notexy[k] = nil
            end
            for k in pairs(noteRenderStateCache) do
                noteRenderStateCache[k] = nil
            end
        end
    end

    updateLaneGravityAnimation(dt)

    notemove.update(dt)

    if story and story.isConnected and story.isConnected() and story.update then
        story.update(dt, {
            song = musicname,
            score = score,
            combo = combo
        })
    end

    local hold = math.max(0, metaDisplayHoldSeconds)
    local fade = math.max(0.001, metaDisplayFadeSeconds)
    local fadeProgress = clamp01((metaDisplayTimer - hold) / fade)
    alpha = 1 - fadeProgress
    jacketalpha = fadeProgress * 0.1

    if songStarted and not finished then
        if not bgmSource:isPlaying() then
            finished = true
        end
    end

    if finished and songStarted and not resultTransitioned then
        transitionToResult()
        return
    end

end




function play.keypressed(key, scancode, isrepeat)
    if key == "escape" then
        if not bgmSource or musicload ~= 1 or finished then
            return
        end

        if not paused then
            paused = true
            waitingResume = false
            resumeTimer = 0
            clearLaneInputStates()
            pauseMenuButtons = buildPauseMenuButtons()
            bgmSource:pause()
        else
            resumeFromPauseMenu()
        end
        return
    end

    if key == "e" then
        if not bgmSource then
            return
        end
        -- エディタシーンに遷移
        programnumber = 8
        program = nil
        return
    end

    if paused then
        return
    end

    if key == "-" or key == "kp-" then
        baseNoteSpeed = math.max(0.1, baseNoteSpeed - 0.1)
        for _, note in ipairs(chartRuntime.notes) do
            if not note.judged then
                note.scrollSpeed = baseNoteSpeed
            end
        end
        return
    elseif key == "+" or key == "=" or key == "kp+" then
        baseNoteSpeed = math.min(5.0, baseNoteSpeed + 0.1)
        for _, note in ipairs(chartRuntime.notes) do
            if not note.judged then
                note.scrollSpeed = baseNoteSpeed
            end
        end
        return
    end

    local lane = resolveLaneInput(key, scancode)
    if lane then
        setLaneHoldState(lane, true)
        local judgeTime = musictime
        if songStarted and not finished then
            local songTime = getCurrentSongTime()
            if songTime and songTime >= 0 then
                judgeTime = songTime
            end
        end
        if songStarted and not finished then
            handleLaneInputJudge(lane, judgeTime)
        end
        if not isrepeat then
            triggerLanePressGlow(lane)
            local s = noteSE and noteSE[seIndex]
            if s and s.stop and s.play then
                pcall(s.stop, s)
                pcall(s.play, s)
            end
        end
        return
    end

    local normalizedKey = normalizeConfiguredInputToken(key)
    local normalizedScancode = normalizeConfiguredInputToken(scancode)
    local directionActions = {
        moveup = 3,
        movedown = 1,
        moveleft = 2,
        moveright = 4
    }
    for actionName, gravityValue in pairs(directionActions) do
        local token = getConfiguredInputToken(actionName)
        if token and (token == normalizedKey or token == normalizedScancode) then
            lanegravity = gravityValue
            return
        end
    end

    if normalizedKey == "a" then
        lanegravity = 2
    elseif normalizedKey == "s" then
        lanegravity = 1
    elseif normalizedKey == "d" then
        lanegravity = 4
    elseif normalizedKey == "w" then
        lanegravity = 3
    end
end

function play.keyreleased(key, scancode)
    local lane = resolveLaneInput(key, scancode)
    if lane then
        setLaneHoldState(lane, false)
        local releaseTime = musictime
        if songStarted and not finished then
            local songTime = getCurrentSongTime()
            if songTime and songTime >= 0 then
                releaseTime = songTime
            end
        end
        if not paused then
            registerLongHoldRelease(lane, releaseTime)
        end
        local idx = normalizeLaneIndex(lane)
        lanePressGlowTimers[idx] = 0
    end
end









function play.mousepressed(x, y, button)
    if button ~= 1 then
        return
    end
    if not paused then
        return
    end

    pauseMenuButtons = buildPauseMenuButtons()
    for _, b in ipairs(pauseMenuButtons) do
        if pointInPauseShape(x, y, b) then
            if b.action == "resume" then
                resumeFromPauseMenu()
            elseif b.action == "restart" then
                restartFromPauseMenu()
            elseif b.action == "exit" then
                exitFromPauseMenu()
            end
            return
        end
    end
end

function notelane()
    if not laneAnim.initialized then
        updateLaneGravityAnimation(0)
    end
    if not laneAnim.currentLines then
        return
    end

    local drawProgress, laneAlpha = getLineIntroVisual()
    local glow = getDirectionGlow()
    laneAlpha = math.min(1, laneAlpha + glow * 0.22)

    local reverseDirection = (laneAnim.toGravity == 2 or laneAnim.toGravity == 3)
    local laneDir = normalizeLaneGravity(laneAnim.toGravity or lanegravity)

    for lane = 1, activeLaneCount do
        local press = getLanePressGlow(lane)
        if press > 0 then
            local b = getLaneBoundsForGravity(lane, laneDir)
            local w = math.max(1, b.right - b.left)
            local h = math.max(1, b.bottom - b.top)
            local pr, pg, pb = applyBrightness(0.18, 0.72, 1.0, press * 0.35)
            love.graphics.setColor(pr, pg, pb, clamp01(0.06 + press * 0.2))
            love.graphics.rectangle("fill", b.left, b.top, w, h)
        end
    end

    love.graphics.setLineWidth(2)
    local lr, lg, lb = applyBrightness(0.88, 0.88, 0.88, glow * 0.45)
    love.graphics.setColor(lr, lg, lb, laneAlpha)
    for _, line in ipairs(laneAnim.currentLines) do
        drawLaneLineProgress(line, drawProgress, reverseDirection)
    end
    love.graphics.setLineWidth(1)
end

function drawJudgeline()
    if not judgeAnim.initialized then
        updateLaneGravityAnimation(0)
    end
    if not judgeAnim.currentLine then
        return
    end

    local currentSongTime = getCurrentSongTime() or tonumber(musictime) or 0
    drawUpcomingGravityWarning(currentSongTime)

    local drawProgress, lineAlpha = getLineIntroVisual()
    local glow = getDirectionGlow()
    local reverseDirection = (judgeAnim.toGravity == 2 or judgeAnim.toGravity == 3)

    love.graphics.setLineWidth(5)
    local r, g, b = applyBrightness(1, 0.95, 0.35, glow * 0.5)
    love.graphics.setColor(r, g, b, math.min(1, lineAlpha + 0.2 + glow * 0.2))
    drawLaneLineProgress(judgeAnim.currentLine, drawProgress, reverseDirection)
    love.graphics.setLineWidth(1)
end

function drawNotes()
    drawLongNoteBodies(tonumber(musictime) or 0)

    if not noteDrawQueue or #noteDrawQueue == 0 then
        return
    end

    for _, n in ipairs(noteDrawQueue) do
        local alpha = clamp01(n.alpha or 1)
        local noteDir = normalizeNoteGravity(n.dir)
        local tintEnabled = isNoteGravityAlignedWithLane(noteDir, lanegravity)
        local stickLength = n.stickLength or 24
        local stickThickness = n.stickThickness or 8
        local glow = getDirectionGlow()
        local w, h = getNoteVisualSize(noteDir, stickLength, stickThickness)
        local x = n.x - w * 0.5
        local y = n.y - h * 0.5
        drawStylishNote(x, y, w, h, n.type, alpha, glow, tintEnabled, n.lane)
    end
end

function drawJudgeHitEffects()
    if not hitEffects or #hitEffects == 0 then
        return
    end

    local dw, dh = getDisplaySize()
    local maxRectSize = math.max(8, math.min(dw, dh) / 6)

    for _, fx in ipairs(hitEffects) do
        local duration = math.max(0.001, fx.duration or hitEffectDuration)
        local t = clamp01((fx.t or 0) / duration)
        local expand = easeOutCubic(t)
        local fade = clamp01((1 - t) ^ 1.2)
        local halfW = math.max(3, tonumber(fx.halfW) or 10)
        local halfH = math.max(3, tonumber(fx.halfH) or 10)

        local baseW = halfW * 2
        local baseH = halfH * 2
        local maxScaleByW = maxRectSize / math.max(1, baseW)
        local maxScaleByH = maxRectSize / math.max(1, baseH)
        local targetScale = math.max(1, math.min(maxScaleByW, maxScaleByH))
        local scale = 1 + expand * (targetScale - 1)
        local rw = baseW * scale
        local rh = baseH * scale
        local rx = fx.x - rw * 0.5
        local ry = fx.y - rh * 0.5

        love.graphics.setColor(fx.r, fx.g, fx.b, fade * 0.9)
        love.graphics.setLineWidth(2.5)
        love.graphics.rectangle("line", rx, ry, rw, rh)

        love.graphics.setColor(fx.r, fx.g, fx.b, fade * 0.45)
        love.graphics.setLineWidth(1.2)
        love.graphics.rectangle("line", rx - 2, ry - 2, rw + 4, rh + 4)
        love.graphics.setLineWidth(1)
    end
end








local function drawPauseMenu()
    if not paused then
        return
    end

    local w, h = getDisplaySize()
    pauseMenuButtons = buildPauseMenuButtons()
    local mx, my = love.mouse.getPosition()

    love.graphics.setColor(0, 0, 0, 0.58)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local titleText = "PAUSED"
    local title = getSafeFont(titlefont)
    local buttonFont = getSafeFont(pauseMenuButtonFont or lefttitlefont or title)
    local centerY = (pauseMenuButtons[2] and pauseMenuButtons[2].cy) or (h * 0.58)
    local lineStart = math.max(32, w * 0.12)
    local lineEnd = math.min(w - 32, w * 0.88)

    love.graphics.setLineWidth(7)
    love.graphics.setColor(0.16, 0.22, 0.3, 0.88)
    love.graphics.line(lineStart, centerY, lineEnd, centerY)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.8, 0.92, 1, 0.8)
    love.graphics.line(lineStart, centerY, lineEnd, centerY)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(title)
    love.graphics.setColor(0.94, 0.98, 1, 0.96)
    love.graphics.print(titleText, w * 0.5 - title:getWidth(titleText) * 0.5, centerY - math.max(132, h * 0.2))

    local statusFont = getSafeFont(lefttitlefont or buttonFont)
    love.graphics.setFont(statusFont)
    local statusY = centerY - math.max(72, h * 0.11)
    if waitingResume then
        local count = math.max(1, math.ceil(resumeDelay - resumeTimer))
        local statusText = "RESUME IN " .. tostring(count)
        love.graphics.setColor(0.84, 0.94, 1, 0.9)
        love.graphics.print(statusText, w * 0.5 - statusFont:getWidth(statusText) * 0.5, statusY)
    else
        local statusText = "Select Button"
        love.graphics.setColor(0.74, 0.84, 0.94, 0.8)
        love.graphics.print(statusText, w * 0.5 - statusFont:getWidth(statusText) * 0.5, statusY)
    end

    love.graphics.setFont(buttonFont)
    for _, b in ipairs(pauseMenuButtons) do
        local hovered = pointInPauseShape(mx, my, b)
        local cx = b.cx or (b.x + b.w * 0.5)
        local cy = b.cy or (b.y + b.h * 0.5)
        if b.useImage and b.image then
            local scaleMul = hovered and 1.03 or 1.0
            local drawW = b.w * scaleMul
            local drawH = b.h * scaleMul
            local drawX = cx - drawW * 0.5
            local drawY = cy - drawH * 0.5

            love.graphics.setColor(0.16, 0.24, 0.32, hovered and 0.22 or 0.12)
            love.graphics.rectangle("fill", drawX - 4, drawY - 4, drawW + 8, drawH + 8)

            love.graphics.setColor(1, 1, 1, hovered and 1 or 0.94)
            love.graphics.draw(
                b.image,
                drawX,
                drawY,
                0,
                drawW / math.max(1, b.image:getWidth()),
                drawH / math.max(1, b.image:getHeight())
            )

            love.graphics.setColor(0.84, 0.94, 1, hovered and 0.85 or 0.45)
            love.graphics.setLineWidth(hovered and 2 or 1)
            love.graphics.rectangle("line", drawX, drawY, drawW, drawH)
            love.graphics.setLineWidth(1)
        else
            local shapeSize = math.max(10, b.size or math.min(b.w, b.h) * 0.5)
            local glowSize = shapeSize * (hovered and 1.42 or 1.24)

            local baseR, baseG, baseB = 0.24, 0.62, 0.9
            if b.action == "restart" then
                baseR, baseG, baseB = 0.95, 0.72, 0.28
            elseif b.action == "exit" then
                baseR, baseG, baseB = 0.96, 0.38, 0.42
            end

            love.graphics.setColor(baseR, baseG, baseB, hovered and 0.22 or 0.13)
            drawPauseShape("fill", b.shape, cx, cy, glowSize)

            love.graphics.setColor(0.04, 0.06, 0.1, hovered and 0.96 or 0.9)
            drawPauseShape("fill", b.shape, cx, cy, shapeSize)

            love.graphics.setColor(baseR, baseG, baseB, hovered and 1 or 0.8)
            love.graphics.setLineWidth(hovered and 3 or 2)
            drawPauseShape("line", b.shape, cx, cy, shapeSize)
            love.graphics.setLineWidth(1)

            local tx = cx - buttonFont:getWidth(b.label) * 0.5
            local ty = cy + shapeSize + math.max(10, shapeSize * 0.35)
            love.graphics.setColor(1, 1, 1, hovered and 1 or 0.92)
            love.graphics.print(b.label, tx, ty)
        end
    end
end

function drawComboDisplay()
    local w, h = getDisplaySize()
    local safeComboFont = getSafeFont(comboFont)
    local safeLabelFont = getSafeFont(labelFont)
    love.graphics.setFont(safeComboFont)
    local centerX = w * 0.5
    local centerY = h * 0.5

    if combo > 0 then
        local comboText = tostring(combo)
        local textWidth = safeComboFont:getWidth(comboText)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(comboText, centerX - textWidth * 0.5, centerY - 40)

        love.graphics.setFont(safeLabelFont)
        love.graphics.setColor(0.8, 0.9, 1.0, 0.8)
        local labelText = "COMBO"
        local labelWidth = safeLabelFont:getWidth(labelText)
        love.graphics.print(labelText, centerX - labelWidth * 0.5, centerY + 20)
    end

    if story and story.isConnected and story.isConnected() then
        local opponentText = "対戦相手を待っています..."
        if story.opponentName and story.opponentCombo ~= nil then
            opponentText = string.format("%s: %d COMBO", story.opponentName, story.opponentCombo)
        end
        love.graphics.setFont(safeLabelFont)
        love.graphics.setColor(0.75, 0.85, 1, 0.9)
        local textWidth = safeLabelFont:getWidth(opponentText)
        love.graphics.print(opponentText, centerX - textWidth * 0.5, centerY + 68)
    end
end

function drawScoreDisplay()
    local w, h = getDisplaySize()
    local safeScoreFont = getSafeFont(scoreFont)
    love.graphics.setFont(safeScoreFont)
    
    local scoreText = "SCORE: " .. string.format("%06d", score)
    
    -- 右下に表示（余白: 20px）
    local textWidth = safeScoreFont:getWidth(scoreText)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(scoreText, w - textWidth - 20, h - 60)
end

function play.draw()
    musicdatadraw()

    --レーン・判定ライン描画
    notelane()
    drawJudgeline()
    drawNotes()
    drawJudgeHitEffects()
    if timingAssistEnabled
        and lastTimingDeltaMs
        and timingAssistRemaining > 0 then
        local delta = lastTimingDeltaMs
        local label = delta < 0 and "EARLY" or "LATE"
        local text = string.format("%s  %d ms", label, math.floor(math.abs(delta) + 0.5))
        local w, h = getDisplaySize()
        local font = getSafeFont(lefttitlefont or titlefont)
        love.graphics.push("all")
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, math.min(1, timingAssistRemaining))
        love.graphics.printf(text, 0, h * 0.78, w, "center")
        love.graphics.pop()
    end
    
    -- コンボとスコア表示
    drawComboDisplay()
    drawScoreDisplay()
    
    if paused then
        drawPauseMenu()
        return
    end
    --楽曲再開カウント
    if waitingResume then
        local count = math.ceil(resumeDelay - resumeTimer)
        local countText = tostring(count)
        local safeFont = getSafeFont(titlefont)
        love.graphics.setFont(safeFont)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(count, displayx / 2 - safeFont:getWidth(countText) / 2, displayy / 2 - safeFont:getHeight() / 2)
    end

    -- FPS表示
    if settingsdata and settingsdata.playsettings and settingsdata.playsettings.showfps then
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, 0.8)
        local fps = love.timer.getFPS()
        love.graphics.print("FPS: " .. math.floor(fps), 8, 8)
    end
end



function play.quit()
    if bgmSource and bgmSource.stop then
        bgmSource:stop()
    end
    bgmSource = nil
    
    -- ゲーム状態をリセット
    paused = false
    waitingResume = false
    resumeTimer = 0
    musicload = 0
    songStarted = false
    finished = false
    resultTransitioned = false
    
end


return play
