--!strict
--[[
	Server entry point.
	Rojo turns this file into a Script called "Server" inside
	ServerScriptService. Its only job is to start each service in order.

	Each service is a ModuleScript in the Services folder that handles one
	topic (saving, combat, shop...). Keeping them separate keeps things tidy.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- 1. Create the remotes first, so clients can find them.
Remotes.setup()

local Services = script.Services

-- 2. Build the map.
require(Services.ArenaBuilder).build()

-- 3. Start the game systems. PlayerData goes first because the others use it.
require(Services.PlayerData).start()
require(Services.CharacterService).start()
require(Services.CombatService).start()
require(Services.ShopService).start()

print("[Jelly Blitz] Server ready!")
