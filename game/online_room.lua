local online_room = {}

local online_connect = require("online_connect")
local discordSDK = require("lib.SDK")

local displayWidth, displayHeight = love.graphics.getDimensions()
local titleFont
local bodyFont
local smallFont

local roomID = ""
local statusText = ""
local statusIsError = false
local focused = false
local caretTimer = 0
local caretVisible = true
local hoverAction = nil
local movedToMusicSelect = false
local gameStarted = false
local replaceRoomIDOnInput = false
local discordFriendsOpen = false
local discordFriends = {}
local selectedDiscordFriendIndex = 1
local discordFriendsMessage = nil

local buttons = {}

local function normalizeRoomID(value)
	return tostring(value or ""):gsub("[^A-Za-z0-9]", ""):sub(1, 64)
end

local function updateLayout()
	displayWidth, displayHeight = love.graphics.getDimensions()

	titleFont = love.graphics.newFont(
		"lib/data/fonts/NotoSansJP-Light.ttf",
		math.max(30, math.floor(displayHeight * 0.065))
	)
	bodyFont = love.graphics.newFont(
		"lib/data/fonts/NotoSansJP-Light.ttf",
		math.max(20, math.floor(displayHeight * 0.032))
	)
	smallFont = love.graphics.newFont(
		"lib/data/fonts/NotoSansJP-Light.ttf",
		math.max(16, math.floor(displayHeight * 0.022))
	)

	local width = math.min(640, displayWidth * 0.65)
	local left = (displayWidth - width) / 2
	local buttonHeight = math.max(44, math.min(58, displayHeight * 0.08))
	local gap = math.max(8, displayHeight * 0.018)
	local columnGap = 12
	local columnWidth = (width - columnGap) / 2
	local top = displayHeight * 0.42

	buttons = {
		host = {x = left, y = top, w = columnWidth, h = buttonHeight},
		join = {x = left + columnWidth + columnGap, y = top, w = columnWidth, h = buttonHeight},
		copy = {x = left, y = top + buttonHeight + gap, w = columnWidth, h = buttonHeight},
		invite = {x = left + columnWidth + columnGap, y = top + buttonHeight + gap, w = columnWidth, h = buttonHeight},
		start = {x = left, y = top + (buttonHeight + gap) * 2, w = columnWidth, h = buttonHeight},
		back = {x = left + columnWidth + columnGap, y = top + (buttonHeight + gap) * 2, w = columnWidth, h = buttonHeight}
	}
end

local function pointInRect(x, y, rect)
	return x >= rect.x and x <= rect.x + rect.w
		and y >= rect.y and y <= rect.y + rect.h
end

local function setStatus(text, isError)
	statusText = text or ""
	statusIsError = isError == true
end

local function hostRoom()
	local ok, result = online_connect.hosting()
	if ok then
		roomID = result or ""
		focused = false
		setStatus("部屋を作成しました")
	else
		setStatus(result or "部屋を作成できませんでした", true)
	end
end

local function joinRoom()
	local ok, result = online_connect.joining(roomID)
	if ok then
		focused = false
		setStatus("部屋に参加しました")
	else
		setStatus(result or "部屋に参加できませんでした", true)
	end
end

local function copyRoomID()
	if roomID == "" then
		setStatus("コピーするRoom IDがありません", true)
		return
	end

	if not love.system or type(love.system.setClipboardText) ~= "function" then
		setStatus("クリップボード機能を利用できません", true)
		return
	end

	local ok, err = pcall(love.system.setClipboardText, roomID)
	if ok then
		setStatus("Room IDをクリップボードにコピーしました")
	else
		setStatus("Room IDのコピーに失敗しました: " .. tostring(err), true)
	end
end

local function openDiscordFriends()
	discordFriendsOpen = true
	selectedDiscordFriendIndex = 1
	discordFriendsMessage = nil

	local friends, message = discordSDK.getFriends()
	if not friends then
		discordFriends = {}
		discordFriendsMessage = tostring(message or "Discordに接続してください")
		return
	end

	discordFriends = friends
	if #friends == 0 then
		discordFriendsMessage = "Discordフレンドが見つかりません"
	elseif online_connect.getRoomID() == "" then
		discordFriendsMessage = "先に部屋を作成するか、参加してください"
	end
end

local function inviteSelectedDiscordFriend()
	local friend = discordFriends[selectedDiscordFriendIndex]
	if not friend then
		return
	end

	if online_connect.getRoomID() == "" then
		discordFriendsMessage = "先に部屋を作成するか、参加してください"
		return
	end

	local sent = discordSDK.sendActivityInvite(friend.id, "Join my ShiftLine room")
	discordFriendsMessage = sent and "Discord招待を送信しました" or "Discord招待を送信できませんでした"
end

