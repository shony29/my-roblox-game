--!strict
--[[
	LoadingScreen: the first thing you see when you join.

	Rojo puts this LocalScript in ReplicatedFirst, so it runs before the
	rest of the game has even arrived. It replaces Roblox's plain loading
	screen with our own sci-fi one: a bouncing slime, the title, a progress
	bar, what's loading right now, and tips. It stays up until:
	  1. the game has finished arriving on your device (game:IsLoaded()),
	  2. the server has finished starting (it sets "ServerVersion"), and
	  3. every part of your screen has started (the Client script sets the
	     "ClientReady" attribute on you at the end of its start-up),
	then fades away. It never waits longer than MAX_WAIT seconds.

	Everything is built right here (no shared modules yet, they may not
	have arrived), so its colours copy the game's sci-fi theme (UI/Theme).
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local MIN_TIME = 1.8 -- seconds: long enough to read, so it never just flashes
local MAX_WAIT = 30 -- seconds: never keep someone waiting forever

local VOID = Color3.fromRGB(8, 10, 18)
local PANEL = Color3.fromRGB(16, 20, 32)
local INSET = Color3.fromRGB(11, 14, 24)
local GREEN = Color3.fromRGB(120, 255, 90)
local CYAN = Color3.fromRGB(90, 220, 255)
local TEXT = Color3.fromRGB(228, 236, 255)
local DIM = Color3.fromRGB(140, 154, 190)
local SLIME = Color3.fromRGB(110, 230, 150)

local TIPS = {
	"Press Q to dash, and Space twice for a double jump.",
	"Sprint, then press Ctrl or C to slide.",
	"Walk over green AMMO crates to refill your spare ammo.",
	"The Daily Squishy gives you a prize every day.",
	"Step on the FREE FOR ALL pad to jump straight into a game.",
	"Your topping flies out of your gun and bursts out of every slime you knock out.",
	"Open Settings (top right) to see every key and button.",
	"Win matches in a row to grow your win streak.",
}

local player = Players.LocalPlayer
local startedAt = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function make(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for name, value in properties do
		(instance :: any)[name] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function round(parent: Instance, radius: UDim?)
	make("UICorner", { CornerRadius = radius or UDim.new(1, 0) }, parent)
end

-- Background: deep dark with a soft green-to-blue glow.
local background = make("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = VOID,
	BorderSizePixel = 0,
}, gui)
make("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 30, 34)),
		ColorSequenceKeypoint.new(0.6, VOID),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 14, 36)),
	}),
}, background)

-- The bouncing slime.
local slimeHolder = make("Frame", {
	Name = "Slime",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.5, -40),
	Size = UDim2.fromOffset(120, 100),
	BackgroundTransparency = 1,
}, background)
local shadow = make("Frame", {
	Name = "Shadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 1, 6),
	Size = UDim2.fromOffset(100, 16),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
}, slimeHolder)
round(shadow)
local body = make("Frame", {
	Name = "Body",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromOffset(110, 92),
	BackgroundColor3 = SLIME,
	BorderSizePixel = 0,
}, slimeHolder)
round(body, UDim.new(0.48, 0))
make("UIStroke", { Color = GREEN, Thickness = 3, Transparency = 0.2 }, body)
local shine = make("Frame", {
	Name = "Shine",
	Position = UDim2.fromScale(0.18, 0.14),
	Size = UDim2.fromScale(0.3, 0.18),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Rotation = -15,
}, body)
round(shine)
for _, x in { 0.36, 0.64 } do
	local eye = make("Frame", {
		Name = "Eye",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, 0.52),
		Size = UDim2.fromScale(0.1, 0.17),
		BackgroundColor3 = Color3.fromRGB(35, 30, 50),
		BorderSizePixel = 0,
	}, body)
	round(eye)
	local sparkle = make("Frame", {
		Position = UDim2.fromScale(0.5, 0.15),
		Size = UDim2.fromScale(0.4, 0.28),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, eye)
	round(sparkle)
	local cheek = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x + (if x < 0.5 then -0.12 else 0.12), 0.68),
		Size = UDim2.fromScale(0.14, 0.08),
		BackgroundColor3 = Color3.fromRGB(255, 160, 190),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, body)
	round(cheek)
end

