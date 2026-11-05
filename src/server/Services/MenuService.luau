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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameContract = require(ReplicatedStorage.Shared.Net.GameContract)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)

-- At most one Play press per second (ignores spam from exploiters).
local playLimiter = RateLimiter.new(1, 1)

local MenuService = {}

local started = false

function MenuService.start()
	if started then
		return
	end
	started = true

	local playPressed = GameContract.getRemote(GameContract.RemoteNames.PlayPressed)
	playPressed.OnServerEvent:Connect(function(player: Player)
		if not playLimiter:allow(player) then
			return
		end
		player:SetAttribute(GameContract.PlayerAttributes.PressedPlay, true)
	end)
end

return MenuService
