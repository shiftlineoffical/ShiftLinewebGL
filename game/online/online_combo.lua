local packet = require "online.online_packet"

return function(network, combo, sequence)
    local encoded = packet.encode("COMBO", {combo = combo}, sequence)
    if encoded then
        network.enqueue(encoded, "medium")
    end
    return encoded
end