--!strict
--[[
	LobbyController: what you see while you're in the bunker lobby.

	  * Level bar at the bottom: "Lv. 3 [=====] 120 / 350 XP".
	  * While standing on a queue pad: "Waiting on 1v1 DUEL · 0:12 - step
	    off the pad to leave".
	  * The SHOP counter's prompt opens the shop window.
	(The Daily Squishy machine is handled by DailyController.)

	Queuing itself happens on the server (QueueService watches the pads);
	this script only shows what the server shares.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModeConfig = require(Shared:WaitForChild("Config"):WaitForChild("ModeConfig"))
local MatchState = require(Shared:WaitForChild("Match"):WaitForChild("MatchState"))
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))
local Progression = require(Shared:WaitForChild("Data"):WaitForChild("Progression"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))
local ShopController = require(script.Parent:WaitForChild("ShopController"))

local Colors = Theme.Colors
local PATTR = MatchState.PlayerAttr
local SHOP_PROMPT = "ShopCounter" -- the ProximityPrompt on the lobby's shop counter
local REFRESH_INTERVAL = 0.25

local LobbyController = {}
local started = false

function LobbyController.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local stateFolder = ReplicatedStorage:WaitForChild(MatchState.FOLDER_NAME)

	local gui = UIHelpers.screenGui("Lobby", 3, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(gui)

	-- Level bar (bottom centre).
	local levelBar = UIHelpers.frame("LevelBar", UDim2.fromOffset(460, 34), UDim2.new(0.5, 0, 1, -24), Vector2.new(0.5, 1))
	UIHelpers.corner(levelBar, UDim.new(1, 0))
	UIHelpers.stroke(levelBar, Colors.Ink, 3)
	levelBar.Parent = gui
	local fill = UIHelpers.frame("Fill", UDim2.fromScale(0, 1), UDim2.new(), nil)
	fill.BackgroundColor3 = Colors.Sky
	fill.BackgroundTransparency = 0
	UIHelpers.corner(fill, UDim.new(1, 0))
	fill.Parent = levelBar
	local levelText = UIHelpers.label("Text", "", 18, Theme.Fonts.Title)
	UIHelpers.textStroke(levelText)
	levelText.Parent = levelBar

	-- Queue banner (top centre).
	local banner = UIHelpers.label("QueueBanner", "", 22, Theme.Fonts.Title)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 74)
	banner.Size = UDim2.fromOffset(640, 30)
	banner.TextColor3 = Colors.Yolk
	UIHelpers.textStroke(banner, 2)
	banner.Parent = gui

	local function refresh()
		local status = player:GetAttribute(PATTR.Status)
		gui.Enabled = status == "Lobby" or status == "Queued"
		if not gui.Enabled then
			return
		end
		local level, into, needed = Progression.levelFromXp(UIHelpers.numberAttribute(player, GameContract.PlayerAttributes.XP))
		fill.Size = UDim2.fromScale(math.clamp(into / needed, 0.04, 1), 1)
		levelText.Text = `Lv. {level}    {into} / {needed} XP`

		local mode = ModeConfig.get(player:GetAttribute(PATTR.QueueMode))
		if status == "Queued" and mode then
			local waited = Workspace:GetServerTimeNow() - UIHelpers.numberAttribute(player, PATTR.QueuedAt)
			local matchRunning = MatchState.toState(stateFolder:GetAttribute(MatchState.Attr.State)) ~= "Lobby"
			banner.Text = if matchRunning
				then `{mode.DisplayName}: a match is running, you're next ({UIHelpers.formatTime(waited)})`
				else `Waiting on {mode.DisplayName} · {UIHelpers.formatTime(waited)} · step off the pad to leave`
		else
			banner.Text = ""
		end
	end

	-- The shop counter opens the shop window.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == SHOP_PROMPT then
			ShopController.open()
		end
	end)

	player:GetAttributeChangedSignal(PATTR.Status):Connect(refresh)
	task.spawn(function()
		while gui.Parent do
			refresh()
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

return LobbyController
