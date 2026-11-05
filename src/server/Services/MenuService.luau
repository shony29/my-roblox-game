--!strict
--[[
	MenuService
	===========
	Listens for the main menu's Play button.

	The client only says "I pressed Play". It sends no data, so there is
	nothing to trust. We mark the player with the PressedPlay attribute;
	RoundService watches that attribute and spawns the player.

	(Was server/Data/DataBootstrap.server.luau. Starting PlayerDataService
	moved to the server start-up script, server/init.server.luau.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameContract = require(ReplicatedStorage.Shared.Net.GameContract)

local PLAY_COOLDOWN = 1 -- seconds, ignores spam from exploiters

local MenuService = {}

local lastPlayPress: { [Player]: number } = {}
local started = false

function MenuService.start()
	if started then
		return
	end
	started = true

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
end

return MenuService
