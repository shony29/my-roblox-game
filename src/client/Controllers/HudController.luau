--!strict
--[[
	HudController
	Builds the on-screen display from code: crosshair, hit marker, health,
	ammo, coins, dash meter, kill feed and big "splat!" messages.

	Building UI in code keeps everything in text files that Rojo can sync.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataController = require(script.Parent.DataController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(30, 30, 45)
local ACCENT = Color3.fromRGB(255, 220, 90)
local DANGER = Color3.fromRGB(255, 90, 110)
local MAX_FEED_ENTRIES = 5

local Hud = {}

-- Small helper: create an instance and set its properties in one go.
local function create(className: string, props: { [string]: any }): any
	local instance: any = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	instance.Parent = props.Parent -- parent last (it's faster)
	return instance
end

local function corner(parent: Instance, radius: number)
	create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0.6
	return create("TextLabel", props)
end

------------------------------------------------------------------------
-- Build the UI
------------------------------------------------------------------------

local gui: ScreenGui = create("ScreenGui", {
	Name = "Hud",
	ResetOnSpawn = false, -- keep the HUD between lives
	IgnoreGuiInset = true,
	Parent = playerGui,
})

-- Crosshair: four small bars around a dot
local crosshair: Frame = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(28, 28),
	BackgroundTransparency = 1,
	Parent = gui,
})
create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(4, 4),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	Parent = crosshair,
})
for _, bar in
	{
		{ UDim2.new(0.5, 0, 0, 0), UDim2.fromOffset(2, 8) },
		{ UDim2.new(0.5, 0, 1, -8), UDim2.fromOffset(2, 8) },
		{ UDim2.new(0, 0, 0.5, 0), UDim2.fromOffset(8, 2) },
		{ UDim2.new(1, -8, 0.5, 0), UDim2.fromOffset(8, 2) },
	}
do
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = bar[1],
		Size = bar[2],
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = crosshair,
	})
end

-- Hit marker (an "X" that flashes when you hit someone)
local hitMarker = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(40, 40),
	Text = "X",
	TextSize = 34,
	TextTransparency = 1,
	TextStrokeTransparency = 1,
	Parent = gui,
})

-- Dash meter under the crosshair
local dashBack: Frame = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 30),
	Size = UDim2.fromOffset(60, 5),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.4,
	BorderSizePixel = 0,
	Parent = gui,
})
corner(dashBack, 3)
local dashFill: Frame = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = ACCENT,
	BorderSizePixel = 0,
	Parent = dashBack,
})
corner(dashFill, 3)

-- Health bar (bottom left)
local healthBack: Frame = create("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 24, 1, -24),
	Size = UDim2.fromOffset(260, 28),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	Parent = gui,
})
corner(healthBack, 8)
local healthFill: Frame = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(120, 230, 120),
	BorderSizePixel = 0,
	Parent = healthBack,
})
corner(healthFill, 8)
local healthText = label({ Size = UDim2.fromScale(1, 1), Text = "100", TextSize = 20, Parent = healthBack })

-- Ammo (bottom right)
local ammoText = label({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -20),
	Size = UDim2.fromOffset(220, 50),
	Text = "24 / 24",
	TextSize = 40,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = gui,
})

-- Coins (top left)
local coinsText = label({
	Position = UDim2.fromOffset(24, 60),
	Size = UDim2.fromOffset(300, 34),
	Text = "Coins: 0",
	TextSize = 28,
	TextColor3 = ACCENT,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = gui,
})
local savingWarning = label({
	Position = UDim2.fromOffset(24, 94),
	Size = UDim2.fromOffset(420, 22),
	Text = "Progress is not being saved (see README: Studio API access)",
	TextSize = 16,
	TextColor3 = DANGER,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
	Parent = gui,
})

-- Controls hint (bottom middle)
label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(600, 20),
	Text = "Click: Shoot   R: Reload   Shift/Q: Dash   Space x2: Double jump   B: Shop",
	TextSize = 16,
	TextTransparency = 0.3,
	Parent = gui,
})

-- Kill feed (top right)
local killFeed: Frame = create("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -24, 0, 60),
	Size = UDim2.fromOffset(340, 200),
	BackgroundTransparency = 1,
	Parent = gui,
})
create("UIListLayout", {
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
	Parent = killFeed,
})

