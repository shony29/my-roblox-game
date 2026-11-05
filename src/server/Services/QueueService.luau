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

	Players who leave the game are removed straight away. The interface
	(join/leave/tryStart) stays small so it can move to reserved servers
	(TeleportService) once the game is published.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local MatchState = require(ReplicatedStorage.Shared.Match.MatchState)
local MatchService = require(script.Parent.MatchService)
local LobbyService = require(script.Parent.LobbyService)

type Pad = {
	part: BasePart,
	mode: string,
	bots: boolean,
	radius: number,
	counter: TextLabel,
}

local PATTR = MatchState.PlayerAttr
local CHECK_INTERVAL = 0.25
local PAD_HEIGHT_TOLERANCE = 6

local QueueService = {}

local queues: { [Pad]: { Player } } = {}
local started = false

-- Set by BotService when bots are available (practice pads need them).
QueueService.botsAvailable = true

local function needed(pad: Pad): number
	local mode = ModeConfig.get(pad.mode)
	if not mode then
		return 0
	end
	-- Practice: you can start alone; your team is you (and friends) plus bots.
	return if pad.bots then 1 else mode.TeamSize * mode.TeamCount
end

local function updateCounter(pad: Pad)
	pad.counter.Text = if pad.bots and not QueueService.botsAvailable
		then "SOON"
		else `{#queues[pad]}/{needed(pad)}`
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
		if mode and #queue >= needed(pad) and #queue > 0 then
			-- Real pads take exactly a full match; practice pads take up to one team.
			local count = if pad.bots then math.min(#queue, mode.TeamSize) else needed(pad)
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
	MatchService.onMatchEnded(QueueService.tryStart)
	task.spawn(function()
		while true do
			checkPads()
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return QueueService
