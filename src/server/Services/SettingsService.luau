--!strict
--[[
	SettingsService: saves each player's Settings window choices (sound
	volume, mouse sensitivity and field of view) with their other data.

	The client sends all three numbers when the player changes something.
	Nothing is trusted: PlayerDataService.setSettings keeps every number
	inside its allowed range (Data/PlayerDataSchema.SETTINGS), and a player
	can save at most a few times per second.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net.Net)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)
local PlayerDataService = require(script.Parent.PlayerDataService)

local SettingsService = {}

local started = false
local limiter = RateLimiter.new(4, 2) -- at most 4 saves every 2 seconds

function SettingsService.start()
	if started then
		return
	end
	started = true
	Net.event("SettingsSave").OnServerEvent:Connect(function(player: Player, volume: unknown, sensitivity: unknown, fieldOfView: unknown)
		if not limiter:allow(player) then
			return
		end
		PlayerDataService.setSettings(player, volume, sensitivity, fieldOfView)
	end)
end

return SettingsService
