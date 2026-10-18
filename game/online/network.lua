local network = {
    queues = {high = {}, medium = {}, low = {}},
    sequence = 0,
    transport = require "network"
}
local unpack = table.unpack or unpack

function network.configure(options)
    if network.transport and network.transport.configure then
        return network.transport.configure(options)
    end

    if type(options) == "table" and options.serverURL ~= nil then
        network.transport.SERVER_URL = tostring(options.serverURL)
    end

    return true
end

function network.setServerURL(url)
    if network.transport and network.transport.setServerURL then
        return network.transport.setServerURL(url)
    end

    network.transport.SERVER_URL = tostring(url)
    return true
end

function network.getServerURL()
    if network.transport and network.transport.getServerURL then
        return network.transport.getServerURL()
    end

    return network.transport.SERVER_URL or ""
end

function network.setTransport(transport)
    network.transport = transport
end

function network.enqueue(data, priority)
    local queue = network.queues[priority or "medium"] or network.queues.medium
    network.sequence = network.sequence + 1
    queue[#queue + 1] = {sequence = network.sequence, data = data}
end

function network.send(typeName, ...)
    local priority = "medium"
    if typeName == "JUDGMENT" or typeName == "ONLINE_JUDGMENT" then
        priority = "high"
    elseif typeName == "POSITION" or typeName == "ONLINE_POSITION" then
        priority = "low"
    end
    network.enqueue({typeName = typeName, args = {...}}, priority)
    return true
end

local function flush(limit)
    local remaining = limit or 8
    for _, priority in ipairs({"high", "medium", "low"}) do
        local queue = network.queues[priority]
        while remaining > 0 and #queue > 0 do
            local item = table.remove(queue, 1)
            if network.transport and network.transport.send and type(item.data) == "table" then
                network.transport.send(item.data.typeName, unpack(item.data.args or {}))
            end
            remaining = remaining - 1
        end
    end
end

function network.update()
    if network.transport and network.transport.update then
        network.transport.update()
    end
    flush(8)
end

function network.host(urlOrConfig)
    if network.transport and network.transport.host then
        return network.transport.host(urlOrConfig)
    end

    return false
end

function network.join(roomID, urlOrConfig)
    if network.transport and network.transport.join then
        return network.transport.join(roomID, urlOrConfig)
    end

    return false
end

function network.close(sendDisconnect)
    network.queues = {high = {}, medium = {}, low = {}}
    return network.transport.close(sendDisconnect)
end

function network.isConnected()
    return network.transport.isConnected()
end

function network.on(event, callback)
    return network.transport.on(event, callback)
end

function network.getError()
    return network.transport.getError()
end

function network.getPlayerID()
    return network.transport.getPlayerID()
end

function network.getRoomID()
    return network.transport.getRoomID()
end

function network.getPartyCount()
    return network.transport.getPartyCount()
end

function network.getPartyPlayers()
    return network.transport.getPartyPlayers()
end

return network