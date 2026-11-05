--!strict
--[[
	LobbyController: what you see while you're in the bunker lobby.

	  * Top: your coins (the + opens the shop) and your level bar.
	  * Bottom: a big PLAY button with a speech bubble, and a bar with
	    WEAPONS (shop's Guns tab), TASKS (Tasks panel) and SHOP.
	    PLAY asks the server to put you on a queue pad (QueueService picks
	    one: practice against a bot when you're alone, otherwise the real
	    queue closest to starting). Stepping off the pad leaves the queue.
	  * While queued, the bubble says what you're waiting for.
	  * The SHOP counter's prompt opens the shop; the counter in the
	    WEAPONS room opens the shop on the Guns tab.
	(The Daily Squishy machine is handled by DailyController.)

	Queuing itself happens on the server; this script only shows what the
	server shares and asks politely.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModeConfig = require(Shared:WaitForChild("Config"):WaitForChild("ModeConfig"))
local MatchState = require(Shared:WaitForChild("Match"):WaitForChild("MatchState"))
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Data"):WaitForChild("Progression"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))
local ShopController = require(script.Parent:WaitForChild("ShopController"))
local TasksController = require(script.Parent:WaitForChild("TasksController"))

local Colors = Theme.Colors
local PATTR = MatchState.PlayerAttr
local SHOP_PROMPT = "ShopCounter" -- the ProximityPrompt on the lobby's shop counter
local WEAPONS_PROMPT = "WeaponsCounter" -- the counter in the weapons room
local REFRESH_INTERVAL = 0.25
local PLAY_GREEN = Color3.fromRGB(110, 220, 70)

local LobbyController = {}
local started = false

-- A chunky rounded button with a dark outline.
local function chunkyButton(name: string, text: string, size: UDim2, color: Color3, textSize: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.Font = Theme.Fonts.Title
	button.TextSize = textSize
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	UIHelpers.corner(button, UDim.new(0, 14))
	UIHelpers.stroke(button, Colors.Ink, 3)
	UIHelpers.textStroke(button, 2)
	return button
end

function LobbyController.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local stateFolder = ReplicatedStorage:WaitForChild(MatchState.FOLDER_NAME)

	local gui = UIHelpers.screenGui("Lobby", 3, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(gui)

	-- Top: coins, then the level bar ------------------------------------
	local coinPill = UIHelpers.frame("Coins", UDim2.fromOffset(210, 46), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0))
	coinPill.BackgroundColor3 = Colors.Ink
	coinPill.BackgroundTransparency = 0.15
	UIHelpers.corner(coinPill, UDim.new(1, 0))
	coinPill.Parent = gui
	local coinText = UIHelpers.label("Value", "🪙 0", 26, Theme.Fonts.Title)
	coinText.Size = UDim2.new(1, -54, 1, 0)
	coinText.Position = UDim2.fromOffset(8, 0)
	coinText.TextColor3 = Colors.Yolk
	UIHelpers.textStroke(coinText, 2)
	coinText.Parent = coinPill
	local addCoins = chunkyButton("Add", "+", UDim2.fromOffset(38, 38), PLAY_GREEN, 26)
	addCoins.AnchorPoint = Vector2.new(1, 0.5)
	addCoins.Position = UDim2.new(1, -4, 0.5, 0)
	addCoins.Parent = coinPill
	addCoins.Activated:Connect(function()
		ShopController.open()
	end)
	local function updateCoins()
		coinText.Text = `🪙 {UIHelpers.numberAttribute(player, GameContract.PlayerAttributes.Coins)}`
	end
	player:GetAttributeChangedSignal(GameContract.PlayerAttributes.Coins):Connect(updateCoins)
	updateCoins()

	local levelBar = UIHelpers.frame("LevelBar", UDim2.fromOffset(380, 28), UDim2.new(0.5, 0, 0, 64), Vector2.new(0.5, 0))
	UIHelpers.corner(levelBar, UDim.new(1, 0))
	UIHelpers.stroke(levelBar, Colors.Ink, 3)
	levelBar.Parent = gui
	local fill = UIHelpers.frame("Fill", UDim2.fromScale(0, 1), UDim2.new(), nil)
	fill.BackgroundColor3 = Colors.Sky
	fill.BackgroundTransparency = 0
	UIHelpers.corner(fill, UDim.new(1, 0))
	fill.Parent = levelBar
	local levelText = UIHelpers.label("Text", "", 17, Theme.Fonts.Title)
	UIHelpers.textStroke(levelText)
	levelText.Parent = levelBar

	-- Bottom: speech bubble, PLAY, and the button bar --------------------
	local bar = UIHelpers.frame("ButtonBar", UDim2.fromOffset(452, 66), UDim2.new(0.5, 0, 1, -12), Vector2.new(0.5, 1))
	bar.BackgroundColor3 = Colors.Ink
	bar.BackgroundTransparency = 0.3
	UIHelpers.corner(bar, UDim.new(0, 18))
	bar.Parent = gui
	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Padding = UDim.new(0, 10)
	barLayout.Parent = bar
	local barButtons = {
		{ name = "Weapons", text = "🔫 WEAPONS", color = Color3.fromRGB(150, 90, 230) },
		{ name = "Tasks", text = "📋 TASKS", color = Colors.SkyDeep },
		{ name = "Shop", text = "🛒 SHOP", color = Colors.YolkDark },
	}
	for order, info in barButtons do
		local button = chunkyButton(info.name, info.text, UDim2.fromOffset(136, 52), info.color, 20)
		button.LayoutOrder = order
		button.Parent = bar
		button.Activated:Connect(function()
			if info.name == "Weapons" then
				ShopController.openTab("Weapon")
			elseif info.name == "Tasks" then
				TasksController.open()
			else
				ShopController.open()
			end
		end)
	end

	local play = chunkyButton("Play", "PLAY", UDim2.fromOffset(250, 70), PLAY_GREEN, 40)
	play.AnchorPoint = Vector2.new(0.5, 1)
	play.Position = UDim2.new(0.5, 0, 1, -88)
	play.Parent = gui
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	shine.Parent = play
	play.Activated:Connect(function()
		Net.event("QuickPlay"):FireServer()
	end)

	local bubble = UIHelpers.frame("Bubble", UDim2.fromOffset(470, 44), UDim2.new(0.5, 0, 1, -170), Vector2.new(0.5, 1))
	bubble.BackgroundColor3 = Colors.White
	bubble.BackgroundTransparency = 0
	UIHelpers.corner(bubble, UDim.new(0, 12))
	bubble.Parent = gui
	local bubbleText = UIHelpers.label("Text", "", 21, Theme.Fonts.Title)
	bubbleText.TextColor3 = Colors.Ink
	bubbleText.Parent = bubble
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, 0)
	tail.Size = UDim2.fromOffset(16, 16)
	tail.Rotation = 45
	tail.BackgroundColor3 = Colors.White
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = bubble

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
			bubbleText.Text = if matchRunning
				then `{mode.DisplayName}: you're next! ({UIHelpers.formatTime(waited)})`
				else `Waiting for {mode.DisplayName} · {UIHelpers.formatTime(waited)} · step off to leave`
			play.Visible = false
		else
			bubbleText.Text = "Press PLAY, or stand on a pad in the hallway!"
			play.Visible = true
		end
	end

	-- Lobby counters: the shop, and the weapons room.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == SHOP_PROMPT then
			ShopController.open()
		elseif prompt.Name == WEAPONS_PROMPT then
			ShopController.openTab("Weapon")
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
