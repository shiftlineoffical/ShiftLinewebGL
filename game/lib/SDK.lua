local SDK = {}
local log = require "log"
local ffiOk, ffi = pcall(require, "ffi")
local native
local initialized = false
local lastLoggedError
local callbackFrameCount = 0

if ffiOk then
    local declared, declarationError = pcall(ffi.cdef, [[
        int shiftline_discord_init(const char *application_id);
        int shiftline_discord_update_callback(void);
        int shiftline_discord_set_rich_presence(
            const char *details,
            const char *state,
            unsigned long long start_timestamp_seconds,
            const char *large_image,
            const char *large_image_text,
            const char *small_image,
            const char *small_image_text,
            const char *party_id,
            int party_size,
            int party_max,
            const char *join_secret
        );
        int shiftline_discord_clear_rich_presence(void);
        int shiftline_discord_register_launch_command(const char *command);
        int shiftline_discord_poll_join_secret(char *output, int capacity);
        int shiftline_discord_poll_log(int *severity, char *output, int capacity);
        int shiftline_discord_is_available(void);
        int shiftline_discord_is_connected(void);
        int shiftline_discord_authorize(void);
        int shiftline_discord_logout(void);
        int shiftline_discord_get_auth_state(void);
        int shiftline_discord_get_friend_count(void);
        int shiftline_discord_get_friend(
            int friend_index,
            char *user_id,
            int user_id_capacity,
            char *display_name,
            int display_name_capacity,
            int *status
        );
        int shiftline_discord_send_activity_invite(const char *user_id, const char *message);
        int shiftline_discord_poll_activity_invite(
            unsigned long long *invite_id,
            char *sender_id,
            int sender_id_capacity,
            char *sender_name,
            int sender_name_capacity,
            int *invite_type
        );
        int shiftline_discord_respond_activity_invite(unsigned long long invite_id, int accept);
        int shiftline_discord_get_last_error(char *output, int capacity);
        void shiftline_discord_shutdown(void);
    ]])
    if not declared then
        ffiOk = false
        log.warn("Discord Social SDK: FFI declarations unavailable: " .. tostring(declarationError))
    end
end

local function takeNativeError()
    if not native then
        return nil
    end
    local buffer = ffi.new("char[1024]")
    local ok, length = pcall(native.shiftline_discord_get_last_error, buffer, 1024)
    if ok and length > 0 then
        return ffi.string(buffer)
    end
    return nil
end

local function reportError(message)
    message = tostring(message)
    if message ~= lastLoggedError then
        log.warn("Discord Social SDK: " .. message)
        lastLoggedError = message
    end
end

local function callNative(name, ...)
    if not native then
        return false, "bridge is unavailable"
    end
    return pcall(native[name], ...)
end

local function checkResult(name, ...)
    local ok, result = callNative(name, ...)
    if not ok then
        reportError(result)
        return false
    end
    if result == 0 then
        reportError(takeNativeError() or (name .. " failed"))
        return false
    end
    lastLoggedError = nil
    return true
end

function SDK.start(applicationId)
    if initialized then
        log.debug("Discord Social SDK: start skipped; already initialized")
        return true
    end

    log.trace("Discord Social SDK: loading bridge for Application ID", tostring(applicationId))
    if not ffiOk or ffi.os ~= "Windows" then
        reportError("Windows LuaJIT FFI is unavailable")
        return false
    end

    local loaded, library = pcall(ffi.load, "shiftline_discord_bridge")
    if not loaded then
        reportError("bridge DLL could not be loaded: " .. tostring(library))
        return false
    end

    native = library
    if not checkResult("shiftline_discord_init", tostring(applicationId)) then
        native = nil
        return false
    end
    initialized = true
    callbackFrameCount = 0
    log.info("Discord Social SDK: initialized")
    return true
end

function SDK.update(presence)
    if not initialized or type(presence) ~= "table" then
        return false
    end

    return checkResult(
        "shiftline_discord_set_rich_presence",
        presence.details,
        presence.state,
        presence.startTimestamp or 0,
        presence.largeImageKey,
        presence.largeImageText,
        presence.smallImageKey,
        presence.smallImageText,
        presence.partyId,
        presence.partySize or 1,
        presence.partyMax or 0,
        presence.joinSecret
    )
end

SDK.setRichPresence = SDK.update

function SDK.clearRichPresence()
    if not initialized then
        return false
    end
    log.info("Discord Social SDK: clearing Rich Presence")
    return checkResult("shiftline_discord_clear_rich_presence")
end

function SDK.updateCallback()
    if not initialized then
        return false
    end

    local ok, result = callNative("shiftline_discord_update_callback")
    if not ok or result == 0 then
        reportError((not ok and result) or takeNativeError() or "callback processing failed")
        return false
    end

    local message = ffi.new("char[2048]")
    local severity = ffi.new("int[1]")
    local severityNames = {
        [1] = "trace",
        [2] = "info",
        [3] = "warn",
        [4] = "error"
    }
    for _ = 1, 64 do
        local logOk, found = callNative("shiftline_discord_poll_log", severity, message, 2048)
        if not logOk then
            reportError(found)
            break
        end
        if found == 0 then
            break
        elseif found < 0 then
            reportError("SDK log queue returned an invalid result")
            break
        end
        local level = severityNames[tonumber(severity[0])] or "debug"
        log[level]("Discord Social SDK:", ffi.string(message))
    end

    local callbackError = takeNativeError()
    if callbackError then
        reportError(callbackError)
    end
    callbackFrameCount = callbackFrameCount + 1
    if callbackFrameCount % 300 == 0 then
    end
    return true
