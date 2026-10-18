local packet = require "online.online_packet"

local sync = {lastSent = 0, interval = 0.1}

function sync.send(network, position, now, sequence)
    if (now or 0) - sync.lastSent < sync.interval then
        return false
    end
    sync.lastSent = now or 0
    local encoded = packet.encode("SYNC", {position = position}, sequence)
    if encoded then
        network.enqueue(encoded, "low")
    end
    return encoded ~= nil
end

return sync