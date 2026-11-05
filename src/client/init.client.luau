--!strict
--[[
	Client start-up: the ONLY LocalScript in the game.

	Rojo turns this file into a LocalScript called "Client" in
	StarterPlayerScripts. Everything else in src/client is a ModuleScript
	inside it:
	  Controllers/  the client systems (each has a start function)
	  UI/           screens and HUD pieces
	  Effects/      purely visual effects

	Controllers start here in a fixed order. Each step is protected:
	  * if one fails, its error is printed in the Output window and the
	    others still start;
	  * if one takes too long, the next ones start anyway.

	It also shows the game version on the main menu, and a small message
	on screen if any part of the game (here or on the server) failed to
	start, so problems are easy to spot even without the Output window.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Controllers
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local STEP_TIMEOUT = 5 -- seconds before we stop waiting for a slow step

local player = Players.LocalPlayer
local problems: { string } = {}

local function run(stepName: string, step: () -> ())
	local finished = false
	task.spawn(function()
		local ok, err = xpcall(step, debug.traceback)
		if not ok then
			table.insert(problems, stepName)
			warn(`[Client] "{stepName}" failed to start:\n{err}`)
		end
		finished = true
	end)
	local waited = 0
	while not finished and waited < STEP_TIMEOUT do
		waited += task.wait()
	end
	if not finished then
		warn(`[Client] "{stepName}" is still starting after {STEP_TIMEOUT} seconds; starting the rest anyway.`)
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
run("TeamOutlineController", function()
	require(Controllers.TeamOutlineController).start()
end)

---------------------------------------------------------------------------
-- Start-up report: version label + a message if anything failed.
-- Built with plain Instances (no other modules), so it still works when
-- the UI code is the part that broke.
---------------------------------------------------------------------------

local playerGui = player:WaitForChild("PlayerGui")

local reportGui = Instance.new("ScreenGui")
reportGui.Name = "StartupReport"
reportGui.DisplayOrder = 100
reportGui.IgnoreGuiInset = true
reportGui.ResetOnSpawn = false
reportGui.Parent = playerGui

local versionLabel = Instance.new("TextLabel")
versionLabel.Name = "Version"
versionLabel.AnchorPoint = Vector2.new(0, 1)
versionLabel.Position = UDim2.new(0, 12, 1, -8)
versionLabel.Size = UDim2.fromOffset(320, 22)
versionLabel.BackgroundTransparency = 1
versionLabel.Font = Enum.Font.GothamBold
versionLabel.TextSize = 14
versionLabel.TextXAlignment = Enum.TextXAlignment.Left
versionLabel.TextColor3 = Color3.new(1, 1, 1)
versionLabel.TextStrokeTransparency = 0.4
versionLabel.Text = `{GameConfig.GameName} v{GameConfig.Version}`
versionLabel.Parent = reportGui

local problemButton = Instance.new("TextButton")
problemButton.Name = "Problems"
problemButton.AnchorPoint = Vector2.new(0.5, 0)
problemButton.Position = UDim2.new(0.5, 0, 0, 12)
problemButton.Size = UDim2.new(0.9, 0, 0, 0)
problemButton.AutomaticSize = Enum.AutomaticSize.Y
problemButton.BackgroundColor3 = Color3.fromRGB(150, 40, 60)
problemButton.BackgroundTransparency = 0.1
problemButton.AutoButtonColor = false
problemButton.Font = Enum.Font.GothamBold
problemButton.TextSize = 16
problemButton.TextWrapped = true
problemButton.TextColor3 = Color3.new(1, 1, 1)
problemButton.Visible = false
problemButton.Parent = reportGui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = problemButton
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.Parent = problemButton

local dismissed = false
problemButton.Activated:Connect(function()
	dismissed = true
	problemButton.Visible = false
end)

local function readString(name: string): string
	local value = ReplicatedStorage:GetAttribute(name)
	return if typeof(value) == "string" then value else ""
end

local function refreshReport()
	-- The version only shows on the main menu (before pressing Play).
	versionLabel.Visible = player:GetAttribute("MatchStatus") == nil or player:GetAttribute("MatchStatus") == "Menu"

	local lines: { string } = {}
	local serverProblems = readString("ServerProblems")
	if serverProblems ~= "" then
		table.insert(lines, `Server: {serverProblems}`)
	end
	if #problems > 0 then
		table.insert(lines, `Your screen: {table.concat(problems, ", ")}`)
	end
	local serverVersion = readString("ServerVersion")
	if serverVersion ~= "" and serverVersion ~= GameConfig.Version then
		table.insert(lines, `Version mismatch: server {serverVersion}, client {GameConfig.Version}`)
	end
	if #lines == 0 or dismissed then
		problemButton.Visible = false
		return
	end
	problemButton.Text = "Some parts of the game didn't start: "
		.. table.concat(lines, "  ·  ")
		.. "\nIn Studio, open View → Output to see why. (Click to hide.)"
	problemButton.Visible = true
end

ReplicatedStorage:GetAttributeChangedSignal("ServerProblems"):Connect(refreshReport)
ReplicatedStorage:GetAttributeChangedSignal("ServerVersion"):Connect(refreshReport)
player:GetAttributeChangedSignal("MatchStatus"):Connect(refreshReport)
refreshReport()

if #problems == 0 then
	print(`[Slime Showdown] Client started: all systems OK (version {GameConfig.Version})`)
else
	warn(`[Slime Showdown] Client started, but these failed: {table.concat(problems, ", ")}. Scroll up for the error text.`)
end
