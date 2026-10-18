local audio = {
    muted = false,
    volume = 1,
    current = nil
}

local function applyVolume()
    love.audio.setVolume(audio.muted and 0 or audio.volume)
end

function audio.setVolume(value)
    audio.volume = math.max(0, math.min(1, tonumber(value) or audio.volume))
    applyVolume()
    return audio.volume
end

function audio.changeVolume(delta)
    return audio.setVolume(audio.volume + (tonumber(delta) or 0))
end

function audio.setMuted(value)
    audio.muted = value == true
    applyVolume()
    return audio.muted
end

function audio.toggleMute()
    return audio.setMuted(not audio.muted)
end

function audio.play(source, loop)
    if not source then
        return false
    end
    audio.current = source
    if source.setLooping then
        source:setLooping(loop == true)
    end
    source:play()
    return true
end

function audio.stop(source)
    local target = source or audio.current
    if target and target.stop then
        target:stop()
    end
    if target == audio.current then
        audio.current = nil
    end
end

function audio.pause(source)
    local target = source or audio.current
    if target and target.pause then
        target:pause()
    end
end

function audio.resume(source)
    local target = source or audio.current
    if target and target.play then
        target:play()
    end
end

function audio.getPosition(source)
    local target = source or audio.current
    if target and target.tell then
        return target:tell()
    end
    return 0
end

return audio