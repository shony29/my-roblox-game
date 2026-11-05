--!strict
--[[
	QueueService: matchmaking on this server (one queue per game mode).

	A client can only ask "queue me for mode X" or "take me out of the
	queue". The server checks:
	  * the mode Id is real (ModeConfig.get),
	  * the player is in the lobby (not on the menu, not already queued,
	    not in a match),
	  * they aren't spamming (RateLimiter).
	When a queue has enough players and no match is running, the first
	players in line are handed to MatchService. Players who leave the game
	are removed straight away, so a queue never holds ghosts.

	This is a same-server prototype. The interface (join/leave/tryStart)
	is kept small so it can later move to cross-server matchmaking.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local MatchState = require(ReplicatedStorage.Shared.Match.MatchState)
local Net = require(ReplicatedStorage.Shared.Net.Net)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)
local MatchService = require(script.Parent.MatchService)

type ModeId = ModeConfig.ModeId

local PATTR = MatchState.PlayerAttr

local QueueService = {}

local queues: { [ModeId]: { Player } } = {}
local limiter = RateLimiter.new(4, 1) -- at most 4 queue requests per second
local started = false

-- Shares how many players wait in each queue (attributes like QueueDuel).
local function publishCounts()
	local folder = ReplicatedStorage:FindFirstChild(MatchState.FOLDER_NAME)
	if folder then
		for _, modeId in ModeConfig.Order do
			folder:SetAttribute("Queue" .. modeId, #queues[modeId])
		end
	end
end

local function clearQueueAttributes(player: Player)
	player:SetAttribute(PATTR.QueueMode, nil)
	player:SetAttribute(PATTR.QueuedAt, nil)
end

function QueueService.leave(player: Player)
	local removed = false
	for _, queue in queues do
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
			removed = true
		end
	end
	if removed and player.Parent == Players then
		clearQueueAttributes(player)
		if player:GetAttribute(PATTR.Status) == "Queued" then
			player:SetAttribute(PATTR.Status, "Lobby")
		end
	end
	publishCounts()
end

function QueueService.tryStart()
	if MatchService.isBusy() then
		return
	end
	for _, modeId in ModeConfig.Order do
		local queue = queues[modeId]
		for i = #queue, 1, -1 do
			if queue[i].Parent ~= Players then
				table.remove(queue, i)
			end
		end
		local mode = ModeConfig.Modes[modeId]
		local needed = mode.TeamSize * mode.TeamCount
		if #queue >= needed then
			local players: { Player } = {}
			for _ = 1, needed do
				local player = table.remove(queue, 1) :: Player
				clearQueueAttributes(player)
				table.insert(players, player)
			end
			publishCounts()
			MatchService.startMatch(mode, players)
			return
		end
	end
	publishCounts()
end

function QueueService.join(player: Player, modeRaw: unknown)
	local mode = ModeConfig.get(modeRaw)
	if mode == nil or player:GetAttribute(PATTR.Status) ~= "Lobby" then
		return -- unknown mode, or not in the lobby (menu, already queued, or in a match)
	end
	table.insert(queues[mode.Id], player)
	player:SetAttribute(PATTR.Status, "Queued")
	player:SetAttribute(PATTR.QueueMode, mode.Id)
	player:SetAttribute(PATTR.QueuedAt, Workspace:GetServerTimeNow())
	publishCounts()
	QueueService.tryStart()
end

function QueueService.start()
	if started then
		return
	end
	started = true
	for _, modeId in ModeConfig.Order do
		queues[modeId] = {}
	end

	Net.event("QueueJoin").OnServerEvent:Connect(function(player: Player, modeRaw: unknown)
		if limiter:allow(player) then
			QueueService.join(player, modeRaw)
		end
	end)
	Net.event("QueueLeave").OnServerEvent:Connect(function(player: Player)
		if limiter:allow(player) then
			QueueService.leave(player)
		end
	end)
	Players.PlayerRemoving:Connect(QueueService.leave)
	MatchService.onMatchEnded(QueueService.tryStart)
	publishCounts()
end

return QueueService
