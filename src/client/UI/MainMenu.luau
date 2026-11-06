--!strict
--[[
	MainMenu
	========
	The starting screen, in the slime bunker's sci-fi style:
	  * Behind it, the camera drifts slowly through the real bunker lobby,
	    looking at the glowing SLIME SHOWDOWN sign.
	  * On the left, a dark glass panel with neon corner brackets: the
	    title, your lifetime stats (eliminations, wins, coins), a glowing
	    PLAY button and a SHOP button.
	Pressing Play fades the menu out, hands the camera back to the game and
	tells the server (which puts you in the lobby).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIHelpers = require(script.Parent:WaitForChild("UIHelpers"))
local GameContract = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("GameContract"))

local player = Players.LocalPlayer
local Sci = Theme.SciFi
local TITLE_FONT = Theme.SciFiFonts.Title
local BODY_FONT = Theme.SciFiFonts.Body
local ATTR = GameContract.PlayerAttributes
local CAMERA_STEP = "MainMenuCamera"
-- Where the lobby's big sign is (used until the real sign has loaded).
local FALLBACK_SIGN = Vector3.new(0, 325, 665)

local MainMenu = {}

-- A glowing outline (a UIStroke on the frame's border).
local function glow(parent: GuiObject, color: Color3, thickness: number, transparency: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- Neon L-shaped brackets on the panel's corners (a classic sci-fi frame).
local function cornerBrackets(parent: GuiObject, color: Color3)
	local length, width = 34, 4
	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		for _, horizontal in { true, false } do
			local bar = Instance.new("Frame")
			bar.Name = "Bracket"
			bar.AnchorPoint = corner
			bar.Position = UDim2.new(corner.X, if corner.X == 0 then -6 else 6, corner.Y, if corner.Y == 0 then -6 else 6)
			bar.Size = if horizontal then UDim2.fromOffset(length, width) else UDim2.fromOffset(width, length)
			bar.BackgroundColor3 = color
			bar.BorderSizePixel = 0
			bar.Parent = parent
		end
	end
end

local function statCard(parent: Instance, order: number, title: string, color: Color3, attribute: string)
	local card = UIHelpers.frame(title, UDim2.fromOffset(150, 78), UDim2.new(), nil)
	card.LayoutOrder = order
	card.BackgroundColor3 = Sci.PanelLight
	card.BackgroundTransparency = 0.1
	UIHelpers.corner(card, UDim.new(0, 10))
	glow(card, Sci.Edge, 1.5, 0.2)
	card.Parent = parent

	-- A neon strip along the top in the stat's colour.
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.Size = UDim2.new(1, -20, 0, 3)
	strip.Position = UDim2.fromOffset(10, 0)
	strip.BackgroundColor3 = color
	strip.BorderSizePixel = 0
	strip.Parent = card

	local value = UIHelpers.label("Value", "0", 30, TITLE_FONT)
	value.Size = UDim2.new(1, -12, 0, 40)
	value.Position = UDim2.fromOffset(6, 8)
	value.TextColor3 = color
	value.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.Parent = value
	value.Parent = card

	local caption = UIHelpers.label("Caption", string.upper(title), 12, BODY_FONT)
	caption.Size = UDim2.new(1, 0, 0, 18)
	caption.Position = UDim2.fromOffset(0, 52)
	caption.TextColor3 = Sci.Dim
	caption.Parent = card

	local function update()
		value.Text = tostring(UIHelpers.numberAttribute(player, attribute))
	end
	player:GetAttributeChangedSignal(attribute):Connect(update)
	update()
end

local function menuButton(name: string, text: string, size: UDim2, fill: Color3, textColor: Color3, edge: Color3): (TextButton, UIStroke, UIScale)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = TITLE_FONT
	button.TextSize = 30
	button.TextColor3 = textColor
	button.BackgroundColor3 = fill
	button.AutoButtonColor = false
	button.Size = size
	UIHelpers.corner(button, UDim.new(0, 12))
	local stroke = glow(button, edge, 3, 0.15)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		UIHelpers.tween(scale, 0.15, { Scale = 1.05 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		UIHelpers.tween(scale, 0.15, { Scale = 1 })
	end)
	return button, stroke, scale
end

-- The camera drifts slowly through the bunker, looking at the big sign.
local function startMenuCamera()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local startedAt = os.clock()
	local signPosition = FALLBACK_SIGN
	task.spawn(function()
		local lobby = Workspace:WaitForChild("Lobby", 30)
		local sign = lobby and lobby:FindFirstChild("BunkerSign", true)
		if sign and sign:IsA("BasePart") then
			signPosition = sign.Position
		end
	end)
	RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value, function()
		local t = os.clock() - startedAt
		local eye = signPosition + Vector3.new(16 + math.sin(t * 0.15) * 7, -15 + math.sin(t * 0.23) * 1.2, 62)
		local target = signPosition + Vector3.new(-9, -8, 0)
		camera.CFrame = CFrame.lookAt(eye, target)
	end)
end

local function stopMenuCamera()
	RunService:UnbindFromRenderStep(CAMERA_STEP)
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

--[[
	Builds the menu. `onPlay` runs once when the Play button is pressed.
	`onShop` (optional) runs when the Shop button is pressed.
]]
function MainMenu.create(gui: ScreenGui, onPlay: () -> (), onShop: (() -> ())?)
	startMenuCamera()

	-- A dark tint over the bunker: strong on the left (behind the panel), light on the right.
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Sci.Void
	background.BackgroundTransparency = 0
	background.BorderSizePixel = 0
	background.Parent = gui
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.45, 0.45),
		NumberSequenceKeypoint.new(1, 0.82),
	})
	fade.Parent = background

	local panel = UIHelpers.frame("Panel", UDim2.fromOffset(560, 560), UDim2.new(0, 70, 0.5, 0), Vector2.new(0, 0.5))
	panel.BackgroundColor3 = Sci.Panel
	panel.BackgroundTransparency = 0.18
	UIHelpers.corner(panel, UDim.new(0, 18))
	glow(panel, Sci.Cyan, 2, 0.35)
	cornerBrackets(panel, Sci.Cyan)
	panel.Parent = background

	local column = Instance.new("Frame")
	column.Name = "Column"
	column.Size = UDim2.new(1, -60, 1, -60)
	column.Position = UDim2.fromOffset(30, 30)
	column.BackgroundTransparency = 1
	column.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 14)
	layout.Parent = column

	local tag = UIHelpers.label("Tag", "◆  SLIME BUNKER  //  ONLINE", 14, TITLE_FONT)
	tag.LayoutOrder = 1
	tag.Size = UDim2.new(1, 0, 0, 20)
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.TextColor3 = Sci.Cyan
	tag.Parent = column

	local titleTop = UIHelpers.label("TitleSlime", "SLIME", 72, TITLE_FONT)
	titleTop.LayoutOrder = 2
	titleTop.Size = UDim2.new(1, 0, 0, 78)
	titleTop.TextXAlignment = Enum.TextXAlignment.Left
	titleTop.TextColor3 = Sci.Green
	local greenGlow = Instance.new("UIStroke")
	greenGlow.Color = Sci.Green
	greenGlow.Thickness = 2
	greenGlow.Transparency = 0.6
	greenGlow.Parent = titleTop
	titleTop.Parent = column

	local titleBottom = UIHelpers.label("TitleShowdown", "SHOWDOWN", 50, TITLE_FONT)
	titleBottom.LayoutOrder = 3
	titleBottom.Size = UDim2.new(1, 0, 0, 56)
	titleBottom.TextXAlignment = Enum.TextXAlignment.Left
	titleBottom.TextColor3 = Sci.Text
	titleBottom.TextScaled = true
	titleBottom.Parent = column

	local subtitle = UIHelpers.label("Subtitle", "Squishy arena shooter", 18, BODY_FONT)
	subtitle.LayoutOrder = 4
	subtitle.Size = UDim2.new(1, 0, 0, 24)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = Sci.Dim
	subtitle.Parent = column

	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.LayoutOrder = 5
	stats.Size = UDim2.new(1, 0, 0, 80)
	stats.BackgroundTransparency = 1
	stats.Parent = column
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 12)
	statsLayout.Parent = stats
	statCard(stats, 1, "Eliminations", Sci.Red, ATTR.LifetimeEliminations)
	statCard(stats, 2, "Wins", Sci.Cyan, ATTR.Wins)
	statCard(stats, 3, "Coins", Sci.Yellow, ATTR.Coins)

	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.LayoutOrder = 6
	spacer.Size = UDim2.new(1, 0, 0, 6)
	spacer.BackgroundTransparency = 1
	spacer.Parent = column

	local play, playGlow, playScale = menuButton("PlayButton", "PLAY", UDim2.fromOffset(500, 78), Sci.Green, Sci.Void, Sci.Green:Lerp(Color3.new(1, 1, 1), 0.4))
	play.LayoutOrder = 7
	play.TextSize = 40
	-- Modal frees the mouse cursor (first person locks it) while the menu shows.
	play.Modal = true
	play.Parent = column

	-- A soft pulse on the PLAY glow so it invites a click.
	local pulsing = true
	task.spawn(function()
		while pulsing and play.Parent do
			UIHelpers.tween(playGlow, 0.9, { Transparency = 0.65 }, Enum.EasingStyle.Sine)
			task.wait(0.9)
			UIHelpers.tween(playGlow, 0.9, { Transparency = 0.1 }, Enum.EasingStyle.Sine)
			task.wait(0.9)
		end
	end)

	if onShop then
		local shop, _, shopScale = menuButton("ShopButton", "SHOP", UDim2.fromOffset(500, 58), Sci.Panel, Sci.Cyan, Sci.Cyan)
		shop.LayoutOrder = 8
		shop.TextSize = 26
		shop.Parent = column
		shop.Activated:Connect(function()
			shopScale.Scale = 0.94
			UIHelpers.tween(shopScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			onShop()
		end)
	end

	local playRemote = GameContract.getRemote(GameContract.RemoteNames.PlayPressed)
	local pressed = false
	play.Activated:Connect(function()
		if pressed then
			return
		end
		pressed = true
		pulsing = false

		playScale.Scale = 0.94
		UIHelpers.tween(playScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		playRemote:FireServer()

		-- Fade the menu away, then hand over to the game camera and the HUD.
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
			stopMenuCamera()
			gui.Enabled = false
			onPlay()
		end)
	end)
end

return MainMenu
