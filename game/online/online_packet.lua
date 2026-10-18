local JSON = require "JSON"
local packet = {
    types = {HANDSHAKE = true, IDENTITY = true, ROOM = true, GAMEPLAY = true, JUDGMENT = true, COMBO = true, SCORE = true, SYNC = true, PING = true, PONG = true, SYSTEM = true}
}

function packet.encode(kind, payload, sequence)
    if not packet.types[kind] then
        return nil, "unknown packet type"
    end
    return JSON:encode({type = kind, sequence = sequence or 0, payload = payload or {}})
end

function packet.decode(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local value = JSON:decode(raw)
    if type(value) ~= "table" or not packet.types[value.type] then
        return nil
    end
    return value
end

return packet