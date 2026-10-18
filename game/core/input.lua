local input = {
    down = {},
    pressed = {},
    released = {},
    target = nil
}

function input.setTarget(target)
    input.target = target
end

function input.isDown(key)
    return input.down[key] == true
end

function input.consumePressed(key)
    local value = input.pressed[key] == true
    input.pressed[key] = nil
    return value
end

function input.keypressed(key, scancode, isrepeat)
    input.down[key] = true
    input.pressed[key] = true
    if key == "f7" then
        require("core.audio").changeVolume(-0.1)
        return true
    elseif key == "f8" then
        require("core.audio").changeVolume(0.1)
        return true
    elseif key == "f9" then
        require("core.audio").toggleMute()
        return true
    end
    if input.target and input.target.keypressed then
        input.target.keypressed(key, scancode, isrepeat)
    end
    return false
end

function input.keyreleased(key, scancode)
    input.down[key] = nil
    input.released[key] = true
    if input.target and input.target.keyreleased then
        input.target.keyreleased(key, scancode)
    end
end

function input.update()
    input.pressed = {}
    input.released = {}
end

return input