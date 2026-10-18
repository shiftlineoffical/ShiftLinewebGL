local effects = {
    active = {}
}

function effects.push(kind, payload, duration)
    effects.active[#effects.active + 1] = {
        kind = kind,
        payload = payload,
        remaining = duration or 0.2
    }
end

function effects.update(dt)
    local write = 1
    for read = 1, #effects.active do
        local effect = effects.active[read]
        effect.remaining = effect.remaining - dt
        if effect.remaining > 0 then
            effects.active[write] = effect
            write = write + 1
        end
    end
    for index = write, #effects.active do
        effects.active[index] = nil
    end
end

return effects