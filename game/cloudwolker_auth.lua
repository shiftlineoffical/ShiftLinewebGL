local cloudwolker_auth = {}

local SDK = nil

local function getSDK()
    if SDK then
        return SDK
    end

    local ok, mod = pcall(require, "lib.SDK")
    if ok and mod then
        SDK = mod
    end

    return SDK
end

local function syncState()
    local sdk = getSDK()
    local state = "unavailable"

    if sdk and type(sdk.getAuthState) == "function" then
        state = sdk.getAuthState()
    end

    cloudwolker_auth.enabled =
        sdk ~= nil
        and type(sdk.isAvailable) == "function"
        and sdk.isAvailable() == true

    cloudwolker_auth.authenticated = state == "ready"
    cloudwolker_auth.loading =
        state == "authorizing"
        or state == "authenticating"
        or state == "connecting"
    cloudwolker_auth.error = nil
    cloudwolker_auth.provider = "discord"

    if type(App) == "table" and type(App.login) == "table" then
        cloudwolker_auth.user = {
            id = App.login.userId or App.login.userid or "",
            displayName = App.login.username or "",
            avatarUrl = App.login.avatarUrl or "",
        }
        cloudwolker_auth.sessionToken = App.login.user_token or nil
        cloudwolker_auth.expiresAt = App.login.expiresAt or 0
    else
        cloudwolker_auth.user = nil
        cloudwolker_auth.sessionToken = nil
        cloudwolker_auth.expiresAt = 0
    end

    return state
end

cloudwolker_auth.enabled = false
cloudwolker_auth.authenticated = false
cloudwolker_auth.loading = false
cloudwolker_auth.error = nil
cloudwolker_auth.user = nil
cloudwolker_auth.provider = "discord"
cloudwolker_auth.sessionToken = nil
cloudwolker_auth.expiresAt = 0

function cloudwolker_auth.isEnabled()
    local sdk = getSDK()
    if not sdk or type(sdk.isAvailable) ~= "function" then
        return false
    end

    return sdk.isAvailable() == true
end

function cloudwolker_auth.isAuthenticated()
    local sdk = getSDK()
    if not sdk or type(sdk.getAuthState) ~= "function" then
        return false
    end

    return sdk.getAuthState() == "ready"
end

function cloudwolker_auth.isLoading()
    local sdk = getSDK()
    if not sdk or type(sdk.getAuthState) ~= "function" then
        return false
    end

    local state = sdk.getAuthState()
    return state == "authorizing"
        or state == "authenticating"
        or state == "connecting"
end

function cloudwolker_auth.getUser()
    if type(App) == "table" and type(App.login) == "table" then
        return {
            id = App.login.userId or App.login.userid or "",
            displayName = App.login.username or "",
            avatarUrl = App.login.avatarUrl or "",
        }
    end

    local sdk = getSDK()
    if sdk and type(sdk.getFriends) == "function" then
        local friends, message = sdk.getFriends()
        if type(friends) == "table" and #friends > 0 then
            return friends[1]
        end
    end

    return nil
end

function cloudwolker_auth.getToken()
    if type(App) == "table" and type(App.login) == "table" then
        return App.login.user_token or nil
    end

    return nil
end

function cloudwolker_auth.getProvider()
    return "discord"
end

function cloudwolker_auth.getError()
    return cloudwolker_auth.error
end

function cloudwolker_auth.getExpiresAt()
    return cloudwolker_auth.expiresAt or 0
end

function cloudwolker_auth.startDiscordLogin()
    local sdk = getSDK()
    if not sdk or type(sdk.authorize) ~= "function" then
        return false, "Discord SDK is unavailable"
    end

    local ok = sdk.authorize()
    syncState()
    return ok, ok and nil or "Discord SDK authorization failed"
end

function cloudwolker_auth.startXLogin()
    return false, "X OAuth is not implemented by the Discord bridge"
end

function cloudwolker_auth.handleCallback(url)
    return false, "Discord SDK authorization does not use shiftline:// callback flow"
end

function cloudwolker_auth.pollCallback()
    local sdk = getSDK()
    if sdk and type(sdk.updateCallback) == "function" then
        pcall(sdk.updateCallback)
    end
    return nil
end

function cloudwolker_auth.getFriends()
    local sdk = getSDK()
    if not sdk or type(sdk.getFriends) ~= "function" then
        return nil, "Discord SDK is unavailable"
    end

    return sdk.getFriends()
end

function cloudwolker_auth.sendActivityInvite(userId, message)
    local sdk = getSDK()
    if not sdk or type(sdk.sendActivityInvite) ~= "function" then
        return false
    end

    return sdk.sendActivityInvite(userId, message)
end

function cloudwolker_auth.logout()
    local sdk = getSDK()
    if sdk and type(sdk.logout) == "function" then
        sdk.logout()
    end

    syncState()
end

syncState()

return cloudwolker_auth
