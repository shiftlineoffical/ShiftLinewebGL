local i18n = {}

local localeTexts = {
    jp = {
        clickToStart = "click to start",
        exit = "Exit",
        login = "ログイン",
        autoLogin = "自動でログインする",
        modeSolo = "ソロプレイ",
        modeStory = "ストーリー",
        modeOnline = "オンライン",
        modeSettings = "設定",
        modeTitle = "タイトルへ",
        play = "Play",
        result = "RESULT",
        levelPrefix = "LEVEL ",
        score = "SCORE",
        totalNotes = "TOTAL NOTES  ",
        maxCombo = "MAX COMBO",
        accuracy = "ACCURACY",
        rank = "RANK",
        perfect = "Perfect",
        good = "Good",
        bad = "Bad",
        miss = "Miss",
        retryHint = "R : RETRY",
        musicSelectHint = "ENTER / ESC : MUSIC SELECT",
        retry = "RETRY",
        musicSelect = "MUSIC SELECT",
        ratingAverage = "RATING",
        songRate = "SONG RATE",
        bestRating = "BEST",
        resume = "Resume",
        restart = "Restart",
    },
    en = {
        clickToStart = "click to start",
        exit = "Exit",
        login = "Login",
        autoLogin = "Remember me",
        modeSolo = "Solo",
        modeStory = "Story",
        modeOnline = "Online",
        modeSettings = "Settings",
        modeTitle = "Title",
        play = "Play",
        result = "RESULT",
        levelPrefix = "LEVEL ",
        score = "SCORE",
        totalNotes = "TOTAL NOTES  ",
        maxCombo = "MAX COMBO",
        accuracy = "ACCURACY",
        rank = "RANK",
        perfect = "Perfect",
        good = "Good",
        bad = "Bad",
        miss = "Miss",
        retryHint = "R : RETRY",
        musicSelectHint = "ENTER / ESC : MUSIC SELECT",
        retry = "RETRY",
        musicSelect = "MUSIC SELECT",
        ratingAverage = "RATING",
        songRate = "SONG RATE",
        bestRating = "BEST",
        resume = "Resume",
        restart = "Restart",
    }
}

local function getLanguage()
    local settings = package.loaded["settings"]
    if not settings then
        local ok, settingsModule = pcall(require, "settings")
        if ok and type(settingsModule) == "table" then
            settings = settingsModule
        end
    end
    if type(settings) == "table" and type(settings.settingsdata) == "table" then
        local misc = settings.settingsdata.miscsettings
        if type(misc) == "table" and type(misc.language) == "string" then
            return misc.language
        end
    end
    return "jp"
end

function i18n.t(key)
    local lang = getLanguage()
    local locale = localeTexts[lang] or localeTexts.jp
    return locale[key] or localeTexts.jp[key] or key
end

function i18n.tf(key, ...)
    local text = i18n.t(key)
    if select("#", ...) == 0 then
        return text
    end
    return string.format(text, ...)
end

function i18n.getLanguage()
    return getLanguage()
end

return i18n
