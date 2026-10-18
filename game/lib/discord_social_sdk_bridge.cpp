#define DISCORDPP_IMPLEMENTATION
#include "../discord_social_sdk/discordpp.h"

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <exception>
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <windows.h>
#include <wincred.h>

#define SHIFTLINE_EXPORT extern "C" __declspec(dllexport)
#define SHIFTLINE_CALL __cdecl

namespace {

std::unique_ptr<discordpp::Client> client;
uint64_t applicationId = 0;
std::atomic<int> authState{0};
std::mutex errorMutex;
std::mutex joinMutex;
std::mutex sdkLogMutex;
std::mutex inviteMutex;
std::string lastError;
std::deque<std::string> joinSecrets;

struct SdkLogEntry {
    int severity;
    std::string message;
};

std::deque<SdkLogEntry> sdkLogs;
std::string refreshToken;

struct PendingActivityInvite {
    uint64_t id;
    uint64_t senderId;
    int type;
    bool delivered;
    discordpp::ActivityInvite invite;
};

std::deque<PendingActivityInvite> activityInvites;
uint64_t nextActivityInviteId = 1;

void setError(const std::string& message)
{
    std::lock_guard<std::mutex> lock(errorMutex);
    lastError = message;
}

void clearError()
{
    std::lock_guard<std::mutex> lock(errorMutex);
    lastError.clear();
}

void queueSdkLog(int severity, const std::string& message)
{
    std::lock_guard<std::mutex> lock(sdkLogMutex);
    if (sdkLogs.size() >= 512) {
        sdkLogs.pop_front();
    }
    sdkLogs.push_back({severity, message});
}

bool parseApplicationId(const char* value, uint64_t& parsed)
{
    if (value == nullptr || *value == '\0') {
        return false;
    }

    for (const unsigned char* character = reinterpret_cast<const unsigned char*>(value);
         *character != '\0';
         ++character) {
        if (*character < '0' || *character > '9') {
            return false;
        }
    }

    errno = 0;
    char* end = nullptr;
    const unsigned long long result = std::strtoull(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || result == 0) {
        return false;
    }

    parsed = static_cast<uint64_t>(result);
    return true;
}

std::optional<std::string> optionalString(const char* value)
{
    if (value == nullptr || *value == '\0') {
        return std::nullopt;
    }
    return std::string(value);
}

std::string credentialTarget()
{
    return "ShiftLine.DiscordSocial." + std::to_string(applicationId);
}

std::string loadRefreshToken()
{
    const std::string target = credentialTarget();
    PCREDENTIALA credential = nullptr;
    if (CredReadA(target.c_str(), CRED_TYPE_GENERIC, 0, &credential) == FALSE) {
        return {};
    }

    std::string token;
    if (credential->CredentialBlob != nullptr && credential->CredentialBlobSize > 0) {
        token.assign(
            reinterpret_cast<const char*>(credential->CredentialBlob),
            credential->CredentialBlobSize);
    }
    CredFree(credential);
    return token;
}

bool saveRefreshToken(const std::string& token)
{
    if (token.empty() || token.size() > CRED_MAX_CREDENTIAL_BLOB_SIZE) {
        return false;
    }

    const std::string target = credentialTarget();
    CREDENTIALA credential{};
    credential.Type = CRED_TYPE_GENERIC;
    credential.TargetName = const_cast<char*>(target.c_str());
    credential.CredentialBlobSize = static_cast<DWORD>(token.size());
    credential.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char*>(token.data()));
    credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
    credential.UserName = const_cast<char*>("ShiftLine");
    return CredWriteA(&credential, 0) != FALSE;
}

void deleteRefreshToken()
{
    const std::string target = credentialTarget();
    CredDeleteA(target.c_str(), CRED_TYPE_GENERIC, 0);
}

void connectUsingToken(
    discordpp::AuthorizationTokenType tokenType,
    std::string accessToken)
{
    if (!client) {
        authState.store(5);
        setError("Discord client was destroyed before token update");
        return;
    }

    authState.store(2);
    client->UpdateToken(tokenType, std::move(accessToken), [](discordpp::ClientResult result) {
        if (!result.Successful()) {
            authState.store(5);
            setError(result.ToString());
            return;
        }

        authState.store(3);
        queueSdkLog(static_cast<int>(discordpp::LoggingSeverity::Info), "Connecting authenticated Discord client");
        client->Connect();
    });
}

