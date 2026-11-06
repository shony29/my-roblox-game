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
	Each step is protected:
	  * if one fails, its error is printed in the Output window and the
	    other systems still start;
	  * if one takes too long, the next ones start anyway.
	At the end, one line in the Output says how many systems started. The
	same report is shown on players' screens if something failed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Services = script.Services
local GameConfig = require(Shared.Config.GameConfig)

local STEP_TIMEOUT = 10 -- seconds before we stop waiting for a slow step

local problems: { string } = {}
local stepCount = 0

local function run(stepName: string, step: () -> ())
	stepCount += 1
	local finished = false
	task.spawn(function()
		local ok, err = xpcall(step, debug.traceback)
		if not ok then
			table.insert(problems, stepName)
			warn(`[Server] "{stepName}" failed to start:\n{err}`)
		end
		finished = true
	end)
	local waited = 0
	while not finished and waited < STEP_TIMEOUT do
		waited += task.wait()
	end
	if not finished then
		warn(`[Server] "{stepName}" is still starting after {STEP_TIMEOUT} seconds; starting the rest anyway.`)
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
run("DailyService", function()
	require(Services.DailyService).start()
end)
run("RobuxService", function()
	require(Services.RobuxService).start() -- Robux purchases (monthly themed items)
end)
run("QuestService", function()
	require(Services.QuestService).start() -- beginner tasks and daily quests
end)
run("SettingsService", function()
	require(Services.SettingsService).start() -- saves the Settings window choices
end)

-- 4. Gameplay systems.
run("MovementService", function()
	require(Services.MovementService).start()
end)
run("WeaponService", function()
	require(Services.WeaponService).start()
end)
run("AmmoService", function()
	require(Services.AmmoService).start() -- slime ammo balls on the maps
end)

-- 5. The lobby first (pressing Play puts you there), then the arena,
-- matches and matchmaking. Separate steps, so a broken map can't stop
-- the lobby from working.
run("LobbyService", function()
	require(Services.LobbyService).start() -- the slime bunker lobby
end)
run("MapService", function()
	-- Build the default map now, so the arena is ready before the first match.
	local MapConfig = require(Shared.Config.MapConfig)
	if not require(Services.MapService).load(MapConfig.Default) then
		error(`the default map "{MapConfig.Default}" could not be built (see the warning above)`)
	end
end)
run("PracticeService", function()
	require(Services.PracticeService).start() -- the practice range (aim training)
end)
run("BotService", function()
	require(Services.BotService).start() -- practice bots (only act during rounds)
end)
run("MatchService", function()
	require(Services.MatchService).start()
end)
run("QueueService", function()
	require(Services.QueueService).start() -- the queue pads hand full queues to MatchService
end)

-- The report: in the Output, and as attributes the client's start-up shows on screen.
ReplicatedStorage:SetAttribute("ServerVersion", GameConfig.Version)
ReplicatedStorage:SetAttribute("ServerProblems", table.concat(problems, ", "))
if #problems == 0 then
	print(`[Slime Showdown] Server started: all {stepCount} systems OK (version {GameConfig.Version})`)
else
	warn(
		`[Slime Showdown] Server started, but {#problems} of {stepCount} systems failed: {table.concat(problems, ", ")}. `
			.. "Scroll up in the Output window for the orange error text of each one."
	)
end
