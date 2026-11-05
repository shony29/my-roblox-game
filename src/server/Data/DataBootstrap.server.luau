--!strict
--[[
	DataBootstrap
	=============
	Starts the player data system and listens for the main menu's Play button.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GameContract = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("GameContract"))

PlayerDataService.start()

--[[
	Play button: the client only tells us "I pressed Play". It sends no
	data, so there is nothing to trust. We mark the player with an
	attribute that the round/spawn code can watch:

		player:GetAttributeChangedSignal("PressedPlay"):Connect(...)
]]
local PLAY_COOLDOWN = 1 -- seconds, ignores spam from exploiters
local lastPlayPress: { [Player]: number } = {}

local playPressed = GameContract.getRemote(GameContract.RemoteNames.PlayPressed)
playPressed.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	local last = lastPlayPress[player]
	if last and now - last < PLAY_COOLDOWN then
		return
	end
	lastPlayPress[player] = now
	player:SetAttribute(GameContract.PlayerAttributes.PressedPlay, true)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastPlayPress[player] = nil
end)
