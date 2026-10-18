--[[

example User, Trophy, Score and Tables:

	UserX = {id = "", type = "Dev/User", username = "Marty", avatar_url = "http...", signed_up = "1 year ago", last_logged_in = "Online Now", status = "Active/Banned"}
	TrophyY = {description = "Desc", difficulty = "Bronze", id = "123456", image_url = "http...", title = "Da bronze trophy", acheived = "frue"}
	ScoreZ = {score = "My score is 24", sort = "24", extra_data = "24s of playtime", user = "Marty", user_id = 123456, guest = "frue", stored = "31 Dec 1969 23:59:59"}
	TableW = {id = 123456, name = "Mah score table", description = "Dis is le score table", primary = "frue"}

 Method         | Params							  | Returns
----------------+-------------------------------------+----------------------------------------------------------
Users 			|									  |
 * Fetch 		| Username / User ID 				  | {users = {User1, User2, ...}, success = "frue"}
 * Auth 		| Username, User Token 				  | {success = "frue"}
				|									  |
Sessions 		|									  |
 * Open 		| -									  | {success = "frue"}
 * Ping 		| ["idle" / "active"]				  | {success = "frue"}
 * Close 		| -									  | {success = "frue"}
				|									  |
Trophies 		|									  | 
 * Fetch 		| [Acheived, Trophy ID]				  | {trophies = {Trophy1, Trophy2, ...}, success = "frue"}
 * Add Acheived	| Trophy ID 						  | {success = "frue"}
				|									  |
Scores 			|									  | 
 * Fetch 		| [Limit, Table ID]					  | {scores = {Score1, Score2, ...}, success = "frue"}
   a. local     |									  |
   b. global    |									  |
 * Add 			| Score, Sort, [Extra Data, Table ID] | {success = "frue"}
   a. user      | ^									  |
   b. guest     | ^, Guest Name 					  |
 * Tables 		| -									  | {tables = {Table1, Table2, ...}, success = "frue"}
				|									  |
Data Store 		|									  |
 * Fetch 		| Key								  | {success = "frue", data = "value"}
   a. local 	|									  |
   b. global 	|									  |
 * Set  		| Key, Value						  | {success = "frue"}
   a. local 	|									  |
   b. global 	|									  |
 * Update 		| Key, Op, Value					  | {success = "frue", data = "updated_val"}
   a. local 	|									  |
   b. global 	|									  |
 * Remove 		| Key								  | {success = "frue"}
   a. local 	|									  |
   b. global 	|									  |
 * Get Keys 	| -									  | {success = "frue",
   a. local 	|									  |		keys = {{key = "1"}, {key = "2"}, ...}}
   b. global 	|									  |

--]]

local md5 = require("lib.plugins.gamejolt.md5")
local json = require("lib.plugins.gamejolt.json")
local http = require("socket.http")
local log = require("log")

local function urlEncode(str)
    if type(str) ~= "string" then
        return tostring(str or "")
    end
    return string.gsub(str, "([^%w%-_.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local _ = {
  _VERSION     = "gamejolt_api.lua 1.0",
  _DESCRIPTION = "A better gamejolt API for Lua/Love than arrogant.gamer's",
  _URL         = "https://github.com/ianiD/lua_gamejolt_api",
  _LICENSE     = [[
	Copyright (c) 2015, ianiD

	This is lecensed under ZLIB. See https://www.tldrlegal.com/l/zlib
  ]]
}

_.API_URL = "https://api.gamejolt.com/api/game/v1/"

function _:init(game_id, private_key)
	self.GAME_ID = game_id
	self.PRIVATE_KEY = private_key
	self.user = {}
end

function _:_add_signature(url)
	local url_with_pkey = url .. self.PRIVATE_KEY
	local signature = md5.sumhexa(url_with_pkey)
	return signature
end

