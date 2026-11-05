--!strict
--[[
	LobbyController: the "Play" panel you see in the lobby.

	  * Pick a game mode (1v1 Duel, 2v2 Team Duel, 4v4 Team Combat). Each
	    button shows how many players are waiting for it.
	  * FIND MATCH joins that mode's queue; while searching you see the
	    waiting time and a CANCEL button.
	  * Only visible while you're in the lobby (not on the menu or in a match).

	The panel only ASKS the server (QueueJoin / QueueLeave); the server
	decides, and the panel just shows the attributes the server sets.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModeConfig = require(Shared:WaitForChild("Config"):WaitForChild("ModeConfig"))
local MatchState = require(Shared:WaitForChild("Match"):WaitForChild("MatchState"))
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))
local Progression = require(Shared:WaitForChild("Data"):WaitForChild("Progression"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))

type ModeId = ModeConfig.ModeId

local Colors = Theme.Colors
local PATTR = MatchState.PlayerAttr
local REFRESH_INTERVAL = 0.25

local LobbyController = {}
local started = false

local function makeButton(parent: Instance, name: string, text: string, y: number, height: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = Theme.Fonts.Title
	button.TextSize = 20
	button.TextColor3 = Colors.Ink
	button.BackgroundColor3 = Colors.White
	button.AutoButtonColor = true
	button.Position = UDim2.fromOffset(14, y)
	button.Size = UDim2.new(1, -28, 0, height)
	UIHelpers.corner(button, UDim.new(0, 12))
	UIHelpers.stroke(button, Colors.Ink, 2)
	button.Parent = parent
	return button
end

function LobbyController.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local stateFolder = ReplicatedStorage:WaitForChild(MatchState.FOLDER_NAME)
	local queueJoin = Net.event("QueueJoin")
	local queueLeave = Net.event("QueueLeave")

	local gui = UIHelpers.screenGui("Lobby", 3, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(gui)

	local panel = UIHelpers.frame("PlayPanel", UDim2.fromOffset(300, 300), UDim2.new(0, Theme.Margin, 0.5, 0), Vector2.new(0, 0.5))
	UIHelpers.corner(panel, UDim.new(0, 18))
	UIHelpers.stroke(panel, Colors.Yolk, 3)
	panel.Parent = gui

	local title = UIHelpers.label("Title", "PLAY", 30, Theme.Fonts.Title)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.fromOffset(0, 8)
	title.TextColor3 = Colors.Yolk
	UIHelpers.textStroke(title)
	title.Parent = panel

	local selected: ModeId = ModeConfig.Default
	local modeButtons: { [ModeId]: TextButton } = {}
	for index, modeId in ModeConfig.Order do
		local button = makeButton(panel, modeId, "", 54 + (index - 1) * 50, 42)
		button.Activated:Connect(function()
			if player:GetAttribute(PATTR.Status) == "Lobby" then
				selected = modeId
			end
		end)
		modeButtons[modeId] = button
	end

	local statusLabel = UIHelpers.label("Status", "", 16)
	statusLabel.Size = UDim2.new(1, -20, 0, 24)
	statusLabel.Position = UDim2.fromOffset(10, 206)
	statusLabel.TextColor3 = Colors.Shell
	statusLabel.Parent = panel

	local action = makeButton(panel, "Action", "FIND MATCH", 236, 50)
	action.TextSize = 26

	action.Activated:Connect(function()
		local status = player:GetAttribute(PATTR.Status)
		if status == "Queued" then
			queueLeave:FireServer()
		elseif status == "Lobby" then
			queueJoin:FireServer(selected)
		end
	end)

	local function refresh()
		local status = player:GetAttribute(PATTR.Status)
		local queued = status == "Queued"
		gui.Enabled = status == "Lobby" or queued
		if not gui.Enabled then
			return
		end

		local queuedMode = ModeConfig.get(player:GetAttribute(PATTR.QueueMode))
		if queued and queuedMode then
			selected = queuedMode.Id
		end

		for modeId, button in modeButtons do
			local mode = ModeConfig.Modes[modeId]
			local waiting = UIHelpers.numberAttribute(stateFolder, "Queue" .. modeId)
			local needed = mode.TeamSize * mode.TeamCount
			button.Text = `{mode.DisplayName}   ({waiting}/{needed})`
			local isSelected = modeId == selected
			button.BackgroundColor3 = if isSelected then Colors.Mint else Colors.White
			button.AutoButtonColor = not queued
		end

		if queued and queuedMode then
			local waitedFor = Workspace:GetServerTimeNow() - UIHelpers.numberAttribute(player, PATTR.QueuedAt)
			local matchRunning = MatchState.toState(stateFolder:GetAttribute(MatchState.Attr.State)) ~= "Lobby"
			statusLabel.Text = if matchRunning
				then `A match is running · you're next ({UIHelpers.formatTime(waitedFor)})`
				else `Searching {queuedMode.DisplayName}... {UIHelpers.formatTime(waitedFor)}`
			action.Text = "CANCEL"
			action.BackgroundColor3 = Colors.Coral
		else
			local level, into, needed = Progression.levelFromXp(UIHelpers.numberAttribute(player, GameContract.PlayerAttributes.XP))
			title.Text = `PLAY · LEVEL {level}`
			statusLabel.Text = `{into}/{needed} XP to level {level + 1}`
			action.Text = "FIND MATCH"
			action.BackgroundColor3 = Colors.Mint
		end
	end

	player:GetAttributeChangedSignal(PATTR.Status):Connect(refresh)
	task.spawn(function()
		while gui.Parent do
			refresh()
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

return LobbyController
