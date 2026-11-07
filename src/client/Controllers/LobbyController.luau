--!strict
--[[
	LobbyController: what you see while you're in the bunker lobby.

	  * Top: your level bar. (Top right: settings, tasks and notifications,
	    see CornerMenuController.)
	  * Left: SHOP (B), TASKS (T) and WEAPONS (the shop's Guns tab).
	  * Bottom: a big PLAY button with a speech bubble.
	    PLAY asks the server to put you on a queue pad (QueueService picks
	    one: practice against a bot when you're alone, otherwise the real
	    queue closest to starting). Stepping off the pad leaves the queue.
	  * While queued, the bubble says what you're waiting for.
	  * The counter in the WEAPONS room opens the shop on the Guns tab.
	    (The shop itself is a window: B, or the SHOP buttons.)
	(The Daily Squishy machine is handled by DailyController.)

	Queuing itself happens on the server; this script only shows what the
	server shares and asks politely.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
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
local Icons = require(UIFolder:WaitForChild("Icons"))
local ShopController = require(script.Parent:WaitForChild("ShopController"))
local TasksController = require(script.Parent:WaitForChild("TasksController"))

local PATTR = MatchState.PlayerAttr
local WEAPONS_PROMPT = "WeaponsCounter" -- the counter in the weapons room
local ROBUX_PROMPT = "RobuxCounter" -- the counter in the ROBUX SHOP room
local REFRESH_INTERVAL = 0.25
local Sci = Theme.SciFi -- the bunker's sci-fi look (same as the menu and shop)
local SCI_FONT = Theme.SciFiFonts.Title
local BODY_FONT = Theme.SciFiFonts.Body

local LobbyController = {}
local started = false

--[[
	A sci-fi button: dark glass with a neon edge and neon text in `accent`.
	`filled` makes it a solid neon button with dark text instead (PLAY).
	Returns the button and its glowing edge.
]]
local function sciButton(name: string, text: string, size: UDim2, accent: Color3, textSize: number, filled: boolean): (TextButton, UIStroke)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = if filled then accent else Sci.Panel
	button.BackgroundTransparency = if filled then 0 else 0.12
	button.AutoButtonColor = false
	button.Font = SCI_FONT
	button.TextSize = textSize
	button.TextColor3 = if filled then Sci.Void else accent
	button.Text = text
	UIHelpers.corner(button, UDim.new(0, 10))
	local edge = UIHelpers.stroke(button, if filled then accent:Lerp(Color3.new(1, 1, 1), 0.4) else accent, 2)
	edge.Transparency = 0.1
	-- Light up a little on hover.
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		UIHelpers.tween(scale, 0.12, { Scale = 1.05 }, Enum.EasingStyle.Back)
		if not filled then
			UIHelpers.tween(button, 0.12, { BackgroundColor3 = Sci.PanelLight })
		end
	end)
	button.MouseLeave:Connect(function()
		UIHelpers.tween(scale, 0.12, { Scale = 1 })
		if not filled then
			UIHelpers.tween(button, 0.12, { BackgroundColor3 = Sci.Panel })
		end
	end)
	return button, edge
end

--[[
	A button for the menu on the left: dark glass, a neon edge and stripe in
	`accent`, a drawn icon, the label, and its keyboard key on the right.
]]
local function menuButton(name: string, text: string, key: string, accent: Color3, drawIcon: (GuiObject, Color3, Color3) -> ()): TextButton
	local button = sciButton(name, text, UDim2.fromOffset(214, 58), accent, 17, false)
	button.TextXAlignment = Enum.TextXAlignment.Left
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 64)
	padding.Parent = button
	-- A glowing stripe down the left edge.
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.AnchorPoint = Vector2.new(0, 0.5)
	stripe.Position = UDim2.new(0, -58, 0.5, 0)
	stripe.Size = UDim2.new(0, 4, 1, -18)
	stripe.BackgroundColor3 = accent
	stripe.BorderSizePixel = 0
	UIHelpers.corner(stripe, UDim.new(1, 0))
	stripe.Parent = button
	drawIcon(Icons.holder(button, UDim2.fromOffset(32, 32), UDim2.new(0, -42, 0.5, 0), Vector2.new(0, 0.5)), accent, Sci.Panel)
	-- The keyboard key, in a small dim box.
	local keyBox = UIHelpers.label("Key", key, 12, SCI_FONT)
	keyBox.AnchorPoint = Vector2.new(1, 0.5)
	keyBox.Position = UDim2.new(1, -10, 0.5, 0)
	keyBox.Size = UDim2.fromOffset(24, 24)
	keyBox.TextColor3 = Sci.Dim
	UIHelpers.corner(keyBox, UDim.new(0, 6))
	UIHelpers.stroke(keyBox, Sci.Dim, 1).Transparency = 0.4
	keyBox.Parent = button
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

	-- Top: the level bar --------------------------------------------------
	local levelBar = UIHelpers.frame("LevelBar", UDim2.fromOffset(380, 26), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0))
	levelBar.BackgroundColor3 = Sci.Inset
	levelBar.BackgroundTransparency = 0.1
	UIHelpers.corner(levelBar, UDim.new(0, 8))
	UIHelpers.stroke(levelBar, Sci.Edge, 1.5)
	levelBar.Parent = gui
	local fill = UIHelpers.frame("Fill", UDim2.fromScale(0, 1), UDim2.new(), nil)
	fill.BackgroundColor3 = Sci.Cyan
	fill.BackgroundTransparency = 0.15
	UIHelpers.corner(fill, UDim.new(0, 8))
	fill.Parent = levelBar
	local levelText = UIHelpers.label("Text", "", 13, SCI_FONT)
	levelText.TextColor3 = Sci.Text
	UIHelpers.textStroke(levelText, 1.5)
	levelText.Parent = levelBar

	-- Left: the menu (SHOP, TASKS, WEAPONS) ---------------------------------
	local menu = UIHelpers.frame("Menu", UDim2.fromOffset(214, 3 * 58 + 2 * 12), UDim2.new(0, 16, 0.5, 0), Vector2.new(0, 0.5))
	menu.BackgroundTransparency = 1
	menu.Parent = gui
	local menuLayout = Instance.new("UIListLayout")
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Padding = UDim.new(0, 12)
	menuLayout.Parent = menu
	local menuButtons: { { name: string, text: string, key: string, color: Color3, icon: (GuiObject, Color3, Color3) -> () } } = {
		{ name = "Shop", text = "SHOP", key = "B", color = Sci.Yellow, icon = Icons.shop },
		{ name = "Tasks", text = "TASKS", key = "T", color = Sci.Cyan, icon = Icons.tasks },
		{ name = "Weapons", text = "WEAPONS", key = "G", color = Sci.Purple, icon = Icons.weapons },
	}
	for order, info in menuButtons do
		local button = menuButton(info.name, info.text, info.key, info.color, info.icon)
		button.LayoutOrder = order
		button.Parent = menu
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

	-- Bottom: PLAY and its speech bubble -------------------------------------
	local play, playGlow = sciButton("Play", "PLAY", UDim2.fromOffset(250, 66), Sci.Green, 32, true)
	play.AnchorPoint = Vector2.new(0.5, 1)
	play.Position = UDim2.new(0.5, 0, 1, -26)
	play.Parent = gui
	playGlow.Thickness = 3
	task.spawn(function()
		while play.Parent do
			UIHelpers.tween(playGlow, 0.9, { Transparency = 0.65 }, Enum.EasingStyle.Sine)
			task.wait(0.9)
			UIHelpers.tween(playGlow, 0.9, { Transparency = 0.05 }, Enum.EasingStyle.Sine)
			task.wait(0.9)
		end
	end)
	play.Activated:Connect(function()
		Net.event("QuickPlay"):FireServer()
	end)

	local bubble = UIHelpers.frame("Bubble", UDim2.fromOffset(470, 44), UDim2.new(0.5, 0, 1, -108), Vector2.new(0.5, 1))
	bubble.BackgroundColor3 = Sci.Panel
	bubble.BackgroundTransparency = 0.08
	UIHelpers.corner(bubble, UDim.new(0, 10))
	UIHelpers.stroke(bubble, Sci.Cyan, 1.5).Transparency = 0.25
	bubble.Parent = gui
	local bubbleText = UIHelpers.label("Text", "", 17, BODY_FONT)
	bubbleText.TextColor3 = Sci.Text
	bubbleText.Parent = bubble
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, 0)
	tail.Size = UDim2.fromOffset(16, 16)
	tail.Rotation = 45
	tail.BackgroundColor3 = Sci.Panel
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

	-- G opens the shop's Guns tab while you're in the lobby.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.G and gui.Enabled then
			ShopController.openTab("Weapon")
		end
	end)

	-- The weapons room counter opens the shop's Guns tab.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == WEAPONS_PROMPT then
			ShopController.openTab("Weapon")
		elseif prompt.Name == ROBUX_PROMPT then
			ShopController.openTab("Robux")
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