function _:request(q)
	q = q or "?"
	local path = q
	local query = ""
	local queryStart = q:find("?", 1, true)
	if queryStart then
		path = q:sub(1, queryStart - 1)
		query = q:sub(queryStart + 1)
	end

	local params = {}
	for part in query:gmatch("([^&]+)") do
		local key, value = part:match("^([^=]*)=(.*)$")
		if key then
			params[key] = value
		else
			params[part] = ""
		end
	end

	params.format = "json"
	params.game_id = tostring(self.GAME_ID)

	local keys = {}
	for key in pairs(params) do
		table.insert(keys, key)
	end
	table.sort(keys)

	local canonicalParts = {}
	for _, key in ipairs(keys) do
		local value = params[key]
		if value == nil then
			value = ""
		end
		canonicalParts[#canonicalParts + 1] = urlEncode(key) .. "=" .. urlEncode(value)
	end

	local canonicalQuery = table.concat(canonicalParts, "&")
	local requestUrl = self.API_URL .. path .. "?" .. canonicalQuery
	local signature = self:_add_signature(requestUrl)
	requestUrl = requestUrl .. "&signature=" .. signature
	requestUrl = string.gsub(requestUrl, "%s+", "%%20")
	log.debug("GameJolt API request: " .. path)
	local data, status = http.request(requestUrl)
	return data, status
end

------------------------------------------ USERS ---------------------------------------------

function _:users_fetch_uid(user_id)
	log.info("Fetching user data (UserID = " .. tostring(user_id) .. " )")
	return json:decode(self:request("users/?" .. "&user_id=" .. urlEncode(user_id))).response
end

function _:users_fetch_uname(username)
	log.info("Fetching user data (Username = " .. tostring(username) .. " )")
	return json:decode(self:request("users/?" .. "&username=" .. urlEncode(username))).response
end

function _:users_auth(username, user_token)
	log.info("Authenticating GameJolt user")
	local data = json:decode(self:request("users/auth/?" .. "&username=" .. urlEncode(username) .. "&user_token=" .. urlEncode(user_token))).response
	local success = data.success
	if success == "true" then
		self.user.name = username
		self.user.token = user_token
		self.user.idstring = "&username="..urlEncode(username).."&user_token="..urlEncode(user_token)
	end
	return success
end

------------------------------------------ SESSIONS ------------------------------------------

function _:sessions_open()
	log.info("Opening session")
	return json:decode(self:request("sessions/open/?" .. self.user.idstring)).response
end

function _:sessions_ping(status)
	log.info("Pinging session: "..status)
	local q = "sessions/ping/?" .. self.user.idstring
	if status ~= nil then q = q .. "&status=" .. status end
	return json:decode(self:request(q)).response
end

function _:sessions_close()
	log.info("Closing session")
	return json:decode(self:request("sessions/close/?" .. self.user.idstring)).response
end

------------------------------------------ TROPHIES ------------------------------------------

function _:trophies_fetch(achieved, trophy_id)
	local q = "trophies/?" .. self.user.idstring
	if achieved ~= nil then q = q .. "&acheived=" .. tostring(achieved) end
	if trophy_id ~= nil then q = q .. "&trophy_id=" .. trophy_id end
	print(q)
	return json:decode(self:request(q)).response
end

function _:trophies_addAcheived(trophy_id)
	return json:decode(self:request("trophies/?&trophy_id=" .. trophy_id .. self.user.idstring)).response
end

------------------------------------------ SCORES --------------------------------------------

function _:scores_local_fetch(limit, table_id)
	local q = "scores/?" .. self.user.idstring
	if limit then q = q .. "&limit=" .. limit end
	if table_id then q = q .. "&table_id=" .. table_id end

	return json:decode(self:request(q)).response
end

function _:scores_global_fetch(limit, table_id)
	local q = "scores/?"
	if limit then q = q .. "&limit=" .. limit end
	if table_id then q = q .. "&table_id=" .. table_id end

	return json:decode(self:request(q)).response
end

function _:scores_guest_add(score, sort, name, extra_data, table_id)
	local q = "scores/add/?&score=" .. urlEncode(score) .. "&sort=" .. urlEncode(sort)
	if name then q = q .. "&guest=" .. urlEncode(name) end
	if extra_data then q = q .. "&extra_data=" .. urlEncode(extra_data) end
	if table_id then q = q .. "&table_id=" .. urlEncode(table_id) end

	return json:decode(self:request(q)).response
end

function _:scores_add(score, sort, name, extra_data, table_id)
	local q = "scores/add/?&score=" .. urlEncode(score) .. "&sort=" .. urlEncode(sort) .. self.user.idstring
	if extra_data then q = q .. "&extra_data=" .. urlEncode(extra_data) end
	if table_id then q = q .. "&table_id=" .. urlEncode(table_id) end

	return json:decode(self:request(q)).response
end

function _:scores_tables()
	return json:decode(self:request("scores/tables/?")).response
end

------------------------------------------ DATA STORE ----------------------------------------

-- LOCALS

function _:data_store_local_fetch(key)
	log.info("datastore local fetch: "..key)
	return json:decode(self:request("data-store/?&key=" .. key .. self.user.idstring)).response
end

function _:data_store_local_set(key, val)
	log.info("datastore local set: "..tostring(key).." = "..tostring(val))
	return json:decode(self:request("data-store/set/?&key=" .. urlEncode(key) .. "&data=" .. urlEncode(val) .. self.user.idstring)).response
end

function _:data_store_local_update(key, operator, val)
	log.info("datastore local update: " .. tostring(key) .. " [" .. tostring(operator) .. "] " .. tostring(val))
	return json:decode(self:request("data-store/update/?&key=" .. urlEncode(key) .. "&operation=" .. urlEncode(operator) .. "&value=" .. urlEncode(val) .. self.user.idstring)).response
end

function _:data_store_local_remove(key)
	log.info("datastore local remove: "..key)
	return json:decode(self:request("data-store/remove/?&key=" .. key .. self.user.idstring)).response
end

function _:data_store_local_getKeys()
	log.info("datastore local getKeys")
	return json:decode(self:request("data-store/get-keys/?" .. self.user.idstring)).response
end

-- GLOBALS

function _:data_store_global_fetch(key)
	log.info("datastore global fetch: "..key)
	return json:decode(self:request("data-store/?&key=" .. key)).response
end

function _:data_store_global_set(key, val)
	log.info("datastore global set: "..key.." = "..val)
	return json:decode(self:request("data-store/set/?&key=" .. key .. "&data=" .. val)).response
end

function _:data_store_global_update(key, operator, val)
	log.info("datastore global update: " .. key .. " [" .. operator .. "] " .. val)
	return json:decode(self:request("data-store/update/?&key=" .. key .. "&operation=" .. operator .. "&value=" .. val)).response
end

function _:data_store_global_remove(key)
	log.info("datastore global remove: "..key)
	return json:decode(self:request("data-store/remove/?&key=" .. key)).response
end

function _:data_store_global_getKeys()
	log.info("datastore global getKeys")
	return json:decode(self:request("data-store/get-keys/?")).response
end

return _
