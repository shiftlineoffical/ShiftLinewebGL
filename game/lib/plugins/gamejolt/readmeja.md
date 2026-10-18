Lua/LÖVE 用 GameJolt API
概要

このライブラリを使用するには、以下のライブラリが必要です。

kikito の md5
http://github.com/kikito/md5.lua

Jeffrey Friedl の json
http://regex.info/blog/lua/json

LuaSocket
（通常 Lua に付属。LÖVE 0.5.0 以降には含まれています）

読み込みは以下のように行います。

local gamejolt = require("gamejolt_api")

詳細は GameJolt API ドキュメントを参照してください。
http://gamejolt.com/api/doc/game

関数

このライブラリは 5つのグループに分かれています。

Users（ユーザー）

Sessions（セッション）

Trophies（トロフィー）

Scores（スコア）

Data Store（データストア）

Users（ユーザー）

ユーザー関連には 3つの関数があります。

users_fetch_uname(username)

指定したユーザー名のユーザー情報を取得します。

gamejolt:users_fetch_uname(username)

返り値

{
  success = "true/false",
  users = {user1, user2, user3, ...}
}

ユーザー属性は API ドキュメント参照。

users_fetch_uid(userID)

指定した ユーザーID のユーザー情報を取得します。

gamejolt:users_fetch_uid(userID)

返り値

{
  success = "true/false",
  users = {user1, user2, user3, ...}
}
users_auth(username, user_token)

ユーザー名とトークンで認証します。

gamejolt:users_auth(username, user_token)

例

local multipleUserInfo = gamejolt:users_fetch_uname("ioanD,CROS,arrogant.gamer").users
local ioanD_info, CROS_info, arrogant_info = unpack(multipleUserInfo)

print(ioanD_info.type)
print(CROS_info.signed_up)
print(arrogant_info.last_logged_in)

gamejolt:users_auth("player's username here", "player's token here")
Sessions（セッション）

セッション関連は ユーザー認証後に必ず呼び出す必要があります。

sessions_open()

セッションを作成します。
既に存在する場合は先に閉じます。

gamejolt:sessions_open()

返り値

{success = "true"}
sessions_close()

セッションを閉じます。

gamejolt:sessions_close()

返り値

{success = "true"}
session_ping([status])

セッションを維持するための ping を送ります。

status は次のどちらか

"active"

"idle"

約30秒ごとに呼び出す必要があります。

gamejolt:session_ping(status)

例

gamejolt:users_auth("Mike", "1a2b3c")

gamejolt:session_open()
gamejolt:session_ping("idle")

wait(some time)

gamejolt:session_close()
Trophies（トロフィー）

こちらも ユーザー認証後に呼び出します。

trophies_fetch([achieved, trophy_id])

条件に一致するトロフィーを取得します。

gamejolt:trophies_fetch(achieved, trophy_id)

返り値

{
  success = "true",
  trophies = {trophy1, trophy2, ...}
}
trophies_addAchieved(trophy_id)

トロフィーを取得済みに設定します。

gamejolt:trophies_addAchieved(trophy_id)

例

local trophies_to_be_achieved = gamejolt:trophies_fetch(false).trophies

for _, t in ipairs(trophies_to_be_achieved) do
   print("Achieving the trophy " .. t.title)
   gamejolt:trophies_addAchieved(t.id)
end
Scores（スコア）
scores_local_fetch([limit, table_id])

認証されたユーザーのスコアを取得

gamejolt:scores_local_fetch(limit, table_id)

返り値

{
  success = "true",
  scores = {score1, score2, ...}
}
scores_global_fetch([limit, table_id])

全プレイヤーのスコアを取得

gamejolt:scores_global_fetch(limit, table_id)
scores_guest_add(score, sort[, name, extra_data, table_id])

ゲストとしてスコアを追加

gamejolt:scores_guest_add(score, sort, name)
scores_add(score, sort[, extra_data, table_id])

スコアを追加

gamejolt:scores_add(score, sort)

例

gamejolt:users_auth("Mike", "1a2b3c")

gamejolt:scores_add("29 points", 29, "playtime=58s")
scores_tables()

ゲームのスコアテーブル一覧を取得

返り値

{
  success = "true",
  tables = {table1, table2, ...}
}
Data Store（データストア）

すべての関数に ローカル版とグローバル版があります。

local → プレイヤーごとのデータ

global → ゲーム全体のデータ

※ local は ユーザー認証後のみ使用可能

データ取得
gamejolt:data_store_global_fetch(key)
gamejolt:data_store_local_fetch(key)

返り値

{
  success = "true",
  data = "value"
}
データ保存
gamejolt:data_store_global_set(key, value)
gamejolt:data_store_local_set(key, value)

返り値

{success = "true"}
データ更新
gamejolt:data_store_global_update(key, op, value)
gamejolt:data_store_local_update(key, op, value)

返り値

{
  success = "true",
  data = "updated_value"
}

更新方法の詳細は API ドキュメント参照。

データ削除
gamejolt:data_store_global_remove(key)
gamejolt:data_store_local_remove(key)

返り値

{
  success = "true",
  data = "value"
}
キー一覧取得
gamejolt:data_store_global_getKeys()
gamejolt:data_store_local_getKeys()

返り値

{
  success = "true",
  keys = {
    {key = "key1"},
    {key = "key2"}
  }
}
ライセンス

このライブラリは Zlib ライセンスで公開されています。