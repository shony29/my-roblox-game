--!strict
--[[
	QueueService: matchmaking with queue pads (same server for now).

	In the lobby hallway, each glowing pad is a queue for one mode. The
	server checks four times a second who is standing on which pad (a
	client can't fake its position into a queue: only the server's view of
	the character counts):
	  * stand on a pad  -> you join that pad's queue,
	  * step off         -> you leave it,
	  * the pad's counter shows "players / needed",
	  * when a queue is full and no match is running, the match starts.
	Practice pads (vs bots) start as soon as one player stands on them;
	bots fill the empty places (BotService). Until bots exist those pads
	just show "SOON".
	The FREE FOR ALL pad (end of the hallway) needs at least MinPlayers (3);
	then everyone else gets FillTime seconds to hop on, up to MaxPlayers (25).

	Players who leave the game are removed straight away. The interface
	(join/leave/tryStart) stays small so it can move to reserved servers
	(TeleportService) once the game is published.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local MatchState = require(ReplicatedStorage.Shared.Match.MatchState)
local Net = require(ReplicatedStorage.Shared.Net.Net)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)
local LobbyBuilder = require(script.Parent.Parent.Map.LobbyBuilder)
local MatchService = require(script.Parent.MatchService)
local LobbyService = require(script.Parent.LobbyService)

type Pad = LobbyBuilder.Pad

local MAX_AVATARS = 8
local quickPlayLimiter = RateLimiter.new(1, 2)

local PATTR = MatchState.PlayerAttr
local CHECK_INTERVAL = 0.25
local PAD_HEIGHT_TOLERANCE = 6

local QueueService = {}

local queues: { [Pad]: { Player } } = {}
local fillUntil: { [Pad]: number } = {} -- free for all: when the joining time ends
local started = false

-- Set by BotService when bots are available (practice pads need them).
QueueService.botsAvailable = true

local function needed(pad: Pad): number
	local mode = ModeConfig.get(pad.mode)
	if not mode then
		return 0
	end
	-- Practice: you can start alone; your team is you (and friends) plus bots.
	if pad.bots then
		return 1
	end
	-- Free for all: enough players to start (more can join until it begins).
	return mode.MinPlayers or mode.TeamSize * mode.TeamCount
end

-- The queue's player pictures on the pad's screen (Roblox avatar headshots).
local function updateAvatars(pad: Pad)
	local holder = pad.avatars
	if holder == nil then
		return
	end
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, player in queues[pad] do
		if index > MAX_AVATARS then
			break
		end
		-- (The screen's grid layout decides each card's size.)
		local card = Instance.new("Frame")
		card.Name = player.Name
		card.LayoutOrder = index
		card.BackgroundTransparency = 1
		card.Parent = holder
		local picture = Instance.new("ImageLabel")
		picture.AnchorPoint = Vector2.new(0.5, 0)
		picture.Position = UDim2.fromScale(0.5, 0)
		picture.Size = UDim2.fromScale(0.8, 0.72)
		picture.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
		picture.Image = `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=150&h=150`
		picture.Parent = card
		local square = Instance.new("UIAspectRatioConstraint")
		square.AspectRatio = 1
		square.Parent = picture
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = picture
		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromScale(0, 0.76)
		name.Size = UDim2.fromScale(1, 0.24)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Text = player.DisplayName
		name.Parent = card
	end
end

local function updateCounter(pad: Pad)
	local deadline = fillUntil[pad]
	local text = if pad.bots and not QueueService.botsAvailable
		then "SOON"
		elseif deadline then `{#queues[pad]} · {math.max(0, math.ceil(deadline - os.clock()))}s`
		else `{#queues[pad]}/{needed(pad)}`
	pad.counter.Text = text
	if pad.screenCount then
		pad.screenCount.Text = text
	end
	updateAvatars(pad)
end

local function padUnder(player: Player): Pad?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	for pad in queues do
		local offset = root.Position - pad.part.Position
		if Vector2.new(offset.X, offset.Z).Magnitude <= pad.radius and math.abs(offset.Y) <= PAD_HEIGHT_TOLERANCE then
			return pad
		end
	end
	return nil
end

local function queuedPad(player: Player): Pad?
	for pad, queue in queues do
		if table.find(queue, player) then
			return pad
		end
	end
	return nil
end

function QueueService.leave(player: Player)
	local pad = queuedPad(player)
	if not pad then
		return
	end
	local queue = queues[pad]
	table.remove(queue, table.find(queue, player) :: number)
	updateCounter(pad)
	if player.Parent == Players then
		player:SetAttribute(PATTR.QueueMode, nil)
		player:SetAttribute(PATTR.QueuedAt, nil)
		if player:GetAttribute(PATTR.Status) == "Queued" then
			player:SetAttribute(PATTR.Status, "Lobby")
		end
	end
end

function QueueService.join(player: Player, pad: Pad)
	if queuedPad(player) == pad or player:GetAttribute(PATTR.Status) ~= "Lobby" and player:GetAttribute(PATTR.Status) ~= "Queued" then
		return
	end
	if pad.bots and not QueueService.botsAvailable then
		return
	end
	QueueService.leave(player)
	table.insert(queues[pad], player)
	player:SetAttribute(PATTR.Status, "Queued")
	player:SetAttribute(PATTR.QueueMode, pad.mode)
	player:SetAttribute(PATTR.QueuedAt, Workspace:GetServerTimeNow())
	updateCounter(pad)
	QueueService.tryStart()
end

function QueueService.tryStart()
	if MatchService.isBusy() then
		return
	end
	for pad, queue in queues do
		for i = #queue, 1, -1 do
			if queue[i].Parent ~= Players then
				table.remove(queue, i)
			end
		end
		local mode = ModeConfig.get(pad.mode)
		if mode and mode.FreeForAll and not pad.bots then
			-- Free for all: wait FillTime once there are enough, so others can join.
			if #queue < needed(pad) then
				if fillUntil[pad] then
					fillUntil[pad] = nil
					updateCounter(pad)
				end
				continue
			end
			if not fillUntil[pad] then
				fillUntil[pad] = os.clock() + (mode.FillTime or 15)
			end
			if os.clock() < (fillUntil[pad] :: number) and #queue < (mode.MaxPlayers or 25) then
				updateCounter(pad)
				continue
			end
			fillUntil[pad] = nil
		end
		if mode and #queue >= needed(pad) and #queue > 0 then
			-- Real pads take exactly a full match; practice pads take up to one
			-- team; free for all takes everyone waiting (up to MaxPlayers).
			local count = if pad.bots
				then math.min(#queue, mode.TeamSize)
				elseif mode.FreeForAll then math.min(#queue, mode.MaxPlayers or 25)
				else needed(pad)
			local players: { Player } = {}
			for _ = 1, count do
				local player = table.remove(queue, 1) :: Player
				player:SetAttribute(PATTR.QueueMode, nil)
				player:SetAttribute(PATTR.QueuedAt, nil)
				table.insert(players, player)
			end
			updateCounter(pad)
			MatchService.startMatch(mode, players, pad.bots)
			return
		end
	end
end

local function checkPads()
	-- Anyone who went somewhere else (practice range, a match) leaves their queue.
	for pad, queue in queues do
		local changed = false
		for i = #queue, 1, -1 do
			local player = queue[i]
			if player.Parent ~= Players or player:GetAttribute(PATTR.Status) ~= "Queued" then
				table.remove(queue, i)
				changed = true
			end
		end
		if changed then
			updateCounter(pad)
		end
	end
	for _, player in Players:GetPlayers() do
		local status = player:GetAttribute(PATTR.Status)
		if status == "Lobby" or status == "Queued" then
			local pad = padUnder(player)
			if pad then
				QueueService.join(player, pad)
			elseif status == "Queued" then
				QueueService.leave(player)
			end
		end
	end
	-- A free-for-all joining countdown is running: keep it ticking.
	if next(fillUntil) ~= nil then
		QueueService.tryStart()
	end
end

--[[
	The lobby's PLAY button: puts the player straight onto a queue pad.
	  * Alone in the server: the 1v1 vs BOT pad, so you can play right away.
	  * Otherwise: the real-player pad closest to starting (ties: 1v1).
	Standing on the pad then queues them as usual (so stepping off leaves).
]]
function QueueService.quickPlay(player: Player)
	local status = player:GetAttribute(PATTR.Status)
	local character = player.Character
	if (status ~= "Lobby" and status ~= "Queued") or character == nil then
		return
	end
	local alone = #Players:GetPlayers() <= 1
	local best: Pad? = nil
	local bestScore = -math.huge
	for pad, queue in queues do
		local total = needed(pad)
		if pad.bots == alone and total > 0 and (pad.bots or #queue < total) then
			local score = if alone then 0 else #queue / total
			if pad.mode == ModeConfig.Default then
				score += 0.01 -- prefer 1v1 when everything else is equal
			end
			if score > bestScore then
				best, bestScore = pad, score
			end
		end
	end
	if best then
		character:PivotTo(CFrame.new(best.part.Position + Vector3.new(0, 4, 0)))
	end
end

function QueueService.refreshCounters()
	for pad in queues do
		updateCounter(pad)
	end
end

function QueueService.start()
	if started then
		return
	end
	started = true
	for _, pad in LobbyService.getPads() do
		queues[pad] = {}
	end
	QueueService.refreshCounters()
	Players.PlayerRemoving:Connect(QueueService.leave)
	Net.event("QuickPlay").OnServerEvent:Connect(function(player: Player)
		if quickPlayLimiter:allow(player) then
			QueueService.quickPlay(player)
		end
	end)
	MatchService.onMatchEnded(QueueService.tryStart)
	task.spawn(function()
		while true do
			checkPads()
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return QueueService
