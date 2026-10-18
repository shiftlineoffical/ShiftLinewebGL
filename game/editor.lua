--[[
エディタモード - 譜面編集用
Play画面でEキーを押すことで遷移
- 譜面は自動で流れない
- スペースキーでスタート
- F1でオートプレイ切り替え
- Qでその楽曲SFLだけを再読み込み
]]

---@diagnostic disable: undefined-global
local editor = {}
local log = require "log"

-- エディタ固有の状態
local editorAutoplay = false
local editorStarted = false

local function resetEditorChartPlayback()
    chartRuntime.currentIndex = 1
    chartRuntime.nextGravityEventIndex = 1
    noteDrawQueue = {}
    noteRenderStateCache = {}
    notexy = {}
    hitEffects = {}
    clearLaneInputStates()

    for _, note in ipairs(chartRuntime.notes or {}) do
        note.judged = nil
        note.hit = nil
        note.judgeDeltaMs = nil
        note.judgedTime = nil
        note.fixedJudgeLinePos = nil
    end
end

-- 初期化
function editor.load()
    editorAutoplay = false
    editorStarted = false
    
    -- play モジュールの必要な変数を初期化
    alpha = 0
    jacketalpha = 0
    playTimer = 0
    metaDisplayTimer = 0
    metaDisplayShown = false
    metaDisplayFinished = false
    musicload = 1  -- editor では常に musicload = 1
    songStarted = false
    jacketimg = nil
    musictime = 0
    musictimer = 0
    finished = false
    resultTransitioned = false
    paused = false
    waitingResume = false
    resumeTimer = 0
    pauseMenuButtons = {}
    lanegravity = 1
    notegravity = 1
    
    -- levelColors を初期化（play.lua の levelColors と同じ）
    levelColors = levelColors or {
        easy = {0.1, 1, 0.1},
        normal = {0.5, 0.5, 1},
        hard = {1, 1, 0},
        extra = {1, 0.1, 0.1},
        default = {0.5, 0.1, 0.5}
    }
    
    log.info("エディタモード起動")
end

-- 更新
function editor.update(dt)
    if not bgmSource then
        return
    end

    if editorStarted then
        if not songStarted and bgmSource.isPlaying and bgmSource:isPlaying() then
            songStarted = true
        end

        local songTime = nil
        if songStarted then
            songTime = getCurrentSongTime()
        end

        if songTime then
            updateChartGravityEvents(songTime)
            updateNoteDrawQueue(songTime)
            musictime = songTime
        else
            musictime = bgmSource:tell("seconds") or musictime
        end

        musictimer = musictimer + dt
    end
end

-- 描画
function editor.draw()
    -- play と同じ描画ロジック
    musicdatadraw()
    
    -- レーン・判定ライン描画
    notelane()
    drawJudgeline()
    drawNotes()
    drawJudgeHitEffects()
    
    -- コンボとスコア表示
    drawComboDisplay()
    drawScoreDisplay()
    
    -- エディタ情報表示
    drawEditorInfo()
end

-- エディタ情報を画面に表示
function drawEditorInfo()
    love.graphics.setColor(1, 1, 1, 0.8)
    local baseFont = love.graphics.getFont()
    love.graphics.setFont(baseFont)
    
    local infoText = "--- エディタモード ---"
    love.graphics.print(infoText, 10, 10)
    
    local statusText = "状態: "
    if editorStarted then
        if editorAutoplay then
            statusText = statusText .. "プレイ中 (オートプレイ: ON)"
        else
            statusText = statusText .. "プレイ中 (オートプレイ: OFF)"
        end
    else
        statusText = statusText .. "停止中"
    end
    love.graphics.print(statusText, 10, 30)
    
    local controlText = "[SPACE] スタート  [F1] オートプレイ切替  [Q] SFL再読込  [F10] コンソール  [ESC] 終了"
    love.graphics.print(controlText, 10, 50)
    
    if bgmSource then
        local timeText = string.format("再生時間: %.2f秒", musictime)
        love.graphics.print(timeText, 10, 70)
    end
end

-- キー入力処理
function editor.keypressed(key, scancode, isrepeat)
    if key == "escape" then
        -- エディタを終了して play に戻る
        if bgmSource then
            bgmSource:stop()
        end
        programnumber = 4  -- play に戻る
        program = nil
        return
    end
    
    if key == "space" then
        -- スタート/ストップ
        if not bgmSource or musicload ~= 1 then
            return
        end
        
        if not editorStarted then
            -- スタート
            editorStarted = true
            songStarted = false
            finished = false
            musictime = 0
            resetEditorChartPlayback()
            if bgmSource then
                bgmSource:stop()
                local okSeek = pcall(bgmSource.seek, bgmSource, 0, "seconds")
                if not okSeek then
                    pcall(bgmSource.seek, bgmSource, 0)
                end
                bgmSource:play()
                songStarted = true
            end
        else
            -- 停止
            editorStarted = false
            if bgmSource then
                bgmSource:pause()
            end
        end
        return
    end
    
    if key == "f1" then
        -- オートプレイ切り替え
        editorAutoplay = not editorAutoplay
        log.info("オートプレイ: " .. (editorAutoplay and "ON" or "OFF"))
        return
    end
    
    if key == "q" then
        -- SFL ファイルを再読み込み
        reloadCurrentChart()
        return
    end
    
    -- 重力変更キー（楽曲視点の切り替え）
    if key == "a" then
        lanegravity = 2
    elseif key == "s" then
        lanegravity = 1
    elseif key == "d" then
        lanegravity = 4
    elseif key == "w" then
        lanegravity = 3
    end
end

-- キー離し処理
function editor.keyreleased(key, scancode)
    -- エディタではキー離しの特殊処理は不要
end

-- マウス入力処理（不使用）
function editor.mousepressed(x, y, button)
    -- エディタではマウス入力は不使用
end

-- マウスホイール処理 - 一小節ごとに進む/戻す
function editor.wheelmoved(x, y)
    if not editorStarted or not bgmSource then
        return
    end
    
    -- BPM を取得（デフォルト 120）
    local bpm = 120
    if chartRuntime and chartRuntime.chart and chartRuntime.chart.bpm then
        bpm = tonumber(chartRuntime.chart.bpm) or 120
    end
    
    -- 一小節の時間（秒）= (60 / BPM) * 4 = 240 / BPM
    local measureTime = 240 / math.max(1, bpm)
    
    -- マウスホイール値（y > 0 なら上に回す = 時間進む）
    local measureCount = math.floor(math.abs(y))
    local delta = (y > 0) and (measureCount * measureTime) or -(measureCount * measureTime)
    
    -- 新しい再生位置
    local newTime = math.max(0, musictime + delta)
    musictime = newTime
    
    -- bgmSource を新しい位置にシーク
    if bgmSource then
        local okSeek = pcall(bgmSource.seek, bgmSource, newTime, "seconds")
        if not okSeek then
            pcall(bgmSource.seek, bgmSource, newTime)
        end
    end
end

-- 終了処理
function editor.quit()
    editorAutoplay = false
    editorStarted = false
    
    if bgmSource then
        bgmSource:stop()
    end
end

return editor

