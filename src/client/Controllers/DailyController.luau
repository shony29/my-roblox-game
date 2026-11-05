--!strict
--[[
	DailyController: the Daily Squishy screen.

	Walk up to the Daily Squishy machine in the lobby and press E (or tap
	the prompt). Tap the squishy: it swells and wobbles with every tap and,
	on the last tap, bursts into jelly droplets and shows your prize.

	The tapping is only animation. The prize comes from the server
	(DailyClaim), which checks the 24-hour timer and picks the item itself.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))

local Colors = Theme.Colors
local PROMPT_NAME = "DailySquishy" -- the ProximityPrompt on the lobby machine
local TAPS_TO_BURST = 6
local DROPLETS = 18
local SQUISHY_COLOR = Color3.fromRGB(120, 230, 160)
local CATEGORY_TEXT: { [string]: string } = {
	Color = "New blob colour!",
	Hat = "New hat!",
	Skin = "New skin!",
	Weapon = "New gun! It's in your loadout.",
}

local player = Players.LocalPlayer

local DailyController = {}
local started = false
local openScreen: () -> () = function() end

-- Seconds until the next squishy (0 = ready now).
local function secondsUntilReady(): number
	local readyAt = player:GetAttribute(GameContract.PlayerAttributes.DailyReadyAt)
	if typeof(readyAt) ~= "number" then
		return 0
	end
	return math.max(0, readyAt - Workspace:GetServerTimeNow())
end

