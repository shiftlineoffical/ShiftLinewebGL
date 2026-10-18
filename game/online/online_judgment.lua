local packet = require "online.online_packet"

return function(network, result, playerId, sequence)
    local payload = {
        playerId = playerId,
        lane = result.lane,
        judgment = result.judgment,
        noteId = result.noteId,
        sequence = sequence
    }
    local encoded = packet.encode("JUDGMENT", payload, sequence)
    if encoded then
        network.enqueue(encoded, "high")
    end
    return encoded
end