void handleTokenExchange(
    discordpp::ClientResult result,
    std::string accessToken,
    std::string newRefreshToken,
    discordpp::AuthorizationTokenType tokenType)
{
    if (!result.Successful()) {
        authState.store(5);
        setError(result.ToString());
        return;
    }

    if (!newRefreshToken.empty()) {
        refreshToken = std::move(newRefreshToken);
        if (!saveRefreshToken(refreshToken)) {
            setError("Discord refresh token could not be saved to Windows Credential Manager");
        }
    }
    connectUsingToken(tokenType, std::move(accessToken));
}

bool copyText(const std::string& value, char* output, int capacity)
{
    if (output == nullptr || capacity <= 0) {
        return false;
    }
    const size_t length = std::min(value.size(), static_cast<size_t>(capacity - 1));
    std::memcpy(output, value.data(), length);
    output[length] = '\0';
    return true;
}

}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_init(const char* applicationIdText)
{
    if (client) {
        return 1;
    }

    uint64_t parsedApplicationId = 0;
    if (!parseApplicationId(applicationIdText, parsedApplicationId)) {
        setError("invalid Discord Application ID");
        return 0;
    }

    try {
        auto newClient = std::make_unique<discordpp::Client>();
        newClient->AddLogCallback([](std::string message, discordpp::LoggingSeverity severity) {
            if (severity == discordpp::LoggingSeverity::None) {
                return;
            }
            queueSdkLog(static_cast<int>(severity), message);
        }, discordpp::LoggingSeverity::Verbose);
        newClient->SetApplicationId(parsedApplicationId);
        newClient->SetActivityJoinCallback([](std::string secret) {
            std::lock_guard<std::mutex> lock(joinMutex);
            if (joinSecrets.size() >= 16) {
                joinSecrets.pop_front();
            }
            joinSecrets.push_back(std::move(secret));
        });
        newClient->SetActivityInviteCreatedCallback([](discordpp::ActivityInvite invite) {
            std::lock_guard<std::mutex> lock(inviteMutex);
            if (activityInvites.size() >= 16) {
                activityInvites.pop_front();
            }
            activityInvites.push_back({
                nextActivityInviteId++,
                invite.SenderId(),
                static_cast<int>(invite.Type()),
                false,
                std::move(invite)
            });
        });
        newClient->SetStatusChangedCallback([](
            discordpp::Client::Status status,
            discordpp::Client::Error error,
            int32_t errorDetail) {
            if (status == discordpp::Client::Status::Ready) {
                authState.store(4);
                queueSdkLog(static_cast<int>(discordpp::LoggingSeverity::Info), "Discord client is ready");
            } else if (status == discordpp::Client::Status::Connecting ||
                       status == discordpp::Client::Status::Connected ||
                       status == discordpp::Client::Status::Reconnecting ||
                       status == discordpp::Client::Status::HttpWait) {
                authState.store(3);
            }

            if (error != discordpp::Client::Error::None) {
                const std::string message = discordpp::Client::ErrorToString(error) +
                    " (detail " + std::to_string(errorDetail) + ")";
                authState.store(5);
                setError(message);
                queueSdkLog(static_cast<int>(discordpp::LoggingSeverity::Error), message);
            }
        });

        client = std::move(newClient);
        applicationId = parsedApplicationId;
        authState.store(0);
        clearError();

        refreshToken = loadRefreshToken();
        if (!refreshToken.empty()) {
            authState.store(2);
            queueSdkLog(static_cast<int>(discordpp::LoggingSeverity::Info), "Refreshing saved Discord authorization");
            client->RefreshToken(applicationId, refreshToken, [](
                discordpp::ClientResult result,
                std::string accessToken,
                std::string newRefreshToken,
                discordpp::AuthorizationTokenType tokenType,
                int32_t,
                std::string) {
                handleTokenExchange(
                    std::move(result),
                    std::move(accessToken),
                    std::move(newRefreshToken),
                    tokenType);
            });
        }
        return 1;
    } catch (const std::exception& error) {
        setError(error.what());
    } catch (...) {
        setError("Discord Social SDK initialization failed");
    }
    return 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_authorize()
{
    if (!client) {
        setError("Discord Social SDK is not initialized");
        return 0;
    }

    const int currentState = authState.load();
    if (currentState >= 1 && currentState <= 4) {
        setError("Discord authorization or connection is already active");
        return 0;
    }

    try {
        auto verifier = client->CreateAuthorizationCodeVerifier();
        discordpp::AuthorizationArgs args;
        args.SetClientId(applicationId);
        args.SetScopes(discordpp::Client::GetDefaultPresenceScopes());
        args.SetCodeChallenge(verifier.Challenge());
        authState.store(1);
        queueSdkLog(static_cast<int>(discordpp::LoggingSeverity::Info), "Starting Discord Public Client authorization");

        client->Authorize(std::move(args), [verifier = std::move(verifier)](
            discordpp::ClientResult result,
            std::string code,
            std::string redirectUri) mutable {
            if (!result.Successful()) {
                authState.store(5);
                setError(result.ToString());
                return;
            }

            authState.store(2);
            const std::string codeVerifier = verifier.Verifier();
            client->GetToken(
                applicationId,
                code,
                codeVerifier,
                redirectUri,
                [](discordpp::ClientResult tokenResult,
                   std::string accessToken,
                   std::string newRefreshToken,
                   discordpp::AuthorizationTokenType tokenType,
                   int32_t,
                   std::string) {
                    handleTokenExchange(
                        std::move(tokenResult),
                        std::move(accessToken),
                        std::move(newRefreshToken),
                        tokenType);
                });
        });
        return 1;
    } catch (const std::exception& error) {
        authState.store(5);
        setError(error.what());
    } catch (...) {
        authState.store(5);
        setError("Discord Public Client authorization failed");
    }
    return 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_logout()
{
    if (!client) {
        return 0;
    }

    if (!refreshToken.empty()) {
        client->RevokeToken(applicationId, refreshToken, [](discordpp::ClientResult result) {
            if (!result.Successful()) {
                setError(result.ToString());
            }
        });
    }
    client->ClearRichPresence();
    client->Disconnect();
    deleteRefreshToken();
    refreshToken.clear();
    authState.store(0);
    queueSdkLog(static_cast<int>(discordpp::LoggingSeverity::Info), "Discord authorization removed");
    return 1;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_get_auth_state()
{
    return authState.load();
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_update_callback()
{
    if (!client) {
        setError("Discord Social SDK is not initialized");
        return 0;
    }

    try {
        discordpp::RunCallbacks();
        return 1;
    } catch (const std::exception& error) {
        setError(error.what());
    } catch (...) {
        setError("Discord Social SDK callback processing failed");
    }
    return 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_set_rich_presence(
    const char* details,
    const char* state,
    unsigned long long startTimestampSeconds,
    const char* largeImage,
    const char* largeImageText,
    const char* smallImage,
    const char* smallImageText,
    const char* partyId,
    int partySize,
    int partyMax,
    const char* joinSecret)
{
    if (!client) {
        setError("Discord Social SDK is not initialized");
        return 0;
    }

    try {
        discordpp::Activity activity;
        activity.SetType(discordpp::ActivityTypes::Playing);
        activity.SetStatusDisplayType(discordpp::StatusDisplayTypes::Details);
        activity.SetDetails(optionalString(details));
        activity.SetState(optionalString(state));

        if ((largeImage != nullptr && *largeImage != '\0') ||
            (smallImage != nullptr && *smallImage != '\0')) {
            discordpp::ActivityAssets assets;
            if (largeImage != nullptr && *largeImage != '\0') {
                assets.SetLargeImage(std::string(largeImage));
            }
            assets.SetLargeText(optionalString(largeImageText));
            if (smallImage != nullptr && *smallImage != '\0') {
                assets.SetSmallImage(std::string(smallImage));
                assets.SetSmallText(optionalString(smallImageText));
            }
            activity.SetAssets(std::move(assets));
        }

        if (startTimestampSeconds > 0 &&
            startTimestampSeconds <= std::numeric_limits<uint64_t>::max() / 1000) {
            discordpp::ActivityTimestamps timestamps;
            timestamps.SetStart(static_cast<uint64_t>(startTimestampSeconds) * 1000);
            activity.SetTimestamps(std::move(timestamps));
        }

        if (partyId != nullptr && std::strlen(partyId) >= 2) {
            discordpp::ActivityParty party;
            party.SetId(partyId);
            const int currentSize = std::max(1, partySize);
            party.SetCurrentSize(currentSize);
            party.SetMaxSize(partyMax > 0 ? std::max(currentSize, partyMax) : 0);
            party.SetPrivacy(discordpp::ActivityPartyPrivacy::Public);
            activity.SetParty(std::move(party));

            if (joinSecret != nullptr && std::strlen(joinSecret) >= 2) {
                discordpp::ActivitySecrets secrets;
                secrets.SetJoin(joinSecret);
                activity.SetSecrets(std::move(secrets));
            }
        }

        client->UpdateRichPresence(std::move(activity), [](discordpp::ClientResult result) {
            if (!result.Successful()) {
                setError(result.ToString());
            }
        });
        return 1;
    } catch (const std::exception& error) {
        setError(error.what());
    } catch (...) {
        setError("Discord Rich Presence update failed");
    }
    return 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_clear_rich_presence()
{
    if (!client) {
        return 0;
    }

    try {
        client->ClearRichPresence();
        return 1;
    } catch (const std::exception& error) {
        setError(error.what());
    } catch (...) {
        setError("Discord Rich Presence clear failed");
    }
    return 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_register_launch_command(const char* command)
{
    if (!client || command == nullptr || *command == '\0') {
        return 0;
    }

    try {
        if (client->RegisterLaunchCommand(applicationId, command)) {
            return 1;
        }
        setError("Discord launch command registration failed");
    } catch (const std::exception& error) {
        setError(error.what());
    } catch (...) {
        setError("Discord launch command registration failed");
    }
    return 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_poll_join_secret(char* output, int capacity)
{
    if (output == nullptr || capacity <= 0) {
        return -1;
    }

    output[0] = '\0';
    std::lock_guard<std::mutex> lock(joinMutex);
    if (joinSecrets.empty()) {
        return 0;
    }

    const std::string secret = std::move(joinSecrets.front());
    joinSecrets.pop_front();
    const size_t length = std::min(secret.size(), static_cast<size_t>(capacity - 1));
    std::memcpy(output, secret.data(), length);
    output[length] = '\0';
    return 1;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_poll_log(
    int* severity,
    char* output,
    int capacity)
{
    if (severity == nullptr || output == nullptr || capacity <= 0) {
        return -1;
    }

    output[0] = '\0';
    std::lock_guard<std::mutex> lock(sdkLogMutex);
    if (sdkLogs.empty()) {
        return 0;
    }

    SdkLogEntry entry = std::move(sdkLogs.front());
    sdkLogs.pop_front();
    const size_t length = std::min(entry.message.size(), static_cast<size_t>(capacity - 1));
    std::memcpy(output, entry.message.data(), length);
    output[length] = '\0';
    *severity = entry.severity;
    return 1;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_is_available()
{
    return client ? 1 : 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_is_connected()
{
    if (!client) {
        return 0;
    }

    const auto status = client->GetStatus();
    return status == discordpp::Client::Status::Connected ||
        status == discordpp::Client::Status::Ready;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_get_friend_count()
{
    if (!client || client->GetStatus() != discordpp::Client::Status::Ready) {
        return -1;
    }

    try {
        int count = 0;
        for (const auto& relationship : client->GetRelationships()) {
            if (relationship.DiscordRelationshipType() == discordpp::RelationshipType::Friend &&
                relationship.User().has_value()) {
                ++count;
            }
        }
        return count;
    } catch (const std::exception& error) {
        setError(error.what());
    } catch (...) {
        setError("Discord friend list query failed");
    }
    return -1;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_get_friend(
    int friendIndex,
    char* userId,
    int userIdCapacity,
    char* displayName,
    int displayNameCapacity,
    int* status)
{
    if (!client || client->GetStatus() != discordpp::Client::Status::Ready ||
        friendIndex < 0 || userId == nullptr || displayName == nullptr || status == nullptr) {
        return 0;
    }

    try {
        int currentIndex = 0;
        for (const auto& relationship : client->GetRelationships()) {
            if (relationship.DiscordRelationshipType() != discordpp::RelationshipType::Friend) {
                continue;
            }
            const auto user = relationship.User();
            if (!user.has_value()) {
                continue;
            }
            if (currentIndex++ != friendIndex) {
                continue;
            }
            if (!copyText(std::to_string(user->Id()), userId, userIdCapacity) ||
                !copyText(user->DisplayName(), displayName, displayNameCapacity)) {
                return 0;
            }
            *status = static_cast<int>(user->Status());
            return 1;
        }
    } catch (const std::exception& error) {
        setError(error.what());
    } catch (...) {
        setError("Discord friend details query failed");
    }
    return 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_send_activity_invite(
    const char* userIdText,
    const char* message)
{
    uint64_t userId = 0;
    if (!client || client->GetStatus() != discordpp::Client::Status::Ready ||
        !parseApplicationId(userIdText, userId)) {
        setError("Discord client is not ready or the friend ID is invalid");
        return 0;
    }

    try {
        client->SendActivityInvite(userId, message == nullptr ? "" : message,
            [](discordpp::ClientResult result) {
                if (!result.Successful()) {
                    setError(result.ToString());
                }
            });
        return 1;
    } catch (const std::exception& error) {
        setError(error.what());
    } catch (...) {
        setError("Discord activity invite failed");
    }
    return 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_poll_activity_invite(
    unsigned long long* inviteId,
    char* senderId,
    int senderIdCapacity,
    char* senderName,
    int senderNameCapacity,
    int* inviteType)
{
    if (inviteId == nullptr || senderId == nullptr || senderName == nullptr || inviteType == nullptr ||
        senderIdCapacity <= 0 || senderNameCapacity <= 0) {
        return -1;
    }

    uint64_t sender = 0;
    {
        std::lock_guard<std::mutex> lock(inviteMutex);
        auto invite = std::find_if(activityInvites.begin(), activityInvites.end(),
            [](const PendingActivityInvite& item) { return !item.delivered; });
        if (invite == activityInvites.end()) {
            return 0;
        }
        invite->delivered = true;
        *inviteId = invite->id;
        sender = invite->senderId;
        *inviteType = invite->type;
    }

    copyText(std::to_string(sender), senderId, senderIdCapacity);
    std::string displayName = std::to_string(sender);
    if (client && client->GetStatus() == discordpp::Client::Status::Ready) {
        const auto user = client->GetUser(sender);
        if (user.has_value() && !user->DisplayName().empty()) {
            displayName = user->DisplayName();
        }
    }
    copyText(displayName, senderName, senderNameCapacity);
    return 1;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_respond_activity_invite(
    unsigned long long inviteId,
    int accept)
{
    if (!client) {
        setError("Discord Social SDK is not initialized");
        return 0;
    }

    std::optional<PendingActivityInvite> pending;
    {
        std::lock_guard<std::mutex> lock(inviteMutex);
        auto invite = std::find_if(activityInvites.begin(), activityInvites.end(),
            [inviteId](const PendingActivityInvite& item) { return item.id == inviteId; });
        if (invite != activityInvites.end()) {
            pending.emplace(std::move(*invite));
            activityInvites.erase(invite);
        }
    }

    if (!pending.has_value()) {
        setError("Discord activity invite is no longer available");
        return 0;
    }
    if (!accept) {
        queueSdkLog(static_cast<int>(discordpp::LoggingSeverity::Info), "Activity invite dismissed");
        return 1;
    }

    try {
        if (pending->type == static_cast<int>(discordpp::ActivityActionTypes::JoinRequest)) {
            client->SendActivityJoinRequestReply(std::move(pending->invite), [](discordpp::ClientResult result) {
                if (!result.Successful()) {
                    setError(result.ToString());
                }
            });
        } else {
            client->AcceptActivityInvite(std::move(pending->invite), [](
                discordpp::ClientResult result,
                std::string joinSecret) {
                if (!result.Successful()) {
                    setError(result.ToString());
                    return;
                }
                std::lock_guard<std::mutex> lock(joinMutex);
                if (joinSecrets.size() >= 16) {
                    joinSecrets.pop_front();
                }
                joinSecrets.push_back(std::move(joinSecret));
            });
        }
        return 1;
    } catch (const std::exception& error) {
        setError(error.what());
    } catch (...) {
        setError("Discord activity invite response failed");
    }
    return 0;
}

SHIFTLINE_EXPORT int SHIFTLINE_CALL shiftline_discord_get_last_error(char* output, int capacity)
{
    std::lock_guard<std::mutex> lock(errorMutex);
    const size_t errorLength = lastError.size();
    if (output != nullptr && capacity > 0) {
        const size_t copyLength = std::min(errorLength, static_cast<size_t>(capacity - 1));
        std::memcpy(output, lastError.data(), copyLength);
        output[copyLength] = '\0';
        lastError.clear();
    }
    return static_cast<int>(std::min(errorLength, static_cast<size_t>(std::numeric_limits<int>::max())));
}

SHIFTLINE_EXPORT void SHIFTLINE_CALL shiftline_discord_shutdown()
{
    if (client) {
        try {
            client->ClearRichPresence();
            discordpp::RunCallbacks();
        } catch (...) {
        }
        client.reset();
    }

    applicationId = 0;
    refreshToken.clear();
    authState.store(0);
    std::lock_guard<std::mutex> lock(joinMutex);
    joinSecrets.clear();
    std::lock_guard<std::mutex> logLock(sdkLogMutex);
    sdkLogs.clear();
    std::lock_guard<std::mutex> inviteLock(inviteMutex);
    activityInvites.clear();
}