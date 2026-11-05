--!strict
--[[
	Server start-up: the ONLY server Script in the game.

	Rojo turns this file into a Script called "Server" in ServerScriptService.
	Everything else in src/server is a ModuleScript inside it:
	  Services/    the server systems (each has a start function)
	  Components/  builders the services use (blob, gun model, score maths)
	  Map/         builds the arena

	Services start here, one after another, in a fixed order. (Separate
	Scripts start in a random order, which once caused a kill-feed bug.)
	Each step is protected: if one fails, its error is printed in the Output
	window and the other systems still start.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Services = script.Services

local function run(stepName: string, step: () -> ())
	local ok, err = xpcall(step, debug.traceback)
	if not ok then
		warn(`[Server] "{stepName}" failed to start:\n{err}`)
	end
end

-- 0. Every RemoteEvent/RemoteFunction (Shared/Net/Net.luau), before anything uses them.
run("Net", function()
	require(Shared.Net.Net).setup()
end)

-- 1. Physics groups that decide what bullets can hit.
run("HitGroups", function()
	require(Shared.Combat.HitGroups).setup()
end)

-- 1b. One fixed slime body for every player (StarterCharacter), before anyone spawns.
run("SlimeRig", function()
	require(script.Components.SlimeRig).install()
end)

-- 2. Saved data first: coins, stats and owned items that other systems read.
run("PlayerDataService", function()
	require(Services.PlayerDataService).start()
end)

-- 3. Main menu Play button, and the shop (also puts on equipped cosmetics).
run("MenuService", function()
	require(Services.MenuService).start()
end)
run("ShopService", function()
	require(Services.ShopService).start()
end)

-- 4. Gameplay systems.
run("MovementService", function()
	require(Services.MovementService).start()
end)
run("WeaponService", function()
	require(Services.WeaponService).start()
end)

-- 5. Build the map, then start the match system (which spawns players).
run("Map and matches", function()
	local arena = require(script.Map.ArenaBuilder).build()
	require(Services.SpawnService).init(arena.spawnPoints)
	require(Services.MatchService).start()
end)

print("[Slime Showdown] Server started")
