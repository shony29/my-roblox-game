--!strict
--[[
	Client start-up: the ONLY LocalScript in the game.

	Rojo turns this file into a LocalScript called "Client" in
	StarterPlayerScripts. Everything else in src/client is a ModuleScript
	inside it:
	  Controllers/  the client systems (each has a start function)
	  UI/           screens and HUD pieces
	  Effects/      purely visual effects

	Controllers start here in a fixed order. Each step is protected: if one
	fails, its error is printed in the Output window and the others still start.
]]

local Controllers = script.Controllers

local function run(stepName: string, step: () -> ())
	local ok, err = xpcall(step, debug.traceback)
	if not ok then
		warn(`[Client] "{stepName}" failed to start:\n{err}`)
	end
end

run("GraphicsController", function()
	require(Controllers.GraphicsController).start()
end)

-- The shop goes before the UI, because the menu's Shop button opens it.
run("ShopController", function()
	require(Controllers.ShopController).start()
end)
run("UIController", function()
	require(Controllers.UIController).start()
end)
run("MovementController", function()
	require(Controllers.MovementController).start()
end)
run("WeaponController", function()
	require(Controllers.WeaponController).start()
end)
run("CameraController", function()
	require(Controllers.CameraController).start()
end)
run("ViewmodelController", function()
	require(Controllers.ViewmodelController).start()
end)
run("BlobAnimator", function()
	require(Controllers.BlobAnimator).start()
end)
run("MatchHudController", function()
	require(Controllers.MatchHudController).start()
end)
run("LobbyController", function()
	require(Controllers.LobbyController).start()
end)
run("TransitionController", function()
	require(Controllers.TransitionController).start()
end)
run("ResultsController", function()
	require(Controllers.ResultsController).start()
end)
run("FeedbackController", function()
	require(Controllers.FeedbackController).start()
end)
run("DailyController", function()
	require(Controllers.DailyController).start()
end)
