--!strict
--[[
	Client entry point.
	Rojo turns this file into a LocalScript called "Client" inside
	StarterPlayerScripts, so it runs on each player's own computer.
	It starts each controller (one per topic: HUD, shop, movement, weapon).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Make sure the shared code and the server's remotes have arrived first.
ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")

local Controllers = script.Controllers

require(Controllers.DataController).start()
require(Controllers.HudController).start()
require(Controllers.ShopController).start()
require(Controllers.MovementController).start()
require(Controllers.WeaponController).start()