local function formatWait(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.ceil((seconds % 3600) / 60)
	return if hours > 0 then `{hours}h {minutes}m` else `{minutes}m`
end

function DailyController.open()
	openScreen()
end

function DailyController.start()
	if started then
		return
	end
	started = true

	local gui = UIHelpers.screenGui("DailySquishy", 25, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(gui)
	gui.Enabled = false

	local overlay = Instance.new("TextButton")
	overlay.Name = "Dim"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Modal = true
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Colors.Ink
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	local title = UIHelpers.label("Title", "DAILY SQUISHY", 44, Theme.Fonts.Title)
	title.Size = UDim2.new(1, 0, 0, 56)
	title.Position = UDim2.fromScale(0, 0.12)
	title.TextColor3 = SQUISHY_COLOR
	UIHelpers.textStroke(title, 3)
	title.Parent = gui

	local hint = UIHelpers.label("Hint", "", 22)
	hint.Size = UDim2.new(1, 0, 0, 30)
	hint.Position = UDim2.fromScale(0, 0.12 + 0.09)
	hint.Parent = gui

	-- The squishy: a round jelly with eyes and a smile.
	local squishy = Instance.new("TextButton")
	squishy.Name = "Squishy"
	squishy.Text = ""
	squishy.AutoButtonColor = false
	squishy.AnchorPoint = Vector2.new(0.5, 0.5)
	squishy.Position = UDim2.fromScale(0.5, 0.55)
	squishy.Size = UDim2.fromOffset(230, 200)
	squishy.BackgroundColor3 = SQUISHY_COLOR
	UIHelpers.corner(squishy, UDim.new(0.5, 0))
	UIHelpers.stroke(squishy, Colors.Ink, 4)
	squishy.Parent = gui
	local shine = UIHelpers.frame("Shine", UDim2.fromOffset(60, 34), UDim2.fromScale(0.28, 0.2), Vector2.new(0.5, 0.5))
	shine.BackgroundColor3 = Colors.White
	shine.BackgroundTransparency = 0.45
	UIHelpers.corner(shine, UDim.new(1, 0))
	shine.Parent = squishy
	for _, x in { 0.38, 0.62 } do
		local eye = UIHelpers.frame("Eye", UDim2.fromOffset(22, 32), UDim2.fromScale(x, 0.45), Vector2.new(0.5, 0.5))
		eye.BackgroundColor3 = Colors.Ink
		eye.BackgroundTransparency = 0
		UIHelpers.corner(eye, UDim.new(1, 0))
		eye.Parent = squishy
		local sparkle = UIHelpers.frame("Sparkle", UDim2.fromOffset(8, 8), UDim2.fromScale(0.65, 0.3), Vector2.new(0.5, 0.5))
		sparkle.BackgroundColor3 = Colors.White
		sparkle.BackgroundTransparency = 0
		UIHelpers.corner(sparkle, UDim.new(1, 0))
		sparkle.Parent = eye
	end
	local squishScale = Instance.new("UIScale")
	squishScale.Parent = squishy

	-- The prize card shown after the burst.
	local card = UIHelpers.frame("Prize", UDim2.fromOffset(420, 230), UDim2.fromScale(0.5, 0.55), Vector2.new(0.5, 0.5))
	card.BackgroundTransparency = 0.05
	card.Visible = false
	UIHelpers.corner(card, UDim.new(0, 20))
	UIHelpers.stroke(card, Colors.Yolk, 4)
	card.Parent = gui
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	local prizeTop = UIHelpers.label("Top", "YOU GOT", 20, Theme.Fonts.Title)
	prizeTop.Size = UDim2.new(1, 0, 0, 30)
	prizeTop.Position = UDim2.fromOffset(0, 16)
	prizeTop.TextColor3 = Colors.Sky
	prizeTop.Parent = card
	local prizeName = UIHelpers.label("Name", "", 36, Theme.Fonts.Title)
	prizeName.Size = UDim2.new(1, -20, 0, 50)
	prizeName.Position = UDim2.fromOffset(10, 50)
	prizeName.TextColor3 = Colors.Yolk
	UIHelpers.textStroke(prizeName, 2)
	prizeName.Parent = card
	local prizeKind = UIHelpers.label("Kind", "", 18)
	prizeKind.Size = UDim2.new(1, -20, 0, 26)
	prizeKind.Position = UDim2.fromOffset(10, 104)
	prizeKind.Parent = card
	local awesome = Instance.new("TextButton")
	awesome.Name = "Close"
	awesome.Text = "AWESOME!"
	awesome.Font = Theme.Fonts.Title
	awesome.TextSize = 24
	awesome.TextColor3 = Colors.Ink
	awesome.BackgroundColor3 = Colors.Mint
	awesome.AnchorPoint = Vector2.new(0.5, 1)
	awesome.Position = UDim2.new(0.5, 0, 1, -18)
	awesome.Size = UDim2.fromOffset(200, 50)
	UIHelpers.corner(awesome, UDim.new(0, 14))
	UIHelpers.stroke(awesome, Colors.Ink, 2)
	awesome.Parent = card

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "X"
	closeButton.Text = "X"
	closeButton.Font = Theme.Fonts.Title
	closeButton.TextSize = 26
	closeButton.TextColor3 = Colors.Ink
	closeButton.BackgroundColor3 = Colors.Coral
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -24, 0, 24)
	closeButton.Size = UDim2.fromOffset(48, 48)
	UIHelpers.corner(closeButton, UDim.new(1, 0))
	closeButton.Parent = gui

	local taps = 0
	local busy = false

	local function reset()
		taps = 0
		busy = false
		squishy.Visible = true
		squishy.BackgroundColor3 = SQUISHY_COLOR
		squishScale.Scale = 1
		card.Visible = false
	end

	local function close()
		if busy then
			return -- let the burst finish
		end
		gui.Enabled = false
		reset()
	end

	local function burst()
		squishy.Visible = false
		for i = 1, DROPLETS do
			local angle = (i / DROPLETS) * math.pi * 2
			local size = math.random(14, 30)
			local drop = UIHelpers.frame("Drop", UDim2.fromOffset(size, size), UDim2.fromScale(0.5, 0.55), Vector2.new(0.5, 0.5))
			drop.BackgroundColor3 = SQUISHY_COLOR:Lerp(Colors.Coral, math.random())
			drop.BackgroundTransparency = 0
			UIHelpers.corner(drop, UDim.new(1, 0))
			drop.Parent = gui
			local distance = math.random(140, 260)
			UIHelpers.tween(drop, 0.6, {
				Position = UDim2.new(0.5, math.cos(angle) * distance, 0.55, math.sin(angle) * distance),
				BackgroundTransparency = 1,
			})
			task.delay(0.65, function()
				drop:Destroy()
			end)
		end
	end

	local function showPrize(result: { [string]: any })
		local name = if typeof(result.displayName) == "string" then result.displayName else "A surprise"
		prizeName.Text = string.upper(name)
		prizeKind.Text = if result.kind == "Coins"
			then "You own everything, so here are coins!"
			else (CATEGORY_TEXT[if typeof(result.category) == "string" then result.category else ""] or "New item!")
		card.Visible = true
		cardScale.Scale = 0.6
		UIHelpers.tween(cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	squishy.Activated:Connect(function()
		if busy then
			return
		end
		if secondsUntilReady() > 0 then
			-- Not ready: a little "nope" wiggle.
			squishScale.Scale = 0.94
			UIHelpers.tween(squishScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			return
		end
		taps += 1
		-- Swell and wobble a bit more with every tap.
		local target = 1 + taps * 0.08
		squishScale.Scale = target * 0.88
		UIHelpers.tween(squishScale, 0.3, { Scale = target }, Enum.EasingStyle.Elastic)
		squishy.BackgroundColor3 = SQUISHY_COLOR:Lerp(Colors.Coral, taps / TAPS_TO_BURST)
		if taps < TAPS_TO_BURST then
			return
		end

		busy = true
		local ok, result = pcall(function()
			return Net.func("DailyClaim"):InvokeServer()
		end)
		if ok and typeof(result) == "table" and result.ok == true then
			burst()
			task.wait(0.4)
			showPrize(result)
			busy = false
		else
			busy = false
			reset()
			hint.Text = if ok and typeof(result) == "table" and typeof(result.message) == "string"
				then result.message
				else "Couldn't open it right now. Try again!"
		end
	end)
	awesome.Activated:Connect(close)
	closeButton.Activated:Connect(close)

	openScreen = function()
		reset()
		gui.Enabled = true
	end

	-- The machine in the lobby opens this screen.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == PROMPT_NAME then
			openScreen()
		end
	end)

	-- Keep the hint and the machine's sign up to date.
	task.spawn(function()
		while gui.Parent do
			local waitFor = secondsUntilReady()
			if gui.Enabled and not busy and not card.Visible then
				hint.Text = if waitFor > 0
					then `Next squishy in {formatWait(waitFor)}`
					else "Tap the squishy until it bursts!"
				squishy.BackgroundColor3 = if waitFor > 0
					then Color3.fromRGB(150, 150, 160)
					else SQUISHY_COLOR:Lerp(Colors.Coral, taps / TAPS_TO_BURST)
			end
			local lobby = Workspace:FindFirstChild("Lobby")
			local sign = lobby and lobby:FindFirstChild("DailyStatus", true)
			if sign and sign:IsA("TextLabel") then
				sign.Text = if waitFor > 0 then `NEXT IN {formatWait(waitFor)}` else "READY!"
			end
			task.wait(0.5)
		end
	end)
end

return DailyController