-- Title, progress bar, status and a tip.
local title = make("TextLabel", {
	Name = "Title",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, -10),
	Size = UDim2.fromOffset(700, 60),
	BackgroundTransparency = 1,
	Font = Enum.Font.Michroma,
	TextSize = 44,
	TextColor3 = GREEN,
	Text = "SLIME SHOWDOWN",
}, background)
make("UIStroke", { Color = GREEN, Thickness = 1.5, Transparency = 0.6 }, title)

local track = make("Frame", {
	Name = "Track",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 66),
	Size = UDim2.fromOffset(440, 14),
	BackgroundColor3 = INSET,
	BorderSizePixel = 0,
}, background)
round(track)
make("UIStroke", { Color = Color3.fromRGB(60, 72, 104), Thickness = 1.5 }, track)
local fill = make("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, track)
round(fill)
make("UIGradient", { Color = ColorSequence.new(GREEN, CYAN) }, fill)

local status = make("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 90),
	Size = UDim2.fromOffset(600, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.Michroma,
	TextSize = 14,
	TextColor3 = CYAN,
	Text = "LOADING  0%",
}, background)

local tipBox = make("Frame", {
	Name = "Tip",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.fromOffset(640, 44),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
}, background)
round(tipBox, UDim.new(0, 12))
make("UIStroke", { Color = Color3.fromRGB(60, 72, 104), Thickness = 1.5 }, tipBox)
local tip = make("TextLabel", {
	Size = UDim2.new(1, -24, 1, 0),
	Position = UDim2.fromOffset(12, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextWrapped = true,
	TextColor3 = TEXT,
	Text = "TIP: " .. TIPS[math.random(1, #TIPS)],
}, tipBox)

gui.Parent = player:WaitForChild("PlayerGui")

-- What's done so far.
local function serverReady(): boolean
	return ReplicatedStorage:GetAttribute("ServerVersion") ~= nil
end
local function clientReady(): boolean
	return player:GetAttribute("ClientReady") == true
end

local shown = 0 -- the bar's position (eases toward the real progress)
local bounce = 0
local tipIndex = math.random(1, #TIPS)
local nextTipAt = os.clock() + 3.5

local connection: RBXScriptConnection
connection = RunService.RenderStepped:Connect(function(dt: number)
	-- Real progress: arrived -> server ready -> your screen ready.
	local target, message = 0.2, "LOADING THE GAME"
	if game:IsLoaded() then
		target, message = 0.5, "WAITING FOR THE SERVER"
	end
	if game:IsLoaded() and serverReady() then
		target, message = 0.8, "BUILDING THE BUNKER"
	end
	if game:IsLoaded() and serverReady() and clientReady() then
		target, message = 1, "READY"
	end
	-- A little creep inside each stage, so the bar always looks alive.
	local creep = if target < 1 then math.min((os.clock() - startedAt) * 0.01, 0.12) else 0
	shown += (math.min(target + creep, target + 0.12, 1) - shown) * math.min(dt * 4, 1)
	fill.Size = UDim2.fromScale(math.clamp(shown, 0.02, 1), 1)
	status.Text = `{message}  {math.floor(shown * 100 + 0.5)}%`

	-- Squash-and-stretch bounce.
	bounce += dt * 6
	local hop = math.abs(math.sin(bounce))
	local squash = 1 + (1 - hop) * 0.18
	body.Size = UDim2.fromOffset(110 * squash, 92 / squash)
	body.Position = UDim2.new(0.5, 0, 1, -hop * 36)
	shadow.Size = UDim2.fromOffset(100 - hop * 30, 16 - hop * 5)
	shadow.BackgroundTransparency = 0.5 + hop * 0.25

	-- A new tip every few seconds.
	if os.clock() >= nextTipAt then
		nextTipAt = os.clock() + 3.5
		tipIndex = tipIndex % #TIPS + 1
		tip.Text = "TIP: " .. TIPS[tipIndex]
	end
end)

-- Wait until everything is ready (or the time limit), then fade away.
while os.clock() - startedAt < MAX_WAIT do
	if os.clock() - startedAt >= MIN_TIME and game:IsLoaded() and serverReady() and clientReady() and shown > 0.97 then
		break
	end
	task.wait(0.1)
end

local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad)
for _, item in gui:GetDescendants() do
	if item:IsA("Frame") then
		TweenService:Create(item, fade, { BackgroundTransparency = 1 }):Play()
	elseif item:IsA("TextLabel") then
		TweenService:Create(item, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	elseif item:IsA("UIStroke") then
		TweenService:Create(item, fade, { Transparency = 1 }):Play()
	end
end
task.wait(0.65)
connection:Disconnect()
gui:Destroy()