local function getDiscordFriendsDialogBounds()
	local panelWidth = math.min(displayWidth * 0.82, 720)
	local panelHeight = displayHeight * 0.76
	local panelX = (displayWidth - panelWidth) / 2
	local panelY = (displayHeight - panelHeight) / 2
	local listX = panelX + 24
	local listY = panelY + 76
	local listWidth = panelWidth - 48
	local rowHeight = math.max(38, smallFont:getHeight() + 12)
	local inviteButton = {
		x = panelX + 24,
		y = panelY + panelHeight - 58,
		w = panelWidth - 48,
		h = 42
	}
	local listHeight = math.max(1, inviteButton.y - listY - 14)
	local visibleCount = math.max(1, math.floor(listHeight / rowHeight))
	local firstIndex = math.min(
		math.max(1, selectedDiscordFriendIndex - visibleCount + 1),
		math.max(1, #discordFriends - visibleCount + 1)
	)
	return panelX, panelY, panelWidth, panelHeight, listX, listY, listWidth,
		listHeight, rowHeight, firstIndex, visibleCount, inviteButton
end

local function drawDiscordFriendsDialog()
	local panelX, panelY, panelWidth, panelHeight, listX, listY, listWidth,
		listHeight, rowHeight, firstIndex, visibleCount, inviteButton = getDiscordFriendsDialogBounds()

	love.graphics.setColor(0, 0, 0, 0.72)
	love.graphics.rectangle("fill", 0, 0, displayWidth, displayHeight)
	love.graphics.setColor(0.08, 0.08, 0.08, 1)
	love.graphics.rectangle("fill", panelX, panelY, panelWidth, panelHeight, 6, 6)
	love.graphics.setColor(1, 1, 1, 0.28)
	love.graphics.rectangle("line", panelX, panelY, panelWidth, panelHeight, 6, 6)

	love.graphics.setFont(bodyFont)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf("Discordフレンドを招待", panelX + 20, panelY + 22, panelWidth - 40, "center")

	love.graphics.setScissor(listX, listY, listWidth, listHeight)
	local lastIndex = math.min(#discordFriends, firstIndex + visibleCount - 1)
	for index = firstIndex, lastIndex do
		local rowY = listY + (index - firstIndex) * rowHeight
		local selected = index == selectedDiscordFriendIndex
		love.graphics.setColor(selected and 0.24 or 0.14, selected and 0.24 or 0.14, selected and 0.24 or 0.14, 1)
		love.graphics.rectangle("fill", listX, rowY, listWidth, rowHeight - 3)
		love.graphics.setFont(smallFont)
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.print(discordFriends[index].name, listX + 12, rowY + 5)
		love.graphics.setColor(0.7, 0.7, 0.7, 1)
		love.graphics.printf(discordFriends[index].status or "unknown", listX + listWidth * 0.65, rowY + 5, listWidth * 0.32, "right")
	end
	love.graphics.setScissor()

	if discordFriendsMessage then
		love.graphics.setFont(smallFont)
		love.graphics.setColor(1, 0.8, 0.55, 1)
		love.graphics.printf(discordFriendsMessage, panelX + 20, inviteButton.y - smallFont:getHeight() - 8, panelWidth - 40, "center")
	end

	love.graphics.setColor(0.18, 0.18, 0.18, 1)
	love.graphics.rectangle("fill", inviteButton.x, inviteButton.y, inviteButton.w, inviteButton.h, 4, 4)
	love.graphics.setColor(1, 1, 1, 0.5)
	love.graphics.rectangle("line", inviteButton.x, inviteButton.y, inviteButton.w, inviteButton.h, 4, 4)
	love.graphics.setFont(smallFont)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf("選択したフレンドに招待を送信", inviteButton.x + 8, inviteButton.y + 8, inviteButton.w - 16, "center")
	love.graphics.setColor(1, 1, 1, 0.65)
	love.graphics.printf("上下で選択  Enterで招待  Escで閉じる", panelX + 20, panelY + panelHeight - 22, panelWidth - 40, "center")
end

local function startGame()
	if not online_connect.isConnected() or not online_connect.getIsHosting() then
		return
	end

	local ok, err = online_connect.send("ONLINE_START")
	if not ok then
		setStatus(err or "ゲーム開始の通知に失敗しました", true)
		return
	end

	gameStarted = true
	if type(changeProgram) == "function" then
		changeProgram(10)
	end
end

local function receivePacket(typeName)
	if typeName ~= "ONLINE_START" or gameStarted then
		return
	end

	gameStarted = true
	if type(changeProgram) == "function" then
		changeProgram(10)
	end
end

function online_room.joinWithRoomID(value)
	roomID = normalizeRoomID(value)
	focused = false
	if love.keyboard and love.keyboard.setTextInput then
		love.keyboard.setTextInput(false)
	end
	joinRoom()
end

function online_room.load()
	if love.keyboard and love.keyboard.setTextInput then
		love.keyboard.setTextInput(false)
	end
	updateLayout()
	local connectedRoomID = online_connect.getRoomID()
	if connectedRoomID ~= "" then
		roomID = normalizeRoomID(connectedRoomID)
	end
	setStatus("Room IDを入力して参加するか、部屋を作成してください")
	focused = false
	replaceRoomIDOnInput = false
	discordFriendsOpen = false
	caretTimer = 0
	caretVisible = true
	movedToMusicSelect = false
	gameStarted = false
end

function online_room.update(dt)
	local width, height = love.graphics.getDimensions()
	if width ~= displayWidth or height ~= displayHeight then
		updateLayout()
	end

	caretTimer = caretTimer + (dt or 0)
	if caretTimer >= 0.5 then
		caretTimer = caretTimer - 0.5
		caretVisible = not caretVisible
	end

	if online_connect.isConnected() then
		local connectedRoomID = online_connect.getRoomID()
		if connectedRoomID ~= "" then
			roomID = connectedRoomID
		end

		local role = online_connect.getIsHosting() and "ホスト待機中" or "接続中"
		setStatus(string.format("%s  •  パーティー %d / 4 人", role, online_connect.getPartyCount()))
	end
end

local function drawButton(rect, label, active)
	love.graphics.setColor(active and 0.28 or 0.1, active and 0.28 or 0.1, active and 0.28 or 0.1, 1)
	love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4, 4)
	love.graphics.setColor(0.8, 0.8, 0.8, 1)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 4, 4)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setFont(bodyFont)
	love.graphics.printf(label, rect.x, rect.y + (rect.h - bodyFont:getHeight()) / 2, rect.w, "center")
