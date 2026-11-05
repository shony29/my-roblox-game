--!strict
--[[
	MainMenu
	========
	Shown when you join: the game title, your lifetime stats
	(eliminations, wins, coins) and a big bouncy Play button.
	Pressing Play hides the menu, shows the HUD and tells the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIHelpers = require(script.Parent:WaitForChild("UIHelpers"))
local GameContract = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("GameContract"))

local player = Players.LocalPlayer
local Colors = Theme.Colors
local ATTR = GameContract.PlayerAttributes

local MainMenu = {}

local function statChip(parent: Instance, order: number, title: string, color: Color3, attribute: string)
	local chip = UIHelpers.frame(title, UDim2.fromOffset(170, 84), UDim2.new())
	chip.LayoutOrder = order
	chip.BackgroundColor3 = Colors.White
	chip.BackgroundTransparency = 0.1
	UIHelpers.corner(chip, UDim.new(0, 16))
	UIHelpers.stroke(chip, Colors.Ink, 3)
	chip.Parent = parent

	local value = UIHelpers.label("Value", "0", 36, Theme.Fonts.Title)
	value.Size = UDim2.new(1, 0, 0, 48)
	value.Position = UDim2.fromOffset(0, 6)
	value.TextColor3 = color
	UIHelpers.textStroke(value, 2)
	value.Parent = chip

	local caption = UIHelpers.label("Caption", title, 16)
	caption.Size = UDim2.new(1, 0, 0, 22)
	caption.Position = UDim2.fromOffset(0, 54)
	caption.TextColor3 = Colors.Ink
	caption.Parent = chip

	local function update()
		value.Text = tostring(UIHelpers.numberAttribute(player, attribute))
	end
	player:GetAttributeChangedSignal(attribute):Connect(update)
	update()
end

--[[
	Builds the menu. `onPlay` runs once when the Play button is pressed.
]]
function MainMenu.create(gui: ScreenGui, onPlay: () -> ())
	-- Bright sky-to-yolk background covering the whole screen.
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Colors.White
	background.BorderSizePixel = 0
	background.Parent = gui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Colors.Sky, Colors.Yolk)
	gradient.Parent = background

	local column = Instance.new("Frame")
	column.Name = "Column"
	column.AnchorPoint = Vector2.new(0.5, 0.5)
	column.Position = UDim2.fromScale(0.5, 0.5)
	column.Size = UDim2.fromOffset(600, 520)
	column.BackgroundTransparency = 1
	column.Parent = background

	local columnLayout = Instance.new("UIListLayout")
	columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	columnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	columnLayout.Padding = UDim.new(0, 24)
	columnLayout.Parent = column

	local title = UIHelpers.label("Title", Theme.GameTitle, 84, Theme.Fonts.Title)
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 100)
	title.TextColor3 = Colors.Shell
	UIHelpers.textStroke(title, 5)
	title.Parent = column

	-- Lifetime stats
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.LayoutOrder = 2
	stats.Size = UDim2.new(1, 0, 0, 84)
	stats.BackgroundTransparency = 1
	stats.Parent = column

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 16)
	statsLayout.Parent = stats

	statChip(stats, 1, "Eliminations", Colors.Coral, ATTR.LifetimeEliminations)
	statChip(stats, 2, "Wins", Colors.SkyDeep, ATTR.Wins)
	statChip(stats, 3, "Coins", Colors.YolkDark, ATTR.Coins)

	-- The big Play button
	local playHolder = Instance.new("Frame")
	playHolder.Name = "PlayHolder"
	playHolder.LayoutOrder = 3
	playHolder.Size = UDim2.fromOffset(340, 110)
	playHolder.BackgroundTransparency = 1
	playHolder.Parent = column

	local play = Instance.new("TextButton")
	play.Name = "PlayButton"
	play.Text = "PLAY"
	play.Font = Theme.Fonts.Title
	play.TextSize = 56
	play.TextColor3 = Colors.White
	play.BackgroundColor3 = Colors.Mint
	play.AutoButtonColor = false
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.Position = UDim2.fromScale(0.5, 0.5)
	play.Size = UDim2.fromScale(1, 1)
	UIHelpers.corner(play, UDim.new(1, 0))
	UIHelpers.stroke(play, Colors.Ink, 4)
	UIHelpers.textStroke(play, 3)
	play.Parent = playHolder

	-- A UIScale makes it easy to "bounce" the button.
	local bounce = Instance.new("UIScale")
	bounce.Parent = play

	play.MouseEnter:Connect(function()
		UIHelpers.tween(bounce, 0.15, { Scale = 1.06 }, Enum.EasingStyle.Back)
	end)
	play.MouseLeave:Connect(function()
		UIHelpers.tween(bounce, 0.15, { Scale = 1 })
	end)

	-- Gentle idle pulse so the button invites a click.
	local pulsing = true
	task.spawn(function()
		while pulsing and play.Parent do
			UIHelpers.tween(play, 0.8, { BackgroundColor3 = Colors.Mint:Lerp(Colors.White, 0.2) }, Enum.EasingStyle.Sine)
			task.wait(0.8)
			UIHelpers.tween(play, 0.8, { BackgroundColor3 = Colors.Mint }, Enum.EasingStyle.Sine)
			task.wait(0.8)
		end
	end)

	local playRemote = GameContract.getRemote(GameContract.RemoteNames.PlayPressed)
	local pressed = false
	play.Activated:Connect(function()
		if pressed then
			return
		end
		pressed = true
		pulsing = false

		bounce.Scale = 0.92
		UIHelpers.tween(bounce, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		playRemote:FireServer()

		-- Fade the menu away, then hand over to the HUD.
		task.delay(0.15, function()
			UIHelpers.tween(background, 0.35, { BackgroundTransparency = 1 })
			for _, descendant in background:GetDescendants() do
				if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
					UIHelpers.tween(descendant, 0.35, { TextTransparency = 1, BackgroundTransparency = 1 })
				elseif descendant:IsA("Frame") and descendant.BackgroundTransparency < 1 then
					UIHelpers.tween(descendant, 0.35, { BackgroundTransparency = 1 })
				elseif descendant:IsA("UIStroke") then
					UIHelpers.tween(descendant, 0.35, { Transparency = 1 })
				end
			end
			task.wait(0.4)
			gui.Enabled = false
			onPlay()
		end)
	end)
end

return MainMenu