end

function SDK.pollEvent()
    if not initialized then
        return nil
    end

    local inviteId = ffi.new("unsigned long long[1]")
    local senderId = ffi.new("char[32]")
    local senderName = ffi.new("char[256]")
    local inviteType = ffi.new("int[1]")
    local inviteOk, inviteFound = callNative(
        "shiftline_discord_poll_activity_invite",
        inviteId,
        senderId,
        32,
        senderName,
        256,
        inviteType
    )
    if not inviteOk then
        reportError(inviteFound)
        return nil
    end
    if inviteFound == 1 then
        return {
            type = "activity_invite",
            id = tonumber(inviteId[0]),
            senderId = ffi.string(senderId),
            senderName = ffi.string(senderName),
            action = tonumber(inviteType[0])
        }
    elseif inviteFound < 0 then
        reportError("invalid Activity Invite event")
        return nil
    end

    local buffer = ffi.new("char[512]")
    local ok, found = callNative("shiftline_discord_poll_join_secret", buffer, 512)
    if not ok then
        reportError(found)
        return nil
    end
    if found == 1 then
        log.info("Discord Social SDK: activity join callback received")
        return {type = "join", secret = ffi.string(buffer)}
    end
    return nil
end

function SDK.respondToActivityInvite(inviteId, accept)
    if not initialized or type(inviteId) ~= "number" then
        return false
    end
    log.info("Discord Social SDK: Activity Invite response", accept and "accepted" or "dismissed")
    return checkResult(
        "shiftline_discord_respond_activity_invite",
        inviteId,
        accept and 1 or 0
    )
end

function SDK.registerLaunchCommand(command)
    if not initialized then
        return false
    end
    log.debug("Discord Social SDK: registering launch command")
    local registered = checkResult("shiftline_discord_register_launch_command", command)
    if registered then
        log.info("Discord Social SDK: launch command registered")
    end
    return registered
end

function SDK.isAvailable()
    if not initialized then
        return false
    end
    local ok, available = callNative("shiftline_discord_is_available")
    return ok and available == 1
end

function SDK.isConnected()
    if not initialized then
        return false
    end
    local ok, connected = callNative("shiftline_discord_is_connected")
    return ok and connected == 1
end

function SDK.getAuthState()
    if not initialized then
        return "unavailable"
    end
    local ok, state = callNative("shiftline_discord_get_auth_state")
    if not ok then
        reportError(state)
        return "failed"
    end
    local states = {
        [0] = "unauthenticated",
        [1] = "authorizing",
        [2] = "authenticating",
        [3] = "connecting",
        [4] = "ready",
        [5] = "failed"
    }
    return states[tonumber(state)] or "unknown"
end

function SDK.authorize()
    if not initialized then
        return false
    end
    log.info("Discord Social SDK: authorization requested")
    return checkResult("shiftline_discord_authorize")
end

function SDK.logout()
    if not initialized then
        return false
    end
    log.info("Discord Social SDK: logout requested")
    return checkResult("shiftline_discord_logout")
end

function SDK.getFriends()
    if not initialized then
        return nil, "Discord Social SDK is unavailable"
    end

    local ok, count = callNative("shiftline_discord_get_friend_count")
    if not ok or count < 0 then
        local message = (not ok and count) or takeNativeError() or "friend list is not ready"
        reportError(message)
        return nil, tostring(message)
    end

    local friends = {}
    local userId = ffi.new("char[32]")
    local displayName = ffi.new("char[256]")
    local status = ffi.new("int[1]")
    local statuses = {
        [0] = "online",
        [1] = "offline",
        [2] = "blocked",
        [3] = "idle",
        [4] = "dnd",
        [5] = "invisible",
        [6] = "streaming",
        [7] = "unknown"
    }

    for index = 0, count - 1 do
        local foundOk, found = callNative(
            "shiftline_discord_get_friend",
            index,
            userId,
            32,
            displayName,
            256,
            status
        )
        if not foundOk then
            reportError(found)
            return nil, tostring(found)
        end
        if found == 1 then
            friends[#friends + 1] = {
                id = ffi.string(userId),
                name = ffi.string(displayName),
                status = statuses[tonumber(status[0])] or "unknown"
            }
        end
    end
    log.debug("Discord Social SDK: loaded friend records", #friends)
    return friends
end

function SDK.sendActivityInvite(userId, message)
    if not initialized or type(userId) ~= "string" then
        return false
    end
    log.info("Discord Social SDK: sending activity invite")
    return checkResult("shiftline_discord_send_activity_invite", userId, message or "")
end

function SDK.shutdown()
    if not initialized then
        return false
    end

    log.info("Discord Social SDK: shutting down")
    local ok, shutdownError = callNative("shiftline_discord_shutdown")
    if not ok then
        reportError(shutdownError)
    end
    native = nil
    initialized = false
    return ok
end

return SDK
