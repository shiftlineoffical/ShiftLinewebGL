local online_connect = {
    isHosting=false,
    roomID="",
}

local network=require("online.network")

local mode = "offline"

function online_connect.hosting()
    mode = "hosting"
    local connected = network.host()

    online_connect.isHosting = connected
    online_connect.roomID = connected and network.getRoomID() or ""

    if not connected then
        mode = "offline"
        return false, network.getError()
    end

    return true, online_connect.roomID
end

function online_connect.joining(roomID)
    mode = "joining"

    local connected = network.join(roomID)

    online_connect.isHosting = false
    online_connect.roomID = connected and network.getRoomID() or ""

    if not connected then
        mode = "offline"
        return false, network.getError()
    end

    return true
end

function online_connect.update()
    network.update()
end

function online_connect.close(sendDisconnect)
    network.close(sendDisconnect)
    mode = "offline"
    online_connect.isHosting = false
    online_connect.roomID = ""
end

function online_connect.isConnected()
    return network.isConnected()
end

function online_connect.getError()
    return network.getError()
end

function online_connect.on(event, callback)
    return network.on(event, callback)
end

function online_connect.send(typeName, ...)
    return network.send(typeName, ...)
end

function online_connect.getPartyCount()
    return network.getPartyCount()
end

function online_connect.getPartyPlayers()
    if network.getPartyPlayers then
        return network.getPartyPlayers()
    end
    return {}
end

function online_connect.getPlayerCount()
    return network.getPartyCount()
end

function online_connect.getMode()
    return mode
end

function online_connect.getPlayerID()
    return network.getPlayerID()
end

function online_connect.getRoomID()
    return online_connect.roomID ~= "" and online_connect.roomID
        or network.getRoomID()
        or ""
end

function online_connect.getIsHosting()
    return online_connect.isHosting == true
end







return online_connect