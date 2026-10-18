function love.conf(t)

    -- アプリ基本情報
    t.identity = "ShiftLine"
    t.version = "11.5"
    t.console = false

    -- ウィンドウ設定（display）
    t.window.title = "ShiftLine"
    t.window.vsync = 1
    -- モジュールの有効化（modules）
    t.modules.audio = true
    t.modules.event = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false
    t.modules.sound = true
    t.modules.system = true
    t.modules.timer = true
    t.modules.window = true
    -- その他の設定
    t.externalstorage = true
    t.accelerometerjoystick = true
    t.gammacorrect = true
end