-- Big centre message ("You splatted Bob!")
local bigMessage = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.33),
	Size = UDim2.fromOffset(600, 50),
	Text = "",
	TextSize = 38,
	TextTransparency = 1,
	TextStrokeTransparency = 1,
	Parent = gui,
})

------------------------------------------------------------------------
-- Functions the other controllers call
------------------------------------------------------------------------

local feedOrder = 0
local messageToken = 0

function Hud.setAmmo(ammo: number, magazineSize: number, reloading: boolean)
	if reloading then
		ammoText.Text = "Reloading..."
		ammoText.TextColor3 = ACCENT
	else
		ammoText.Text = `{ammo} / {magazineSize}`
		ammoText.TextColor3 = if ammo == 0 then DANGER else WHITE
	end
end

function Hud.setDashReady(fraction: number)
	dashFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	dashFill.BackgroundColor3 = if fraction >= 1 then ACCENT else WHITE
end

function Hud.setHealth(health: number, maxHealth: number)
	local fraction = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0
	healthFill.Size = UDim2.fromScale(fraction, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(255, 90, 110):Lerp(Color3.fromRGB(120, 230, 120), fraction)
	healthText.Text = tostring(math.ceil(health))
end

function Hud.flashHitMarker(killed: boolean)
	hitMarker.TextColor3 = if killed then DANGER else WHITE
	hitMarker.TextTransparency = 0
	hitMarker.Size = UDim2.fromOffset(52, 52)
	TweenService:Create(hitMarker, TweenInfo.new(0.25), {
		TextTransparency = 1,
		Size = UDim2.fromOffset(40, 40),
	}):Play()
end

function Hud.showMessage(text: string, color: Color3)
	messageToken += 1
	local myToken = messageToken
	bigMessage.Text = text
	bigMessage.TextColor3 = color
	bigMessage.TextTransparency = 0
	bigMessage.TextStrokeTransparency = 0.5
	task.delay(1.4, function()
		if messageToken == myToken then -- a newer message hasn't replaced this one
			TweenService:Create(bigMessage, TweenInfo.new(0.4), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end)
end

function Hud.addKillFeedEntry(killer: Player?, victim: Player)
	feedOrder += 1
	local text = if killer
		then `{killer.DisplayName}  splatted  {victim.DisplayName}`
		else `{victim.DisplayName} got splatted`
	local involvesMe = killer == player or victim == player
	local entry = label({
		Size = UDim2.fromOffset(340, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = `  {text}  `,
		TextSize = 18,
		BackgroundTransparency = 0.35,
		BackgroundColor3 = if involvesMe then Color3.fromRGB(90, 70, 20) else DARK,
		LayoutOrder = -feedOrder, -- newest at the top
		Parent = killFeed,
	})
	corner(entry, 6)

	-- Keep only the newest few entries.
	local entries = {}
	for _, child in killFeed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(entries, child)
		end
	end
	table.sort(entries, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = MAX_FEED_ENTRIES + 1, #entries do
		entries[i]:Destroy()
	end

	task.delay(6, function()
		if entry.Parent then
			entry:Destroy()
		end
	end)
end

local function showData(data: Types.PublicData)
	coinsText.Text = `Coins: {data.Coins}`
	savingWarning.Visible = not data.SavingEnabled
end

function Hud.start()
	DataController.onChanged(showData)

	-- Kill feed + personal "splat" messages
	Remotes.event("KillFeed").OnClientEvent:Connect(function(killer: Player?, victim: Player)
		Hud.addKillFeedEntry(killer, victim)
		if killer == player and victim ~= player then
			Hud.showMessage(`You splatted {victim.DisplayName}!`, ACCENT)
		elseif victim == player and killer then
			Hud.showMessage(`Splatted by {killer.DisplayName}!`, DANGER)
		end
	end)

	-- Health bar follows whichever character we currently have.
	local function onCharacterAdded(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		Hud.setHealth(humanoid.Health, humanoid.MaxHealth)
		humanoid.HealthChanged:Connect(function(health)
			Hud.setHealth(health, humanoid.MaxHealth)
		end)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

return Hud