end

function online_room.draw()
	love.graphics.setColor(0.03, 0.03, 0.03, 1)
	love.graphics.rectangle("fill", 0, 0, displayWidth, displayHeight)

	love.graphics.setColor(0.35, 0.35, 0.35, 1)
	love.graphics.rectangle("fill", 0, displayHeight * 0.22, displayWidth, 2)

	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setFont(titleFont)
	love.graphics.printf("オンラインルーム", 0, displayHeight * 0.13, displayWidth, "center")

	local inputWidth = buttons.host.w
	local inputX = buttons.host.x
	local inputY = displayHeight * 0.29
	love.graphics.setColor(0.1, 0.1, 0.1, 1)
	love.graphics.rectangle("fill", inputX, inputY, inputWidth, 64, 4, 4)
	love.graphics.setColor(focused and 1 or 0.55, focused and 1 or 0.55, focused and 1 or 0.55, 1)
	love.graphics.rectangle("line", inputX, inputY, inputWidth, 64, 4, 4)
	love.graphics.setColor(0.75, 0.75, 0.75, 1)
	love.graphics.setFont(smallFont)
	love.graphics.print("Room ID", inputX + 18, inputY + 8)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setFont(bodyFont)
	love.graphics.print(roomID, inputX + 18, inputY + 29)
	if focused and caretVisible then
		local caretX = inputX + 18 + bodyFont:getWidth(roomID)
		love.graphics.line(caretX, inputY + 28, caretX, inputY + 53)
	end

	local isWaitingHost = online_connect.isConnected() and online_connect.getIsHosting()
	if not isWaitingHost then
		drawButton(buttons.host, "部屋を作成", hoverAction == "host")
		drawButton(buttons.join, "このRoom IDに参加", hoverAction == "join")
	end
	drawButton(buttons.copy, "Room IDをコピー", hoverAction == "copy")
	drawButton(buttons.invite, "Discordフレンド招待", hoverAction == "invite")
	if isWaitingHost then
		drawButton(buttons.start, "ゲームを開始", hoverAction == "start")
	end
	drawButton(buttons.back, "戻る", hoverAction == "back")

	love.graphics.setFont(smallFont)
	love.graphics.setColor(statusIsError and 1 or 0.85, statusIsError and 1 or 0.85, statusIsError and 1 or 0.85, 1)
	love.graphics.printf(statusText, buttons.host.x, buttons.back.y + buttons.back.h + 16, buttons.host.w, "center")

	local players = online_connect.getPartyPlayers()
	love.graphics.setColor(0.65, 0.65, 0.65, 1)
	love.graphics.printf(string.format("参加者 %d / 4", #players), buttons.host.x, displayHeight * 0.78, buttons.host.w, "center")
	love.graphics.setColor(1, 1, 1, 1)
	local playerText = #players > 0 and table.concat(players, "\n") or "参加者を待っています"
	love.graphics.printf(playerText, buttons.host.x, displayHeight * 0.82, buttons.host.w, "center")
	love.graphics.setColor(1, 1, 1, 1)
	if discordFriendsOpen then
		drawDiscordFriendsDialog()
	end
end

function online_room.mousepressed(x, y, button)
	if button ~= 1 then
		return
	end

	local inputY = displayHeight * 0.29
	local isWaitingHost = online_connect.isConnected() and online_connect.getIsHosting()
	if discordFriendsOpen then
		local _, _, _, _, listX, listY, listWidth, listHeight, rowHeight, firstIndex, _, inviteButton = getDiscordFriendsDialogBounds()
		if pointInRect(x, y, inviteButton) then
			inviteSelectedDiscordFriend()
		elseif x >= listX and x <= listX + listWidth and y >= listY and y <= listY + listHeight then
			local index = firstIndex + math.floor((y - listY) / rowHeight)
			if index >= 1 and index <= #discordFriends then
				selectedDiscordFriendIndex = index
			end
		elseif not pointInRect(x, y, {x = (displayWidth - math.min(displayWidth * 0.82, 720)) / 2, y = (displayHeight - displayHeight * 0.76) / 2, w = math.min(displayWidth * 0.82, 720), h = displayHeight * 0.76}) then
			discordFriendsOpen = false
		end
		return
	end
	if isWaitingHost and pointInRect(x, y, buttons.start) then
		startGame()
	elseif pointInRect(x, y, buttons.invite) then
		focused = false
		openDiscordFriends()
	elseif isWaitingHost and pointInRect(x, y, buttons.copy) then
		copyRoomID()
	elseif isWaitingHost and pointInRect(x, y, buttons.back) then
		online_connect.close()
		if type(changeProgram) == "function" then
			changeProgram(2)
		end
	elseif pointInRect(x, y, {x = buttons.host.x, y = inputY, w = buttons.host.w, h = 64}) then
		focused = true
		if love.keyboard and love.keyboard.setTextInput then
			love.keyboard.setTextInput(true)
		end
	elseif pointInRect(x, y, buttons.host) then
		hostRoom()
	elseif pointInRect(x, y, buttons.join) then
		joinRoom()
	elseif pointInRect(x, y, buttons.copy) then
		copyRoomID()
	elseif pointInRect(x, y, buttons.back) then
		online_connect.close()
		if type(changeProgram) == "function" then
			changeProgram(2)
		end
	else
		focused = false
		if love.keyboard and love.keyboard.setTextInput then
			love.keyboard.setTextInput(false)
		end
	end
end

function online_room.mousemoved(x, y)
	hoverAction = nil
	if discordFriendsOpen then
		return
	end
	for name, rect in pairs(buttons) do
		if pointInRect(x, y, rect) then
			hoverAction = name
			break
		end
	end
end

function online_room.textinput(text)
	if not focused or (#roomID >= 64 and not replaceRoomIDOnInput) then
		return
	end

	if replaceRoomIDOnInput then
		roomID = ""
		replaceRoomIDOnInput = false
	end

	roomID = normalizeRoomID(roomID .. text)
	caretTimer = 0
	caretVisible = true
end

function online_room.keypressed(key)
	if discordFriendsOpen then
		if key == "escape" then
			discordFriendsOpen = false
		elseif #discordFriends > 0 and (key == "up" or key == "w" or key == "kpup") then
			selectedDiscordFriendIndex = math.max(1, selectedDiscordFriendIndex - 1)
		elseif #discordFriends > 0 and (key == "down" or key == "s" or key == "kpdown") then
			selectedDiscordFriendIndex = math.min(#discordFriends, selectedDiscordFriendIndex + 1)
		elseif key == "return" or key == "space" or key == "kpenter" then
			inviteSelectedDiscordFriend()
		end
		return
	end

	local controlDown = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
	if focused and controlDown and key == "a" then
		replaceRoomIDOnInput = true
		return
	elseif focused and controlDown and key == "v" then
		if love.system and type(love.system.getClipboardText) == "function" then
			local pastedText = love.system.getClipboardText() or ""
			roomID = normalizeRoomID(pastedText)
			replaceRoomIDOnInput = false
			caretTimer = 0
			caretVisible = true
		end
		return
	end

	if key == "backspace" and focused then
		roomID = roomID:sub(1, -2)
		caretTimer = 0
		caretVisible = true
	elseif key == "return" or key == "kpenter" then
		if focused then
			joinRoom()
		end
	elseif key == "escape" then
		if love.keyboard and love.keyboard.setTextInput then
			love.keyboard.setTextInput(false)
		end
		online_connect.close()
		if type(changeProgram) == "function" then
			changeProgram(2)
		end
	end
end

function online_room.quit()
end

online_connect.on("packet", receivePacket)

return online_room
